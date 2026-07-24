# Caliper redesign — design spec

**Date:** 2026-07-23
**Area:** Measure / Ruler tool (Phase 16)
**Status:** approved (design) — implementation pending

## Goal

Make the **caliper** (the squared-U dimension bracket) the single, primary
measuring interaction, with a more intuitive drag-to-measure flow, a hover
"snap dot," and a more refined look for both the caliper and its label pill.

Two product decisions are fixed and are honored here, not re-litigated:

1. **The caliper IS the measure tool.** Drag → a horizontal or vertical
   caliper, axis chosen from the drag direction. The free-diagonal mode and the
   line-vs-bracket form toggle are dropped entirely; the inspector is simplified
   to match. One opinionated caliper.
2. **The label pill is a live on-canvas overlay with a real Liquid-Glass
   backdrop blur** (not baked into the layer bitmap). Because the pill is no
   longer baked, exported/flattened output must still carry the measurement — so
   a legible pill is baked **for export only**.

## Settled decisions (from brainstorming)

- **Geometry = a 3-point caliper** (confirmed with the user):
  - The **measuring line** (`start`, `end`) is the two **feet** A and B, sitting
    **on the measured space**, constrained to one axis. This is the line that
    snaps to detected edges; its span is the measured value.
  - The **third point is the head** — the closed, perpendicular outer end of the
    U — offset from the feet line by one signed **`headOffset`** scalar (sign =
    side/direction). The **legs point from the head toward the measured space**
    (down to A and B). The **chip/label is centered on the head line** and carries
    a **border**. Because the pill is translucent glass, the **head line is drawn
    only from the two leg tops inward to the chip's edges — with a gap under the
    chip** (a broken dimension line); no stroke is ever visible behind the glass.
    An invert control is redundant — `headOffset`'s sign *is* the direction.
- **Export label look:** a **flat glass-style pill** — neutral translucent fill
  + hairline border + caliper-colored text (the on-canvas glass look minus the
  live blur).
- **Inspector:** keep **Color, Thickness, Unit, Show-label**. Remove Style
  (line/bracket), Direction, and invert.

## Model — `Sources/PhotonzCore/Measure.swift`

Today: `MeasureContent` stores `start`/`end` as **opposite corners of a box**,
plus `MeasureForm {line, bracket}`, `MeasureMode {free, horizontal, vertical}`,
and `MeasureCapStyle {ticks, arrows}`. `bracketGeometry()` derives the squared-U;
the label sits offset *outside* the connector.

New:

- `MeasureMode` collapses to **`{horizontal, vertical}`** (drop `.free`).
- **Delete `MeasureForm` and `MeasureCapStyle`** and every code path that
  branches on them (rasterizer, canvas preview, inspector, builder, state).
- `MeasureContent` fields become: `start`, `end` (the two **feet** on the
  measured space, layer-local), `headOffset: CGFloat` (signed perpendicular
  distance from the feet line to the head/chip bar; sign = side), `mode`,
  `strokeWidth`, `colorHex`, `showLabel`, `unit`, `decimals`.
- **Measured value** = the feet line's axis span: `|end.x − start.x|`
  (horizontal) / `|end.y − start.y|` (vertical). `displayDistance`/`label` are
  unchanged (pixels default; points divide by `pixelScale`, ≤0→1 guard).
- **Geometry** (`geometry()` / a pure static): the feet are leveled onto a single
  cross-axis value; the head bar is the feet line shifted perpendicular by
  `headOffset`. The squared-U path (opening toward the measured space) is
  `footA → headA → headB → footB`, where `head = foot + perp·headOffset`. The
  **label centers on the head bar midpoint** (the outer edge) — not offset beyond
  it. `cornerRadius` on the two head↔leg joins is small (refined, not
  cartoonish).
- **Migration:** `init(from:)` keeps `decodeIfPresent` for the removed keys so
  old payloads still decode; a legacy `.free`/`.line`/4-corner measure is
  coerced to the nearest H/V caliper — feet line = the dominant-axis span,
  `headOffset` = the perpendicular extent (sign toward the old head corner). No
  pixel data, no document breakage. (Beta has ≈no saved measures; this is
  correctness hygiene.)

## Builder — `MeasureBuilder` (same file)

`layer` / `updating` / `resized` / `restyled` keep their shapes but operate on
the new params. The frame bbox must include the **legs and the head label**:
union the feet line bbox, the head bar (feet ± `headOffset` perpendicular), and
the label reservation centered on the head. `restyled` drops `form`/`capStyle`
args.

## Interaction — `Sources/Photonz/CanvasView.swift`

- **Hover snap dot.** While `.measure` is active and idle, a dot follows the
  cursor and magnetizes to the nearest detected edge via the existing
  `EdgeSnapping.snap(...)` over `EditorState.snappingEdgeMap` (per-axis → nearest
  edge intersection). **⌘ bypasses** (free). It marks where a drag will begin.
  Reuses the existing hover/tracking-area path (as `hoverSlot` does) and the
  existing snap source — **no second snapping system**.
- **Drag = the measuring line.** Mouse-down at the snapped dot = `start`. The
  **dominant drag direction** picks H/V. The growing end snaps **along-axis** to
  perpendicular edges (horizontal caliper → vertical edges / x-positions;
  vertical → horizontal edges / y). `headOffset` defaults to a fixed length; its
  **side is inferred from the small cross-axis drift** of the drag (drift up →
  head up, legs point down), flippable afterward. Reuses `measureDrag` +
  `axisGated` motion gating + `refreshMeasurePreview`.
- **Post-creation edit = 3 handles.** Foot A, foot B (kept level), and one
  **head handle** at the head bar's midpoint. Extends `MeasureCornerDrag` /
  `measureCorners()` / `previewMeasureEndpoints` / `commitMeasureEndpoints` to
  carry the head handle alongside the two feet, with the existing edge-snap +
  ⌘-bypass + axis-gating. Foot drags snap along-axis; the head handle changes
  only the offset (distance) and side.

## Visual — caliper + label pill

- **Caliper** (`Sources/PhotonzRender/MeasureRasterizer.swift`): draw the
  squared-U with a small join radius (rounded corners) instead of sharp
  miter/butt. Strokes stay rasterized (logical px × `pixelScale`, pixel-grid
  crisp). Feet get a subtle tick or none (tuned in run-app). When `showLabel` is
  on, the **head segment is split around the chip** — drawn from each leg top
  inward to the chip's edge, leaving a **gap** sized to the chip footprint (+ a
  small margin) so the translucent pill never reveals a stroke behind it. This
  gap is present on **both** the interactive render (pill = live overlay) and the
  baked export render (pill drawn into the gap). With `showLabel` off, the head
  line is continuous.
- **Label pill — live glass overlay hosted in `CanvasNSView`.** An
  `NSHostingView` wrapping a SwiftUI pill (`.glassEffect`, fully rounded,
  **border**, text tinted to the caliper color), **centered on the head line**
  and filling the head-line gap (the rasterized head line stops at the pill's
  edges, so no stroke sits behind the glass), added as a canvas subview and
  positioned every overlay-refresh from the **live** endpoints + viewport
  (create-drag, corner/depth drag, pan, zoom) — one update pass, zero drift. To
  keep the gap ≥ the pill (line never peeks), the pill is sized to the same
  measured chip footprint the rasterizer uses for the gap.
  A `document`-bound SwiftUI overlay is rejected: live drags re-render a preview
  doc without touching the published `document`, so it would lag.
  **Fallback:** if `.glassEffect` won't sample the canvas image layer, use
  `NSVisualEffectView` `.withinWindow` (same frosted look, guaranteed to blur the
  canvas). Verified in run-app.
  - One hosted pill per placed measure (few in practice) + one for the in-flight
    create-drag preview. Hidden when `showLabel` is off.

## Export path — Decision 2's trade-off

The seam is clean: the live canvas renders via `RenderScheduler →
DocumentRenderer.renderInteractive`; export/thumbnails/sprites use a **separate**
`DocumentRenderer.render(...)`. Both funnel through `compositeImage → ciImage →
MeasureRasterizer`.

- Thread **`bakeMeasureLabels: Bool`** through `compositeImage` /
  `ciImage(for:)`, folded into the measure raster cache **variant** so the two
  representations never collide.
- `renderInteractive` (live canvas) and `renderSprite` (drag sprite) →
  **false**: no baked pill; the glass overlay is the only on-screen label, and a
  moving measure sprite carries no stale pill.
- `render(...)` / `render(_:scale:)` (export, thumbnails, region-promote) →
  **true**: `MeasureRasterizer` bakes the **flat glass-style pill** (neutral
  translucent fill + hairline border + caliper-colored text).
- **Result:** on-canvas = live Liquid-Glass pill; every exported/flattened image
  still shows the measurement as a legible on-brand pill. Called out explicitly
  in the PR description.

## Inspector & state — `MeasureInspector`, `EditorState`

- `MeasureInspector`: Color · Thickness (1/2/3px) · Unit (Pixels/Points) ·
  Show-label. Remove Style, Direction, invert. Delete `setMeasureForm`,
  `invertMeasure`, `setMeasureAxis` (axis comes from the drag), and the
  cap-style path.
- `EditorState.measureStyle`: drop `form`/`capStyle`; keep the rest.

## Non-goals / out of scope

- No new snapping system — extend the existing `EdgeMap`/`EdgeSnapping` flow.
- No true backdrop blur baked into a layer bitmap (impossible for an isolated
  layer) — the live pill is an overlay; export gets the flat approximation.
- No unrelated refactoring of the render or canvas code beyond what the model
  change and the `bakeMeasureLabels` flag require.

## Testing (TDD — core/render first, per CLAUDE.md)

Write/update tests **before** implementation for all `PhotonzCore` /
`PhotonzRender` work:

- **Geometry:** feet leveling, `head = foot + perp·headOffset`, squared-U path
  order, label center = head midpoint, rounded-join metrics, `headOffset` sign →
  side.
- **Distance/label:** value = axis span; pixels vs points (`pixelScale` incl.
  ≤0 guard); decimals formatting.
- **Migration:** legacy `.free`/`.line`/4-corner payloads decode and coerce to a
  valid H/V caliper; round-trip stable.
- **Builder:** frame reserves legs + bar label; `updating`/`resized`/`restyled`
  preserve identity/style; endpoints re-localized.
- **Rasterizer:** rounded U present; `bakeMeasureLabels=false` → no pill pixels;
  `bakeMeasureLabels=true` → flat pill (neutral fill + border + colored text)
  present and upright.
- App/UX is verified interactively via the `run-app` skill (feel-heavy change):
  snap dot, drag-to-measure, 3-handle edit, glass pill look, and an **export
  round-trip** proving the label survives.

`Scripts/test.sh` green before any commit. Perf: the composite path changes only
by adding an early-out (no baked label interactively) — a perf note goes in the
PR; target <16ms re-render for a 12MP / 10-layer doc is not regressed.

## Plan-maintenance (per CLAUDE.md)

- Add a task to `docs/plan/phase-16.json` (e.g. `16.12 Caliper redesign`),
  `in_progress` on start, `done` with notes on finish.
- Update `docs/design/tools.md` § Measure to describe the 3-point caliper, the
  live glass pill, and the export bake.
- Append a dated entry to `docs/progress/log.md` at session end.
