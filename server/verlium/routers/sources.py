from __future__ import annotations

import mimetypes
from pathlib import PurePath

from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel

from .. import blobs, db, extract, worker
from .notebooks import get_or_404

router = APIRouter(tags=["sources"])

SRC_COLS = ("id, notebook_id, kind, title, url, mime, size_bytes, status, error, summary, key_topics, selected, "
            "char_count, created_at, updated_at")
MAX_UPLOAD = 200 * 1024 * 1024  # Gemini Notebook allows 200 MB per source
KIND_BY_EXT = {"pdf": "pdf", "txt": "text", "md": "markdown", "markdown": "markdown", "csv": "text", "json": "text"}


class LinkIn(BaseModel):
    id: str | None = None
    url: str


class PasteIn(BaseModel):
    id: str | None = None
    title: str | None = None
    text: str


class SourcePatch(BaseModel):
    title: str | None = None
    selected: bool | None = None


async def _get(sid: str, cols: str = SRC_COLS) -> dict:
    row = await db.fetch_one(f"SELECT {cols} FROM sources WHERE id=:id AND deleted=0", {"id": sid})
    if not row:
        raise HTTPException(404, "Source not found")
    return row


async def _create(nid: str, sid: str | None, **fields) -> dict:
    await get_or_404(nid)
    sid = sid or db.new_id()
    if await db.fetch_one("SELECT id FROM sources WHERE id=:id", {"id": sid}):
        return await _get(sid)  # idempotent retry from a client outbox
    cols = {"id": sid, "notebook_id": nid, **fields}
    await db.execute(f"INSERT INTO sources ({', '.join(cols)}) VALUES ({', '.join(':' + k for k in cols)})", cols)
    await worker.enqueue("ingest", nid, sid)
    return await _get(sid)


@router.get("/notebooks/{nid}/sources")
async def list_sources(nid: str):
    return await db.fetch_all(f"SELECT {SRC_COLS} FROM sources WHERE notebook_id=:id AND deleted=0 "
                              "ORDER BY created_at", {"id": nid})


@router.post("/notebooks/{nid}/sources/upload")
async def upload_source(nid: str, file: UploadFile, id: str | None = Form(default=None)):
    data = await file.read()
    if len(data) > MAX_UPLOAD:
        raise HTTPException(413, "File is larger than 200 MB")
    name = PurePath(file.filename or "upload").name
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    kind = KIND_BY_EXT.get(ext)
    if not kind:
        raise HTTPException(415, f"Unsupported file type '.{ext}' (supported now: {', '.join(KIND_BY_EXT)})")
    key, sha = blobs.put(data, ext)
    return await _create(nid, id, kind=kind, title=name, blob_key=key, sha256=sha, size_bytes=len(data),
                         mime=file.content_type or mimetypes.guess_type(name)[0])


@router.post("/notebooks/{nid}/sources/link")
async def link_source(nid: str, body: LinkIn):
    url = body.url.strip()
    if not url.lower().startswith(("http://", "https://")):
        raise HTTPException(400, "Enter a full http(s) URL")
    kind = "youtube" if extract.youtube_id(url) else "url"
    return await _create(nid, body.id, kind=kind, title=url[:1000], url=url)


@router.post("/notebooks/{nid}/sources/text")
async def paste_source(nid: str, body: PasteIn):
    if not body.text.strip():
        raise HTTPException(400, "Text is empty")
    return await _create(nid, body.id, kind="paste", title=(body.title or "Pasted text")[:1000], content=body.text)


@router.get("/sources/{sid}")
async def get_source(sid: str, content: bool = False):
    return await _get(sid, SRC_COLS + (", content" if content else ""))


@router.get("/sources/{sid}/file")
async def get_source_file(sid: str):
    row = await _get(sid, "blob_key, mime, title")
    if not row["blob_key"]:
        raise HTTPException(404, "This source has no stored file")
    return Response(blobs.get(row["blob_key"]), media_type=row["mime"] or "application/octet-stream")


@router.patch("/sources/{sid}")
async def update_source(sid: str, body: SourcePatch):
    await _get(sid)
    fields = body.model_dump(exclude_none=True)
    if "selected" in fields:
        fields["selected"] = int(fields["selected"])
    if fields:
        await db.execute(f"UPDATE sources SET {', '.join(f'{k}=:{k}' for k in fields)} WHERE id=:id",
                         {**fields, "id": sid})
    return await _get(sid)


@router.post("/notebooks/{nid}/sources/select")
async def select_all(nid: str, selected: bool = True):
    await db.execute("UPDATE sources SET selected=:s WHERE notebook_id=:id AND deleted=0",
                     {"s": int(selected), "id": nid})
    return {"ok": True}


@router.post("/sources/{sid}/retry")
async def retry_source(sid: str):
    row = await _get(sid, "notebook_id")
    await db.execute("UPDATE sources SET status='queued', error=NULL WHERE id=:id", {"id": sid})
    await worker.enqueue("ingest", row["notebook_id"], sid)
    return await _get(sid)


@router.delete("/sources/{sid}")
async def delete_source(sid: str):
    await _get(sid)
    await db.execute("DELETE FROM chunks WHERE source_id=:id", {"id": sid})
    await db.execute("UPDATE sources SET deleted=1 WHERE id=:id", {"id": sid})
    return {"ok": True}
