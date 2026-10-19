from __future__ import annotations

import json
import time

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel

from .. import attachments, blobs, db, memory, rag, worker
from ..providers import ProviderError, require_role
from .notebooks import get_or_404

router = APIRouter(tags=["chat"])

MSG_COLS = "id, notebook_id, thread_id, role, content, citations, thinking, steps, attachments, created_at"
THREAD_COLS = "id, notebook_id, title, summary, created_at, updated_at"


class HistoryItem(BaseModel):
    role: str
    content: str


class AskIn(BaseModel):
    id: str | None = None                 # client id for the user message
    question: str
    thread_id: str | None = None          # None = start a new thread (ignored when incognito)
    incognito: bool = False               # nothing is stored; the client sends its own history
    history: list[HistoryItem] = []       # incognito only
    source_ids: list[str] | None = None   # default: the notebook's selected sources
    reasoning_effort: str | None = None   # none | low | medium | high (models that support it)
    attachment_ids: list[str] = []        # images / videos uploaded via POST /notebooks/{nid}/attachments


class ThreadPatch(BaseModel):
    title: str


def sse(event: str, data) -> str:
    return f"event: {event}\ndata: {json.dumps(data, default=str)}\n\n"


# ---- threads ----------------------------------------------------------------------

async def _adopt_orphans(nid: str) -> None:
    """Messages from before threads existed are moved into one 'Earlier chat' thread."""
    if await db.fetch_one("SELECT 1 x FROM chat_messages WHERE notebook_id=:nb AND thread_id IS NULL AND deleted=0 "
                          "FETCH FIRST 1 ROWS ONLY", {"nb": nid}):
        tid = db.new_id()
        await db.execute("INSERT INTO chat_threads (id, notebook_id, title) VALUES (:id, :nb, 'Earlier chat')",
                         {"id": tid, "nb": nid})
        await db.execute("UPDATE chat_messages SET thread_id=:t WHERE notebook_id=:nb AND thread_id IS NULL",
                         {"t": tid, "nb": nid})


@router.get("/notebooks/{nid}/threads")
async def list_threads(nid: str):
    await _adopt_orphans(nid)
    return await db.fetch_all(
        f"SELECT {', '.join('t.' + c.strip() for c in THREAD_COLS.split(','))}, "
        "(SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id AND m.deleted = 0) message_count "
        "FROM chat_threads t WHERE t.notebook_id=:nb AND t.deleted=0 ORDER BY t.updated_at DESC", {"nb": nid})


async def _summarize_previous(nid: str, except_id: str | None = None) -> None:
    """When a new chat starts, recap the most recent finished thread in the background."""
    prev = await db.fetch_one(
        "SELECT t.id FROM chat_threads t WHERE t.notebook_id=:nb AND t.deleted=0 AND t.summary IS NULL "
        "AND t.id <> NVL(:ex, '-') AND EXISTS (SELECT 1 FROM chat_messages m WHERE m.thread_id=t.id AND m.role='assistant') "
        "ORDER BY t.updated_at DESC FETCH FIRST 1 ROWS ONLY", {"nb": nid, "ex": except_id})
    if prev:
        await worker.enqueue("summarize_thread", nid, prev["id"])


@router.post("/notebooks/{nid}/threads")
async def create_thread(nid: str):
    await get_or_404(nid)
    tid = db.new_id()
    await db.execute("INSERT INTO chat_threads (id, notebook_id) VALUES (:id, :nb)", {"id": tid, "nb": nid})
    await _summarize_previous(nid, tid)
    return await db.fetch_one(f"SELECT {THREAD_COLS}, 0 message_count FROM chat_threads WHERE id=:id", {"id": tid})


@router.patch("/threads/{tid}")
async def rename_thread(tid: str, body: ThreadPatch):
    await db.execute("UPDATE chat_threads SET title=:t WHERE id=:id", {"t": body.title[:500], "id": tid})
    return {"ok": True}


@router.delete("/threads/{tid}")
async def delete_thread(tid: str):
    await db.execute("UPDATE chat_messages SET deleted=1 WHERE thread_id=:id", {"id": tid})
    await db.execute("UPDATE chat_threads SET deleted=1 WHERE id=:id", {"id": tid})
    return {"ok": True}


@router.get("/threads/{tid}/messages")
async def thread_messages(tid: str):
    return await db.fetch_all(f"SELECT {MSG_COLS} FROM chat_messages WHERE thread_id=:id AND deleted=0 "
                              "ORDER BY created_at", {"id": tid})


@router.delete("/notebooks/{nid}/chat")
async def clear_history(nid: str):
    await db.execute("UPDATE chat_messages SET deleted=1 WHERE notebook_id=:id", {"id": nid})
    await db.execute("UPDATE chat_threads SET deleted=1 WHERE notebook_id=:id", {"id": nid})
    return {"ok": True}


# ---- ask --------------------------------------------------------------------------

@router.post("/notebooks/{nid}/chat")
async def ask(nid: str, body: AskIn):
    """SSE stream: start → step* → (thinking | delta)* → done (final renumbered message) | error."""
    nb = await get_or_404(nid)
    if not body.question.strip() and not body.attachment_ids:
        raise HTTPException(400, "Question is empty")
    atts = await attachments.load(nid, body.attachment_ids)
    question = body.question.strip() or ("What's in this video?" if atts and atts[0]["kind"] == "video"
                                         else "What's in this image?")
    try:
        cfg = await require_role("chat")
    except ProviderError as e:
        raise HTTPException(400, str(e))

    if body.source_ids is None:
        sids = [r["id"] for r in await db.fetch_all(
            "SELECT id FROM sources WHERE notebook_id=:id AND deleted=0 AND selected=1 AND status='ready'", {"id": nid})]
    else:
        sids = body.source_ids

    thread_id = None
    if body.incognito:
        hist = [h.model_dump() for h in body.history[-12:]]
    else:
        thread_id = body.thread_id
        if not thread_id or not await db.fetch_one("SELECT id FROM chat_threads WHERE id=:id AND deleted=0",
                                                   {"id": thread_id}):
            thread_id = thread_id or db.new_id()
            await db.execute("INSERT INTO chat_threads (id, notebook_id, title) VALUES (:id, :nb, :t)",
                             {"id": thread_id, "nb": nid, "t": question[:80]})
            await _summarize_previous(nid, thread_id)
        else:
            await db.execute("UPDATE chat_threads SET title = CASE WHEN title='New chat' THEN :t ELSE title END "
                             "WHERE id=:id", {"id": thread_id, "t": question[:80]})
        hist = await db.fetch_all(
            "SELECT role, content, attachments FROM (SELECT role, content, attachments, created_at FROM chat_messages "
            "WHERE thread_id=:id AND deleted=0 ORDER BY created_at DESC FETCH FIRST 12 ROWS ONLY) ORDER BY created_at",
            {"id": thread_id})
        for h in hist:
            if h.get("attachments"):
                names = ", ".join(a.get("name") or a.get("kind") for a in h["attachments"])
                h["content"] = f"[Attached: {names}]\n{h['content'] or ''}"

    personal, n_mem, recap = ("", 0, False) if body.incognito else await memory.context_block(nid, thread_id)
    hist_chars = sum(len(h["content"] or "") for h in hist) + len(personal)
    t0 = time.perf_counter()
    chunks = await rag.retrieve(nid, question, sids, rag.budgets(cfg, hist_chars))
    search_ms = round((time.perf_counter() - t0) * 1000)

    n_src = len({c.source_id for c in chunks})
    steps = [{"type": "search", "label": "Searched your sources",
              "detail": f"Read {len(chunks)} passage{'s' if len(chunks) != 1 else ''} from {n_src} "
                        f"source{'s' if n_src != 1 else ''} ({search_ms} ms)"}]
    if n_mem or recap:
        steps.append({"type": "memory", "label": "Personalised",
                      "detail": ", ".join(filter(None, [f"{n_mem} memories" if n_mem else "",
                                                       "recap of your last chat" if recap else ""]))})

    user_id = body.id or db.new_id()
    if not body.incognito:
        await db.execute("INSERT INTO chat_messages (id, notebook_id, thread_id, role, content, attachments) "
                         "VALUES (:id, :nb, :t, 'user', :c, :a)",
                         {"id": user_id, "nb": nid, "t": thread_id, "c": body.question,
                          "a": [attachments.public(a) for a in atts] or None})

    effort = body.reasoning_effort or cfg.params.get("reasoning_effort")

    async def stream():
        yield sse("start", {"user_message_id": user_id, "thread_id": thread_id, "incognito": body.incognito})
        for s in steps:
            yield sse("step", s)
        text_parts: list[str] = []
        think_parts: list[str] = []
        images: list[str] = []
        att_text = ""
        try:
            if atts:
                images, att_text, att_steps = await attachments.build_input(cfg, atts)
                for st in att_steps:
                    steps.append(st)
                    yield sse("step", st)
        except Exception as e:
            yield sse("error", {"message": (str(e) or type(e).__name__)[:500]})
            return
        for attempt in (0, 1):
            messages = rag.build_messages(cfg, nb["chat_config"], hist, question, chunks, personal,
                                          images=images, attachment_text=att_text)
            try:
                async for kind, chunk in cfg.client().chat_stream(
                        cfg.model_id, messages, temperature=cfg.params.get("temperature"),
                        max_tokens=cfg.params.get("max_tokens"), reasoning_effort=effort):
                    if kind == "thinking":
                        think_parts.append(chunk)
                        yield sse("thinking", {"text": chunk})
                    else:
                        text_parts.append(chunk)
                        yield sse("delta", {"text": chunk})
                break
            except Exception as e:  # provider/network error mid-stream
                # A text-only model rejecting the images: let the Vision model describe them, then ask again.
                if attempt == 0 and images and not text_parts and isinstance(e, ProviderError) and e.status == 400:
                    try:
                        images, att_text, att_steps = await attachments.build_input(cfg, atts, force_describe=True)
                    except Exception as e2:
                        yield sse("error", {"message": (str(e2) or type(e2).__name__)[:500]})
                        return
                    for st in att_steps[-1:]:
                        steps.append(st)
                        yield sse("step", st)
                    continue
                yield sse("error", {"message": (str(e) or type(e).__name__)[:500]})
                return
        text, cites = rag.finalize_citations("".join(text_parts).strip(), chunks)
        thinking = "".join(think_parts).strip() or None
        mid = db.new_id()
        if not body.incognito:
            await db.execute(
                "INSERT INTO chat_messages (id, notebook_id, thread_id, role, content, citations, thinking, steps) "
                "VALUES (:id, :nb, :t, 'assistant', :c, :cit, :th, :st)",
                {"id": mid, "nb": nid, "t": thread_id, "c": text, "cit": cites, "th": thinking, "st": steps})
            await db.execute("UPDATE chat_threads SET summary = NULL WHERE id=:id", {"id": thread_id})
        yield sse("done", {"id": mid, "thread_id": thread_id, "content": text, "citations": cites,
                           "thinking": thinking, "steps": steps})

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@router.get("/notebooks/{nid}/suggestions")
async def suggestions(nid: str):
    """Three suggested questions shown under the notebook summary."""
    nb = await get_or_404(nid)
    if not nb["summary"]:
        return []
    cfg = await require_role("chat")
    try:
        data = await cfg.client().chat_json(cfg.model_id, (
            "Suggest 3 short, specific questions a curious reader would ask about these sources. "
            'Reply with JSON only: {"questions": ["...", "...", "..."]}\n\n' + nb["summary"]), temperature=0.7)
    except (ProviderError, ValueError):
        return []
    return (data.get("questions") if isinstance(data, dict) else data or [])[:3]


# ---- attachments ------------------------------------------------------------------

@router.post("/notebooks/{nid}/attachments")
async def upload_attachment(nid: str, file: UploadFile):
    await get_or_404(nid)
    data = await file.read()
    try:
        return await attachments.save_upload(nid, data, file.filename or "upload", file.content_type)
    except ValueError as e:
        raise HTTPException(400, str(e))


async def _attachment(aid: str) -> dict:
    row = await db.fetch_one("SELECT * FROM chat_attachments WHERE id=:id AND deleted=0", {"id": aid})
    if not row:
        raise HTTPException(404, "Attachment not found")
    return row


@router.get("/attachments/{aid}/media")
async def attachment_media(aid: str):
    """Original file, with Range support for video seeking. Players pass ?token=."""
    a = await _attachment(aid)
    return FileResponse(blobs.path_for(a["blob_key"]), media_type=a["mime"], filename=a["name"],
                        content_disposition_type="inline")


@router.get("/attachments/{aid}/thumb")
async def attachment_thumb(aid: str):
    a = await _attachment(aid)
    return FileResponse(blobs.path_for(a["thumb_key"] or a["blob_key"]), media_type="image/jpeg")
