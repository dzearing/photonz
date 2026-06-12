# Progress log

Append-only. Newest entry on top. One entry per working session: what changed, what's next, open questions.

## 2026-06-12 — Phase 3.1/3.2: tool state machine + drag-to-create annotations

- **3.1 Tools**: `Tool` enum in `PhotonzCore/Tools.swift` with `annotationShape` mapping and `defaultAnnotation` smart defaults (red #FF3B30 strokes, yellow #FFD60A highlight — front-loads part of 3.6). `AppState.activeTool` + `setTool` (clears marquee/layer selection on entering a drawing tool); sticky annotation tools, Esc reverts to select. Toolbar: select/arrow/line/rect/ellipse/highlight with V/A/L/R/O/H shortcuts and accent-circle active state; crop/text/zoom-callout disabled placeholders.
- **3.2 Drag-to-create**: `AnnotationDrag` (⇧ = 45° snap for line/arrow, square for box shapes — shape-aware, a flat ⇧-rect can't collapse) + `AnnotationBuilder` (frame = bbox + `renderPadding`; `Geometry.arrowheadHalfWidth` shared with the rasterizer so wing padding can't drift). Canvas draws the in-flight drag as CAShapeLayers (fill-only arrowhead sublayer; multiply filter for highlight), and **holds the preview after commit until a different composite CGImage arrives** so the ~50ms async re-render never shows a flash.
- 157 tests green (16 new core tests). Canvas behavior verified with an ad-hoc headless harness (compiles `CanvasView.swift` against the built module .o files, synthesizes NSEvent drags, pixel-asserts previews/commits, PNGs reviewed): 32 checks incl. Esc cancel, sticky tool, marquee regression, click-creates-nothing.
- **Known gap for 3.5**: resizing an annotation layer via handles doesn't remap `start`/`end` — the drawing distorts/clips. 3.5 must scale endpoints with the frame.
- **Next**: 3.3 style popover (color/stroke width on the selected annotation) or 3.4 text blocks.

## 2026-06-12 — Phase 2 complete: marquee, layer select/move/resize, drag preview pipeline

- **2.3 Marquee**: `MarqueeDrag` (core, 13 tests) — standardize/⇧-square/canvas-clamp, zoom-aware click detection, `Geometry.pixelAligned` commits. Marching ants = white CAShapeLayer under animated black dashes; selection lives in AppState (doc coords), survives zoom/pan, Esc/click clears.
- **2.4 Hit-test + move**: `Layer.contains` (inverts the render transform), top-down `Document.hitTest` skipping invisible/locked, `Snapping` to canvas edges/center with 8 *screen*-pt tolerance (11 tests). **Background layer is now born locked** so clicking it marquees. Pointer-modal interaction: hit → select+move, miss → marquee. One undo step per drag; Esc cancels via no-op commit.
- **2.5 Handles**: `Handles` (core, 14 tests) — 8 handles, 6 screen-pt hit tolerance beating layer hit-test, resize anchors the opposite corner/edge, never inverts (1×1 clamp), ⇧ = uniform corner scale / cross-axis edge scale. No resize cursors yet (needs tracking areas; phase-7 polish note).
- **2.6 Drag preview**: drag start kicks off async underlay (`render(hiding:)`) + padded sprite (`renderSprite`, `LayerStyle.previewPadding`) renders; canvas then floats the sprite as a CALayer (blend via compositingFilter) so mouse moves cost zero Core Image work. Falls back to full submits until ready; preview clears only after the post-commit frame lands (no flash-back).
- 141 tests green. App-side behavior verified with the headless NSEvent + CALayer.render harness from 2.1 (synthesized mouse drags, pixel asserts, PNGs reviewed). Note: `CALayer.render(in:)` output is vertically flipped — account for it when sampling.
- **Next**: Phase 3 (annotations & text tools). The toolbar buttons in EditorView are still inert placeholders; phase 3 wires them. Known preview approximations (documented in plan 2.6 notes): resize stretches the sprite bitmap until commit.

## 2026-06-12 — Phase 2.1/2.2 (canvas + zoom/pan) and phase 9 (screenshot capture, user request)

- **Canvas**: `Viewport` (PhotonzCore, 10 tests) owns all camera math — fit-never-upscales, zoom-to-cursor, per-axis clamping, center-preserving resize. `CanvasNSView` is a flipped layer-backed NSView that mirrors `Viewport` into a CALayer (nearest-neighbor ≥2×); gestures (scroll pan, pinch zoom, smart-magnify toggle) apply locally then notify AppState. View menu: ⌘= ⌘- ⌘0 ⌘1.
- **Screenshot capture (new phase-9, preempts phase-2 remainder)**: ⌘⇧4 rectangle grab (multi-screen dim overlay, Esc cancels), ⌘⇧3 full-screen (one capture per display), ⌘⇧H history carousel with copy/edit per capture. Carbon global hotkeys + Capture menu; PNGs persist in App Support (capped 50, `CaptureHistory` core model, 6 tests).
- 97 tests green. App-side pieces verified headlessly (CALayer.render pixel harness, synthesized scroll events, CaptureStore round-trip, hotkey registration status) — this machine lacks Screen Recording permission for screencapture-based visual checks.
- **Needs user verification**: grant Screen Recording to Photonz.app on first capture; disable system Screenshots shortcuts for global ⌘⇧3/⌘⇧4 to reach Photonz. In-app Capture menu works regardless.
- **Next**: user-verify capture flow, then phase 2 remainder (2.3 marquee selection, 2.4 hit-testing/drag, 2.5 handles, 2.6 gesture preview pipeline).

## 2026-06-12 — Phase 1 complete: model & render engine hardening

- All 7 tasks done, TDD throughout; 81 tests green (was 29).
- New core types: `LayerTransform` (rotation/skew/flip, top-left-space angles, composed flip→skew→rotation), `RGBA` hex parser, `BlendMode` (normal/multiply/screen), `Geometry.arrowhead`.
- Renderer pipeline now: crop → scale → blur → corner-radius clip → border → transform → center-based position → shadow → opacity, with per-layer blend modes. Key gotcha: model angles must be negated for CI's y-up space, and shadows composite after positioning or their extent breaks centering.
- New rasterizers: `TextRasterizer` (CoreText framesetter, no AppKit), `AnnotationRasterizer` (arrow/rect/ellipse/line/highlight; highlight multiplies at composite time).
- Async rendering: `RenderScheduler` actor with latest-wins coalescing; AppState API unchanged, frames delivered back to MainActor, stale frames dropped on document close.
- Perf baseline recorded in `docs/progress/perf.md`: 45.5ms median for 12MP/10-layer (target 16ms) — optimization is phase 7's job; suspects listed there.
- **Next**: Phase 2 — Metal-backed canvas view, zoom/pan, selection.
- Open question: colored (non-black) shadows darken slightly via the alpha-weighted color matrix; revisit if/when shadow color becomes user-facing.

## 2026-06-12 — Phase 0: project bootstrap

- Created the SwiftPM project (PhotonzCore / PhotonzRender / Photonz app), 29 tests green.
- Core model: `PhotonzDocument`, `Layer`/`LayerStyle`, `Geometry` (crop/resize/skew/zoom-callout math), snapshot `History`.
- Renderer: `ImageStore` + `DocumentRenderer` (Core Image over Metal) with pixel tests.
- App shell: glass toolbar (`.glassEffect`), open/drop image, zoom controls, undo/redo. Verified `dist/Photonz.app` launches.
- Toolchain gotcha: machine has CommandLineTools only (no Xcode). `swift test` needs explicit Testing.framework search paths — encoded in `Scripts/test.sh`. CI uses full Xcode so plain `swift test` works there.
- Infra: CI/release/site workflows, marketing site, release skill, plan + design docs, CLAUDE.md rules.
- **Next**: Phase 1 — layer transforms, style rendering (corner radius/border/shadow), text + annotation rasterizers. TDD: pixel tests first.
