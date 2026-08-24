# Photonz mock — page author contract

You are building ONE standalone page for the Photonz "Creation Vision" clickable
prototype. Many agents work in parallel, each owning a single file under
`pages/`. **Only edit your own page file.** Do not touch `shared/`, `index.html`,
or any other page — that's how we stay collision-free and consistent.

The prototype is a set of independent pages composed by an iframe shell
(`index.html`). Every page imports the same design system, so the whole thing
reads as one product even though we build it in pieces.

## The look: it must feel like an unreleased native macOS pro app

Liquid-glass surfaces, precise spacing, SF Pro (system font), dark+light aware,
zero visual noise. Restrained and confident, not flashy. Real designed content on
canvases (gradients, glow, type) — never lorem, never empty gray boxes.

## Page template (copy exactly)

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Photonz · <your-page-id></title>
<link rel="stylesheet" href="/shared/photonz-ds.css">
</head>
<body class="page">
<main class="stage">
  <section class="screen on" id="<your-page-id>">
    <div class="scen-head"><span class="pip" style="background:<accent>"></span><h2><Title></h2><span class="k">· <subtitle></span></div>
    <!-- your window(s) + captions here -->
  </section>
</main>
<!-- Only if you need steppers/subtabs/cross-links. Safe to always include: -->
<script src="/shared/photonz-ds.js"></script>
</body>
</html>
```

Page-specific CSS/JS: add a `<style>`/`<script>` in the page **only for things the
shared system doesn't cover.** Prefer composing existing classes. If you invent a
new component, base its spacing/radii/colors on the tokens below so it matches.

### PREFIX every page-local class (this bug has bitten ten times)

`shared/photonz-ds.css` opens with a **RESERVED CLASS NAMES** list. A page that
reuses one of those bare names for its own purpose silently inherits the DS rule,
and it presents as a mystery layout bug, not as a collision. Real cases: `.bar`
and `.btn` swallowed a selection ring; `.ghost` turned a control into a 300px
absolutely-positioned dashed box; `.shot` blew up a toast; `.meta` overrode an
effect row; `.sheet`, `.rail`, `.timeline`, `.panel`, `.ramp`, `.val`, `.body`
and `.dsub` each broke a different page.

- **Prefix every local class with a page tag** — `#video-motion .mg-tag`,
  `#export-share .ex-body`, `#lang-frame .lf-spec`.
- Scoped **refinement** of a DS class is fine and encouraged
  (`#dsys .win.shell{height:740px}`). **Shadowing** one with a different meaning
  is the bug.
- **Before you hand-roll a rule, check whether the DS already owns it.** VR6
  promoted seven that 4–37 pages had each written out by hand, byte-identical:
  `.pglead` (the sentence under the page title) · `.mlabel` (9px uppercase
  caption over a run of rows) · `.rl` (an inspector row's label, in ANY row
  container) · `.setrow` (label left, control right) · `.actstack` (stacked
  full-width actions) · `.seg.stack` (a segmented control allowed to wrap) ·
  `.win.shell .canvas{min-height:0}` (the canvas has no height floor inside a
  shell). All seven are now reserved bare names. `vr6-strip.py` re-runs as a
  guard: it should always report 0 rules to remove. Two more have joined them
  since: `.actrow` (`.actstack`'s sibling — two or three SHORT buttons on one
  line, wrapping only when the dock is narrow) and `.cnv-hint`, the dark glass
  pill on the artboard that names the gesture ("Drag an anchor and the stroke
  re-renders"). `.cnv-hint` is NOT a tooltip: it is on screen from the start,
  it is never hovered, and it goes away once you have done the thing. The page
  sets only its `top`/`bottom`.
- Same rule for `data-*`: `data-target` is a reserved global cross-page nav hook
  that `preventDefault`s and `stopPropagation`s. Using it as page data means your
  control silently never fires. Pick your own `data-` name.
- **Inside a `.wt` walkthrough this is sharper.** If a page-local attribute
  appears on BOTH a control and a `.wt-step`, your own render loop will toggle
  `.on` across the step elements and `ds.js`'s step state breaks in a way that
  looks like the walkthrough is skipping steps. Give the step attribute and the
  control attribute different names, and scope control queries to the dock or the
  canvas (`#my-page .pdock [data-mything]`) rather than querying document-wide.

## THE SPACING STANDARD — non-negotiable

Use ONLY the 4pt scale. No 7/9/11/13/15/18/22px one-offs. Tokens exist for all of
it (see top of `shared/photonz-ds.css`):

- `--s1:4 --s2:8 --s3:12 --s4:16 --s5:24 --s6:32 --s7:40`
- Semantic: `--pad:16` (card/pane padding) · `--pad-sm:12` (compact rows) ·
  `--gap:16` (sibling gap) · `--gap-sm:8` · `--gap-lg:24` · `--inset:24` (window
  content padding).
- Radii: `--r2:8 --r3:10 --r4:12 (cards) --r5:14`.
- Top-level blocks are **full-bleed** (no side margins) so all edges line up.
  Caption columns use `.caption .c { flex:1 }` so they align to the grid above.

## CONTROL METRICS — heights, gaps, and the light source (non-negotiable)

Controls that sit in one row must read as one family. Three rules:

1. **One height scale.** Every interactive control comes in exactly three
   heights: `--ctl-h-sm:24` · `--ctl-h:32` (default) · `--ctl-h-lg:40`
   (defined in button.css). `.btn`, `.input`, `.stepper`, `.select`, and `.seg`
   all sit on it. NEVER a control at its browser-default height: a bare
   `<select>` or `<input>` without its DS class is a bug, and the "tiny
   dropdown next to a full-size field" it produces is the exact smell this rule
   exists to kill. Controls sharing a row share the same height step.
2. **One gap scale between controls.** Controls in a row: `--gap-sm:8`.
   Stacked form rows: `--s3:12`. A form block against its neighbors: `--gap:16`.
   Nothing else.
3. **One light source, from above.** RAISED things you press (buttons, `.select`
   triggers, segmented controls, toolbar tools) catch light on their TOP edge:
   `--ctl-gloss` (inset 0 1px 0 highlight). RECESSED things you type into
   (`.input`, `.stepper`, any well) shade at the top lip and catch light at the
   bottom lip: `background:var(--well); box-shadow:var(--well-sh)`. Never put
   the raised gloss on a field, and never fake an inset with a plain border.
   The question to ask of any control: do I press it (raised) or fill it
   (recessed)? `.select` is pressed, so it is raised even though it sits next
   to fields.

## Links (one primitive, never browser-default)

Bare `a` is styled by the DS (`links.css`): accent ink, quiet always-on
underline that firms on hover, no visited-purple, standard focus ring. Use
`.link` to give a button the same look, `.link.quiet` for dense runs of
repeated links, and `<i class="ic ic-external linkext"></i>` inside a link that
leaves the surface. Never restyle links per page and never let default blue
or visited purple appear.

## Overlays and list motion (never hand-choreographed)

Two shared components implement UX-PATTERNS **D11**; a page writes markup and
calls them, never its own timings.

- **Dialogs and overlays** (`dialog.css` + `dialog.js`). Author a
  `.dlg-scrim` wrapping a `.dlg`, then open it with `data-dialog-open="#id"` or
  `PZ.dialog.open(el)`. You get the standard entrance (scrim fades dur-2 while
  the surface rises and scales dur-3/decelerate), the quicker plainer exit, and
  **soft dismiss on all three gestures**: Escape (topmost only), a click on the
  scrim itself, and any `[data-dialog-close]` control. Focus moves in on open
  and returns to the opener on close. A closing dialog is still in the DOM, so
  code that re-renders its container must wait for the `close(el, done)`
  callback. Never write your own overlay open/close.
- **Lists that change** (`listfx.js`). Wrap the mutation:
  `PZ.listfx(container, function () { container.innerHTML = rows(); })`, give
  each row a stable `data-key`, and put `data-lfx` on the container. You get the
  three-phase sequence (exits fade in place, then survivors travel, then
  arrivals rise, staggered), interruption that retargets from live geometry
  instead of jumping, and suspension while a row is focused or held. Never
  animate list rows per page.

- **Whole views** (`view.css` + `view.js`). Every page gets the standard
  entrance automatically on load. When a page swaps a region wholesale, call
  `PZ.view.enter(el)` on it, and only when the view actually changed. Never
  write a page-local page transition.

All three collapse to instant under `prefers-reduced-motion`, with an identical
end state.

## Color / type tokens (never hardcode raw hex for chrome)

`--ink --dim --faint` (text) · `--panel --panel-2 --chrome` (surfaces) ·
`--line --line-soft --line-strong` (borders) · `--accent`/`--accent-soft`/`--accent-line`
(primary) · `--comp`/`--comp-soft`/`--comp-line` (components, purple) ·
`--good --warn --crit` (semantic) · `--artboard` (canvas). Fonts: `--sans` (SF),
`--serif` ("New York", real on macOS — use for display headlines), `--mono`.
Everything must work in BOTH light and dark (tokens handle it; just use them).

## Reusable classes (read `shared/photonz-ds.css` for the full set)

- **Window:** `.win`/`.win.tall` › `.titlebar` (`.lights`>i.r/.y/.g, `.wtitle`>b,
  `.tbtns`) › `.toolbar` (`.tool`/`.tool.on`, `.tsep`, `.pill`/`.pill.ai`/`.pill.solid`).
- **Editor 3-pane:** `.edit` › `.pane.layers` / `.canvas` / `.pane.insp`;
  `.pane-h`, `.lrow`/`.lrow.sel`/`.lrow.selc`, `.lgroup`.
- **Inspector:** `.section`>`.sec-h`, `.row`>`.rl`, `.field`, `.grid2`, `.chip`
  (`.chip.style`, `.chip.comp`), `.swatch`, `.bar`>i, `.seg` segmented control,
  `.efx` effect rows, `.gramp`/`.gstop` gradient, `.dial`.
- **Canvas content:** `.hero-card` (designed sample), `.uibtn`/`.uibtn.grad`,
  selection: `.sel-ring`+`.handle`, `.mtag`; component: `.cinst`/`.cring`+`.cbadge`.
- **Specimen card:** `.spec` › `.spec-h` (uppercase SPECIMEN label, optional
  `.sub` subtitle and trailing `.tag`/`.tag.acc`) + `.spec-b`, laid out in a
  `.specs` grid (`.spec.wide` spans it). This is how §4c Kind-2 is enforced BY
  CLASS: anything in a `.spec` wears no window chrome. `.spec.tile` is the
  padded flex tile variant for runs of small demos (not `.spec.stage`:
  `.stage` is the page-level walkthrough stage). Never hand-roll either.
- **Preset picker:** `.bpick` (radiogroup grid) › `.bchip` (thumbnail chip with
  a live `<canvas>` preview inside, `.on` marks the active one). For brushes,
  paints, styles, transitions — any choice that IS a picture.
- **Artstack:** `.artstack` stacks `<canvas>` + `<svg>` at `inset:0` inside one
  positioned box so vector geometry and raster pixels land on the SAME pixels.
  Give it a height or set `--ar` (aspect-ratio). Optional `.plabel` corner tag.
  The background is artwork and stays page-authored.
- **Effect row readout:** the mono value at the right of an `.efx` row is
  `.emeta` (renamed from `.meta`, which page-local rules kept colliding with).
- **Effect row enable:** `.efx .en` is a **`<button>`**, never a span — a span
  cannot be pressed, focused or announced. Author it with `aria-pressed` and a
  `title`; the press itself (flip `.off`, sync `aria-pressed`, and keep the
  click off the row's own `data-target`) is shared in `core.js`, so a page adds
  a listener only when it also paints the result.
- **Bounds rings are one family, all in `selection.css`:** `.sel-ring` (selected),
  `.cinst`/`.cring` (component instance), `.marq` (marquee), `.hover-ring`,
  `.lock-ring`. Every one of them hugs the bounds with a **2px** radius and never
  traces the object's shape — only the STROKE changes, because only the meaning
  changes. Never re-round one on a page: a card-sized radius makes the ring read
  as an object of its own, so you cannot tell it from the thing it is ringing.
- **Color:** `.cpick` (the ONE paint popover: a Solid/Linear/Radial/Angular type
  switch, the gradient ramp + stop rows when a gradient is chosen, an SV field, a
  centered HSL/RGB/HEX switch, one slider per channel with an editable value,
  derived shades and related-hue rows, recents, contrast readout) opened by a
  `.cpick-btn` swatch trigger. Never author a second color UI, and never a
  separate gradient editor; see UX-PATTERNS.md D7 and `pages/color.html`.
  **Adopting it is two lines.** The popover's body is built by the component, so
  a page writes only the empty shell and one swatch per slot:

  ```html
  <button class="cpick-btn wide" data-menu="#bgPick" data-cp-slot="Backdrop"
          data-cp-color="#3A4150"><span class="sw"></span><span class="cph"></span></button>
  …
  <div class="popover cpick pop" id="bgPick" data-cp-color="#3A4150" aria-label="Backdrop"></div>
  ```

  `.sw` shows the paint and `.cph` its hex; both follow the picker live and are
  seeded from `data-cp-color`. Add `data-cp-paint='{"type":"linear",…}'` when the
  slot opens on a gradient, `data-cp-flat` for a slot that takes a flat color
  (a drop shadow) so the paint-type row is hidden rather than shown doing
  nothing, and `data-cp-open` on the slot the picker should start pointed at, so
  the page gets one `cp:change` and paints its canvas without a second copy of
  the value. Many slots, one popover: clicking a different swatch moves it.
  Only annotate the regions by hand when the page IS the spec (`comp-color`).
- **Row tag:** `.rtag` — the state word at the end of a `.lrow` or a `.masklist`
  ("live", "ready", "editing"); `.rtag.accent` for the one you are working on.
  Three pages had each declared this under `.lrow` only and then used it in a
  `.masklist`, where it rendered as bare text.
- **Captions:** `.caption`>`.c`>`.lab`(/`.lab.g2`)+`p`. Use these to explain
  "the idea / direction / open question" under each window.
- **Code snippets:** `.codeblk` (with `.k`/`.s`/`.c`/`.p` spans for syntax).
  Author it on a **`<div>` or `<pre>`, never a `<span>`** — it is a block, and an
  inline element would fragment a multi-line snippet across line boxes.
- **Walkthrough:** `.wt` (see "Usage walkthroughs" below). The old
  `.wsteps`>`.wstep` slideshow is **legacy**; do not author new pages with it.
- **Selection: DECLARE it, do not draw it.** `data-sel-frame` on the object's own
  box and `selection.js` builds the whole frame — ring, four corner grabs, size
  tag — in the canonical order:

  ```html
  <div class="selwrap" data-sel-frame="Frame · 268 × 95"></div>
  ```

  The value is the `.mtag` text; leave it empty for a frame with no tag. If the
  tag carries page state (a walkthrough retags it by id), author the `.mtag`
  yourself inside the host and this leaves its text alone. `data-sel-parts`
  takes `edges` (the four midpoints), `rotate` (the knob), `none` (ring only).
  The parts are absolutely positioned, so the host must be the POSITIONED box
  the frame should hug — `.selwrap` is that and nothing more
  (`position:relative`). Retyping the four lines by hand is how five separate
  pages ended up promising a selection in their copy and drawing nothing;
  `node shared/check-selection.mjs` now fails a page that does, and ratchets the
  count of hand-written frames downward. The anatomy it builds, for reading the
  CSS: `.selwrap` › `.sel-ring` + `.handle` + `.mtag`. **The frame shows
  BOUNDS, never the object's shape** — a rectangle with a constant 2px radius,
  hugging the bounds, on a circle exactly as on a card. Never set `border-radius`
  or `inset` on a `.sel-ring`: a shape-tracing frame needs a big radius for
  cards, and below ~52px that radius exceeds half the box so the browser clamps
  it into a circle. Ten pages had each patched that locally with seven radii and
  five insets. The frame is constant; the HANDLES adapt, stamped by
  `selection.js` from the measured box (`md` ≥44px · `sm` shrinks and steps
  outside · `xs` <16px drops them, since a 7px handle on a 6px object is not
  grabbable). A full transform frame is EIGHT points: add `.handle.tc/.bc/.ml/.mr`
  edge handles where a single-axis resize is meaningful (they drop at `sm`), and
  `.rotstem`+`.rot` for the rotate knob above the frame (drops at `xs`).
  Lives in `shared/components/selection.{css,js}`.
- **Both docks collapse, and `dock.js` injects the controls** — you do not author
  them. Any `.timeline` with a `.tlbar` gets a `.tl-close` (×) at the end of the
  bar and a one-row `.tlrail` to bring it back, mirroring the panel dock's
  `.dock-close` / `.drail`. Write `data-tl-summary` on the `.timeline` to say what
  the collapsed row reports (the SELECTION, not the panel's name) — an observer
  picks it up. Collapsed must release `.timeline`'s `min-height:172px`. See
  UX-PATTERNS D9.
- **No Layers group in a workspace that has a timeline.** The timeline is the
  layer list: same objects, same groups, same order, plus when each starts and
  stops. Layers stays in the image and UI lenses, where it is the only inventory.
- **Property lists render the CATALOGUE, not the keyed set** (D10). Every
  animatable property gets a row and a key diamond, including dormant ones, so
  the way to animate something is visible on a clip nobody has touched. Three
  diamond states: dim outline (dormant) / coloured outline (animated, no key
  here) / filled (key here).
- **Video/timeline primitives are components** — never re-author them per page.
  `.clip` (with `.lbl`, `.edge.l/.r` trim handles, `.speed` badge, `.kfm` key
  marks) · `.editpt` the cut · the overlap family `.xband` (`.sel`, `.blk`
  for a dip, `.gr.l/.r` grips), `.xspare.a/.b`, `.xfade.in/.out`, and the
  expanded-cut set `.track.xrow` + `.xused` + `.xboth` · transition tiles
  `.libtile.tt` with `.th-*` thumbnails. All in
  `shared/components/video.css`; canonical page `pages/comp-video.html`.
  **The rule they encode: a transition is not a clip.** It overlaps two clips,
  occupies no slot, moves nothing, and is paid for in spare media — which is
  why the band draws ON the clips and the spare draws OUTSIDE them.
- **Tooltip timing is REST, not dwell.** The open clock (`DELAY_IN` 1000ms)
  restarts on every pointermove, so a tooltip is owed to a pointer that has
  *stopped* — sweeping a toolbar is silent at any value. Opening, swapping and
  closing are three separate constants and must stay that way: `DELAY_IN` 1000 ·
  `DELAY_FOCUS` 120 (keyboard has no pointer to still) · `DELAY_SWAP` 60 (one
  open, walking to a neighbour) · `DELAY_HIDE` 450 (grace, so slipping onto the
  gap between two buttons is travel not dismissal). Escape / press / scroll
  bypass all four. Never collapse them into one number. Canonical page:
  `pages/comp-tooltips.html`.
- **Tooltip:** `data-tip="Label"` on ANY element (optionally `data-tip="Label|⌘K"`
  for a shortcut, and `data-tip-side="top|bottom|left|right"`). It shows on hover
  AND on keyboard focus, flips when it would clip, and points its beak at the
  trigger. Do NOT use the native `title` and do NOT hand-roll a hint bubble: any
  `title` is upgraded to `data-tip` automatically, and the old `.tooltip` class
  is gone. For a doc page that needs one sitting in the flow, use `.tip-demo`.
  Lives in `shared/components/tooltip.{css,js}`.
- **Elevation:** depth comes from a TOKEN, never a hand-written shadow.
  `--shadow-1` raised a hair (handle, knob, selected segment) · `--shadow-2` the
  hover lift · `--shadow` the window · `--lg-shadow` a float over live content
  (popover, menu, toast, tooltip) · `--lg-shadow-3` a surface ON a float ·
  `--glow`/`--glow-sm`/`--glow-hi` a filled or selected control, recoloured by
  setting `--glow-c` on it · `--ring` focus, recoloured with `--ring-c`. Canvas
  ARTWORK is exempt. `node shared/check-elevation.mjs` fails the build on a
  hand-written one. Ladder + tokens live in `shared/components/elevation.css`.
- **Home:** every `.cmdpop` gets a trailing **Home** item automatically (the
  shell component appends it). Do not author one per page.
- **`.elev-0/1/2` and `.elev-3`**, the only surface allowed to sit
  ON a popover (a callout anchored to something inside it). It must not reuse the
  popover's tokens: dark lifts by getting lighter (`--glass-3`), light lifts by
  casting further (`--lg-shadow-3`). See `pages/lang-elevation.html`.
- **Scenario accent pips:** UI/components `var(--comp)`, image `#ff7e5f`,
  video `#12c2e9`, automation gradient `linear-gradient(120deg,#6E8BFF,#c56cff)`.

## Where the design system lives

`shared/photonz-ds.css` and `.js` are **empty on purpose**. Every component is
its own file under `shared/components/` (38 CSS, 17 JS), assembled into those two
URLs by `dev-server.mjs`. Pages are unaffected: same two `<link>`/`<script>`
tags, same order. To change a component, edit its file. To add one, add the file
and register it in `shared/components/order.json` at the cascade position it
needs. Never add rules to the two base files. See
`shared/components/README.md`.

## App shell (compose this, don't reinvent)

**"The app" is FOUR shell surfaces, not one window** (PRODUCT-MODEL.md §4e), and
**every one of them is shared**. If your page depicts any of them you reuse the
pattern below; you never invent a local version, and you never wrap one in fake
window chrome:

1. the **menu-bar (systray) app menu** — `.mbar` / `.mbicon` / `.mbmenu`
2. the **history overlay** — `.sheet.down.hist`
3. the **capture toast** — `.ctoast-stack` / `.ctoast`
4. the **editor window(s)** — `.win.tall.cq`

They form one loop: you capture from the menu bar or its shortcut, a **toast**
confirms it and says it is on the clipboard, the capture lands in **history**
(⇧⌘H or the same menu-bar icon), and picking it there opens an **editor window**.
Reference page for all four: `pages/app-shell.html`.

There is ONE window shell and it is **lean and canvas-first**: a floating bottom
tool bar, ONE right dock of stacked panel groups, and overlays. It **scales by
collapsing, resizing, and scrolling, never by inventing new chrome per feature**
(PRODUCT-MODEL.md §4b, UX-PATTERNS.md §1/§3). Do NOT hand-roll chrome.

### The shell is a COMPONENT. Do not hand-author chrome.

`photonz-ds.js` builds the title bar, the Ask launcher, the agent-chat overlay
and the `…` command-surface button. A page declares what it **is**:

```html
<div class="win tall cq shell"
     data-shell="promo-cut · 1920 × 1080 · <span id='docLen'>0:18</span>"
     data-ws="video"                        <!-- image | ui | video | none -->
     data-status="1080p · 30 fps">          <!-- optional readout, may hold ids -->
  <div class="edit lean" id="shell" data-dock="open">
    <div class="popover menu pop cmdpop" id="cmdMenu"> … this page's commands … </div>
    <div class="cnv"> … </div>
    <div class="pdock"> … </div>
  </div>
</div>
```

Text before the first `·` in `data-shell` is bolded. `data-shell`/`data-status`
may contain markup, so a walkthrough can drive a live readout by id.

**The title bar holds lights · document · status · Ask, and nothing else.** No
Share/Export/Done (the native menu bar owns those) and **no segmented control**:
three workspace tabs up there read as app-level navigation, which is the opposite
of what "one document, surfaces are lenses" is trying to say. `data-ws` still
records the document's kind, for the tool strip. The workspace switcher itself
is gone from the study entirely (PRODUCT-MODEL.md §4f): no page authors one,
and there is no shared class for it. Do not reintroduce a lens toggle.

**Panel-group height is a role, not a number.** Every page used to hand-pick
`--gh`, so the same panel expanded to a different height nearly everywhere:
measured across 17 shells, Layers had **11** distinct budgets (76–186px) and
Properties **13** (150–398px). Now a group declares what it is —
`data-grp="layers|props|effects|library|agent"` — and the ladder assigns one of
three sizes (`--gh-sm/md/lg`). A group needing a different budget names it
(`data-gh="lg"`); it never writes a pixel value. Anything that overflows scrolls
in its own `.dgrp-b`, which is what the budget is for.

**The component harvests before it deletes.** The old header rows mixed chrome
with content (this page's own command popover, a live status readout, a real
control like Reset or Play). On conversion the component moves popovers into
`.cnv`, status into `.wstatus`, and any remaining control into `.cnv-act` as an
icon `.tool` with its old label as the tooltip — then drops the empty rows. So
converting a page is just adding `data-shell`/`data-ws`; nothing is lost.

**This is the rule, not a convenience.** 57 pages each retyped the title bar, and
they drifted: Share/Export/Done buttons the canonical shell says the native menu
bar owns, a `.toolbar` command strip `app-shell.html` had already deleted, and 56
copies of the `.cmdk` search well that D6 replaced. The component **deletes** any
`.titlebar` or `.toolbar` it finds inside `[data-shell]`, so that drift cannot
come back. If chrome needs to change, change it in `photonz-ds.js` once.

What stays page-authored is **content**: the `.cmpop` menu items for this
scenario, the canvas, the dock groups, the tool strip. The `…` button that opens
the command menu is chrome and is built into `.cnv-act` automatically.

**A window with no document still gets that chrome.** The front door (New /
Open / Recent) holds no document, so it has no canvas, no tool bar and no dock —
but the agent is reachable from every window, not only from a document. So it
marks its content row `.shell-body` instead of `.edit.lean` and declares
`data-shell` as usual; the component builds the title bar and hosts the chat
overlay there, and the scrim dims the body while the title bar stays lit.
Canonical page: `pages/home.html`. Do NOT hand-author an `.askpal`.

Canonical composition (chrome marked ⚙ is built, not written):

```
.win.tall.cq[data-shell]         ← .cq = container-query root (responsive)
 ├─ .titlebar ⚙      (lights · wtitle · .wstatus · .askbtn Ask ⌘K — nothing else)
 │                   secondary surfaces (specimens) may still author .tbtns
 ├─ .edit.lean  [data-dock="open|closed|overlay"]
 │   ├─ .cnv                       ← the canvas column, and it dominates
 │   │   ├─ .canvas                → document + selection (.sel-ring/.handle/.mtag)
 │   │   │                          grid scales with --zoom; .canvas.mini = specimen
 │   │   ├─ .cnv-act ⚙            → the `…` command surface (D3) + page actions
 │   │   ├─ .tbar                  → floating tool bar: .tstrip · .swpair · .zoomctl
 │   │   └─ .sheet.down            → slide-down overlay (history)
 │   ├─ .cmdpop                    → THIS PAGE'S command menu (content)
 │   ├─ .askscrim ⚙                → the overlay scrim
 │   ├─ .askpal › .chat ⚙          → the agent chat / command palette (D6)
 │   ├─ .splitter.v                → drag to resize the dock
 │   ├─ .pdock                     → stacked panel groups
 │   │   ├─ .dgrp  (Layers)   › .dgrp-h + .dgrp-b   ← own bound + own scroller
 │   │   ├─ .splitter.h            → drag to resize the group above
 │   │   ├─ .dgrp  (Properties)
 │   │   ├─ .dgrp  (Effects)
 │   │   └─ .dgrp.grow (Library)   ← one group may take the leftover space
 │   └─ .drail › .drailtab         → what the dock collapses to
 ├─ .transport       (only when the document has time)
 └─ .timeline        (only when the document has time)
```

### The scalable dock vocabulary (all in `shared/photonz-ds.css`)

- **`.win.cq`** — makes the window the **container-query root**. Put it on every
  shell you author. Breakpoints: **≤880px** the dock rails + overlays and the tool
  bar overflows; **≤620px** the rail drops labels and the zoom slider drops out.
  Verify by narrowing the browser, not by drawing a small mock.
  **Gotcha:** `@container shell (...)` only matches **descendants of `.win.cq`**.
  A rule whose subject is an ANCESTOR of the window (e.g. the page `<section>`, or
  a custom property you set on `#my-page`) silently never applies — it will look
  like the breakpoint is broken. Put the property on an element *inside* the
  window instead.
- **`.edit.lean`** — the canvas-dominant editor row (flex, replaces the fixed
  3-column `.edit` grid). `data-dock="open|closed|overlay"` is the single state.
- **`.cnv`** — the canvas column. Everything that floats over the canvas is a
  child of this.
- **`.dgrp` › `.dgrp-h` + `.dgrp-b`** — a **collapsible, scroll-constrained panel
  group**. The header takes a title (`.ttl`), an optional count (`.cnt`), and
  buttons; `ds.js` injects the chevron and wires collapse (`.dgrp.collapsed`). The
  body gets its **own** `max-height` via `--gh` and its own scroller, so a long
  list never pushes its siblings off screen. `.dgrp.grow` takes the leftover
  space. **New capability = a new group, not new chrome.**
- **`.splitter.v` / `.splitter.h`** — drag to resize (dock width / group height).
  `data-resize="prev|next"`, `data-min`, `data-max`. Keyboard-resizable, visible
  grip, accent on hover and drag. Sizes persist for the session.
- **`.drail` › `.drailtab`** — the collapsed rail. Give each tab
  `data-group="#groupId"` so it restores the dock and reveals that group.
- **`.cnv-act`** — canvas top-right cluster. Put the **panel toggle** here:
  `<button class="tool" data-dock-toggle="#shellId">` with `ic-sidebar`.
- **`.tbar`** (inside `.cnv`) — the **floating bottom tool bar**: `.tstrip` of
  `.tool`s, `.tsep`, the `.swpair` foreground/background swatch with an
  `ic-swap` button, `.tsep`, then `.zoomctl` (`.zslider` + `.val.zval`). Mark
  lower-priority tools `.ovf`; they hide when narrow and a `.tbar-more` button
  opens the same list as a `.popover.pop.menu`.
- **`.sheet.down`** — a slide-down **overlay**. `.sheet-h` (title, `.sp` spacers, a
  `.seg`, actions, `[data-sheet-close]`) + `.sheet-b`. Toggle it with
  `[data-sheet="#id"]`; Esc closes. Use it for anything catalog-like that would
  crowd the canvas. **Not** for history — see the next bullet.
- **`.sheet.down.hist`** — the **capture history pane**, and it is
  **CHROMELESS**: no `.titlebar`, no traffic lights, and **no `.sheet-h` header
  row** (PRODUCT-MODEL §4b req 5). It is a global surface belonging to the
  **menu-bar agent**, not to a window, so it floats inset near the top over
  whatever is behind it. Compose exactly:
  `.sheet.down.hist` › `.sheet-b` › `.histbar` + `.filmstrip`. `.histbar` is a
  **centered `.seg`** (All · Screenshots · Videos, active scope filled accent)
  plus `.hb-r` holding a top-right **Clear All** with `ic-trash`. Those two
  controls and the filmstrip are the entire surface. Esc or an outside click
  dismisses it; there is no close button to draw.
- **`.filmstrip` › `.filmcard`** — the capture filmstrip, scrolls horizontally:
  `.th` (video captures add a `.pl` play affordance and a `.dur` duration badge),
  `.cap` › `.nm` + **`.ago` relative time on EVERY card** ("14 minutes ago"), and
  `.acts` (copy, edit, pin, delete) which only appears on `.filmcard.sel`. Wrap in
  `data-radio=".filmcard" data-radio-class="sel"` for single selection, and ship
  the pane with **one card already selected** so the action row is visible. Show
  enough cards to read as a strip (the real pane shows about eight).
- **`.transport`** — the video bottom bar, in this order and with nothing else in
  it: a `.grp` for volume, a `.grp` for skip back / play / skip forward (and loop,
  if the page has one), `.tc.cur`, a `.scrub` (`.fill`, `.mark` in/out, `.knob`,
  `data-duration`), `.tc`. **Time controls only — see UX-PATTERNS D8.** The
  scrubber is the only flexible child and it needs every pixel: an edit action
  parked beside it is stealing from the one control here you have to aim. Put the
  action in the title bar, the tool strip, next to the selection it acts on, or on
  the timeline dock's own `.tlbar`, in that order of preference.
- **`.popover.pop`** — any menu toggled by `[data-menu="#id"]`. Outside-click and
  Esc dismiss it. Use it for the command surface, panel menus, tool overflow.
- **`[data-radio="<sel>"]`** — exclusive selection inside a container
  (tool strips, filmstrips). `data-radio-class` picks the state class.

### The GLOBAL surfaces: the menu bar and the capture toast

These two belong to the resident **menu-bar agent**, not to any window, so they
never wear a `.titlebar` or traffic lights. Give them a **desktop** to float over
and the specimen stays honest (PRODUCT-MODEL §4c: a specimen wears no app chrome).

- **`.desk` › `.mbar` + `.deskbody`** — the screen the agent lives on. `.desk` is
  a flex column, clips its own overflow, and is a **container query root named
  `desk`**, so the surfaces inside it respond to the screen, not the browser. Give
  it a definite height in your page CSS. The wallpaper is artwork, not chrome.
  `.deskbody` is the positioning context for anything that floats over the screen.
- **`.mbar`** — the macOS **status strip**. Only the right-hand status area is
  ours; this mock NEVER draws a fake set of app menus (D3). Compose
  `.sp` (spacer) · `.mbitem` · `.mbicon`s · `.clock`. Below a 560px desk the clock
  drops and below 400px the strip and menu tighten, the way macOS condenses.
- **`.mbitem` › `.mbicon` + `.popover.menu.mbmenu`** — the **menu-bar (systray)
  app menu**, and this is the app's REAL root: capture starts here, history opens
  here, and every document is created here. `.mbitem` is the positioning context.
  `.mbicon` is the status item (26×22 template glyph, use `ic-aperture`, the mark
  the shipping app draws); it fills with the accent while its menu is open, via
  `.on` or `aria-expanded="true"`. It is a **native menu**, so build it out of
  `.menuitem` + `.sc` + `.menu-sep` and nothing else: no icons, no custom widget.
  Contents in order, groups split by `.menu-sep`:
  `Capture Region ⇧⌘4` · `Capture Full Screen ⇧⌘3` · `Stop Recording ⇧⌘5` /
  `Show History ⇧⌘H` / `New Window` · `New from Clipboard` · `Open…` /
  `Check for Updates…` · `Welcome & Permissions…` · `Preferences…` ·
  `About Photonz` / `Quit Photonz ⌘Q`.
  Author each row as a `<button class="menuitem">` so it has real hover, focus,
  and `.disabled` states; hover fills the whole row in the accent like a real
  macOS menu. Add `[data-menu="#id"]` to make it toggleable, or leave `.pop` off
  and it stays open, which is what an anatomy specimen wants.
- **`.ctoast-stack` › `.ctoast`** — the **capture toast**, the "it worked, and
  it's on your clipboard" feedback. Anchored bottom-right of the `.deskbody`,
  newest card in the corner, older ones stacking upward. One card is:
  `.cshot` (the **actual captured thumbnail**, 16:10, subtle inner border) then
  `.cfm` › `.ok` (green check) + **"Copied to clipboard!"**. A recording carries
  the same `.pl` + `.dur` vocabulary a `.filmcard` does, so kind is legible
  everywhere. It is **transient: no close button, no dismissal chrome**, and it
  is fixed-dark in both themes because it floats over a desktop, not over the app.
- **`.wshot`** — miniature "screenshot of a window" artwork for a `.cshot` or a
  `.filmcard .th`, so a capture is never an empty gray rectangle:
  `.wshot` › `.w` › `.tb`>i·i·i + `.bd` › `.sd` + `.mn` › `.ln`/`.ln.s`/`.ln.a`.
- **`[data-toast="#someToast"]`** — JS hook: fires another copy of that `.ctoast`
  into the `.ctoast-stack` it lives in and removes it a few seconds later, so a
  page can show the real behavior (captures stack, each one leaves on its own).
  The card you point at stays put; only the clones come and go.

### Still true

- **Library scope switch** — reuse the existing **`.seg`** (Media · Components ·
  Styles · Systems) inside the **Library panel group**. One Library surface, four
  scopes; do not promote a scope to its own dock or window. The video "media pool"
  is this group with scope = Media (D1, amended: it is a **right-dock group or an
  overlay**, never a left dock).
- **`.libtools`** — the Library toolbar row: a search field + `+ Import` button.
- **`.srch`** — reusable search field (`.ic-search` + `input`), capsule glass.
- **`.libgrid` › `.libtile`** — grid of draggable-looking thumbnail tiles
  (`.libtile .th` / `.cap` / `.nm` / `.mt`; `.libtile.sel`, `.libtile.comp`).
  Selecting a tile drives Properties, same selection model as a canvas layer.
- **`.askbtn` › `.askpal`** — the **Ask launcher** in the title bar's right slot
  and the agent chat it opens (D6 revised), the **secondary** command path.
  `.askbtn` is a raised `.btn` variant (sparkle + "Ask" + `⌘K` hint), wired with
  `data-ask="#askPal"`; `⌘K` opens the same overlay. `.askpal` is a centred
  elevation-2 overlay (glass + blur + shadow + an auto-created `.askscrim`) that
  **hosts the shared `.chat` component**, so it and the Agent panel group in the
  dock are one conversation in two places. Typing `/` in its composer turns it
  into the command palette: a filtered `.cplist` of `.cpx` rows inline above the
  composer, each labelled with its real API name. One field, two modes, one call.
  Pair it with a `.tool` `ic-more` **command surface** button (D3) opening a
  grouped `.popover`/`.menu`/`.menuitem`/`.menu-sep`. The **native macOS menu bar
  is the real command surface**; NEVER draw a fake one in the mock, and never add
  a permanent options-bar row of tools (tools live in `.tbar`).
- **`.cmdk`** — DEPRECATED. The old ⌘K search well. Do not add it to a page; it
  survives only until every page is swept onto `.askbtn`.
- **`.wsw`** — REMOVED. The workspace switcher (an Image · UI · Video lens
  toggle in the title bar) is superseded by PRODUCT-MODEL.md §4f: a workspace is
  only a starting template at New. The title bar carries document identity; the
  tool strip follows the document's kind; the timeline appears when the document
  has time. Never add a lens toggle to any chrome.
- **`.lrow.adj` + `.clipmark`** — an **adjustment / filter layer**, a first-class
  layer type. Renders in Layers with the `ic-sliders` glyph and a `.clipmark`
  showing it clips to the layers below. Its properties open in the Properties
  group as a normal `.section` of `.row`/`.bar`/`.val` sliders. Because it is just
  a layer, it grades a UI frame exactly as a photo. Add it from the Layers group
  header (a `.btn.ghost.icon.sm` `ic-sliders` that opens a `.popover.pop.menu`).
- **`.dnav` › `.dtab`** — a tab header for a panel host. Legacy from the left-dock
  model; prefer stacked `.dgrp` groups. Only reach for it when two views genuinely
  swap in the same slot.

Tool strip order is fixed per D4 (`Select → create cluster → measure → Hand →
Zoom`); shared tools keep the same glyph and slot in every workspace. Selection
shows in three places at once: `.sel-ring` on canvas, `.lrow.sel` in Layers, and
Properties. Region callout labels on a reference/anatomy page are page-local
(`.rnum`/`.leg` in `app-shell.html`), not shell chrome.

**Two hard rules when you author a shell:** give the `.win` a **definite height**
(so the dock is bounded and the group scrollers do the work instead of the window
stretching), and put every long list inside a `.dgrp-b`.

## Usage walkthroughs: ONE app, operated (PRODUCT-MODEL.md §4d)

A walkthrough is **not a slideshow of windows**. The old format rendered a new
illustration per step, so it could never answer the only questions that matter:
*what did I click, where does that control live, and what changed?* Re-chroming
each illustration does not fix that. The format below does.

**The contract:** render the app screen **once**, then **operate** it. A step
declares STATE, anchors a **click cue** on the **real control in its real
place**, and reads out one fixed caption grammar. The shell never re-renders.

### Structure

```html
<div class="wt">
  <div class="wt-stage">
    <div class="win tall cq shell"> …ONE complete app screen… </div>
  </div>

  <ol class="wt-steps">
    <li class="wt-step"
        data-title="Pick up the Blade"
        data-cue="#tBlade" data-cue-label="Click the Blade tool" data-cue-place="top"
        data-tool="#tBlade" data-open="#gLibrary" data-scope="media">
      <div class="wt-cap vid">           <!-- .comp / .img / .vid tints the number -->
        <span class="wt-n">7</span>
        <p class="wt-do">the <b>Blade</b> tool</p>
        <p class="wt-where">the floating tool bar, under the canvas</p>
        <p class="wt-res">Blade becomes the active tool.</p>
      </div>
    </li>
  </ol>

  <div class="wbar">
    <button class="wprev">Back</button>
    <div class="wdots"></div>            <!-- ds.js fills this in -->
    <span class="wlabel"></span>
    <button class="wt-reset">Reset</button>
    <button class="wnext next">Next</button>
  </div>
</div>
```

`ds.js` snapshots the stage's authored baseline, and on every step change it
**resets and replays steps 0..n**, so state accumulates in order and Back is
always exact. Nothing is animated into place by hand.

### Step directives (all optional, all resolved inside `.wt-stage`)

| attribute | effect |
| --- | --- |
| `data-tool="#tBlade"` | exclusive `.on` among the `.tool`s in that tool's `.tstrip` |
| `data-activate="#wsVideo"` | exclusive `.on` among an element's like-classed siblings (any one-of-N segmented control) |
| `data-open` / `data-collapse` | un-collapse / collapse `.dgrp` panel groups (comma list) |
| `data-dock="open\|closed\|overlay"` | the `.edit.lean` dock state |
| `data-scope="media"` | Library scope: `.on` the `[data-scope]` button, reveal `[data-scope-body="media"]`, set `[data-scope-label]` from `data-scope-name` |
| `data-select="#lrHero"` | exclusive selection across `.lrow` / `.libtile` / `.filmcard` / `.clip`. Class from `data-select-class`, else the target's `data-sel-class`, else `sel` |
| `data-show` / `data-hide` | drop or add `.wt-off` (reveal canvas content, selection rings, badges, empty states) |
| `data-sheet-open` / `data-sheet-shut` | the `.sheet.down` overlay (history) |
| `data-pop="#layerMenu"` | open a `.popover.pop`, so a cue can sit on a real menu item. Every step shuts every popover first, so a menu that stays open across two steps declares it on both |
| `data-time="on\|off"` | the document has time: shows or hides `.transport` + `.timeline` |
| `data-set="#id=text\|#id2=text"` | set a readout's text (counts, titles, values) |
| `data-css="#clipA=width:26%"` | inline geometry (a trimmed clip, a bar) |
| `data-class="#trans1=blk\|#cvTitle=-caret"` | add a variant class for this step; a leading `-` takes one off again |
| `data-cue` / `data-cue-label` / `data-cue-place` | the click cue and its label; place is `top\|bottom\|left\|right`, auto if omitted |

`.wt-off` is the ONE class for "not in the document yet". Author the finished
state in markup and hide the parts a later step reveals.

**The timeline measures the lanes, not the window.** `.ruler` is inset by the
track label, and `.playhead` takes `--t`, a 0..1 position in LANE space
(`data-css="#playhead=--t:0.44"`), so a time on the ruler, a clip edge, and the
playhead all land on the same pixel. An inline `left:%` still works for the older
pages, and it is wrong by the width of the track label.

### The cue

`ds.js` injects a `.wt-cue` into `.wt` and positions it over the target with
`getBoundingClientRect`, matching the control's own corner radius, with a pulse
ring and a short label. It repositions on resize, on group scroll, and after the
shell's own transitions settle. If the target is inside the dock and the window
is narrow, the cue **summons the dock as an overlay** so there is always
something to point at.

**Anchor the cue on a control that still EXISTS after the step's state applies.**
If clicking a control makes it disappear (an overlay's Open button that also
closes the overlay), split it into two honest steps instead.

### The caption grammar

Exactly three lines, in this order, labelled by CSS so every walkthrough in the
study reads identically:

> **Click** &lt;control&gt; · **in** &lt;where it lives&gt; · **Result:** &lt;what changed&gt;

Use `data-verb="Drag"` on `.wt-do` when the gesture is a drag. Keep `.wt-res`
concrete: name the panel, the badge, the row, the chrome that appeared.

### Hard rules

- **The window is an app screen**, so §4c applies in full: real `.titlebar` +
  `.toolbar` + `.edit.lean` + floating `.tbar` + the dock groups its workspace
  calls for. No arbitrarily missing toolbar or dock.
- **Title bar = document identity only** (`brand-system · 1200 × 630`,
  `promo-cut · 1920 × 1080 · 0:18`). **NEVER** put the lesson title there. The
  lesson title goes in `.scen-head` and the captions, outside the window.
- **A step that cannot be expressed as a real click on a real surface is not a
  usage step.** Either add the affordance to the app, or move the idea to
  Prototypes & Ideas.
- Give the `.win` a **definite height** and keep every long list in a `.dgrp-b`,
  so the page works narrow. Verify by narrowing the browser.
- `?step=5` deep-links a walkthrough to one step, which is handy for review.
- **History is global.** Photonz is a resident menu-bar agent, so a walkthrough
  that starts from capture history must invoke it from the **menu-bar icon** or
  **⇧⌘H**, with no editor window open, and the editor is what a capture *opens
  into* (PRODUCT-MODEL §4b req 5). An in-window History button is a convenience,
  never the taught path. `pages/capture-wt.html` shows the small desktop +
  menu-bar agent representation this needs.

### Blank-slate ENTRY walkthroughs: one shared template

Every "how do I start from nothing" clickthrough opens on the SAME screen: an
empty desk, the resident menu-bar agent, and the global history. That chrome is
identical by definition, so it is a component (`shared/components/entry.js`),
not markup you retype. Mark the desk and it is built for you:

- **`.desk[data-entry]`** injects the canonical **`.mbar`** (spacer · Photonz
  status item with the FULL canonical menu · sound · clock) as the desk's first
  child, unless the page authors its own `.mbar`. Stable ids for step cues:
  `#mbAgent #mbMenu #miCapture #miCaptureFull #miRecord #miHistory
  #miNewWindow #miNewClipboard #miOpen`. `Show History` is auto-wired
  (`data-sheet`) to the desk's own `.sheet.down.hist`.
- A history sheet with no `.histbar` gets the canonical one injected
  (`#hsAll #hsShots #hsVids` + Clear All).
- **`.filmstrip[data-entry-fill]`** gets the **standard past** appended after
  the page's own card(s): the same eight filler captures on every entry page.
  Cards carry their kind (`.fk-shot` / `.fk-clip`; stamp your own cards too),
  and the strip filters with `.flt-shot` / `.flt-vid` — a step drives it with
  `data-activate="#hsVids" data-class="#<stripId>=flt-vid"`, and direct clicks
  on the injected histbar do the same live.

The page authors only what is unique to its flow: the desk artwork and hint,
its own history card(s), the toast, and the editor window(s) the flow opens
into. One entry page exists per surface and they share this template:
`capture-wt` (image), `ui-entry-wt` (UI, via New Window and the front door),
`video-entry-wt` (video, via history's Videos scope).

Reference implementations: `pages/ds-build-wt.html`,
`pages/video-transition-wt.html`, and (for the entry template)
`pages/capture-wt.html`.

**One scenario per page.** The video clickthroughs are the model: `transition`,
`cut`, `title`, `move`, `zoom`, `freeze`, each answering one question a person
actually arrives with ("how do I put a dissolve on that cut?"). A page that
teaches importing AND cutting AND titling AND exporting teaches none of them,
which is why `video-create-wt` was retired.

### Legacy: `.wsteps`

`.wsteps` swapped a whole illustration per step, which is exactly the failure
§4d forbids. The conversion is COMPLETE: no page uses it any more (verified
2026-08-23), and only the driver in `core.js` remains for archival safety.
**Never author a page with it; every walkthrough is a `.wt`.**

## Controls (canonical)

There is ONE button system: `.btn`. **Every button must use it.** No ad-hoc
square, tiny, or round buttons, and no inert controls — if it is interactive it
MUST show visible **hover, active/pressed, focus-visible, and disabled** states
(the `.btn` system and the normalized controls below already do). All controls
are capsule Liquid-Glass and size off the 4pt scale.

- **Sizes:** `.btn` (default/md, 32px) · `.btn.sm` (24px) · `.btn.lg` (40px).
  Heights, padding, and font all come from the 4pt tokens.
- **Variants:** `.btn.primary` (glossy accent glass) · `.btn.secondary` (neutral
  glass) · `.btn.ghost` (transparent, fills on hover) · `.btn.danger` (crit
  glass). Variants are consistent across every size.
- **Shapes:** `.btn.icon` (square/circular icon-only, same height as its size) ·
  `.btn.block` (full width). Icon + label sit on one line (`gap` from tokens,
  `white-space:nowrap`); drop an inline `svg` or `.ic` for the glyph, `.kbd` for
  a shortcut hint.
- **States (built in, all variants):** hover brightens + edge highlight, active
  scales down / insets, `:focus-visible` shows the accent ring (`--ring`),
  `[disabled]`/`.disabled` dims and kills pointer events.

Example: `<button class="btn primary lg">…</button>`,
`<button class="btn ghost icon"><svg…></svg></button>`,
`<button class="btn danger block">Delete</button>`.

The older controls (`.pill`/`.pill.solid`/`.pill.ai`, `.tool`, `.chip`,
`.select`, `.seg`) keep their existing roles but are normalized to the SAME
hover/active/focus/disabled response and capsule radii, so everything reads as
one system. Prefer `.btn` for any new button; reach for the others only in their
established slots (toolbar status pill, toolbar icon `.tool`, inspector
`.select`, tag `.chip`, segmented `.seg`).

## Cross-links between pages

To make something jump to another page, add `data-target="<page-id>"` to the
element. ds.js turns it into a shell navigation automatically. Page ids are the
file basenames: `foundations home walk composites dsys editor states typography
image redline video agent paint effects ideas`.

## Core product thesis (keep every page on-message)

Primitives → API → UI. Five primitives (Paint, Effect stack, Layer, Type,
Tokens) + a reuse tier (Tokens → **Styles** → **Components**). Components are
reusable layer trees you instance & re-paint with Styles; the same component drops
onto UI, a photo, or a video timeline. Automation is model-agnostic: local Qwen
(MLX) default + frontier via MCP; the command schema keeps it safe. Everything the
UI does is one API call, so an agent can do it too (local model by default, frontier via MCP). Full spec:
`docs/design/creation-vision.md`.

## Design-language SUB-PAGE spec (pages/lang-*.html)

A design-language sub-page is a deep dive on ONE app-shell pattern (frame,
toolbars, docking, resizable panes, collapsible sections, overlays, selection,
elevation, spacing, motion, color/states, keyboard). It is a reference page, not a
scenario. Structure it as stacked blocks in this order, each a titled card/window
using DS classes:

1. **Breadcrumb + intro** — `.scen-head` with h2 = the pattern name and
   `<span class="k">· Design language</span>`; add a small back-chip that
   cross-links `data-target="language"` to the overview. One-sentence "what it is
   and when to use it".
2. **Anatomy** — a live specimen of the component with its parts labeled (callout
   labels pointing at regions, or a labeled legend). Name each part.
3. **Variants & sizes** — the meaningful variations shown side by side.
4. **States** — rest / hover / focus / pressed / disabled / active as applies.
5. **Live examples** — 2 to 3 real specimens in realistic context (inside a `.win`
   or `.pane` where it belongs).
6. **Rules — Do / Don't** — 3 to 5 short do/don't lines (use `.good`/`.crit` cues).
7. **In the API** — how the pattern is addressed by a command (e.g.
   `panel.dock("right")`, `section.collapsed=true`, `run("tool.text")`), tying to
   the "everything the UI does is one API call" thesis.
8. **Responsive / compact** — one line on how it adapts in a small window.
9. Close with the three `.caption` notes (idea / direction / open question).

Keep it calm and scannable; the page must itself be an exemplar of the pattern it
documents. Reuse the real DS classes for that pattern (read them in
`shared/photonz-ds.css`) rather than inventing look-alikes. Cross-link to sibling
patterns and to `dsys`/`editor` where natural.

## Latitude

Within your topic, go beyond the literal ask — propose genuinely good ideas a
Figma/Photoshop/Premiere power user would love, as long as they fit the thesis and
the design system. Every page ends with `.caption` notes: **the idea**, **a
direction/alternative**, and **an open question**. Keep copy plain and human (no em
dashes, no "leverage", no mention of the tooling, never say "Claude" in UI copy (say "agent")). Verify your page renders by
checking it loads at `http://127.0.0.1:8791/pages/<id>.html` (a dev server with
livereload is running).

## Iconography (NEVER use ascii/unicode glyphs)

There is a monochrome SVG icon set in the shared DS. Use it for every glyph.
NEVER use ascii/unicode symbols (◄ ▭ ✎ ◈ ⌗ ▾ ◉ ◆ ✦ ⋮⋮ ↺ ▶ 🖌 etc.) as icons.

**Two carve-outs (these are NOT icons, leave them):**
1. **Keyboard-shortcut symbols** — `⌃ ⌥ ⇧ ⌘ ⌦ ⌫ ↩ ⎋` inside a `.kbd`, `.sc`, or
   `<code>` shortcut hint are the correct macOS notation, not icons. Keep them.
   **Modifiers always print in the macOS order `⌃ ⌥ ⇧ ⌘`, then the key**, with no
   `+` between them: `⇧⌘H`, `⌥⌘L`, `⇧⌘4` — never `⌘⇧H` or `Cmd + Shift + H`. One
   shortcut has exactly one spelling everywhere it appears, so a chord looks the
   same in a menu, a tooltip, a keycap row and the `lang-keyboard.html` legend
   that documents this rule.
2. **Typographic marks in running prose** — an arrow or middot used as a text
   connector in an explanatory sentence or caption ("before → after", "Tokens ·
   Styles · Components") is text, not an icon. Only convert a glyph when it acts
   AS an icon: inside an interactive control (`.tool`/`.btn`/tab/menuitem), a
   `.lrow`/badge, a toolbar, or as a status/disclosure indicator.

Usage: `<i class="ic ic-<name>"></i>` — inherits `currentColor`, sized by role
with `.ic.xs` 12 / `.ic.sm` 14 / `.ic` 16 / `.ic.lg` 20 / `.ic.xl` 24. Never an
ad-hoc `width:15px`. It works inside `.tool`, `.btn`, `.lrow`, `.menuitem` and
badges.

The set is drawn to one grid: 24 x 24 box, 20 x 20 live area, square keyline
18 x 18, circle keyline d17.2, stroke 1.75 with round caps and joins, fills
only where the glyph is solid by nature (play, keyframe, star, cursor, sparkle,
dots). Adding a glyph means adding it to `shared/icons.mjs` and running
`node shared/build-icons.mjs` from `docs/design/mocks` — that regenerates the
CSS, the iconography page and this list together. Do NOT hand-write a mask rule
into `photonz-ds.css`; the generated block is overwritten.

The full searchable library, with the grid and the drawing rules, is
`pages/iconography.html`. Names by group:

<!-- ICONNAMES:BEGIN -->
**Navigation & disclosure** — chevron-up chevron-down chevron-left chevron-right chevron-updown arrow-up arrow-down arrow-left arrow-right more more-vertical external

**Core actions** — plus minus x check check-circle x-circle search trash copy duplicate undo redo save export import share link unlink refresh settings info help filter

**Documents & library** — home document document-new folder folder-open library grid list tag image star history pin archive

**View & canvas** — zoom-in zoom-out zoom-fit zoom-actual hand maximize minimize sidebar-left sidebar-right panel-bottom canvas-grid rulers snap

**Tools** — cursor move marquee-rect marquee-ellipse lasso wand subject crop straighten ruler eyedropper pen pencil brush eraser fill gradient clone heal patch dodge-burn blur-tool text

**Shapes & vector** — square circle line triangle polygon frame bezier node corner-radius path-close boolean-union boolean-subtract boolean-intersect boolean-exclude flatten

**Layers & structure** — layers layer-add group ungroup component instance mask clip eye eye-off lock unlock opacity blend merge

**Transform & arrange** — flip-horizontal flip-vertical rotate-left rotate-right align-left align-center-h align-right align-top align-middle align-bottom distribute-h distribute-v bring-forward send-backward swap scale flow-horizontal flow-vertical

**Adjust & effects** — sliders swatch exposure contrast saturation temperature curves levels sharpen blur noise vignette shadow glow border effects

**Type** — bold italic underline strikethrough text-align-left text-align-center text-align-right text-align-justify line-height letter-spacing font-size list-bullet list-number

**Media & timeline** — play pause stop skip-back skip-forward step-back step-forward loop keyframe transition blade trim speed timeline audio waveform volume volume-off solo mic captions video film camera aperture

**Agent, capture & system** — sparkle chat capture record window display cloud download upload branch compare restore keyboard command warning

Aliases (older names, still render): zoom→zoom-in sidebar→sidebar-right edit→pencil fullscreen→maximize align-center→align-center-h color→swatch agent→sparkle add→plus close→x delete→trash split→blade measure→ruler visible→eye hidden→eye-off
<!-- ICONNAMES:END -->

Glyph -> icon mapping when sweeping: select/pointer -> cursor; move -> move;
frame -> frame; shape/rect -> square (or circle for ellipse); pen/edit -> pen;
T/text -> text; image -> image; measure -> ruler; crop -> crop; visibility/eye ->
eye (eye-off when hidden); component/instance (◈/◆) -> component; keyframe (◇) ->
keyframe; agent/AI (✦) -> sparkle; add (+/✚) -> plus; reset -> undo; play/pause ->
play/pause; brush -> brush; eraser -> eraser; drag handle (⋮⋮) -> more; search ->
search; back -> chevron-right (or a left variant); export/import/save -> export/
import/save; layers -> layers; blade/split -> blade; zoom -> zoom; hand/pan -> hand;
magic/select-subject -> wand; adjustments -> sliders; redact -> blur (the effect
IS a blur; eye-off means "this layer is hidden" and nothing else); open a
capture/document in the editor -> external (pen/pencil is Edit, so Open must not
share it); save something as a style -> swatch (a style is always swatch, never
library). If no icon fits, use a clean text label, never an ascii symbol. If you truly need a new icon, add it to the
generator (Scripts) not inline.

## VISUAL RULES (non-negotiable, from design review)

These came from reviewing real screenshots. Each one is a rule, not a preference.

1. **Padding is consistent.** Comparable surfaces get identical padding from the
   4pt tokens. Never mix ad-hoc paddings inside one panel or between sibling
   cards.

2. **Concentric radii.** When a rounded thing sits inside another rounded thing,
   the gap between their edges must stay CONSTANT around the corner. So the inner
   radius is SMALLER: `inner = outer - gap`. Use
   `border-radius: calc(var(--r-outer) - var(--pad))`. An inner radius equal to
   (or larger than) its outer radius reads as broken.

3. **Round inside round.** A control inside a pill/capsule container must match
   that geometry: circular for icon-only, capsule for labelled. A rounded
   RECTANGLE button inside a pill tool bar is wrong.

4. **Panel groups must be manageable.** Every `.dgrp` header needs a visible
   collapse/expand affordance, and the dock needs an obvious way to manage which
   panes are shown. A header with no toggle is a dead end.

   *Implemented.* The chevron was already auto-injected into every `.dgrp-h`;
   what was missing was the dock-level decision. Every `.pdock` with 2+ groups
   now ends in a sticky `.dockmgr` footer - one `PANELS` button opening a
   checklist BUILT FROM THAT DOCK'S OWN GROUPS, so no page authors it and none
   can drift. Unchecking sets `.dgrp.hidden` (display:none); collapsing still
   leaves the header. A `.drailtab` un-hides as well as un-collapses.
   The bar carries NO backdrop-filter on purpose: a blurred ancestor becomes a
   backdrop root and the menu nested inside it rendered see-through, which
   broke rule 11.

5. **One canvas treatment everywhere.** The grid + subtle radial gradient is the
   canonical canvas for image, UI and video alike. **The grid SCALES WITH ZOOM**,
   so grid density tells you your zoom level. Do not invent a per-page canvas.

   *Implemented.* `.canvas` owns a minor grid, a major grid every 5 cells, and
   the radial artboard. `photonz-ds.js` drives `--zoom` (1 = 100%) from any
   `.zslider`, scoped to the canvases inside that slider's own
   `.cnv`/`.edit`/`.wt-step`/`.win`/`.shell` — a page with several windows
   zooms only the one you touched. Use `.canvas.mini` for an inline specimen
   canvas in a doc card (smaller cell, no editor min-height, rounded).
   A page may retune exactly three knobs and NOTHING else:
   `--artboard-glow` (glow size), `--artboard-ink` / `--artboard-bg` (its two
   colours; set them equal for a flat artboard). Re-declaring `background` on
   a canvas is a bug — four pages did it and each had drifted. If the retuned
   artboard is LIGHT, add `.canvas.on-light` so the grid flips dark instead of
   vanishing.

6. **No segmented controls in narrow panels.** `.seg` does not resize down; in a
   ~268px dock it wraps to two rows and looks broken. Use a `.select`/menu, or a
   wrapping chip list, for scope switching in a panel.

   *Implemented.* Any `.seg` inside `.pdock`/`.dgrp-b` gets the dock form
   automatically - applied by LOCATION (segmented.css), so no page opts in
   and none can opt out. It is a one-row grid of NATURAL-WIDTH columns
   (`minmax(0,max-content)` spread with `space-between`), so each label gets
   exactly the width it needs; nothing ever wraps. When the whole label set
   genuinely cannot fit the track, segmented.js collapses the control to a
   menu trigger (`.collapsed`) instead of letting labels ellipsize. SEVEN
   pages had each invented the same `display:flex;width:100%` +
   `button{flex:1}` workaround; all seven are deleted. Do not write an
   eighth.

7. **Do not mix inputs and buttons on one skinny row.** A search field next to an
   Import button in a dock truncates the field to nonsense ("Search cor"). Stack
   them. **Be deliberate about how many things you stack horizontally** in narrow
   space.

   *Implemented.* `.libtools` wraps, and the flex BASES do the deciding:
   160 + 120 + gap cannot fit a dock, so each control takes its own full-width
   line there and they sit side by side only in a wide window. No breakpoint,
   no container query, and it reflows live while the splitter is dragged.

8. **Library tiles must stay recognizable.** Justify/size the grid so a card
   reads as a card (min tile width, `auto-fill`), never squeezed into skinny
   unrecognizable slivers.

   *Implemented (width).* `.libgrid` was `repeat(3,1fr)` - a FIXED column count,
   so a 268px dock produced 76px tiles with a 46px thumb and an ellipsised
   name. It is now `repeat(auto-fill,minmax(96px,1fr))`, so the dock decides
   how many cards fit (2 at rest, 4 in a widened dock) instead of three no
   matter what, and `.libtile .th` uses `aspect-ratio:16/10` so the thumbnail
   grows with the tile - a fixed strip on a wide tile reads as a list row.
   Measured across 209 tiles on 64 pages: smallest is now 107px (was 76), zero
   ellipsised names.

   *Implemented (height).* A card cut in half by the dock edge is a sliver too,
   and the Library's own chrome was eating more than a whole tile row. The
   space came from deleting a DUPLICATE affordance rather than from a bigger
   floor: the body's Import button is gone on the 39 pages whose group header
   already carries a `+` Import menu (chrome 102px -> 77px), and `.dgrp.grow`
   now floors at 244/200 so one whole card row is visible with the next
   peeking as scroll affordance. Do not re-add an Import button inside
   `.libtools` - the header `+` is the canonical one.

9. **Counts are badges after the label, left-aligned.** `SECTION [2]` with the
   badge immediately following the header text. Never right-align a count across
   from a left-aligned header.

   *Implemented.* `.dgrp-h .ttl` no longer takes the free space; `.cnt` is a
   pill right after it. The first element AFTER the label or its badge takes
   the auto margin instead, so trailing buttons still sit at the right edge and
   no page markup had to change.

10. **Related controls sit together.** Walkthrough **Back and Next are adjacent**
    (Back immediately left of Next), and stepping supports **arrow keys**. Never
    split a related pair to opposite ends of a bar.

    *Implemented.* The nav is no longer a detached strip under the caption:
    `ds.js` wraps `.wt-steps` + `.wbar` in a generated `.wt-panel`, and the
    card chrome moved from `.wt-cap` up to that panel, so the caption and the
    controls are ONE box. `.wbar .wt-reset{margin-left:auto}` is deleted - it
    was what stranded Back at the far left and Next at the far right. The bar's
    children are reordered IN THE DOM to dots · label · **Reset · Back · Next**,
    not with CSS `order`, which would move them visually while leaving tab
    order telling a different story. Arrow keys are bound per `.wt`: one
    walkthrough on a page responds without needing focus, more than one
    requires it, and arrows aimed at a text control are never intercepted.
    Author the bar however you like - ds.js fixes the order - but do NOT
    re-add a `margin-left:auto` to any of the three buttons.

11. **Menus and popovers are opaque.** Darkened AND blurred background so text is
    fully legible over any content. A see-through menu is a bug.
