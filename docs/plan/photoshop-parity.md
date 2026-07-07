# Photoshop parity — gap audit & spec

Audit of Photonz (end of phase 17.6, 2026-07-06) against the core Photoshop editing
vocabulary: selections, layers, paint/retouch, transforms, grids/guides. Compiled from a
full code sweep of `Sources/` + `docs/plan/` plus three user-reported problems from a
real editing session. Like `competitive-cleanshot.md`, this is a feature map + spec —
pull items into numbered phases in `overview.json` when committing to them.

Companion docs: `docs/design/tools.md`, `docs/design/layers.md`, `docs/design/rendering.md`.

## 0. Reported bugs & discoverability failures (fix before feature work)

These came from a user session that "felt buggy." **None are reproduced yet** — the
hypotheses below are from code reading only. Each needs a repro (manual or pixel test)
before a fix is claimed.

### 0.1 "I don't know how to marquee-select the content of a layer"

**Not a missing feature — a discoverability failure.** Rect marquee (`Tool.rectSelect`),
ellipse marquee (`Tool.ellipseSelect`), and magic wand (`Tool.wand`) are fully built
(phase 17), with ⇧ add / ⌥ subtract / ⇧⌥ intersect, ⌘D deselect, ⇧⌘I invert, region
fill/erase/⌘J promote. A Photoshop user still couldn't find them. Gaps to close:

- **Cmd-click layer thumbnail → select layer content** (the specific Photoshop gesture
  the user reached for) does not exist. Spec: Cmd-click in `LayersPanel` builds a
  `SelectionRegion` from the layer's visual bounds (or alpha contour via `ContourTracer`
  for image layers). Small, high leverage.
- **Select All (⌘A)** has no menu item/shortcut (phase 17.6 open TODO).
- Selection tools have unresolved keyboard shortcuts (phase 17.6 TODO: M/⇧M/W vs taken keys).
- No first-run affordance pointing at the selection tools (the phase 17 welcome
  walkthrough should cover them).

### 0.2 Fill produced "weird blurred edges"

Unreproduced. Code-level hypotheses (medium confidence), in likelihood order:

1. **Raster-then-scale softening**: annotation fills rasterize via CGContext with default
   antialiasing (`AnnotationRasterizer.swift:15-18`), then the raster is scaled into the
   layer frame (`DocumentRenderer.swift:382-384`). If raster size ≠ frame size, the AA
   edge pixels get interpolated → visible blur.
2. **Layer style leakage**: `LayerStyle.blurRadius` or `cornerRadius` clip
   (`DocumentRenderer.swift:387-413`) applied to a filled layer softens edges after the
   crisp fill.

**Repro recipe**: draw a rectangle annotation, fill (G) with a saturated color, inspect
edges at 100% and 400% zoom; repeat after resizing the layer; repeat with a region fill
(marquee + bucket) on an image layer. Compare against a pixel test using
`RegionOps.filled()` / `AnnotationRasterizer` output directly to isolate model vs
composite. Fix should land with a pixel test in `PhotonzRenderTests`.

### 0.3 Rotate left residue on canvas after the layer was deleted

Unreproduced; all 670 tests pass, including `IncrementalRenderTests` stale-pixel
coverage — so this escapes the existing oracle. Hypotheses (high confidence the bug is
in incremental invalidation, lower on the exact mechanism):

1. **Dirty-region under-coverage for rotated layers**: `RenderDiff.visualBounds()`
   (`RenderDiff.swift:21-33`) computes the rotated AABB via `CGRect.applying()`; the
   incremental patch (`DocumentRenderer.swift:140-212`, coordinate flip at ~189) re-renders
   exactly that rect. Any mismatch vs the pixels actually drawn in earlier frames
   (AA bleed, blur/shadow padding interaction with rotation, float rounding, rect not
   snapped outward to integral pixels) leaves a fringe.
2. **Multi-step interaction**: rotation applied, then a later small-delta edit computes a
   dirty region from the *new* state only; the old rotated extent never re-enters the
   dirty union.
3. **Chrome, not canvas**: stale selection-chrome/handles drawn by `CanvasView` outside
   the document composite (would exonerate the renderer).

**Repro recipe**: solid background + rectangle layer → rotate ~30–45° → delete layer →
inspect corners of the old AABB. Vary: with/without shadow+blur styles, after an
intervening small edit, and force a cold `render()` after the residue appears (if a cold
render clears it, it's incremental invalidation; if not, it's caching or chrome). Encode
the failing case as an `IncrementalRenderTests` oracle test ("rotated layer deleted
leaves no stale pixels").

**Backstop regardless of root cause**: pad/outset dirty rects to integral pixel bounds
(+1–2px AA margin) after transform math, and add a rotation-angle sweep to the
incremental-vs-cold-render oracle tests.

## 1. Gap matrix

Legend: ✅ built · 🟡 partial · ❌ missing. Pointers are to `Sources/`.

| Photoshop staple | Status | Notes |
| --- | --- | --- |
| Rect/ellipse marquee | ✅ | `Tool.rectSelect/.ellipseSelect`, `PhotonzCore/SelectionRegion.swift` |
| Magic wand | ✅ | `Tool.wand`, `PhotonzRender/FloodFill.swift` + `ContourTracer` (contiguous only) |
| Lasso (freehand) | ❌ | no freehand path selection |
| Polygonal lasso | ❌ | no click-to-build-path selection |
| Edge-aware/smart selection | 🟡 | EdgeMap Sobel snapping assists marquee corners (`EdgeMap.swift`, `EdgeSnapping.swift`); no "select subject"/magnetic lasso |
| Select layer content (⌘-click thumb) | ❌ | §0.1 |
| Select All / feather | ❌ | ⌘A missing (deselect/invert exist); no feathering anywhere |
| Layer blend modes | 🟡 | normal/multiply/screen only (`Layer.swift:153`) |
| Layer masks | ❌ | no mask model; per-layer crop is the workaround |
| Clipping masks | ❌ | — |
| Layer groups/folders | ❌ | flat array in `Document.swift` |
| Adjustment layers | ❌ | per-layer styles only |
| Merge/flatten | 🟡 | ⌘E merge down exists; no flatten-all |
| Brush / pencil (freehand paint) | ❌ | pencil deferred to phase 14 |
| Eraser | 🟡 | region erase only (`RegionOps.erased()`); no brush eraser |
| Paint bucket / fill | ✅ | `Tool.fill` + region fill (`Fill.swift`, `RegionOps.swift`); no opacity/tolerance on fill |
| Gradients | ❌ | solid colors only |
| Clone stamp / healing | ❌ | not in plan |
| Eyedropper / color picker | ✅ | phase 13; recent-colors MRU, no saved swatches |
| Move/scale/rotate/skew/flip/crop | ✅ | non-destructive (`LayerTransform`, `Crop`) |
| Free transform (unified) | ❌ | rotate + skew are separate chrome gestures |
| Rulers | ❌ | measure tool covers ad-hoc measurement |
| Grid + snap-to-grid | ❌ | no grid at all |
| User guides | ❌ | built then dropped (phase 16.6, preserved on `wip/16.6-alignment-guides`) |
| Align/distribute layers | ❌ | canvas-edge snap only (`Snapping.swift`) |
| Snap to object/smart guides | 🟡 | EdgeMap snaps to *image content* edges; no layer-to-layer snapping |

Already strong (no action): text layers, shape annotations, zoom callouts, measure,
collage, history/undo, export, capture/recording — see `competitive-cleanshot.md`.

## 2. Feature specs (proposed phases)

Ordered by (user pain × leverage ÷ size). Sizes: S ≤1 session, M = 1–3, L = 3+.

### P0 — Refinement pass (bugs + discoverability) — size M
The "feels buggy" impression outweighs any single missing feature.
- Reproduce + fix §0.2 fill edges and §0.3 rotate residue, each with a pixel test.
- Dirty-rect integral-outset backstop + rotation sweep tests.
- ⌘A Select All; ⌘-click layer thumbnail → select content; selection shortcuts TODO;
  selection tools in the welcome walkthrough.

### P1 — Selection completeness — size M
All build on the existing `SelectionRegion` (CGPath + booleans) — no new model needed.
- **Lasso** (`Tool.lasso`): freehand drag → smoothed closed CGPath. Reuses marching
  ants, combine modes, RegionOps for free.
- **Polygonal lasso**: click-to-add vertices, double-click/Esc to close. Shares the
  lasso builder.
- **Feathering**: `SelectionRegion.feather: CGFloat`; render-side Gaussian on the region
  mask when filling/erasing/extracting (`RegionOps`). Also fixes "fill edge" control:
  crisp by default, soft on request.
- **Global color select** ("select all pixels of this color", wand minus contiguity):
  flood-fill variant over the whole bitmap; same tolerance slider.
- Defer: magnetic lasso / select-subject (EdgeMap could power it later; spike first).

### P2 — Layer power: masks, modes, groups — size L
- **Layer masks**: `Layer.mask: ImageRef?` (grayscale), applied in the compositor after
  content raster, before style. "Add mask from selection" is the creation path
  (selection → `ContourTracer`/bitmap mask). Editing masks needs brushes (P3) — ship
  creation/apply/enable-disable first, Photoshop-style thumbnail in `LayersPanel`.
- **Blend modes**: extend the enum — overlay, soft light, darken, lighten, difference,
  color, luminosity (all direct `CIBlendKernel`/`composited(over:)` mappings). Cheap;
  gate the picker UI on layer type only where meaningless.
- **Layer groups**: the one real *model* change — flat `[Layer]` → tree (group node with
  its own opacity/visibility/lock; render = composite subtree then style). Touches
  Document mutations, RenderDiff, LayersPanel drag-reorder, multi-select. Do it in one
  dedicated phase; do not piggyback.
- Flatten-all (trivial once merge-down exists) + merge-visible.

### P3 — Paint: brush engine, gradients, stamps — size L
One shared **brush engine** (pressure-less v1: stamped circular dab, spacing, hardness,
size; destructive into a bakeable image layer via `RegionOps`-style compositing):
- **Brush + brush eraser** (paint color / clear).
- **Mask painting** (paints into `Layer.mask` — completes P2 masks).
- **Clone stamp** (⌥-click source anchor, offset-copy dabs). Healing deferred.
- **Gradient tool**: linear + radial, FG→BG and FG→transparent, drag defines the ramp
  (`CILinearGradient`/`CIRadialGradient`); respects active selection. Independent of the
  brush engine — can ship first as an S-size slice.

### P4 — Grid, guides, alignment — size M
- **Grid definitions**: document-level `GridSpec` (spacing, subdivisions, color) persisted
  in `.photonz`; canvas overlay; snap-to-grid in `Snapping.swift` alongside canvas-edge
  snap. View ▸ Show Grid / Snap to Grid toggles.
- **Layer-to-layer smart guides**: extend `Snapping.swift` candidates with other layers'
  edges/centers (the dropped 16.6 work on `wip/16.6-alignment-guides` is a starting
  point — revisit with snap-lines-during-drag UX rather than persistent guides, which is
  what the user rejected).
- **Align/distribute** menu for multi-selected layers (pure `Geometry.swift` math). S-size.
- Rulers: defer; measure tool + grid cover most needs.

### Explicitly deferred (unchanged from backlog)
Adjustment layers, healing brush, vector shape layers, free-transform unification,
curved arrows/step counter/redaction (phase 14 already owns these).

## 3. Sequencing note

P0 is the answer to "the app isn't quite refined" — do it before any feature phase.
P1 and the P3 gradient slice are the best effort-to-visible-payoff items. P2 groups is
the only structural risk in this doc (model tree change) — isolate it. Every core change
follows the TDD mandate in `CLAUDE.md`; render changes need pixel tests with the
cold-render oracle.
