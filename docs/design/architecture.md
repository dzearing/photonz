# Architecture

## Module boundaries

```
┌─────────────────────────────────────────────┐
│ Photonz (SwiftUI/AppKit app)                │
│   AppCoordinator (menu-bar agent, resident) │
│     status item · hotkeys · capture/history │
│     · updater · window registry             │
│   EditorState (per editor window) + EditorView / tools │
└──────────────┬──────────────────────────────┘
               │ owns
┌──────────────▼──────────────┐  ┌────────────────────────┐
│ PhotonzRender               │  │ PhotonzCore            │
│   ImageStore (CGImage pool) │←─│   PhotonzDocument      │
│   DocumentRenderer (CI)     │  │   Layer / LayerStyle   │
└─────────────────────────────┘  │   Geometry / History   │
                                 └────────────────────────┘
```

## Process & window topology

The app is a **resident menu-bar agent**, not a window-first app (see
`capture.md`). `AppCoordinator` is the app-level root (status item, global
hotkeys, capture pipeline + persisted history, updater, window registry) and
stays alive with no windows open. The **editor is per-window**: each editor
window owns its own `EditorState` (today's `AppState`), `History`, `ImageStore`,
and `DocumentRenderer`, so several images edit independently at once. History is
a **global slide-down overlay**, not editor chrome. (Phase 11 migrates from the
phase-9 single-window, in-editor carousel to this model.)

- `PhotonzCore` depends on nothing but CoreGraphics/Foundation. It must compile on any Apple platform and be 100% unit-testable without a GPU.
- `PhotonzRender` depends on `PhotonzCore` + CoreImage. It is testable headlessly (CI runners render via software/Metal fine).
- The app target is the only module allowed to import SwiftUI/AppKit.

## Data flow

1. User action → `AppState.perform { doc in ... }`.
2. `History.perform` snapshots, mutates, dedupes no-ops.
3. `AppState.rerender()` runs `DocumentRenderer.render(document, store:)` → `CGImage`.
4. SwiftUI observes `renderedImage` and repaints.

This is intentionally synchronous and simple for now. The planned evolution (Phase 2):
- Renderer moves off the main actor; renders are coalesced and cancelled (latest-wins).
- The canvas becomes a `CALayer`/Metal-backed view with tiled drawing for large documents; SwiftUI `Image` is only the placeholder implementation.
- Interactive gestures (drag a crop handle) preview via cheap transforms on the last rendered image, committing a real render on gesture end.

## Concurrency model

- `AppState` is `@MainActor`; all model mutation happens there.
- `ImageStore` is lock-protected and `@unchecked Sendable` — registered images are immutable `CGImage`s.
- `DocumentRenderer` holds a `CIContext` (thread-safe per Apple docs); render calls may move to a background executor in Phase 2.
- Everything in `PhotonzCore` is `Sendable` value types — no actors needed.

## Persistence (Phase 6)

- Native format: `.photonz` package — `document.json` (the Codable `PhotonzDocument`) + `images/<uuid>.heic` for each `ImageRef`.
- Export: PNG/JPEG/HEIC via `CGImageDestination` from the rendered composite; clipboard via `NSPasteboard`.
