# Progress log

Append-only. Newest entry on top. One entry per working session: what changed, what's next, open questions.

## 2026-06-12 — Phase 0: project bootstrap

- Created the SwiftPM project (PhotonzCore / PhotonzRender / Photonz app), 29 tests green.
- Core model: `PhotonzDocument`, `Layer`/`LayerStyle`, `Geometry` (crop/resize/skew/zoom-callout math), snapshot `History`.
- Renderer: `ImageStore` + `DocumentRenderer` (Core Image over Metal) with pixel tests.
- App shell: glass toolbar (`.glassEffect`), open/drop image, zoom controls, undo/redo. Verified `dist/Photonz.app` launches.
- Toolchain gotcha: machine has CommandLineTools only (no Xcode). `swift test` needs explicit Testing.framework search paths — encoded in `Scripts/test.sh`. CI uses full Xcode so plain `swift test` works there.
- Infra: CI/release/site workflows, marketing site, release skill, plan + design docs, CLAUDE.md rules.
- **Next**: Phase 1 — layer transforms, style rendering (corner radius/border/shadow), text + annotation rasterizers. TDD: pixel tests first.
