# Photonz — the product model (how it all fits together)

**Status: v1.0, approved. This is the canonical answer to "how does the app
work and how do the surfaces fit together." It sits above UX-PATTERNS.md (which
says how the shell behaves) and AGENTS.md (which says how a page is styled). If a
page, feature, or idea contradicts this doc, the page is wrong, not the doc.**

The bar this doc must clear: *a competent builder could read only this section and
know how the app fits together.* If it can't, expand it here first.

---

## 1. The core model: one document, one layer stack, surfaces are lenses

There is ONE document engine. "Image editing", "UI design", and "video" are **not
separate apps** — they are **workspaces (lenses)** over the same document. A
workspace foregrounds a different tool set and different panels; it does not
change the engine, the layer model, or the inspector.

A **layer** is any of:

- **Raster** — pixels (a photo, a screenshot, a painted bitmap).
- **Vector / shape** — resolution-independent paths (pen, bezier handles,
  booleans). A path carries a **fill** and a **stroke**, and both are Paint. See
  "Vector strokes are brushes" below.
- **Text** — a type layer bound to a Type style.
- **Component instance** — a linked instance of a reusable layer tree.
- **Adjustment / filter** — a non-destructive effect (blur, grade, duotone,
  hue/curves) that clips to the layers below it.
- **Group / frame** — a container; a frame adds auto-layout + constraints.

Every layer lives in ONE layer panel, is edited through ONE inspector (contextual
to selection), and can carry the non-destructive **effect stack** (blur, shadow,
border, radius, opacity). Because adjustment/filter layers are *just layers*, they
apply to a UI frame exactly as to a photo. That is the whole unlock.

### Vector strokes are brushes (where vector and raster stop being separate)

A vector path's **stroke can be painted with a Brush**. You pick a brush from the
Library (scope = Brushes) and the path renders with that brush's tip, spacing,
scatter, pressure dynamics and texture — while the path itself stays fully
editable bezier geometry. Move an anchor and the brushed stroke re-renders. And
**closing a path makes a shape you can fill**, so the same object carries a Paint
fill and a brushed stroke at once.

This collapses the usual vector-vs-raster split: you are not choosing between
"precise but sterile" and "organic but unrepeatable". The geometry is exact and
re-editable; the mark is expressive.

**Why this matters most for the agent.** An agent emits precise coordinates —
`path.add()` with exact bezier control points — which is what makes agent output
reliable, diffable, and re-editable. But precise coordinates rendered as a plain
1px vector stroke look sterile and machine-made. Brushed strokes let the agent
**draw with exact bezier curves and still get a hand-drawn feeling**: the
structure is machine-precise, the surface is human. It also means a user can
restyle everything an agent drew by swapping one brush, because the brush is a
Style, not baked pixels. This is the clearest payoff of "everything is a layer,
everything is one command".

### What makes a surface a surface

A **workspace** = (which tools are in the tool strip) + (which panels are
foregrounded) + (whether the timeline dock is shown). Nothing else. Switching
Image ↔ UI ↔ Video re-arranges the chrome around the *same* document.

- **Image workspace** — raster + adjustment layers foregrounded; tools: Select
  (marquee/lasso/wand), Crop, Brush, Eraser, Heal, Clone, Pen, Text, Shape,
  Measure, Hand, Zoom.
- **UI workspace** — frame + component + text + auto-layout foregrounded; tools:
  Select, Frame, Component-insert, Shape, Pen, Text, Measure, Hand, Zoom.
- **Video workspace** — the same document **plus a time dimension**: layers gain
  in/out points and keyframes; the **timeline is the bottom dock**, shown only
  when the document has time. Tools: Select, Blade, Title/Text, Shape, Measure,
  Hand, Zoom.

---

## 2. Map to real Photonz (what actually ships today)

Photonz today has three real surfaces. The model reconciles them:

- **Image editor surface** and **Video editor surface** = one editor, two
  workspaces. The timeline appears when the document has time. Same layers,
  inspector, components, adjustments.
- **History overlay (⌘⇧H)** = the app's **front door / launcher**: capture
  history (screenshots + recordings) and the new-document entry. This is the
  "blank slate" a usage clickthrough starts from.
- The **UI-design / design-system / agent** capabilities are the **aspirational
  expansion** of the same editor — a new workspace and new layer emphases, NOT a
  fourth app.

"Can I do X here" questions resolve to "yes, because it's the same document":
apply a filter layer to a UI frame, drop a component onto a video track, measure a
photo or a button with the same Measure tool.

---

## 3. The reuse tier: Tokens → Styles → Components → Design Systems

- **Tokens** — named primitives (color, type, spacing, radius).
- **Styles** — named bundles of tokens (a text style, a fill, an effect).
- **Components** — reusable layer trees you instance and re-paint with Styles.
  Instances are **linked**; edit the main, all instances update.
- **Design System** — a named set of Tokens + Styles + Components. Components bind
  to **semantic** token slots, not hardcoded values, so swapping the active system
  re-resolves every component.

### The design-system questions, answered

- **Extract a system from a website** → an agent command (`system.extract(url)`)
  reads a URL, infers tokens (color/type/space/radius) + component patterns, and
  produces a named Design System.
- **Pick a system from a catalog** → the **Library panel, scope = Styles/Systems**
  — a browsable catalog you apply to the document.
- **AI applies different systems to the same components** → because components
  bind semantic slots, applying a foreign system re-themes them; the agent maps
  the foreign system's tokens onto your component's semantic slots.
- **Choose components** → the **Library panel, scope = Components**; drag = linked
  instance.

---

## 4. Everything is one command (UI == API == agent)

Every action maps to one API call (`run("tool.text")`, `layer.addAdjustment()`,
`system.apply(id)`, `panel.dock("right")`). Four equal ways to reach it: tool
strip, context menu, the compact command surface, and the ⌘K palette. An agent
drives the identical calls. This is why an agent can "extract a design system" or
"apply a grade to the UI" — it is the same command a user runs.

---

## 4b. The layout system: scalable, learnable, collapsible

The shipping app today is deliberately **lean and canvas-first**: a floating
bottom tool bar whose overflow tools collapse, a single collapsible right Layers
panel, the native macOS menu bar, and a slide-down history overlay (⌘⇧H). We are
**extending scope** (UI design, components, design systems, richer video), which
means more panels — so the layout must **scale without becoming a different app**.

The resolution: **one scalable dock system that is lean by default and grows by
collapsing, resizing, and scrolling — never by inventing new chrome per feature.**

### Non-negotiable layout requirements

1. **Responsive at every width.** Every page must render sensibly when narrow.
   Panels collapse to labeled rails or overlays; the tool bar overflows into a
   "more" menu (the shipping image editor already collapses overflow tools). No
   page may assume a wide window.
2. **Collapsible panels and panes.** Every dock and every panel group collapses —
   to an icon/label rail, or fully hidden behind a toggle. The user minimizes what
   they are not using; the canvas stays dominant.
3. **Resizable panes (Photoshop-like).** Drag a splitter to resize a dock or a
   panel group. Sizes are remembered.
4. **Scroll-constrained groups.** Long lists (Layers, Effects, component groups)
   render a **bounded** set inside their own scroll area with its own max height,
   so one long list never pushes its siblings off screen. Groups stack; each
   scrolls independently.
5. **History-first loop preserved.** The capture history (slide-down: All /
   Screenshots / Videos, filmstrip, per-item actions) stays the front door, and
   you open images and videos into the editor from there. Extending scope must
   never bury this fast path.

   **History is a GLOBAL surface, not a panel inside an editor window.** It has
   exactly two entry points, and both work with no editor window open:
   - the **global keystroke ⌘⇧H**, and
   - the **menu-bar (systray) app icon**, which shows the history.

   Photonz is a resident menu-bar agent, so the history overlay comes from that
   agent, over whatever is on screen. It is therefore the app's true launcher: you
   go history → pick a capture → it opens in the editor. Do NOT model history as
   an in-window toolbar button that only exists once you already have a document
   open; a page may show a convenience entry, but the canonical invocation is the
   keystroke or the menu-bar icon.

   **The history pane is CHROMELESS.** It is an overlay pane that shows over the
   UX with **no title bar and no window header**. It is not a window and must not
   wear one. Because it is global and chromeless it reads as a system surface, not
   a document window. Never give it a `.titlebar`, traffic lights, or a header row.

   **Anatomy (from the shipping app — build exactly this):**
   - A wide, floating, rounded glass panel anchored near the **top of the
     screen**, overlaying whatever is behind it. It is not attached to any window.
   - **Centered segmented filter**: `All` · `Screenshots` · `Videos`, with the
     active scope filled in the accent color.
   - **Top-right `Clear All`** with a trash icon. These two controls and the
     filmstrip are the entire surface: there is no other chrome.
   - A **horizontal filmstrip** of landscape capture thumbnails, each with its
     **relative timestamp beneath** ("14 minutes ago", "2 hours ago"). It scrolls
     horizontally as captures accumulate.
   - **Video captures** carry a play affordance and a **duration badge** (`0:01`)
     on the thumbnail, so kind is readable at a glance.
   - The **selected card** gets an accent ring and reveals an **action row beneath
     it**: copy, edit, pin, delete. Only the selected card shows actions.

   **Open direction (not yet built):** history is a global concept, so it could
   also be hosted inside a **content landing page** reached from the menu-bar
   icon — a home surface where recent captures live alongside "new document"
   entries. The overlay stays the fast path from anywhere; the landing page would
   be the browsable home. If we build it, the overlay and the landing page must
   show the SAME history content, not two divergent designs.
6. **Scalable, learnable patterns.** New capability must be expressed with the
   SAME small vocabulary — dock, panel group, collapse, resize, scroll, overflow,
   overlay. Learn the pattern once and it applies everywhere. A feature that needs
   brand-new chrome is a signal to adjust the foundation, not to invent locally.

### What this means concretely

- The **floating bottom tool bar** (tools + color + zoom, with overflow collapse)
  is the canonical tool surface for canvas work; the tool strip content changes
  per workspace (D4).
- The **right dock** hosts stacked, independently collapsible/scrollable panel
  groups (Layers, Properties/Inspector, Effects, Library). It resizes and can
  collapse entirely to a rail.
- The **native macOS menu bar** is the real command surface; ⌘K is a secondary
  palette, not the primary story.
- **Overlays** (history, and anything catalog-like that would crowd the canvas)
  slide over the canvas rather than permanently consuming width.

---

## 4e. Shell surfaces: the complete inventory

"The app" is not just the editor window. These are ALL the shell surfaces, and
every one of them is part of the design system. A page depicting any of them must
use the shared pattern, not invent one.

### 1. The menu-bar (systray) app menu
Photonz is a resident menu-bar agent, so this is the app's real root. It is a
standard macOS menu popped from the status icon. Contents, in order:

- **Capture Region** `⇧⌘4` · **Capture Full Screen** `⇧⌘3` · **Stop Recording** `⇧⌘5`
- **Show History** `⇧⌘H`
- **New Window** · **New from Clipboard** · **Open…**
- **Check for Updates…** · **Welcome & Permissions…** · **Preferences…** ·
  **About Photonz**
- **Quit Photonz** `⌘Q`

This menu is where capture starts, where history is shown, and where new
documents are created. It is a native menu: no custom chrome, no invented widget.

### 2. The history overlay
The chromeless global pane described in §4b requirement 5. Invoked by `⇧⌘H` or
**Show History** in the menu above.

### 3. The capture toast
After a screenshot or recording completes, a **floating result card** appears over
the screen: the **actual captured thumbnail** in a rounded dark glass card, with a
confirmation row beneath it — a green check plus **"Copied to clipboard!"**.
Multiple captures **stack** as separate cards. The toast is a real preview of what
you just captured, not a text-only notification, and it is the immediate
"it worked, and it's on your clipboard" feedback that makes the capture path feel
instant. It is transient and requires no dismissal.

### 4. The editor window(s)
The lean canvas-first shell of §4b: image documents, video documents, and any new
main surface we build UI from. Multiple windows may be open.

### 5. The launcher / landing window
A window that holds **no document**. It is where you start: recent captures
alongside the new-document entries, reached from **New Window** in the menu-bar
menu. Because it has no document it correctly has **no canvas, no floating tool
bar and no dock** — it is a window, but not an editor shell, and the screen
contract (§4c) must not demand editor chrome of it.

This is the "content landing page" direction: history is a global concept, so it
can appear both as the fast chromeless overlay (surface 2) *and* hosted in this
browsable landing window. **If both exist they must show the SAME history
content**, not two divergent designs. The landing window is also the natural home
for the §4f fork — "New" choosing the resource type and opening the right kind of
document.

Any NEW main surface we invent joins this list and must be specified here first.

---

## 4f. Modes vs. starting points (UI and image are NOT different apps)

The open question: *are UI design and image editing different experiences, and
should you be able to switch between them?*

**Decision: they are not different apps, and there is no mode to switch.** A UI
design and an edited screenshot are the same thing — layers on a canvas. The only
real differences are (a) which layer types you tend to use and (b) what the
document starts as. Making them modes would actively break the good cases:
annotating a screenshot with real UI components, or dropping a photo into a
mockup. Under one document, both just work.

So:

- **The fork happens at creation, not during editing.** "New" chooses the
  resource type and sets up the right document: canvas size, starting layers, and
  which panel groups and tools are foregrounded. Entry points are the menu-bar
  **New Window / New from Clipboard / Open…**, and opening a capture from history.
- **Once you are in a document, you do not switch experiences.** You never hunt
  for a mode. Tools and Properties are **contextual to the selected layer**:
  select a raster layer and brush/heal/clone apply; select a frame and
  auto-layout and constraints appear; select a path and fill/stroke appear.
- **Video is the one genuine difference, and it is not a mode either** — it is a
  property of the document. A document either has time or it does not; when it
  does, the transport and timeline appear ("timeline when time").

**Consequence for what we already built:** the persistent **workspace switcher**
(`.wsw`, an Image · UI · Video lens selector in the title bar) is **superseded**.
It models these as modes you toggle, which this decision rejects. Replace it with:
the document's own identity in the title bar, tools/panels driven by selection,
and the timeline appearing when the document has time. Keep a workspace concept
only as a *starting template* chosen at New, never as a live toggle.

---

## 4c. The screen contract: a real screen, or an honest specimen

The single biggest cohesion failure is windows that are **sketches of ideas
wearing app chrome**: a title bar with an essay in it, no toolbar, no dock, a
different set of panels than the window beside it. Every window in the study is
now exactly ONE of two kinds, and must declare which:

### Kind 1 — An app screen (depicts the product)

It MUST be **complete and canonical**. If it wears traffic lights and a title
bar, it is claiming to be the app, so it must actually be the app:

- The real shell: `.win.tall.cq` › `.titlebar` › `.toolbar` › `.edit.lean` with
  the canvas, the floating tool bar, and the dock groups appropriate to its
  workspace. **No arbitrarily missing toolbar. No arbitrarily missing dock.**
- **Title bar content is fixed** — traffic lights · **document identity** ·
  workspace switcher · document actions (Share / Export / Done). Document
  identity means the document's name plus its context:
  `settings-capture · 2560 x 1440`, `promo-cut · 0:18`, `untitled-1 · 1200 x 630`.
- **NEVER put a lesson title, feature name, or explanatory phrase in a title
  bar.** "Vector pen · resolution-independent shape" and "Brush · paints onto a
  raster Layer" are wrong: they are teaching copy, not a document. That text
  belongs in the page's `.scen-head` or a `.caption`, **outside** the window.

### Kind 2 — A specimen / anatomy (depicts a part, not the app)

It MUST NOT wear app chrome: **no traffic lights, no fake title bar**. Use a
plain labeled card or bordered block. A close-up of a control, a state ladder, a
token table, a curve editor in isolation are all specimens. Being honest about
this is what stops the study reading as fifty half-built apps.

### The consequence

A window that is genuinely "a sketch of an idea" and cannot satisfy Kind 1
belongs in **Prototypes & Ideas**, explicitly labeled an exploration. It may never
be presented as the app.

---

## 4d. Usage walkthroughs: ONE app, operated

A walkthrough is **not a slideshow of windows**. Today's format renders a new
illustration per step, so it can never answer the only questions that matter:
*what did I click, where does that control live, and what changed?*

The required pattern:

- **ONE persistent app screen**, rendered once. It does not re-render between
  steps. The chrome stays put so the user learns the app.
- **A step changes that screen's state** — the active tool, which dock group is
  open, the canvas content, the selection. It never swaps in a different window.
- **Each step anchors a click cue** to the **real control in its real location**
  (the tool in the floating bar, the Library rail tab, the `+ Import` button in
  the Library group), positioned on the actual element.
- **Each step's caption uses one grammar:**
  **Click** <control> **in** <where it lives> → **Result:** <what changed>.
- A step that cannot be expressed as a real click on a real surface is not a
  usage step. Either add the affordance to the app, or move the idea to
  Prototypes & Ideas.

This is what makes every walkthrough consistent and learnable: they are all the
same app being driven, so learning one teaches the rest.

---

## 5. Success criteria (the rubric we refine against)

A refine pass is "good" when all ten hold:

1. **One model, written down** — this doc answers how image/UI/video/layers/
   components/systems relate, and every page is consistent with it.
2. **Shell coherence** — every editor page answers on screen: *what document am I
   in, what tool/workspace is active, what is selected, where is my Library, how
   do I run a command.*
3. **Legible entries** — each surface has a **blank-slate clickthrough**: start
   with nothing → click → reach the key outcome, using the real docked shell.
4. **One walkthrough template** — every usage flow is built the same way (same
   stepper, same shell, same controls, same icons), so learning one teaches the
   rest.
5. **Foundation-gated features** — before any feature page: does it fit the
   framework, or must the framework change first? If it doesn't fit, adjust the
   foundation or move the page to Prototypes & Ideas.
6. **The build test** — a competent builder could read the App Design section and
   know how to build the app.
7. **Responsive & collapsible** — every page renders at small widths; docks and
   panel groups collapse and resize; long lists scroll inside their own bounded
   group (§4b requirements 1-4).
8. **History-first preserved** — the capture → edit fast path (⌘⇧H history →
   open an image or video in the editor) is intact and never buried by new scope
   (§4b requirement 5).
9. **Every screen declares its kind** (§4c) — an app screen is complete and
   canonically titled (document identity, never a lesson title, never an
   arbitrarily missing toolbar or dock); a specimen wears no app chrome; an idea
   sketch lives in Prototypes & Ideas. *Ask of every screen: does this make sense
   as a screen of the product we are designing, or is it just a sketch of an
   idea?*
10. **Walkthroughs are one app, operated** (§4d) — a single persistent screen
    whose state changes per step, with a click cue on the real control and a
    Click / Where / Result caption. No slideshows of separate windows.

---

## 6. Information architecture (how the site is organized)

Three zones, no standalone "Guided walkthrough" section:

- **App Design** (canonical) — the model (this doc made visible), the shell, the
  surfaces/workspaces, entrypoints, primitives, iconography, design language.
  "This *is* the app." A builder reads this to understand the whole.
- **Usage clickthroughs** — folded under each surface. Consistent "from a blank
  slate, do X" flows, ONE template, the real docked shell inside every step. Not a
  separate section — each lives with the surface it teaches.
- **Prototypes & Ideas** — the feature explorations, clearly labeled speculative,
  not canonical. Ideas that don't yet fit the framework live here until the
  foundation is adjusted to hold them.

---

## 7. The refine loop

Repeat until the six criteria hold:

1. **Model pass** — is the foundation right (shell, menus, toolbars, entrypoints,
   layers, tabs, workspaces)? Fix the foundation before touching features.
2. **Conform pass** — make every page sit in the model (the shell, the Library
   dock, selection → Inspector, one icon set). Promote repeated fixes into the
   shared DS, never per page.
3. **Entries pass** — one blank-slate clickthrough per surface, one template.
4. **Audit pass** — score every page against the six criteria; feed misses back
   into pass 1.
