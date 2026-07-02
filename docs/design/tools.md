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

`AnnotationContent`: arrow, rectangle, highlight, ellipse, line. Stroke width, color, start/end points in layer-local coords, plus `arrowheadScale` (arrow-only size multiplier) and `cornerRadius` (rectangle-only).
- **Tool stickiness (one-shot by default):** drawing tools commit one shape, then revert to `.select` and select the new shape so it can be tweaked immediately (`EditorState.toolLocked == false`). **Double-clicking** a toolbar tool sets `toolLocked` (a white inner ring marks it) so it stays active for repeated drawing until the tool changes. `setTool(_:locked:)` / `lockTool`.
- **Rectangle corner radius:** `cornerRadius` rounds the rectangle's *own stroke* — `AnnotationRasterizer` strokes a `CGPath(roundedRect:)` (clamped to a capsule) — rather than relying on the layer-level `LayerStyle.cornerRadius`, whose rounded mask would clip the sharp stroke corners away (the "rectangle borders disappear when rounded" bug). Edited via a "Corner Radius" slider in the `AnnotationInspector` (rectangles only).
- **Arrows (Phase 10 redesign):** bold proportioned head via `Geometry.arrowhead(…, scale:)`; head size is driven by `arrowheadScale` (a user-facing multiplier). Per Phase 10.4 it must be made **independent of stroke width** so the thickness control doesn't grow the head, and the default scale is **1.0**. `Geometry.arrowShaftEnd` stops the shaft *inside* the head so the round line cap never pokes past the sharp tip (used by both the rasterizer and the live `CanvasView` preview). `Geometry.arrowheadHalfWidth` stays in lockstep with the wing math so frame render-padding can't drift. CURVED-arrow variant + tail flair + arrow style set are **deferred to Phase 14**.
- Highlight: multiply-blended translucent fill.
- Rendered by a CoreGraphics rasterizer in `PhotonzRender` (pixel-tested), then composited like any image layer.
- **Styling & per-object editing:** `AnnotationStyles` holds the defaults new annotations get (color, stroke width, `arrowheadScale`) and persists to UserDefaults. Two surfaces edit annotations: the toolbar **style popover** (color swatches + Width/Arrowhead sliders) sets defaults / restyles the selected one, and the Layers-panel **AnnotationInspector** gives per-object Color / Thickness / Head Size. Both preview live via `EditorState.previewAnnotationRestyle` (no history) and commit one undo step on release via `setAnnotationStrokeWidth` / `setAnnotationArrowheadScale`. (`AppState` was split into per-window `EditorState` + resident `AppCoordinator` in Phase 11.1 — see `capture.md`.) Endpoint-drag/resize remap goes through `AnnotationBuilder.restyled`/`updating`/`resized`.

## Text (Phase 3)

`TextContent`: string, font name, size, weight, color. Rasterized via CoreText (`TextRasterizer` also measures `naturalSize` and picks the family face nearest a `TextWeight`). Interaction: text tool click places an inline `NSTextView` editor on the canvas (zoom-scaled to match the final render); click-away commits a layer whose frame hugs the measured text, Esc cancels, double-click re-edits in place (the layer hides under the editor). Style popover gains font/size/weight menus for the text tool; current style persists via `TextStyles` in UserDefaults.

**Phase 13 text fixes (the "very buggy text" round):**
- **Font resolution:** "SF Pro"/"SF Mono" aren't matchable by family name (CoreText silently returns Helvetica), so `TextRasterizer.font(for:)` special-cases them via `CTFontCreateUIFontForLanguage(.system / .userFixedPitch)` + a weight-trait descriptor copy. "New York" was dropped (only reachable via AppKit's design API, which the render layer can't import) → "Baskerville". Resolved faces are memoized per `(family,weight)` to avoid a `fontd` XPC stall under parallel load.
- **Wrap + min width:** the inline editor box **hugs the typed text** (no longer spans to the canvas edge), wrapping at 60% of the canvas with an 80pt floor (`TextRasterizer.minimumTextWidth`, `naturalSize(maxWidth:minWidth:)`). Live editor and commit share `CanvasNSView.textWrapWidth`.
- **Resize = WIDTH-only re-wrap:** text now `allowsFrameResize` (`resizeWidthOnly`) — reverses the old 3.5 "text never frame-resizes" decision. Dragging a handle sets the wrap width and the text **re-wraps** (height auto-follows; no glyph stretch — text is excluded from the drag sprite). Holds under rotation via `Handles.anchoredFrame`, which keeps the corner opposite the dragged handle fixed in *screen* space (a plain resize swings it — the "resize after rotate is broken" bug).
- **Border outlines the GLYPHS, not the box:** a border on a text layer strokes the letter outlines (two-pass: fat border-colored glyphs underneath + normal fill on top → an OUTER outline that grows outward, fill intact). `DocumentRenderer` suppresses the box border for text; the glyph border is threaded into the raster cache key (`variant`).
- **Editing entry/exit:** **Return** on a selected text layer re-edits it (mirrors double-click); **⌘Return** in the editor commits (plain Return is a newline) via the `InlineTextView` subclass.

## Measure / Ruler (Phase 16) — the user's PRIMARY workflow

A designer's redline tool for measuring gaps/sizes on a screenshot and checking alignment. `MeasureContent` (`PhotonzCore/Measure.swift`) is its own `LayerContent.measure` case on the two-endpoint pattern (start/end = the two box corners, layer-local once built); `MeasureBuilder` mirrors `AnnotationBuilder` (layer/updating/resized/restyled). Tool = `.measure` (toolbar "ruler", shortcut **M**, `createsMeasureByDrag`).

- **Two forms (`MeasureForm`)** — the tool defaults to **`bracket`**:
  - **`bracket`** (a squared "U") — drag corner **A → opposite corner B**; the connector + **label sit on the START corner's side** and the U opens toward the end (natural TL→BR drag ⇒ label above for horizontal, left for vertical). `bracketGeometry()` returns the 4-point open path + connector midpoint + outward unit. **The axis NEVER auto-flips from the drag's box shape** (a size-dependent `bracketAxis` auto-detect was shipped and removed 2026-06-29 — "the direction changes depending on the size I drag!"): brackets use the persisted `measureStyle.mode`, **default vertical**; ⇧ flips on create; the inspector Direction toggle changes it (and persists as the new default); invert ⇄ swaps corners to flip the label side.
  - **`line`** — a straight dimension line (+ witness lines in the locked H/V modes), free point-to-point.
- **Measured value** — `rawDistance` (free=hypot, H/V=|dx|/|dy|, i.e. the gap-axis span). `MeasureUnit` **defaults to `pixels`** (raw image px); `points` divides by `PhotonzDocument.pixelScale` (≤0→1 guard). `label(pixelScale:)` = `%.<decimals>f <suffix>`.
- **Stroke width is in LOGICAL pixels**, rendered ×`pixelScale` (`MeasureRasterizer` uses butt caps + miter joins for crisp 1px right-angle corners), so a "1px" sizer line aligns to the image's pixel grid. Default 1; inspector offers 1/2/3px.
- **Rendering** (`PhotonzRender/MeasureRasterizer.swift`): branches on form; the numeric **label** is white CoreText on a rounded plate filled with the measure color — produced via `TextRasterizer` and **blitted** in (drawing CoreText directly into the rasterizer's flipped context renders it upside-down). Cache `variant = "scale:<pixelScale>"` so the points readout invalidates on scale change. The frame reserves `estimatedLabelSize` at `labelCenter(labelSize:)` so the label isn't clipped.
- **Select / move / resize**: a selected measure shows the universal dotted selection box + **round handles on all 4 box corners** (a `line` shows its 2 ends). Dragging any corner updates the right start/end components (diagonal-opposite stays fixed) and the gap/label **update live** (full re-render per move via `previewMeasureEndpoints`; one undo step on release via `commitMeasureEndpoints`; Esc restores). Move works via hit-testing (`Layer.contains` tests the drawn strokes). `MeasureCornerDrag` carries `(xFromEnd, yFromEnd)`.
- **Inspector** (`MeasureInspector`, `InspectorSectionID.measure`): styled to match the Effects panel — small secondary caption **above** each control (`.labelsHidden()` segmented pickers, so labels never wrap vertically); narrow controls (Color) get a left label instead. Rows: Direction (**Horizontal listed first**, brackets only) + invert ⇄ (`invertMeasure` swaps corners → flips the bracket to the other side) · Style (Bracket/Line) · Unit (Pixels/Points) · Thickness (1/2/3px) · Color · Show-label toggle. Defaults live in `EditorState.measureStyle` (in-memory; **not yet persisted**).
- **Open follow-ups**: measureStyle persistence; auto-detect `pixelScale` from the capture's DPI (currently fixed at 1 — the 1×/2× inspector control was removed as confusing); the toolbar S style-popover doesn't cover measures.

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
