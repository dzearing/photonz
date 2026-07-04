# Post-1.0 backlog

Triaged after the 1.0.0 release (2026-06-12). This is a candidate list, not committed
scope — pull items into a new numbered phase in `overview.json` when you decide to do them.
Ordered roughly by priority.

## Resolved (audited 2026-07-03)

- ~~**GitHub Actions billing failing**~~ — RESOLVED. CI runs green on pushes to main
  (verified 2026-07-03; latest push built in ~1m40s).
- ~~**Public download link 404 (private repo)**~~ — RESOLVED. The repo is public now, so
  `releases/latest/download/Photonz.dmg` serves anonymously.
- ~~**Developer ID signing + notarization secrets**~~ — RESOLVED. All six secrets configured
  2026-06-13 (`gh secret list`); v0.2.0 shipped Developer-ID signed (notarization best-effort —
  verify status at the next release before dropping the "right-click → Open" notice).

## P2 — platform reach

- **Windows amd64 evaluation.** The renderer is Core Image/Metal and the shell is SwiftUI/AppKit —
  both Apple-only. A Windows port is effectively a rewrite of `PhotonzRender` (e.g. onto Direct2D/
  Skia/wgpu) and the entire UI shell; only `PhotonzCore` (pure Swift values, CoreGraphics types) is
  portable, and even that needs Swift-on-Windows + a CoreGraphics shim. Verdict: large, separate
  track — scope a spike before committing. Not a near-term phase.

- **Mac App Store distribution.** Would require app sandboxing (the global ⌘⇧3/⌘⇧4 capture hotkeys
  via Carbon and the screencapture flow need entitlement review / rework under the sandbox),
  a provisioning profile, and App Review. Evaluate against the simpler Developer-ID + notarized
  direct-download path already scaffolded above.

## P3 — product nice-to-haves (deferred from earlier phases)

- Resize cursors on selection handles (needs `NSTrackingArea`s; noted in phase 2.5).
- Drag-preview resize stretches the sprite bitmap until commit (phase 2.6 approximation).
- User-facing shadow color for layers (colored shadows currently darken slightly via the
  alpha-weighted color matrix; phase 1 open question).
