"""Async Oracle connection pool (python-oracledb thin mode) and small query helpers."""
from __future__ import annotations

import array
import uuid
from decimal import Decimal
from typing import Any

import oracledb

from .config import get_settings

oracledb.defaults.fetch_lobs = False  # CLOBs come back as str

_pool: oracledb.AsyncConnectionPool | None = None


def connect_params(user: str | None = None, password: str | None = None) -> dict[str, Any]:
    s = get_settings()
    params: dict[str, Any] = {
        "user": user or s.db_user,
        "password": password or s.db_password,
        "dsn": s.db_dsn,
    }
    if s.db_wallet_dir:
        params |= {
            "config_dir": s.db_wallet_dir,
            "wallet_location": s.db_wallet_dir,
            "wallet_password": s.db_wallet_password or None,
        }
    return params


async def open_pool() -> None:
    global _pool
    if _pool is None:
        _pool = oracledb.create_pool_async(**connect_params(), min=1, max=get_settings().db_pool_max, increment=1)


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def pool() -> oracledb.AsyncConnectionPool:
    if _pool is None:
        raise RuntimeError("Database pool is not open")
    return _pool


def new_id() -> str:
    return str(uuid.uuid4())


def _bind(cur, params: dict | None) -> dict:
    """dict/list values go to JSON columns; array.array values bind as VECTOR automatically."""
    params = params or {}
    sizes = {k: oracledb.DB_TYPE_JSON for k, v in params.items() if isinstance(v, (dict, list))}
    if sizes:
        cur.setinputsizes(**sizes)
    return params


def plain(v: Any) -> Any:
    """Oracle JSON gives non-integer numbers back as Decimal, which json/httpx can't encode."""
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, dict):
        return {k: plain(x) for k, x in v.items()}
    if isinstance(v, list):
        return [plain(x) for x in v]
    return v


def _rows(cursor, rows) -> list[dict[str, Any]]:
    cols = [d[0].lower() for d in cursor.description]
    return [{c: plain(x) for c, x in zip(cols, r)} for r in rows]


async def fetch_all(sql: str, params: dict | None = None) -> list[dict[str, Any]]:
    async with pool().acquire() as conn:
        with conn.cursor() as cur:
            await cur.execute(sql, _bind(cur, params))
            return _rows(cur, await cur.fetchall())


async def fetch_one(sql: str, params: dict | None = None) -> dict[str, Any] | None:
    rows = await fetch_all(sql, params)
    return rows[0] if rows else None


async def execute(sql: str, params: dict | None = None) -> int:
    async with pool().acquire() as conn:
        with conn.cursor() as cur:
            await cur.execute(sql, _bind(cur, params))
            n = cur.rowcount
        await conn.commit()
        return n


async def execute_many(sql: str, rows: list[dict]) -> None:
    if not rows:
        return
    async with pool().acquire() as conn:
        with conn.cursor() as cur:
            sizes = {k: oracledb.DB_TYPE_JSON for k, v in rows[0].items() if isinstance(v, (dict, list))}
            # A VECTOR column whose first row is NULL would otherwise be bound as VARCHAR for the whole batch.
            sizes |= {k: oracledb.DB_TYPE_VECTOR for k in rows[0]
                      if any(isinstance(r.get(k), array.array) for r in rows)}
            if sizes:
                cur.setinputsizes(**sizes)
            await cur.executemany(sql, rows)
        await conn.commit()
