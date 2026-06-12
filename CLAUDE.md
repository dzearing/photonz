# Photonz — repo rules

Photonz is a native macOS (arm64, macOS 26+) photo/screenshot editor. SwiftUI shell, Core Image/Metal rendering, pure-Swift document model. It must feel like a built-in macOS app: Liquid Glass surfaces, fluid animations, zero jank.

## Session startup — read these first, nothing else

1. `docs/plan/overview.json` — phase list and statuses. Find the phase marked `in_progress`.
2. `docs/plan/phase-N.json` — only the active phase file(s). Do NOT read other phase files unless the task requires it.
3. `docs/design/overview.md` — one-page architecture summary. Deeper design docs exist per area; read only what the task touches.

## Plan maintenance protocol (every iteration)

- When you start a task: set its status to `in_progress` in the phase file.
- When you finish a task: set `done`, fill in `notes` with anything a future session needs (gotchas, decisions, file locations).
- When a phase completes: set it `done` in both the phase file and `overview.json`, and set the next phase `in_progress`.
- Append a dated entry to `docs/progress/log.md` at the end of every working session: what changed, what's next, any open questions.
- If scope changes, edit the plan files — the plan is the source of truth, not chat history.

## Quality bar — non-negotiable

- **TDD**: write or update tests BEFORE implementation for all `PhotonzCore` and `PhotonzRender` work. UI work in `Sources/Photonz` is exempt from test-first but logic must be pushed down into testable core modules.
- `Scripts/test.sh` must pass before every commit. Never commit with failing or skipped tests.
- `PhotonzCore` must stay pure: no AppKit/SwiftUI/CoreImage imports. CoreGraphics types only. Everything Sendable, value-typed, Codable.
- No force unwraps in `Sources/PhotonzCore` or `Sources/PhotonzRender` (tests and scripts are fine).
- Swift 6 strict concurrency must stay clean — no `@preconcurrency` band-aids without a comment explaining why.
- Performance is a feature: renderer changes need a perf note in the PR/commit description if they touch the composite path. Target: <16ms re-render for a 12-megapixel document with 10 layers.

## Build & test commands

| Action | Command |
| --- | --- |
| Run tests | `Scripts/test.sh` (wrapper handles CommandLineTools quirks; plain `swift test` only works with full Xcode) |
| Debug build | `swift build` |
| App bundle | `Scripts/build-app.sh` → `dist/Photonz.app` |
| App + DMG | `Scripts/build-app.sh --dmg` |
| Run the app | `open dist/Photonz.app` |
| Regenerate icon | `swift Scripts/make-icon.swift` (only when intentionally changing it) |

## Architecture invariants

- Pixel data NEVER lives in the document model. Documents hold `ImageRef`s; bitmaps live in `ImageStore` (PhotonzRender).
- Document model coordinates are top-left origin. `DocumentRenderer` owns the flip to Core Image's bottom-left.
- All document mutation goes through `History.perform` so undo/redo stays correct.
- Layer styling (blur, shadow, border, corner radius, opacity) is non-destructive — applied at render time, never baked into pixels.

## Releases

Use the `release` skill (`.claude/skills/release/SKILL.md`). Never hand-roll a release: the skill keeps VERSION, CHANGELOG, `site/version.json`, the git tag, and the GitHub release in lockstep.
