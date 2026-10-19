"""Turn a source (file bytes, URL, YouTube link, pasted text) into plain text with page offsets."""
from __future__ import annotations

import re
from dataclasses import dataclass, field

import httpx


@dataclass
class Extracted:
    text: str
    title: str | None = None
    # (char_offset, page_number) markers, ascending; used to tag chunks with a page
    pages: list[tuple[int, int]] = field(default_factory=list)


def from_pdf(data: bytes) -> Extracted:
    import pymupdf

    parts, pages, offset = [], [], 0
    with pymupdf.open(stream=data, filetype="pdf") as doc:
        title = (doc.metadata or {}).get("title") or None
        for i, page in enumerate(doc, start=1):
            t = page.get_text("text").strip()
            pages.append((offset, i))
            parts.append(t)
            offset += len(t) + 2
    return Extracted("\n\n".join(parts), title, pages)


def from_text(data: bytes) -> Extracted:
    for enc in ("utf-8-sig", "utf-16", "cp1252"):
        try:
            return Extracted(data.decode(enc))
        except UnicodeDecodeError:
            continue
    return Extracted(data.decode("utf-8", errors="replace"))


YOUTUBE_RE = re.compile(r"(?:youtube\.com/(?:watch\?v=|shorts/|live/|embed/)|youtu\.be/)([\w-]{11})")


def youtube_id(url: str) -> str | None:
    m = YOUTUBE_RE.search(url)
    return m.group(1) if m else None


async def from_youtube(url: str) -> Extracted:
    from youtube_transcript_api import YouTubeTranscriptApi

    vid = youtube_id(url)
    if not vid:
        raise ValueError("Not a YouTube URL")
    import asyncio

    def fetch():
        api = YouTubeTranscriptApi()
        return api.fetch(vid, languages=["en", "en-US", "en-GB"]) if hasattr(api, "fetch") else \
            YouTubeTranscriptApi.get_transcript(vid)

    try:
        transcript = await asyncio.to_thread(fetch)
    except Exception as e:
        # TODO(phase 4): fall back to yt-dlp audio + STT when captions are missing
        raise ValueError(f"No captions available for this video ({type(e).__name__})") from e
    snippets = [getattr(s, "text", None) or s["text"] for s in transcript]
    title = None
    try:
        async with httpx.AsyncClient(timeout=15) as c:
            r = await c.get("https://www.youtube.com/oembed", params={"url": url, "format": "json"})
            if r.is_success:
                title = r.json().get("title")
    except httpx.HTTPError:
        pass
    return Extracted(" ".join(s.replace("\n", " ") for s in snippets), title)


async def from_url(url: str) -> Extracted:
    import trafilatura

    async with httpx.AsyncClient(timeout=30, follow_redirects=True,
                                 headers={"User-Agent": "Mozilla/5.0 (Verlium source importer)"}) as c:
        r = await c.get(url)
        r.raise_for_status()
    ctype = r.headers.get("content-type", "")
    if "pdf" in ctype:
        return from_pdf(r.content)
    if ctype.startswith("text/plain"):
        return from_text(r.content)
    html = r.text
    text = trafilatura.extract(html, include_comments=False, include_tables=True, favor_recall=True) or ""
    meta = trafilatura.extract_metadata(html)
    if not text.strip():
        raise ValueError("Could not extract readable text from this page")
    return Extracted(text, meta.title if meta else None)
