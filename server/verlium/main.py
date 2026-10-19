"""Verlium API server. Run: uvicorn verlium.main:app --host 0.0.0.0 --port 8000"""
from __future__ import annotations

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI

from . import db, worker
from .routers import activity, chat, notebooks, notes, settings, sources, studio
from .security import require_token

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.open_pool()
    task = asyncio.create_task(worker.run_forever())
    yield
    task.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await task
    await db.close_pool()


app = FastAPI(title="Verlium", version="0.1.0", lifespan=lifespan)

for r in (activity.router, notebooks.router, sources.router, notes.router, chat.router, settings.router, studio.router):
    app.include_router(r, prefix="/api", dependencies=[Depends(require_token)])


@app.get("/health")
async def health():
    row = await db.fetch_one("SELECT 1 ok FROM dual")
    return {"ok": bool(row), "service": "verlium", "version": app.version}
