"""The "Test" buttons in Settings → Models. Each returns {ok, latency_ms, detail, ...}."""
from __future__ import annotations

import base64
import io
import math
import re
import time
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from .providers import OpenAICompat, RoleConfig


def vision_test_image() -> bytes:
    """Red circle with the text VERLIUM 42 on white. The model must report all three facts."""
    img = Image.new("RGB", (512, 512), "white")
    d = ImageDraw.Draw(img)
    d.ellipse((96, 40, 416, 360), fill=(220, 30, 30))
    try:
        font = ImageFont.load_default(size=64)
    except TypeError:  # very old Pillow
        font = ImageFont.load_default()
    d.text((256, 440), "VERLIUM 42", fill="black", font=font, anchor="mm")
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def _cos(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)) or 1)


async def run_test(cfg: RoleConfig) -> dict[str, Any]:
    c: OpenAICompat = cfg.client()
    m, p = cfg.model_id, cfg.params
    t0 = time.perf_counter()

    def done(ok: bool, detail: str, **extra: Any) -> dict[str, Any]:
        return {"ok": ok, "latency_ms": round((time.perf_counter() - t0) * 1000), "detail": detail, **extra}

    if cfg.role == "chat":
        r = await c.chat(m, [{"role": "user", "content": "Reply with exactly: OK"}], max_tokens=p.get("test_max_tokens", 2000))
        out_tokens = (r["usage"] or {}).get("completion_tokens")
        secs = time.perf_counter() - t0
        return done(bool(r["content"].strip()), r["content"].strip()[:200],
                    tokens_per_s=round(out_tokens / secs, 1) if out_tokens else None)

    if cfg.role == "vision":
        b64 = base64.b64encode(vision_test_image()).decode()
        r = await c.chat(m, [{"role": "user", "content": [
            {"type": "text", "text": "Describe this image in one short sentence: the shape, its colour, and any text."},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ]}], max_tokens=2000)
        text = r["content"].lower()
        checks = {"red": "red" in text, "circle": bool(re.search(r"circle|round|disc|disk|dot|ball", text)), "42": "42" in text}
        return done(all(checks.values()), r["content"].strip()[:300], checks=checks)

    if cfg.role == "embeddings":
        a, b, z = await c.embed(m, [
            "The cat sat on the warm windowsill in the sun.",
            "A kitten was lying in the sunshine by the window.",
            "Quarterly revenue rose due to strong bond markets.",
        ], p.get("dimensions"))
        sim_close, sim_far = _cos(a, b), _cos(a, z)
        return done(sim_close > sim_far, f"{len(a)} dimensions; similar={sim_close:.3f}, unrelated={sim_far:.3f}",
                    dimensions=len(a))

    if cfg.role == "tts":
        voices = [v for v in (p.get("voice_a", "alloy"), p.get("voice_b")) if v]
        samples = {}
        for v in voices:
            audio = await c.speech(m, f"Hi, I'm {v}, one of your Verlium hosts.", v, p.get("format", "mp3"))
            samples[v] = base64.b64encode(audio).decode()
        return done(all(samples.values()), f"Generated {len(samples)} voice sample(s)",
                    audio_b64=samples, mime="audio/mpeg")

    if cfg.role == "stt":
        # Round-trip needs a TTS model; otherwise the client uploads a mic clip to /settings/roles/stt/transcribe.
        from .providers import get_role
        tts = await get_role("tts")
        if not tts:
            return done(False, "Configure a TTS model first, or use 'Record 3 s' to test with your microphone")
        phrase = "Verlium test forty two"
        audio = await tts.client().speech(tts.model_id, phrase, tts.params.get("voice_a", "alloy"), "mp3")
        text = await c.transcribe(m, audio, "test.mp3", p.get("language"))
        return done("42" in text or "forty" in text.lower(), text.strip()[:300])

    if cfg.role == "image":
        img = await c.image(m, "A small friendly robot reading a book, flat illustration", p.get("size", "1024x1024"))
        return done(len(img) > 1000, f"{len(img) // 1024} KB image", image_b64=base64.b64encode(img).decode())

    return done(False, f"No test for role '{cfg.role}' yet")
