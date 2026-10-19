"""Rendering helpers for Studio visuals: slides, video frames with captions, ffmpeg assembly.

Text is drawn with Pillow (crisp, correct spelling, any language Inter covers) on top of
AI-generated illustrations, so output quality does not depend on the image model rendering text.
"""
from __future__ import annotations

import io
import re
import shutil
import subprocess
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = Path(__file__).parent / "assets" / "fonts" / "Inter.ttf"

# Deck themes: background gradient (top, bottom), title colour, body colour, accent.
THEMES = {
    "dark": ((15, 17, 32), (32, 24, 64), (245, 245, 250), (205, 208, 225), (118, 160, 255)),
    "light": ((250, 249, 249), (232, 236, 250), (20, 22, 30), (60, 64, 80), (66, 89, 255)),
}


@lru_cache(maxsize=64)
def font(size: int, weight: int = 400) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_axes([min(max(size // 2, 14), 32), weight])
    except Exception:  # static fallback font
        pass
    return f


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    for para in text.split("\n"):
        cur = ""
        for word in para.split():
            trial = f"{cur} {word}".strip()
            if draw.textlength(trial, font=f) <= width or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines


def gradient(size: tuple[int, int], top, bottom) -> Image.Image:
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        col.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return col.resize(size)


def cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scale and centre-crop to fill `size`."""
    w, h = size
    s = max(w / img.width, h / img.height)
    img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def to_png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG", optimize=True)
    return buf.getvalue()


def open_image(data: bytes | None) -> Image.Image | None:
    if not data:
        return None
    try:
        return Image.open(io.BytesIO(data)).convert("RGB")
    except Exception:
        return None


def render_slide(title: str, bullets: list[str], art: bytes | None, *, index: int, total: int,
                 deck_title: str = "", theme: str = "dark", size=(1920, 1080), cover_slide: bool = False) -> bytes:
    top, bottom, c_title, c_body, accent = THEMES.get(theme, THEMES["dark"])
    W, H = size
    img = gradient(size, top, bottom)
    d = ImageDraw.Draw(img)
    pic = open_image(art)
    margin = 96

    if cover_slide:
        if pic:
            bg = cover(pic, size).filter(ImageFilter.GaussianBlur(2))
            img = Image.blend(bg, Image.new("RGB", size, top), 0.55)
            d = ImageDraw.Draw(img)
        f = font(96, 700)
        lines = wrap(d, title, f, W - 2 * margin)[:3]
        y = H // 2 - len(lines) * 112 // 2 - 40
        for ln in lines:
            d.text((margin, y), ln, font=f, fill=c_title)
            y += 112
        if bullets:
            d.text((margin, y + 24), bullets[0][:140], font=font(40, 400), fill=c_body)
        d.rectangle((margin, y - len(lines) * 112 - 36, margin + 140, y - len(lines) * 112 - 28), fill=accent)
        return to_png(img)

    text_w = W - 2 * margin
    if pic:  # illustration on the right 42%
        art_w = int(W * 0.42)
        art_img = rounded(cover(pic, (art_w - margin, H - 2 * margin)), 36)
        img.paste(art_img, (W - art_w, margin), art_img)
        text_w = W - art_w - margin - 64
    d = ImageDraw.Draw(img)
    d.rectangle((margin, margin, margin + 96, margin + 8), fill=accent)
    tf = font(64, 700)
    y = margin + 40
    for ln in wrap(d, title, tf, text_w)[:3]:
        d.text((margin, y), ln, font=tf, fill=c_title)
        y += 78
    y += 28
    bf = font(36 if len(bullets) <= 5 else 30, 400)
    lh = int(bf.size * 1.45)
    for b in bullets[:7]:
        if y > H - margin - lh:
            break
        d.ellipse((margin, y + lh // 2 - 14, margin + 12, y + lh // 2 - 2), fill=accent)
        for ln in wrap(d, b, bf, text_w - 40)[:3]:
            d.text((margin + 36, y), ln, font=bf, fill=c_body)
            y += lh
        y += 14
    foot = font(24, 400)
    d.text((margin, H - 64), deck_title[:90], font=foot, fill=c_body)
    d.text((W - margin, H - 64), f"{index} / {total}", font=foot, fill=c_body, anchor="ra")
    return to_png(img)


def render_vertical_frame(art: bytes | None, caption: str, *, size=(720, 1280), accent=(255, 214, 10)) -> bytes:
    """9:16 frame: full-bleed art, dark gradient at the bottom, big centred caption (TikTok style)."""
    W, H = size
    pic = open_image(art)
    img = cover(pic, size) if pic else gradient(size, (25, 20, 60), (90, 30, 110))
    top = int(H * 0.45)
    grad = Image.linear_gradient("L").resize((W, H - top)).point(lambda v: int(min(255, v * 2.2) * 0.88))
    lower = img.crop((0, top, W, H))
    img.paste(Image.composite(Image.new("RGB", lower.size, (0, 0, 0)), lower, grad), (0, top))
    d = ImageDraw.Draw(img)
    f = font(58, 800)
    lines = wrap(d, caption.upper(), f, W - 100)[:4]
    y = int(H * 0.68)
    for ln in lines:
        d.text((W // 2, y), ln, font=f, fill=accent, anchor="ma", stroke_width=5, stroke_fill=(0, 0, 0))
        y += 72
    return to_png(img)


def render_scene_frame(title: str, bullets: list[str], art: bytes | None, size=(1280, 720)) -> bytes:
    """16:9 explainer scene: reuses the slide layout at video resolution."""
    png = render_slide(title, bullets, art, index=0, total=0, size=(1920, 1080))
    return to_png(Image.open(io.BytesIO(png)).resize(size, Image.LANCZOS))


def caption_chunks(text: str, words: int = 5) -> list[str]:
    toks = re.findall(r"\S+", text)
    return [" ".join(toks[i:i + words]) for i in range(0, len(toks), words)] or [text]


def pdf_from_pngs(pngs: list[bytes]) -> bytes:
    pages = [Image.open(io.BytesIO(p)).convert("RGB") for p in pngs]
    buf = io.BytesIO()
    pages[0].save(buf, "PDF", save_all=True, append_images=pages[1:], resolution=144)
    return buf.getvalue()


# ---- ffmpeg ---------------------------------------------------------------------------

def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if not exe:
        raise RuntimeError("ffmpeg is not installed on the server")
    return exe


def run(args: list[str]) -> None:
    r = subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y", *args], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"ffmpeg failed: {r.stderr[-800:]}")


def probe_seconds(path: Path) -> float:
    out = subprocess.run([ffmpeg(), "-hide_banner", "-i", str(path)], capture_output=True, text=True).stderr
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", out)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0


def slideshow(frames: list[tuple[Path, float]], audio: Path | None, out: Path, size: tuple[int, int], fps: int = 30) -> None:
    """Still frames with per-frame durations (+ optional audio) → H.264/AAC MP4."""
    lst = out.with_suffix(".txt")
    body = "".join(f"file '{p.as_posix()}'\nduration {d:.3f}\n" for p, d in frames)
    body += f"file '{frames[-1][0].as_posix()}'\n"  # concat demuxer needs the last frame repeated
    lst.write_text(body, encoding="utf-8")
    w, h = size
    args = ["-f", "concat", "-safe", "0", "-i", str(lst)]
    if audio:
        args += ["-i", str(audio)]
    args += ["-vf", f"scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,fps={fps},format=yuv420p",
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-movflags", "+faststart"]
    if audio:
        args += ["-c:a", "aac", "-b:a", "128k", "-shortest"]
    run(args + [str(out)])


def concat_audio(clips: list[Path], out: Path, gap: float = 0.25) -> list[float]:
    """Concatenate narration clips with small gaps; returns each clip's start time."""
    silence = out.with_name("gap.mp3")
    run(["-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", f"{gap}", "-c:a", "libmp3lame", str(silence)])
    lst = out.with_suffix(".txt")
    lst.write_text("".join(f"file '{c.as_posix()}'\nfile '{silence.as_posix()}'\n" for c in clips), encoding="utf-8")
    run(["-f", "concat", "-safe", "0", "-i", str(lst), "-ar", "24000", "-ac", "1", "-c:a", "libmp3lame", "-b:a", "96k", str(out)])
    starts, t = [], 0.0
    for c in clips:
        starts.append(round(t, 2))
        t += probe_seconds(c) + gap
    return starts


def join_clips_with_narration(clips: list[Path], narration: Path | None, out: Path, size: tuple[int, int]) -> None:
    """Normalise generated video clips to one size/fps, concatenate, and lay narration over them."""
    w, h = size
    norm = []
    for i, c in enumerate(clips):
        n = out.with_name(f"norm{i}.mp4")
        run(["-i", str(c), "-an", "-vf",
             f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},fps=30,format=yuv420p",
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", str(n)])
        norm.append(n)
    lst = out.with_name("clips.txt")
    lst.write_text("".join(f"file '{n.as_posix()}'\n" for n in norm), encoding="utf-8")
    joined = out.with_name("joined.mp4")
    run(["-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(joined)])
    if narration:
        # Loop the visuals if narration is longer; cut at the narration's end.
        run(["-stream_loop", "-1", "-i", str(joined), "-i", str(narration), "-map", "0:v", "-map", "1:a",
             "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", str(out)])
    else:
        shutil.copy(joined, out)
