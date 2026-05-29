# iV — Document Editor Architecture (Audit & Direction)

**Status:** Approved direction — March 2026  
**Supersedes:** treating `RichTextEditor` / `NSTextView` as the final manuscript surface.

---

## 1. Current editor assessment

### 1.1 Current engine / components

| Component | Path | Role |
|-----------|------|------|
| `RichTextEditor` | `iV/Editor/NSTextViewRepresentable.swift` | SwiftUI wrapper |
| `NSTextViewRepresentable` | same | AppKit `NSTextView` in `NSScrollView` |
| `FormattingToolbar` | `iV/UI/Editor/FormattingToolbar.swift` | Bold, italic, underline, H1/H2, undo/redo |
| `EditorFormatting` | `iV/Editor/EditorFormatting.swift` | Attribute toggles on `NSTextView` |
| `EditorUndoController` | `iV/Editor/EditorUndoController.swift` | Forwards to `NSUndoManager` |
| `FindReplaceBar` | `iV/Editor/FindReplaceController.swift` | Find/replace over plain string |
| `Document` model | `iV/Domain/DomainModels.swift` | `plainText` + optional `formattingSpans` in JSON sidecar |
| `DocumentStore` | `iV/Storage/DocumentStore.swift` | Persists `manuscript/{id}.json` |
| DOCX import/export | `iV/DOCX/*`, `ImportExportCapability.limitedDOCX` | **Import → plain text + spans; export → minimal OOXML** |

Workspace integration: `WorkspaceView` → `manuscriptEditor` → `RichTextEditor`; diagnostics overlaid as background highlights on character ranges in `NSTextView`.

### 1.2 What the current editor can do

- Edit **plain text** with basic rich attributes (bold, italic, underline, two heading levels) inside `NSTextView`.
- Native macOS undo/redo (when document string is not replaced from SwiftUI binding).
- Find/replace on plain string.
- Paragraph indexing and diagnostics tied to **UTF-16/NSString ranges** in plain text.
- Import/export: **plain text (full)**, **RTF (text only)**, **DOCX (limited)** — honest labels in UI.
- Reference pane, revision split review, snapshots, scene index (plain-text–based).

### 1.3 What it cannot do (and will not without unsustainable effort)

- Open/edit/save **real DOCX** with Word/Google Docs fidelity.
- Tables, images, comments, footnotes, headers/footers, section breaks, styles gallery, paste from Word with layout preserved.
- Page layout, pagination, print preview as in an office suite.
- Collaborative editing, track changes (Word-native).
- Building a “Word clone” toolbar on `NSTextView` — explicitly **out of scope**.

### 1.4 Why it cannot become a full DOCX editor

DOCX is OOXML: thousands of elements, styles, relationships, themes, numbering definitions, compatibility modes. A production editor requires:

- Layout engine (pagination, floats, tables).
- Style inheritance and numbering restart rules.
- Round-trip testing against Word, not “valid ZIP with `word/document.xml`”.

The current `DOCXParser` / `DOCXRichParser` extract text and a **small span list**; export writes a **minimal** archive. That is appropriate for **import assistance**, not as the **authoring surface**.

**Conclusion:** `NSTextView` + homemade DOCX IO is a **prototype/stub**. Do not expand `FormattingToolbar` into a Word clone.

### 1.5 What to keep vs replace

| Keep (app shell) | Replace / demote |
|------------------|------------------|
| Project library, overview, registry | `FormattingToolbar` as primary chrome (office engine has its own) |
| Rules, canon, memory, diagnostics, pipeline | `RichTextEditor` as **final** editor |
| Proposals, diff review (interim for plain-text proposals) | Limited DOCX as “full editor” narrative |
| Snapshots, scene metadata layer | Plain-text-only assumption for primary save path |
| Ollama / local AI, context builder | Homemade DOCX editing |
| Command palette, settings, status bar | |
| **New:** embedded office editor host, AI chat panel, selection bridge | |

---

## 2. Required DOCX capabilities (product target)

Target: **real document editor** via mature embeddable engine (ONLYOFFICE Document Server, Collabora Online, or equivalent).

See §3 for engine comparison. Capabilities checklist (engine-dependent):

- Core: open/edit/save DOCX, formatting preservation, undo/redo, paste from Word/Docs, shortcuts, styles, fonts, colors, alignment, lists, spacing, page/section breaks, images, tables.
- Advanced (if engine supports): headers/footers, comments, footnotes/endnotes, outline navigation, find.
- **Not** “convert to HTML and edit as rich text.”

---

## 3. Architecture decision: **Option A (recommended)**

### Option A — Embedded office editor as primary surface

**Preferred engine: ONLYOFFICE Document Server** (local instance), embedded in the macOS app via **WKWebView** loading the editor frame against `http://127.0.0.1:<port>/`.

| Criterion | ONLYOFFICE | Collabora Online |
|-----------|------------|------------------|
| DOCX fidelity | Strong; Word-oriented | Strong (LibreOffice core) |
| macOS desktop embed | Document Server + iframe/JS API; desktop packaging via local server | CODE + iframe; similar server model |
| Local-first | Yes — bundle/run Document Server locally; files stay on disk | Yes — local CODE server |
| Selection API | JS API (`GetSelectedText`, cursor, plugins) | UNO/PostMessage bridges; heavier integration |
| Licensing | AGPL v3 Document Server — **compliance review required** for distribution | MPL 2.0 / dual licensing — review required |
| Packaging | Docker or native server binary; app manages lifecycle | Similar |
| Risk | Server RAM, AGPL, bridge complexity | Heavier integration, server RAM |

**Option B (internal editor + DOCX import/export)** — **rejected** for stated product goal. Cannot reach Google Docs–level DOCX fidelity. May remain as **legacy fallback** for plain-text diagnostics-only workflows until Option A is stable.

### Local-first constraints

- Default: **no cloud accounts**, manuscripts on disk under project folder.
- Document Server runs **on localhost**; app starts/stops or documents prerequisite in Settings.
- File flow: project `manuscript/{documentId}.docx` is authoritative; JSON sidecar holds metadata, scene index, diagnostics anchors (not full duplicate prose long-term).
- **Explicitly document** if any build ships with remote Document Server URL (not default).

### Integration complexity (rough)

**IV-12 (incomplete):** WOPI/local file host + ONLYOFFICE DocsAPI `DocEditor` session + JS selection bridge. Until IV-12 ships, the app stays in `bridgePending` — never fake `.ready`.

1. **Phase 1:** WKWebView host + health check + honest unavailable/bridge-pending UI.  
2. **Phase 2:** Open/save DOCX via server callback / WOPI-like local file handler.  
3. **Phase 3:** JS bridge — selection text, insert/replace, change events.  
4. **Phase 4:** AI chat panel wired to bridge.  
5. **Phase 5:** Apply AI edits with snapshot + explicit confirm.  
6. **Phase 6:** Scene index from headings/outline API or extracted text.

---

## 4. AI chat layer (product)

Not a generic chatbot. **Document-aware, selection-aware** assistant panel (right side, collapsible).

### Use cases

1. Generate prose from scaffold (outline, beats, notes).  
2. Rewrite selection (“make this darker”, “expand scene”, …).  
3. Analyze selection (rules, voice, logic, continuity).  
4. Apply via explicit actions: insert at cursor, replace selection, append, copy — **never silent mutation**.

### Request model (Swift)

Implemented in `iV/AI/AiChatModels.swift`:

- `AiChatTarget`: `.selection` | `.cursor` | `.document` | `.project` with typed fields; `selectionRange` is `unknown` until editor API validated.
- `AiChatRequest`: project/document IDs, user message, target, rules context, scoped document excerpt, `instructionMode`.

### Safety

- Snapshot before replace/bulk insert (existing `ManuscriptSnapshotService`).  
- User must click **Replace selection** / **Insert** — no auto-apply.  
- Call out if editor API bypasses undo stack; prefer editor-native transactions.

---

## 5. Scene indexing with DOCX

Scene list remains **metadata layer** (`DocumentStructure`), not aggressive OOXML mutation.

| Source | MVP |
|--------|-----|
| Headings / outline from office API | Auto-detect when available |
| Separator markers in text | Fallback |
| Manual labels | Always |
| Bookmarks/custom XML | Only if engine supports safe anchors |

If range anchoring is unreliable, show scene list without jump-to-range until Phase 6.

---

## 6. Migration plan

### Remove / demote

- Mark `RichTextEditor` as **legacy prototype** (`@available(*, deprecated)` message in code comments).
- Stop investing in `FormattingToolbar` / `EditorFormatting` for DOCX fidelity.
- Relabel limited DOCX import/export as **auxiliary** (migration, backup), not primary authoring.

### Keep

- Entire project shell, diagnostics, pipeline, rules, canon, proposals (adapt to extracted text).
- Snapshots before destructive/AI ops.

### Integrate

| Area | Placement |
|------|-----------|
| Embedded editor | Center column — `EmbeddedDocumentEditorView` |
| AI chat | Right column — `AIChatPanelView` (beside or above inspector) |
| Selection bridge | `DocumentEditorBridge` ← office JS / legacy NSTextView |
| DOCX files | `manuscript/{id}.docx` + JSON metadata sidecar |

---

## 7. MVP implementation phases

| Phase | Deliverable |
|-------|-------------|
| **1** | Architecture doc, spec update, `DocumentEditorBridge`, office host UI, legacy fallback |
| **2** | Open/save local DOCX through Document Server |
| **3** | Selection extraction bridge |
| **4** | AI chat panel + Ollama requests with scoped context |
| **5** | Apply buttons + snapshots |
| **6** | Scene indexing via outline/text extraction |

**Current codebase phase:** 1 + 4 (UI/wiring); office server connection user-configured.

---

## 8. Risks

| Risk | Mitigation |
|------|------------|
| Document Server packaging | Document Docker setup in Settings; health probe |
| AGPL / licensing | Legal review before App Store / commercial ship |
| Selection/range `unknown` | Discriminated types; no fake precision |
| Undo after AI insert | Use engine APIs; test per engine |
| Diagnostics on DOCX | Extract plain text for indexing; stale when doc changes |
| Performance | Server memory; lazy load editor |
| Privacy | Localhost only by default; no upload |

---

## 9. Code map (new)

```
iV/Editor/DocumentEditor/
  DocumentEditorModels.swift      — engine kind, selection snapshot, capabilities
  DocumentEditorEngine.swift      — protocol
  DocumentEditorBridge.swift      — observable bridge
  LegacyNSTextDocumentEditor.swift
  ONLYOFFICEEditorHost.swift      — WKWebView + config
  EmbeddedDocumentEditorView.swift
iV/AI/
  AiChatModels.swift
  AiChatService.swift
iV/UI/AI/
  AIChatPanelView.swift
```

Legacy paths unchanged but routed through bridge when `documentEditorKind == .legacyPrototype`.
