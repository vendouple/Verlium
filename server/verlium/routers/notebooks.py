from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .. import db

router = APIRouter(prefix="/notebooks", tags=["notebooks"])

NB_COLS = "id, title, emoji, summary, chat_config, created_at, updated_at"


class NotebookIn(BaseModel):
    id: str | None = None  # client-generated UUID (offline create)
    title: str | None = None
    emoji: str | None = None


class NotebookPatch(BaseModel):
    title: str | None = None
    emoji: str | None = None
    chat_config: dict[str, Any] | None = Field(default=None, description="{goal, custom_prompt, length}")


async def get_or_404(nid: str) -> dict:
    nb = await db.fetch_one(f"SELECT {NB_COLS} FROM notebooks WHERE id=:id AND deleted=0", {"id": nid})
    if not nb:
        raise HTTPException(404, "Notebook not found")
    return nb


@router.get("")
async def list_notebooks():
    return await db.fetch_all(
        f"SELECT {', '.join('n.' + c.strip() for c in NB_COLS.split(','))}, "
        "(SELECT COUNT(*) FROM sources s WHERE s.notebook_id = n.id AND s.deleted = 0) source_count "
        "FROM notebooks n WHERE n.deleted = 0 ORDER BY n.updated_at DESC")


@router.post("")
async def create_notebook(body: NotebookIn):
    nid = body.id or db.new_id()
    await db.execute("INSERT INTO notebooks (id, title, emoji) VALUES (:id, :t, :e)",
                     {"id": nid, "t": body.title or "Untitled notebook", "e": body.emoji})
    return await get_or_404(nid)


@router.get("/{nid}")
async def get_notebook(nid: str):
    return await get_or_404(nid)


@router.patch("/{nid}")
async def update_notebook(nid: str, body: NotebookPatch):
    await get_or_404(nid)
    fields = body.model_dump(exclude_none=True)
    if fields:
        if "chat_config" in fields and fields["chat_config"].get("custom_prompt"):
            fields["chat_config"]["custom_prompt"] = fields["chat_config"]["custom_prompt"][:10000]
        sets = ", ".join(f"{k} = :{k}" for k in fields)
        await db.execute(f"UPDATE notebooks SET {sets} WHERE id = :id", {**fields, "id": nid})
    return await get_or_404(nid)


@router.delete("/{nid}")
async def delete_notebook(nid: str):
    await get_or_404(nid)
    for table in ("sources", "notes", "chat_messages"):
        await db.execute(f"UPDATE {table} SET deleted = 1 WHERE notebook_id = :id", {"id": nid})
    await db.execute("DELETE FROM chunks WHERE notebook_id = :id", {"id": nid})
    await db.execute("UPDATE notebooks SET deleted = 1 WHERE id = :id", {"id": nid})
    return {"ok": True}
