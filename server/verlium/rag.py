"""Grounded chat: retrieval (full-context or hybrid vector + Oracle Text), prompt, citations."""
from __future__ import annotations

import array
import re
from dataclasses import dataclass
from typing import Any

from . import db
from .providers import RoleConfig, get_role

CHARS_PER_TOKEN = 3.5
STOP = set("the and for are but not you all any can had her was one our out has have this that with from they "
           "what when where which who why how does did into about would could should their there them then than".split())


@dataclass
class Chunk:
    id: str
    source_id: str
    source_title: str
    text: str
    char_start: int
    char_end: int
    page: int | None
    seq: int


def _bind_list(prefix: str, values: list[str]) -> tuple[str, dict]:
    names = {f"{prefix}{i}": v for i, v in enumerate(values)}
    return ",".join(f":{k}" for k in names) or "NULL", names


CHUNK_COLS = ("c.id, c.source_id, s.title source_title, c.text, c.char_start, c.char_end, c.page, c.seq "
              "FROM chunks c JOIN sources s ON s.id = c.source_id")


def _chunk(r: dict) -> Chunk:
    return Chunk(r["id"], r["source_id"], r["source_title"] or "Source", r["text"], r["char_start"], r["char_end"],
                 r["page"], r["seq"])


def text_query(q: str) -> str | None:
    words = [w.lower() for w in re.findall(r"[A-Za-z0-9]{3,}", q) if w.lower() not in STOP][:20]
    return " ACCUM ".join("{" + w + "}" for w in dict.fromkeys(words)) or None


async def retrieve(notebook_id: str, query: str, source_ids: list[str], budget_chars: int) -> list[Chunk]:
    if not source_ids:
        return []
    in_sql, binds = _bind_list("s", source_ids)
    base = {"nb": notebook_id, **binds}
    total = await db.fetch_one(
        f"SELECT NVL(SUM(char_count), 0) n FROM sources WHERE id IN ({in_sql}) AND status='ready'", binds)

    if total and total["n"] <= budget_chars:  # everything fits: give the model the whole sources
        rows = await db.fetch_all(f"SELECT {CHUNK_COLS} WHERE c.source_id IN ({in_sql}) "
                                  "ORDER BY s.created_at, c.seq", binds)
        return _dedupe_overlap([_chunk(r) for r in rows])

    ranked: dict[str, float] = {}
    rows_by_id: dict[str, dict] = {}
    k = 60

    emb = await get_role("embeddings")
    if emb:
        qv = (await emb.client().embed(emb.model_id, [query], emb.params.get("dimensions")))[0]
        rows = await db.fetch_all(
            f"SELECT {CHUNK_COLS} WHERE c.notebook_id = :nb AND c.source_id IN ({in_sql}) AND c.embed_model = :em "
            "ORDER BY VECTOR_DISTANCE(c.embedding, :qv, COSINE) FETCH FIRST 40 ROWS ONLY",
            {**base, "em": emb.model_id, "qv": array.array("f", qv)})
        for rank, r in enumerate(rows):
            ranked[r["id"]] = ranked.get(r["id"], 0) + 1 / (k + rank)
            rows_by_id[r["id"]] = r

    tq = text_query(query)
    if tq:
        rows = await db.fetch_all(
            f"SELECT {CHUNK_COLS} WHERE c.notebook_id = :nb AND c.source_id IN ({in_sql}) "
            "AND CONTAINS(c.text, :tq, 1) > 0 ORDER BY SCORE(1) DESC FETCH FIRST 40 ROWS ONLY", {**base, "tq": tq})
        for rank, r in enumerate(rows):
            ranked[r["id"]] = ranked.get(r["id"], 0) + 1 / (k + rank)
            rows_by_id[r["id"]] = r

    if not ranked:  # nothing matched: fall back to the beginning of each source
        rows = await db.fetch_all(f"SELECT {CHUNK_COLS} WHERE c.source_id IN ({in_sql}) AND c.seq < 3 "
                                  "ORDER BY s.created_at, c.seq", binds)
        return [_chunk(r) for r in rows]

    picked, used = [], 0
    for cid in sorted(ranked, key=ranked.get, reverse=True):
        r = rows_by_id[cid]
        if used + len(r["text"]) > budget_chars:
            continue
        picked.append(_chunk(r))
        used += len(r["text"])
    picked.sort(key=lambda c: (c.source_id, c.seq))
    return picked


def _dedupe_overlap(chunks: list[Chunk]) -> list[Chunk]:
    """In full-context mode, trim the overlap between consecutive chunks to save tokens."""
    out: list[Chunk] = []
    for c in chunks:
        if out and out[-1].source_id == c.source_id and c.char_start < out[-1].char_end:
            cut = out[-1].char_end - c.char_start
            c = Chunk(c.id, c.source_id, c.source_title, c.text[cut:], out[-1].char_end, c.char_end, c.page, c.seq)
        out.append(c)
    return out


GOALS = {
    "default": "Best for general purpose research and brainstorming tasks.",
    "learning_guide": ("Act as a learning guide: help the user understand the material step by step, ask a "
                       "follow-up question to check understanding, and encourage critical thinking rather than "
                       "just giving answers."),
}
LENGTHS = {"default": "", "longer": "Give detailed, thorough answers.", "shorter": "Keep answers short and concise."}

# Rendered by the app: KaTeX-style math, native charts, and sandboxed interactive HTML widgets.
VISUALS = r"""You can show maths and visuals; the app renders them inline. Use them when they genuinely help (maths, data, processes, "show me", "graph", "visualise") — not for every answer.
- Math: LaTeX with $...$ inline and $$...$$ on its own lines for display equations. Keep prose and maths apart: put each formula, worked example or derivation step in its own display block rather than inline in a sentence. For multi-step working use one block with \begin{aligned} ... \end{aligned}, one step per line, aligned on "=", with the rule used as \quad\text{(Sum Law)} at the end of the line; put the final answer in \boxed{...}. Use cases for piecewise functions.
- Chart: a fenced block with language `chart` containing JSON only:
  {"type": "line|area|scatter|bar|pie", "title": "...", "x_label": "...", "y_label": "...",
   "series": [{"name": "...", "data": [[x, y], ...]}            // points (line/area/scatter)
              {"name": "f(x)=x^2", "fn": "x^2", "domain": [-3, 3]}  // plotted function: + - * / ^ sin cos tan sqrt abs ln log exp pi e
              {"name": "Sales", "data": [3, 5, 2]}],              // bar/pie values, with "labels": ["Q1", "Q2", "Q3"] at top level
   "x_range": [min, max], "y_range": [min, max]}                  // optional
- Interactive widget: for anything that benefits from interaction (sliders, toggles, animation, step-through, simulations, diagrams, drawings), a fenced block with language `widget` containing one self-contained HTML fragment (inline <style>, <svg>/<canvas>, <script>; no external files or network). The page already has theme CSS variables --bg, --panel, --text, --muted, --primary, --accent, --success, --warn, --danger, --border and styled inputs; use them so it fits light and dark mode. Keep it compact (≤ 520px tall), label controls, show live values, and add one sentence explaining what to try.
Put a short explanation in normal text around visuals. Never wrap these blocks in other code fences."""


def system_prompt(chat_config: dict[str, Any] | None, personal: str = "") -> str:
    cc = chat_config or {}
    goal = cc.get("goal", "default")
    goal_text = cc.get("custom_prompt", "")[:10000] if goal == "custom" else GOALS.get(goal, "")
    return "\n".join(filter(None, [
        "You are Verlium, a research assistant that answers questions about the user's sources.",
        "Ground every factual statement in the numbered source excerpts provided. Cite them inline with "
        "square-bracket numbers right after the claim, e.g. [3] or [2][5]. Never invent citation numbers.",
        "If the sources do not contain the answer, say so plainly, then you may add general knowledge clearly "
        "labelled as not from the sources.",
        "Use Markdown: short paragraphs, **bold** key terms, bullet lists where helpful.",
        VISUALS if cc.get("visuals", True) else "",
        goal_text,
        LENGTHS.get(cc.get("length", "default"), ""),
        personal,
    ]))


def build_messages(cfg: RoleConfig, chat_config: dict | None, history: list[dict], question: str,
                   chunks: list[Chunk], personal: str = "", images: list[str] | None = None,
                   attachment_text: str = "") -> list[dict]:
    excerpts = "\n\n".join(
        f"[{i}] (source: {c.source_title}{f', page {c.page}' if c.page else ''})\n{c.text.strip()}"
        for i, c in enumerate(chunks, start=1))
    msgs = [{"role": "system", "content": system_prompt(chat_config, personal)}]
    msgs += [{"role": h["role"], "content": strip_citations(h["content"] or "")} for h in history]
    text = (f"SOURCE EXCERPTS:\n{excerpts or '(no sources selected)'}\n\n"
            + (f"{attachment_text}\n\n" if attachment_text else "") + f"QUESTION:\n{question}")
    if images:  # OpenAI-style multimodal content
        msgs.append({"role": "user", "content": [{"type": "text", "text": text},
                                                 *({"type": "image_url", "image_url": {"url": u}} for u in images)]})
    else:
        msgs.append({"role": "user", "content": text})
    return msgs


# Fenced blocks (charts, widgets, code), inline code and LaTeX are never touched by citation handling,
# so JSON arrays like [1,2,3] and intervals like $[0,1]$ survive.
PROTECTED_RE = re.compile(r"```.*?(?:```|\Z)|`[^`\n]*`|\$\$.*?\$\$|\\\[.*?\\\]|\\\(.*?\\\)|\$[^$\n]+\$", re.S)


def sub_outside_code(pattern: re.Pattern, repl, text: str) -> str:
    out, pos = [], 0
    for m in PROTECTED_RE.finditer(text):
        out.append(pattern.sub(repl, text[pos:m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(pattern.sub(repl, text[pos:]))
    return "".join(out)


_STRIP_RE = re.compile(r"\s?\[\d+(?:\s*[,–-]\s*\d+)*\]")


def strip_citations(text: str) -> str:
    return sub_outside_code(_STRIP_RE, "", text)


CITE_RE = re.compile(r"\[(\d+(?:\s*,\s*\d+)*)\]")


def finalize_citations(text: str, chunks: list[Chunk]) -> tuple[str, list[dict]]:
    """Renumber citations 1..k in order of first appearance and return the citation table."""
    mapping: dict[int, int] = {}
    cites: list[dict] = []

    def repl(m: re.Match) -> str:
        out = []
        for n in (int(x) for x in re.split(r"\s*,\s*", m.group(1))):
            if not 1 <= n <= len(chunks):
                continue
            if n not in mapping:
                mapping[n] = len(mapping) + 1
                c = chunks[n - 1]
                cites.append({"n": mapping[n], "chunk_id": c.id, "source_id": c.source_id,
                              "source_title": c.source_title, "char_start": c.char_start, "char_end": c.char_end,
                              "page": c.page, "quote": c.text.strip()[:600]})
            out.append(f"[{mapping[n]}]")
        return "".join(out)

    return sub_outside_code(CITE_RE, repl, text), cites


def budgets(cfg: RoleConfig, history_chars: int) -> int:
    ctx_tokens = int(cfg.params.get("context_window") or 32000)
    out_tokens = int(cfg.params.get("max_tokens") or 4096)
    usable = max(ctx_tokens - out_tokens - 1500, 2000)  # 1500 ≈ system prompt + question
    return max(int(usable * CHARS_PER_TOKEN) - history_chars, 4000)
