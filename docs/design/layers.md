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

## Layers panel UI (Phase 6)

- Right-side glass panel: thumbnails, visibility eye, lock, opacity slider, drag-reorder.
- Double-click name to rename; context menu: duplicate, delete, merge down, rasterize style.
- Effects inspector below the list for the selected layer (blur, shadow, border, corner radius) with live preview — every slider drag previews via render, commits to `History` on release (one undo step per gesture).
