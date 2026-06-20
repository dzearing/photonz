# Capture, menu-bar agent & history overlay

How Photonz captures the screen and surfaces results. Read this when working on
the menu-bar agent, global hotkeys, the history overlay, or the multi-window
editor lifecycle. Target architecture (CleanShot-style); supersedes the
phase-9 in-editor history carousel.

## The shift (why this doc exists)

Phase 9 shipped capture as a *feature of the editor window*: ⌘⇧3/⌘⇧4 captured
into a carousel (`HistoryPanel`) that lived inside `EditorView`, toggled by
`capture.isHistoryVisible`. That couples "I want to grab a screenshot" to "an
editor window must be open," which is wrong for a tool you reach for dozens of
times a day.

The target model inverts it: **the resident process is a menu-bar agent**, and
the editor is just one of several on-demand windows it can spawn. History is a
**global overlay**, not editor chrome. This matches CleanShot X (see
`docs/plan/competitive-cleanshot.md`).

## Process & window topology

```
┌──────────────────────────────────────────────────────────────┐
│ Menu-bar agent (resident, LSUIElement / .accessory)          │
│   AppCoordinator (@MainActor, @Observable)                   │
│     • NSStatusItem + menu                                     │
│     • HotkeyCenter (global Carbon hotkeys)                    │
│     • CaptureCenter  → CaptureStore (history, persisted)      │
│     • Updater (check vs site/version.json)                    │
│     • spawns / focuses windows ▼                              │
└───────┬───────────────────────┬──────────────────────┬───────┘
        │ slides down            │ on capture            │ edit
┌───────▼─────────┐   ┌──────────▼──────────┐   ┌───────▼────────────┐
│ History overlay │   │ Quick Access Overlay│   │ Editor window(s)   │
│ (top-screen,    │   │ (corner thumbnail,  │   │ one per document;  │
│  borderless     │   │  post-capture)      │   │ each owns its own  │
│  NSPanel)       │   │  (phase 11.5)       │   │ EditorState        │
└─────────────────┘   └─────────────────────┘   └────────────────────┘
```

- **Resident agent, no required main window.** The app runs as a menu-bar /
  status-item agent (`LSUIElement` or `NSApplication.setActivationPolicy(.accessory)`)
  and stays alive with zero windows open. The user can **Quit** from the menu;
  closing the last editor window does NOT quit the app.
- **`AppCoordinator`** (new) is the app-level root: owns the status item, global
  hotkeys, the capture pipeline, the history store, the updater, and the window
  registry. It replaces the notion of one app-wide `AppState`.
- **Editor windows are per-document.** Each editor window owns its own editor
  state (today's `AppState`, renamed conceptually to per-window `EditorState`),
  its own `History`, `ImageStore`, and `DocumentRenderer`. Multiple editor
  windows edit different images simultaneously and independently.
- **Windowing = SwiftUI `WindowGroup`** *(decided)*. The editor is a
  value-based `WindowGroup(for: CaptureID.self)` (plus a file-backed variant for
  opened images). `openWindow(value:)` with a capture's id **reuses the existing
  window** for that id — giving "focus the existing window editing this image"
  for free — and opens a fresh one otherwise. `AppCoordinator` still tracks the
  open set for the menu/registry, but SwiftUI owns window lifecycle.

## Status-item menu

The `NSStatusItem` menu is the always-available entry point:

- **Capture Region** (⌘⇧4)
- **Capture Full Screen** (⌘⇧3)
- **Record Screen / Video…** (phase 12)
- **Open History** (⌘⇧H) — toggles the slide-down overlay
- ──
- **Check for Updates…**
- **Preferences…** (later)
- **About Photonz**
- **Quit Photonz**

(Set is open — anything that belongs in a global capture context can live here.)

## Capture flow

1. Trigger: a global hotkey (`HotkeyCenter`) or a menu item, handled by
   `CaptureCenter` on the resident agent — **no editor window required**.
2. Region capture uses the fullscreen `RectSelectionController` overlay; full
   screen / window / video are their own modes.
3. The result is added to `CaptureStore` (the persisted history) as a new entry.
4. A **Quick Access Overlay** (phase 11.5) shows a corner thumbnail with
   Copy / Save / Edit / drag-out / Delete and an auto-close timeout.
5. Editing routes through the multi-window editor (below).

Screen Recording permission (TCC) is requested user-initiated from the agent;
see `docs/progress/log.md` for the macOS 26 TCC caveats.

## History overlay (replaces the in-editor carousel)

A **global, top-of-screen overlay**, not editor chrome.

- **Presentation.** A borderless, non-activating `NSPanel` pinned to the **top
  edge of the active display**, spanning a comfortable width, Liquid Glass
  styling, above normal windows.
- **Animation.** On show: **slides DOWN from the top edge while fading in.** On
  dismiss: **slides UP and fades out.** Driven by a single spring; the panel is
  removed when the animation completes.
- **Dismiss.** Esc, click-away, re-pressing ⌘⇧H, or selecting an action.
- **Contents.** Newest-first thumbnails (capped by `CaptureHistory`). Per item:
  **Copy**, **Edit** (→ opens/focuses an editor window), drag-the-file-out,
  **Delete**, and (later) Pin-to-screen.
- The phase-9 `HistoryPanel` inside `EditorView` and `capture.isHistoryVisible`
  are removed; `CaptureStore` / `CaptureHistory` are reused unchanged.

## Multi-window editor & the edit round-trip

- **Edit opens a window.** Choosing **Edit** on a history item (or the Quick
  Access Overlay) opens that capture in an **editor window**.
- **Focus, don't duplicate.** If a window is already editing that capture, bring
  it to the front instead of opening a second copy. The `AppCoordinator` keeps a
  registry of `captureID → editor window`.
- **Independent windows.** Other editor windows (different images, or opened
  files) stay open and independent.
- **Round-trip back to history** (phase 11.4): on save/close, an edited capture
  can **Override** the history entry in place or **Save as new** (a derived
  entry). Model changes for replace/derive live in `CaptureStore`/core and are
  TDD'd; the prompt is app-side.

## Updater

**Check for Updates…** uses a **lightweight custom check** *(decided — no
Sparkle)*: compare the running `VERSION` against the published
`site/version.json` (the release pipeline keeps it in lockstep — see
`release.md`) and, if newer, offer to download the DMG from the GitHub release.
The version comparator is a testable core type; fetch/UI is the thin shell.

## What stays testable

Capture/history/updater **logic** stays in core/store types with unit tests:
`CaptureStore` (add/dedupe/cap/persist, override-vs-derive), the version
comparator, and any geometry for overlay placement. The `NSStatusItem`,
`NSPanel` animation, and window management are the thin AppKit/SwiftUI shell.

## Decided

- **Windowing:** SwiftUI `WindowGroup(for: EditorWindowID.self)` — value-based
  reuse gives focus-existing for free (see *Process & window topology*).
  `EditorWindowID` is an enum `{ capture(UUID) | file(URL) | fresh(UUID) |
  clipboard(UUID) }` — one window group covers captures, opened files, new and
  clipboard documents (rather than two parallel groups). NOTE: a value-typed
  `WindowGroup` still force-opens one window at launch, so the editor group
  carries `.defaultLaunchBehavior(.suppressed)` to start as a pure agent.
- **Menu-bar item:** SwiftUI **`MenuBarExtra`**, not a raw `NSStatusItem`
  (phase 11.1). Same UX, and its always-rendered label captures
  `@Environment(\.openWindow)` at launch so the windowless agent can spawn
  editor windows (the `.menu`-style content is built lazily and can't).
- **App split (phase 11.1, done):** `AppState` → per-window **`EditorState`**
  (document/history/render/viewport/tools) + resident **`AppCoordinator`**
  (`@MainActor @Observable`) owning `CaptureCenter` (capture + global hotkeys +
  `CaptureStore`) and the window-open intents. Agent lifecycle via an
  `AppDelegate`: `.accessory` activation policy + `applicationShouldTerminate-
  AfterLastWindowClosed = false`; the bundle adds `LSUIElement`. Menu commands
  target the focused window through `@FocusedValue(\.editorState)`.
- **Updater:** lightweight custom `version.json` check, no Sparkle.

## Open questions

- Where Preferences live and what they cover (hotkeys, capture defaults,
  history cap, overlay timeout).
