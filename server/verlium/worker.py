"""In-process background job runner (ingestion now, Studio generation later).

Jobs live in Oracle, so a crash or restart resumes them. One worker is plenty for one user;
the same loop can later run as a separate process on the VM.
"""
from __future__ import annotations

import asyncio
import logging
import traceback

from . import activity, db
from .providers import ConfigError

log = logging.getLogger("verlium.worker")
MAX_ATTEMPTS = 3
_wake = asyncio.Event()
HANDLERS = {}
RUNNING: dict[str, dict] = {}  # job id -> job (with live _progress), for /activity


def handler(kind: str):
    def deco(fn):
        HANDLERS[kind] = fn
        return fn
    return deco


async def enqueue(kind: str, notebook_id: str | None = None, ref_id: str | None = None, payload: dict | None = None) -> str:
    jid = db.new_id()
    await db.execute(
        "INSERT INTO jobs (id, kind, notebook_id, ref_id, payload) VALUES (:id, :k, :nb, :ref, :p)",
        {"id": jid, "k": kind, "nb": notebook_id, "ref": ref_id, "p": payload or {}})
    _wake.set()
    return jid


async def _claim() -> dict | None:
    async with db.pool().acquire() as conn:
        with conn.cursor() as cur:
            out = cur.var(str)
            await cur.execute(
                "UPDATE jobs SET status='running', attempts=attempts+1 WHERE status='queued' AND id = "
                "(SELECT id FROM jobs WHERE status='queued' ORDER BY created_at FETCH FIRST 1 ROWS ONLY) "
                "RETURNING id INTO :out", {"out": out})
            jid = (out.getvalue() or [None])[0]
        await conn.commit()
    if not jid:
        return None
    return await db.fetch_one("SELECT id, kind, notebook_id, ref_id, payload, attempts FROM jobs WHERE id=:id", {"id": jid})


async def _run(job: dict) -> None:
    fn = HANDLERS.get(job["kind"])
    job["label"] = await job_label(job)
    RUNNING[job["id"]] = job
    token = activity.current_job.set(job)
    attempt = f" (attempt {job['attempts']})" if job["attempts"] > 1 else ""
    activity.report(f"Started {job['kind']}: {job['label']}{attempt}", progress=0)
    try:
        if not fn:
            raise RuntimeError(f"No handler for job kind {job['kind']}")
        result = await fn(job)
        await db.execute("UPDATE jobs SET status='done', progress=100, result=:r WHERE id=:id",
                         {"id": job["id"], "r": result or {}})
        activity.report(f"Finished {job['label']}", "success", progress=100)
    except Exception as e:
        log.error("job %s failed: %s", job["id"], traceback.format_exc())
        retry = job["attempts"] < MAX_ATTEMPTS and not isinstance(e, (ValueError, PermissionError, ConfigError))
        msg = str(e) or type(e).__name__  # e.g. httpx.ReadTimeout has an empty message
        await db.execute("UPDATE jobs SET status=:s, error=:e WHERE id=:id",
                         {"id": job["id"], "s": "queued" if retry else "error", "e": msg[:3900]})
        activity.report(f"{'Will retry' if retry else 'Failed'} {job['label']}: {msg}", "warn" if retry else "error")
        on_fail = getattr(fn, "on_fail", None)
        if on_fail and not retry:
            await on_fail(job, e if str(e) else RuntimeError(msg))
    finally:
        activity.current_job.reset(token)
        RUNNING.pop(job["id"], None)


async def job_label(job: dict) -> str:
    """Human name for a job: the source / output / chat title it works on."""
    table = {"ingest": "sources", "studio": "studio_outputs", "summarize_thread": "chat_threads"}.get(job["kind"])
    if table and job.get("ref_id"):
        try:
            row = await db.fetch_one(f"SELECT * FROM {table} WHERE id=:id", {"id": job["ref_id"]})
            if row and row.get("title"):
                return row["title"]
            if row and table == "studio_outputs":
                return TYPE_LABEL.get(row["type"], row["type"])
        except Exception:
            pass
    return job["kind"]


async def run_forever(concurrency: int = 3) -> None:
    """Runs up to `concurrency` jobs at once, so a long audio render doesn't block source ingestion."""
    while True:  # the DB may be unreachable at boot (network / IP allow-list); keep trying
        try:
            await db.execute("UPDATE jobs SET status='queued' WHERE status='running'")
            break
        except Exception as e:
            log.warning("worker waiting for database: %s", str(e).splitlines()[0])
            activity.report(f"Waiting for database: {str(e).splitlines()[0]}", "error")
            await asyncio.sleep(15)
    slots = asyncio.Semaphore(concurrency)
    running: set[asyncio.Task] = set()
    db_down = False
    while True:
        await slots.acquire()
        try:
            job = await _claim()
            if db_down:
                activity.report("Database connection restored", "success")
                db_down = False
        except Exception as e:
            log.exception("job claim failed")
            if not db_down:  # one event per outage, not one every 5 s
                activity.report(f"Database unreachable: {str(e).splitlines()[0]}", "error")
                db_down = True
            job = None
            await asyncio.sleep(5)
        if job:
            t = asyncio.create_task(_run(job))
            running.add(t)
            t.add_done_callback(lambda t: (running.discard(t), slots.release()))
            continue
        slots.release()
        _wake.clear()
        try:
            await asyncio.wait_for(_wake.wait(), timeout=10)
        except asyncio.TimeoutError:
            pass


# ---- handlers ---------------------------------------------------------------
from .ingest import ingest_source  # noqa: E402
from .memory import summarize_thread  # noqa: E402
from .studio import TYPE_LABEL, output_failed, run_output  # noqa: E402


@handler("ingest")
async def _ingest(job: dict):
    await ingest_source(job["ref_id"])
    return {"source_id": job["ref_id"]}


async def _ingest_failed(job: dict, err: Exception) -> None:
    await db.execute("UPDATE sources SET status='error', error=:e WHERE id=:id",
                     {"id": job["ref_id"], "e": str(err)[:3900]})

_ingest.on_fail = _ingest_failed


@handler("summarize_thread")
async def _summarize(job: dict):
    return await summarize_thread(job["ref_id"])


@handler("studio")
async def _studio(job: dict):
    return await run_output(job["ref_id"])

_studio.on_fail = output_failed
