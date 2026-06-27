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
4. **Post-capture feedback = the history overlay itself** (revised 2026-06-21).
   On capture/recording complete, the slide-down history overlay is shown with
   the **newest entry highlighted** (accent ring + glow). The earlier corner
   "Quick Access" toast (phase 11.7) was **removed** as redundant: it
   auto-dismissed and wasn't recallable, whereas history is one place and
   ⌘⇧H-recallable. Per-item actions (Copy / Save / Edit / Pin / Delete; for
   videos Play / Save-Export) and drag-out live on the history cells.
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
- **Contents.** Newest-first thumbnails of the **capture folder** (below). A
  **Clear All** header action (moves everything to the Trash, with a confirm).
  Per-item actions are **hidden until the item is hovered** (they're noisy
  otherwise) and each shows a small tooltip **below** the row so it never covers
  the thumbnail: **Copy**, **Edit** / **Pin** (images) or **Play** / **Export
  GIF·HEIC** (videos), **Delete**, plus drag-the-file-out. The newest item is
  ring-highlighted right after a capture.
- The phase-9 `HistoryPanel` inside `EditorView` and `capture.isHistoryVisible`
  are removed.

## Capture storage = a user folder (no private library)

*(Revised 2026-06-21 per user feedback.)* The capture history is backed
**directly by `~/Pictures/Screenshots`** — there is no private Application-Support
library or index. The folder is the single source of truth:

- Every capture/recording is auto-written into it (macOS-style names,
  `Screenshot/Recording yyyy-MM-dd at HH.mm.ss.ext`), so the user never has to
  "Save" — it's already a file in a normal folder.
- History is a **live listing** of the folder's media files (classified by
  extension via the testable `CaptureLibrary`), newest first.
- **Delete in history ⇒ file to Trash; delete the file ⇒ leaves history.** A
  `DispatchSource` folder watcher reloads on external changes, keeping the two in
  sync both ways. Deletes use the Trash (recoverable).
- Thumbnails are cached in memory; video poster frames are generated on demand
  (no poster files written into the user's folder). `CaptureEntry` is now just a
  `{ url, createdAt, kind }` descriptor (identity = URL); the location will become
  a Preference later.

## Multi-window editor & the edit round-trip

- **Edit opens a window.** Choosing **Edit** on a history item (or the Quick
  Access Overlay) opens that capture in an **editor window**.
- **Focus, don't duplicate.** If a window is already editing that capture, bring
  it to the front instead of opening a second copy. The `AppCoordinator` keeps a
  registry of `captureID → editor window`.
- **Independent windows.** Other editor windows (different images, or opened
  files) stay open and independent.
- **Edit = open the file.** Captures are plain files, so Edit just opens
  `EditorWindowID.file(url)` (re-opening the same URL focuses the existing
  window — no separate `.capture` id).
- **Round-trip back to history** (phase 11.5): "Save to Capture History" on a
  file opened from the capture folder offers **Override** (rewrite that file) or
  **Save as new** (a new file in the folder). `CaptureStore.replace(at:)` /
  `add` handle it; the prompt is app-side.

## Updater

**Check for Updates…** uses a **lightweight custom check** *(decided — no
Sparkle)*: compare the running `VERSION` against the published
`site/version.json` (the release pipeline keeps it in lockstep — see
`release.md`) and, if newer, offer to download the DMG from the GitHub release.
The version comparator is a testable core type; fetch/UI is the thin shell.

## What stays testable

Capture/history/updater **logic** stays in core types with unit tests:
`CaptureLibrary` (extension→kind classification, newest-first ordering), the
version comparator, and overlay placement geometry. The folder scan + watcher,
`NSStatusItem`, `NSPanel` animation, and window management are the thin
AppKit/SwiftUI shell (`CaptureStore`).

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
  `AppDelegate`: `applicationShouldTerminateAfterLastWindowClosed = false`; the
  bundle adds `LSUIElement`. Menu commands target the focused window through
  `@FocusedValue(\.editorState)`.
- **Hybrid activation policy (DYNAMIC, not always `.accessory`):** the app starts
  `.accessory` (menu-bar agent, no Dock icon, windowless). When an editor/video
  window opens it switches to **`.regular`** so editor windows are first-class
  multi-document windows — Dock icon, ⌘` window cycling, click-the-Dock-icon-to-
  return. `AppCoordinator.syncActivationPolicy()` (called from `openWindow` and a
  `NSWindow.willCloseNotification` observer) drops back to `.accessory` when the
  last editor window closes (editor windows = `!(is NSPanel) && .titled`; the
  history/pinned/tooltip surfaces are panels). The menu-bar icon stays in both
  modes.
- **History is decoupled from editor windows:** `showHistory`/`flashNewCapture`
  do **not** `NSApp.activate` — the history overlay is a non-activating floating
  panel that orders itself front and becomes key on its own, so "Show History"
  never drags editor windows forward.
- **Window titles:** each editor window sets `.navigationTitle` from `EditorState.
  windowTitle` (saved package name → opened file name → "Untitled N") / `VideoEditorState.windowTitle` (recording file name), so windows are tellable apart in the ⌘` switcher / Window menu / Dock (the title bar itself is hidden).
- **Double-click-to-zoom:** `.hiddenTitleBar` leaves no real title bar, so
  `CanvasNSView.mouseDown` zooms the window on a double-click that isn't on an
  *editable* layer (matte, empty, or the locked base image — `document.hitTest`
  returns nil); editable layers stay double-click-to-edit.
- **Updater:** lightweight custom `version.json` check, no Sparkle.

## Open questions

- Where Preferences live and what they cover (hotkeys, capture defaults,
  history cap, overlay timeout).
