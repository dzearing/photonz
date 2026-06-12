# Progress log

Append-only. Newest entry on top. One entry per working session: what changed, what's next, open questions.

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
