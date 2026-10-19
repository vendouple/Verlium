"""Studio generators (UI-SPEC §3.5–3.7). Each runs as a background job and fills studio_outputs.

Text outputs (report, flashcards, quiz, mindmap, table) are one structured LLM call grounded in the
selected sources. Audio Overview = LLM script for two hosts → TTS per line → ffmpeg concat to one MP3.
"""
from __future__ import annotations

import asyncio
import logging
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from . import activity, blobs, db, rag
from .providers import ProviderError, RoleConfig, require_role

log = logging.getLogger("verlium.studio")

TYPES = ("audio", "report", "flashcards", "quiz", "mindmap", "table", "slides", "infographic", "video")
TYPE_LABEL = {"audio": "Audio Overview", "report": "Report", "flashcards": "Flashcards", "quiz": "Quiz",
              "mindmap": "Mind Map", "table": "Data Table", "slides": "Slide Deck", "infographic": "Infographic",
              "video": "Video Overview"}


async def _progress(oid: str, pct: int, status: str = "running") -> None:
    job = activity.current_job.get()
    if job is not None:
        job["_progress"] = pct
    await db.execute("UPDATE studio_outputs SET progress=:p, status=:s WHERE id=:id", {"p": pct, "s": status, "id": oid})


async def source_context(nid: str, sids: list[str], focus: str, cfg: RoleConfig, share: float = .7) -> str:
    """Selected sources as numbered excerpts, as much as the chat model's context allows."""
    budget = int(rag.budgets(cfg, 0) * share)
    chunks = await rag.retrieve(nid, focus or "overview of the main ideas", sids, budget)
    if not chunks:
        raise ValueError("No processed sources selected. Add or select sources first.")
    out, current = [], None
    for c in chunks:
        if c.source_id != current:
            out.append(f"\n## Source: {c.source_title}\n")
            current = c.source_id
        out.append(c.text.strip())
    return "\n".join(out)


def _lang(opts: dict) -> str:
    lang = (opts.get("language") or "").strip()
    return f"Write everything in {lang}." if lang and lang.lower() not in ("default", "english") else ""


# ---- text generators ----------------------------------------------------------------

REPORT_TEMPLATES = {
    "briefing": ("Briefing Doc", "Write a briefing document: an executive summary, then the key themes and most "
                                 "important ideas or facts, with short supporting quotes from the sources."),
    "study_guide": ("Study Guide", "Write a study guide: a short-answer quiz (10 questions) with an answer key, "
                                   "5 essay-format questions, and a glossary of key terms with definitions."),
    "blog": ("Blog Post", "Write an insightful, engaging blog post that distils the most surprising and "
                          "counter-intuitive takeaways from the sources, with a catchy title and listicle structure."),
    "faq": ("FAQ", "Write an FAQ: the 10 most important questions a reader would ask, each with a clear answer."),
    "timeline": ("Timeline", "Write a detailed chronological timeline of the main events, then a cast of "
                             "characters with a one-line bio for each person mentioned."),
}


async def gen_report(cfg: RoleConfig, ctx: str, prompt: str, opts: dict) -> tuple[str, Any]:
    tpl = opts.get("template", "briefing")
    name, instr = REPORT_TEMPLATES.get(tpl, ("Report", ""))
    if tpl == "custom" or not instr:
        instr = prompt or "Write a well-structured report on the sources."
    elif prompt:
        instr += f"\nFocus: {prompt}"
    r = await cfg.client().chat(cfg.model_id, [
        {"role": "system", "content": "You write clear, well-structured Markdown documents grounded ONLY in the "
                                      "provided sources. Start with a single '# Title' line."},
        {"role": "user", "content": f"{instr}\n{_lang(opts)}\n\nSOURCES:\n{ctx}"}], temperature=0.4)
    md = r["content"].strip()
    m = re.match(r"#\s+(.+)", md)
    return (m.group(1).strip() if m else name), {"markdown": md, "template": tpl}


COUNTS = {"fewer": 0.5, "standard": 1.0, "more": 1.75}


async def gen_flashcards(cfg: RoleConfig, ctx: str, prompt: str, opts: dict) -> tuple[str, Any]:
    n = round(20 * COUNTS.get(opts.get("count", "standard"), 1))
    data = await cfg.client().chat_json(cfg.model_id, (
        f"Create {n} flashcards from the sources. Difficulty: {opts.get('difficulty', 'medium')}. "
        f"{('Topic: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        'Reply with JSON only: {"title": "short deck title", "cards": [{"front": "question or term", '
        '"back": "concise answer (1-3 sentences)"}]}\n\nSOURCES:\n' + ctx), temperature=0.5)
    cards = [c for c in data.get("cards", []) if c.get("front") and c.get("back")]
    if not cards:
        raise ProviderError("The model returned no flashcards")
    return data.get("title") or "Flashcards", {"cards": cards}


async def gen_quiz(cfg: RoleConfig, ctx: str, prompt: str, opts: dict) -> tuple[str, Any]:
    n = round(10 * COUNTS.get(opts.get("count", "standard"), 1))
    data = await cfg.client().chat_json(cfg.model_id, (
        f"Create a {n}-question multiple-choice quiz from the sources. Difficulty: {opts.get('difficulty', 'medium')}. "
        f"{('Topic: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        "Each question has 4 options, exactly one correct, and a one-sentence rationale for EVERY option "
        "explaining why it is right or wrong. Add a short hint.\n"
        'Reply with JSON only: {"title": "quiz title", "questions": [{"question": "...", "hint": "...", '
        '"options": [{"text": "...", "correct": true, "rationale": "..."}]}]}\n\nSOURCES:\n' + ctx), temperature=0.5)
    qs = [q for q in data.get("questions", []) if len(q.get("options", [])) >= 2
          and sum(bool(o.get("correct")) for o in q["options"]) == 1]
    if not qs:
        raise ProviderError("The model returned no valid quiz questions")
    return data.get("title") or "Quiz", {"questions": qs}


async def gen_mindmap(cfg: RoleConfig, ctx: str, prompt: str, opts: dict) -> tuple[str, Any]:
    data = await cfg.client().chat_json(cfg.model_id, (
        "Build a mind map of the sources: one root topic, 4-7 main branches, each with 2-6 sub-topics, "
        "optionally one more level. Labels are short noun phrases (max 6 words). "
        f"{('Centre it on: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        'Reply with JSON only: {"label": "root", "children": [{"label": "...", "children": [...]}]}\n\nSOURCES:\n'
        + ctx), temperature=0.3)
    root = data.get("root", data)
    if not root.get("label"):
        raise ProviderError("The model returned no mind map")
    return root["label"], {"root": root}


async def gen_table(cfg: RoleConfig, ctx: str, prompt: str, opts: dict) -> tuple[str, Any]:
    data = await cfg.client().chat_json(cfg.model_id, (
        f"Extract a data table from the sources. {prompt or 'Choose the most useful structured comparison.'} "
        f"{_lang(opts)}\nKeep cells short. "
        'Reply with JSON only: {"title": "...", "columns": ["..."], "rows": [["cell", "..."]]}\n\nSOURCES:\n' + ctx),
        temperature=0.2)
    cols, rows = data.get("columns") or [], data.get("rows") or []
    if not cols or not rows:
        raise ProviderError("The model returned an empty table")
    rows = [[str(c) if c is not None else "" for c in (r + [""] * len(cols))[:len(cols)]] for r in rows]
    return data.get("title") or "Data table", {"columns": [str(c) for c in cols], "rows": rows}


# ---- audio overview --------------------------------------------------------------------

AUDIO_FORMATS = {
    "deep_dive": "A lively conversation between two hosts unpacking and connecting the topics in the sources.",
    "brief": "A bite-sized overview that helps the listener quickly grasp the core ideas.",
    "critique": "An expert review of the sources that offers constructive feedback to help improve the material.",
    "debate": "A thoughtful debate between the two hosts that illuminates different perspectives on the sources.",
}
AUDIO_WORDS = {"short": 700, "default": 1400, "long": 2600}


def _ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if not exe:
        raise RuntimeError("ffmpeg is not installed on the server")
    return exe


def _probe_seconds(path: Path) -> float:
    out = subprocess.run([_ffmpeg(), "-hide_banner", "-i", str(path)], capture_output=True, text=True).stderr
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", out)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0


async def gen_audio(oid: str, cfg: RoleConfig, ctx: str, prompt: str, opts: dict) -> tuple[str, Any, bytes]:
    tts = await require_role("tts")
    fmt = opts.get("format", "deep_dive")
    words = 350 if fmt == "brief" else AUDIO_WORDS.get(opts.get("length", "default"), 1400)
    voice_a = tts.params.get("voice_a") or "onyx"
    voice_b = tts.params.get("voice_b") or "nova"

    data = await cfg.client().chat_json(cfg.model_id, (
        f"Write a podcast script. Format: {AUDIO_FORMATS.get(fmt, AUDIO_FORMATS['deep_dive'])}\n"
        "Two hosts: A (male) and B (female). Natural, warm, curious; short turns; reactions like 'Right.' and "
        "'Exactly.'; explain jargon; open with a hook, close with a takeaway. Do not read citations aloud. "
        "Never mention being AI. Do not name the hosts.\n"
        f"Length: about {words} words. {('Focus on: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        'Reply with JSON only: {"title": "episode title", "lines": [{"speaker": "A", "text": "..."}]}\n\n'
        f"SOURCES:\n{ctx}"), temperature=0.8, max_tokens=8000)
    lines = [ln for ln in data.get("lines", []) if (ln.get("text") or "").strip()]
    if not lines:
        raise ProviderError("The model returned an empty script")
    await _progress(oid, 25)

    client = tts.client()
    sem = asyncio.Semaphore(4)
    done = 0

    async def speak(i: int, ln: dict) -> bytes:
        nonlocal done
        voice = voice_b if str(ln.get("speaker", "A")).upper().startswith("B") else voice_a
        async with sem:
            for attempt in range(3):
                try:
                    audio = await client.speech(tts.model_id, ln["text"].strip(), voice, "mp3")
                    break
                except ProviderError:
                    if attempt == 2:
                        raise
                    await asyncio.sleep(2 * (attempt + 1))
        done += 1
        if done % 4 == 0:
            await _progress(oid, 25 + int(65 * done / len(lines)))
        return audio

    clips = await asyncio.gather(*(speak(i, ln) for i, ln in enumerate(lines)))

    with tempfile.TemporaryDirectory(prefix="verlium-audio-") as tmp:
        tmpd = Path(tmp)
        files, transcript, t = [], [], 0.0
        for i, (ln, audio) in enumerate(zip(lines, clips)):
            f = tmpd / f"{i:04d}.mp3"
            f.write_bytes(audio)
            files.append(f)
            dur = _probe_seconds(f)
            transcript.append({"speaker": ln.get("speaker", "A"), "text": ln["text"], "start": round(t, 2)})
            t += dur + 0.25
        silence = tmpd / "gap.mp3"
        lst = tmpd / "list.txt"
        out = tmpd / "out.mp3"

        def render():
            subprocess.run([_ffmpeg(), "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", "0.25",
                            "-c:a", "libmp3lame", str(silence)], check=True, capture_output=True)
            lst.write_text("".join(f"file '{f.as_posix()}'\nfile '{silence.as_posix()}'\n" for f in files),
                           encoding="utf-8")
            subprocess.run([_ffmpeg(), "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-ar", "24000",
                            "-ac", "1", "-c:a", "libmp3lame", "-b:a", "96k", str(out)], check=True, capture_output=True)
            return out.read_bytes(), _probe_seconds(out)

        mp3, total = await asyncio.to_thread(render)
    content = {"transcript": transcript, "format": fmt, "voices": [voice_a, voice_b], "duration": round(total, 1)}
    return data.get("title") or "Audio Overview", content, mp3


# ---- job entry point -------------------------------------------------------------------

async def run_output(oid: str) -> dict:
    row = await db.fetch_one("SELECT * FROM studio_outputs WHERE id=:id AND deleted=0", {"id": oid})
    if not row:
        return {}
    await _progress(oid, 5)
    cfg = await require_role("chat")
    activity.report(f"Gathering context from {len(row['source_ids'] or []) or 'all'} source(s) for {TYPE_LABEL.get(row['type'], row['type'])}")
    sids = row["source_ids"] or []
    opts, prompt = row["options"] or {}, row["prompt"] or ""
    ctx = await source_context(row["notebook_id"], sids, prompt, cfg)
    await _progress(oid, 15)
    activity.report(f"Context ready ({len(ctx):,} chars) · generating with {cfg.model_id}", "debug")

    kind = row["type"]
    blob_key = mime = None
    duration = None
    if kind == "audio":
        title, content, mp3 = await gen_audio(oid, cfg, ctx, prompt, opts)
        blob_key, _ = blobs.put(mp3, "mp3")
        mime, duration = "audio/mpeg", content["duration"]
    elif kind in ("slides", "infographic", "video"):
        from . import studio_visual as sv

        async def progress(p: int) -> None:
            await _progress(oid, p)

        gen_v = {"slides": sv.gen_slides, "infographic": sv.gen_infographic, "video": sv.gen_video}[kind]
        title, content, data, mime = await gen_v(cfg, ctx, prompt, opts, progress)
        ext = {"application/pdf": "pdf", "image/png": "png", "video/mp4": "mp4"}[mime]
        activity.report(f"Rendered {ext.upper()} · {len(data) / 1e6:.1f} MB", "debug")
        blob_key, _ = blobs.put(data, ext)
        duration = content.get("duration")
    else:
        gen = {"report": gen_report, "flashcards": gen_flashcards, "quiz": gen_quiz,
               "mindmap": gen_mindmap, "table": gen_table}.get(kind)
        if not gen:
            raise ValueError(f"{kind} is not available yet")
        title, content = await gen(cfg, ctx, prompt, opts)

    await db.execute(
        "UPDATE studio_outputs SET status='ready', progress=100, title=:t, content=:c, blob_key=:b, mime=:m, "
        "duration_s=:d, error=NULL, unread=1 WHERE id=:id",
        {"id": oid, "t": (title or TYPE_LABEL[kind])[:1000], "c": content, "b": blob_key, "m": mime, "d": duration})
    return {"output_id": oid}


async def output_failed(job: dict, err: Exception) -> None:
    await db.execute("UPDATE studio_outputs SET status='error', error=:e WHERE id=:id",
                     {"id": job["ref_id"], "e": str(err)[:3900]})
