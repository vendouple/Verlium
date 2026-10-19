"""Visual Studio outputs: Slide Deck, Infographic, Video Overview (Short 9:16, Explainer 16:9, Cinematic).

Slides and video frames are rendered with Pillow over AI illustrations (crisp text); "AI-rendered"
slides and infographics ask the image model to draw the whole thing. Video = TTS narration +
frames (or generated clips for Cinematic) assembled with ffmpeg.
"""
from __future__ import annotations

import asyncio
import logging
import tempfile
from pathlib import Path
from typing import Any, Awaitable, Callable

from . import blobs, media
from .providers import ProviderError, RoleConfig, get_role, require_role

log = logging.getLogger("verlium.studio")
Progress = Callable[[int], Awaitable[None]]

ART_STYLE = ("clean modern editorial illustration, soft lighting, cohesive muted palette, "
             "no text, no letters, no words, no watermark")


def _lang(opts: dict) -> str:
    lang = (opts.get("language") or "").strip()
    return f"Write all text in {lang}." if lang and lang.lower() not in ("default", "english") else ""


async def _images(prompts: list[str | None], size: str, progress: Progress | None = None,
                  lo: int = 30, hi: int = 70) -> list[bytes | None]:
    """Generate one image per prompt (None → no image). Failures degrade to no image, not a failed job."""
    cfg = await get_role("image", fallback_to_chat=False)
    if not cfg:
        return [None] * len(prompts)
    client, sem, done = cfg.client(), asyncio.Semaphore(3), 0

    async def one(p: str | None) -> bytes | None:
        nonlocal done
        if not p:
            return None
        async with sem:
            try:
                return await client.image(cfg.model_id, p, size)
            except ProviderError as e:
                log.warning("image failed: %s", e)
                return None
            finally:
                done += 1
                if progress and len(prompts):
                    await progress(lo + int((hi - lo) * done / len(prompts)))

    return list(await asyncio.gather(*(one(p) for p in prompts)))


async def _speak_all(texts: list[str], voice: str | None = None, progress: Progress | None = None,
                     lo: int = 30, hi: int = 70) -> list[bytes]:
    tts = await require_role("tts")
    client, sem, done = tts.client(), asyncio.Semaphore(4), 0
    voice = voice or tts.params.get("voice_a") or "onyx"

    async def one(t: str) -> bytes:
        nonlocal done
        async with sem:
            for attempt in range(3):
                try:
                    audio = await client.speech(tts.model_id, t, voice, "mp3")
                    break
                except ProviderError:
                    if attempt == 2:
                        raise
                    await asyncio.sleep(2 * (attempt + 1))
        done += 1
        if progress:
            await progress(lo + int((hi - lo) * done / len(texts)))
        return audio

    return list(await asyncio.gather(*(one(t) for t in texts)))


# ---- slide deck ---------------------------------------------------------------------------

async def gen_slides(cfg: RoleConfig, ctx: str, prompt: str, opts: dict, progress: Progress
                     ) -> tuple[str, dict, bytes, str]:
    presenter = opts.get("format") == "presenter"
    n = 6 if opts.get("length") == "short" else 11
    data = await cfg.client().chat_json(cfg.model_id, (
        f"Create a {n}-slide deck from the sources. "
        + ("Presenter slides: very little text on each slide (a headline and at most 3 short phrases), "
           "with full talking points in the speaker notes. " if presenter else
           "Detailed deck: each slide stands alone when read, with 3-5 informative bullets (max 18 words each). ")
        + "Slide 1 is the title slide (bullets = one subtitle line). The last slide is a summary/takeaways slide. "
        f"{('Focus: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        'Reply with JSON only: {"title": "deck title", "slides": [{"title": "...", "bullets": ["..."], '
        '"notes": "speaker notes", "visual": "one-sentence description of an illustration for this slide"}]}'
        f"\n\nSOURCES:\n{ctx}"), temperature=0.5, max_tokens=8000)
    slides = [s for s in data.get("slides", []) if s.get("title")]
    if not slides:
        raise ProviderError("The model returned no slides")
    deck = data.get("title") or slides[0]["title"]
    theme = opts.get("theme", "dark")
    await progress(25)

    ai = opts.get("render") == "ai"
    if ai:  # the image model draws the whole slide, text included (closest to Gemini Notebook's look)
        prompts = [
            f"A polished 16:9 presentation slide. Title: \"{s['title']}\". "
            + (f"Bullet points: {'; '.join(s.get('bullets') or [])}. " if s.get("bullets") else "")
            + f"Visual: {s.get('visual', '')}. Modern professional design, {theme} theme, legible typography, "
              "consistent style across the deck." for s in slides]
        arts = await _images(prompts, "1376x768", progress, 25, 85)
    else:
        arts = await _images([f"{s.get('visual') or s['title']}. {ART_STYLE}" for s in slides], "896x1024",
                             progress, 25, 85)

    pngs: list[bytes] = []
    for i, (s, art) in enumerate(zip(slides, arts), start=1):
        if ai and art:
            pngs.append(media.to_png(media.cover(media.open_image(art), (1920, 1080))))
        else:
            pngs.append(media.render_slide(s["title"], [str(b) for b in s.get("bullets") or []], art, index=i,
                                           total=len(slides), deck_title=deck, theme=theme, cover_slide=i == 1))
    await progress(92)
    out = []
    for s, png in zip(slides, pngs):
        key, _ = blobs.put(png, "png")
        out.append({"title": s["title"], "bullets": s.get("bullets") or [], "notes": s.get("notes") or "",
                    "image": key})
    pdf = media.pdf_from_pngs(pngs)
    return deck, {"slides": out, "theme": theme, "render": "ai" if ai else "designed"}, pdf, "application/pdf"


# ---- infographic -----------------------------------------------------------------------------

INFO_SIZES = {"landscape": "1536x864", "portrait": "864x1536", "square": "1152x1152"}


async def gen_infographic(cfg: RoleConfig, ctx: str, prompt: str, opts: dict, progress: Progress
                          ) -> tuple[str, dict, bytes, str]:
    img_cfg = await require_role("image")
    detail = opts.get("detail", "standard")
    style = opts.get("style", "auto")
    data = await cfg.client().chat_json(cfg.model_id, (
        "Design an infographic that summarises the sources. Write the image-generation prompt for it: describe the "
        "layout (header, 3-6 labelled sections, icons, a key statistic or two, short captions), the exact short text "
        "to render (title max 8 words, labels max 5 words), the colour palette and the visual style. "
        f"Detail level: {detail}. Style: {style if style != 'auto' else 'choose what suits the content'}. "
        f"{('Focus: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        'Reply with JSON only: {"title": "...", "prompt": "the full image prompt"}\n\nSOURCES:\n' + ctx),
        temperature=0.6)
    if not data.get("prompt"):
        raise ProviderError("The model returned no infographic design")
    await progress(35)
    size = INFO_SIZES.get(opts.get("orientation", "landscape"), INFO_SIZES["landscape"])
    png = await img_cfg.client().image(img_cfg.model_id, data["prompt"] + " High-resolution infographic, legible text.",
                                       size)
    await progress(90)
    return data.get("title") or "Infographic", {"prompt": data["prompt"], "orientation": opts.get("orientation")}, \
        png, "image/png"


# ---- video overview ---------------------------------------------------------------------------

async def gen_video(cfg: RoleConfig, ctx: str, prompt: str, opts: dict, progress: Progress
                    ) -> tuple[str, dict, bytes, str]:
    fmt = opts.get("format", "explainer")
    if fmt == "cinematic":
        return await _cinematic(cfg, ctx, prompt, opts, progress)
    short = fmt == "short"
    if short:
        spec = ("A 60-90 second vertical TikTok/Reels-style video: a scroll-stopping hook in the first line, "
                "8-10 fast scenes, punchy conversational narration (12-20 words per scene), one surprising fact, "
                "and a memorable closing line.")
        fields = '{"narration": "...", "visual": "vivid vertical scene description"}'
    else:
        spec = ("A 2-3 minute explainer video like a polished YouTube tutorial: 7-9 scenes that build understanding "
                "step by step; each scene has an on-screen title, 2-4 short on-screen bullet points and 35-55 words of "
                "clear, friendly narration.")
        fields = '{"title": "on-screen title", "bullets": ["..."], "narration": "...", "visual": "illustration description"}'
    data = await cfg.client().chat_json(cfg.model_id, (
        f"Write the script for {spec} Base it only on the sources. Do not read citations aloud. "
        f"{('Focus: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        f'Reply with JSON only: {{"title": "video title", "scenes": [{fields}]}}\n\nSOURCES:\n{ctx}'),
        temperature=0.7, max_tokens=6000)
    scenes = [s for s in data.get("scenes", []) if (s.get("narration") or "").strip()]
    if not scenes:
        raise ProviderError("The model returned an empty video script")
    title = data.get("title") or "Video Overview"
    await progress(20)

    size_str = "768x1344" if short else "1344x768"
    arts, audio = await asyncio.gather(
        _images([f"{s.get('visual') or s.get('title') or title}. {ART_STYLE}" for s in scenes], size_str),
        _speak_all([s["narration"].strip() for s in scenes], progress=progress, lo=20, hi=70))
    await progress(75)

    def build() -> tuple[bytes, list[float], float]:
        with tempfile.TemporaryDirectory(prefix="verlium-video-") as tmp:
            d = Path(tmp)
            clips = []
            for i, a in enumerate(audio):
                p = d / f"n{i:03d}.mp3"
                p.write_bytes(a)
                clips.append(p)
            narration = d / "narration.mp3"
            starts = media.concat_audio(clips, narration, gap=0.25)
            frames: list[tuple[Path, float]] = []
            for i, (s, art, clip) in enumerate(zip(scenes, arts, clips)):
                dur = media.probe_seconds(clip) + 0.25
                if short:
                    chunks = media.caption_chunks(s["narration"], 5)
                    total_chars = sum(len(c) for c in chunks) or 1
                    for j, chunk in enumerate(chunks):
                        f = d / f"f{i:03d}_{j:02d}.png"
                        f.write_bytes(media.render_vertical_frame(art, chunk))
                        frames.append((f, dur * len(chunk) / total_chars))
                else:
                    f = d / f"f{i:03d}.png"
                    f.write_bytes(media.render_scene_frame(s.get("title") or title,
                                                           [str(b) for b in s.get("bullets") or []], art))
                    frames.append((f, dur))
            out = d / "video.mp4"
            media.slideshow(frames, narration, out, (720, 1280) if short else (1280, 720))
            return out.read_bytes(), starts, media.probe_seconds(out)

    mp4, starts, total = await asyncio.to_thread(build)
    content = {"format": fmt, "aspect": "9:16" if short else "16:9", "duration": round(total, 1),
               "transcript": [{"text": s["narration"], "start": st, "title": s.get("title")}
                              for s, st in zip(scenes, starts)]}
    return title, content, mp4, "video/mp4"


async def _cinematic(cfg: RoleConfig, ctx: str, prompt: str, opts: dict, progress: Progress
                     ) -> tuple[str, dict, bytes, str]:
    vid = await require_role("video")
    duration = int(vid.params.get("duration") or 6)
    data = await cfg.client().chat_json(cfg.model_id, (
        "Plan a short cinematic video (3-4 shots) that captures the essence of the sources. For each shot write a "
        "rich visual prompt for a text-to-video model (camera move, subject, lighting, mood; no on-screen text) and "
        f"one line of narration (max 20 words) that fits a {duration}-second shot. "
        f"{('Focus: ' + prompt) if prompt else ''} {_lang(opts)}\n"
        'Reply with JSON only: {"title": "...", "shots": [{"prompt": "...", "narration": "..."}]}\n\nSOURCES:\n' + ctx),
        temperature=0.8)
    shots = [s for s in data.get("shots", []) if s.get("prompt")][:4]
    if not shots:
        raise ProviderError("The model returned no shots")
    await progress(15)
    client = vid.client()
    sem = asyncio.Semaphore(2)

    async def clip(s: dict) -> bytes:
        async with sem:
            return await client.video(vid.model_id, s["prompt"], duration=duration, aspect="16:9")

    clips_b, audio = await asyncio.gather(asyncio.gather(*(clip(s) for s in shots)),
                                          _speak_all([s.get("narration") or "" for s in shots if s.get("narration")]))
    await progress(85)

    def build() -> tuple[bytes, float]:
        with tempfile.TemporaryDirectory(prefix="verlium-cine-") as tmp:
            d = Path(tmp)
            clips = []
            for i, b in enumerate(clips_b):
                p = d / f"c{i}.mp4"
                p.write_bytes(b)
                clips.append(p)
            narration = None
            if audio:
                parts = []
                for i, a in enumerate(audio):
                    p = d / f"n{i}.mp3"
                    p.write_bytes(a)
                    parts.append(p)
                narration = d / "narration.mp3"
                media.concat_audio(parts, narration, gap=0.6)
            out = d / "cinematic.mp4"
            media.join_clips_with_narration(clips, narration, out, (1280, 720))
            return out.read_bytes(), media.probe_seconds(out)

    mp4, total = await asyncio.to_thread(build)
    content: dict[str, Any] = {"format": "cinematic", "aspect": "16:9", "duration": round(total, 1),
                               "transcript": [{"text": s.get("narration", ""), "start": None} for s in shots]}
    return data.get("title") or "Cinematic overview", content, mp4, "video/mp4"
