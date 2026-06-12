# Rendering

## Pipeline

`DocumentRenderer.render(document, store:)` walks layers bottom-to-top:

1. Resolve content → `CIImage` (image layers now; text/annotation/zoom-callout rasterizers land in Phases 3–5).
2. Apply layer-local crop (stored rect, never destructive).
3. Scale content into `layer.frame`.
4. Apply `LayerStyle`: gaussian blur (clamped-to-extent to avoid edge fade), opacity via `CIColorMatrix` alpha vector. Corner radius, border, and shadow rasterization land with Phase 6 styling work.
5. Translate onto canvas, flipping top-left model coords → Core Image bottom-left. **This flip exists in exactly one place; never add another.**
6. `composited(over:)` accumulation, final `createCGImage` over the canvas extent.

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
