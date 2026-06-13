# Post-1.0 backlog

Triaged after the 1.0.0 release (2026-06-12). This is a candidate list, not committed
scope — pull items into a new numbered phase in `overview.json` when you decide to do them.
Ordered roughly by priority.

## P0 — release-pipeline blockers (surfaced during the 1.0.0 release)

- **GitHub Actions billing is failing.** Every workflow run (Release, CI, Deploy site) now
  aborts in ~4s with *"recent account payments have failed or your spending limit needs to be
  increased."* Until this is fixed in GitHub → Settings → Billing & plans:
  - the tag-triggered **Release** workflow can't build/publish (1.0.0 was published manually with
    a locally-built, locally-tested DMG via `gh release create`);
  - **CI** doesn't run on pushes/PRs;
  - the **Deploy site** Pages workflow doesn't run, so `dzearing.github.io/photonz` still serves the
    old `version.json` (0.1.0) and old `index.html` even though `site/` in the repo is current.
  After fixing billing, re-run `gh workflow run site.yml` to deploy the refreshed site, and confirm
  CI is green again.

- **Public download link is broken because the repo is private.** The marketing site's
  "Download for Mac" button points at `releases/latest/download/Photonz.dmg`, but a private repo's
  release assets 404 for anonymous users (verified: both v0.1.0 and v1.0.0 assets 404 without auth;
  the v1.0.0 asset is reachable with a token). Options:
  1. make the repo public (simplest; fits the site's "free & open source" copy);
  2. keep the repo private and host the DMG on a public bucket / release mirror, and point the site
     and `release` skill at that URL instead.

## P1 — distribution hardening

- **Developer ID signing + notarization.** `release.yml` already has the conditional steps and
  documents the six required secrets (`APPLE_SIGNING_IDENTITY`, `APPLE_CERTIFICATE_P12`,
  `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`); `gh secret list`
  shows none are configured, so builds ship ad-hoc-signed and Gatekeeper warns on first launch.
  Configuring these flips `HAVE_SIGNING` on and lets us drop the "right-click → Open" notice from
  the site and CHANGELOG.

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
