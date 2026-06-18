# Layers

## Model

`Layer`: id, name, `LayerContent` (image | text | annotation | zoomCallout), `frame` (canvas coords), optional `crop` (layer-local), `LayerStyle`, `isVisible`, `isLocked`. Index 0 = bottom.

`LayerStyle` (all non-destructive, render-time):
- `opacity` 0–1 (drives "fade in/out" — animatable in UI)
- `blurRadius` — gaussian, clamped extent so edges stay solid
- `cornerRadius`, `borderWidth`/`borderColorHex`, `shadow` (radius/offset/color/opacity)

## Promote selection to layer

`PhotonzDocument.promoteRegionToLayer(region:rasterized:name:)` — the caller (app) rasterizes the selected canvas region via the renderer, registers it in `ImageStore`, and the model stacks the new image layer directly on top, clamped to canvas.

This enables the signature blur-behind workflow:
1. Select region → promote to layer.
2. Blur the new layer (`style.blurRadius`).
3. Promote the same region again, crop the copy (`layer.crop`), leave it sharp on top.
Result: blurred background with a sharp focal cutout, fully non-destructive.

## Layers panel UI (Phase 6, redesign planned Phase 10.5)

- Right-side glass panel: thumbnails, visibility eye, lock, opacity slider, drag-reorder.
- Double-click name to rename; context menu: duplicate, delete, merge down, rasterize style.
- **`LayerInspector`** below the list for the selected layer — opacity, blur, corner radius, border (+color), and **shadow**: enable toggle then Blur, Color, **Distance** (offset magnitude), **Direction** (offset angle 0–360°, derived from `ShadowStyle.offset` via distance+angle), Opacity. Every slider drag previews via `previewLayerStyle` and commits to `History` on release (one undo step per gesture).
- **`AnnotationInspector`** (Phase 10) shows above `LayerInspector` when the selected layer is an annotation: per-object Color / Thickness / Head Size (arrow only). See `tools.md`.
- **PLANNED redesign (Phase 10.5):** convert this floating overlay into a *docked, full-height* right side panel with a 1px draggable resize handle on its left edge (persisted width), and make the inner sections (Layers list, Annotation properties, Effects, Shadow, …) **drag-reorderable collapsible sections** (Photoshop-style, elegant/modern; persist order + collapsed state). Also tracked as Phase 10 perf item 10.7: layer *selection* must be instant (no re-render / thumbnail regen on select), and bug 10.6: enabling Shadow currently shows nothing.

## Shadow model note

`ShadowStyle` stores `offset` as a `CGSize` (model top-left space). The renderer flips y into Core Image's bottom-left space and derives the shadow from the layer's **alpha silhouette** (so an arrow's shadow hugs the stroke, not its bounding box — see `rendering.md`).

The inspector exposes **five independent knobs** — these are distinct concepts, don't conflate them:
- **Blur** (`radius`) — softness of the edge.
- **Size** (`spread`, Phase 10.6 — to add) — how big the shadow *shape* is vs the object. Implemented by dilating the alpha silhouette (`CIMorphologyMaximum`, radius = spread; negative = erode via `CIMorphologyMinimum`) BEFORE the blur. Default 0.
- **Distance** (offset magnitude) — how far the shadow is pushed off the object.
- **Direction** (offset angle 0–360°) — which way it's pushed. Distance+Direction are the polar form of `offset`: `offset = (cos θ · d, sin θ · d)`.
- **Color** + **Opacity**.
