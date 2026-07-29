# Photonz — UX patterns & interaction model (the app's spine)

**Status: v1.1. §1 and §3 now describe the LEAN, SCALABLE shell (PRODUCT-MODEL.md
§4b): canvas-first, a floating bottom tool bar, one right dock of collapsible /
resizable / scrollable panel groups, rails, overlays, and a real responsive
contract. D1/D2 are amended (Library is a right-dock group or an overlay, not a
left dock); D3–D6 stand as written. This is the source of truth for how the
product behaves, above and beyond how a single page looks.** `AGENTS.md` governs how one page is
*styled*; this doc governs how the whole app *works* so that every page feels like
the same product, not a different app by a different person.

The problem this fixes: pages were authored in parallel, each inventing its own
chrome, its own way to reach tools/panels/catalogs, its own selection behavior,
and its own icons. Result: walking the pages feels like visiting many different
apps. Every page MUST now sit inside one shell, use one navigation model, one
selection model, and one icon library. When a page shows a surface (a media pool,
a component catalog, a vector tool), it must be obvious *how you got there, where
it lives, and how you get back*.

---

## 0. How to use this doc

- Read this BEFORE authoring or auditing any page.
- Every claim here should become either a shared DS class/pattern or an audit
  rule. If a page needs something not covered, add the pattern here first, then
  use it, so the next page reuses it instead of reinventing it.
- Keep it concrete: name the surface, say where it docks, say how you open it,
  say how you get back.

---

## 1. One app shell: lean, canvas-first, and built to scale

There is ONE window shell hosting ONE document (see `PRODUCT-MODEL.md` §1 and
especially **§4b, the layout system**, which this section implements). The
shipping app is deliberately **lean and canvas-first**, and it must stay that way
as scope grows. The resolution is **one scalable dock system that grows by
collapsing, resizing, and scrolling, never by inventing new chrome per feature**.

**Image · UI · Video are not separate apps; they are workspaces (lenses) over the
same document and layer stack**, selected from the **workspace switcher**
(`.wsw`) in the title bar. Switching a workspace re-arranges the chrome, never the
engine: the **tool strip** swaps to that workspace's tool inventory (D4) and its
**foregrounded panel groups** change, while the canvas, layer model, Library, and
Inspector stay the same. The **timeline dock and transport bar appear only when
the document has time** (the Video workspace), "timeline when time". A layer type
therefore works in every workspace, so an adjustment/filter layer grades a UI
frame exactly as it grades a photo.

### The regions, always in the same place

1. **Title bar** (`.titlebar`) — traffic lights, document name + context
   ("settings-capture · 2560 x 1440"), the **workspace switcher**, and
   right-aligned document actions (Share, Export, Done).
2. **Command surface** — the **native macOS menu bar is the real command
   surface** in the shipping app (File, Edit, Select, Layer, Type, Effect, View,
   Window, Help), and it is the literal expression of "everything the UI does is
   one API call". The mock never draws a fake one (D3); it shows a compact
   command button (`.tool` + `ic-more`) plus the **Ask launcher** (`.askbtn`, D6
   revised) as the secondary path, along with the **History** entry.
3. **Canvas** (`.cnv` > `.canvas`) — the document, and the dominant region. It is
   the only region that grows when everything else collapses. Selection lives
   here. Everything that floats, floats over this: the tool bar, the canvas
   action cluster, and overlays.
4. **Floating bottom tool bar** (`.cnv > .tbar`) — a rounded glass capsule
   centered at the bottom of the canvas: the **tool strip**, a separator, the
   **foreground/background swatch pair with a swap affordance** (`.swpair`), a
   separator, and the **zoom slider + percent** (`.zoomctl`). Overflow tools
   (`.ovf`) collapse into a **more** affordance (`.tbar-more`) when the window is
   narrow. This is the canonical tool surface for canvas work; there is no
   permanent options-bar row.
5. **Canvas action cluster** (`.cnv-act`) — top-right of the canvas: the **panel
   toggle** (`ic-sidebar`, `[data-dock-toggle]`) that shows or hides the dock, and
   the **history** entry. Panel visibility is controlled where the canvas is, not
   in a distant toolbar.
6. **Right dock** (`.pdock`) — ONE dock holding **stacked panel groups**
   (`.dgrp`): Layers, Properties/Inspector, Effects, Library. Every group is
   independently **collapsible** and independently **scrollable** with its own
   bounded height. The dock **resizes** by dragging a `.splitter.v`, and
   **collapses entirely** to a `.drail`.
7. **Rail** (`.drail` > `.drailtab`) — what the dock collapses to: a slim labeled
   strip. Clicking a rail tab restores the dock and reveals that group. At tight
   widths the rail drops its labels and becomes icons only.
8. **Bottom dock, only when the document has time** — the **transport bar**
   (`.transport`: volume, skip back, play, skip forward, a scrubber with in/out
   marks and timecodes, then edit actions) and the **timeline** (`.timeline`).
   Hidden in every other workspace.
9. **Overlays** — the **slide-down history sheet** (`.sheet.down`, ⌘⇧H) and
   anything catalog-like that would crowd the canvas. Overlays slide over the
   canvas instead of permanently consuming width.

A page does not have to render every region, but whatever it renders must be in
the region above, at the same edge, with the same affordance. No page invents a
floating panel where a docked one belongs, and no page invents new chrome when a
panel group would do.

### Responsive behavior (non-negotiable, PRODUCT-MODEL §4b req. 1)

Put `.cq` on the `.win` and it becomes the container-query root, so the shell
adapts to the **window** width rather than the viewport. Two breakpoints, both in
`shared/photonz-ds.css`:

- **≤ 880px (narrow)** — the dock stops consuming width: it becomes a **rail**
  plus an on-demand **overlay** beside the rail. The vertical splitter goes away.
  The tool bar's `.ovf` tools fold into `.tbar-more`. Transport buttons drop their
  labels.
- **≤ 620px (tight)** — the rail drops its labels, the zoom slider drops out, the
  transport compacts further.

Every editor page must render sensibly at both. Test it by narrowing the window,
not by drawing a separate small mock.

---

## 2. Navigation: how you reach a surface (and get back)

Rule: **surfaces dock; they do not pop into unexplained new windows.** For each
surface the mock shows, it must make the entry+exit legible:

- **Media pool / Assets / Component catalog / Style library**: these are the SAME
  surface family — a **Library** panel group (`.dgrp`) in the **right dock**, or
  the same content as a slide-down overlay when it needs room to browse. Inside
  Library, a **scope switch** (segmented: Media · Components · Styles · Assets)
  picks which reusable content you are browsing (D1/D2, amended). You reveal it
  from the canvas **panel toggle**, its **rail tab**, `⌥⌘L`, or the command
  palette; you add to it via the group's own "+ Import" affordance, drag-drop onto
  the group/canvas, or right-click "Add to Library" on a selection (video also
  adds via Capture). It is NOT a separate window and NOT a bespoke per-page
  widget. Video's "media pool" is this same Library group with scope = Media.
  Getting back = it never left; it is a persistent group in the one dock.
- **Tools** (pen, brush, crop, measure, etc.): always in the **floating bottom
  tool bar**'s tool strip (§6). Selecting a tool changes the canvas cursor and the
  active tool's options. You "get to the vector tool" by picking the Pen in the
  tool strip, not by teleporting to a different screen. When the window is narrow
  the tool may be under the **more** affordance, never somewhere else.
- **Guided walkthroughs** are the exception: they are teaching flows, explicitly
  framed as steppers, and should say so. But the SURFACES they show inside each
  step must still be the docked, real ones (Library in the left dock, Inspector on
  the right), so the walkthrough teaches the real app, not a diorama.

Every editor page should be able to answer, on screen: *what document am I in
(title bar), what tool is active (the floating tool bar), what is selected (canvas
+ the Properties group), where is my content library (the Library group in the
right dock), where do my captures live (the ⌘⇧H history overlay), how do I run a
command (the native menu bar, plus the compact command surface and the Ask
chat at ⌘K)*.

---

## 3. Panels & surfaces taxonomy (the whole vocabulary)

This is the complete list. **A feature that needs chrome outside this list is a
signal to adjust the foundation, not to invent locally** (PRODUCT-MODEL §4b req.
6). Learn these seven and you can read every surface in the app.

- **Dock** (`.pdock`) — ONE persistent column on the right holding stacked panel
  groups. Resizable by a `.splitter.v`, collapsible to a `.drail`. There is no
  left dock: Layers, Properties, Effects, and **Library** are all groups in this
  one dock (see D1/D2, amended).
- **Panel group** (`.dgrp` > `.dgrp-h` + `.dgrp-b`) — the unit of panel scope.
  Header = chevron + title + optional count + optional buttons; clicking it
  collapses the group to its header (`.dgrp.collapsed`). The body has its **own
  bounded max-height (`--gh`) and its own scroller**, so a 60-layer stack scrolls
  inside Layers and never pushes Effects or Library off screen. Exactly one group
  per dock may be `.grow` and take the leftover space. **New capability is a new
  group.**
- **Splitter** (`.splitter.v` / `.splitter.h`) — the drag-to-resize handle.
  Vertical between canvas and dock, horizontal between stacked groups. Visible
  grip at rest, accent on hover and drag, keyboard-resizable, bounded by
  `data-min` / `data-max`. Sizes persist for the session.
- **Rail** (`.drail` > `.drailtab`) — the dock fully collapsed to a slim labeled
  strip so the canvas dominates. Clicking a tab restores the dock and reveals
  that group. Icons only at tight widths.
- **Floating tool bar** (`.cnv > .tbar`) — the canvas tool surface: tool strip,
  color swatch pair, zoom. Overflow tools collapse into `.tbar-more`.
- **Transport bar** (`.transport`) — the bottom bar for documents with time.
  Volume, transport buttons, scrubber with in/out marks and timecodes, edit
  actions.
- **Overlay** (`.sheet.down`) — a surface that slides over the canvas rather than
  consuming width forever. The **history overlay** (⌘⇧H) is the canonical one:
  segmented All / Screenshots / Videos, a `.filmstrip` of `.filmcard`s with
  relative timestamps, and a selected card revealing its action row. Reach for an
  overlay when the surface is browsed occasionally, and a panel group when it is
  referenced constantly.
- **Popover / menu** (`.popover.pop` + `.menu`/`.menuitem`) — transient, anchored
  to its trigger via `[data-menu="#id"]`. Color pickers, add-adjustment menus,
  panel menus, tool-bar overflow, context menus. Dismiss on outside-click or Esc.
- **Modal + toast** — rare document-scoped dialogs (export, new document), and
  transient confirmations ("Saved", "42 instances updated").

Audit failing examples: a component catalog rendered as a bespoke centered card
with no dock and no open/close affordance; a panel that grows the window instead
of scrolling inside its group; a page that only works wide. Correct: a `.dgrp` in
the dock, or a `.sheet.down` overlay.

---

## 4. Selection model: global vs contextual

- **Global, always present** regardless of selection: the tool strip, the menu
  bar, the Library dock, document actions, zoom.
- **Contextual to selection**: the **Inspector** (right dock). Nothing selected =
  document/artboard properties. One layer selected = that layer's properties. A
  component instance selected = instance props + overrides + variant. Multi-select
  = shared properties only. This is the pattern users learn: *look right to see
  what the current selection can do.*
- **Selection is shown in one consistent way**: `.sel-ring` + handles on canvas,
  the matching `.lrow.sel` in Layers, and a selection label. One object selected
  in three places reads as one selection.
- Tools are global; the *tool options* are contextual to the active tool (shown
  in the options bar or the top of the Inspector).

---

## 5. Layers representation: flat vs grouped (be consistent)

- Layers panel is a single tree. **Flat list** when the doc is flat; **groups**
  (`.lgroup`) when structure exists (a component is a group; a frame with children
  is a group). Do not show a flat list on one page and an arbitrarily grouped one
  on another for the same kind of content.
- A **component instance** always renders in Layers as a single collapsed group
  with the component glyph; expandable to show overrides, not its full internals.
- Visibility (eye), lock, and reorder affordances are identical on every row.

---

## 6. Tools: where they live, how they change context

- The **tool strip** is the left cluster of the **floating bottom tool bar**
  (`.cnv > .tbar > .tstrip`), followed by a separator, the foreground/background
  swatch pair, and zoom. Same order across workspaces where a tool exists
  (Select/Move first; then create tools; then measure/crop; view tools last).
  Tools marked `.ovf` fold into the `.tbar-more` menu when the window is narrow;
  they are never re-slotted or dropped.
- Selecting a tool: (a) highlights it (`.tool.on`), (b) changes the canvas cursor
  / interaction, (c) swaps the tool options in the options bar / inspector top.
- A page that shows "drawing vectors" must show the Pen selected in the strip and
  its options, so the user understands they entered a mode, not a new app.
- The **canonical per-app tool inventory** (ordered) is fixed in §10 decision D4.
  Shared tools (Select, Hand, Zoom, Text, Shape, Measure) keep the same glyph and
  slot in every app; app-specific tools slot between the create cluster and the
  view cluster. Never reorder or re-glyph a shared tool per page.

---

## 7. Menu / command system (the API made browsable)

- Every command maps to one API call (`run("tool.text")`, `panel.dock("right")`,
  `layer.group()`). There are FOUR ways to reach the same call, all equal: the
  toolbar/tool strip, a right-click context menu, the **command surface** (D3),
  and the **agent chat** (D6 revised) — reached by the Ask button or ⌘K, where a
  `/` command and a plain-language request issue the same call. An agent drives
  the identical calls.
- In the mock shell we express the menu as a **compact command surface** in the
  toolbar (a menu/command button) plus the **Ask launcher** (`.askbtn`), NOT a
  faked full macOS menu bar (see D3). The shipping app additionally has the native
  menu bar; the mock does not render it. Keep the command surface + Ask present on
  every editor page so the "UI == API == agent" story is always visible.

---

## 8. Iconography: ONE library, one style (no exceptions)

The single biggest consistency smell was mixed icon styles and ascii/emoji
glyphs. Rules:

- One monochrome line-icon library on one grid: 24x24 viewBox, 20x20 live area,
  square keyline 18x18, circle keyline d17.2, 1.75 stroke, round caps/joins,
  `currentColor`, no fills except where the glyph is intrinsically solid.
  Authored in `shared/icons.mjs`, generated into `photonz-ds.css` as `.ic-*` by
  `node shared/build-icons.mjs`, and documented on `pages/iconography.html`
  (searchable, click to copy).
- Use `<i class="ic ic-NAME"></i>` everywhere. NEVER ascii/unicode symbols
  (◄ ▭ ✎ ◈ ⌗ ▾ ◉ ◆ ✦ → ← etc.) as icons, NEVER emoji, NEVER a second icon style.
- One concept = one icon, app-wide (e.g. component is always `ic-component`; add
  is always `ic-plus`). Maintain the concept->icon mapping in AGENTS.md.
- If a glyph is missing, ADD it to `shared/icons.mjs` and regenerate, rather
  than substituting a near-miss or an ascii symbol. Keep the new glyph in the
  same grammar and drawn to a keyline. Never hand-edit the generated CSS block.
- Sizes come from `.ic.xs` 12 / `.ic.sm` 14 / `.ic` 16 / `.ic.lg` 20 /
  `.ic.xl` 24, never ad-hoc px.

Done: the set was redrawn to one grid and one weight (199 glyphs in 12 groups,
plus aliases for the older names). Remaining action item: keep auditing pages
for conformance (see the audit agent). The icon set must look drawn by one hand.

---

## 9. Per-page consistency checklist (audit gates)

Every editor/scenario page must satisfy:

- [ ] Sits in the one shell: title bar, canvas-dominant `.edit.lean` row, the
      floating tool bar, the right dock of panel groups.
- [ ] Answers "how did I get here": the active tool/mode is visible; the surface
      shown (Library/media pool/tool) is a panel group or an overlay, reachable
      via a visible affordance, not teleported in.
- [ ] Library/assets/catalog is the Library group in the right dock (or the same
      content as an overlay), with an add/import affordance.
- [ ] Selection drives the Properties group; selection shown consistently on
      canvas + in Layers.
- [ ] **Responsive**: the `.win` carries `.cq`, and the page renders sensibly
      narrowed (dock rails or overlays, tool bar overflows).
- [ ] **Bounded panels**: every long list is inside a `.dgrp-b` with its own
      max-height and scroller; no list stretches the window.
- [ ] Layers use flat-vs-group consistently; rows have identical affordances.
- [ ] Every glyph is an `.ic-*` from the one library; zero ascii/emoji/mixed
      styles.
- [ ] Controls are canonical `.btn`/`.seg`/etc. with real states.
- [ ] **Transport bar holds time controls only** (D8): nothing but volume,
      skip, play/pause, loop, the two timecodes and the scrubber shares that row.
- [ ] Copy: plain, no em dashes, "agent" not "Claude".

---

## 10. Resolved decisions (baked in — build to these)

These were the review open questions. They are now DECIDED. Every page, the app
shell, and the audit agent conform to these. If a decision must change, change it
here first, then propagate.

### D1 — Media pool is the Library panel group, scope = Media

> **Amended (PRODUCT-MODEL §4b).** The Library no longer lives in a **left** dock.
> There is exactly ONE dock, on the right, and Library is a **panel group**
> (`.dgrp`) inside it, alongside Layers, Properties, and Effects. The scope switch
> and every rule below are unchanged; only its home moved. When Library needs room
> to browse, show the same content as a `.sheet.down` overlay rather than widening
> the dock.

The "media pool" is not its own surface. It is the **Library** group in the right
dock with its scope switch set to **Media**. Locked rules for every video/media
page:

- **Open path:** the canvas **panel toggle**, the **Library rail tab**, `⌥⌘L`,
  `Window > Library` in the menu model, or Ask (⌘K) `→ "/library"`. It is a persistent
  group in the dock, so the normal state is "already there".
- **Add media (three ways, always all present):** the panel's **+ Import** button
  (file picker), **drag-drop** a file onto the panel or the canvas, and **Capture**
  (screenshot/recording from the menu-bar agent) which lands new media here.
- **Contents:** clips, images, audio, each a thumbnail tile with duration/size
  meta; drag a tile to the timeline or canvas to use it. Selecting a tile shows
  its properties in the **Properties group**, same selection model as §4.
- No video page renders a bespoke "media bin" widget outside this group.

### D2 — One Library surface with an internal scope switch (not N panels)

> **Amended (PRODUCT-MODEL §4b).** Read "the left dock has two top-level tabs" as
> "the right dock has stacked panel groups". Layers and Library are two of those
> groups, not two tabs. Everything else stands.

Component catalog, style library, media pool, and assets are the SAME surface.
Inside the Library group, a **segmented scope switch** picks the content family:
**Media · Components · Styles · Assets**. Rationale: they are all "reusable content
you browse and drag onto the canvas"; one location + one scope switch beats four
competing panels and keeps the mental model flat. Each scope has the same shape
(search, grid of tiles, + affordance, right-click "Add to Library"). Selecting any
tile drives the Properties group. Do NOT promote a scope to its own dock or
window.

### D3 — No fake menu bar. Compact command surface + Ask (still holds)

> **Enforced (2026-07-26).** The title bar, the Ask launcher and the `…` command
> surface button are now BUILT by the shell component in `photonz-ds.js` from
> `data-shell` / `data-ws` / `data-status` on the `.win`. Pages had each retyped
> that chrome and drifted: Share/Export/Done in the header, a `.toolbar` command
> strip `app-shell.html` had already deleted, 56 copies of the `.cmdk` well. The
> component deletes any `.titlebar`/`.toolbar` found inside `[data-shell]`, so it
> cannot drift again. A page authors its own `.cmdpop` menu ITEMS (content); the
> button that opens them is chrome. See AGENTS.md, "The shell is a COMPONENT".

The **shipping app's real command surface is the native macOS menu bar** (File,
Edit, Select, Layer, Type, Effect, View, Window, Help), and that is the primary
story. But the mock `.win` frames live inside an iframe shell, so drawing a full
menu bar would read as fake chrome. Decision, unchanged in substance: the mock
expresses the command system as a **compact command surface** (a `.tool`
`ic-more` button that opens a grouped `.popover.menu`) plus the **Ask launcher**
(`.askbtn`, D6 revised), and it says in copy that the native menu bar is the real
one. Ask is the **secondary** path, not the headline. No page draws a full
horizontal menu bar, and no page adds a permanent options-bar row of tools: tools
live in the floating bottom tool bar.

### D4 — Canonical tool-strip inventory per app

Ordered left→right in the tool strip. **Shared tools keep the same glyph and the
same relative slot in every app.** Structure is always: `Select → [create/edit
cluster] → [measure/crop] → Hand → Zoom`.

- **Shared (identical glyph + slot wherever present):** Select (`ic-cursor`),
  Hand (`ic-hand`), Zoom (`ic-zoom`), Text (`ic-text`), Shape (`ic-square` /
  `ic-circle`), Measure (`ic-ruler`).
- **UI design:** Select · Frame (`ic-frame`) · Component-insert (`ic-component`) ·
  Shape · Pen (`ic-pen`) · Text · Measure · Hand · Zoom.
- **Image:** Select (marquee/lasso/wand `ic-lasso`/`ic-wand` as a select subgroup)
  · Crop (`ic-crop`) · Brush (`ic-brush`) · Eraser (`ic-eraser`) · Heal
  (`ic-heal`) · Clone (`ic-clone`) · Pen · Text · Shape · Measure · Hand · Zoom.
- **Video:** Select · Blade/split (`ic-blade`) · Title/Text · Shape · Measure ·
  Hand · Zoom. (The timeline has its own Select/Blade in its local toolbar; they
  mirror the same tools.)
- **Draw:** Select · Pen · Brush · Eraser · Shape · Text · Measure · Hand · Zoom.

App-specific tools slot between the create cluster and the view cluster (Hand/
Zoom). If an app lacks a shared tool (e.g. no Measure), omit it — never re-slot
the ones it has.

### D5 — Walkthroughs embed the REAL shell (may be reduced, never relocated)

Guided-walkthrough steppers teach the real app. The `.win` illustration in each
step must show the **canonical docked surfaces** relevant to that step: tool strip
in the toolbar, Library in the left dock, Inspector in the right dock, timeline at
the bottom for video. A step MAY hide docks irrelevant to what it teaches
(reduced), but MUST NOT relocate a surface, invent a floating panel where a docked
one belongs, or use non-canonical chrome. The stepper frame (`.wsteps`/`.wbar`) is
the only walkthrough-specific UI; everything inside a step is the real shell.

### D6 (revised) — The agent chat IS the command palette. One entry point, not two

> **Revised.** D6 used to adopt a separate ⌘K command palette, shown in the title
> bar as a `.cmdk` search well. That is superseded: the title bar's right slot now
> holds **one launcher** and it opens the **agent chat**.

There is a global fourth entry point alongside the tool strip, context menus, and
the command surface (D3), and it is the **agent chat**. It is reached exactly two
ways, both landing on the same surface:

- **`.askbtn`** — the Ask button in the title bar's right slot. A raised `.btn`
  variant (sparkle glyph + "Ask" + a `⌘K` hint), because it opens a surface. The
  old `.cmdk` was an inset well because you typed into it in place; nothing in the
  title bar is a well any more.
- **`⌘K`** — opens the same overlay and focuses its composer.

What opens is **`.askpal`**: a centred overlay at elevation 2 (glass + blur +
shadow + scrim, per the ladder on `pages/lang-elevation.html`), living inside
`.edit.lean` so it dims the canvas and the dock but leaves the title bar lit. It
does not restate the conversation UI, it **hosts the shared `.chat` component**, so
the overlay and the Agent panel group in the dock are the same conversation in two
places.

**One field, two modes.** The composer takes plain language ("make the headline
bigger") or, when it starts with `/`, becomes the command palette: a filtered
`.cplist` of `.cpx` rows appears inline above the composer, each showing its real
API name (`image.removeBackground`, `panel.dock`). Same field, same Enter key. A
sentence you ask and a command you run issue the identical call, which is the most
direct on-screen proof of "UI == API == agent" — stronger than the old palette,
because the proof and the agent are now literally the same box.

Pages that demonstrate command-running route it through this surface rather than
inventing a one-off runner. Do NOT add a `.cmdk` to any page; it is deprecated and
survives only until the sweep finishes.

### D7 — One color picker, one trigger, every color slot

Color is picked exactly one way. The **trigger is always a swatch** showing the
current color (`.cpick-btn` in a row, the `.swpair` in the tool bar, a `.gstop` on
a gradient ramp), and what opens is always the **one shared picker**
(`.cpick`, styled in `photonz-ds.css`, driven by `initColorPickers()` in
`photonz-ds.js`). No page authors a second color UI, no slot falls through to the
system color panel, and no slot uses a labelled "Choose..." button instead of a
swatch. The picker is a `.popover` but it is **sticky**: clicks inside it do not
dismiss it, because you operate it rather than pick one item from it.

Its regions, in this order, always: before/after preview + slot name + eyedropper
· **four paint-type thumbnails** · (gradients only) the **aim pad + ramp + selected
stop** · saturation/value field · a centered **HSL / RGB / HEX** switch · **one
slider per channel** · **one swatch row with a scope switch** (shades of this
color / related hues / in this document) · contrast readout and "Save style".

Two rules inside it matter more than the layout:

1. **One control per channel.** The format switch picks which channels you are
   sliding; it is not a second way to see the same ones. So there is no hue
   slider sitting next to an H field. HEX has no channels to slide, so that mode
   keeps the hue and alpha tracks and adds a text field, which is also the paste
   target (it takes hex, `rgb()` or `hsl()`).
2. **Every value is typable where it lives.** Each slider carries its number as
   an editable field on the right, and right-clicking a track focuses it. There
   is no separate numeric-entry row to reach for.

The shades row is the point of the whole control: the most common color edit is
"the same color, a bit darker", and it must cost one click and no numbers.

**A color slot holds a PAINT, not a color.** That is how you get a gradient onto a
fill, a stroke or a text layer, and it is the first control in the popover:
**Solid / Linear / Radial / Angular**, drawn as four thumbnails that each render
the CURRENT stops at the CURRENT angle. You choose between four outcomes, not four
words. Pick a gradient and the aim pad, ramp and selected-stop row appear in
place, seeded from the color you already had; the picker below then edits whichever
stop is selected. A stop is a color slot like any other, so selecting one costs
nothing new to learn: drag a key to move it, click the bare strip to add one.

**Direction is aimed, never typed.** The aim pad is a small square showing the
paint with handles you drag; the angle readout follows the handles rather than
leading them. "135°" is a value a person has to decode, so it is a readout, not
the control.

The pad carries **two handles of one family**: a small dot for the paint's
**origin** and a larger one for its **direction**, with a line between them so
they read as one object. Both are live on every gradient type, including linear -
a CSS linear gradient has no origin of its own, so moving it slides every stop
along the axis, and a sideways move correctly does nothing. A radial has no
direction, so it shows the origin alone.

Three rules came out of getting this wrong:

- **Never draw a handle on something the pointer cannot pick up.** A dead dot
  that looks grabbable is worse than no dot.
- **Grab, do not teleport.** Pressing near a handle keeps the offset so it does
  not jump out from under the pointer. The cursor is `grab`/`grabbing`, never
  `crosshair` (which promises "click to place"), and the handles react to hover
  even though the SVG they live in cannot take pointer events.
- **A hover-revealed overlay needs hover intent.** The stop callout floats clear
  of the ramp, so travelling between them crosses a few pixels of nothing.
  Hiding on that gap makes the card vanish exactly when you reach for it, so
  leaving only schedules the hide and arriving anywhere in the pair cancels it.

**The selected stop names itself, where it is.** Its color, its number and a
labelled Position field ride in a small beaked card over the stop on the ramp,
not in a row underneath. A row parks the label away from its subject and competes
for width the row does not have; the card is an overlay, so it costs no layout
height. It is up while you are working the ramp AND while anything in the ramp
block holds focus, because a focused thing must not lose its label just because
the pointer wandered off.

That card is also the DS's only **elev 3** surface, and it is the reason the level
exists: a card sitting ON an elev-2 popover cannot reuse the popover's own tokens,
or it reads as a hole punched in it rather than a plate above it. In dark it lifts
by growing **lighter**, in light by casting **further**, never both, and it is
opaque because glass over glass doubles the blur. Use `.elev-3`; see
`pages/lang-elevation.html`.

**Two rules that keep it usable:**

3. **Show the outcome, do not name it.** A word or a number is the fallback for
   when a control cannot show you the answer. Here it can.
4. **The popover has a height budget.** It must fit a laptop window with room to
   spare, which means nothing stacks a second copy of anything: no preview beside
   a type list, no aim pad beside an angle row, and the shades / related /
   in-document families share one row behind a scope switch rather than stacking
   three labelled grids.

**The switch appears only where a paint applies.** A drop shadow takes a flat
color, so the Shadow row opens straight into the picker with no type switch, the
same rule as opacity: a control that cannot apply is not shown doing nothing. The
non-color paint types (image, noise) are the same switch with their own body; see
`pages/paint.html`.

**Spacing inside it:** 12 between blocks, 8 inside a block, 4 between swatches in
a grid. Nothing else. (`.popover.pop.on{display:block}` out-specifies a bare
`.cpick{display:flex}`, so the layout declaration is written as
`.cpick, .popover.pop.on.cpick` - get that wrong and every gap silently dies.)

Authoring: `data-cp-color` seeds it, `data-cp-fill` / `data-cp-text` bind live
outputs, a `cp:change` event carries `{hex, rgba, r,g,b,a, h,s,l}`, and a
`cp:set` event re-points the same popover at another slot. Canonical page:
`pages/color.html`.

---

### D8 — The transport bar holds time controls only

The scrubber is the one control in the app whose usefulness is measured in
pixels. At a 15-second document a 323px track gives you 21px per second, so
"put the playhead on 6.40s" is a two-pixel gesture and you cannot land it.
Anything parked on that row is taken directly out of that budget.

So the transport row is **volume · skip · play/pause · loop · timecode ·
scrubber · timecode**, and nothing else. The scrubber is the only flexible
child; every sibling is `flex:none`. It carries an invisible 24px pointer band
(`.scrub::before`), because 6px is what a track should be *drawn* at and has
never been what it should be *grabbed* at.

Fourteen pages had violated this identically, because they were copied from
each other: `video.html` carried Cut · Add key · Delete key · Export, a 353px
block that was **wider than the 323px scrubber it was starving**. Every one of
those buttons already existed somewhere better, which is the tell — a control
lands on the transport when nobody decided where it belonged.

Where an evicted action goes, in order of preference:

| The action is… | It belongs… | Example |
| --- | --- | --- |
| about the whole document | the title bar (`.tbtns`) or the command menu | Export — already the primary button up there on all 14 pages |
| a mode you enter | the tool strip (D4) | Cut → the Blade tool, already in the canvas strip *and* the timeline's |
| about the current selection | next to that selection | Key it → the button already in Properties; Apply / Hard cut → the timeline bar that names the cut |
| about one property at one time | on that property's own row | Add key / Delete key → one diamond per lane in the keyframe editor |
| scoped to the timeline dock | the dock's local bar (`.tlbar`) | Duck, Clear, Reset |

The last row of that table is the one worth internalising. **A keyframe is
never document-level** — it is one value, on one property, at one time — so
"Add key" phrased as a global command had to guess all three. As a diamond on
the property's lane it guesses nothing: the lane says which property, the
playhead says when, and the diamond's own fill says whether a key is already
there (hollow = click to set, filled = click to clear). That is the After
Effects / Final Cut idiom, and it replaces two labelled buttons with one
control that also reads as state. Canonical page: `pages/video.html`.
