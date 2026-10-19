from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .. import blobs, db, worker
from ..studio import TYPE_LABEL, TYPES
from .notebooks import get_or_404

router = APIRouter(tags=["studio"])

COLS = ("id, notebook_id, type, title, status, progress, error, prompt, options, source_ids, content, mime, "
        "duration_s, unread, created_at, updated_at, CASE WHEN blob_key IS NULL THEN 0 ELSE 1 END has_media")


class StudioIn(BaseModel):
    id: str | None = None
    type: str
    prompt: str = ""
    options: dict[str, Any] = {}
    source_ids: list[str] | None = None  # default: selected sources


class StudioPatch(BaseModel):
    title: str | None = None
    unread: bool | None = None


async def _get(oid: str) -> dict:
    row = await db.fetch_one(f"SELECT {COLS} FROM studio_outputs WHERE id=:id AND deleted=0", {"id": oid})
    if not row:
        raise HTTPException(404, "Output not found")
    return row


@router.get("/notebooks/{nid}/studio")
async def list_outputs(nid: str):
    return await db.fetch_all(f"SELECT {COLS} FROM studio_outputs WHERE notebook_id=:nb AND deleted=0 "
                              "ORDER BY created_at DESC", {"nb": nid})


@router.post("/notebooks/{nid}/studio")
async def create_output(nid: str, body: StudioIn):
    await get_or_404(nid)
    if body.type not in TYPES:
        raise HTTPException(400, f"{body.type} is not available yet")
    sids = body.source_ids
    if sids is None:
        sids = [r["id"] for r in await db.fetch_all(
            "SELECT id FROM sources WHERE notebook_id=:nb AND deleted=0 AND selected=1 AND status='ready'", {"nb": nid})]
    if not sids:
        raise HTTPException(400, "Select at least one processed source first")
    oid = body.id or db.new_id()
    await db.execute(
        "INSERT INTO studio_outputs (id, notebook_id, type, title, prompt, options, source_ids, unread) "
        "VALUES (:id, :nb, :type, :title, :prompt, :opts, :sids, 0)",
        {"id": oid, "nb": nid, "type": body.type, "title": TYPE_LABEL[body.type], "prompt": body.prompt[:10000],
         "opts": body.options or {}, "sids": sids})
    await worker.enqueue("studio", nid, oid)
    return await _get(oid)


@router.get("/studio/{oid}")
async def get_output(oid: str):
    return await _get(oid)


@router.patch("/studio/{oid}")
async def update_output(oid: str, body: StudioPatch):
    await _get(oid)
    fields = body.model_dump(exclude_none=True)
    if "unread" in fields:
        fields["unread"] = int(fields["unread"])
    if fields:
        await db.execute(f"UPDATE studio_outputs SET {', '.join(f'{k}=:{k}' for k in fields)} WHERE id=:id",
                         {**fields, "id": oid})
    return await _get(oid)


@router.post("/studio/{oid}/retry")
async def retry_output(oid: str):
    row = await _get(oid)
    await db.execute("UPDATE studio_outputs SET status='queued', progress=0, error=NULL WHERE id=:id", {"id": oid})
    await worker.enqueue("studio", row["notebook_id"], oid)
    return await _get(oid)


@router.delete("/studio/{oid}")
async def delete_output(oid: str):
    await db.execute("UPDATE studio_outputs SET deleted=1 WHERE id=:id", {"id": oid})
    return {"ok": True}


@router.get("/studio/{oid}/media")
async def output_media(oid: str):
    """Supports HTTP Range so players can seek. Players pass ?token= since they can't set headers."""
    row = await db.fetch_one("SELECT blob_key, mime, title FROM studio_outputs WHERE id=:id AND deleted=0", {"id": oid})
    if not row or not row["blob_key"]:
        raise HTTPException(404, "No media for this output")
    ext = row["blob_key"].rsplit(".", 1)[-1]
    return FileResponse(blobs.path_for(row["blob_key"]), media_type=row["mime"],
                        filename=f"{(row['title'] or 'output')[:80]}.{ext}", content_disposition_type="inline")


@router.get("/studio/{oid}/asset/{index}")
async def output_asset(oid: str, index: int):
    """Per-slide images of a Slide Deck (content.slides[i].image)."""
    row = await db.fetch_one("SELECT content FROM studio_outputs WHERE id=:id AND deleted=0", {"id": oid})
    slides = ((row or {}).get("content") or {}).get("slides") or []
    if not 0 <= index < len(slides) or not slides[index].get("image"):
        raise HTTPException(404, "No such slide")
    return FileResponse(blobs.path_for(slides[index]["image"]), media_type="image/png")
