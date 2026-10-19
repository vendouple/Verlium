"""Images and videos attached to chat messages.

Uploads are stored as blobs with a downscaled copy for models and a thumbnail for the app. At ask time
they become model input: images inline (data URIs) when the chat model can see, otherwise a description
from the Vision model; videos become a handful of frames plus an audio transcript (when STT is set).
"""
from __future__ import annotations

import asyncio
import base64
import io
import logging
import tempfile
import time
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

from . import blobs, db, media
from .providers import ConfigError, ProviderError, RoleConfig, get_role

log = logging.getLogger("verlium.attachments")

MAX_IMAGE = 25 * 1024 * 1024
MAX_VIDEO = 300 * 1024 * 1024
MODEL_PX = 1568   # long side sent to models (enough detail, bounded tokens)
THUMB_PX = 480
VIDEO_EXT = {".mp4": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm", ".mkv": "video/x-matroska",
             ".m4v": "video/mp4", ".avi": "video/x-msvideo"}
IMAGE_EXT = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
             ".gif": "image/gif", ".bmp": "image/bmp"}
COLS = "id, notebook_id, kind, mime, name, size_bytes, width, height, duration_s"


def classify(filename: str, mime: str | None) -> tuple[str, str] | None:
    ext = Path(filename or "").suffix.lower()
    mime = (mime or "").lower()
    if mime.startswith("image/") or ext in IMAGE_EXT:
        return "image", IMAGE_EXT.get(ext, mime if mime.startswith("image/") else "image/png")
    if mime.startswith("video/") or ext in VIDEO_EXT:
        return "video", VIDEO_EXT.get(ext, mime if mime.startswith("video/") else "video/mp4")
    return None


def _jpeg(img: Image.Image, px: int, quality: int = 85) -> bytes:
    img = img.copy()
    img.thumbnail((px, px))
    if img.mode not in ("RGB", "L"):  # flatten transparency onto white, like most viewers show it
        bg = Image.new("RGB", img.size, "white")
        bg.paste(img, mask=img.convert("RGBA").split()[-1])
        img = bg
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=quality, optimize=True)
    return buf.getvalue()


def _process_image(data: bytes) -> dict[str, Any]:
    img = Image.open(io.BytesIO(data))
    img.seek(0)  # first frame of GIFs
    img = ImageOps.exif_transpose(img)
    return {"width": img.width, "height": img.height,
            "model": _jpeg(img, MODEL_PX), "thumb": _jpeg(img, THUMB_PX, 80)}


def _process_video(path: Path) -> dict[str, Any]:
    dur = media.probe_seconds(path)
    poster = path.with_suffix(".poster.jpg")
    media.run(["-ss", f"{min(1.0, dur / 2):.2f}", "-i", str(path), "-frames:v", "1",
               "-vf", f"scale='min({THUMB_PX},iw)':-2", str(poster)])
    img = Image.open(poster)
    return {"duration": dur, "thumb": poster.read_bytes(), "width": img.width, "height": img.height}


async def save_upload(nid: str, data: bytes, filename: str, mime: str | None) -> dict[str, Any]:
    kind_mime = classify(filename, mime)
    if not kind_mime:
        raise ValueError("Only images and videos can be attached")
    kind, mime = kind_mime
    if len(data) > (MAX_IMAGE if kind == "image" else MAX_VIDEO):
        raise ValueError(f"{kind.title()} is too large (max {(MAX_IMAGE if kind == 'image' else MAX_VIDEO) // 2**20} MB)")
    ext = Path(filename).suffix.lstrip(".").lower() or mime.split("/")[-1]
    key, _ = blobs.put(data, ext)
    row: dict[str, Any] = {"id": db.new_id(), "nb": nid, "knd": kind, "mime": mime, "fname": (filename or kind)[:500],
                           "sz": len(data), "bkey": key, "mkey": None, "tkey": None, "w": None, "h": None, "dur": None}
    try:
        if kind == "image":
            info = await asyncio.to_thread(_process_image, data)
            row["mkey"] = blobs.put(info["model"], "jpg")[0]
        else:
            info = await asyncio.to_thread(_process_video, blobs.path_for(key))
            row["dur"] = round(info["duration"], 2)
        row |= {"tkey": blobs.put(info["thumb"], "jpg")[0], "w": info["width"], "h": info["height"]}
    except Exception as e:
        raise ValueError(f"Couldn't read this {kind}: {e}") from e
    await db.execute(
        "INSERT INTO chat_attachments (id, notebook_id, kind, mime, name, size_bytes, blob_key, model_key, thumb_key, "
        "width, height, duration_s) VALUES (:id, :nb, :knd, :mime, :fname, :sz, :bkey, :mkey, :tkey, :w, :h, :dur)", row)
    return await get(row["id"])


async def get(aid: str) -> dict[str, Any]:
    row = await db.fetch_one(f"SELECT {COLS} FROM chat_attachments WHERE id=:id AND deleted=0", {"id": aid})
    if not row:
        raise LookupError("Attachment not found")
    return row


async def load(nid: str, ids: list[str]) -> list[dict[str, Any]]:
    out = []
    for aid in ids[:10]:
        row = await db.fetch_one("SELECT * FROM chat_attachments WHERE id=:id AND notebook_id=:nb AND deleted=0",
                                 {"id": aid, "nb": nid})
        if row:
            out.append(row)
    return out


def public(a: dict[str, Any]) -> dict[str, Any]:
    """What the app stores on the message and renders."""
    return {k: a.get(k) for k in ("id", "kind", "mime", "name", "width", "height", "duration_s")}


# ---- model input -------------------------------------------------------------------------------------------

_caps: dict[tuple[str, str], tuple[float, bool | None]] = {}


async def sees_images(cfg: RoleConfig) -> bool | None:
    """True/False from the provider's model list (input_modalities), None if it doesn't say. Cached 1 h."""
    key = (cfg.provider.id, cfg.model_id)
    hit = _caps.get(key)
    if hit and time.time() - hit[0] < 3600:
        return hit[1]
    val: bool | None = None
    try:
        for m in await cfg.client().list_models():
            if m["id"] == cfg.model_id:
                mods = [x.lower() for x in m.get("input_modalities") or []]
                val = ("image" in mods) if mods else None
                break
    except Exception:
        log.warning("could not read model capabilities", exc_info=True)
    _caps[key] = (time.time(), val)
    return val


def _data_uri(jpeg: bytes) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()


def _video_frames(path: Path, duration: float, n: int) -> list[bytes]:
    times = [duration * (i + 0.5) / n for i in range(n)] if duration > 0 else [0.0]
    frames = []
    with tempfile.TemporaryDirectory() as d:
        for i, t in enumerate(times):
            out = Path(d) / f"f{i}.jpg"
            try:
                media.run(["-ss", f"{t:.2f}", "-i", str(path), "-frames:v", "1", "-vf", "scale='min(768,iw)':-2",
                           "-q:v", "4", str(out)])
                frames.append(out.read_bytes())
            except RuntimeError:
                pass
    return frames


def _video_audio(path: Path) -> bytes | None:
    with tempfile.TemporaryDirectory() as d:
        out = Path(d) / "a.mp3"
        try:
            media.run(["-i", str(path), "-vn", "-ac", "1", "-ar", "16000", "-b:a", "48k", "-t", "1800", str(out)])
        except RuntimeError:  # no audio stream
            return None
        return out.read_bytes() if out.exists() and out.stat().st_size > 2000 else None


async def build_input(chat_cfg: RoleConfig, atts: list[dict[str, Any]],
                      force_describe: bool = False) -> tuple[list[str], str, list[dict]]:
    """Returns (image data URIs for the chat model, extra text for the prompt, steps for the UI)."""
    images: list[tuple[str, str]] = []   # (label, data uri)
    notes: list[str] = []
    steps: list[dict] = []
    for a in atts:
        if a["kind"] == "image":
            images.append((f"Image “{a['name']}”", _data_uri(blobs.get(a["model_key"]))))
            continue
        dur = float(a["duration_s"] or 0)
        n = max(3, min(10, int(dur // 6) + 1))
        frames = await asyncio.to_thread(_video_frames, blobs.path_for(a["blob_key"]), dur, n)
        for i, f in enumerate(frames):
            images.append((f"Video “{a['name']}” frame {i + 1}/{len(frames)} at "
                           f"{dur * (i + 0.5) / max(1, len(frames)):.0f}s", _data_uri(f)))
        transcript = ""
        stt = await get_role("stt")
        if stt:
            audio = await asyncio.to_thread(_video_audio, blobs.path_for(a["blob_key"]))
            if audio:
                try:
                    transcript = await stt.client().transcribe(stt.model_id, audio, "audio.mp3",
                                                               stt.params.get("language") or None)
                except ProviderError as e:
                    log.warning("video transcription failed: %s", e)
        notes.append(f"Video “{a['name']}” ({dur:.0f}s): {len(frames)} frames attached in order."
                     + (f"\nAudio transcript:\n{transcript.strip()[:20000]}" if transcript.strip() else
                        ("" if stt else "\n(No speech-to-text model set, so the audio wasn't transcribed.)")))
        steps.append({"type": "video", "label": "Watched video",
                      "detail": f"{a['name']} · {len(frames)} frames"
                                + (f" · transcript {len(transcript):,} chars" if transcript else "")})

    if not images:
        return [], "\n\n".join(notes), steps

    n_img = sum(1 for a in atts if a["kind"] == "image")
    if n_img:
        steps.insert(0, {"type": "image", "label": "Looked at your image" + ("s" if n_img > 1 else ""),
                         "detail": ", ".join(a["name"] for a in atts if a["kind"] == "image")})

    if not force_describe and await sees_images(chat_cfg) is not False:
        labels = "\n".join(f"- Attachment {i + 1}: {lbl}" for i, (lbl, _) in enumerate(images))
        return [u for _, u in images], "\n\n".join([f"ATTACHED VISUALS (in order):\n{labels}", *notes]), steps

    # The chat model is text-only: let the Vision model look and pass its description along.
    vision = await get_role("vision", fallback_to_chat=False)
    if not vision or vision.model_id == chat_cfg.model_id:
        raise ConfigError(f"{chat_cfg.model_id} can't read images. Set a Vision model in Settings → Models "
                          "(or pick a chat model that accepts images).")
    content: list[dict] = [{"type": "text", "text":
                            "Describe these attachments thoroughly for someone who can't see them: all visible text "
                            "(verbatim), numbers, equations (as LaTeX), diagrams, charts, people/objects, layout. "
                            "For video frames, describe what changes between frames. Label each attachment."}]
    for lbl, uri in images:
        content += [{"type": "text", "text": lbl}, {"type": "image_url", "image_url": {"url": uri}}]
    r = await vision.client().chat(vision.model_id, [{"role": "user", "content": content}],
                                   max_tokens=vision.params.get("max_tokens") or 4000)
    desc = r["content"].strip()
    for a in atts:
        await db.execute("UPDATE chat_attachments SET description=:d WHERE id=:id", {"id": a["id"], "d": desc})
    steps.append({"type": "vision", "label": "Described with vision model", "detail": vision.model_id})
    return [], "\n\n".join([f"ATTACHMENTS (described by a vision model, {vision.model_id}):\n{desc}", *notes]), steps
