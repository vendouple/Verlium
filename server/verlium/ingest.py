"""Source ingestion: extract → chunk → embed → index → source guide."""
from __future__ import annotations

import array
import asyncio
import json
import logging
import re

from . import blobs, db, extract
from .activity import report
from .config import get_settings
from .providers import ProviderError, get_role

log = logging.getLogger("verlium.ingest")


def chunk_text(text: str, size: int, overlap: int) -> list[tuple[int, int]]:
    """Return (start, end) character spans; prefers to break at paragraph, then sentence, then space."""
    spans, n, start = [], len(text), 0
    while start < n:
        end = min(start + size, n)
        if end < n:
            floor = start + int(size * 0.6)
            for sep in ("\n\n", "\n", ". ", " "):
                cut = text.rfind(sep, floor, end)
                if cut != -1:
                    end = cut + len(sep)
                    break
        if text[start:end].strip():
            spans.append((start, end))
        if end >= n:
            break
        nxt = max(end - overlap, start + 1)
        sp = text.find(" ", nxt, end)
        start = sp + 1 if sp != -1 else nxt
    return spans


def page_at(pages: list[tuple[int, int]], offset: int) -> int | None:
    page = None
    for off, num in pages:
        if off > offset:
            break
        page = num
    return page


async def _extract(src: dict) -> extract.Extracted:
    kind = src["kind"]
    if kind in ("paste",):
        return extract.Extracted(src["content"] or "")
    if kind == "youtube":
        return await extract.from_youtube(src["url"])
    if kind == "url":
        return await extract.from_url(src["url"])
    data = blobs.get(src["blob_key"])
    if kind == "pdf":
        return extract.from_pdf(data)
    if kind in ("text", "markdown"):
        return extract.from_text(data)
    raise ValueError(f"Unsupported source type: {kind}")


async def _source_guide(text: str, title_hint: str | None) -> dict:
    cfg = await get_role("chat")
    if not cfg:
        return {}
    budget = int((cfg.params.get("context_window") or 32000) * 3)  # ~chars, leave headroom
    excerpt = text[: min(budget, 120_000)]
    prompt = (
        "You are generating a source guide for a research notebook. Read the source and reply with JSON only:\n"
        '{"title": "short descriptive title (max 80 chars)", "summary": "2-4 sentence summary with the key '
        'ideas in **bold**", "key_topics": ["3-6 short topic phrases"]}\n\n'
        f"Existing title (may be a filename): {title_hint or 'none'}\n\nSOURCE:\n{excerpt}"
    )
    try:
        data = await cfg.client().chat_json(cfg.model_id, prompt, temperature=0.2)
    except ProviderError as e:
        # The guide is a nice-to-have: keep the source usable for chat even if it fails.
        log.warning("source guide failed: %s", e)
        report(f"Source guide skipped: {e}", "warn")
        return {}
    return data if isinstance(data, dict) else {}


async def ingest_source(source_id: str) -> None:
    s = get_settings()
    src = await db.fetch_one("SELECT * FROM sources WHERE id = :id", {"id": source_id})
    if not src or src["deleted"]:
        return
    await db.execute("UPDATE sources SET status='processing', error=NULL WHERE id=:id", {"id": source_id})

    report(f"Extracting text ({src['kind']})", progress=5)
    ex = await _extract(src)
    text = ex.text.strip()
    if not text:
        raise ValueError("The source contained no readable text")
    spans = chunk_text(text, s.chunk_chars, s.chunk_overlap)
    report(f"Extracted {len(text):,} chars · {len(ex.pages) or 1} page(s) → {len(spans)} chunks", progress=15)

    emb_cfg = await get_role("embeddings")
    vectors: list[list[float] | None] = [None] * len(spans)
    if emb_cfg:
        client = emb_cfg.client()
        starts = list(range(0, len(spans), s.embed_batch))
        n_batches, done = len(starts), 0
        gate = asyncio.Semaphore(3)  # a few batches in flight: big PDFs take minutes, not half an hour

        async def run(i: int) -> None:
            nonlocal done
            batch = [text[a:b] for a, b in spans[i:i + s.embed_batch]]
            async with gate:
                vectors[i:i + len(batch)] = await client.embed(emb_cfg.model_id, batch,
                                                               emb_cfg.params.get("dimensions"))
            done += 1
            if done == 1 or done % 5 == 0 or done == n_batches:
                report(f"Embedded {done}/{n_batches} batches with {emb_cfg.model_id}", "debug",
                       progress=15 + 50 * done / n_batches)

        await asyncio.gather(*(run(i) for i in starts))
    else:
        report("No embeddings model set — keyword search only", "warn")
    embed_model = emb_cfg.model_id if emb_cfg else None

    await db.execute("DELETE FROM chunks WHERE source_id = :id", {"id": source_id})
    rows = [{
        "id": db.new_id(), "sid": source_id, "nb": src["notebook_id"], "seq": i,
        "text": text[a:b], "cs": a, "ce": b, "page": page_at(ex.pages, a), "em": embed_model,
        "emb": array.array("f", v) if v is not None else None,
    } for i, ((a, b), v) in enumerate(zip(spans, vectors))]
    sql = ("INSERT INTO chunks (id, source_id, notebook_id, seq, text, char_start, char_end, page, embed_model, embedding) "
           "VALUES (:id, :sid, :nb, :seq, :text, :cs, :ce, :page, :em, :emb)")
    report(f"Indexing {len(rows)} chunks", progress=68)
    for i in range(0, len(rows), 200):
        await db.execute_many(sql, rows[i:i + 200])

    report("Writing source guide", progress=75)
    guide = await _source_guide(text, src["title"] or ex.title)
    title = src["title"] if src["kind"] == "paste" and src["title"] else (ex.title or guide.get("title") or src["title"])
    await db.execute(
        "UPDATE sources SET content=:content, char_count=:n, title=:title, summary=:summary, "
        "key_topics=:topics, embed_model=:em WHERE id=:id",
        {"id": source_id, "content": text, "n": len(text), "title": (title or "Untitled source")[:1000],
         "summary": guide.get("summary"), "topics": guide.get("key_topics") or [], "em": embed_model})
    # Update the notebook title/summary before flipping to 'ready', so clients that refresh on 'ready' see it.
    report("Updating notebook summary", progress=90)
    try:
        await refresh_notebook_summary(src["notebook_id"], include=source_id)
    except Exception as e:
        log.exception("notebook summary failed")
        report(f"Notebook summary skipped: {e}", "warn")
    await db.execute("UPDATE sources SET status='ready' WHERE id=:id", {"id": source_id})


async def refresh_notebook_summary(notebook_id: str, include: str | None = None) -> None:
    """Auto title + emoji + summary, like Gemini Notebook does once sources are added."""
    cfg = await get_role("chat")
    if not cfg:
        return
    nb = await db.fetch_one("SELECT title, emoji FROM notebooks WHERE id=:id", {"id": notebook_id})
    srcs = await db.fetch_all(
        "SELECT title, summary FROM sources WHERE notebook_id=:id AND deleted=0 "
        "AND (status='ready' OR id=NVL(:inc, '-')) ORDER BY created_at", {"id": notebook_id, "inc": include})
    if not nb or not srcs:
        return
    listing = "\n".join(f"- {s['title']}: {s['summary'] or ''}" for s in srcs)[:20000]
    prompt = (
        "These are the sources in a research notebook. Reply with JSON only: "
        '{"title": "concise notebook title (max 60 chars)", "emoji": "one emoji", '
        '"summary": "one paragraph overview of what the sources cover together, key terms in **bold**"}\n\n' + listing)
    data = await cfg.client().chat_json(cfg.model_id, prompt, temperature=0.3)
    if not isinstance(data, dict):
        return
    keep_title = nb["title"] not in ("Untitled notebook", "", None)
    await db.execute("UPDATE notebooks SET title=:t, emoji=:e, summary=:s WHERE id=:id", {
        "id": notebook_id,
        "t": nb["title"] if keep_title else (data.get("title") or nb["title"])[:500],
        "e": nb["emoji"] or (data.get("emoji") or "📓")[:16],
        "s": data.get("summary"),
    })
