# Verlium — Research Brief (Gemini Notebook clone)

> Status: research only, no code yet. This is the base document for a later agent handoff.
> Date: 2026-10-14 (updated 2026-10-15 with a live UI capture)
>
> **UI:** the 1:1 UI spec is in [ui/UI-SPEC.md](ui/UI-SPEC.md). It covers design tokens, layout, every screen and behaviour, measured from the live app. Raw measurements are in [ui/_raw-capture-notes.md](ui/_raw-capture-notes.md) and screenshots in [ui/screens/](ui/screens/). Where §1.1 below conflicts with the live capture, the UI spec wins. In particular, Configure Chat's custom goal allows **10,000 characters**, not 300. The live app also offers Studio types that §1.1 does not list: Slide Deck (Detailed / Presenter), Infographic (11 styles), Data Table, and Interactive Reports.

## 1. What we are cloning

**Gemini Notebook** (formerly NotebookLM; renamed 2026-07-16, now at `notebook.google.com`). It is a source-grounded research workspace: you add sources to a notebook, then chat with them and generate "Studio" outputs from them. Google's product is closed source, so we can't fork it. We can rebuild it, using open-source clones as a reference.

### 1.1 Feature inventory (target for "1:1-ish")

| Area | Gemini Notebook behaviour | Verlium priority |
|---|---|---|
| **Notebooks** | Many notebooks per user. Each has a title, an emoji or cover, sources, chat, notes and studio outputs. | P0 |
| **Sources** | PDF, DOCX, TXT/MD, pasted text, web URL, YouTube URL, Google Docs and Slides, images (OCR), CSV/Sheets, audio files. Limits: 50 sources per notebook (free) up to 300+ (paid), 500k words per source, 200 MB per file. | P0 (Google Docs import is P2) |
| **Source selection** | Checkboxes scope which sources the chat and outputs use. | P0 |
| **Source guide** | When a source is added, it gets an auto summary, key topics and suggested questions. | P0 |
| **Chat** | Answers are grounded only in the sources, with inline numbered citations. Hovering or clicking a citation jumps to the exact passage. History persists. | P0 |
| **Configure chat** | Goal: Default, Learning guide, or Custom (a prompt of about 300 chars). Length: Default, Shorter, or Longer. | P0 |
| **Notes** | Save a chat reply as a note, write your own notes, and convert a note into a source. | P0 |
| **Discover / Fast Research / Deep Research** | Web search for new sources. Deep Research runs in the background, writes a report, and imports the report plus its cited sources. | P2 (needs a search API) |
| **Audio Overview** | A two-host "podcast". Formats: Deep Dive, Brief, Critique, Debate. Length: short, default or long. Supports 80+ languages and custom steering instructions. **Interactive mode** lets you interrupt the hosts with a question. | P1 (P3 for interactive) |
| **Video Overview** | Formats: Explainer, Short/Brief (about 60 s, vertical), Cinematic (1–3 min, fully animated). Styles include Classic, Whiteboard, Watercolor, Anime and more. | P2 |
| **Mind map** | An interactive, expandable topic tree built from the sources. | P1 |
| **Reports** | Briefing doc, study guide, FAQ, timeline, and custom report prompts. A report can be added back as a source. | P1 |
| **Flashcards / Quiz** | Generated from the sources. Each card has an "explain" option with citations. | P1 |
| **Infographic / Slide deck / Data table** | Generated visual and structured outputs. | P2 |
| **Cloud computer** | A per-notebook sandbox that runs code against the sources (math, charts). Added in July 2026. | P3 |
| **Real-time voice conversation** | Live voice chat with the notebook (Sept 2026). | P3 |
| **Mobile audio recording** | Record audio on the phone and turn it into a source (Sept 2026). | P1 (cheap once STT exists) |
| **Sharing** | Share with specific users or by public link. | P3 (single-user first) |
| **Output language** | A global setting for which language outputs are generated in. | P1 |

Note: Google's **Explainer video is not generated video**. It is narrated slides: an LLM writes the script, images are generated per slide, and TTS narrates over them. Only **Cinematic** uses a true video model (Veo). We can copy that split: Explainer = LLM + image model + TTS + ffmpeg, and Cinematic = the optional video model.

## 2. Open-source references (things to borrow from)

| Project | License | Stack | Why look at it |
|---|---|---|---|
| **[Open Notebook](https://github.com/lfnovo/open-notebook)** (~40k ★) | MIT | FastAPI + LangChain, Next.js/React, SurrealDB, `esperanto` provider library | Closest 1:1 clone: notebooks, sources, chat with citations, notes, "transformations", podcasts with 1–4 speakers, 20+ providers, model settings in the UI, and API keys encrypted at rest. **The best reference.** |
| [SurfSense](https://github.com/MODSetter/SurfSense) | Apache-2.0 | Python + Next.js, Postgres/pgvector | Connectors (Slack, Notion, YouTube…) and a desktop build. |
| Khoj | AGPL-3.0 | Python/Django | "Second brain" ideas. Avoid copying code because of the AGPL license. |
| AnythingLLM, kotaemon | MIT / Apache | various | RAG pipeline and document parsing ideas. |

**Recommendation: use Open Notebook as a reference, not as a literal fork.** Its UI is web-only, it is built around SurrealDB, and it has no offline or mobile story. Swapping in Oracle and adding native Android and Windows clients with local sync would replace most of the code anyway. What carries over well:

- the domain model (notebook → sources → chunks/embeddings; notes; transformations)
- the podcast pipeline (outline → transcript → per-speaker TTS → merge)
- the provider abstraction and the model-roles settings page
- the prompts

The MIT license allows copying any of it with attribution.

## 3. Database: Oracle AI Database 26ai Free

The free edition (formerly "23ai Free") has these **limits: 2 CPUs, 2 GB RAM, 12 GB of user data.** It runs on Windows x64 natively, on Linux, or in Docker (`container-registry.oracle.com/database/free`, or the community `gvenzl/oracle-free` image).

Built-in features that fit this app:

- **`VECTOR` data type plus HNSW/IVF vector indexes**, with `VECTOR_DISTANCE` in SQL. RAG retrieval runs in the DB.
- **Oracle Text** (`CONTAINS`) for full-text search. Combining it with vector search gives hybrid search.
- **`DBMS_VECTOR_CHAIN`**: in-DB chunking and text extraction (optional; doing it in the app is more portable).
- **In-DB ONNX embedding models** (`DBMS_VECTOR.LOAD_ONNX_MODEL`, e.g. all-MiniLM). These give **free embeddings with no API key** as a fallback. It is tight on 2 GB RAM, so test it.
- **JSON Relational Duality Views**: JSON documents over relational tables, with optimistic concurrency via ETAGs. A good fit as the sync wire format.
- Drivers: **python-oracledb thin mode** (pure Python, no Instant Client needed, supports `VECTOR` since 2.2) and node-oracledb thin. Java JDBC also exists.

### Hard constraints that shape the design

1. **Android cannot talk to Oracle directly in any sane way.** There is no supported Dart or Android driver, and exposing port 1521 to the internet is a security problem. Clients must go through an **app server (our API)** that sits next to the DB. Oracle's old mobile sync products (Database Mobile Server, MCS) are legacy, so we build our own sync.
2. **12 GB cap.** Text, chunks, vectors and metadata fit easily. Raw files (PDFs, audio, generated MP3/MP4) will blow through the cap. **Store binaries on the server filesystem or an S3-compatible store (MinIO), and keep only metadata and hashes in Oracle.** As a rough guide, 384-dim float32 vectors take about 1.5 KB per chunk, and 1536-dim about 6 KB.
3. **Reaching the server from your phone when you're out**: use Tailscale (or WireGuard) to your home box, or host on a VPS / Oracle Cloud Always Free. Don't port-forward Oracle.

## 4. Proposed architecture

```
┌────────────── Client (Android + Windows, one codebase) ───────────────┐
│ UI ─ local SQLite (notebooks, notes, chat, source metadata, outbox)   │
│      local file cache (uploads pending, downloaded audio/video)       │
│      secure key store (Android Keystore / Windows DPAPI)              │
│      Sync engine: outbox push → pull changes since cursor             │
└───────────────────────────────┬───────────────────────────────────────┘
                                │ HTTPS (Tailscale / VPS)
┌───────────────────────────────▼───────────────────────────────────────┐
│ Verlium API server (Python FastAPI)                                   │
│  • REST + SSE streaming for chat                                      │
│  • /sync endpoints (push ops, pull since change_seq)                  │
│  • Ingestion workers: parse → chunk → embed → index                   │
│  • Studio job queue: audio/video/mindmap/report/quiz generation       │
│  • Provider gateway: calls the user-configured model endpoints        │
│  • Blob store (filesystem / MinIO)                                    │
└───────────────────────────────┬───────────────────────────────────────┘
                     python-oracledb (thin)
                    Oracle AI Database 26ai Free
```

### "Files on device sync, then clear"

1. Adding a source while offline: the file is copied into the app cache, a `source` row is written to local SQLite with `status=pending_upload`, and an outbox op is queued.
2. When the client is connected, it does a resumable chunked upload. The server stores the blob, records its hash, and replies `uploaded`.
3. The client marks the source `synced`. **The local copy is then evicted.** You might keep a small preview, and pinning stays optional for offline reading.
4. Server-side ingestion fills in the extracted text, chunks and embeddings. The client pulls the source guide and summary through normal sync.
5. Generated outputs (MP3/MP4) stay on the server. The client streams them or downloads them on demand, like Google's "download audio for offline" option.

### Sync model (keep it simple; single user, multiple devices)

- Each entity gets a UUID (client-generated), `updated_at`, a `version`, and a `deleted` tombstone.
- The server keeps a monotonic `change_seq`. Clients pull with `?since=<seq>`.
- Conflicts: last-writer-wins per field for metadata. Notes are the only freeform text that is likely to conflict, so use a version check there and keep both copies on conflict.
- Heavy work (embedding, generation) runs **only on the server**. Clients never need embeddings locally, so offline mode means browsing, notes and queueing, not RAG chat. Optional later: on-device chat via a local model.

## 5. Client stack options (decision needed)

| Option | Android | Windows | Notes |
|---|---|---|---|
| **Flutter** (recommended) | Native-quality | Good | One Dart codebase. Mature SQLite (`drift`), secure storage, background upload, audio recording and playback, and file pickers on both targets. |
| Tauri 2 + React | WebView | Excellent, tiny installer | Could reuse Open Notebook's React UI ideas. Android support is younger, and audio recording and background tasks need more plugin work. |
| Compose Multiplatform | Best native | OK (JVM, larger installer) | Best if you prefer Kotlin. |
| PWA only | OK | OK | Fastest to build, but weak offline file handling and background sync on Android. |

The server is Python either way: python-oracledb has the best Oracle support, and the AI and document-parsing ecosystem (pymupdf, docling/unstructured, yt-dlp, ffmpeg bindings) is there.

## 6. Model settings (bring your own model)

Everything goes through user-configured **OpenAI-compatible endpoints**. That covers OpenAI, OpenRouter, LiteLLM proxy, Ollama, LM Studio, vLLM, Groq, Together and others. Gemini and Anthropic also offer OpenAI-compatible endpoints.

### Data model: Providers × Roles

**Provider profile**: `name, base_url, api_key, (optional headers)`.

**Model role assignment**: `role → provider + model_id + params`.

| Role | Required? | Endpoint | Settings fields | Test button does |
|---|---|---|---|---|
| **Chat / LLM** | Yes | `POST /chat/completions` (stream) | model id, **context window (tokens)**, max output tokens, temperature, supports-tools flag | Sends "Reply with OK", then shows latency, tokens per second and the reply |
| **Vision** | Optional; can reuse the Chat model | `/chat/completions` with an `image_url` part | model id (defaults to the chat model) | Sends a generated test image (e.g. red circle + text "VERLIUM 42") and asks what it shows. Pass if the reply mentions red, circle and 42. ✅/❌ |
| **Embeddings** | Yes, effectively (see below) | `POST /embeddings` | model id, **dimensions** (auto-detected by the test), batch size | Embeds two similar sentences and one unrelated one, then shows the dimension and that the similarity ordering is correct |
| **TTS** | Needed for Audio/Video Overview | `POST /audio/speech` | model id, voice A, voice B, format | Plays a sample of each voice |
| **STT** | Needed for audio/video sources and voice input | `POST /audio/transcriptions` | model id, language | Records 3 s or uses a bundled clip, then shows the transcript |
| **Image generation** | Optional | `POST /images/generations` | model id, size | Generates a thumbnail and shows it |
| **Video generation** | Optional | Async: `POST /videos` → poll → download (OpenAI/LiteLLM schema; OpenRouter uses `/api/v1/videos`, also async) | model id, resolution, duration, adapter type | Submits a 2 s clip and shows job status and the result. Warn about cost first. |
| **Realtime voice** | Optional; powers Interactive Audio "Join" and live voice chat | WebSocket/WebRTC realtime API (OpenAI Realtime-compatible; Gemini Live via adapter) | model id, voice A (male host), voice B (female host), transport | Opens a session, speaks a test line in each voice, and echoes back a 3 s mic sample transcript |
| Reranker | Optional, later | `/rerank` (Cohere/Jina style) | model id | Ranks 3 docs |

Implementation notes:

- **Provider "adapter" field** (`openai`, `openrouter`, `litellm`, `ollama`, `gemini-native`…). Images and especially video differ in request shape across vendors, so a dropdown is needed even with "OpenAI-compatible" endpoints.
- **"Fetch models" button** that calls `GET /models` to fill the model-id picker.
- **Context window drives RAG**: the retrieval budget is roughly `context − system prompt − history − reserved output`. With small local models, retrieve less. With 1M-context models, you can stuff whole sources like Google does.
- **Changing the embedding model forces a re-embed.** Oracle `VECTOR(dim)` columns are dimension-typed, so store `embedding_model_id` and `dim` per chunk set and show "Re-index N sources?".
- **Where keys live**: start device-local in secure storage. If settings should sync across devices, encrypt them server-side with a user passphrase (as Open Notebook does), and never store keys in plaintext in Oracle.
- Per-role fallback to the Chat provider means a user with a single OpenRouter key can configure everything quickly.

## 7. My take on embeddings / TTS / STT

- **Embeddings: yes, required.** Google can rely on Gemini's 1M context. A BYO model might have 8k–128k. Without retrieval, chatting over 50 sources doesn't work. Use hybrid retrieval (Oracle vector + Oracle Text) and keep citations as chunk IDs with char offsets, so a click can jump to the exact passage. If no embedding API is configured, fall back to the **in-DB ONNX model**, so the app still works with zero extra keys.
- **TTS: yes.** The Audio Overview is the flagship feature and needs two distinct voices. OpenAI-compatible `/audio/speech` covers OpenAI, OpenRouter, Kokoro and Orpheus via local servers, and ElevenLabs via LiteLLM.
- **STT: yes.** It is needed for audio sources, YouTube videos without captions, mobile voice recordings, and voice questions. It also enables the later "interactive audio overview" (STT → LLM → TTS loop).
- **Image generation: optional**, but it unlocks infographics, slide decks and Explainer video.
- **Video generation: optional, last.** It is only needed for "Cinematic". It is expensive and asynchronous, so implement it as a background job.

## 8. Suggested build phases

1. **Core**: server + Oracle schema + model settings (Chat, Embeddings, Vision) with test buttons. Notebooks, sources (PDF, text, URL, YouTube transcript), ingestion, chat with citations, notes. One client on Windows.
2. **Cross-device**: the same client on Android, local SQLite, outbox sync, upload-then-evict, auth (a single-user token is fine).
3. **Studio I**: source guide, reports, FAQ, timeline, flashcards, quiz, mind map, chat configuration.
4. **Studio II**: TTS + Audio Overview (4 formats), STT sources and audio recording, image generation → infographic and slides, Explainer video (ffmpeg).
5. **Extras**: Deep Research (needs a search API, e.g. SearXNG, Tavily or Brave), Cinematic video, interactive audio, code sandbox, sharing.

## 9. Open decisions for you

> Items 1–4 were resolved on 2026-10-15; see §10. Item 5 (offline chat) still defaults to "no" for v1.

1. Client framework: Flutter (recommended), Tauri, or Compose MP?
2. Where does the server and Oracle run: your Windows PC (Docker/WSL), a home server, or a VPS / Oracle Cloud Always Free?
3. Should API keys sync across devices (encrypted on the server) or be entered on each device?
4. Single user only, or multi-user / sharing later? This affects the schema now (an `owner_id` on everything is cheap insurance).
5. Is offline chat needed, i.e. an on-device model? (Suggested: no for v1.)

## 10. Decisions (2026-10-15)

| Topic | Decision |
|---|---|
| Client | **Flutter**: one codebase for Android and Windows. |
| Hosting | **Oracle Cloud Always Free** (details below). |
| Users / keys | **Single user, keys synced.** Keys are entered once and stored **encrypted on the server**; devices never hold raw provider keys (see the Pollinations note below). |
| First provider | **Custom base URL; testing with Pollinations** (`https://gen.pollinations.ai/v1`, key from enter.pollinations.ai). |

### 10.1 Hosting on OCI Always Free (no paid VPS)
Oracle Always Free includes everything this needs:

| Piece | Always Free resource | Notes |
|---|---|---|
| **Database** | **Autonomous AI Database (26ai)**, managed. 2 instances, each with 1 OCPU, **20 GB** (more than the 12 GB local Free edition), 20 sessions. | No database admin needed. Includes VECTOR search, Oracle Text, JSON Duality and built-in ORDS REST. The ORDS HTTP interface is rate-limited to roughly 3–6 simultaneous users, which is fine for one user. Connect from the server with python-oracledb using a wallet or TLS. |
| **API server + workers** | **Ampere A1 VM**: 1,500 OCPU-h and 9,000 GB-h per month, about **2 OCPU / 12 GB** total (the old "4 OCPU / 24 GB" figure is outdated). Block storage 200 GB. | Runs FastAPI, the ingestion and Studio job workers, and ffmpeg. **Idle instances can be reclaimed** if CPU, network and memory all stay under 20% (95th percentile) for 7 days, so keep a light periodic job running or accept the risk. |
| **Files** | **Object Storage**, 20 GB (Always Free-only accounts), 50k requests per month. Alternatively the VM's block volume. | Uploaded sources and generated MP3/MP4/PNG files. |
| Bandwidth | 10 TB per month outbound | Plenty. |

**Can it be "just the database, all local" with no server?**

- **Fully local:** possible for development. Run Oracle AI Database Free in Docker plus the API on your PC. The drawback is that your phone only works while the PC is on, and only through Tailscale.
- **Database only, no API server:** technically possible. Autonomous DB's ORDS REST lets the Flutter app read and write data directly, and each device would call Pollinations itself. It isn't recommended:
  1. Pollinations says `sk_` keys must **never** ship in a mobile app.
  2. Studio jobs (audio and video rendering) would stop when the app closes.
  3. ffmpeg video assembly is heavy on Android.
  4. Every device would duplicate the ingestion work.

  The free A1 VM costs nothing and fixes all four.
- **Recommended:** Autonomous AI DB, plus the A1 VM for the API and workers, plus Object Storage. Everything is free. Use a local Docker Oracle Free only as the developer environment.

### 10.2 Pollinations as the test provider
It is one key and one base URL that covers every model role. Docs: gen.pollinations.ai/docs, and APIDOCS.md in the pollinations GitHub repo.

| Verlium role | Pollinations endpoint |
|---|---|
| Chat / Vision | `POST /v1/chat/completions` (streaming, tools, vision, structured output, reasoning). It also offers `/v1/responses` and an Anthropic-style `/v1/messages`. |
| Embeddings | `POST /v1/embeddings` (e.g. `openai/text-embedding-3-small`) · `GET /embeddings/models` |
| TTS | `POST /v1/audio/speech`: OpenAI voices (alloy, echo, fable, onyx, nova, shimmer) plus 30+ ElevenLabs voices, which is good for the male and female hosts. |
| STT | `POST /v1/audio/transcriptions`: whisper and assemblyai models; `srt`/`vtt` output for some models; max 25 MB. |
| Image | `POST /v1/images/generations` (OpenAI-compatible, `size`, `b64_json` or `url`) and `/v1/images/edits`, or `GET /image/{prompt}?model=…` |
| Video | `GET /video/{prompt}?model=…&duration=…` with header `Prefer: respond-async`, then poll `GET /v1/jobs/{id}` and download `GET /v1/jobs/{id}/result`. Models include Veo 3.1 fast, Seedance 2.x, Wan 2.7/3.0, Grok Imagine and others. A **"pollinations-async" video adapter** is needed. |
| Realtime voice | `GET /v1/realtime` WebSocket using the **OpenAI Realtime protocol** (`openai/gpt-realtime-2.1`). This powers Interactive Audio "Join". |
| Model pickers | `GET /v1/models` (each entry has `supported_endpoints`, so the "Fetch models" button can filter by role automatically), plus `/text/models`, `/image/models`, `/video/models` and `/audio/models`, which include voices and pricing. |
| Usage meter | `GET /account/balance` and `/account/key/usage`. These can feed the Verlium "Usage" dialog, which replaces Google's AI usage meter. |
| Async media | Any long image, video or audio request can use `Prefer: respond-async` plus `/v1/jobs`. |

Auth is `Authorization: Bearer sk_…`. **`sk_` keys are server-only.** This confirms the design: the Verlium server holds the keys and the apps talk only to the Verlium server.

## Sources

- [Rename / what changed — DEV Community](https://dev.to/alifar/google-expands-gemini-notebook-with-syncing-interactive-tools-and-a-new-name-1dm)
- [Code execution + rename — DEV Community](https://dev.to/alifar/google-renames-notebooklm-to-gemini-notebook-with-code-execution-and-cross-app-sync-19ak)
- [Features & plan limits — Elephas](https://elephas.app/blog/what-is-notebooklm)
- [Audio Overview formats (Debate etc.) — 9to5Google](https://9to5google.com/2025/09/02/notebooklm-audio-overview-debate/)
- [Video/Audio Overviews 80 languages — Google blog](https://blog.google/technology/google-labs/notebook-lm-audio-video-overviews-more-languages-longer-content/)
- [Chat goals & custom personas — Google blog](https://blog.google/technology/google-labs/notebooklm-custom-personas-engine-upgrade/)
- [Deep Research + file types — Google blog](https://blog.google/innovation-and-ai/models-and-research/google-labs/notebooklm-deep-research-file-types/)
- [Short video overviews — eesel](https://www.eesel.ai/blog/notebooklm-short-video-overviews)
- [Open Notebook — GitHub](https://github.com/lfnovo/open-notebook)
- [OSS alternatives comparison](https://rohitraj.tech/en/notes/open-notebook-vs-khoj-vs-surfsense-notebooklm-2026)
- [Oracle AI Database Free](https://www.oracle.com/database/free/)
- [Oracle AI Vector Search tutorial — DataCamp](https://www.datacamp.com/tutorial/oracle-ai-vector-search-tutorial)
- [python-oracledb VECTOR guide](https://python-oracledb.readthedocs.io/en/stable/user_guide/vector_data_type.html)
- [JSON Relational Duality](https://www.oracle.com/database/json-relational-duality/)
- [OpenRouter: every modality via one API](https://openrouter.ai/blog/insights/every-modality-one-api/)
- [OpenRouter audio APIs](https://openrouter.ai/blog/announcements/announcing-audio-apis)
- [OpenRouter video generation](https://openrouter.ai/docs/features/multimodal/video-generation)
- [LiteLLM video endpoints](https://docs.litellm.ai/docs/videos)
- [Pollinations API docs (APIDOCS.md)](https://github.com/pollinations/pollinations/blob/main/APIDOCS.md)
- [OCI Always Free resources](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Always Free Autonomous AI Database](https://docs.oracle.com/iaas/autonomous-database-shared/doc/autonomous-always-free.html)
