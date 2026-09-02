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
   - **Freeze-frame model (revised 2026-07-02, user-proposed; dim-first since
     2026-09-02).** Every display is covered by a borderless panel at
     `CGShieldingWindowLevel()` (above every window, panel, and alert — nothing
     underneath stays interactive or can float over the drag box), and the
     selection is dragged on top of it. The panels go up **first**, in the same
     turn of the run loop as the shortcut (measured under 20 ms from
     `begin()` to every display covered), so the screen dims immediately; the
     freeze follows and each display's picture slides in underneath as its shot
     lands (43 ms cold, 12 ms warm per display). Until then the dim falls on the
     live screen, which is also the permanent fallback when a shot fails.
     The panels carry `sharingType = .none` while the freeze is in flight, so
     the shot cannot photograph our own dim (verified: a panel left at
     `.readOnly` dropped the captured luma by exactly its alpha; at `.none` the
     capture was pixel-identical to the clean screen). Once every shot is in
     they go back to `.readOnly` so an ordinary screen recording still shows
     the overlay. On
     mouse-up the region is **cropped from the frozen bitmap** (screen points ×
     `backingScaleFactor`) — atomically WYSIWYG; the old dismiss → 60ms sleep →
     live re-capture dance survives only as a fallback when freezing fails.
     Region *recording* uses the same selection UI but ignores the crop and
     records live (the overlay tears down before the stream starts), so it
     dims on the same schedule.
     `animationBehavior = .none` + a disabled-actions CATransaction keep the
     freeze imperceptible — macOS's default panel fade reads as a visible flash.
     **GOTCHA (fixed 2026-07-03):** assign `level` LAST when configuring the
     panel — NSPanel property setters can silently rewrite it. `isFloatingPanel
     = true` ran after the level assignment and reset it to `.floating` (3),
     which beats normal windows but loses to modal dialogs (level 8) — the
     "selection appears behind the modal" bug. Verified via a CGWindowList
     z-dump; note the filter-based SCK screenshot API EXCLUDED shielding-level
     windows, so verify stacking with the window list, not pixels.
   - **Window shadows (fixed 2026-07-03).** `ScreenCapturer` uses the WYSIWYG
     `SCScreenshotManager.captureImage(in:)` API (macOS 15.2+), NOT the
     filter-based `captureImage(contentFilter:configuration:)` one. The filter
     path re-composites windows from their individual buffers and synthesizes
     NO window shadows (measured Δ0 luma under every window edge vs the
     `screencapture` CLI's Δ57 normal / Δ123 modal) — frozen modals looked
     pasted-on. The WYSIWYG call matches the system screenshot exactly:
     shadows included, cursor excluded, native backing scale. Its rect is CG
     global top-left coordinates — `cgGlobalRect(for:on:)` converts from the
     screen-local top-left rects callers pass (conversion verified pixel-exact
     with a known-position window).
   - **Window picking (Next, `next-window-capture`, added 2026-09-02).** With
     the flag on, `RectSelectionController` lists the on-screen windows once at
     freeze time (`WindowLister`, `CGWindowListCopyWindowInfo` on-screen-only,
     converted into each display's top-left points space) and the overlay
     highlights the frontmost layer-0, visible, non-shield window under the
     pointer with an app-and-size pill (`WindowPick` in PhotonzCore decides
     which window, what counts as a click, and where the label goes; unit
     tested). Since 2026-09-02 the pill also carries the window's title
     between the app and the size, in a lighter weight ("Safari · Apple
     1440 × 900"), so one of an app's several windows is tellable from the
     rest. `WindowLister` reads `kCGWindowName`, which the window server
     only fills in for clients holding the Screen Recording grant (the dev
     and shipping apps, and the probe once it has been granted once). `WindowPick.displayTitle` drops a
     title that only repeats the app name, including the Chromium-style
     "Page - Microsoft Edge" suffix; `WindowPick.fittedLabel` shortens the
     title alone (`WindowPick.shortenedTitle`: cut in the MIDDLE the way the
     Finder shortens a name, the ending gets a third of the budget and starts
     on a word, never fewer than three characters, else dropped) so two
     windows that differ only at the end of their titles still read
     differently, and the pill stays inside the window when it sits there, inside
     the display when it hangs below a small window, and never wider than
     400 pt. The app measures, the core decides. A press that moves under 4
     pt captures that window's bounds
     clamped to the display, cropped from the same frozen bitmap a drag uses;
     a bigger move becomes the ordinary region drag, which now also shows a
     size pill. A click over nothing pickable cancels, as a bare click always
     did. The highlight is computed at show time from the pointer, not after
     the first move. Region recording shares the overlay, so a click there
     records that window's region live. Per-move cost measured at well under
     0.2 ms (partial invalidation of old and new chrome only).
   - **Window shots (Next, `next-window-capture`, added 2026-09-02).** A click
     on a highlighted window no longer crops the frozen picture. It asks the
     window server for that one window (`ScreenCapturer.captureWindow`,
     macOS 26 `SCScreenshotManager.captureScreenshot(contentFilter:configuration:)`
     with a `desktopIndependentWindow` filter, cursor off, clipping ignored so
     a window hanging off the display comes back whole) so the rounded
     corners are transparent and nothing in front of it is in the shot. The
     shadow is on by default like the built-in capture; Option while clicking
     gives the other choice, and the flag's "Include the window shadow"
     checkbox flips the default (`WindowShot.style`). The shot is live at the
     click, not the frozen picture, exactly as the system capture behaves.
     `WindowShot.isFaithful` (PhotonzCore, tested) rejects a shadowed shot
     that is not larger than the window (ScreenCaptureKit has been seen to
     squeeze window plus shadow into a window-sized frame) and a bare shot
     smaller than the window; a rejected or failed shot falls to the bare
     shot, then to the frozen crop, so a click never comes back empty. NOT
     verified live as of 2026-09-02: no unmanned bundle holds a Screen
     Recording grant; the playtest audit asks the user to confirm the look.
   - **The dim is a layer, not a fill (fixed 2026-09-02).** `SelectionView`
     used to paint the 25% black over `bounds` in `draw`, which only ever
     covered the rectangles AppKit had marked dirty: on a fresh overlay that was
     the hovered window's outline and nothing else, so most of the display sat
     at full brightness until a drag had swept over it. The dim now belongs to
     `DimView`, a shape-layer-backed view between the picture and the chrome,
     whose path is the whole display with an even-odd hole where the selection
     or the hovered window is. The compositor keeps it right without a repaint,
     and the hole moves by setting one path inside a disabled-actions
     transaction. Two AppKit traps to keep in mind: a `CAShapeLayer` added by
     hand as a sublayer is discarded when the view joins a layer-backed window
     (hence `makeBackingLayer`), and handing the frozen picture to the layer the
     chrome draws into replaces what the chrome drew there (hence the picture's
     own view).
   - **No loupe (removed 2026-09-02).** A magnifier beside the pointer shipped
     behind `next-capture-loupe` as competitor parity and the user rejected it
     on sight: a drag shows the box and its size, nothing else. The flag, its
     parameters, `CaptureLoupe` and its tests are deleted rather than defaulted
     off, so nobody has anything to switch off; `ExperimentsTests` keeps a
     regression test that the flag stays gone. The drag's size pill, which used
     to step aside for it, is the one readout during a drag again.
   - **The overlay must NOT activate the app.** With an editor window open the
     app is `.regular`, so `NSApp.activate(ignoringOtherApps:)` would raise
     *every* Photonz window — yanking the editor to the foreground when you
     screenshot from another app (a reported bug, fixed 2026-06-28). The
     selection windows are therefore **non-activating panels** (`NSPanel`,
     `.nonactivatingPanel`) ordered front via `orderFrontRegardless()` with
     **no `NSApp.activate`** — but the panel under the mouse IS made **key**
     (`makeKey()`): a non-activating panel can be key without activating the
     app, and key-ness is what makes the crosshair cursor and direct Esc
     delivery reliable (fixed 2026-07-02 — the crosshair never appeared while
     the panel wasn't key). `acceptsFirstMouse` keeps drag-to-select working,
     and **Esc** is additionally caught via local **and** global `NSEvent` key
     monitors. Do not reintroduce `NSApp.activate` here.
3. The result is added to `CaptureStore` (the persisted history) as a new entry.
4. **Post-capture feedback = bottom-right toasts** (re-revised 2026-06-27;
   `ToastController`). Each capture pops a small glass toast (thumbnail +
   "Copied to clipboard") on its own borderless non-activating panel — gaps
   between stacked toasts stay click-through. Holds 7s, fades 3s; hover pins it
   open and reveals **Edit / Dismiss**; **double-click anywhere on the toast =
   Edit** (2026-07-03). Toasts must never take key focus (`canBecomeKey =
   false`) — stealing key from whatever the user is typing in caused stray
   keystrokes + beeps. The slide-down history overlay remains the recallable
   home (⌘⇧H) with the newest entry ring-highlighted.
   - **Edit row (Next, `next-capture-toast-edit`, added 2026-09-02).** The
     hover pencil is invisible until pointed at and only the Welcome window
     ever taught ⇧⌘6, so a first capture read as a receipt with no way in.
     With the flag on, `ToastEditAction.always` adds a full-width Edit pill
     under the message, as wide as the thumbnail (196pt, so a longer
     recording message cannot push the toast wider), with ⇧⌘6 at its trailing
     end; the hover pill drops its pencil and keeps Copy / Dismiss. On a
     Touch Bar Mac where macOS still owns ⇧⌘6 the key is left off
     (`WelcomeState.currentShortcutConflicts`). Off (Current) is the hover
     pencil above, unchanged.
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
  the thumbnail: **Copy**, **Edit** (images) or **Play** (videos), then
  **Show in Finder** and **Delete** on every tile, plus drag-the-file-out. Every
  capture is a real file in a normal folder, so every tile can point at it.
  Recordings used to carry an Export menu there instead (Export GIF…/HEIC…, a
  save panel writing a converted copy elsewhere) — that's a *format* choice, and
  it belongs in the editor's Export menu with the other format choices
  (2026-08-22, user feedback: "the export button on history video items — I
  don't understand it. I can understand a show in finder button"). **Pin** was
  removed the same day for the same reason — a floating always-on-top copy of a
  screenshot, offered on image tiles only, that the user called "stupid and only
  on some types". `PinnedWindowController`/`PinnedImageView`/`PinnedImageMetrics`
  went with it. **Double-clicking an
  image tile opens it in the editor** (2026-07-03; videos open on a single
  click — the tap recognizers are installed conditionally so Play never waits
  out a double-click window). The newest item is ring-highlighted right after
  a capture.
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
- **Round-trip back to history** (phase 11.5, extended 2026-07-03):
  - **⌘S saves back in place.** A window opened from a capture file (and never
    saved as a `.photonz` package) writes the flattened composite straight back
    into that file via `CaptureStore.replace` — history items are real files,
    so Save means "save to where it came from". No prompt.
  - **⌘⌥S "Save to Capture History"** keeps the choice: **Override** vs **Save
    as new**; `AppCoordinator.saveEditedCapture` returns the landed URL so the
    editor adopts it as its new source.
  - **Layered sidecar (the "don't lose my layers" model).** Saving to a PNG
    flattens, so every save-to-capture ALSO auto-writes the full layered
    document as a `.photonz` package sidecar with the same basename
    (`EditorState.sidecarURL(for:)`). Re-opening the capture prefers the
    sidecar — layers come back editable. A **staleness guard** (sidecar mtime ≥
    media mtime − 2s) ignores the sidecar when the PNG was rewritten by
    something else. `.photonz` isn't a media extension, so sidecars never show
    in history; deleting a capture (or Clear All) trashes its sidecar too.
  - **Unsaved-changes protection** (2026-07-03): editor windows track a
    `savedDocument` baseline (value equality — undo back to the last save reads
    clean). Closing a dirty window shows the standard Save…/Cancel/Don't Save
    sheet via a **window-delegate proxy** (`WindowCloseGuard` — SwiftUI has no
    close veto; the proxy forwards everything else to SwiftUI's own delegate),
    with the edited dot in the close button. ⌘Q sweeps all dirty windows:
    Review Changes… / Cancel / Discard and Quit (`applicationShouldTerminate`
    + `.terminateLater`).

## Video editing round-trip: a saved recording IS the trimmed file

*(Phase 19, 2026-08-22.)* Trim and crop used to be sidecar-only — recorded in
`.photonzedits` and "applied at export" — so the stored MP4 stayed full length
and everything that hands out the file (drag from history, copy to the
clipboard) handed out the untrimmed original. The model, not any one call site,
was the bug: correct code sitting on top of a promise the file didn't keep.

The recording editor now saves exactly like the image editor:

- **The stored media file is the truth.** ⌘S **commits**: the trim/crop are
  re-encoded into the recording, so every consumer gets trimmed media without
  knowing trimming exists. No consumer re-applies edits any more — history
  thumbnails, duration pills, copy, and export-from-history all read the file
  verbatim.
- **The original is preserved, so the edit is reversible.** The pre-edit bytes
  move to `.photonz-originals/<same name>.mp4` beside the recording on the first
  save — a hidden dot-folder (so the capture scan never lists it) that keeps the
  media extension (so AVFoundation reads it unaided). Deleting a recording (or
  Clear All) trashes it along with the sidecar.
- **The editor always edits FROM the original**
  (`VideoOriginals.editSource(for:)`), the same way an image window prefers a
  capture's layered `.photonz` sidecar over the flattened PNG. Edits therefore
  always compose against full-length source: repeated saves never stack trims,
  and clearing the trim restores the whole clip (Video ▸ **Revert to Original**).
- **`.photonzedits` changed meaning.** It no longer describes pending edits to
  apply on the way out; it records how the visible file was *derived* from the
  preserved original. Only a save writes it, so it always matches the file.
- **Dirty = the edits differ from what's committed** (`VideoSaveState`). A
  recording trimmed before phase 19 has a sidecar but no original, so it reads
  as *unsaved* on open — the migration is a save prompt, not a silent loss.
- **Same window chrome as an image.** Video windows get `WindowCloseGuard`, the
  edited dot, the Save…/Cancel/Don't Save sheet and the ⌘Q sweep, via a shared
  `SaveableEditor` protocol (completion-based, because a video commit
  re-encodes). ⌘⇧S "Save As…" maps to the existing MP4 export panel — Export
  stays for *format* choices (GIF/HEIC/quality), never as the way to save.
- **Failure is not partial.** `VideoAssetCommit` builds the new media into a
  hidden scratch file first, preserves the original second, then swaps with
  `FileManager.replaceItemAt` (keeping the recording's name and creation date,
  which history sorts by), then writes the sidecar.

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
