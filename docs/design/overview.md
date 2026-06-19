# Photonz — design overview

One page. Read this every session; read the per-area docs only when working in that area.

## What it is

A native macOS photo/screenshot editor optimized for *speed of editing*: crop, resize, skew, annotate (arrows, rectangles, highlights, text), zoom callouts, and Photoshop-style layers with non-destructive effects. arm64 / macOS 26+ only. It should feel like Apple shipped it with the OS.

It runs as a **resident menu-bar agent** (CleanShot-style): always available to capture a screenshot or recording, with a **global slide-down history overlay**, and an **on-demand, multi-window editor** (one window per image). Capture and history are app-level — not editor chrome. See `capture.md`.

## Stack

- **Swift 6 / SwiftUI** app shell with macOS 26 Liquid Glass (`.glassEffect`) surfaces.
- **Core Image over Metal** for compositing and effects (GPU path everywhere).
- **SwiftPM only** — no Xcode project. `Scripts/build-app.sh` assembles the `.app`.

## Module map

| Module | Role | Rules |
| --- | --- | --- |
| `PhotonzCore` | Document model: layers, geometry, history. | Pure values. CoreGraphics types only. 100% testable. |
| `PhotonzRender` | `ImageStore` (bitmaps) + `DocumentRenderer` (CIImage compositor). | No UI imports. Pixel-tested. |
| `Photonz` (app) | SwiftUI/AppKit shell: menu-bar `AppCoordinator`, per-window `EditorState`/`EditorView`, capture + history overlay, tools. | Thin; logic pushed down into core. |

## Key decisions (and why)

1. **Bitmaps outside the model.** Documents hold `ImageRef`s; `ImageStore` holds `CGImage`s. Keeps documents value-typed, Sendable, Codable, and makes snapshot undo O(model) not O(pixels).
2. **Snapshot undo** (`History`). Documents are tiny without pixels, so whole-document snapshots beat command-pattern complexity.
3. **Non-destructive styling.** `LayerStyle` (opacity/blur/shadow/border/corner radius) is applied at render time. Crop on a layer is a stored rect, not a pixel edit.
4. **Top-left model coordinates.** Matches UI thinking; `DocumentRenderer` flips to Core Image's bottom-left in exactly one place.
5. **No Xcode project.** CommandLineTools + SPM builds everything; CI uses the same path. `Scripts/test.sh` adds the framework search paths swift-testing needs under CLT.

## Per-area design docs

- `architecture.md` — module boundaries, data flow, concurrency model, process/window topology.
- `capture.md` — menu-bar agent, global hotkeys, slide-down history overlay, multi-window editor & edit round-trip.
- `rendering.md` — compositor pipeline, coordinate systems, perf budget.
- `tools.md` — crop/resize/skew, annotations, text, zoom-callout interactions.
- `layers.md` — layer model, promote-to-layer, effects semantics.
- `release.md` — versioning, CI, release pipeline, website.

## Repo workflow

Plan lives in `docs/plan/` (overview + per-phase JSON). Progress journal in `docs/progress/log.md`. Rules in `CLAUDE.md`. Releases via the `release` skill.
