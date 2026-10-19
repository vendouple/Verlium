"""Personalisation: long-term memories about the user, plus a recap of the previous chat thread.

Both are produced in the background when the user starts a new chat (job "summarize_thread"),
so answering never waits on them. Incognito chats are never stored or summarised.
"""
from __future__ import annotations

import logging
from typing import Any

from . import db
from .providers import get_role

log = logging.getLogger("verlium.memory")
MAX_MEMORIES_IN_PROMPT = 40


async def get_setting(key: str, default: Any = None) -> Any:
    row = await db.fetch_one("SELECT value FROM app_settings WHERE key = :k", {"k": key})
    return default if row is None or row["value"] is None else row["value"].get("v", default)


async def set_setting(key: str, value: Any) -> None:
    await db.execute(
        "MERGE INTO app_settings t USING (SELECT :k key FROM dual) s ON (t.key = s.key) "
        "WHEN MATCHED THEN UPDATE SET value = :v WHEN NOT MATCHED THEN INSERT (key, value) VALUES (:k, :v)",
        {"k": key, "v": {"v": value}})


async def personalisation_enabled() -> bool:
    return bool(await get_setting("personalise", True))


async def context_block(notebook_id: str, thread_id: str | None) -> tuple[str, int, bool]:
    """Text appended to the system prompt; returns (text, memory_count, used_recap)."""
    if not await personalisation_enabled():
        return "", 0, False
    mems = await db.fetch_all(
        "SELECT content FROM memories WHERE deleted = 0 ORDER BY created_at DESC FETCH FIRST :n ROWS ONLY",
        {"n": MAX_MEMORIES_IN_PROMPT})
    recap = await db.fetch_one(
        "SELECT title, summary FROM chat_threads WHERE notebook_id = :nb AND deleted = 0 AND summary IS NOT NULL "
        "AND id <> NVL(:tid, '-') ORDER BY updated_at DESC FETCH FIRST 1 ROWS ONLY",
        {"nb": notebook_id, "tid": thread_id})
    parts = []
    if mems:
        parts.append("What you know about this user from earlier chats (use it to tailor tone, depth and "
                     "examples; never mention it unless asked):\n" + "\n".join(f"- {m['content']}" for m in mems))
    if recap:
        parts.append(f"Recap of the user's previous chat in this notebook (\"{recap['title']}\"): {recap['summary']}")
    return "\n\n".join(parts), len(mems), bool(recap)


async def summarize_thread(thread_id: str) -> dict:
    cfg = await get_role("chat")
    th = await db.fetch_one("SELECT id, title, summary FROM chat_threads WHERE id = :id AND deleted = 0",
                            {"id": thread_id})
    if not cfg or not th:
        return {}
    msgs = await db.fetch_all("SELECT role, content FROM chat_messages WHERE thread_id = :id AND deleted = 0 "
                              "ORDER BY created_at", {"id": thread_id})
    if len(msgs) < 2:
        return {}
    transcript = "\n".join(f"{m['role'].upper()}: {(m['content'] or '')[:1500]}" for m in msgs)[-24000:]
    existing = [m["content"] for m in await db.fetch_all(
        "SELECT content FROM memories WHERE deleted = 0 ORDER BY created_at DESC FETCH FIRST 100 ROWS ONLY")]
    data = await cfg.client().chat_json(cfg.model_id, (
        "Summarise this chat between a user and a research assistant. Reply with JSON only:\n"
        '{"title": "3-6 word title", "summary": "2-3 sentences: what the user wanted and where it ended", '
        '"memories": ["new durable facts about the USER (goals, background, preferred style, level of expertise). '
        'Not facts about the documents. Max 3. Skip anything already known."]}\n\n'
        f"Already known about the user:\n{chr(10).join('- ' + e for e in existing) or '(nothing)'}\n\n"
        f"CHAT:\n{transcript}"), temperature=0.2)
    await db.execute("UPDATE chat_threads SET summary = :s, title = CASE WHEN title = 'New chat' THEN :t ELSE title END "
                     "WHERE id = :id", {"id": thread_id, "s": data.get("summary"), "t": (data.get("title") or th["title"])[:500]})
    added = 0
    if await personalisation_enabled():
        for fact in (data.get("memories") or [])[:3]:
            if isinstance(fact, str) and fact.strip() and fact.strip() not in existing:
                await db.execute("INSERT INTO memories (id, content, source_thread_id) VALUES (:id, :c, :t)",
                                 {"id": db.new_id(), "c": fact.strip()[:1000], "t": thread_id})
                added += 1
    return {"summary": bool(data.get("summary")), "memories_added": added}
