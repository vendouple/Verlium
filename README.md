# Verlium

A cross-device (Windows + Android) research notebook modelled 1:1 on Google's Gemini Notebook (formerly NotebookLM), with bring-your-own models and an Oracle AI Database backend.

| Path | What |
|---|---|
| `docs/RESEARCH.md` | Feature inventory, architecture, model roles, hosting decisions |
| `docs/ui/UI-SPEC.md` | Measured 1:1 UI spec (tokens, layout, components), plus screenshots |
| `docs/SETUP.md` | Database, server and provider setup |
| `server/` | FastAPI + python-oracledb: notebooks, sources, ingestion, RAG chat with citations, model settings |
| `app/` | Flutter client (Windows and Android) |
| `infra/` | systemd, Caddy and keep-alive files for the OCI Always Free A1 VM |

## Status: Phase 1 (core)

- [x] Oracle schema: notebooks, sources, chunks (`VECTOR`, Oracle Text), notes, chat, providers, roles, jobs, plus a sync change-sequence
- [x] Model settings: providers with encrypted keys, per-role models, Fetch models, Test buttons (chat, vision, embeddings, TTS, STT, image)
- [x] Sources: PDF, text/markdown, websites, YouTube transcripts, pasted text. Background ingestion, then the source guide and the notebook auto title/emoji/summary
- [x] Chat: hybrid retrieval (vector + Oracle Text, RRF) or full-context when it fits, streaming, numbered citations that open the passage
- [x] Notes: create/edit, save answers to notes, convert a note to a source
- [x] Resizable panels (drag the gaps; double-click to reset; widths remembered)
- [x] Chat threads (history + New chat), live Thinking + steps, reasoning effort, Incognito, personalisation (memories + last-chat recap)
- [x] Studio: Reports, Flashcards, Quiz, Mind Map, Data Table, Audio Overview (2 hosts, TTS + ffmpeg) with viewers
- [x] Studio: Slide Deck, Infographic, Video Overview (image/video models)
- [x] Chat visuals: LaTeX maths, charts (data or plotted functions), interactive HTML widgets with sliders (sandboxed WebView)
- [x] Activity dock: live jobs, progress, debug log, server/database health, toast notifications
- [ ] Phase 2: local SQLite + outbox sync, upload-then-evict, Android polish
- [ ] Phase 5: Deep Research, interactive audio (realtime), sharing

## Quick start (dev)

```bash
cd server
python -m venv .venv && .venv/Scripts/pip install -e ".[dev]"
cp .env.example .env   # fill in; see docs/SETUP.md
.venv/Scripts/python -m verlium.migrate --bootstrap-user
.venv/Scripts/python -m uvicorn verlium.main:app --reload --port 8000

cd ../app
flutter run -d windows
```
