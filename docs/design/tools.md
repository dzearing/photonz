# Tools

All tool math lives in `PhotonzCore` (mostly `Geometry`) and is unit-tested. Views only translate gestures into geometry calls.

## Crop

- Marquee drag → `Geometry.clampCrop` (handles negative-size drags and canvas bounds).
- Whole-document crop: `PhotonzDocument.crop(to:)` rebases layer frames, drops layers left fully outside.
- Per-layer crop: `layer.crop` rect, non-destructive, applied at render time.
- UI: rule-of-thirds grid overlay, edge/corner handles, aspect-ratio locks (1:1, 4:3, 16:9, free), ⏎ commits, ⎋ cancels.

## Resize

- `PhotonzDocument.resize(to:)` scales all layer frames via `Geometry.resizeScale`.
- UI: dialog with pixel/percent units, aspect lock, common presets (50%, @1x from @2x screenshot).

## Skew / transform

- `Geometry.skewTransform(xAngle:yAngle:around:)` — affine skew about the layer center.
- Layer transforms compose: scale (from frame) → skew → translate. Stored on the layer in Phase 3 as a `LayerTransform` struct.

## Annotations (Phase 3, arrow redesign Phase 10)

`AnnotationContent`: arrow, rectangle, highlight, ellipse, line. Stroke width, color, start/end points in layer-local coords, plus `arrowheadScale` (arrow-only size multiplier), `cornerRadius` (rectangle-only), and `fillColorHex` (rectangle/ellipse interior fill, nil = outline-only; added 2026-07-03 with a Fill toggle + color well in the inspector — toggling on seeds from the stroke color).
- **Tool stickiness (one-shot by default):** drawing tools commit one shape, then revert to `.select` and select the new shape so it can be tweaked immediately (`EditorState.toolLocked == false`). **Double-clicking** a toolbar tool sets `toolLocked` (a white inner ring marks it) so it stays active for repeated drawing until the tool changes. `setTool(_:locked:)` / `lockTool`.
- **Rectangle corner radius:** `cornerRadius` rounds the rectangle's *own stroke* — `AnnotationRasterizer` strokes a `CGPath(roundedRect:)` (clamped to a capsule) — rather than relying on the layer-level `LayerStyle.cornerRadius`, whose rounded mask would clip the sharp stroke corners away (the "rectangle borders disappear when rounded" bug). Edited via a "Corner Radius" slider in the `AnnotationInspector` (rectangles only). Rectangles stroke with **MITER joins** (2026-07-03): the old round joins made a thick stroke fake a corner radius the inspector read as 0 — radius 0 must be truly sharp; a real `cornerRadius` curves the path itself.
- **Arrows (Phase 10 redesign):** bold proportioned head via `Geometry.arrowhead(…, scale:)`; head size is driven by `arrowheadScale` (a user-facing multiplier). Per Phase 10.4 it must be made **independent of stroke width** so the thickness control doesn't grow the head, and the default scale is **1.0**. `Geometry.arrowShaftEnd` stops the shaft *inside* the head so the round line cap never pokes past the sharp tip (used by both the rasterizer and the live `CanvasView` preview). `Geometry.arrowheadHalfWidth` stays in lockstep with the wing math so frame render-padding can't drift. CURVED-arrow variant + tail flair + arrow style set are **deferred to Phase 14**.
- Highlight: multiply-blended translucent fill.
- Rendered by a CoreGraphics rasterizer in `PhotonzRender` (pixel-tested), then composited like any image layer.
- **Styling & per-object editing:** `AnnotationStyles` holds the per-shape defaults new annotations get — color, stroke width, `arrowheadScale`, `cornerRadius`, and `fillColorHex` — and persists to UserDefaults. EVERY inspector commit writes back to the shape's defaults, so "the next rectangle reuses the last-touched rectangle's settings" holds for all of them (corner radius was missing from `ShapeDefaults` entirely until 2026-07-03 — a user-reported bug). Two surfaces edit annotations: the toolbar **style popover** (color swatches + Width/Arrowhead sliders) sets defaults / restyles the selected one, and the Layers-panel **AnnotationInspector** gives per-object Color / Thickness / Head Size. Both preview live via `EditorState.previewAnnotationRestyle` (no history) and commit one undo step on release via `setAnnotationStrokeWidth` / `setAnnotationArrowheadScale`. (`AppState` was split into per-window `EditorState` + resident `AppCoordinator` in Phase 11.1 — see `capture.md`.) Endpoint-drag/resize remap goes through `AnnotationBuilder.restyled`/`updating`/`resized`.

## Text (Phase 3)

`TextContent`: string, font name, size, weight, color. Rasterized via CoreText (`TextRasterizer` also measures `naturalSize` and picks the family face nearest a `TextWeight`). Interaction: text tool click places an inline `NSTextView` editor on the canvas (zoom-scaled to match the final render); click-away commits a layer whose frame hugs the measured text, Esc cancels, double-click re-edits in place (the layer hides under the editor). Style popover gains font/size/weight menus for the text tool; current style persists via `TextStyles` in UserDefaults.

**Phase 13 text fixes (the "very buggy text" round):**
- **Font resolution:** "SF Pro"/"SF Mono" aren't matchable by family name (CoreText silently returns Helvetica), so `TextRasterizer.font(for:)` special-cases them via `CTFontCreateUIFontForLanguage(.system / .userFixedPitch)` + a weight-trait descriptor copy. "New York" was dropped (only reachable via AppKit's design API, which the render layer can't import) → "Baskerville". Resolved faces are memoized per `(family,weight)` to avoid a `fontd` XPC stall under parallel load.
- **Wrap + min width:** the inline editor box **hugs the typed text** (no longer spans to the canvas edge), wrapping at 60% of the canvas with an 80pt floor (`TextRasterizer.minimumTextWidth`, `naturalSize(maxWidth:minWidth:)`). Live editor and commit share `CanvasNSView.textWrapWidth`.
- **Resize = WIDTH-only re-wrap:** text now `allowsFrameResize` (`resizeWidthOnly`) — reverses the old 3.5 "text never frame-resizes" decision. Dragging a handle sets the wrap width and the text **re-wraps** (height auto-follows; no glyph stretch — text is excluded from the drag sprite). Holds under rotation via `Handles.anchoredFrame`, which keeps the corner opposite the dragged handle fixed in *screen* space (a plain resize swings it — the "resize after rotate is broken" bug).
- **Border outlines the GLYPHS, not the box:** a border on a text layer strokes the letter outlines (two-pass: fat border-colored glyphs underneath + normal fill on top → an OUTER outline that grows outward, fill intact). `DocumentRenderer` suppresses the box border for text; the glyph border is threaded into the raster cache key (`variant`).
- **Editing entry/exit:** **Return** on a selected text layer re-edits it (mirrors double-click); **⌘Return** in the editor commits (plain Return is a newline) via the `InlineTextView` subclass.

## Measure / Ruler (Phase 16, redesigned 16.12) — the user's PRIMARY workflow

A designer's redline tool for measuring gaps/sizes on a screenshot. The
**caliper** (a squared-U dimension bracket) is the single, opinionated measuring
interaction — the old free/diagonal mode and the line-vs-bracket form toggle are
gone. `MeasureContent` (`PhotonzCore/Measure.swift`) is its own
`LayerContent.measure` case; `MeasureBuilder` mirrors `AnnotationBuilder`
(layer/updating/resized/restyled). Tool = `.measure` (toolbar "ruler", shortcut
**i**, `createsMeasureByDrag`). Full design:
`docs/superpowers/specs/2026-07-23-caliper-redesign-design.md`.

- **A 3-point caliper.** `MeasureContent` stores `start`/`end` = the two **feet**
  (the measuring line, on the measured space, leveled to one axis) and
  **`headOffset`** = a signed perpendicular distance to the **head** (the closed
  outer bar carrying the chip). Its sign is the direction, so there is no invert
  control. `MeasureMode` is just `{horizontal, vertical}`. `caliperGeometry()`
  returns the feet, the two head corners, the label anchor (head midpoint), and
  the squared-U `path` (`footA → headA → headB → footB`). The legs point from the
  head toward the measured space.
- **Measured value** — `rawDistance` = the feet line's axis span (`|dx|` / `|dy|`).
  `MeasureUnit` **defaults to `pixels`** (raw image px); `points` divides by
  `PhotonzDocument.pixelScale` (≤0→1 guard). `label(pixelScale:)` =
  `%.<decimals>f <suffix>`.
- **Stroke width is in LOGICAL pixels**, rendered ×`pixelScale`, so a "1px" sizer
  line aligns to the image's pixel grid. Default 1; inspector offers 1/2/3px.
  The two head↔leg joins are **lightly rounded** (round line joins + a small
  `addArc` fillet), refined not cartoonish.
- **The label pill is a LIVE Liquid-Glass overlay, not baked** (Decision 2). On
  the canvas it's a `MeasureLabelView` (`NSVisualEffectView .withinWindow` — a
  real backdrop blur of the composite — hairline border in the caliper color,
  caliper-colored text) hosted **inside `CanvasNSView`** and repositioned every
  overlay refresh from live geometry, so it tracks create/handle/move drags and
  pan/zoom with zero drift; pointer events pass through it. Centered on the head
  line, which is **cut around the chip** (a gap) so the translucent glass never
  reveals a stroke behind it.
- **Export keeps the label** (the trade-off Decision 2 demanded). `bakeMeasureLabels`
  threads through `DocumentRenderer.compositeImage → ciImage` (folded into the
  measure raster cache variant). Interactive (`renderInteractive`), the move-drag
  sprite, and the drag underlay pass **false** (no baked pill — the glass overlay
  is the label); export / `render(scale:)` / thumbnails / region-promote pass
  **true**, and `MeasureRasterizer` bakes a **flat glass-style pill** (neutral
  translucent fill + hairline caliper-color border + caliper-colored text,
  `TextRasterizer` glyphs blitted upright) into the same head-line gap. So
  flattened/exported output still shows the measurement, minus the live blur.
  Perf: the flag is an early-out; interactive re-render stays ~7.5ms (12MP/10L).
- **Interaction — placement** (`MeasurePlacement`): while idle a **hover snap dot**
  magnetizes to the nearest detected edge (⌘ bypasses). The measuring line is drawn
  **either** by click/click (click foot A, move, click foot B) **or** by a single
  **press-drag-release** (down at foot A, drag to foot B, release) — a drag past a
  small tolerance on the first press completes the line. Either way you then land
  in head-placement mode; a final **click** (or drag) sets the **head** (depth +
  direction = the cursor's signed perpendicular offset), completing the caliper.
  The axis is the dominant direction, feet snap along-axis to perpendicular edges,
  ⎋ cancels. On completion the tool **auto-reverts to Select** and selects the new
  caliper (the old sticky measure tool felt inconsistent with other apps).
- **Select / edit = 3 handles** (two feet + head; `MeasureHandleDrag`,
  `measureHandles`): a foot drag moves that end (the line stays level; snaps via
  the existing `EdgeSnapping`/`EdgeMap`, ⌘ bypass), the head drag changes only the
  offset/side (free). Values/label update live (`previewMeasureEndpoints`), one
  undo step on release (`commitMeasureEndpoints`), Esc restores. Move works via
  hit-testing (`Layer.contains` walks the caliper path).
- **Migration**: legacy `line`/`bracket`/`free` payloads decode and coerce to a
  valid H/V caliper (explicit `CodingKeys` keep the removed keys decode-only;
  custom `encode` writes only the caliper keys).
- **Inspector** (`MeasureInspector`): Unit (Pixels/Points) · Thickness (1/2/3px) ·
  **Label size** slider (`labelScale`, live preview via `previewMeasureLabelScale`,
  one undo on release) · Color. (No Show-label toggle — the label is always on.)
  Defaults live in `EditorState.measureStyle` (in-memory).
- **The caliper is image content.** Lines are ACTUAL image pixels (a "1px" caliper
  = 1 image px, not ×pixelScale); the label pill scales with zoom exactly like the
  baked/export pill (sized in image px × zoom), so the live glass pill and the
  head-line gap match at every zoom and the pill border equals the line width.
  Selection shows 3 handle dots (two feet + head); the handle layer is raised
  above the pill so the head dot isn't occluded by its own chip.
- **Open follow-ups**: measureStyle persistence; auto-detect `pixelScale` from the
  capture's DPI (fixed at 1); optionally swap the pill's `NSVisualEffectView` for a
  SwiftUI `.glassEffect` host; tune `labelFontSize`/`defaultHeadOffset`/corner
  radius to taste.

### Edge snapping (16.4–16.5, shipped 2026-07-02) — how the ruler finds UI edges

There is no UI tree in a screenshot; snapping comes from image analysis. The
design went through several user-tested revisions — the final model, and why:

- **The moving line snaps to parallel edges it actually crosses.** `EdgeMap`
  (`PhotonzCore/EdgeMap.swift`) stores block-summed (16px) **directional**
  Sobel fields — |Gy| for horizontal boundaries, |Gx| for vertical (directional
  matters: combined magnitude lets glyph stems smear a text band into noise) —
  and answers **windowed** queries (`horizontalEdges(inXRange:)` /
  `verticalEdges(inYRange:)`) where the window is the dragged ruler line's
  span. Global X/Y projections were tried first and FAILED: a baseline only
  spans its own text run and dilutes to nothing across a full-width image.
- **Acceptance = absolute floor only** (`defaultFloor` 0.12 on windowed mean
  gradient; hard unit edge ≈ 4.0/px). A window-relative threshold was tried
  and REMOVED — it drowned faint hairline borders sharing a window with a
  strong dark→white panel edge (raw ~0.15 vs ~3.4). Noise stays under ~0.08.
- **Luma landings**: `EdgeMap` also stores perceptual (sRGB) luma; each
  `EdgeCandidate` carries `edgeBefore`/`edgeAfter` = the first **visually
  clean background** row/col walking from the gradient peak toward each side
  (residual ≤ 10% of the edge's own contrast). AA glow counts as element;
  sparse descender ink counts as background — the user measures from the
  BASELINE. Hard hairlines land on the peak row itself. Snapping uses the
  pointer-side landing, so a baseline→divider gap reads the number a designer
  expects.
- **Pick is strength-weighted** (`score = strength / (1 + distance/4)`), not
  nearest-wins — a real baseline a few px away beats an antialiasing ghost
  under the pointer; a faint divider still captures when alone.
- **Approach-side filtering**: candidates cluster into "runs" (gap ≤ 40px);
  a run of ≥3 lines only exposes the lines on the pointer's side of its
  midpoint — approaching text from below can snap baseline/box-bottom, never
  the topline.
- **App feel** (`CanvasView` + `EdgeSnapping`): snapping applies to the CREATE
  drag (anchor + growing corner) and corner-resize; **⌘ bypasses**; a decayed
  motion accumulator gates axes (decisive vertical motion suppresses X
  captures — no perpendicular guide bars); tolerance = `max(8pt/zoom, 4px)` so
  high zoom keeps a magnet; captured edges draw a full-span guide via the
  shared `snapGuideLayer`; un-captured axes round to the pixel grid.
- **Analysis cost**: one background pass per image (`EdgeMapAnalyzer`, ~2s
  debug on a 7MP capture), computed off-main in `EditorState` (gated to the
  measure tool / a selected measure), cached per `ImageRef`. Snapping is a
  no-op until the map lands.
- **Gotchas encoded in tests**: `render(toBitmap:)` writes rows TOP-first
  (an added "flip" mirrored every horizontal edge — caught only by an
  asymmetric fixture; symmetric fixtures hid it); calibration fixtures mirror
  measured rows from a real capture.

## Zoom callout (Phase 5) — signature feature

Select a box → magnified copy placed nearby with leader lines back to the source.
- `Geometry.zoomCalloutPlacement` picks the quadrant with the most free space, clamps on-canvas.
- `Geometry.leaderLines` connects the two nearest corner pairs.
- Rendered as a `ZoomCalloutContent` layer: source region re-rendered at `magnification`, styled with border + shadow + corner radius; source box gets a matching outline.
- Stays live: if the underlying pixels change, the callout re-renders (it references the canvas region, not a baked copy).
