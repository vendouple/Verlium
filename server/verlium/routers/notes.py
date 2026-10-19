from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .. import db
from .notebooks import get_or_404

router = APIRouter(tags=["notes"])

NOTE_COLS = "id, notebook_id, kind, title, content, citations, version, created_at, updated_at"


class NoteIn(BaseModel):
    id: str | None = None
    kind: str = "note"
    title: str | None = None
    content: str = ""
    citations: list[dict[str, Any]] | None = None


class NotePatch(BaseModel):
    title: str | None = None
    content: str | None = None
    base_version: int | None = None  # optimistic concurrency for multi-device edits


@router.get("/notebooks/{nid}/notes")
async def list_notes(nid: str):
    return await db.fetch_all(f"SELECT {NOTE_COLS} FROM notes WHERE notebook_id=:id AND deleted=0 "
                              "ORDER BY created_at DESC", {"id": nid})


@router.post("/notebooks/{nid}/notes")
async def create_note(nid: str, body: NoteIn):
    await get_or_404(nid)
    note_id = body.id or db.new_id()
    if not await db.fetch_one("SELECT id FROM notes WHERE id=:id", {"id": note_id}):
        await db.execute(
            "INSERT INTO notes (id, notebook_id, kind, title, content, citations) VALUES (:id, :nb, :k, :t, :c, :cit)",
            {"id": note_id, "nb": nid, "k": body.kind, "t": (body.title or "New note")[:1000], "c": body.content,
             "cit": body.citations or []})
    return await db.fetch_one(f"SELECT {NOTE_COLS} FROM notes WHERE id=:id", {"id": note_id})


@router.patch("/notes/{note_id}")
async def update_note(note_id: str, body: NotePatch):
    note = await db.fetch_one(f"SELECT {NOTE_COLS} FROM notes WHERE id=:id AND deleted=0", {"id": note_id})
    if not note:
        raise HTTPException(404, "Note not found")
    if body.base_version is not None and body.base_version != note["version"]:
        raise HTTPException(409, {"message": "Note changed on another device", "server": note})
    fields = body.model_dump(exclude_none=True, exclude={"base_version"})
    if fields:
        await db.execute(
            f"UPDATE notes SET {', '.join(f'{k}=:{k}' for k in fields)}, version = version + 1 WHERE id=:id",
            {**fields, "id": note_id})
    return await db.fetch_one(f"SELECT {NOTE_COLS} FROM notes WHERE id=:id", {"id": note_id})


@router.delete("/notes/{note_id}")
async def delete_note(note_id: str):
    await db.execute("UPDATE notes SET deleted=1 WHERE id=:id", {"id": note_id})
    return {"ok": True}
