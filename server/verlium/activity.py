"""Live activity feed: what background jobs are doing right now, for the app's debug panel.

Events live in memory (a ring buffer), so they reset on restart; job status itself is durable in the
jobs table. Code running inside a job just calls `report("…")` — the current job is tracked with a
contextvar, so callers don't need to pass ids around.
"""
from __future__ import annotations

import contextvars
import itertools
import time
from collections import deque
from typing import Any

_seq = itertools.count(1)
_events: deque[dict[str, Any]] = deque(maxlen=500)
current_job: contextvars.ContextVar[dict | None] = contextvars.ContextVar("current_job", default=None)


def report(message: str, level: str = "info", progress: float | None = None, **data: Any) -> None:
    """Append an event. level: debug | info | success | warn | error."""
    job = current_job.get()
    if job is not None and progress is not None:
        job["_progress"] = max(0, min(100, round(progress)))
    _events.append({
        "seq": next(_seq),
        "ts": time.time(),
        "level": level,
        "message": message,
        "job_id": job["id"] if job else None,
        "kind": job["kind"] if job else None,
        "notebook_id": job.get("notebook_id") if job else None,
        "progress": job.get("_progress") if job else None,
        **({"data": data} if data else {}),
    })


def since(seq: int, limit: int = 200) -> list[dict[str, Any]]:
    out = [e for e in _events if e["seq"] > seq]
    return out[-limit:]


def last_seq() -> int:
    return _events[-1]["seq"] if _events else 0
