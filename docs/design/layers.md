# Layers

## Model

`Layer`: id, name, `LayerContent` (image | text | annotation | zoomCallout | measure), `frame` (canvas coords), optional `crop` (layer-local), `LayerTransform`, `LayerStyle`, `isVisible`, `isLocked`. Index 0 = bottom.

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

## Marquee multi-select & batch ops (Phase 16.8, 2026-07-03)

- The select-tool marquee doubles as rubber-band layer selection: every
  visible, unlocked layer whose transformed bounds sit **fully inside** the
  committed rect joins `EditorState.multiSelectedLayerIDs` (fully-inside, not
  intersecting — a long arrow crossing the sweep isn't grabbed). Exactly one
  captured layer promotes to the primary `selectedLayerID` instead.
- REAL state, not derived from the rect: hiding a member would fail a
  containment re-query (invisible layers never match) and silently drop it.
  Any primary-selection change dissolves the multi-selection (`didSet`).
- Panel rows highlight via `isLayerSelected`; **eye / lock / delete on a member
  apply to the whole selection in one undo step** (lock also dissolves it).
  Canvas draws dotted outlines (live during the drag) and ⌫ batch-deletes via
  `Document.removeLayers(ids:)`. Core query: `Document.layerIDs(fullyInside:)`.
- ⌘C with no layer selected copies the marquee region (or whole canvas)
  flattened from the composite — as a Photonz image-layer payload (⌘V lands a
  layer) plus a plain PNG for other apps.

## Layer commands (Photoshop shortcuts, 2026-07-03)

Layer menu + per-row context menu share: **New Layer via Copy ⌘J** (promotes
the marquee if present, else duplicates), Duplicate ⌘D, **Merge Down ⌘E**
(Export moved to ⇧⌘E), Bring to Front **⌘⇧]** / Forward **⌘]** / Backward
**⌘[** / to Back **⌘⇧[**, Delete ⌘⌫; the context menu adds Rename/Hide/Lock
and acts on the clicked row. Details:

- **Merge Down** composites ONLY the participants (selected layer + the one
  below, or the whole multi-selection) over transparency — temp document →
  `DocumentRenderer.rasterize(region:)`, region = transformed bounds ∪ style
  `previewPadding`, clamped to canvas — into one image layer taking the bottom
  participant's slot/name/lock. Merging into the locked Background works and
  stays locked; participants must be visible; one undo step. Caveat: a merged
  zoom callout bakes against only its co-participants, not the full backdrop.
- **Restacking** floors at the locked Background — nothing slides beneath it;
  locked layers don't move.

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
- **Size** (`spread`) — how big the shadow *shape* is vs the object. Implemented by dilating the alpha silhouette (`CIMorphologyMaximum`, radius = spread; negative = erode via `CIMorphologyMinimum`) BEFORE the blur. Default 0. The UI slider is **0…80** (2026-07-03): the model still accepts negative (erode) values and old documents render unchanged, but the control no longer offers them — "negative size" read as nonsense.
- **Distance** (offset magnitude) — how far the shadow is pushed off the object.
- **Direction** (offset angle 0–360°) — which way it's pushed. Distance+Direction are the polar form of `offset`: `offset = (cos θ · d, sin θ · d)`.
- **Color** + **Opacity**.
