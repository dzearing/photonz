# UX audit — clustered findings (all 63 pages)

> **SUPERSEDED by the 2026-08-23 rescan.** A fresh clusters A-G scan over all
> 88 pages lives in `ux-audit-2026-08-23.md`; most findings below are fixed
> (the component rebuild landed the shell everywhere). Remaining work is
> queued as ten family-scoped conform tasks. Keep this file for the cluster
> definitions and history.

> **TARGET UPDATED (read this first).** These findings were written against the
> older *docked* shell (left dock with Layers|Library tabs, a top options bar with
> a left tool strip). That shell is **superseded**. The real shipping app is lean
> and canvas-first, and the shell is now the **scalable dock system**:
> `.win.tall.cq` › `.edit.lean` › `.cnv` (canvas + floating `.tbar` tool bar +
> `.cnv-act` panel toggle + `.sheet.down` overlays) › `.splitter.v` › `.pdock` of
> stacked collapsible/scrollable `.dgrp` groups › `.drail`, with
> `.transport`/`.timeline` only when the document has time.
>
> **Use the *problems* below, but take the *fix target* from:**
> `shared/PRODUCT-MODEL.md` §4b, `shared/UX-PATTERNS.md` v1.1 §1/§3,
> `shared/AGENTS.md` "App shell", and `pages/app-shell.html` (the exemplar).
> Anywhere a fix says "left dock" or "options bar tool strip", read it as
> "right-dock `.dgrp` group" and "floating `.tbar`" instead.

Source: 7 disjoint audit passes against UX-PATTERNS D1-D6 + PRODUCT-MODEL. ~180
raw findings collapse into 7 recurring patterns. **Fix centrally (shared DS / the
app shell), then conform pages — never copy per page.**

**Clean pages (conform reference):** app-shell.html, ds-modes.html,
lang-resize.html, lang-spacing.html.

---

## Cluster A — Page does not sit in the shared shell (no toolbar/tool strip; bespoke chrome)
Severity: high. The page jumps titlebar → content, or invents its own chrome.
Pages: agent-edit, ui-nested, draw (3 separate windows), composites (Layers docked
on the RIGHT), agent, agent-variations (.vbar), video-motion (.mg-controls),
video-compositing (inert span tools), video-speed, video-transitions, ui-autolayout,
ui-grid, brush-library, img-masking, paint, effects, draw-boolean, dsys, ds-switch,
states/ui-variants (reduced, acceptable but show the header).
Fix: compose `.win.tall` → `.titlebar` → `.toolbar`(D4 tool strip + command
surface + ⌘K) → `.edit`(left dock / canvas / Inspector) → timeline, mirroring
app-shell.html. Reduced is fine; relocated/invented is not (D5).

## Cluster B — Missing command surface + ⌘K in the toolbar (D3/D6)
Severity: med (very common). ⌘K is often mis-bound to an "Ask Agent" pill.
Pages: redline, editor, image, img-bg-remove, img-retouch-wt, img-masking,
brush-editor, draw, capture-wt, paint, states, ui-variants, ui-autolayout, ui-grid,
video, video-audio, video-captions, video-transitions, lang-frame, agent.
Fix: shell toolbar carries `.tool ic-more` command surface + `.cmdk` "Search or run
a command ⌘K", distinct from the agent. Central: bake into the shell so adopters
inherit it.

## Cluster C — Left dock missing Layers|Library `.dnav` tabs (Library unreachable) (D2)
Severity: high on editors that live on imported content.
Pages: editor, image, img-bg-remove, img-retouch-wt, img-grade-wt, img-masking,
draw, brush-editor, states, ui-variants, ui-autolayout, ui-grid, agent, video-*
(no left dock at all), lang-panels (taxonomy omits Library).
Fix: left dock = `.dnav` (Layers | Library) + Library body (`.seg` scope Media·
Components·Styles·Systems + `.libtools` + `.libgrid`/`.libtile`), per app-shell.

## Cluster D — Media pool / catalog / library built as a bespoke widget (D1/D2)
Severity: high. The single biggest coherence break.
Pages: video-create-wt (.bin), video (.bin), components (.libshell), brush-library
(full-window widget), ds-build-wt (.wgrid-lib), ui-build-screen (floating .spanel),
dsys (bespoke 3-col catalog), video-transitions (.tlib), draw/brush-editor
(.presets in Layers), ds-switch (.dss-pick), video-compositing (no media pool).
Fix: render as the docked Library panel with shared `.libgrid`/`.libtile` at the
right scope; the "media pool" is Library scope=Media (D1). Kill the bespoke widget.

## Cluster E — Selection not routed to the right-dock Inspector (§4 / D5)
Severity: med-high. Properties shown in floating panels or as text only.
Pages: agent-generate-wt (.miniinsp), component-configure-wt (.section cards),
composites (.alpanel/.miniinsp), vector-wt (.vinsp), ui-build-screen (.spanel),
walk (.miniinsp), video-speed (.scfoot), video (kfSelLbl text only), video-audio,
editor (no canvas .sel-ring), effects/paint (Inspector with nothing selected),
agent-edit, ds-build-wt, img-retouch-wt.
Fix: selection drives `.pane.insp`; show it in three places (canvas `.sel-ring` +
`.lrow.sel` + Inspector). Move floating property panels into the right dock.

## Cluster F — Bespoke chrome / one-off controls instead of shared classes (coherence)
Severity: med.
- One-off buttons: `.obtn` (lang-overlays, language, lang-color), `.pill`/`.pill.solid`
  for title-bar actions (dsys, typography, lang-frame, lang-panels), `.iconbtn`
  (lang-frame), ad-hoc `.tfadd` (dsys). Fix → `.btn` variants / `.btn.icon`.
- Inert `<span class="tool">` (no states): video-compositing, typography, video-speed.
  Fix → `<button class="tool">`.
- Bespoke selection rings / timelines / inspectors: documents (.mring), export-share
  (.hoel), ui-grid (.gc-el.sel), video-captions (.captl), video-speed (.clipz),
  video-transitions (.ttl), walk (.vmini), ui-nested (.insp2), lang-elevation
  (hand-rolled titlebar). Fix → shared `.sel-ring`/`.handle`/`.mtag`, `.timeline`,
  `.pane.insp` primitives.

## Cluster G — Icon near-misses (small tail)
- ic-component reused for boolean/combine: draw-boolean, vector-wt → needs a
  boolean/union glyph (add to library).
- flip H/V both ic-transition: lang-toolbars → ic-flip-horizontal/vertical.
- transition marker ic-x: video, video-create-wt → ic-transition.
- transport skip rotated ic-play: video → ic-skip-back/ic-skip-forward.
- image.html tools: lasso=ic-pen, heal=ic-wand, clone=ic-swatch, patch=ic-component
  → ic-lasso/ic-heal/ic-clone + a non-component patch glyph.
- Back button rotated ic-chevron-right: video-animate-wt, video-transitions,
  img-grade-wt, ui-build-screen → ic-chevron-left.
- eyedropper=ic-sliders (vector-wt), swap=ic-redo (draw-boolean), row/col=ic-move/
  ic-layers (ui-autolayout), dodge/burn=ic-circle (img-retouch-wt) → add proper
  glyphs (eyedropper, swap, flow-h/v, dodge-burn).
- ascii-as-icon: foundations `.farrow →`, agent `+` add, states `!` status,
  typography/lang-toolbars `B`/`I`/`L`/`C`/`R`, "Get Photonz →" CTAs → `.ic-*`.
- Missing glyphs to add: boolean/union, eyedropper, swap, flow-horizontal/vertical,
  dodge-burn, bold, italic, patch (or reuse), skip already exists.

## Copy tail
- foundations capitalizes "Agent" (→ lowercase "the agent"); img-grade-wt says "AI"
  (→ "agent"); lang-keyboard do/don't label "Not" vs lang-spacing "No" (standardize);
  V key bound to "Move" vs "Select" inconsistency (→ Select everywhere).
