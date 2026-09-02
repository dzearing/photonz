---
name: run-app
description: Build and run the Photonz menu-bar agent (fast debug binary or signed bundle) and verify features. Use when asked to run, launch, start, or debug the app, or to see a change working in the real app.
---

# Run Photonz

Photonz is a **resident menu-bar agent**, not a window-first app. At launch it
calls `NSApp.setActivationPolicy(.accessory)`, so there is **no Dock icon and no
window** — it lives as the camera-viewfinder icon in the menu bar. Capture,
history, the Quick Access Overlay, and pinned windows all spawn from there.
"Nothing appeared" after launch is the *expected* state; check the menu bar.

## Whose app is it? Read this before you build a bundle

Three bundles can be on this machine at once, and they are NOT interchangeable:

| Bundle | Who it belongs to | Rebuild it? |
| --- | --- | --- |
| `dist/Photonz Dev.app` | **a person**, working in the app | only when they ask |
| `dist/Photonz Probe.app` | the unmanned task loop | freely, all day |
| `dist/Photonz.app` | the shipping build | release pipeline only |

**If you are an unmanned runner, "Photonz Dev.app" is not yours.** Rebuilding it
quits the session out from under whoever is using it, and because macOS
re-authorizes any screen-capture client whose binary changed, it also re-prompts
them for Screen Recording. Use the probe (option C below).
`Scripts/build-app.sh` refuses to rebuild the dev bundle while
`queue/playtest.lock` exists, but nothing can stop a hand-written
`pkill -f "Photonz Dev"`, so simply never write one.

## Three ways to run — pick by what you're verifying

### A. Fast debug binary — `.build/debug/Photonz`
For iterating on behavior and for **headless verification** (logs go to your
terminal).

```bash
swift build && .build/debug/Photonz
```

- Runs the same menu-bar agent (activation policy is set in code, not the
  bundle), windowless, `print`/`NSLog` stream to your terminal.
- **Caveat:** no Info.plist, so `CFBundleShortVersionString` is nil and
  `UpdateChecker.currentVersion` falls back to `0.0.0` — *Check for Updates*
  will always say "update available". Use the bundle (B) to test version logic.
- Runs in the foreground forever; launch with `run_in_background: true` (or
  append `&`) and redirect to a log if you need to keep working:
  `swift build && .build/debug/Photonz > /tmp/photonz.log 2>&1 &`

### B. Signed app bundle — `dist/Photonz Dev.app`
For the real thing: stamped version, `LSUIElement`, self-signed, Finder/TCC
integration. Local builds produce the **dev variant** — bundle id
`com.dzearing.photonz.dev`, display name "Photonz (Dev)" — so it holds its own
TCC grants/defaults and runs side by side with an installed release Photonz.app.
(`--dmg` or `CODESIGN_IDENTITY` switch to release naming — see build-app.sh.)

```bash
Scripts/build-app.sh
open "dist/Photonz Dev.app"
```

- `CFBundleShortVersionString` = the `VERSION` file. (Background update checks
  are OFF for dev bundles by design — `AppInfo.isDevBuild`.)
- Output does **not** go to your terminal (launched via `open`).

Kill stale instances first so you're testing the new build. Match only the
bundle you own, so a running release app — or somebody's dev session — is left
alone:
```bash
pkill -f "Photonz Dev.app/Contents/MacOS"   # ONLY if this dev app is yours
pkill -f ".build/debug/Photonz"
```

### C. Probe bundle — `dist/Photonz Probe.app`
**This is the one an unmanned runner uses.** Same app, its own bundle id
(`com.dzearing.photonz.probe`), its own permissions, defaults and menu-bar entry
("Photonz (Probe)"), so building and relaunching it disturbs nobody.

```bash
Scripts/probe-app.sh                 # build + launch
Scripts/probe-app.sh some/shot.png   # ...and open a file in it
Scripts/probe-app.sh --no-build      # relaunch what's already built
Scripts/probe-app.sh --quit          # quit it when you're done
```

- Quits only its own processes (matched on `Photonz Probe.app/Contents/MacOS`),
  waits for the agent to come up, and prints its pid.
- Quit it when you finish, so nobody is left with a second viewfinder icon.
- It does not export the `.photonz` document type, so a throwaway build can
  never win the default-handler race for somebody's files.
- Its Screen Recording grant resets whenever its binary changes (that is the
  cost of a bundle that is rebuilt constantly). Capture-dependent checks still
  need a human; everything else works.
- To drive it from a script instead of by hand (open a file, press keys,
  click, drag, render the window offscreen, read the editor's state back):
  `Scripts/playtest.sh <walk.json>`. Only the probe acts on a script. Format
  and example: `docs/design/playtest-harness.md`,
  `Scripts/playtest/redline-walk.json`.

## Confirm it's actually running (as an agent)

```bash
lsappinfo info -only ApplicationType `lsappinfo find "LSDisplayName=Photonz (Dev)"`
# => "ApplicationType"="UIElement"   (menu-bar agent, no Dock icon)
pgrep -lf "Photonz"
```

## Driving it — what needs a human / permissions

This is a native AppKit/SwiftUI GUI; most flows are **not drivable headlessly**
on a machine without these TCC grants:

- **Screen Recording** — required for any capture (⌘⇧4 / ⌘⇧3 / menu Capture).
  Without it, captures no-op and the overlay shows a permission hint.
- **Accessibility** — required for the global Carbon hotkeys to fire, and for
  driving the UI via `osascript`/System Events (`-25211` error = not granted).
- macOS's own Screenshot shortcuts swallow ⌘⇧3/⌘⇧4 until disabled in System
  Settings → Keyboard → Keyboard Shortcuts → Screenshots. The **menu items work
  regardless**.

So hand interactive verification to the user: menu-bar dropdown clicks, the
capture → Quick Access Overlay → Pin flow, slide/auto-close feel, drag-out,
pinned-window drag/opacity. Tell them which to check and what to expect.

## Headless verification trick (env-guarded self-test)

When you must prove wiring/placement without the permissions above, add a
temporary, `#if DEBUG` + env-guarded hook in `AppCoordinator.start()` that
synthesizes input and `NSLog`s the result, run it via the **debug binary** (A),
grep the log, then **remove the hook**. The window *frame* is available via
`NSApp.windows` / `CGWindowList` without Screen Recording (only pixel capture
needs it). Proven examples (since removed): `PHOTONZ_DEBUG_QUICKACCESS` and
`PHOTONZ_DEBUG_PIN` injected a synthetic capture and logged the panel/window
frame, which was asserted against the computed `QuickAccessLayout` /
`PinnedImageMetrics`. Pattern:

```bash
swift build && PHOTONZ_DEBUG_X=1 .build/debug/Photonz > /tmp/t.log 2>&1 &
sleep 3; grep "X_SELFTEST" /tmp/t.log; pkill -f ".build/debug/Photonz"
```

Prefer pushing the real logic into a `PhotonzCore` type with unit tests; use the
self-test only for the AppKit shell wiring the tests can't reach.

## Quit

`Scripts/probe-app.sh --quit` for the probe. For a dev app that is yours,
`pkill -f "Photonz Dev.app"` (never a bare `pkill -f Photonz` — that also kills
a running release app and every other flavor), or **Quit Photonz (Dev)** in the
menu (⌘Q). Closing the
last editor window does **not** quit — it's a resident agent by design.
