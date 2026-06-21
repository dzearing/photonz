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

## Two ways to run — pick by what you're verifying

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

### B. Signed app bundle — `dist/Photonz.app`
For the real thing: stamped version, `LSUIElement`, self-signed, Finder/TCC
integration.

```bash
Scripts/build-app.sh        # add --dmg for a disposable DMG
open dist/Photonz.app
```

- `CFBundleShortVersionString` = the `VERSION` file, so version-dependent
  behavior (Check for Updates) is real.
- Output does **not** go to your terminal (launched via `open`).

Always kill stale instances first so you're testing the new build:
```bash
pkill -f "Photonz.app/Contents/MacOS/Photonz"; pkill -f ".build/debug/Photonz"
```

## Confirm it's actually running (as an agent)

```bash
lsappinfo info -only ApplicationType `lsappinfo find LSDisplayName=Photonz`
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

`pkill -f "Photonz"`, or **Quit Photonz** in the menu (⌘Q). Closing the last
editor window does **not** quit — it's a resident agent by design.
