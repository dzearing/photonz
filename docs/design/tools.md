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

## Zoom callout (Phase 5) — signature feature

Select a box → magnified copy placed nearby with leader lines back to the source.
- `Geometry.zoomCalloutPlacement` picks the quadrant with the most free space, clamps on-canvas.
- `Geometry.leaderLines` connects the two nearest corner pairs.
- Rendered as a `ZoomCalloutContent` layer: source region re-rendered at `magnification`, styled with border + shadow + corner radius; source box gets a matching outline.
- Stays live: if the underlying pixels change, the callout re-renders (it references the canvas region, not a baked copy).
