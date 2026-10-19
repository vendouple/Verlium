from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, UploadFile
from pydantic import BaseModel

from .. import db, memory
from ..modeltests import run_test
from ..providers import ROLE_ENDPOINTS, ROLES, OpenAICompat, ProviderError, RoleConfig, get_role, load_provider
from ..security import encrypt, mask, decrypt

router = APIRouter(prefix="/settings", tags=["settings"])


class ProviderIn(BaseModel):
    id: str | None = None
    name: str
    base_url: str
    adapter: str = "openai"
    api_key: str | None = None  # None = keep the stored key
    headers: dict[str, str] | None = None


class RoleIn(BaseModel):
    provider_id: str | None
    model_id: str | None
    params: dict[str, Any] = {}


@router.get("/providers")
async def list_providers():
    rows = await db.fetch_all(
        "SELECT id, name, base_url, adapter, api_key_enc, headers FROM providers WHERE deleted = 0 ORDER BY created_at")
    return [{**{k: r[k] for k in ("id", "name", "base_url", "adapter", "headers")},
             "api_key_hint": mask(decrypt(r["api_key_enc"]))} for r in rows]


@router.post("/providers")
async def upsert_provider(p: ProviderIn):
    pid = p.id or db.new_id()
    exists = await db.fetch_one("SELECT id FROM providers WHERE id = :id", {"id": pid})
    params = {"id": pid, "name": p.name, "base_url": p.base_url.rstrip("/"), "adapter": p.adapter,
              "headers": p.headers or {}}
    if exists:
        sql = "UPDATE providers SET name=:name, base_url=:base_url, adapter=:adapter, headers=:headers, deleted=0"
        if p.api_key is not None:
            sql += ", api_key_enc=:k"
            params["k"] = encrypt(p.api_key) if p.api_key else None
        await db.execute(sql + " WHERE id=:id", params)
    else:
        params["k"] = encrypt(p.api_key) if p.api_key else None
        await db.execute(
            "INSERT INTO providers (id, name, base_url, adapter, api_key_enc, headers) "
            "VALUES (:id, :name, :base_url, :adapter, :k, :headers)", params)
    return {"id": pid}


@router.delete("/providers/{pid}")
async def delete_provider(pid: str):
    await db.execute("UPDATE model_roles SET provider_id = NULL WHERE provider_id = :id", {"id": pid})
    await db.execute("UPDATE providers SET deleted = 1, api_key_enc = NULL WHERE id = :id", {"id": pid})
    return {"ok": True}


@router.get("/providers/{pid}/models")
async def provider_models(pid: str, role: str | None = None):
    prov = await load_provider(pid)
    if not prov:
        raise HTTPException(404, "Provider not found")
    try:
        models = await OpenAICompat(prov).list_models()
    except (ProviderError, Exception) as e:  # surface network errors to the UI
        raise HTTPException(502, str(e))
    if role:
        ep = ROLE_ENDPOINTS.get(role)
        tagged = [m for m in models if m["supported_endpoints"]]
        if ep and tagged:  # gateway tells us which endpoints each model supports
            models = [m for m in models if any(e.startswith(ep) for e in m["supported_endpoints"])]
            if role == "vision":
                models = [m for m in models if "image" in (m["input_modalities"] or ["image"])]
    return models


@router.get("/roles")
async def list_roles():
    rows = {r["role"]: r for r in await db.fetch_all("SELECT role, provider_id, model_id, params FROM model_roles")}
    return [{"role": role, **({k: rows[role][k] for k in ("provider_id", "model_id", "params")} if role in rows
                              else {"provider_id": None, "model_id": None, "params": {}})} for role in ROLES]


@router.put("/roles/{role}")
async def set_role(role: str, body: RoleIn):
    if role not in ROLES:
        raise HTTPException(404, "Unknown role")
    await db.execute(
        "MERGE INTO model_roles t USING (SELECT :role role FROM dual) s ON (t.role = s.role) "
        "WHEN MATCHED THEN UPDATE SET provider_id=:pid, model_id=:mid, params=:params "
        "WHEN NOT MATCHED THEN INSERT (role, provider_id, model_id, params) VALUES (:role, :pid, :mid, :params)",
        {"role": role, "pid": body.provider_id, "mid": body.model_id, "params": body.params or {}})
    return {"ok": True}


@router.post("/roles/{role}/test")
async def test_role(role: str, body: RoleIn | None = None):
    """Tests the saved config, or an unsaved one passed in the body (so users can test before saving)."""
    if body and body.provider_id and body.model_id:
        prov = await load_provider(body.provider_id)
        if not prov:
            raise HTTPException(404, "Provider not found")
        cfg = RoleConfig(role, prov, body.model_id, body.params or {})
    else:
        cfg = await get_role(role)
        if not cfg:
            raise HTTPException(400, f"No model configured for '{role}'")
    try:
        return await run_test(cfg)
    except Exception as e:
        return {"ok": False, "latency_ms": None, "detail": str(e)[:500]}


@router.post("/roles/stt/transcribe")
async def stt_mic_test(file: UploadFile):
    cfg = await get_role("stt")
    if not cfg:
        raise HTTPException(400, "No STT model configured")
    try:
        text = await cfg.client().transcribe(cfg.model_id, await file.read(), file.filename or "clip.m4a",
                                             cfg.params.get("language"))
    except ProviderError as e:
        return {"ok": False, "detail": str(e)}
    return {"ok": bool(text.strip()), "detail": text}


class MemorySettings(BaseModel):
    enabled: bool


@router.get("/memory")
async def get_memory():
    rows = await db.fetch_all("SELECT id, content, created_at FROM memories WHERE deleted = 0 ORDER BY created_at DESC")
    return {"enabled": await memory.personalisation_enabled(), "memories": rows}


@router.put("/memory")
async def set_memory(body: MemorySettings):
    await memory.set_setting("personalise", body.enabled)
    return {"ok": True}


@router.delete("/memory/{mid}")
async def delete_memory(mid: str):
    await db.execute("UPDATE memories SET deleted = 1 WHERE id = :id", {"id": mid})
    return {"ok": True}


@router.delete("/memory")
async def clear_memory():
    await db.execute("UPDATE memories SET deleted = 1 WHERE deleted = 0")
    return {"ok": True}
