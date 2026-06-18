# Rendering

## Pipeline

`DocumentRenderer.render(document, store:)` walks layers bottom-to-top:

1. Resolve content → `CIImage`. Image layers wrap a stored `CGImage`; text/annotation/zoom-callout layers rasterize on demand (`TextRasterizer`, `AnnotationRasterizer`, zoom-callout overlay) into a transparent-background image.
2. Apply layer-local crop (stored rect, never destructive).
3. Scale content into `layer.frame`.
4. Apply `LayerStyle`: gaussian blur (clamped-to-extent to avoid edge fade) → corner-radius clip → border (inner stroke) → geometric transform → center-based positioning → **shadow** → opacity (`CIColorMatrix` alpha vector). **Shadow is derived from the layer image's ALPHA silhouette** (a `CIColorMatrix` that tints the existing alpha, then blur + offset), so a diagonal arrow's shadow hugs the actual stroke pixels, NOT its bounding box. The shadow composites *after* positioning, or its expanded extent breaks centering.
5. Translate onto canvas, flipping top-left model coords → Core Image bottom-left. **This flip exists in exactly one place; never add another.**
6. `composited(over:)` accumulation, final `createCGImage` over the canvas extent. The same composite path backs `render`, `renderSprite` (drag float), scaled export, and thumbnails — so styling/shadow behave identically everywhere.

## Coordinate systems

| Space | Origin | Used by |
| --- | --- | --- |
| Model (canvas) | top-left | `PhotonzCore`, all tools, all UI math |
| Core Image | bottom-left | `DocumentRenderer` internals only |
| View | top-left, zoom-scaled | canvas view; converts via `zoom` factor |

## Performance budget

- Re-render after an edit: **< 16 ms** for 12 MP / 10 layers on M1.
- Interactive gestures must not trigger full renders per frame — preview with transforms, render on commit.
- `CIContext` is created once (`cacheIntermediates: true`); never create contexts per frame.
- Future: dirty-rect rendering (only recomposite the union of changed layer frames), `CIRenderDestination` straight into the canvas's Metal drawable.

## Testing approach

Renderer tests build small solid-color `CGImage`s, composite, and assert pixels at known coordinates (see `DocumentRendererTests`). Every new content rasterizer or style effect needs pixel tests with tolerance bands (GPU rounding varies by device — use >240 / <16 style thresholds, not exact equality).
