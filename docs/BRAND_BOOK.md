# iV Visual System / Brand Book

Canonical visual identity for the iV macOS app. **Mandatory** for all UI work.

Cursor agents: see also `.cursor/rules/05-visual-brand-system.mdc`, `.cursor/rules/56-typography-system.mdc` (always on), and `.cursor/rules/55-ui-visual-implementation.mdc` (Swift UI files).

**Editorial manuscript rules** (`edit-rules/*.mdc`, prose pipeline) are **not** visual brand — see [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) § Edit Rules.

---

## 0. Core visual identity

**iV is NOT:** an AI toy, cyberpunk app, startup landing page, neon dashboard, glassmorphism experiment, productivity-influencer app, Notion clone, chat application.

**iV IS:** native macOS prose workstation, literary IDE, focused writing environment, professional authoring tool, document-first system, calm dense serious workspace.

**Tone:** deep focus, quiet intelligence, restrained sophistication, editorial confidence, immersive concentration, native desktop professionalism. Dark library at night, muted forest, old paper under neutral light, macOS pro app.

---

## 1. Primary visual direction

**FOREST + IVY ACCENTS + NEUTRAL DOCUMENT SURFACE**

| Zone | Palette |
|------|---------|
| Chrome (sidebars, toolbars, inspectors, diagnostics chrome) | Dark forest |
| Accents (active, focus, success, progress) | Ivy green — **restrained** |
| Manuscript editor | Neutral document — **never forest** |

Manuscript must feel: readable, neutral, trusted, print-like, low-fatigue (Google Docs / native editor — not Obsidian neon).

---

## 2. Global principles

Dark-first, typography-first, dense but breathable, low-noise, structured, minimal not sterile, immersive not theatrical, native.

**Avoid:** decorative clutter, floating gimmicks, giant gradients, massive blur, oversized cards, over-animation, glowing borders, excessive transparency.

**Readability:** primary chrome text must never look disabled. Use `chromeDisabled` only for truly disabled controls.

**macOS native:** keep standard traffic lights visible; never draw fake window buttons. Custom top chrome (`.ivIntegratedChrome`) sits **below** the system titlebar — no fake traffic lights, no extra-large leading pad on the logo row.

**Chrome/content separation:** use `.ivChromeFooter`, `chromeEdgeGap` (6pt), `.ivChromeScrollContent()` — avoid `ZStack` + full-bleed canvas over main content (breaks safe-area insets).

---

## 3. Color system

### 3.1 Forest (chrome)

| Token | Hex | Use |
|-------|-----|-----|
| Forest Black | `#0F1A14` | App background |
| Forest Deep | `#0F1F18` | Base chrome |
| Forest Surface | `#152418` | Sidebars, panels |
| Forest Elevated | `#1E2E25` | Elevated panels, toolbar, status bar, empty-state card |
| Forest Hover | `#274037` | Hover fills, dividers |

### 3.2 Ivy (accent — restrained)

| Token | Hex | Use |
|-------|-----|-----|
| Ivy Primary | `#2E7D5B` | Primary fills, success, progress, selection tint |
| Ivy Bright | `#3FA370` | Ivy UI states |
| Ivy Soft | `#64C080` | Logo tint, ivy labels |
| Ivy Glow | `#A7E0C1` | Soft ivy highlight |

**Ivy is brand green** — primary/success/progress. **Not** the firefly hover edge (see §3.2a).

Use for: pipeline running icons, accepted proposals, muted selection fills. **Do not flood UI with green.**

### 3.2a Firefly (warm micro-accent — separate from ivy)

| Token | Hex | Use |
|-------|-----|-----|
| Firefly Core | `#FFF7D6` | Tiny ember center |
| Firefly Warm | `#FFD66B` | **Hover/focus border** (1px crisp) |
| Firefly Amber | `#F5A524` | Focus pulse, editor top edge |
| Firefly Soft Shadow | `#FFD66B` @ 28% | Outer glow radius **2–3px max** |

**Firefly = warm lantern**, not green neon outline. Button text stays `chromePrimary` on hover — never bright green labels.

**Code:** `IVColor.fireflyCore` … `fireflySoftShadow`; logic in `IVFirefly.swift`.

### 3.3 Chrome text (UI only)

| Token | Hex / value | Use |
|-------|-------------|-----|
| Chrome Primary | `#E8EDEA` | Titles, toolbar labels, status emphasis |
| Chrome Secondary | `#B8C4BE` | Body, descriptions, status items |
| Chrome Tertiary | `#8A9A92` | Metadata, captions |
| Chrome Disabled | `#5C6B64` | Disabled controls only |

### 3.4 Editor / document (manuscript only)

| Token | Hex |
|-------|-----|
| Document surface | `#F6F7F8` |
| Secondary neutral | `#E5E7E8` |
| Text | `#111827` |
| Muted text | `#687280` |
| Selection | Soft ivy-tinted neutral highlight |

### 3.5 Diagnostics severity

| Severity | Treatment |
|----------|-----------|
| Info | Muted blue |
| Warning | Muted amber |
| Error | Muted orange-red |
| Blocking | Muted magenta-red |
| Success | Muted ivy green |

Never fully saturated RGB or hacker-terminal aesthetics. Editorial, not catastrophic.

---

## 4. Typography (mandatory)

Three distinct layers — **coherent but different**. Never treat typography as “default SF everywhere.”

| Layer | Family | Use |
|-------|--------|-----|
| **UI** | SF Pro Display (headers), SF Pro Text (labels/body) | Chrome, navigation, inspectors, dialogs |
| **Manuscript** | **New York** (default) | Editor body only — literary, print-oriented |
| **Monospace** | SF Mono | Evidence, paths, raw markdown, technical snippets |

### 4.1 Philosophy

Literary workstation, editorial IDE, calm nocturnal writing. **Avoid** startup/SaaS, sci-fi, gamer, cyberpunk, “AI assistant” onboarding tone.

### 4.2 UI typography

- **SF Pro Display** — large labels, screen titles, library headers (`Font.ivUIHeader`).
- **SF Pro Text** — interface body, buttons, inspectors, status bar, command palette (`Font.ivUIBody`, `.ivUICaption`).
- **Never** green-tint manuscript ink.

### 4.3 Manuscript typography (critical)

**New York** @ **18pt** (17–19 acceptable). Fallback: Charter → Literata → Source Serif Pro → Crimson Pro → Times New Roman.

**Forbidden manuscript body:** Inter, Poppins, Montserrat, Roboto, Futura, Orbitron, Bebas, fantasy/handwritten gimmicks.

**Manuscript text:** `#111827` — no green tint.

### 4.4 Navigation & sidebar

Xcode / JetBrains density: compact, structured, muted but readable.

### 4.5 Diagnostics

SF Pro Text, compact, technical-editorial. No giant red alarm headlines.

### 4.6 Empty states

Semibold title (`chromePrimary`) + readable muted body (`chromeSecondary`). Restrained **elevated panel** (`forestElevated` + border) — not invisible, not giant marketing card. Logo mark OK.

### 4.7 Command palette & status bar

Raycast / Spotlight density. Status bar: SF Pro Text ~10–11pt, **medium contrast** (`chromeSecondary` default, `chromePrimary` emphasis).

### 4.8 Scale & consistency

Subtle hierarchy only. Code: `IVTheme` in `iV/UI/Theme/IVTheme.swift`.

### 4.9 Living accent (“firefly”) system

Subconscious **warm** light in a dark forest — **not** ivy-green neon, not SaaS glow.

| Rule | Detail |
|------|--------|
| **Color** | **Warm** firefly tokens (§3.2a) — **never** ivy green for hover border |
| **Sparse** | Hover, selection, focus, running pipeline/LLM/index only |
| **Button hover** | **1px** (max 1.25px pressed) `Firefly Warm` border + optional 2–3px `Firefly Soft Shadow` — **no** wide green outline |
| **Shape** | **1px** crisp warm border (+ optional ≤2.5px soft shadow) on hover/focus/selection — **no** ember clusters on ordinary buttons, rows, or cards; warm breathing dots **only** for running pipeline / LLM / indexing |
| **Text** | Stays `chromePrimary` / `chromeSecondary` — do not turn labels bright green on hover |
| **Motion** | 120–180ms ease; breathing = warm point pulse on running work |
| **Forbidden** | Ivy/neon green outline, shadow radius 8+, scale jump, saturated `.tint(.green)` on firefly |

**Code:** `IVFirefly.swift` — `.ivFireflyRow`, `.ivFireflyCard`, `.ivFireflyBreathing`, `IVEditorChromeFocusEdge`; buttons via `IVFireflyButtonLabel`.

### 4.10 Buttons & interaction

| Style | Use |
|-------|-----|
| `.ivToolbar` | “Open…”, “Rules” — `chromePrimary`; warm firefly edge on hover |
| `.ivToolbarAccent` | “New Project” — `chromePrimary` text, forest fill, **warm** firefly border on hover |
| `.ivPrimary` | Dialog primary — `chromePrimary` text, warm hover edge |
| `.ivSecondary` / `.ivGhost` / `.ivIcon` | Forest/ghost fills; warm edge on hover only |

Disabled: no firefly glow. Hover: **never** cursor-only.

### 4.11 Window chrome & traffic lights

- **Native traffic lights** must remain visible in windowed mode.
- Custom header via `.ivIntegratedChrome()` sits **below** the native titlebar (traffic lights stay in system chrome). Do not add extra large leading inset on the custom bar.
- Do **not** hide the system titlebar in a way that removes traffic lights.
- Do **not** draw fake red/yellow/green buttons.
- `IVWorkspaceCanvas` may extend background horizontally/bottom only — not over titlebar controls.

### 4.12 Layout tokens (`IVLayout`)

| Token | Value | Use |
|-------|-------|-----|
| `windowHPadding` | 20 | Window, sidebar, status, sheets |
| `windowVPadding` | 10 | Sidebar filter blocks |
| `toolbarHeight` | 40 | `IVTopChromeBar` min height |
| `toolbarVPadding` | 8 | Top chrome vertical |
| `statusBarHeight` | 24 | Bottom infrastructural bar |
| `chromeEdgeGap` | 6 | Gap between header/footer chrome and content |
| `chromeScrollBottomPad` | 8 | Scroll tail under footer chrome |
| `panelCornerRadius` | 5 | Panels, buttons, empty-state card |
| `cardCornerRadius` | 6 | Project library cards |
| `buttonCornerRadius` | 3 | Toolbar / action buttons |
| `emptyStateTopFraction` | 0.24 | Empty-state optical anchor |
| `disabledOpacity` | 0.42 | Truly disabled controls only |

**SwiftUI helpers:** `.ivIntegratedChrome`, `.ivChromeFooter`, `.ivChromeScrollContent()`, `.ivWindowToolbar()`, `.ivSheetChrome()` (modest vertical pad).

### 4.13 Code map (source of truth)

| Concern | File |
|---------|------|
| Colors + firefly hex | `iV/UI/Theme/IVTheme.swift` (`IVColor`) |
| Typography | `iV/UI/Theme/IVTheme.swift` (`IVTheme`, `Font.iv*`) |
| Firefly behavior | `iV/UI/Theme/IVFirefly.swift` |
| Buttons | `iV/UI/Theme/IVStyling.swift` (`.ivToolbar` … `.ivIcon`) |
| Layout grid | `iV/UI/Theme/IVLayout.swift` |
| Top/bottom chrome, empty state | `iV/UI/Theme/IVComponents.swift` |
| Logo | `iV/UI/Theme/IVLogoView.swift`, asset `iVLogo` |
| App icon PNGs | `iV/Assets.xcassets/AppIcon.appiconset/`, `Scripts/generate_app_icon.swift` |

---

## 5. Layout (mandatory)

```
LEFT     → navigation / library / structure
CENTER   → manuscript / editor (dominant)
RIGHT    → diagnostics / context / inspector
BOTTOM   → status / progress / analysis
```

---

## 6–25. Component & pattern rules

See `.cursor/rules/05-visual-brand-system.mdc`.

**Project library:** default startup; restrained cards with `.ivFireflyCard()`; no Netflix hover zoom.

**Editor:** light neutral manuscript; forest chrome around it; comfortable prose width.

**Diff:** Read · Light highlight · Full diff (restrained).

**Active Watch:** IDE inspections, not chat.

**Logo:** `IVLogoView` / `IVBrandHeader` — bundled `iVLogo` asset, `ivySoft` tint; sizes 20–44pt by context; no giant hero logo.

**App icon:** `AppIcon.appiconset` — raster export of `iV/Resources/Brand/iVLeavesLogo.svg` on `forestDeep`, ivy tint `#64C080` (same mark as `iVLogo`). Regenerate after SVG changes: `swift Scripts/generate_app_icon.swift`.

**Motion:** subtle, fast, native — no bounce.

**Copy tone:** calm, editorial — never “AI magic”.

---

## Reference products

Structure: Xcode, IntelliJ, Final Cut. Editor: IA Writer, Ulysses. Diff: VS Code / JetBrains. Palette: Raycast, Spotlight.

---

## Final target

Calm native macOS literary workstation: dark forest chrome with readable text hierarchy, **warm** firefly embers (separate from ivy brand green), neutral manuscript, dense elegant layout, native traffic lights, editorial seriousness.
