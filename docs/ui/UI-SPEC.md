# Verlium UI Spec (1:1 clone of Gemini Notebook)

Source of truth: measured from the live app on 2026-10-14/15. Raw measurements are in [_raw-capture-notes.md](_raw-capture-notes.md) and screenshots in [screens/](screens/).
All px values were measured at a 1280×800 viewport. The goal is a UI that looks and behaves the same, so users can move over with no relearning. Branding is our own: the name "Verlium", our own logo, and no Google logos or names.

---

## 1. Design tokens

### 1.1 Typography
- **Family:** Google's app uses `Google Sans Flex`, which is proprietary. Use **`Google Sans Flex` if available, otherwise fall back to `"Google Sans", Roboto Flex, Roboto, system-ui`**. Bundle **Roboto Flex**, a free variable font, so non-standard weights like 370, 470 and 540 still render.
- **Icons:** Material Symbols Rounded, a variable icon font. Google's internal "Google Symbols / Luminous Symbols" fonts map almost 1:1 onto it by name (`audio_spark`, `flowchart`, `quiz`, `keep_pin`, `side_nav`, `collapse_content`, ...). A few names exist only in Google's fonts. For those, pick the nearest Material Symbol.

| Token | Weight / size / line-height | Used for |
|---|---|---|
| display-title | 320 36/44 | Notebook title in the chat header |
| zero-state-h1 | 400 32/40 | "Let's start your notebook..." |
| report-h1 | 350 28/36 | Report viewer H1 |
| report-h2 | 380 24/28 | Report viewer H2 |
| section-h2 | 400 24/32 | Home "Recent notebooks" |
| logo-text | 475 23/29 | Wordmark |
| title-bar | 400 22/36 | Notebook title in header, source title, note title |
| card-title | 470 20/24 | Notebook card title, dialog titles |
| answer-body | 400 17/24 (bold 540) | Chat answers |
| input | 400 16/24 | Query box |
| label-15 | 400 15/20 | Panel headers ("Sources"), card subtitles, table td |
| button | 370 15 | Buttons |
| body-14 | 400 14/24 | Summary, source rows, suggestion cards |
| tile-label | 400 13/17 | Studio tiles, Studio list titles |
| small | 400 12/16 | Studio list meta, counters |
| caption | 500 11/16 | Citation numbers, badges |

### 1.2 Color: dark theme (default)
| Token | Value | Role |
|---|---|---|
| `bg` | `#0f0f0f` | Page and chat column background |
| `panel` | `#1f1f1f` | Sources and Studio panels, menus |
| `tonal` | `#171717` | Tonal buttons, tiles, notebook cards, user bubble, citation chips, query surface |
| `dialog` | `#0f0f0f` (some inner containers `#1f1f1f`) | Dialog surface |
| `text` | `#c7c7c7` | Body text |
| `text-strong` | `#e6e6e6` | Labels and titles |
| `text-title` | `#f2f2f2` | Headings |
| `text-muted` | `rgba(255,255,255,.55)` | Secondary text |
| `icon-muted` | `#ababab` | ⋮ icons, citation numbers |
| `outline` | `rgba(255,255,255,.12)` | Outlined buttons and inputs (0.67px) |
| `divider` | `#37383b` | Table rows, chip outlines |
| `primary` | `#4259ff` | Filled CTAs (Save, Next, play button, selected chip) |
| `primary-tonal` | `#1f3b9b` | "New notebook" button, selected format card |
| `link` | `#c3cafc` | Links |
| `source-guide` | `#2f334b` | Source guide card |
| `unread-dot` | `#3186ff` | Unread dot in the Studio list |
| `success` / `error` | `#80da88` / `#f2b8b5` (quiz borders: green / red) | Quiz feedback |
| `scrim` | `rgba(0,0,0,.6)` | Behind dialogs |

### 1.3 Color: light theme
| Token | Value |
|---|---|
| `bg` | `#faf9f9` |
| `panel` | `#ffffff` |
| `tonal` | `#f2f0f0` |
| `text` | `#303030` |
| `text-strong` / `text-title` | `#000` / `#1b1b1c` |
| `text-muted` | `rgba(0,0,0,.55)` |
| `outline` | `rgba(0,0,0,.08)` |
| `primary-tonal` | `#9dd2ff` (with black text) |
| citation chip | bg `#f2f0f0`, text `#5e5e5e` |
| `scrim` | `rgba(0,0,0,.32)` |

### 1.4 Studio type colors (icon tint)
| Type | Icon | Dark | Light |
|---|---|---|---|
| Audio Overview | `audio_spark` | `#76a0ff` | `#2e64de` |
| Slide Deck | `tablet` | `#f872b9` | `#c43d92` |
| Video Overview | `videocam` | `#3fdda0` | `#0aac6e` |
| Mind Map | `flowchart` | `#a47dff` | `#6858c7` |
| Reports | `auto_tab_group` | `#f872b9` | `#c43d92` |
| Flashcards | `copy` / `cards_star` | `#ecdf77` | `#ff8104` |
| Quiz | `quiz` | `#4dd2e1` | `#167f9b` |
| Infographic | `stacked_bar_chart` | `#ecdf77` | `#ff8104` |
| Data Table | `format_list_bulleted` / `table_view` | `#76a0ff` | `#2e64de` |
| Note | `article` | text color | text color |

### 1.5 Shape, elevation, state
- **Radii:**
  - 40: notebook cards, user bubble
  - 32: side panels, zero-state chips
  - 28: dialogs
  - 24: discovery box, suggestion cards, chips with outline
  - 20: menus, Studio tiles, Studio list items
  - 16: source guide, answer card, drop zone
  - 12: menu items, quiz options
  - 8: source rows, citation popover
  - pill (9999): buttons, inputs, segmented controls
  - circle: citation chip, send button, play button
- **Menu shadow:** `0 0 20px rgba(0,0,0,.28)`.
- **Card elevation:** `0 .125rem .25rem rgba(0,0,0,.1)`.
- **Dialog elevation:** `0 .5rem 1rem rgba(0,0,0,.2)`.
- **State layers:**
  - Hover: 8% of the on-color.
  - Focus and pressed: 12%.
  - Drag-over a drop target: `rgba(66,89,255,.08)` light, `rgba(195,202,255,.08)` dark.
- **Heights:**
  - Buttons: 36 (standard), 40 (dialog), 48 (Generate, Add note), 32 (small).
  - Icon buttons: 36 (32 in dense rows).
  - Source row: 36.
  - Studio tile: 48 (about 56 on mobile).
  - Header: 64.

---

## 2. Layout

### 2.1 Breakpoints
| Width | Notebook layout | Home layout |
|---|---|---|
| ≥ 1051 | 3 panels | Grid, 4 columns at 1280 (cards about 299 wide, gap 8) |
| ≤ 1050 | One column with a tab bar `[Sources | Chat | Studio]`; Chat is the default tab | Grid with fewer columns |
| < 600 | Same as ≤ 1050 | Forced list view |

### 2.2 Notebook page (desktop)
```
┌ Header 64 ─────────────────────────────────────────────────────────────────┐
│ (logo●) Notebook title (editable)        + Create notebook  Share  ⋮  ⚙  ◉ │
├──12──┬──────── 314 ───────┬─8─┬──────── flex ────────┬─8─┬──── 314 ────┬12┤
│      │ Sources       [⇤]  │   │  (scrolling chat)    │   │ Studio [⇥]  │  │
│      │ (+ Add sources)    │   │                      │   │ tiles 2×N   │  │
│      │ ┌discovery box┐    │   │                      │   │ ─────────── │  │
│      │ sort…  Select all☑ │   │                      │   │ output list │  │
│      │ ▢ source rows ☑    │   │ ┌ query box ───────┐ │   │  (Add note) │  │
│      │                    │   │ └──────────────────┘ │   │             │  │
│      │                    │   │ disclaimer           │   │             │  │
└──────┴────────────────────┴───┴──────────────────────┴───┴─────────────┴──┘
```
- Side panels: bg `panel`, radius 32, padding 8, height = viewport − 64 − 12.
- The chat column has no card. Content is centred, about 515 wide for text and 483 for bubbles and answers.
- **Collapse:** the `side_nav` icon in each panel header collapses that panel to an icon rail.
- **Widening:** when the Studio panel opens a viewer (report, note, app, table), it widens 314→480 and Sources narrows 314→262. Clicking the header's `collapse_content` restores both. The expand button opens a large modal (about 1180×700).
- **Source viewer:** opening a source replaces the source list inside the Sources panel.

### 2.3 Mobile / narrow
- **Header:** logo, title (truncated), `+`, share icon, ⋮, settings, avatar.
- **Tab bar:** pill, 343×32, bg `tonal`; each tab 28 high, 14px text; the active tab is lighter.
- **Each tab:**
  - Sources tab: the Sources panel content, full width.
  - Chat tab: chat content, with the query box pinned to the bottom. The source counter shows as `📄 (3)`.
  - Studio tab: tiles in 2 columns (larger), the list below, and a floating "Add note".

---

## 3. Screens and components

### 3.1 Home `/`
- **Header (64):**
  - Logo and wordmark.
  - Filter: inline tabs `All · My notebooks · Discover · Shared with me · Collections` at ≥1400px, a dropdown `All ▾` below that.
  - Search pill "Search notebooks" (256×36, outlined).
  - Grid/list segmented control.
  - ⚙ settings, avatar.
- **Featured notebooks:** "View all ›", one horizontal row of cover cards (radius 40, image with gradient, badge, publisher, title, date · sources, globe icon).
  - For Verlium: drop this section, or reuse it for "Pinned" notebooks.
- **Recent notebooks:** with "+ New notebook" (`primary-tonal`).
- **Notebook card:** 185 high, padding 32, emoji at 36px, ⋮ menu (Edit title, Add to collection, Pin to top, Delete), title, "Oct 14, 2026 · 3 sources", globe icon if shared.
- **List view:** table with columns Title (emoji + title), Sources, Created, Visibility, Role, ⋮.
- **Settings menu (Verlium version):**
  - Help, Send feedback
  - Output language
  - Notifications
  - Theme ▸ (Light / Dark / Device)
  - **Models & providers** (our addition)
  - **Sync & storage** (our addition)
  - Usage (token and cost meter)
  - Licenses

### 3.2 Notebook: Sources panel
1. **Header:** "Sources" plus a collapse icon.
2. **"+ Add sources":** tonal pill, full width. Opens the Add sources dialog.
3. **Discovery box** (radius 24):
   - Textarea "Search the web for new sources".
   - Chip `🌐 Web ▾`: Web "Best sources from the web" / Drive "Your content from Google Drive". For us, replace Drive with "Local files" or omit it.
   - Chip `✦ Fast Research ▾`: Fast Research "Great for quick results" / Deep Research "In-depth report and results".
   - Submit button →.
4. **Toolbar:** sort menu (Recent / Title / Type) and "Select all ☑".
5. **Source row (36):**
   - Type icon (favicon, YouTube, PDF ...). On hover it turns into ⋮ with Remove source / Rename source.
   - Title, ellipsized.
   - Checkbox. While processing, a spinner shows instead.
6. **Empty state:** "Saved sources will appear here", "Add files, websites, or more. Then ask questions or create things based on these sources.", "Drop files here or add a source". The whole panel is a drop target.
7. **Source viewer:**
   - Title (22px) with ↗ open-original.
   - **Source guide** card (collapsible, bg `source-guide`): a summary with **bold key terms**, plus topic chips. Clicking a chip asks chat about that topic.
   - The full extracted text. Citation clicks scroll here and highlight the cited span.

### 3.3 Add sources dialog (700 wide)
- **Title:** "Create Audio and Video Overviews from" with an animated rotating blue phrase ("your documents", "websites", ...).
- **Discovery box:** same as in the panel.
- **Source-type pills** (outlined, 40 high):
  - `Upload files`
  - `Websites` (link + YouTube icons)
  - `Copied text`
  - The `Drive` and `Play Books` pills are Google-only. Replace them with `Local folder` and `Audio recording`, or omit them.
- **Drop zone:** dashed border, radius 16. Text: "Drag & drop your files to upload. Supported file types: pdf, images, docs, audio, and more."
- **Websites sub-view:**
  - "Website and YouTube URLs", textarea "Paste any links", an **Insert** button.
  - Rules list: separate URLs by space or newline; only visible text is imported; paid articles aren't supported; YouTube imports the transcript only; public videos only.
- **Copied text sub-view:** a textarea and Insert. Not captured live; build it with the same pattern.

### 3.4 Notebook: Chat
- **Zero state** (no sources): 👋, "Let's start your notebook...", a blurb, "What would you like this notebook to help you do?", and 3 chips.
- **Notebook header block** (top of the scroll):
  - Emoji (click opens an emoji picker), optional cover image.
  - Title 36px, "3 sources · Oct 14, 2026".
  - The **auto summary**, with bold key terms.
  - Actions: Save to note, copy, 👍, 👎.
  - **3 suggested-question cards**: radius 24, padding 20, ↳ icon.
- **User message:** right-aligned bubble, `tonal`, radius 40.
- **Answer:**
  - No bubble. 17/24 text, markdown (lists, bold, headings), KaTeX math.
  - A collapsible **"Thoughts ▾"** chain of steps: icon, bold step title, text; "Searched your sources" as a step.
  - **Citation chips:** circles 22×22 with a number; "…" for a collapsed group.
  - **Citation hover popover** (420×420): source title, scrollable passage with the cited text highlighted, "View source" link.
  - Actions: Save to note, Copy, 👍, 👎.
  - A follow-up suggestion line or cards after the answer.
- **Date separators:** "Today • 10:28 PM".
- **Streaming state:** the input placeholder becomes "Responding...", and the send button turns into a stop (■) button.
- **Query box** (pill, 64 high):
  - Textarea "Ask a question or create something".
  - "N sources" counter, showing the count of checked sources.
  - Round ↑ send button.
  - Below it, the disclaimer "Verlium can make mistakes, so double-check it."
- **Header ⋮ menu:** Configure Chat · Customize notebook · Copy notebook · Delete chat history ("Chat history is private to you.").
- **Configure Chat dialog:**
  - Goal: `Default` ("Best for general purpose research and brainstorming tasks."), `Learning Guide` ("Best for educational content, helping you grasp new concepts and skills efficiently."), or `Custom` (textarea with a 0/10000 counter).
  - Response length: `Default | Longer | Shorter`.
  - Save.
- **Customize notebook dialog:** cover image upload, notebook title, a "Set custom notebook summary" toggle and text, Done.

### 3.5 Notebook: Studio panel
- **Tiles:** a 2-column grid, gap 8; each tile 48 high, radius 20, colored icon plus label. On hover a `›` appears. **Clicking a tile opens its Customize dialog.** Order:
  1. Audio Overview
  2. Slide Deck
  3. Video Overview
  4. Mind Map
  5. Reports
  6. Flashcards
  7. Quiz
  8. Infographic
  9. Data Table
- **Output list** (newest first):
  - **Pending item:** spinner, "Generating {Type}...", "based on N sources". Audio says "Come back in a few minutes".
  - **Done item** (60 high, radius 20): colored icon, title (1 line), meta "Briefing Doc · 3 sources · 1m ago", unread dot, ⋮ menu (Share · Rename · [Download for audio] · View prompt and sources · Delete).
  - **Audio items** also show hover buttons for `Interactive` and ▶.
  - **Notes** appear in the same list.
- **Empty state:** "Studio output will be saved here." and "After adding sources, click to add Audio Overview, Study Guide, Mind Map, and more!"
- **Floating "Add note"** pill at the bottom.

### 3.6 Customize dialogs (shared shell)
- **Shell:** radius 28; title with a leading icon; sections labelled at 500 16/20.
- **Footer:**
  - "AI Usage" meter, with the legend Already used / Estimated use. For Verlium, show an **estimated token or cost** figure from the configured model.
  - `Generate later`: in Verlium, queue it to run in the background.
  - `Generate now`.
- **Common fields:** Choose language, Sources (subset picker "3 sources ▾"), and a free-text focus prompt.

| Type | Specific controls |
|---|---|
| Audio Overview | Format cards: **Deep Dive / Brief / Critique / Debate** (descriptions in the raw notes) · Length `Short / Default / Long` (Brief has no length) · "What should the AI hosts focus on in this episode?" |
| Slide Deck | Format: **Detailed Deck / Presenter Slides** · Length `Short / Default` · "Describe the slide deck you want to create" |
| Video Overview | Format: **Short (9:16) / Explainer (16:9)**, plus **Cinematic** if a video model is set · "What should the video focus on?" with 3 AI-suggested topic chips and a "Custom topic" |
| Mind Map | "What should the topic be?" |
| Reports | Format: **Interactive / Document** · Templates: Create Your Own, Briefing Doc, Study Guide, Blog Post, plus **4 AI-suggested templates** generated from the sources · A pencil on a template opens an edit sub-view |
| Flashcards | Number `Fewer / Standard / More` · Difficulty `Easy / Medium / Hard` · Images `Include / Text Only` · Topic |
| Quiz | The same three controls as Flashcards, plus Question types `Multiple Choice / Multiple Select / Fill in the Blank / Short Answer` · Topic with a prefilled suggestion and "+ topic" chips |
| Infographic | Orientation `Landscape / Portrait / Square` · Style `Auto-select, Kawaii, Clay, Sketch Note, Anime, Editorial, Instructional, Bento Grid, Bricks, Scientific, Professional…` · Detail `Concise / Standard / Detailed` · Description |
| Data Table | "Describe the data table you want to create" |

### 3.7 Viewers (in the Studio panel; expandable to a modal)
- **Common chrome:**
  - Breadcrumb "Studio › {Type}" with ⤡ close.
  - Title, share, copy or expand, ⋮.
  - **"View prompt and N sources"** pill. It opens a popover showing the prompt text with ↻ re-run and copy buttons, and source chips.
  - Footer: 👍 Good / 👎 Bad.
- **Report:** document typography; ⋮ Export (in Verlium: **Markdown / DOCX / PDF**) · Delete.
- **Mind map:**
  - Horizontal tree with the root on the left; curved connectors; pill nodes with ‹ › toggles.
  - Controls: expand all, zoom +/−, download PNG.
  - **Clicking a node** sends "Discuss what these sources say about {node}, in the larger context of {root}." to chat.
- **Flashcards:**
  - Hint "Press "Space" to flip, "←/→" to navigate"; counter "1 / 64"; card over a soft glow; flip to see the answer.
  - "Explain" sends the card to chat.
  - Controls: ←, ✗ count, ✓ count, →.
- **Quiz:**
  - "1 / 12"; options A–D.
  - On answering: green "✓ Right answer" or red "✗ Not quite", with a rationale shown for every option.
  - "Explain" and "Next".
- **Data table:** native table with horizontal scroll and links; Export CSV/XLSX.
- **Audio player** (docked at the bottom of Studio):
  - Title, 👍/👎, ⋮, ✕; seek bar; "mm:ss / mm:ss".
  - Speed menu: 0.5 / 0.8 / 1.0 / 1.2 / 1.5 / 1.8 / 2.0x.
  - ⟲10, ▶ (40px circle, `primary`), ⟳10, and a queue button.
- **Note editor:**
  - Title input, 🗑.
  - Toolbar: undo/redo · "Normal ▾" · **B** *I* · overflow (link, code, code block, bullets, numbers, quote, divider, clear).
  - "Convert to source" pill.
- **Infographic / Slide deck / Video:** see §5.

### 3.8 Share dialog
Verlium is single-user first, so treat this as a later phase.
- People input, "Notify people", rows with Owner/Editor/Viewer roles.
- General access: `Restricted / Anyone with a link / Public`.
- Copy link, Save.

---

## 4. Behaviors to replicate
1. **When the first sources are processed:**
   - Auto-generate the notebook **title, emoji and summary**, plus 3 suggested questions.
   - Auto-generate each source's **Source guide** (summary and 5 topic chips).
2. **Checked sources** scope chat and Studio generation. The counter in the query box reflects them.
3. **Studio jobs** run in the background. Several can run in parallel, each with its own pending item. New items get an unread dot.
4. Every output keeps **its prompt and source set**, and can be re-run (↻).
5. "Explain" from a flashcard or quiz, and mind map node clicks, **post a prompt into chat**.
6. **Save to note** from any answer or the summary. A note can be converted to a source.
7. **Citations** map to chunk IDs plus character offsets, so the hover popover and "View source" can scroll to and highlight the exact text.
8. **Featured / Discover / Collections:** skip these for v1.

## 5. Media viewers (captured 2026-10-15)
- **Infographic:**
  - One generated image: Landscape was 2752×1536.
  - Fit to width; zoom +/− floats bottom-right.
  - ⋮ menu: Download · Delete.
  - Expand opens the modal.
  - Google adds a watermark bottom-right. For us, put none, or an optional "Made with Verlium".
- **Slide Deck:**
  - Each slide is **one generated 16:9 image** (1376×768): a designed poster-style slide, not editable text.
  - The panel shows a vertical list of slides (radius 8, 2px border; the current slide is highlighted).
  - Header: ▶ "Start slideshow" and expand.
  - The expand modal shows the large current slide plus a **numbered thumbnail rail** on the right (selected thumb has a blue outline), with zoom +/−.
  - Slideshow mode shows the slide large with ←/→ navigation.
  - **Build note:** Verlium's slide pipeline is: an LLM writes the outline and content per slide, then the image model renders each slide. As a fallback when no image model is set, render HTML/SVG templates. Export as PDF or PPTX of the images.
- **Video Overview player:**
  - Custom controls: play/pause, ⟲10 "Rewind", ⟳10 "Skip forward", "mm:ss / mm:ss", speed (0.5 / 0.75 / 1 / 1.25 / 1.5 / 1.75 / 2x), fullscreen.
  - Footer: "Good video / Bad video".
  - **Short** is 9:16 (720×1280), centred in the panel. It's a **TikTok/Reels-style** video: fast cuts, punchy hook, big burned-in captions, about 60–90 s.
  - **Explainer** is 16:9: a **tutorial-style explainer** with polished motion graphics (titles, diagrams, animated callouts) and a narrator. It is longer.
  - **Captions are burned into the video** (lower-third text on a dark box).
  - Studio list meta: "1:26 · Short · 8 sources", with ▶ quick-play on hover.
  - **Build note:**
    - Short/Explainer: LLM script → per-scene image (or video clip if a video model is set) → TTS narration → ffmpeg with Ken-Burns motion and burned-in subtitles.
    - Cinematic: requires the video model.
- **Interactive Audio:**
  - Opened from "Interactive" on an audio item.
  - Panel "Studio › Audio Overview": title, (i) info, download, "2 hosts", a large **canvas waveform**, and a bottom row with ▶ · wide **"👋 Join"** pill (enabled once playback starts) · ↻ "Restart audio".
  - Info text: users can interrupt to ask a question; voice and transcript are not stored; share/download use the original audio.
  - **How it works (confirmed by the user):** it runs on a **realtime speech-to-speech model**. There are two hosts, one male and one female. When you Join, you become a third participant. You can cut in between the hosts, and they respond to you and to each other live, like a call-in podcast.
  - **Build note:**
    - **Primary path:** a Realtime role in model settings (OpenAI Realtime, Gemini Live, or any OpenAI-Realtime-compatible WebSocket/WebRTC endpoint), with 2 voices.
      - Session context: the sources, the episode transcript, and the playback position.
      - When the user joins, pause the pre-rendered episode and switch to a live session in which both hosts are voiced. Use one session with voice switching, or two sessions coordinated by a turn manager.
      - The hosts acknowledge the user's question, discuss it between themselves, and then hand back.
      - Resume the recording, or continue live.
    - **Fallback** when no realtime model is set: STT → LLM writes a short two-host reply script → TTS with both voices → play → resume. This is slower but works with any provider.

## 6. Read-only / shared notebook (Viewer role). Phase 3, but design for it.
- **Header:** "🔗 Shared" chip after the title; **Copy** (duplicate the notebook into your own account) replaces Share.
- **Chat column:** starts with a **cover hero card** (image, author, title, rating/price link), then the owner's intro text. Viewers chat with their own private history.
- **Sources panel:** an optional pinned primary source card (it can be locked), then a "Supplementary sources" list.
- **Studio panel:** no create tiles. An owner note banner, then the output list.

## 7. Still not observed
- The live "Join" conversation itself. It needs microphone access, which I didn't grant.
- Cinematic video, Interactive Reports, Deep Research flow.

Build these from the descriptions in [../RESEARCH.md](../RESEARCH.md) and the patterns above.
