"""Model gateway: OpenAI-compatible client for every model role.

Providers are stored in Oracle with the API key encrypted; roles map a capability
(chat, vision, embeddings, tts, stt, image, video, realtime) to provider + model + params.
"""
from __future__ import annotations

import asyncio
import base64
import json
import re
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

import httpx

from . import db
from .security import decrypt

ROLES = ("chat", "vision", "embeddings", "tts", "stt", "image", "video", "realtime", "rerank")

# Which `supported_endpoints` entry marks a model as usable for a role (OpenAI /models extensions,
# as returned by Pollinations, LiteLLM and OpenRouter-style gateways).
ROLE_ENDPOINTS = {
    "chat": "/v1/chat/completions",
    "vision": "/v1/chat/completions",
    "embeddings": "/v1/embeddings",
    "tts": "/v1/audio/speech",
    "stt": "/v1/audio/transcriptions",
    "image": "/v1/images/generations",
    "video": "/video",
    "realtime": "/v1/realtime",
}

TIMEOUT = httpx.Timeout(connect=15, read=300, write=120, pool=15)
EMBED_TIMEOUT = httpx.Timeout(connect=15, read=60, write=60, pool=15)


class ProviderError(RuntimeError):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class ConfigError(ProviderError):
    """A setting is missing (e.g. no model for a role). Retrying can't help, so jobs fail right away."""


_CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def clean_text(text: str) -> str:
    """Strips control chars and lone surrogates that PDF extractors emit and strict JSON validators reject."""
    text = text.encode("utf-8", "replace").decode("utf-8")
    return _CTRL.sub(" ", text).strip()


def parse_json(text: str) -> Any:
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        m = re.search(r"[\[{].*[\]}]", text, re.S)
        if not m:
            raise ProviderError(f"Model did not return JSON: {text[:200]}")
        return json.loads(m.group(0))


@dataclass
class Provider:
    id: str
    name: str
    base_url: str
    adapter: str = "openai"
    api_key: str = ""
    headers: dict[str, str] = field(default_factory=dict)


@dataclass
class RoleConfig:
    role: str
    provider: Provider
    model_id: str
    params: dict[str, Any]

    def client(self) -> "OpenAICompat":
        return OpenAICompat(self.provider)


async def load_provider(provider_id: str) -> Provider | None:
    row = await db.fetch_one(
        "SELECT id, name, base_url, adapter, api_key_enc, headers FROM providers WHERE id = :id AND deleted = 0",
        {"id": provider_id},
    )
    if not row:
        return None
    return Provider(row["id"], row["name"], row["base_url"], row["adapter"], decrypt(row["api_key_enc"]), row["headers"] or {})


async def get_role(role: str, fallback_to_chat: bool = True) -> RoleConfig | None:
    row = await db.fetch_one("SELECT role, provider_id, model_id, params FROM model_roles WHERE role = :r", {"r": role})
    if (not row or not row["provider_id"] or not row["model_id"]) and fallback_to_chat and role == "vision":
        return await get_role("chat", False)
    if not row or not row["provider_id"] or not row["model_id"]:
        return None
    prov = await load_provider(row["provider_id"])
    if not prov:
        return None
    return RoleConfig(role, prov, row["model_id"], row["params"] or {})


async def require_role(role: str) -> RoleConfig:
    cfg = await get_role(role)
    if not cfg:
        raise ConfigError(f"No model configured for '{role}'. Open Settings → Models and pick a Model ID.")
    return cfg


def _raise_for(resp: httpx.Response) -> None:
    if resp.is_success:
        return
    try:
        body = resp.json()
        err = body.get("error")
        msg = (err.get("message") if isinstance(err, dict) else err) or body.get("message") or body
        # Validation errors often hide the useful part (which field) in a details list.
        details = (err.get("details") if isinstance(err, dict) else None) or body.get("details")
        if details:
            msg = f"{msg} — {json.dumps(details)[:300]}"
    except Exception:
        msg = resp.text[:500]
    raise ProviderError(f"{resp.status_code} from provider: {msg}", resp.status_code)


class ThinkSplitter:
    """Splits streamed text into thinking/text parts around <think>…</think>, across chunk boundaries."""
    OPEN, CLOSE = "<think>", "</think>"

    def __init__(self):
        self.buf = ""
        self.inside = False

    def feed(self, chunk: str) -> list[tuple[str, str]]:
        self.buf += chunk
        out: list[tuple[str, str]] = []
        while True:
            tag = self.CLOSE if self.inside else self.OPEN
            i = self.buf.find(tag)
            if i != -1:
                if i:
                    out.append(("thinking" if self.inside else "text", self.buf[:i]))
                self.buf = self.buf[i + len(tag):]
                self.inside = not self.inside
                continue
            # keep a possible partial tag at the end of the buffer
            keep = next((k for k in range(len(tag) - 1, 0, -1) if self.buf.endswith(tag[:k])), 0)
            emit = self.buf[: len(self.buf) - keep]
            if emit:
                out.append(("thinking" if self.inside else "text", emit))
            self.buf = self.buf[len(emit):]
            return out

    def flush(self) -> list[tuple[str, str]]:
        out = [("thinking" if self.inside else "text", self.buf)] if self.buf else []
        self.buf = ""
        return out


class OpenAICompat:
    def __init__(self, provider: Provider):
        self.p = provider
        self.base = provider.base_url.rstrip("/")

    def _headers(self, json_body: bool = True) -> dict[str, str]:
        h = {"User-Agent": "Verlium/0.1"}
        if json_body:
            h["Content-Type"] = "application/json"
        if self.p.api_key:
            h["Authorization"] = f"Bearer {self.p.api_key}"
        h.update(self.p.headers or {})
        return h

    def _client(self, timeout: httpx.Timeout = TIMEOUT) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=timeout, follow_redirects=True)

    # ---- discovery -------------------------------------------------------
    async def list_models(self) -> list[dict[str, Any]]:
        async with self._client() as c:
            r = await c.get(f"{self.base}/models", headers=self._headers(False))
            _raise_for(r)
            data = r.json()
        items = data.get("data", data) if isinstance(data, dict) else data
        out = []
        for m in items:
            if isinstance(m, str):
                m = {"id": m}
            out.append({
                "id": m.get("id"),
                "title": m.get("title") or m.get("name") or m.get("id"),
                "category": m.get("category"),
                "supported_endpoints": m.get("supported_endpoints") or [],
                "input_modalities": m.get("input_modalities") or m.get("architecture", {}).get("input_modalities") or [],
                "output_modalities": m.get("output_modalities") or [],
                "context_length": m.get("context_length") or m.get("context_window"),
                "paid_only": m.get("paid_only"),
            })
        return out

    # ---- text ------------------------------------------------------------
    @staticmethod
    def _chat_body(model: str, messages: list[dict], params: dict[str, Any], stream: bool) -> dict[str, Any]:
        body: dict[str, Any] = {"model": model, "messages": messages, "stream": stream}
        for k in ("temperature", "top_p", "max_tokens", "response_format", "reasoning_effort", "seed"):
            if params.get(k) is not None:
                body[k] = params[k]
        return body

    async def chat(self, model: str, messages: list[dict], **params: Any) -> dict[str, Any]:
        async with self._client() as c:
            r = await c.post(f"{self.base}/chat/completions", headers=self._headers(),
                             json=self._chat_body(model, messages, params, False))
            _raise_for(r)
            data = r.json()
        choice = (data.get("choices") or [{}])[0]
        content = (choice.get("message") or {}).get("content") or ""
        content = re.sub(r"<think>.*?</think>", "", content, flags=re.S).strip()
        return {"content": content, "usage": data.get("usage") or {}}

    async def chat_json(self, model: str, prompt: str, *, system: str | None = None, **params: Any) -> Any:
        """Ask for a JSON object; tolerant of models that wrap it in prose or code fences."""
        msgs = ([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": prompt}]
        # Models differ in what they accept (json_object vs json_schema only; reasoning models reject
        # temperature), so step down to a plain request on a 4xx instead of failing.
        attempts = [{**params, "response_format": {"type": "json_object"}}, params,
                    {k: v for k, v in params.items() if k not in ("temperature", "top_p")}]
        for i, p in enumerate(attempts):
            try:
                r = await self.chat(model, msgs, **p)
                break
            except ProviderError as e:
                if i == len(attempts) - 1 or (e.status is not None and not 400 <= e.status < 500):
                    raise
        return parse_json(r["content"])

    async def chat_stream(self, model: str, messages: list[dict], **params: Any) -> AsyncIterator[tuple[str, str]]:
        """Yields ("thinking" | "text", chunk). Reasoning arrives as `reasoning_content` (DeepSeek/vLLM),
        `reasoning` (OpenRouter-style gateways) or inline <think>…</think> tags (Qwen/DeepSeek R1 raw)."""
        splitter = ThinkSplitter()
        async with self._client() as c:
            async with c.stream("POST", f"{self.base}/chat/completions", headers=self._headers(),
                                json=self._chat_body(model, messages, params, True)) as r:
                if not r.is_success:
                    await r.aread()
                    _raise_for(r)
                async for line in r.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if payload == "[DONE]":
                        break
                    try:
                        evt = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    for ch in evt.get("choices") or []:
                        delta = ch.get("delta") or {}
                        reasoning = delta.get("reasoning_content") or delta.get("reasoning")
                        if isinstance(reasoning, str) and reasoning:
                            yield "thinking", reasoning
                        if delta.get("content"):
                            for part in splitter.feed(delta["content"]):
                                yield part
        for part in splitter.flush():
            yield part

    # ---- embeddings ------------------------------------------------------
    async def embed(self, model: str, texts: list[str], dimensions: int | None = None) -> list[list[float]]:
        """Embeds texts. On a 400 it degrades gracefully: drop `dimensions`, then split the batch in half,
        so a provider with a smaller batch limit (or one odd chunk) doesn't fail a whole source."""
        texts = [clean_text(t) or " " for t in texts]
        try:
            return await self._embed_once(model, texts, dimensions)
        except ProviderError as e:
            if e.status != 400:
                raise
            if dimensions:
                return await self.embed(model, texts, None)
            if len(texts) == 1:
                raise
            mid = len(texts) // 2
            return await self.embed(model, texts[:mid]) + await self.embed(model, texts[mid:])

    async def _embed_once(self, model: str, texts: list[str], dimensions: int | None) -> list[list[float]]:
        body: dict[str, Any] = {"model": model, "input": texts}
        if dimensions:
            body["dimensions"] = dimensions
        # A batch normally takes seconds; a hung request is retried quickly instead of stalling for minutes.
        # Transient failures (timeouts, 429, 5xx) retry with backoff so one blip doesn't fail a 100-batch source.
        for attempt in range(5):
            try:
                async with self._client(EMBED_TIMEOUT) as c:
                    r = await c.post(f"{self.base}/embeddings", headers=self._headers(), json=body)
                if r.status_code == 429 or r.status_code >= 500:
                    _raise_for(r)
                break
            except (httpx.TransportError, ProviderError):  # only 429/5xx raise inside the loop
                if attempt == 4:
                    raise
                await asyncio.sleep(2 ** attempt * 2)
        _raise_for(r)
        data = r.json()["data"]
        data.sort(key=lambda d: d.get("index", 0))
        return [d["embedding"] for d in data]

    # ---- audio -----------------------------------------------------------
    async def speech(self, model: str, text: str, voice: str, fmt: str = "mp3", **extra: Any) -> bytes:
        body = {"model": model, "input": text, "voice": voice, "response_format": fmt, **extra}
        async with self._client() as c:
            r = await c.post(f"{self.base}/audio/speech", headers=self._headers(), json=body)
            _raise_for(r)
            return r.content

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None = None) -> str:
        data = {"model": model}
        if language:
            data["language"] = language
        async with self._client() as c:
            r = await c.post(f"{self.base}/audio/transcriptions", headers=self._headers(False),
                             data=data, files={"file": (filename, audio)})
            _raise_for(r)
            ctype = r.headers.get("content-type", "")
            return r.json().get("text", "") if "json" in ctype else r.text

    # ---- video (Pollinations async adapter) --------------------------------
    async def video(self, model: str, prompt: str, *, duration: int = 5, aspect: str = "16:9",
                    audio: bool = False, timeout_s: int = 900) -> bytes:
        """GET {root}/video/{prompt} with `Prefer: respond-async`, poll /v1/jobs/{id}, download the MP4."""
        from urllib.parse import quote

        root = re.sub(r"/v1/?$", "", self.base)
        params = {"model": model, "duration": duration, "aspectRatio": aspect, "audio": str(audio).lower()}
        headers = {**self._headers(False), "Prefer": "respond-async"}
        async with self._client() as c:
            r = await c.get(f"{root}/video/{quote(prompt[:1800], safe='')}", params=params, headers=headers)
            _raise_for(r)
            if r.status_code == 200 and r.headers.get("content-type", "").startswith("video/"):
                return r.content  # cached result returned directly
            job = r.json()
            jid = job.get("id")
            if not jid:
                raise ProviderError(f"Video request returned no job id: {str(job)[:200]}")
            waited = 0
            while waited < timeout_s:
                await asyncio.sleep(5)
                waited += 5
                s = await c.get(f"{root}/v1/jobs/{jid}", headers=self._headers(False))
                _raise_for(s)
                status = s.json().get("status")
                if status == "succeeded":
                    res = await c.get(f"{root}/v1/jobs/{jid}/result", headers=self._headers(False))
                    _raise_for(res)
                    return res.content
                if status == "failed":
                    raise ProviderError(f"Video generation failed: {s.json().get('error') or s.text[:300]}")
            raise ProviderError("Video generation timed out")

    # ---- images ----------------------------------------------------------
    async def image(self, model: str, prompt: str, size: str = "1024x1024", **extra: Any) -> bytes:
        body = {"model": model, "prompt": prompt, "size": size, "n": 1, "response_format": "b64_json", **extra}
        async with self._client() as c:
            r = await c.post(f"{self.base}/images/generations", headers=self._headers(), json=body)
            _raise_for(r)
            item = r.json()["data"][0]
            if item.get("b64_json"):
                return base64.b64decode(item["b64_json"])
            img = await c.get(item["url"])
            _raise_for(img)
            return img.content
