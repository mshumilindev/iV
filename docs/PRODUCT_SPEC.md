# iV — Product Specification

Pronounced like **“ivy”**.

iV is a neutral, serious, **local-first / desktop-first writing application** for long-form fiction: a **full DOCX manuscript editor** (via an embedded office-class engine) plus deterministic editorial tooling and a **selection-aware AI assistant** — not a generic chatbot UI.

**Authoritative architecture:** [`DOCUMENT_EDITOR_ARCHITECTURE.md`](DOCUMENT_EDITOR_ARCHITECTURE.md) (audit, engine choice, migration phases).

It is **NOT**:

- a homemade rich-text / `NSTextView` Word clone (legacy editor is prototype only);
- a Tiptap/ProseMirror primary surface;
- “DOCX” via HTML conversion pretending to be full fidelity;
- an AI writing chatbot as the main screen;
- a Notion clone;
- a generic Markdown editor;
- a productivity coach;
- a fantasy-branded app;
- a “write my novel with AI” tool;
- a tray/menu-bar ambient assistant;
- a background-first “ambient writing” app.

It should feel closer to:

- JetBrains IDE for prose;
- Scrivener for structure;
- Grammarly-style diagnostics;
- compiler / CI pipeline for narrative text;
- local canon/context engine;
- optional constrained local AI subsystem.

**Core philosophy:** AI is not the author. AI is a constrained subsystem inside a deterministic editorial pipeline. The user remains the author and final authority. The app prevents prose degradation rather than generating “pretty AI prose”.

**Correct UX model:** fullscreen-capable native macOS app; opens to **Project Library**; project-based; manuscript/workstation UI; document editor first; diagnostics/AI as supporting systems. Usable as the main writing environment, not just an external checker.

---

## Absolute product rules

### The app must NEVER

- silently rewrite manuscript text;
- auto-accept creative edits;
- overwrite user prose without review;
- optimize prose for “easy readability”;
- flatten author voice;
- turn prose into short punchy AI/YA rhythm;
- use one giant AI prompt for everything;
- send the whole book to a model by default;
- treat AI output as truth;
- rely on chat memory;
- require paid APIs;
- require OpenAI API;
- place AI chat as the central UI.

### The app must ALWAYS

- keep writing local-first;
- separate deterministic checks from AI checks;
- expose diagnostics clearly;
- show diffs for proposed changes;
- allow accept/reject/edit for every non-mechanical change;
- store structured project context;
- expand analysis scope gradually;
- preserve author intent;
- support project-specific edit rules;
- work even if Ollama/local AI is not installed.
- require **confirmation** before irreversible or high-impact destructive actions (see below).

---

## Confirmation for destructive & high-impact actions

Use native macOS **confirmation dialogs** (`confirmationDialog` / alert sheet)—not silent deletes, not LLM “are you sure” chat.

**Always confirm before:**

| Action | Message must state |
|--------|-------------------|
| Delete project | Folder removed from disk; cannot undo |
| Delete document | Manuscript file and linked diagnostics/index data removed |
| Remove project cover | Cover file deleted from `covers/` |
| Import manuscript **replacing** active document | Existing text will be overwritten (after import preview when feasible) |
| Accept `ChangeProposal` (creative) | Optional secondary confirm only for chapter-level / multi-paragraph proposals (paragraph-level: diff review is sufficient) |
| Apply chapter split / hard structural split | Structural change; creates proposal first, confirm on apply |
| Delete canon entity / narrative memory entry | Data removed from project memory |
| Clear all diagnostics / reset analysis run history | Optional; confirm if bulk |
| Disable all LLM / switch to destructive performance override | Warn when disabling safety nets |

**Do not confirm for:** typing, mechanical safe auto-fix preview, toggling rule file enabled, opening rules browser, running read-only diagnostics, export (uses save panel), duplicate project (creates copy; non-destructive).

**Copy rules:** title names the object (`Delete “Novel Title”?`); body explains consequence; default/focus on **Cancel**; destructive button uses `role: .destructive`.

Edit project metadata uses an **edit sheet**, not a delete-style confirm (save is explicit).

---

## Platform / stack

Build a **native macOS** app using:

- Swift, SwiftUI, AppKit (where SwiftUI is insufficient);
- SwiftData or SQLite (optional; JSON-on-disk acceptable for MVP);
- Foundation, NaturalLanguage where useful;
- UniformTypeIdentifiers;
- FileDocument / NSOpenPanel / NSSavePanel;
- URLSession for Ollama local HTTP;
- Codable persistence;
- XCTest / Swift Testing.

**Do NOT use:** Tauri, React, Electron, OpenAI API, paid cloud APIs, Tiptap/ProseMirror as the primary DOCX surface, manual OOXML editing.

**Embedded document editor exception:** A **WKWebView** may host **ONLYOFFICE Document Server** (or Collabora CODE) on **localhost only** — this is the sanctioned main manuscript surface, not a generic web app shell.

### Apple Silicon–first architecture

Design for modern Apple Silicon Macs (e.g. M4). Goals: fast local analysis, responsive editor, efficient background work, local AI readiness, battery/thermal awareness, intelligent scheduling. **Not** “use 100% CPU/GPU.”

Use:

- Swift concurrency, structured async/await, task cancellation;
- priority-aware background work;
- efficient text indexing, incremental analysis;
- memory-conscious processing.

Heavy work must **never** block typing, scrolling, selection, undo/redo, or saving.

### Local AI execution strategy

First provider: **Ollama** via `OllamaAIProvider`. Do not hardcode the app around Ollama forever.

Abstraction `LocalAIProvider`:

- `checkAvailability()` / `listModels()`;
- `runJSONTask()` / `runTextTask()`;
- `embed()`;
- `cancelTask()`;
- `estimateContextLimit()` / `estimateRuntimeCost()`.

`LocalAIBackend` enum: `ollama`, `coreML`, `mlx`, `llamaCpp`, `appleFoundationModels`, `disabled`. MVP: implement Ollama; stub others as unavailable. **Do not fake** unsupported backends.

**Mandatory:** `LocalModelRouter` + `ModelMemoryManager` (see **Local model routing & task scheduling**). The app must **not** naively run one model for every task or keep many large models loaded at once.

Do not claim Neural Engine / Metal usage unless actually implemented; keep architecture ready for future Core ML / MLX backends.

---

## Project structure (code layout)

```
iV/
  App/           iVApp, AppState, AppCommands
  UI/            RootView, Library, Workspace, Editor, Diagnostics, Pipeline, Diff, Canon, Rules, Settings, CommandPalette
  Domain/        models (Project, Document, Chapter, Scene, Paragraph, Diagnostic, …)
  Storage/       ProjectStore, DocumentStore, DiagnosticsStore, CanonStore, …
  Editor/        EmbeddedDocumentEditor (ONLYOFFICE host), DocumentEditorBridge, Legacy RichTextEditor (prototype), ParagraphIndexer
  AI/            AiChatModels, AiChatService (selection-aware assistant)
  EditRules/     EditRuleLoader, excerpt builder
  RulesEngine/   DeterministicRuleEngine, SafeAutoFixEngine, Rules/*
  Analysis/      AnalysisCoordinator, AnalysisQueue, scope expansion
  Pipeline/      PipelineEngine, passes
  Context/       ContextBuilder
  LLM/           LocalAIProvider, Ollama, scene expansion
  Diff/          TextDiffEngine, ChangeProposalService
  DOCX/          import/export services
  Utilities/
  Resources/edit-rules/   bundled .mdc (00–09)
```

**Runtime edit rules** (manuscript prose, **not** Cursor/coding-agent rules):

- `src/edit-rules/` (repo/dev)
- `iV/Resources/edit-rules/` (bundle)
- `{Project}.ivproject/edit-rules/` (per-project overrides by filename)

Load, parse, display, index, and selectively include in local LLM prompts.

---

## App startup / project library

On launch: **Project Library** (normal windowed app, fullscreen supported; no menu-bar-only behavior).

### Project Library

- grid/list of writing projects;
- optional book cover per project;
- title, subtitle/description;
- last edited, word count, diagnostics summary, last pipeline status;
- actions: **open**, **create**, **edit metadata**, **duplicate**, **reveal in Finder**, **delete** (with confirmation), **open existing** `.ivproject` folder (register if missing from global registry);
- **each project card** exposes a visible **⋯ menu** on the library grid (not only right-click): Edit…, Duplicate, Reveal in Finder, **Delete…** — user does **not** need to open Project Overview to delete;
- toolbar: **New Project**, **Open Project…**, **Edit Rules…** (global rules browser — no project required).

#### Edit project (metadata)

From library **card menu** / context menu or project overview **Project** menu:

- change **name** and **subtitle** (persisted in `project.json` and global registry);
- replace or **remove** cover image (`covers/` on disk);
- project **folder path on disk is not renamed** when the display name changes (stable paths; rename-on-disk is a future enhancement).

#### Delete project

- always requires **confirmation** — available from **Project Library** (card ⋯ menu or context menu) and from **Project Overview** (Project menu);
- confirmation title: `Delete “{Project Name}”?`; body states the project folder is removed from disk and cannot be undone; default focus **Cancel**; destructive **Delete Project** button;
- deletes the entire `{Name}.ivproject` folder from disk and removes the entry from `~/Library/Application Support/iV/projects.json`;
- if the deleted project was open, navigation returns to **Project Library**;
- **not** a soft archive in MVP — destructive delete only.

### Covers

- optional PNG/JPG/WebP/HEIC if feasible;
- stored under `{project}/covers/`;
- neutral placeholder when missing (no fantasy decoration).

### Create project

- name, subtitle, optional cover;
- local folder; default language; default rule profile;
- empty manuscript or import file.

### Global registry

`~/Library/Application Support/iV/projects.json` plus per-project folders:

```
ProjectName.ivproject/
  project.json
  manuscript/
  snapshots/          # import snapshot, accepted baseline
  covers/
  exports/
  memory/             # canon, narrative memory, suggestions
  diagnostics/
  edit-rules/
  indexes/
```

---

## Project overview page

Before full editor: cover, title, description, documents, chapter/scene summary, word count, diagnostics summary, last edited, last analysis run.

Actions: Open Editor, Import Manuscript, Create Manuscript, Canon Vault, **Edit Rules…** (rules browser sheet), Run Full Analysis, Export; **Project** menu: Edit…, Duplicate, Delete… (with confirmation).

---

## Primary MVP goal

User can:

1. Create/open a local writing project.
2. Import manuscript (plain, RTF, DOCX per service capability).
3. Edit prose in **embedded DOCX editor** (ONLYOFFICE/Collabora on local Document Server); legacy `NSTextView` prototype only when office engine unavailable.
4. Organize project → documents → chapters → scenes → paragraphs.
5. Load/view edit rules from `src/edit-rules`, bundle, and project folder.
6. Store canon, memory, summaries.
7. Run deterministic diagnostics.
8. Run multi-pass pipeline with gradual scope expansion.
9. Run local AI via Ollama when available.
10. Review proposals via diff/revision split; accept/reject/edit.
11. Export manuscript.
12. Use the app **without** Ollama.

**DOCX (authoritative):** primary manuscript file is `.docx` on disk, edited by embedded office engine. Legacy `DocumentImportService` / `DocumentExportService` limited paths remain for migration/auxiliary export — menus must **not** imply full Word fidelity for the homemade path. See [`DOCUMENT_EDITOR_ARCHITECTURE.md`](DOCUMENT_EDITOR_ARCHITECTURE.md).

---

## Data model

Codable structs; `Identifiable` / `Hashable` where useful.

### Project

`id`, `name`, `subtitle`, `rootURL`, `createdAt`, `updatedAt`, `activeDocumentID`, `settings` (language, rule profile, **performance mode**), `enabledRuleFileIDs`, `ollamaSettings`, `coverImagePath`, `wordCount`, `diagnosticsSummary`, `lastPipelineStatus`.

### Document

`id`, `projectID`, `title`, `type` (manuscript | notes | canon | rules), `plainText` (working manuscript), `originalSnapshot` (import snapshot), **`acceptedPlainText`** (last accepted baseline after review), `createdAt`, `updatedAt`, `version`.

**Document lanes (do not conflate):**

1. Original imported snapshot.
2. Current working manuscript.
3. Proposed revisions (`ChangeProposal`).
4. Accepted final baseline.

**Primary authoring format:** `.docx` per document under `manuscript/`. JSON sidecar (`{id}.json`) holds metadata, diagnostics linkage, scene index, and optional extracted plain text for analysis — not a substitute for the office editor surface.

### Chapter / Scene / Paragraph

As specified: summaries, function, POV/location metadata, `startParagraphID` / `endParagraphID`, diagnostics summaries.

**Paragraph:** stable `id`, `hash`, `wordCount`, `sentenceCount`, `lastAnalyzedHash`, order, scene/chapter linkage.

### EditRuleFile / EditRule / categories

Filename → category mapping (`00-minimum-gate` … `09-causality-pov-logic`, `custom`). Enable/disable per file (persisted in project).

### Diagnostic

Includes `textHashAtCreation`, `scopeHashAtCreation`, **`isStale`**, **`staleReason`**. Status: open, accepted, rejected, ignored, resolved, **stale**. Sources: deterministic, llm, pipeline.

### CanonEntity, NarrativeMemory, AnalysisRun, ChangeProposal, ContextPacket

As in original spec. Memory entries versioned via `sourceHash`; stale when underlying text changes.

### ParagraphDirtyState

`paragraphID`, `previousHash`, `currentHash`, `changedAt`, `dirtyReasons`, `affectedScopes` (sentence → project).

---

## Main UI

`NavigationSplitView` — **manuscript-first** layout:

| Left sidebar | Center | Right inspector (optional) |
|--------------|--------|---------------------------|
| **Documents** (default), **Structure** (chapters/scenes), Rules, Canon, Memory — compact vertical nav | **Embedded DOCX editor** (center) + **AI Assistant** panel (right, collapsible); slim chrome: Overview, inspector, Analyze | **Diagnostics** + pipeline/tools in inspector; AI chat does not replace diff review for pipeline proposals |

**Moved off the editor bar** (Settings, command palette, Editor menu): performance mode, reference pane picker, active watch toggle, semantic search panel.

**Status bar:** save state, active scene line, word count, queue/pipeline when active, issue count when &gt; 0, short “Ollama off” when unavailable — not a full dashboard of Ch/Sc/Rules counts.

**Empty states:** library (no projects), workspace (no manuscript / no documents), rules sidebar (honest reload + load defaults), diagnostics quiet panel (deterministic checks still work without Ollama).

**Visual:** dark forest chrome + ivy accents + **neutral light manuscript surface** — see [`BRAND_BOOK.md`](BRAND_BOOK.md). Dense, professional, typography-focused; no sparkles or cute AI mascot UI.

---

## Editor requirements (DOCX-first)

**Final direction:** embed **ONLYOFFICE Document Server** (preferred) or **Collabora Online** via localhost + `WKWebView`. Full audit: [`DOCUMENT_EDITOR_ARCHITECTURE.md`](DOCUMENT_EDITOR_ARCHITECTURE.md).

**Do not** use SwiftUI `TextEditor`, Tiptap/ProseMirror, or expanding the legacy toolbar into a Word clone.

### Legacy prototype (non-final)

`RichTextEditor` + `NSTextViewRepresentable` — **stub only**, retained for diagnostics development and fallback when Document Server is offline:

- large text, undo/redo;
- **autosave** (policy below);
- selection → current paragraph;
- inline diagnostic highlights (by severity);
- scroll-to-diagnostic;
- formatting toolbar;
- find/replace;
- focus mode;
- **split editor / reference pane:** import snapshot, accepted baseline, current paragraph;
- comments/annotations architecture (future-ready).

### Document autosave policy

Follow common native-editor practice (VS Code, Xcode, Scrivener-class apps): **never rely on manual save only**, but **do not save on every keystroke synchronously**.

| Mechanism | Policy |
|-----------|--------|
| **Idle debounce** | After typing stops, save after **2 seconds** (configurable 1–3 s). Cancel/restart debounce on each edit. |
| **Explicit save** | ⌘S flushes immediately; shows errors if write fails. |
| **Lifecycle** | Save pending changes when app/window **resigns active** or terminates. |
| **Atomic writes** | Write to temp file → replace (`AtomicFileWriter`); avoid half-written JSON on crash. |
| **Scope** | Autosave active `Document`, paragraph index, structure sidecar, project `wordCount` / `updatedAt`. |
| **UI state** | Status bar: **Saved** / **Saving…** / **Unsaved** (dirty since last successful write). |
| **Not autosaved** | In-flight LLM output, unreviewed proposals, UI-only filters. |
| **Import** | New import creates document; **replacing** current document content requires confirmation. |
| **Optional later** | Timed safety snapshot (e.g. every 10–15 min) into `snapshots/`; version browser—not required for MVP. |

Editor thread must never block on disk I/O; save runs off hot path (async Task). Autosave failure → non-blocking error alert + remain **Unsaved**.

### ParagraphIndexer

- split paragraphs; **stable IDs** across edits when possible;
- hashes; dirty states; persisted per document in `indexes/`.

### Analysis targets

selected text → sentence → paragraph → paragraph window → scene → previous+current scene → chapter section → chapter → document → project memory/canon.

### Embedded office editor

- **Engine:** ONLYOFFICE Document Server on `127.0.0.1` (user-configured port); Collabora acceptable alternative.
- **Host:** `WKWebView` in `EmbeddedDocumentEditorView`; app shell owns project paths and lifecycle.
- **Save:** authoritative `.docx` on disk; status bar reflects real save state (no fake “Saved”).
- **Bridge:** `DocumentEditorBridge` — selection text, cursor context, insert/replace via engine APIs when available; `selectionRange` typed as `unknown` until validated.

### AI Assistant panel (selection-aware chat)

Right-side panel (`AIChatPanelView`), collapsible. **Not** the primary UI — document remains center.

| Behavior | Rule |
|----------|------|
| Selection | When user selects text in office editor (or legacy stub), show **Using selected text**; include in `AiChatRequest.target` |
| No selection | Use cursor/document/project target — do not fake selection context |
| Generate / rewrite / analyze | `instructionMode` on request; scoped context (selection → nearby excerpt → rules) |
| Apply | **Replace selection**, **Insert at cursor**, **Append**, **Copy** — explicit buttons only |
| Safety | Snapshot before replace/bulk insert; never silent manuscript mutation |
| LLM | Local Ollama only; unavailable → honest error in panel |

Types: `iV/AI/AiChatModels.swift`. Service: `AiChatService`.

---

## Import / export

Protocols: `DocumentImportService`, `DocumentExportService` with `ImportExportCapability` (honest menu labels).

| Format | Capability | Notes |
|--------|------------|--------|
| **Plain Text** | Full | UTF-8 import/export — first-class. |
| **RTF** | Text only | Imports plain text from RTF; exports plain text as minimal RTF — **no rich roundtrip**. |
| **DOCX** | **Primary (office editor)** | Open/edit/save via embedded engine. |
| **DOCX (homemade path)** | Limited | Legacy import/export services — auxiliary only; menus say “DOCX (limited)”. |

Import: `NSOpenPanel` (panel message = limitation summary), parse, create document, detect headings / `***` scene breaks, assign paragraph IDs, store **original snapshot**.

Export: working manuscript only; no diagnostics or unreviewed proposals in output files.

---

## Edit rule loader

Scan `src/edit-rules`, bundle `Resources/edit-rules`, project `edit-rules/`. Load `.mdc`/`.md`, parse headings → sections, infer category, stable file IDs for enable persistence. Missing/empty folder must not crash app.

### Edit Rules Browser (view UI)

Dedicated **sheet/window-style** browser (not chat, not manuscript editor):

| Entry point | Scope |
|-------------|--------|
| Project Library toolbar **Edit Rules…** | bundled + development (`src/edit-rules`) rules |
| Project overview **Edit Rules…** | merged catalog for current project (bundled + dev + project overrides by filename) |
| Workspace sidebar **Rules** tab → **Browse…** | same as project scope |

**Layout:** `NavigationSplitView` — file list (left) + detail (right).

**List:** file name, category, section count, source badge (`bundled` / `project` / `dev`), enabled/disabled indicator.

**Filters:** text search (filename + section headings/content), category picker, source segment (All / Bundled / Project / Development).

**Detail pane:** enable toggle (persisted per project in `enabledRuleFileIDs`), path, priority, collapsible **section outline** with full text, full **raw markdown** (selectable).

**Actions:** Reload, Close; **Reveal project rules** when a project is open (opens `edit-rules/` in Finder).

**Workspace sidebar (compact):** enabled/total counts, file list summary, **Browse…** opens the full browser.

Rule files are read-only in-app in MVP (edit on disk in Finder or external editor); toggling enabled state is the only in-app mutation besides reload.

---

## Deterministic rule engine

`ProseRule` protocol; `RuleInput` with project, document, chapter, scene, paragraph, text window, canon, edit rules, scope.

Implement conservative checks including (non-exhaustive):

1. Repeated words in paragraph.
2. Repeated words across nearby paragraphs.
3. Repeated phrase fragments.
4. Excessive short sentences / one-line paragraphs.
5. Repeated sentence openings.
6. Triadic / symmetrical contrast patterns.
7. Dialogue without trigger; dialogue symmetry.
8. Repeated gestures; generic sensory overuse; atmosphere vocabulary repetition.
9. Latin in Ukrainian prose; terminology; canon spelling; calques.
10. False agency (city/night/silence/rain/room/object).
11. Object continuity.
12. Mood without action; emotion without behavior.
13. Scene missing function; scene missing pressure shift.
14. Repeated chapter scene shapes; document motif overuse; escalation stagnation.

If uncertain, **warn**—do not replace literary judgment.

---

## Safe auto fix

`SafeAutoFixEngine`: spaces, punctuation, quotes, dashes, terminology/canon replacements only.

Never auto-fix rhythm, dialogue, structure, atmosphere, POV, pacing, splits, creative rewrites. Non-safe → diagnostic or `ChangeProposal` (user reviews).

---

## Pipeline engine

No single “improve text” call. Passes with `PipelinePassMode`: deterministic | llm | hybrid.

**Default passes (0–16):** Minimum Gate, Text Integrity, Structure, Causality/POV, Canon/Terminology/Language, Rhythm, Dialogue, Character Voice, Atmosphere/Sensory, World/Magic/Information, Action/Violence/Aftermath, Repetition/Tautology, Escalation/Pacing, Scene Function, Multi-Scope Continuity, AI Marker, Manual Review Readiness.

UI per pass: pending, running, completed, failed, diagnostics/proposals counts, rules used, context scope.

Persist `AnalysisRun` history per project.

---

## Mandatory iterative scope expansion

For a local issue, expand in order—**never** jump to whole-book context first:

1. sentence / selection  
2. paragraph  
3. previous + current paragraph  
4. current + next paragraph  
5. scene  
6. previous scene + current scene  
7. chapter section  
8. whole chapter  
9. previous chapter end + current chapter  
10. document  
11. project canon/memory  

Each scope checks different concerns (wording, rhythm, continuity, function, pacing, canon drift, etc.).

---

## Local model routing & task scheduling

**Mandatory product behavior.** iV is not “many models always running.” It is:

- one active **primary** LLM (generative) at a time by default;
- one optional **embedding** model when enabled;
- deterministic checks first;
- LLM only when useful;
- queued, cancellable background tasks;
- strict memory / keep-alive policy.

The app must avoid: loading multiple large models simultaneously; LLM on every keystroke; sending whole documents to LLM by default; keeping unused models in memory forever; background work that stutters the editor.

### Core components

| Component | Responsibility |
|-----------|----------------|
| `LocalModelRouter` | Pick model/backend; sync vs async; mechanical-only; queue/skip/defer; reuse loaded model; unload before switch |
| `ModelMemoryManager` | Track loaded model, last used, unload via Ollama keep-alive, enforce `maxLoadedLLMModels` |
| `AnalysisQueue` | Priority queue, dedupe by scope, cancel on typing |
| `PerformancePolicyService` | Debounce, battery/Low Power, mode gates |

### Model roles

1. **Primary reasoning / editorial** — paragraph/scene/dialogue/atmosphere analysis, rewrite proposals, skeleton expansion, chapter split reasoning, manual review checklist. Suggested families: Qwen3 8B/14B via Ollama (user-mapped; not hardcoded as mandatory).

2. **Fast utility** (optional) — quick summaries, cheap classification, short explanations, lightweight JSON. If missing → use primary; do not require a second model.

3. **Embedding** (optional) — semantic search, similar paragraphs, canon retrieval, context selection. Examples: `mxbai-embed-large`, `nomic-embed-text`, `embeddinggemma`. MVP may use lexical index only; architecture must support embeddings.

4. **Disabled / mechanical only** — Ollama unavailable, Quiet Mode, user disabled AI, battery/thermal block, safe lint tasks.

### ModelSettings (persisted per project)

```swift
ModelSettings {
  primaryModelName
  utilityModelName?          // optional
  embeddingModelName?
  allowUtilityModel
  allowEmbeddings
  maxLoadedLLMModels         // default 1
  maxConcurrentLLMTasks      // default 1
  keepAlivePolicy            // balanced | quiet | intensive | manual
  performanceMode            // links to PerformanceMode
}
```

Defaults: `maxLoadedLLMModels = 1`, `maxConcurrentLLMTasks = 1`, embeddings **off** until user enables, primary handles all LLM if no utility, mechanical always available. Detect installed Ollama models; let user assign **roles** (`generalReasoning`, `proseAnalysis`, `summarization`, `embeddings`, `fastUtility`, …)—suggestions only, not enforced truth.

### Keep-alive / memory policy

Ollama supports `keep_alive`. `ModelMemoryManager` must implement real unload/reuse—not fake memory control.

| Mode | LLM load | Unload |
|------|----------|--------|
| **Balanced** | Keep primary briefly after user-triggered analysis | Unload after idle; do not keep utility if primary loaded |
| **Quiet** | No auto-load | Unload after task when possible |
| **Intensive** | Primary may stay loaded longer | Still max one large generative model |
| **Manual only** | Load only on explicit user action | Unload after task or short idle |

When switching large models with `maxLoadedLLMModels = 1`: unload previous first; show **Switching local model…** in status UI.

Prefer: fewer switches; reuse loaded primary; batch small tasks for same model; unload after idle. Do **not** load primary + utility + embedding simultaneously by default.

### Task routing table

**Synchronous / UI-adjacent (no heavy LLM by default)**

| Task | Policy |
|------|--------|
| Typing | No LLM; no heavy analysis |
| Paragraph indexing after edit | Fast background; no LLM; never block typing |
| Mechanical diagnostics (current paragraph) | Debounce 500–1000 ms; deterministic; Active Watch |
| Safe Auto Fix preview | Deterministic; feels instant |
| Diagnostic list filter/sort | Local only |

**Asynchronous (queued, cancellable)**

| Task | Model | Notes |
|------|-------|-------|
| LLM paragraph analysis | primary or utility | Debounce 3000–7000 ms Active Watch; dirty scope only |
| LLM transition analysis | primary/utility | Paragraph window only |
| Scene logic | primary | After paragraph tasks |
| Dialogue | primary (utility if proven) | |
| Atmosphere | primary | |
| Rewrite proposal | primary | **User-triggered only** → ChangeProposal |
| Scene expansion | primary | **User-triggered only**; multi-pass |
| Chapter split analysis | primary | User-triggered or low priority; never auto-split |
| Chapter escalation/pacing | primary | Low priority; idle or manual |
| Document/project checks | primary | Lowest; not during typing unless full pipeline |
| Embedding updates | embedding only | Delta; low priority; cancellable |

### Model selection by task type

| Task | Model |
|------|-------|
| Mechanical lint, safe auto-fix, rule parsing | none |
| Rhythm/repetition (detection) | deterministic first; LLM optional for explanation |
| Language/canon exact replacements | deterministic first |
| Paragraph explanation | utility if available, else primary |
| Scene logic, dialogue, atmosphere, action, world/lore | primary (+ canon context) |
| Rewrite selection, expand skeleton, chapter split | primary only |
| Summaries | utility if acceptable, else primary |
| Canon extraction | primary; never auto-apply |
| Embeddings / semantic retrieval | embedding model if enabled; else lexical fallback |

### No model spam rules

- Active typing **cancels** pending LLM tasks.
- Only **latest dirty scope** analyzed; dedupe same scope/task.
- No scene/chapter LLM while paragraph LLM pending unless user requested.
- No project-level LLM in Active Watch.
- No LLM if mechanical diagnostics already **block** same scope.
- No rewrite / scene expansion unless user explicitly requests.

### Concurrency limits (defaults)

- `maxConcurrentMechanicalTasks` — reasonable system default (parallel small jobs OK).
- `maxConcurrentLLMTasks = 1`
- `maxLoadedLLMModels = 1`
- `maxConcurrentEmbeddingTasks = 1` (if embeddings enabled)

Editor always has priority over analysis.

### Performance modes

| Mode | Behavior |
|------|----------|
| **Quiet** | Mechanical only; no auto LLM; no embedding updates while typing; unload models quickly |
| **Balanced** | Default; mechanical debounce; LLM current paragraph/window or explicit action only |
| **Intensive** | Scene/chapter background OK; embeddings updates OK; still one heavy LLM by default; warn on battery |
| **Manual only** | No background analysis; user-triggered only |

`PerformancePolicyService`: debounce durations; AC vs battery (IOKit); Low Power Mode; pause LLM with visible reason.

### LLM JSON / generation settings

**JSON diagnostic tasks:** temperature 0.0–0.2; JSON schema when supported; short max output; no creative generation; strict validation; **retry once** with stricter prompt; then fail safely (diagnostic, no manuscript mutation).

**Rewrite / scene expansion:** slightly higher temperature if needed; never auto-apply; before/after proposal; run deterministic lint after generation.

**Summaries:** low temperature; compact; tied to `sourceHash`.

### Pipeline model usage

Each pass decides: (1) deterministic sufficient? (2) LLM needed? (3) scope small enough? (4) user idle? (5) model loaded? (6) worth latency/memory? If no → skip/defer LLM pass; deterministic diagnostic only.

### Embedding / semantic index strategy

Not mandatory for MVP. Lexical index + hashes + repeated phrase checks + summaries first.

When enabled: update **changed paragraphs only**; background low priority; cancellable; no full re-embed unless user rebuilds; never during active typing unless tiny delta and Intensive mode.

Use cases: similar paragraphs, repeated scene patterns, canon retrieval, context selection.

### Local AI status UI

Show clearly: AI disabled · Ollama unavailable · Model loading · Model loaded · Running analysis · Queued · Paused while typing · Deferred by performance mode · Unloading model · Failed.

Also: current model name, task type, queue count, performance mode, document save state.

### Failure behavior

| Failure | Behavior |
|---------|----------|
| Model unavailable | Deterministic checks work; clear message; editor not blocked |
| Invalid JSON | No manuscript mutation; diagnostic; user may retry |
| Timeout / slow | Cancel; mark timed out; editor responsive |
| Expensive model switch | Queue or confirm by task importance |

### Default recommended configuration (Apple Silicon laptop)

- Mode: **Balanced**
- One primary model; no required utility; embeddings **disabled** initially
- Suggested primary: Qwen3 8B (speed) or 14B (quality) if RAM allows
- Suggested embedding if enabled: `mxbai-embed-large` or `nomic-embed-text`
- Do not force model names—detect Ollama list and map roles in Settings

### Correct vs incorrect behavior

**Correct:** user types → mechanical checks on dirty paragraph → index marks dirty scopes → LLM waits for pause → one model, one task → diagnostics/proposals → editor responsive → unload per policy.

**Incorrect:** multiple LLM calls per keystroke → several models in RAM → whole chapter sent automatically → editor stutters → AI rewrites without review → memory spikes.

---

## Ollama provider

Default endpoint `http://localhost:11434`. Implement via `OllamaAIProvider` behind `LocalAIProvider` + router.

### LLM task types

Paragraph/scene/dialogue/voice/atmosphere/action/world analysis; transitions; rewrite suggestions; scene expansion; chapter splits; repetition/escalation; summaries; canon extraction; rule validation; manual review checklist.

### Strict JSON contract

`LLMAnalysisResponse` with `diagnostics`, `changeProposals`, `summaryUpdates`, `canonUpdateSuggestions`, `manualReviewReady`. Parse failure → diagnostic, no apply. LLM failures must not corrupt manuscript.

---

## Context builder

`ContextPacket`: task, scope, current/previous/next text, scene/chapter/document/project summaries, **previousSceneSummary**, relevant rule excerpts (category-selected, not all files), relevant canon, objects, character states, threads, existing diagnostics.

**Context preview** in UI before LLM runs.

---

## Scene expansion mode

Skeleton + beats + outcome + constraints → pipeline (validate, draft, deterministic lint, scoped passes) → **`ChangeProposal` only**—never direct manuscript replace.

---

## Chapter split system

Suggest splits (time/location/POV shift, tension loop, cadence, length, etc.). Output: paragraph id, confidence, reason, risk, split type (soft section | hard chapter | none). **No automatic split**—user creates proposal from suggestion.

---

## Narrative diagnostics

Repeated escalation, argument shapes, scene shapes, atmosphere entropy, sensory/gesture repetition, pacing stagnation, missing consequences, forgotten threads, voice drift, canon/timeline/location/object continuity.

---

## Memory / canon vault

CRUD for characters, locations, terms, institutions, magic, timeline, objects, relationships. Memory is source of truth; LLM suggests updates → **user approves** (`CanonUpdateSuggestion` flow).

Summaries: scene, chapter, document, project—stored, versioned (`sourceHash`), stale when text changes.

---

## Diff / revision review

All creative changes → `ChangeProposal` → review.

**Revision split** (side-by-side):

1. **Read** — clean comparison.  
2. **Light highlight** — changed regions only.  
3. **Full diff** — insert/delete highlighting; accept/reject whole proposal minimum; edit-before-accept.

Available for paragraph rewrite, scene expansion, chapter proposals, any AI/deterministic proposal.

---

## Diagnostics UI

Filter: severity, scope, source, rule category, fix level. Click → scroll. Ignore / resolve / safe fix / create proposal / deeper analysis.

**Active Watch panel** (compact): severity-sorted, source icons (mechanical | LLM | pipeline), one-line titles; tap → detail sheet.

Inline highlights: info (subtle) → warning → error → blocking.

Show **stale** diagnostics distinctly; do not delete until refreshed.

---

## Active watch mode

Optional; never blocks typing; **never** auto-rewrites.

- Toggle on/off (toolbar + settings).
- **Mechanical:** debounce 500–1000 ms after typing stops; dirty paragraph/window only.
- **LLM:** debounce 3000–7000 ms; cancel on resume typing; one job per scope; dirty scope only—never whole document in background.
- Queue mechanical before LLM; pause LLM on battery/low power when policy says so.

Panel in inspector; full list remains in Diagnostics tab.

---

## Project-wide paragraph index & delta-based analysis

`ParagraphIndexService` + `ParagraphIndexer`:

- index all paragraphs; stable ids; hashes; order; scene/chapter membership;
- on edit: diff hashes → `ParagraphDirtyState` → mark dependent scopes dirty;
- invalidate/stale diagnostics for changed text; cache unchanged;
- pipeline/watch rerun **affected scopes only** unless user requests full pass.

Behaves like an IDE/compiler, not a batch rewriter.

---

## Analysis queue

Implements routing priorities from **Local model routing & task scheduling**:

1. Editor-critical  
2. Paragraph mechanical  
3. Paragraph window mechanical  
4. Scene mechanical  
5. Selected LLM  
6. Chapter mechanical  
7. Chapter LLM  
8. Document/project background  

Typing cancels stale LLM; dedupe by `scopeKey`; expose pending count in status bar.

---

## Semantic index

`SemanticIndexService` protocol; `OllamaSemanticIndexService` when embeddings enabled. Lexical fallback always available. See embedding policy in local model routing section.

---

## Manual review ready

Aggregate: blocking, errors, warnings, style/canon/logic/AI-pattern risks, pending proposals. Ready when blockers cleared, passes done, high-risk proposals decided.

---

## Commands / menus / shortcuts

New/Open project, **edit/delete project**, import/export (text, RTF, DOCX), paragraph/scene/chapter analysis, full pipeline, safe auto fix, scene expand, chapter split, context packet, refresh summaries, **Edit Rules browser**, canon/diagnostics/diff, Ollama check, **command palette** (e.g. ⇧⌘K), find (⌘F).

---

## Writing safety & scene structure

Local-first **undo/redo**, **safety snapshots**, and **scene indexing** inside chapters. These protect high-trust manuscript data without turning iV into version control or a dashboard.

### Undo / Redo

- **Engine:** AppKit `NSTextView` with `allowsUndo = true` and `NSUndoManager` (not web-editor plugins).
- **Shortcuts:** ⌘Z undo, ⌘⇧Z redo when the manuscript editor is first responder.
- **Rules:** Autosave and SwiftUI binding sync must **not** replace the full document string while the user is editing (only on document load, import, or snapshot restore). App menu undo/redo forwards to the active `NSTextView` via `EditorUndoController`.
- **Optional UI:** Subtle Undo/Redo in the formatting toolbar; disabled when unavailable.

### Local safety snapshots

Not Git, not cloud history — **recovery points** on disk under `{project}/snapshots/{documentID}/`.

Each snapshot stores: project id, document id, optional chapter/scene ids, plain text, format version, timestamp, reason type, word count, schema/app version.

**Reason types:** `manual`, `autosave_checkpoint`, `before_destructive_action`, `before_bulk_replace`, `before_import`, `before_scene_reindex`, `before_rule_apply`, `recovery`.

**Triggers (minimum):** before delete project/document, import replace, accept proposal / automated rewrite, scene re-index, project close with unsaved→saved checkpoint; periodic checkpoint after save when word-count delta or time threshold met (not every keystroke).

**Retention:** default **30** snapshots per document; always retain `before_destructive_action` until a newer stable save exists; prune oldest non-protected entries.

**Restore:** list snapshots (time, type, word count) → confirm → snapshot current content as `before_destructive_action` → replace manuscript → reload editor epoch.

**Save state:** `Saved` / `Saving` / `Unsaved` / explicit error — never show Saved if persistence failed.

### Scene detection & chapter scene index

Chapters contain **scenes** (paragraph-ID–anchored). Detection is **deterministic** for MVP (no required AI).

**Signals:** explicit separators (`***`, `---`, `#`, etc.), heading-like scene labels, imported breaks, multiple blank lines (lower confidence). **Manual boundaries are authoritative** — re-detection preserves manual scenes and titles.

**Scene metadata:** stable id, order, start/end paragraph ids, title, boundary source, confidence, index status (`clean` | `needs_review` | `stale` | `user_corrected`), preview, word count, placeholders for summary/character/location hints.

**User actions:** jump, rename, split at cursor (insert separator), merge with previous/next (index only — no text delete), re-run detection, mark index reviewed. **Delete scene text** is destructive (confirm + snapshot). **Remove scene boundary** merges index only.

**UI:** Scene list in workspace sidebar (scenes tab); active scene in status bar (`Chapter · Scene · words`). Editor remains central.

**Staleness:** large edits / paste / boundary-adjacent changes mark index `stale` or affected scenes `needs_review`; save persists structure + scene index together.

### Interaction rules

| Layer | Role |
|-------|------|
| Undo/redo | Short-term editor history |
| Snapshots | Medium-term recovery |
| Scene index | Structural metadata for navigation & future context |

Snapshot **before** restore, delete chapter/scene text, import overwrite, proposals/automated rewrite, scene re-index. **Not** before normal typing or rename.

**Code map:** `EditorUndoController`, `ManuscriptSnapshotStore`, `SceneDetector`, `SceneIndexService`, `SceneIndexPanelView`, `ManuscriptSnapshotsView`.

---

## Implementation milestones

1. App shell, library, persistence  
2. NSTextView editor, indexing, autosave, structure, **undo/redo**, **safety snapshots**, **scene index**  
3. Import/export + DOCX boundaries  
4. Edit rules loader + UI  
5. Deterministic engine + diagnostics + safe fix  
6. Pipeline + scope expansion + analysis runs  
7. Local model router + memory manager + Ollama + JSON validation  
8. Context builder + canon + summaries  
9. Proposals + diff/revision split  
10. Scene expansion + chapter split + narrative diagnostics  
11. Active watch + queue + performance modes + polish  

---

## Acceptance criteria

1. Create project.  
1b. Edit project metadata (name, subtitle, cover) from library or overview.  
1c. Delete project with confirmation; folder removed from disk.  
1d. Other destructive actions use confirmation per policy table.  
2. Edit and save text; autosave debounce + ⌘S + save-state indicator; atomic writes.  
3. Paragraph IDs persist.  
4. Chapters/scenes exist.  
5. Edit rules loaded; **Edit Rules Browser** available from library, overview, and workspace (search, filters, section outline, enable toggle).  
6. Missing rules folder does not break app.  
7. Deterministic diagnostics run.  
8. Safe auto fix is safe-only (creative via proposals).  
9. Multi-pass pipeline runs.  
10. Scope expansion works.  
11. Ollama works when installed; **LocalModelRouter** enforces one LLM task / one loaded large model by default.  
12. App works without Ollama.  
13. LLM JSON validated.  
14. LLM failures do not corrupt manuscript.  
15–16. Proposals as diffs; accept/reject/edit.  
17. Canon/memory exist.  
18. Context preview exists.  
19. Scene expansion → proposal.  
20. Chapter split suggestions (+ proposal path).  
21. Export at least plain text.  
22. **No creative change silently applied.**

---

## Final target experience

User writes prose. iV analyzes mechanically, expands scope gradually, uses local AI only when useful, proposes changes as diffs. User remains final authority.

**iV is a deterministic, iterative, context-aware native macOS prose IDE.**

---

## Agent note (repository)

- **This file** = product specification for humans and coding agents planning iV features.  
- **[`BRAND_BOOK.md`](BRAND_BOOK.md)** = mandatory visual system (forest/ivy/neutral editor).  
- **`src/edit-rules/*.mdc`** and **`Resources/edit-rules/`** = runtime manuscript editing rules for the app, **not** this spec.  
- **`.cursor/rules/*.mdc`** = Cursor coding-agent rules; [`05-visual-brand-system.mdc`](../.cursor/rules/05-visual-brand-system.mdc) enforces UI.
