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
| Run tests | `Scripts/test.sh` (wrapper handles CommandLineTools quirks; plain `swift test` only works with full Xcode). A run that DIES on signal 10 or 11 is almost always a half-rebuilt `.build` rather than a bug: the wrapper says so, throws `.build` away and runs again, and tells you if it dies the same way twice |
| Debug build | `swift build` |
| App bundle | `Scripts/build-app.sh` → `dist/Photonz Dev.app` (dev variant: own bundle id `….photonz.dev`, coexists with the release app; `--release`/`--dmg`/`CODESIGN_IDENTITY` produce release-named `dist/Photonz.app`) |
| App + DMG | `Scripts/build-app.sh --dmg` |
| Run the app | `open "dist/Photonz Dev.app"` |
| Run the app *as an agent* | `Scripts/probe-app.sh [file]` → builds and launches `dist/Photonz Probe.app` (`….photonz.probe`). Unmanned runners use this, never the dev app — see below |
| Full walk sweep | Not yours to run: it is about 560 walks and about 105 minutes, eleven times the 600s ceiling on an agent's background work. `queue/bin/sweep.sh request "<why>"` puts it on the pile; the loop runs the full set at most twice a day (`queue/bin/sweep.sh schedule`). `Scripts/playtest-all.sh --no-build <name-fragment>` runs just the walks you touched, in seconds |
| Where the loop's day went | `queue/bin/loop-day.mjs` (add `--hours 48`): the share of wall clock spent building, sweeping and idle |
| Scripted playtest | `Scripts/playtest.sh <walk.json>` → drives the probe editor from a JSON script (keys, clicks, drags), writes offscreen renders + `log.json`. Probe-only, compiled out of release. See `docs/design/playtest-harness.md`; example: `Scripts/playtest/redline-walk.json` |
| Regenerate icon | `swift Scripts/make-icon.swift` (only when intentionally changing it) |

### How often the whole walk set runs

Asking for a sweep does not start one. Runners ask after every task, and while
every ask started a whole-set run the loop spent most of its life re-running
walks: thirteen runs in twenty four hours on 2026-09-21, 835 minutes of a 1440
minute day, 58 per cent of its wall clock against 41 per cent building
(`queue/bin/loop-day.mjs --hours 24`).

The schedule now:

* **The full set runs at most once every twenty four hours**, so once a day, and
  only when code has landed since the last one. Requests pile up in between and
  the next run serves them all.
* **In between, after any task that lands code, a rotating check**: about ten
  minutes of walks, made of the end-to-end walks every check runs
  (`an-editing-session-walk`: a whole video edit at Next defaults, failing on
  any blank frame while it plays), every walk whose script changed since the
  last check, and the next chunk of the set, carrying on where it stopped. Over
  a day the rotation covers the whole set anyway, in ten minute pieces.
* **A rotating check is not a sweep.** It never closes the standing walk task,
  and fifty walks passing is never the state of five hundred. A walk it finds
  broken is written onto the standing walk task the same day.
* **A change every walk touches can jump the floor**:
  `queue/bin/sweep.sh request --now "<why the whole set, right now>"`.

`queue/bin/sweep.sh schedule` prints this, out of the code that runs it
(`queue/bin/sweep-schedule.mjs`), and `queue/bin/sweep.sh status` says why
nothing is running right now.

### Walks never run under the person's hands

Walks drive the probe, and on 2026-09-26 the user could not even type while the
loop tested. So nothing that drives the probe starts while somebody is using the
Mac, and anything running stops when they come back (`queue/bin/person-at-mac.sh`,
HIDIdleTime): a walk needs a minute with no keyboard or mouse input, the
rotating check five minutes, the whole set fifteen; a walk that sees input quits
the probe and exits 6 (`DEFERRED`, never a failure), and a sweep that sees input
puts itself down and its request goes back on the pile. The whole set runs at
most once a day. `PHOTONZ_IGNORE_PERSON=1` is for a person running a walk by
hand while they watch.

### A locked screen stops names, not the app

A scripted walk finds every control BY NAME, and a locked screen takes that name
away. With the login window up, each control is still on screen at the right
size and still carries its tooltip, and the name SwiftUI hands to AppKit comes
back empty, so step after step reports a control missing that is plainly there.

Nothing else about the app stops. On a locked Mac the app still drags, still
lays out, still animates, and a snapshot step still photographs the window for
real. So a walk that never looks a control up by name RUNS on a locked screen
and its answer counts: about half the set does nothing but click points, drag,
press keys, photograph the window and reach panel controls through the app's own
register of them. `redline-walk` ran all 70 of its steps and wrote fourteen real
pictures of the window on a Mac that had been locked for three days. Those runs
report `lockSafe: true` and every picture they leave carries a label saying it
was taken under a lock, because one thing about it is not what a person at the
machine would see: colours can read dimmed. A tutorial card was a second cost
until 2026-09-22, and is not any more: a guide a walk is driving keeps its card
up however buried the window is, and a walk that finds the card missing stops
rather than photographing the window without it. Which step kinds survive and
which do not is
`Sources/PhotonzCore/PlaytestLockSafety.swift`, one list, unit tested.

A walk that DOES look a control up by name is a different matter: it **does not
pass and does not fail**. It reports `status: "locked"`, naming the step that
needs a name and how many of its pictures forcing it would still get, and
`Scripts/playtest.sh` exits 3. `Scripts/playtest-all.sh` carries on to the rest
of the walks and counts the refusals separately.

So a sweep on a locked Mac is a **partial sweep**: it runs the walks a lock
cannot touch, records what they found, files any walk that failed in them, and
says in numbers how much of the set that was and how much was refused. It is
never allowed to read as the state of the walk set, and the request for a full
sweep stays pending until the screen is unlocked. While the screen stays locked
the loop runs that partial at most once per commit, so it does not spend forty
minutes between every pair of tasks re-checking code it has already covered. Every launch
prints the state on its `Grants:` line (`· screen locked`).

Nothing tries to unlock the Mac, and nothing can: a Mac already locked stays
locked until a person logs in. What the loop does do is stop the NEXT lock. It
takes one power assertion when it starts and holds it until it stops, gaps
between sweeps included, so a Mac that is unlocked when the loop starts is still
unlocked in the morning. The `Grants:` line says when that hold is on
(`· the loop is holding this Mac awake`). Until 2026-09-21 only a sweep held it,
for the length of that sweep, and the Mac locked itself in a gap between two of
them and cost 163 of 544 walks on every sweep afterwards. See
`queue/bin/go-loop.sh` (hold_awake) and `queue/bin/awake-drill.sh`.

This is not theoretical. The Mac locked at 2026-09-14 20:46:47 and the sweep at
00:09 reported 115 of 400 walks broken, including all 31 tutorial walks, on
source that had passed every one of them that afternoon. Runners were then sent
to hunt bugs that were not in the app. See
`Sources/Photonz/Playtest/PlaytestScreenState.swift`.

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

## The intake window

The session the user reviews the app from is an INTAKE window, not a place to
write app code: they say what is wrong, you file one queue task per thing and
answer their question in a few sentences. The whole contract is
`.claude/skills/intake/SKILL.md` (`/intake`); the short version is that every
task the user asks for is `p1-high` with `source: user` and a low `seq`, and the
go loop does the building. Infrastructure the loop runs on (`queue/`,
`.claude/skills/`, this file, the loop's scripts and prompts) is still yours to
change directly.

## Releases

Use the `release` skill (`.claude/skills/release/SKILL.md`). Never hand-roll a release: the skill keeps VERSION, CHANGELOG, `site/version.json`, the git tag, and the GitHub release in lockstep.
