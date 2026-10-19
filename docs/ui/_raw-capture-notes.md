# Raw capture notes (Gemini Notebook, captured 2026-10-14, dark theme, viewport 1280x800)

Stack observed: Angular + Angular Material 3 (MDC). Body classes `dark-theme luminous-ui mat-app-background`.
Icon fonts: "Google Symbols" / "Luminous Symbols" (= Material Symbols Rounded-ish). Font: "Google Sans Flex" (variable; weights used 370/400/470/475/500).
Logo: https://www.gstatic.com/tailwind/_/static/branding/v6/dark_mode/notebook-icon.svg (don't copy; make our own).

## HOME (/)
- body bg #0f0f0f, text #c7c7c7
- header `page-header` h64, bg #0f0f0f. Logo at x20 y18: icon + "Gemini Notebook" 475 23px/29px #f2f2f2.
- Filter: at >=~1400px shows inline tabs [All | My notebooks | Discover | Shared with me | Collections]; at 1280 collapses to tonal dropdown button "All ▾" (bg #171717, pill, 36h, pad 0 8 0 12, 370 15px).
- Right side: search pill "Search notebooks" 256x36 outlined (border .67px rgba(255,255,255,.12), pill, pad 0 12 0 8) ; segmented [grid_view | view_headline] 76x36 bg #171717 pill pad 2, each btn 36x32 (active text #e6e6e6, inactive rgba(255,255,255,.55)); settings gear icon btn; Google apps grid; avatar.
- Section h2 "Featured notebooks" 24px/32px #f2f2f2 at x24; "View all >" text button right.
- Featured card: 299x209, radius 40px, pad 32, cover image full-bleed with dark gradient; top-left badge (white pill, black icon menu_book + "Full book" 500 11px); publisher avatar + name 14px white; more_vert top-right; title 470 20px/24px white; subtitle "Aug 4, 2026 · 11 sources" 400 15px/20px; public (globe) icon bottom-right. Single row horizontal (project-grid.single-row-layout), gap 8.
- "Recent notebooks" h2 + right "+ New notebook" filled button (bg #1f3b9b in dark, pill, 36h, pad 0 12 0 8, icon add_2).
- Notebook card: 299x185, bg #171717, radius 40px, pad 32. Emoji 36px top-left (box 36x36). more_vert (20px, #ababab) top-right. Title 470 20px/24px #e6e6e6 (ellipsis). Subtitle "Sep 22, 2026 · 1 source" 400 15px/20px rgba(255,255,255,.55); dot separator padded 0 4px. Shared notebooks show public icon bottom-right. Grid: 4 cols @1280 (cards 299 wide), gap 8.
- Card menu (mat-menu, bg #1f1f1f, radius 20, shadow 0 0 20px rgba(0,0,0,.28), width 206): items 36h radius 12 pad 8 gap 8: [edit Edit title] [category Add to collection] [push_pin Pin to top] [delete Delete].
- Settings menu (243w): Gemini Notebook help · Send feedback · Discord · Output language · Notifications · Remove watermarks [Upgrade] · Licenses · Device (submenu: light_mode Light mode / dark_mode Dark mode / routine Device) · Usage · Upgrade Gemini Notebook (button).
- Output language dialog: 640x480 radius 28 bg #0f0f0f; title "Configure settings"; close X; "Choose your language override" mat-select (Default); Save filled button (bg #4259ff, white, radius 96, pad 0 24, 40h).
- Usage dialog: "Gemini Notebook AI Usage & Limits" — current usage % (resets every 5h) + Weekly limit % + Upgrade CTA. (Verlium: map to token/cost usage per provider.)

## NOTEBOOK (/notebook/:id) — 3 panels
- notebook-header h64: round logo button (left), editable title 400 22px/36px #f2f2f2 at x76; right: "+ Create notebook" text btn, "Share" (share_1), more_vert, settings, apps, avatar.
- Sources panel: section.source-panel x12 y64 w314 h724, bg #1f1f1f, radius 32, pad 8. Header "Sources" 400 15px/20px #e6e6e6 + side_nav collapse icon; header pad 8 8 8 12 h40.
- Chat panel: center x334 w603, transparent on #0f0f0f (no card).
- Studio panel: section.studio-panel x945 w314, same style as Sources (bg #1f1f1f radius 32 pad 8).
- Gutters: 12px outer, ~8px between panels.
- Sources panel contents: "+ Add sources" tonal pill full-width 36h (bg #171717). Discovery box (bg #171717 radius 24 pad 12 8 8, gap 16): textarea placeholder "Search the web for new sources" 15px/20px; chips row: [language ▾] corpus menu (Web "Best sources from the web" / Drive "Your content from Google Drive"), [search_spark ▾] mode menu (Fast Research "Great for quick results" / Deep Research "In-depth report and results"); chips bg #1f1f1f pill 36h 370 13px; arrow_forward submit icon btn (disabled color rgba(255,255,255,.55)).
- Sources empty state: description icon, "Saved sources will appear here" (bold) + "Add files, websites, or more. Then ask questions or create things based on these sources." + "Drop files here or add a source" (link underlined).
- Chat zero state: emoji 👋, h1 "Let's start your notebook..." 400 32px/40px #f2f2f2; body 14px/24px #c7c7c7 "This is your blank canvas to understand, create, or make progress on something new. I can help you get started or you can go ahead and add your own sources."; prompt 500 14px/24px "What would you like this notebook to help you do?"; chips (bg #171717 radius 32 pad 10 20, 40h, 14px/24px): "Learn about a new topic", "Create something new", "Make progress on a project".
- Query box: x350 w571 h64 at bottom; textarea placeholder "Ask a question or create something" 16px/24px; right: "0 sources" counter (12px) + round send button arrow_upward 36x36 (disabled alpha .38).
- Disclaimer under: "Gemini Notebook can make mistakes, so double-check it." 13px/17px rgba(255,255,255,.55) centered pad 12 0.
- Studio: optional promo banner ("New: You can now create Interactive Reports!" + Try it + X). Tiles grid 2 cols (144.33px each) gap 8; tile 48h radius 20 pad 4 12 4 8, bg #171717 (via ::after), icon 24px colored + label 400 13px/17px #e6e6e6, hover shows chevron_forward / edit (pencil) to customize.
  Tiles & icon colors (dark): Audio Overview audio_spark #76a0ff · Slide Deck (pink) · Video Overview videocam #3fdda0 · Mind Map flowchart #a47dff · Reports auto_tab_group #f872b9 (+ "New!" badge) · Flashcards copy #ecdf77 · Quiz quiz #4dd2e1 · Infographic stacked_bar_chart #ecdf77 · Data Table format_list_bulleted #76a0ff.
- Studio empty: edit_fix_auto icon 28px, "Studio output will be saved here." 500 14px, "After adding sources, click to add Audio Overview, Study Guide, Mind Map, and more!" 15px/20px, all rgba(255,255,255,.55).
- Floating "Add note" button bottom-center of studio: article icon, 48h, pill, bg #171717, pad 0 16 0 12.
- First-visit modal "We're giving you more flexibility and control over how you use Gemini Notebook." 3 cards: Limits refresh every 5 hours / Create more of what you love / New background queue.

## ADD SOURCES DIALOG (?addSource=true)
- 700x492, container bg #1f1f1f radius 28. Title (470 20px/27px #e6e6e6, centered): "Create Audio and Video Overviews from" + 2nd line animated rotating phrase in blue ("your documents" / "websites" / ...).
- Same discovery box as panel (bg #171717 radius 24, 660 wide): textarea "Search the web for new sources", chips [🌐 Web ▾] [✦ Fast Research ▾], round submit (bg #1a1d22).
- Source type pills (outlined, border .67 rgba(255,255,255,.12), pill, 40h, 370 17px/24px): [upload Upload files] [link_2 + red YouTube icon  Websites] [Play Books] [drive Drive] [content_paste Copied text].
- Drop zone: dashed border .67 rgba(255,255,255,.12), radius 16, 660x142, upload icon + "Drag & drop your files to upload. Supported file types: pdf, images, docs, audio, and more." (13px/18.2 rgba(255,255,255,.55)).
- Websites sub-view: back arrow + "Website and YouTube URLs" + X; "Paste in Website and YouTube URLs below to upload as a source in Gemini Notebook."; textarea "Paste any links" (168h, outlined focus white); bullet notes: multiple URLs separated by space/newline; only visible text imported; paid articles unsupported; only YouTube transcript imported; only public YouTube; recently uploaded may not be available; "If upload fails, learn more". Button "Insert" (disabled grey until valid).

## SOURCES LIST (populated)
- Toolbar row: sort icon btn (32x32) left → menu [Recent | Title ✓ | Type]; right: "Select all" 14px/24px + checkbox.
- Row: 36h, radius 8, pad 0 8, gap 12: favicon/type icon 20px (Wikipedia W, YouTube red) → on hover becomes more_vert menu [delete Remove source | edit Rename source]; title 400 14px/24px #f2f2f2 ellipsis; checkbox right (MDC checkbox).
- While processing: row shows URL as title + spinner instead of checkbox. New rows animate in (source-picker__move-in).
- After first sources: notebook auto-titled ("Chlorophyll: The Green Pigment of Photosynthesis") + auto emoji.

## SOURCE VIEWER (click a source) — replaces list inside the Sources panel (same 314 width)
- Header: "Sources" + collapse_content icon (back to list). Title 400 22px/36px #f2f2f2 + open_in_new.
- "Source guide" collapsible card: bg #2f334b (nlm-brand-dark-blue), radius 16, pad 0 16; header button_magic icon + "Source guide" + arrow_drop_up; summary paragraph with bold key terms; key-topic chips (500 12px/16px, 32h, pad 0 12) e.g. "Light reactions", "Calvin cycle" — click asks chat about topic.
- Below: full extracted source text rendered (doc viewer; paragraphs, tables, lists).

## CHAT (populated)
- Notebook header block at top of chat scroll: big emoji (click → emoji picker), optional cover image (landscape_2 placeholder 192px at 12% white), title 320 36px/44px #e6e6e6, meta "3 sources · Oct 14, 2026" 14px/24px.
- Notebook summary paragraph with strong (600) key terms.
- Action row under summary: [keep_pin Save to note] [copy] [thumb_up] [thumb_down] icon buttons 36x36.
- Suggested questions: 3 cards side by side (bg #171717 radius 24 pad 20, 164w), text 14px/24px #e6e6e6, subdirectory_arrow_right 18px icon at bottom.
- User message: right-aligned card bg #171717 radius 40, max ~483w, text #e6e6e6.
- While answering: query placeholder becomes "Responding...", send button becomes stop (square) button; small dot loader at answer position.
- Assistant answer: no bubble (transparent, radius 16), width ~483, body 400 17px/24px #c7c7c7, bold weight 540; ordered/unordered lists; KaTeX math.
- "Thoughts ▾" collapsible (thinking-chain-view; header 36h radius 8 pad 6 8, 14px/24px): expanded = timeline of steps: neurology icon + bold step title + text; document_search "Searched your sources".
- Citation markers: inline circle 22x22 bg #171717 color #ababab 500 11px; "…" marker for collapsed group. Hover → popover 420x420, bg #0f0f0f radius 8, shadow; header = source title; scrollable source passage (cited span highlighted); footer link "View source" (opens source viewer scrolled+highlighted).
- Answer actions: [keep_pin Save to note] copy ("Copy model response to clipboard"), thumb_up, thumb_down. Follow-up suggestion cards after each answer.

## NOTEBOOK HEADER ⋮ ("Notebook configuration") menu
- tune Configure Chat · brush Customize notebook · copy Copy notebook · delete Delete chat history ("Chat history is private to you.").
- Configure Chat dialog (614w, radius 28): "Notebooks can be customized to help you achieve different goals: do research, help learn, show various perspectives, or converse in a particular style and tone." / "Define your conversational goal, style, or role": chips [Default][Learning Guide][Custom] (selected = filled #4259ff with check; others outlined border #37383b radius 24, 33h). Default help: "Best for general purpose research and brainstorming tasks." Learning Guide: "Best for educational content, helping you grasp new concepts and skills efficiently." Custom → textarea (0 / 10000 counter), placeholder examples: respond at a PhD student level / pretend to be a role-playing game host / help me prepare for upcoming board meeting. "Choose your response length": [Default][Longer][Shorter]. Save (filled pill).
- Customize notebook dialog (410w): 'Customize the experience of "<title>"'; cover image area (placeholder + "Upload" pill top-right); "Notebook title" outlined field; toggle row (notes icon) "Set custom notebook summary" — "By default, Gemini Notebook autogenerates a summary that refreshes every time you open the notebook. You can choose to override this by manually setting a custom summary."; Done.

## STUDIO CUSTOMIZE DIALOGS (tile → chevron). Common footer: "AI Usage" meter (bar 8h radius 4; legend Already used / Estimated use) + [Generate later] text btn + [Generate now] tonal btn (48h pill). Common fields: "Choose language" select (English), "Sources" dropdown ("3 sources ▾" subset picker), free-text focus prompt. Dialog title 470 20px/24px with leading icon; section labels 500 16px/20px.
- Audio Overview (icon audio_magic_eraser): Format = 4 selectable cards in a row (selected = blue fill + check): Deep Dive "A lively conversation between two hosts, unpacking and connecting topics in your sources"; Brief "A bite-sized overview to help you grasp the core ideas from your sources quickly"; Critique "An expert review of your sources, offering constructive feedback to help you improve your material"; Debate "A thoughtful debate between two hosts, illuminating different perspectives on your sources". Language select; Length segmented [Short | ✓Default | Long] (Brief disables length); Sources; "What should the AI hosts focus on in this episode?" placeholder: Things to try • Focus on a specific source ("only cover the article about Italy") • Focus on a specific topic ("just discuss the novel's main character") • Target a specific audience ("explain to someone new to biology").
- Slide Deck (icon tablet): Format Detailed Deck "A comprehensive deck with full text and details, perfect for emailing or reading on its own." / Presenter Slides "Clean, visual slides with key talking points to support you while you speak."; Language; Length [Short|Default]; Sources; "Describe the slide deck you want to create".
- Video Overview (icon subscriptions): Format Short (crop_9_16, New!) "A bite-sized overview to help you quickly grasp core ideas from your sources" / Explainer (crop_16_9) "A structured, comprehensive overview that connects the dots within your sources"; Language; Sources; "What should the video focus on?" = 3 AI-suggested topic chips (pen_spark) + "Custom topic" (edit). (Cinematic + visual styles not offered on this free account.)
- Mind Map: Language; Sources; "What should the topic be?".
- Reports ("Create report", icon auto_tab_group): Format Interactive (New!) "An interactive report with embedded studio content" / Document "A structured text-only document"; Template "Learning Overview — Summarizes key concepts alongside studio content to help you learn" (edit to change).
- Flashcards (icon cards_star): Number of Cards [Fewer | Standard (Default) | More]; Level of Difficulty [Easy | Medium (Default) | Hard]; Include Images (New!) [Include (Default) | Text Only]; Language; Sources; "What should the topic be?".
- Quiz: Number of Questions [Fewer|Standard|More]; Difficulty [Easy|Medium|Hard]; Include Images; Question Types (New!) [Multiple Choice][Multiple Select][Fill in the Blank][Short Answer]; Language; Sources; topic textarea prefilled with an AI suggestion + chips "+ Photosynthesis Mechanics", "+ Structural Components", "+ Scientific History".
- Infographic: Language; orientation [Landscape|Portrait|Square]; visual style grid: Auto-select, Kawaii, Clay, Sketch Note, Anime, Editorial, Instructional, Bento Grid, Bricks, Scientific, Professional (+ more ›); Level of detail [Concise|Standard|Detailed BETA]; Sources; "Describe the infographic you want to create".
- Data Table (icon table_view): Language; Sources; "Describe the data table you want to create".
- Report Document templates grid (4 cols, cards radius ~20, pencil edit btn top-right of each): Create Your Own ("Craft reports your way by specifying structure, style, tone, and more") · Briefing Doc ("Overview of your sources featuring key insights and quotes") · Study Guide ("Short-answer quiz, suggested essay questions, and glossary of key terms") · Blog Post ("Insightful takeaways distilled into a highly readable article"); then "✦ Suggested Template" row of 4 AI-generated templates specific to the sources (e.g. Technical Assessment, Formulation Standard, Conceptual Overview, Comparative Primer). Pencil → sub-view (back arrow) showing template name+desc, Language "English (default)", Sources, "Describe the report you want to create".
- Format selection card selected style: bg blue (#1f3b9b-ish) with white check circle; unselected: dark card w/ empty circle.
- "Generate later" tooltip: "Doesn't use your current limit. Cheaper, ready in hours" (background queue). In Verlium: could map to "queue for batch/cheaper model" or just "queue".
- In current UI, clicking a Studio tile ALWAYS opens the customize dialog (no instant generation).

## STUDIO OUTPUT LIST (artifact-library) — below tiles in Studio panel
- Pending item: progress_activity spinner + "Generating Report..." + "based on 3 sources" (Audio: "Come back in a few minutes"). Item bg #171717-ish rounded.
- Done item (artifact-button-content): 60h, radius 20, pad 8, gap 8: type icon 22px in its tile color; title 400 13px/17px #e6e6e6 (1 line ellipsis, tooltip full); details 12px/16px rgba(255,255,255,.55) e.g. "Briefing Doc · 3 sources · 1m ago"; unread blue dot 6px #3186ff; more_vert.
- Item ⋮ menu: share Share · edit Rename · info_spark View prompt and sources · delete Delete.
- Notes also live in this list (article icon, "New Note", "1m ago").
- Newest first.

## VIEWERS (open item) — Studio panel widens 314→480 (Sources shrinks 314→262; chat flexes). Header breadcrumb "Studio › <Type>" + collapse_content (close). Title row: title (ellipsis) + share + copy/expand + ⋮. Pill "View prompt and N sources" (outlined, 32h, radius 96, 13px) → popover: "✦ Prompt" + restart_alt (re-run) + copy, full prompt text, "Sources" chips. Footer: [👍 Good report/content] [👎 Bad report/content] outlined pills.
- Report viewer: document typography — H1 350 28px/36px, H2 380 24px/28px, body 16px, lists, bold, KaTeX. ⋮: Export to Docs · Export to Sheets · Delete. Copy = "Copy content with formatting".
  Briefing Doc prompt (reference): "Create a comprehensive briefing document that synthesizes the main themes and ideas from the sources. Start with a concise Executive Summary that presents the most critical takeaways upfront. The body of the document must provide a detailed and thorough examination of the main themes, evidence, and conclusions found in the sources. This analysis should be structured logically with headings and bullet points to ensure clarity. The tone must be objective and incisive."
- Mind Map / Flashcards / Quiz = "App" viewers (breadcrumb "Studio › App"): sandboxed iframe (Google serves generated mini-apps from *.usercontent.goog). Has Expand (expand_content) → large modal (~1180x700, radius 28, title + View sources + share/collapse/close/⋮[Delete] + Good/Bad footer).
- Mind map: horizontal tree, root left; curved lavender connector lines; nodes = rounded rect pills (L1 slate #3c4150-ish, leaves green-tinted #2f3d36-ish), white 13px text; circular "<"/">" expand/collapse toggles to the right of nodes; floating controls bottom-right: expand/collapse-all (unfold), zoom +, zoom −, download. Clicking a node label sends chat prompt: "Discuss what these sources say about {node}, in the larger context of {root}." and collapses modal.
- Flashcards: hint "Press "Space" to flip, "←/→" to navigate"; card ~560x400 radius ~32 bg #2b2b2b over blurred blue/green radial glow; "1 / 64" counter top-left, ⋮ top-right; front = question large 28px; "See answer" bottom; back = answer + "Explain" pill (sends to chat). Controls row: ← (prev), ✗ count (red), count ✓ (green), → (blue filled). 
- Quiz: "1 / 12", ⋮; question bold 15px; options A–D as cards (bg #232323 radius 12). After choosing: correct = green border + "✓ Right answer" + rationale; chosen wrong = red border + "✗ Not quite" + rationale; others show their rationale greyed. Bottom: "Explain" pill + "Next" filled blue pill.
- Data Table: native table in panel (not iframe), horizontal scroll; th 370 17px/24px pad 8 12; td 400 15px/20px pad 8 12; row divider .67px #37383b; links #c3cafc underlined; KaTeX in cells. ⋮: Export to Sheets · Delete.

## NOTE EDITOR (Add note / open note) — opens in Studio panel (480w)
- Breadcrumb "Studio › Note", collapse_content (Close note view). Title input (placeholder/value "New Note", 22px) + delete (trash) icon.
- Rich-text toolbar: undo, redo | "Normal ▾" (paragraph style) | B, I | overflow "…" (link, inline code, code block, bulleted list, numbered list, quote, divider, clear formatting).
- Editor body 14px/24px. Footer pill "convert_to_text Convert to source" (32h radius 16, 13px).
- Chat shows date separators: "Today • 10:28 PM" 500 12px/16px #ababab centered.

## AUDIO OVERVIEW (done item + player)
- List item: audio_spark icon, title (AI-generated, e.g. "The Quantum Engine Inside Every Leaf"), meta "23:11 · Deep Dive · 3 sources · 1m ago", hover buttons: waving_hand "Interactive" (Interactive mode) pill, play_arrow Play, more_vert. Item ⋮: Share · Rename · Download · View prompt and sources · Delete.
- Player docked at bottom of Studio panel (~265x148): title (ellipsis) + 👍 Good discussion / 👎 Bad discussion / ⋮ (Download · Share · Rename · Delete · View 3 sources) / ✕ close; seek slider full width; time "00:03 / 23:11" 12px/20px; controls row: speed "1.0x" (menu 0.5/0.8/1.0/1.2/1.5/1.8/2.0x), replay_10, play/pause 40px circle bg #4259ff, forward_10, "acute" Open queue (audio queue).
- Generating state text: "Generating Audio Overview... / Come back in a few minutes". Took ~5–8 min for a 23-min Deep Dive.
- NOT captured: Interactive-mode screen (needs mic), Slide Deck / Video viewers (free-tier immediate limit hit: dialog footer becomes "This content will generate in a few hours. Or, upgrade to get it sooner." + only [Generate later]). Infographic was generated ("Two-Stage Engine of Photosynthesis") but its viewer was not captured.

## DAY 2 CAPTURES (2026-10-15)
- Infographic viewer (icon stacked_bar_chart): opens in Studio panel / expand modal; a single generated raster image (2752x1536 for Landscape, i.e. ~16:9 at 2.7K) fit-to-width on dark canvas; floating zoom + / − bottom-right; header share / collapse / close / ⋮ [Download, Delete]; "View 3 sources" pill; Good/Bad content footer. Style = illustrated poster with title, two-column sections, labeled diagram, small text callouts, "© Gemini Notebook"-style watermark bottom-right (paid plans: "Remove watermarks").
- Interactive Audio viewer (click "Interactive" on an audio item): Studio panel "Studio › Audio Overview"; title + info (i) + download; "2 hosts" label; large canvas waveform visualizer (thin green line, animates while speaking); bottom row: play_circle (left), wide pill "👋 Join" (disabled until playback starts), refresh "Restart audio" (right); Good/Bad discussion footer.
  Info popover text: "You can now interrupt your Audio Overview to ask a question, interject, or make a request to the hosts! … Your voice and transcribed interactions with the hosts will not be stored. Clicking on the share / download buttons will share / download your original Audio Overview. Other users will not be able to interact with your Audio Overview via the share link. There may be a slight delay in starting to play the initial content, after you hit the join button…"
- Video generating item text: "Generating Short Video Overview... / This may take a while".
- Usage toast above query box: "You're almost at your AI usage limit. Limit resets at 2:22 PM." + "View usage" link + ✕ (snackbar-like card, radius ~16, bg #2f334b-ish).
- Repeated first-visit modal "We're giving you more flexibility…" appears again on each new session.
- Slide Deck viewer (seen on public featured notebook "How Nvidia Powered the AI Revolution"): panel view = title + ▶ "Start slideshow" + expand; vertical scroll list of slide images (each a generated raster 1376x768, 16:9, radius 8, 2px border — selected/current slide border #5e5e5e, gap 4). Expand modal = big current slide left + numbered thumbnail rail right (1,2,3… numbers left of thumbs, selected thumb blue 2px outline), zoom +/− overlay bottom-right of slide; ▶ slideshow hides rail and shows slide large (arrow-key nav). Slides look like designed posters (title, subtitle, diagrams), with "Gemini Notebook" watermark bottom-right. Item meta has no duration ("8 sources · 50d ago").
- Video Overview player (Short): Studio panel "Studio › Video Overview" + close; title; "View 8 sources"; vertical 9:16 video (720x1280) centered, ~271x483 in a 480 panel; captions are BURNED IN (no text tracks) — bold white serif-ish text on dark box, lower third; watermark bottom-right. Custom controls (no native): pause/play, replay_10 "Rewind", forward_10 "Skip forward", time "00:01 / 01:26", speed menu (0.5 / 0.75 / 1 / 1.25 / 1.5 / 1.75 / 2x), fullscreen. Footer "Good video / Bad video". List item meta: "1:26 · Short · 8 sources" with ▶ quick-play on hover. Visuals are photoreal/cinematic shots (generated imagery with motion).
- Read-only / shared notebook view (Viewer role): header shows "🔗 Shared" chip after title, "Copy" (copy notebook to own account) instead of Share; chat column top = big cover-image hero card (radius ~32) with author avatar+name, title, "5.0 ★ Purchase to unlock ↗"; then an owner-written intro. Sources panel: a featured "locked" primary source card (lock icon + cover thumb + title + author + chevron) then "Supplementary sources" list. Studio panel for viewers: no create tiles; an owner note banner (emoji + text, bg #2f334b-ish radius 16) + the output list only. Viewers can still chat (with their own private history).

## SHARE DIALOG
- 'Share "<notebook title>"' + close; "Add people and groups" outlined input; "People with access" + "Notify people" checkbox; rows: avatar + name + email + role select (Owner/Editor/Viewer); "Notebook Access": lock icon + select [Restricted | Anyone with a link | Public] + help "Only people with access can open with the link"; footer: split button [link_2 Copy link | ▾ → "Copy link to chat view"] + Save. (Screenshot not saved — showed account email.)

## LIGHT THEME (prefers-color-scheme / Settings › Device › Light mode)
- body #faf9f9, text #303030, titles #1b1b1c / #000; panels #ffffff; tonal surfaces (Add sources, discovery box, user bubble, citation chip, notebook card, segmented bg, pending items) #f2f0f0; secondary text rgba(0,0,0,.55); outline rgba(0,0,0,.08); "New notebook" button bg #9dd2ff text #000.
- Studio tile icon colors (light): audio #2e64de · slide #c43d92 · video #0aac6e · mind map #6858c7 · reports #c43d92 · flashcards #ff8104 · quiz #167f9b · infographic #ff8104 · data table #2e64de. (Dark: audio #76a0ff · video #3fdda0 · mind map #a47dff · reports #f872b9 · flashcards #ecdf77 · quiz #4dd2e1 · infographic #ecdf77 · data table #76a0ff.)
- Citation chip light: bg #f2f0f0, text #5e5e5e.

## RESPONSIVE
- Media queries: <600 (XSmall), 600–959, 960–1279, ≥1280 (Material CDK breakpoints) plus max-width 1050px.
- Notebook: ≥~1051px = 3 panels; ≤1050px (tested 1024 and 375) = single column with top pill tab bar [Sources | Chat | Studio] (343x32, bg #171717, pill; tab 28h 14px; Chat default). Header compresses to: logo, truncated title, + (create), share icon, ⋮, settings, apps, avatar. Query box shows source count as "📄 (3)".
- Mobile Studio tab: tiles 2-col larger (≈56h), library list below, floating "Add note" pill.
- Home on mobile: forced list view; "Recent notebooks" first (rows: emoji + title (wraps) + ⋮), then "Featured notebooks" list; header: logo, "All ▾", search icon, settings, apps, avatar; "+ New notebook" filled pill.
- Home list view (desktop): table columns Title (emoji + title) · Sources ("3 Sources") · Created · Visibility (public globe icon) · Role (Owner/Viewer) · ⋮; Recent table first, then Featured table.
