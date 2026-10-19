from __future__ import annotations

import asyncio
import time

from fastapi import APIRouter

from .. import activity, db, worker

router = APIRouter(tags=["activity"])


@router.get("/activity")
async def get_activity(since: int = 0):
    """Running + queued jobs and new log events since `since` (the last `seq` the client saw)."""
    running = [{
        "id": j["id"], "kind": j["kind"], "label": j.get("label") or j["kind"], "notebook_id": j.get("notebook_id"),
        "progress": j.get("_progress", 0), "attempts": j["attempts"], "status": "running",
    } for j in worker.RUNNING.values()]
    queued, db_ok = [], True
    async def load_queued():
        rows = await db.fetch_all(
            "SELECT id, kind, notebook_id, ref_id, attempts, error FROM jobs WHERE status='queued' "
            "ORDER BY created_at FETCH FIRST 20 ROWS ONLY")
        for r in rows:
            queued.append({"id": r["id"], "kind": r["kind"], "label": await worker.job_label(r),
                           "notebook_id": r["notebook_id"], "attempts": r["attempts"], "status": "queued",
                           "error": r["error"], "progress": 0})

    try:  # the panel must stay responsive even when the database isn't
        await asyncio.wait_for(load_queued(), timeout=3)
    except Exception:
        db_ok = False
    return {"seq": activity.last_seq(), "now": time.time(), "db_ok": db_ok,
            "jobs": running + queued, "events": activity.since(since)}
