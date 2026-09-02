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
| App bundle | `Scripts/build-app.sh` → `dist/Photonz Dev.app` (dev variant: own bundle id `….photonz.dev`, coexists with the release app; `--dmg`/`CODESIGN_IDENTITY` produce release-named `dist/Photonz.app`) |
| App + DMG | `Scripts/build-app.sh --dmg` |
| Run the app | `open "dist/Photonz Dev.app"` |
| Run the app *as an agent* | `Scripts/probe-app.sh [file]` → builds and launches `dist/Photonz Probe.app` (`….photonz.probe`). Unmanned runners use this, never the dev app — see below |
| Scripted playtest | `Scripts/playtest.sh <walk.json>` → drives the probe editor from a JSON script (keys, clicks, drags), writes offscreen renders + `log.json`. Probe-only, compiled out of release. See `docs/design/playtest-harness.md`; example: `Scripts/playtest/redline-walk.json` |
| Regenerate icon | `swift Scripts/make-icon.swift` (only when intentionally changing it) |

### Three bundles, three owners

`dist/Photonz Dev.app` belongs to **the person working in the app**;
`dist/Photonz Probe.app` belongs to **the unmanned task loop**;
`dist/Photonz.app` is the shipping build. They carry different bundle ids so
each holds its own permissions, settings and menu-bar identity.

Rebuilding the dev app quits whoever is using it, so `Scripts/build-app.sh`
refuses to rebuild the dev bundle while `queue/playtest.lock` exists (override
for your own session with `PHOTONZ_ALLOW_DEV_BUILD=1`, or delete the lock).
**A task runner never rebuilds the dev app**: automation that needs a running
app uses `Scripts/probe-app.sh`, which never touches the dev bundle.

The one exception is the loop itself, between tasks: after a task lands code
under `Sources/`, `queue/bin/refresh-dev-app.sh` rebuilds the dev bundle and
puts it back as it found it, so the user is never reviewing a stale build
(asked for on 2026-09-02). That is safe because the dev cert is stable, so the
Screen Recording grant survives a rebuild. `PHOTONZ_AUTO_REFRESH=0` turns it
off.

### Dev signing & Screen Recording permission (grant once per machine)

Dev builds are signed with a stable self-signed **"Photonz Dev"** cert so macOS
TCC grants (Screen Recording, etc.) survive rebuilds — grant once, never again.
`Scripts/build-app.sh` **auto-creates this cert on the first dev build** (needs
Homebrew `openssl@3`: `brew install openssl@3`); it lives in the login keychain,
so every worktree on the machine shares it. NEVER ad-hoc sign a dev build — that
changes the code identity each rebuild and re-breaks the grant (symptom: the app
shows as granted/on in System Settings but still can't capture). Per machine you
grant Screen Recording once; a new machine re-creates the cert on first build and
you grant once there. If a grant ever gets wedged after signing changes:
`tccutil reset ScreenCapture com.dzearing.photonz.dev`, relaunch, re-grant.

## Architecture invariants

- Pixel data NEVER lives in the document model. Documents hold `ImageRef`s; bitmaps live in `ImageStore` (PhotonzRender).
- Document model coordinates are top-left origin. `DocumentRenderer` owns the flip to Core Image's bottom-left.
- All document mutation goes through `History.perform` so undo/redo stays correct.
- Layer styling (blur, shadow, border, corner radius, opacity) is non-destructive — applied at render time, never baked into pixels.

## Experiments: releases in one binary

Photonz ships `current` (the default, what everyone gets) and `next` (the
next-generation experience) **in the same app**. The user picks one in the
Experiments window and tunes per-release feature flags there. `legacy` is
reserved for the day Next is promoted. Full design:
`docs/design/experiments.md`.

- A release's own code lives in `Sources/Photonz/Releases/<Release>/`, reached
  through `ReleaseExperience` — the ONE switch over `Release` in the app. Never
  branch on the release anywhere else.
- Everything outside `Releases/` is **shared**. A file only moves into a release
  folder when that release genuinely needs it different: copy it in, prefix the
  type with the release name (`NextEditorView`, since it's one module), and
  point that release's `…Experience` at the copy. See
  `Sources/Photonz/Releases/README.md`.
- Smaller differences belong behind a feature flag
  (`Experiments.shared.isEnabled(…)`), not a forked file.
- **Porting rule, one way only.** EVERY change to Current must reach Next. While
  a file is shared that happens by itself; once Next has forked that file,
  carrying the change across by hand is part of the work, and **a Current change
  is not finished until Next has it**. Nothing in `Next/` is ever back-ported to
  Current — Next reaches users by being promoted (Next becomes Current, today's
  Current becomes Legacy), not by leaking.
- Each release owns its own settings namespace (`experiments.<release>.flags`),
  so editing one never disturbs the other.
- The app names itself after its release: Photonz, Photonz Next, and dev builds
  keep their `(Dev)` on the end.
- Model + flag store live in `PhotonzCore` (pure, Codable, tested). The app layer
  owns `Experiments`, the release folders, the dialog, and the window.

## Task queue & go loop (unmanned progress)

`queue/` at the repo root drives an unmanned build loop: tasks by priority
folder, one-click UX decisions, daily digest + triage, all rendered live on the
design dashboard (http://127.0.0.1:8791, Project section). Start or restore
everything with the `go` skill (`/go`). Full design: `docs/design/dashboard.md`
and `queue/README.md`. Queue mutations go through `queue/bin/queue.mjs`, never
hand-edited status files. Queue-driven app work targets the **next** release
unless a task explicitly says otherwise.

## Releases

Use the `release` skill (`.claude/skills/release/SKILL.md`). Never hand-roll a release: the skill keeps VERSION, CHANGELOG, `site/version.json`, the git tag, and the GitHub release in lockstep.
