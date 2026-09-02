import AppKit
import Observation
import PhotonzCore
import PhotonzMedia
import SwiftUI

/// The resident menu-bar agent's root (CleanShot-style). Owns everything that
/// must outlive any single editor window: the capture pipeline + global
/// hotkeys, the persisted capture history, and the window-spawning intents.
/// It survives with **zero windows open** — only the menu's Quit terminates the
/// app; closing the last editor window does not.
///
/// Per-document editor state lives in `EditorState`, one instance per editor
/// window. This split (app-level coordinator vs per-window editor) is phase
/// 11.1, the prerequisite for the multi-window editor and the global overlays.
///
/// SwiftUI owns window lifecycle via `WindowGroup(for: EditorWindowID.self)`.
/// Because the agent's menu can run with no window open, the coordinator can't
/// reach `@Environment(\.openWindow)` itself — the menu-bar scene injects a
/// closure here (`openWindowAction`) that the coordinator calls to spawn or
/// focus a window for a given id.
@MainActor
@Observable
final class AppCoordinator {
    /// Capture + global hotkeys + the persisted history store. Was owned by the
    /// single app-wide `AppState`; now app-level so capture works without an
    /// editor window.
    let capture = CaptureCenter()

    /// SwiftUI's `openWindow(value:)`, captured from the menu-bar scene so the
    /// agent can open/focus editor windows even with none currently on screen.
    @ObservationIgnored var openWindowAction: ((EditorWindowID) -> Void)?

    /// The global slide-down history overlay (phase 11.4). Observed by the menu
    /// for its show/hide label.
    private(set) var isHistoryShown = false
    @ObservationIgnored private let historyOverlay = HistoryOverlayController()

    /// The just-captured file, highlighted in the history overlay so the latest
    /// capture/recording stands out when the overlay pops after a capture. Nil
    /// when the overlay was opened manually (⇧⌘H) or after it's dismissed.
    private(set) var highlightedCaptureURL: URL?

    /// Floating tooltips for the history overlay's per-item icons (their own
    /// window so they escape the overlay bounds — no reserved space per cell).
    @ObservationIgnored private let tooltip = TooltipController()

    /// Bottom-right post-capture toasts. A capture no longer pops the whole
    /// history overlay — it stacks a small "Copied to clipboard" toast instead.
    @ObservationIgnored private let toasts = ToastController()

    /// First-run permissions walkthrough. Created at launch so it can record
    /// whether Screen Recording was granted when the process started (a grant
    /// mid-session needs a relaunch to take effect).
    @ObservationIgnored private let welcome = WelcomeController()

    /// The Experiments window (release picker + feature flags). App-level so it
    /// opens with no editor window on screen.
    @ObservationIgnored private let experimentsWindow = ExperimentsWindowController()

    /// One entry in the global focus history (`focusMRU`).
    private enum FocusToken {
        /// A non-Photonz app that came forward. Held strongly — the notification's
        /// `NSRunningApplication` isn't retained anywhere we control, so a weak
        /// ref would zero out before we could use it. Apps report `isTerminated`.
        case app(NSRunningApplication)
        /// A Photonz editor window that became main, keyed by window number.
        case editorWindow(Int)
    }

    /// Most-recently-focused first: a merged history of non-Photonz app
    /// activations and Photonz editor-window focuses. When an editor window
    /// closes we consult the most-recent *remaining* entry to decide who gets
    /// focus, so closing behaves like an ordinary window — it returns to the last
    /// thing you were in, whether that's another Photonz window or another app.
    /// (AppKit already promotes the next Photonz window on its own, so we only
    /// step in when the front of the history is a different app.)
    @ObservationIgnored private var focusMRU: [FocusToken] = []

    /// Runs once at launch (from the `AppDelegate`). Becomes a menu-bar agent
    /// (`.accessory`: no Dock icon, stays alive windowless) and starts capture.
    func start() {
        // Agent lifecycle: no Dock icon, the app keeps running with no windows.
        // The bundled app also sets LSUIElement, but this makes plain
        // `swift build` dev runs behave the same.
        NSApp.setActivationPolicy(.accessory)
        // The app menu's title comes from the bundle, which can't know which
        // release is running. Rename it (and keep renaming it: SwiftUI rebuilds
        // the menu bar as scenes come and go).
        applyAppMenuTitle()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppCoordinator.applyAppMenuTitle() }
        }
        // History presentation: capture signals; the overlay is ours to drive.
        capture.onToggleHistory = { [weak self] in self?.toggleHistory() }
        capture.onRequestHistory = { [weak self] in self?.showHistory() }
        capture.onEditLastCapture = { [weak self] in self?.editLastCapture() }
        capture.onCaptureComplete = { [weak self] entry in
            // Auto-copy so the user can paste immediately (image data for
            // screenshots, the file for recordings).
            self?.capture.store.copyToPasteboard(entry)
            self?.showCaptureToast(entry)
        }
        historyOverlay.onDismiss = { [weak self] in
            self?.isHistoryShown = false
            self?.highlightedCaptureURL = nil
            self?.tooltip.hide()
        }
        // Record every non-Photonz app that comes forward, most-recent-first.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.recordFocus(.app(app))
            }
        }
        // Record every Photonz editor window that becomes main, most-recent-first.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            let win = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let win, Self.isEditorWindow(win) else { return }
                self.recordFocus(.editorWindow(win.windowNumber))
            }
        }
        // On editor-window close: hand focus to the most-recently-used thing that
        // remains (another Photonz window or another app), so closing behaves
        // like an ordinary window. Then re-evaluate the Dock-icon policy once the
        // window has left the list. willClose fires before it leaves, so the
        // policy step is deferred a tick; the focus step must NOT be — a deferred
        // yield lands a frame after AppKit promotes a sibling, flashing it forward.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let win = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self else { return }
                if let win, Self.isEditorWindow(win) { self.editorWindowWillClose(win) }
                DispatchQueue.main.async { MainActor.assumeIsolated { self.syncActivationPolicy() } }
            }
        }
        capture.start()
        // First-run walkthrough: guide the user through the one-time macOS
        // permissions before their first capture fails scarily. No-op once
        // completed (window closed with Screen Recording granted).
        welcome.presentIfNeeded(capture: capture)
        // Background update discovery (badge on the menu-bar icon).
        startUpdateChecks()
    }

    /// Menu "Welcome & Permissions…" and the history overlay's permission hint:
    /// reopen the setup walkthrough on demand.
    func showWelcome() {
        welcome.present(capture: capture)
    }

    /// Menu "Experiments…": the release picker and per-release feature flags.
    func showExperiments() {
        experimentsWindow.present()
    }

    /// Names the app menu after the running release ("Photonz Next"), since the
    /// bundle's own name is fixed at build time. Cheap and idempotent, so it can
    /// run on every activation.
    static func applyAppMenuTitle() {
        guard let appMenuItem = NSApp.mainMenu?.items.first else { return }
        let name = AppInfo.name
        if appMenuItem.title != name { appMenuItem.title = name }
        if appMenuItem.submenu?.title != name { appMenuItem.submenu?.title = name }
    }

    private func applyAppMenuTitle() { Self.applyAppMenuTitle() }

    // MARK: - Post-capture feedback

    /// After a capture/recording lands, stack a bottom-right toast (thumbnail +
    /// "Copied to clipboard") instead of popping the whole history overlay. The
    /// toast auto-fades; hovering it pins it and reveals Edit / Dismiss. History
    /// is still a deliberate ⇧⌘H away. If a capture is highlighted in an open
    /// overlay, keep that behavior in sync.
    func showCaptureToast(_ entry: CaptureEntry) {
        if historyOverlay.isShown { highlightedCaptureURL = entry.url }
        let isVideo = entry.kind == .video
        toasts.present(
            entry: entry, store: capture.store,
            message: "Copied to clipboard!", on: activeScreen(),
            editAction: captureToastEditAction,
            onEdit: { [weak self] in
                guard let self else { return }
                if isVideo { self.openRecording(entry.url) } else { self.editCapture(entry.url) }
            },
            // Recordings get a Copy menu (video / GIF); screenshots are already an
            // image on the clipboard, so they don't.
            onCopyVideo: isVideo ? { [weak self] in self?.copyRecording(entry, as: .mp4) } : nil,
            onCopyGIF: isVideo ? { [weak self] in self?.copyRecording(entry, as: .gif) } : nil)
    }

    // MARK: - Recordings (phase 12.4 / 12.5)

    /// Open a recording in the in-app video editor (phase 13.3): open/focus a
    /// `.video` window for it and bring the app forward. Opening a recording for
    /// playback is NOT TCC-gated (only capturing one is). Falls back to revealing
    /// the file in Finder if the window action isn't wired up yet.
    func openRecording(_ url: URL) {
        guard openWindowAction != nil else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        openWindow(.video(standardizing: url))
    }

    /// Show a capture in the Finder. History is a live listing of a real folder,
    /// so "where is this file" is a question it should be able to answer.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Copy recording to clipboard (video / GIF)

    /// History overlay: copy a recording to the clipboard as an MP4 file or an
    /// animated GIF. The stored file is the truth (phase 19) — a saved trim is
    /// already in it — so nothing is re-applied on the way out.
    func copyRecording(_ entry: CaptureEntry, as format: RecordingFormat) {
        copyRecording(sourceURL: entry.url, as: format, trim: nil, crop: nil)
    }

    /// Video editor: copies what the window is showing, including edits the user
    /// hasn't saved yet — so it reads from the edit source (the preserved
    /// original once one exists) and applies them.
    func copyRecording(_ state: VideoEditorState, as format: RecordingFormat) {
        guard let url = state.editSourceURL else { return }
        let edits = state.exportEdits
        copyRecording(sourceURL: url, as: format, trim: edits.trim, crop: edits.crop)
    }

    /// MP4 with no edits copies the source file directly; everything else
    /// re-encodes into a clipboard scratch file first, then copies that. Ends
    /// with a toast — re-encodes take a moment and the app may have no window
    /// up, so the user needs to see when the clipboard is actually ready.
    private func copyRecording(sourceURL: URL, as format: RecordingFormat,
                               trim: VideoTrim?, crop: VideoCrop?) {
        if format == .mp4, trim == nil, crop == nil {
            ClipboardWriter.writeFile(sourceURL)
            presentCopyToast(for: sourceURL, message: "Video copied to clipboard!")
            return
        }
        guard !isExportingRecording else { return }
        isExportingRecording = true
        // A GIF re-encode takes ~a second; show a live progress toast in the
        // bottom-right stack so the wait isn't a mystery. (MP4 copies are quick
        // and stay silent until the "copied" toast.)
        let progress: ToastProgress? = format == .gif
            ? toasts.presentProgress(title: "Preparing GIF…", on: activeScreen()) : nil
        Task {
            do {
                let destination = Self.clipboardScratchURL(for: sourceURL, format: format)
                if format == .mp4 {
                    let seconds = await VideoExporter.duration(of: sourceURL)
                    try await VideoExporter.exportMP4(from: sourceURL, to: destination,
                                                      trim: trim ?? VideoTrim(duration: seconds),
                                                      crop: crop)
                    ClipboardWriter.writeFile(destination)
                    presentCopyToast(for: sourceURL, message: "Video copied to clipboard!")
                } else {
                    // Preserve the recording's smoothness: match the source fps
                    // (capped at the format's ceiling) instead of the exporter's
                    // fixed 15fps default, which made pasted GIFs look choppy.
                    // Keep full (physical) resolution up to the exporter's cap so
                    // the GIF stays crisp on Retina — Chromium apps (Teams) render
                    // it larger, but a downscale to logical size looks blurry.
                    let sourceFPS = await VideoExporter.frameRate(of: sourceURL)
                    let targetFPS = AnimatedExportPlanner.clipboardFPS(sourceFPS: sourceFPS, format: format)
                    // Reserve the last sliver for the encode/finalize step so the
                    // bar doesn't sit at 100% while ImageIO writes the file.
                    try await VideoExporter.exportAnimated(
                        from: sourceURL, to: destination, format: format,
                        trim: trim, crop: crop, targetFPS: targetFPS,
                        onProgress: { done, total in
                            Task { @MainActor in
                                progress?.update(fraction: 0.95 * Double(done) / Double(max(1, total)))
                            }
                        })
                    progress?.update(fraction: 1)
                    // Inline GIF bytes ride along for targets that paste content
                    // instead of attaching files.
                    let data = format == .gif ? try? Data(contentsOf: destination) : nil
                    ClipboardWriter.writeFile(destination, data: data, dataType: format == .gif ? .gif : nil)
                    if let progress { toasts.dismissProgress(progress) }
                    presentCopyToast(for: sourceURL, message: "GIF copied to clipboard!")
                }
            } catch {
                if let progress { toasts.dismissProgress(progress) }
                reportExportFailure(error)
            }
            isExportingRecording = false
        }
    }

    /// Where clipboard re-encodes land: a temp folder, file named after the
    /// recording so pastes carry a meaningful filename. Overwritten per copy.
    private static func clipboardScratchURL(for sourceURL: URL, format: RecordingFormat) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotonzClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".\(format.fileExtension)")
    }

    private func presentCopyToast(for sourceURL: URL, message: String) {
        let entry = capture.store.entries.first(where: { $0.url == sourceURL })
        toasts.present(entry: entry, store: capture.store,
                       message: message, on: activeScreen(),
                       editAction: captureToastEditAction) { [weak self] in
            self?.openRecording(sourceURL)
        }
    }

    /// How a capture toast offers editing. Next (`next-capture-toast-edit`)
    /// shows the Edit row and names ⇧⌘6; the key is left off on a Touch Bar
    /// Mac where macOS still owns ⇧⌘6 for its own screenshot, so the toast
    /// never promises a key that does nothing. Current keeps the hover pencil.
    private var captureToastEditAction: ToastEditAction {
        guard Experiments.shared.captureToastEditEnabled else { return .onHover }
        let shadowed = WelcomeState.currentShortcutConflicts().contains(.touchBar)
        return .always(shortcut: shadowed ? nil : SystemScreenshotShortcuts.Shortcut.touchBar.keyLabel)
    }

    /// Export the recording open in the video editor, honoring its in-memory
    /// trim/crop (phase 13.5). MP4 with no edits is a fast verbatim copy; with
    /// trim/crop it's a real re-encode. GIF/HEIC always re-encode (trim+crop
    /// threaded through). Runs off the main actor with basic error reporting.
    func saveRecording(_ state: VideoEditorState, as format: RecordingFormat,
                       quality: VideoExportQuality = .standard) {
        // Read from the edit source (the preserved original once one exists) so
        // the window's edits apply to full-length media rather than stacking on
        // an already-committed trim; name the file after the recording.
        guard let recordingURL = state.url, let sourceURL = state.editSourceURL else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.savePanelType]
        panel.nameFieldStringValue = recordingURL.deletingPathExtension().lastPathComponent + ".\(format.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let trim = state.exportTrim
        let crop = state.crop
        let edited = state.hasEdits

        if format == .mp4 {
            if !edited {
                // Fast path: no trim/crop → verbatim copy, no re-encode.
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.copyItem(at: sourceURL, to: url)
                return
            }
            isExportingRecording = true
            Task {
                do {
                    try await VideoExporter.exportMP4(from: sourceURL, to: url, trim: trim, crop: crop)
                } catch {
                    reportExportFailure(error)
                }
                isExportingRecording = false
            }
        } else {
            isExportingRecording = true
            Task {
                do {
                    try await VideoExporter.exportAnimated(from: sourceURL, to: url, format: format,
                                                           trim: trim, crop: crop,
                                                           targetFPS: quality.targetFPS,
                                                           maxDimension: quality.maxDimension)
                } catch {
                    reportExportFailure(error)
                }
                isExportingRecording = false
            }
        }
    }

    /// True while a recording re-encode is in flight, so the editor can show a
    /// progress/cancel affordance and disable re-entrant exports.
    private(set) var isExportingRecording = false

    private func reportExportFailure(_ error: Error) {
        NSLog("Recording export failed: \(error)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't export the recording"
        alert.informativeText = String(describing: error)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - History overlay

    /// ⇧⌘H / menu: show the global history overlay, or hide it if already up.
    func toggleHistory() {
        if historyOverlay.isShown { hideHistory() } else { showHistory() }
    }

    func showHistory() {
        guard !historyOverlay.isShown else { return }
        // The history overlay is a non-activating floating panel that orders
        // itself front and becomes key on its own — DON'T activate the app, or
        // every editor window would be dragged forward with it. "Show history"
        // means show history, not the editor windows.
        historyOverlay.show(content: HistoryOverlay(coordinator: self), on: activeScreen(),
                            reserveForPermissionHint: capture.needsScreenRecordingPermission)
        isHistoryShown = true
    }

    func hideHistory() {
        historyOverlay.hide(notify: false)
        isHistoryShown = false
        highlightedCaptureURL = nil
        tooltip.hide()
    }

    /// History-icon tooltips (their own floating window). Anchored to the icon's
    /// frame (`rect`, in the overlay's local top-left coordinate space) so the
    /// tooltip sits just BELOW the icon — not wherever the pointer happens to be.
    func showCaptureTooltip(_ text: String, iconFrameInOverlay rect: CGRect) {
        guard let panel = historyOverlay.panelFrame else { return }
        let centerX = panel.minX + rect.midX
        let iconBottomScreenY = panel.maxY - rect.maxY  // overlay y is top-down; screen is bottom-up
        tooltip.show(text, below: CGPoint(x: centerX, y: iconBottomScreenY - 6))
    }

    func hideCaptureTooltip() {
        tooltip.hide()
    }

    /// "Clear All" in the history overlay: confirm, then move every capture to
    /// the Trash (recoverable). The watched folder drives the UI refresh.
    func clearHistory() {
        let count = capture.store.entries.count
        guard count > 0 else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear capture history?"
        alert.informativeText =
            "This moves \(count) item\(count == 1 ? "" : "s") in \(capture.store.directory.lastPathComponent) to the Trash. You can recover them from there."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            capture.store.clearAll()
        }
    }

    /// The display the overlay should drop onto: the one with the key window,
    /// else the one under the pointer, else the main display.
    private func activeScreen() -> NSScreen {
        if let screen = NSApp.keyWindow?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Window intents

    /// Opens (or focuses) an editor window for `id`. Editor windows are
    /// first-class app windows — becoming `.regular` gives the app a Dock icon,
    /// ⌘` window cycling, and click-the-Dock-icon-to-return, like any
    /// multi-document app. `syncActivationPolicy` drops back to the menu-bar-only
    /// `.accessory` when the last one closes.
    func openWindow(_ id: EditorWindowID) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id)
    }

    /// Editor windows are real titled app windows; the history/tooltip surfaces
    /// are panels. Be `.regular` while any editor window is open (Dock
    /// icon + ⌘` cycling) and return to the windowless agent's `.accessory` (no
    /// Dock icon) when none remain.
    func syncActivationPolicy() {
        let hasEditorWindow = NSApp.windows.contains { window in
            !(window is NSPanel) && window.styleMask.contains(.titled) && window.isVisible
        }
        let desired: NSApplication.ActivationPolicy = hasEditorWindow ? .regular : .accessory
        if NSApp.activationPolicy() != desired { NSApp.setActivationPolicy(desired) }
    }

    /// An editor window (titled, non-panel — image or video editor), as opposed
    /// to the app's panels (history overlay, tooltip, toast, welcome).
    private static func isEditorWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    /// Push a freshly focused app/window to the front of the focus history,
    /// de-duping any earlier entry for the same thing and dropping dead apps.
    private func recordFocus(_ token: FocusToken) {
        focusMRU.removeAll { existing in
            switch (existing, token) {
            case let (.app(a), .app(b)): return a.processIdentifier == b.processIdentifier
            case let (.editorWindow(a), .editorWindow(b)): return a == b
            default: return false
            }
        }
        focusMRU.removeAll { if case .app(let a) = $0 { return a.isTerminated } else { return false } }
        focusMRU.insert(token, at: 0)
        if focusMRU.count > 32 { focusMRU.removeLast(focusMRU.count - 32) }
    }

    /// An editor window is closing: give focus to the most-recently-used thing
    /// that remains, so closing behaves like an ordinary window. If that's
    /// another app, activate it now (synchronously — a deferred activation lands
    /// a frame after AppKit reveals a sibling window, flashing it forward). If
    /// it's another Photonz window (or nothing), do nothing: AppKit already
    /// promotes the next window, which is exactly what we want.
    private func editorWindowWillClose(_ window: NSWindow) {
        let closing = window.windowNumber
        focusMRU.removeAll { if case .editorWindow(let n) = $0 { return n == closing } else { return false } }
        focusMRU.removeAll { if case .app(let a) = $0 { return a.isTerminated } else { return false } }
        if case .app(let app)? = focusMRU.first {
            app.activate()
        }
    }

    /// Menu "New Window": a brand-new empty document in its own window.
    func newDocumentWindow() {
        openWindow(.fresh(UUID()))
    }

    /// ⌘N "New from Clipboard": a new window seeded from the clipboard image.
    func newFromClipboardWindow() {
        openWindow(.clipboard(UUID()))
    }

    /// Edit a capture from history: dismiss the overlay, open/focus its window.
    /// Captures are files now, so this just opens the file (re-opening the same
    /// URL focuses the existing window).
    func editCapture(_ url: URL) {
        if isHistoryShown { hideHistory() }
        openWindow(.file(url))
    }

    /// The newest item in history, or nil when the folder is empty. "Newest" is
    /// whatever history lists first, so the menu, the hotkey and the overlay
    /// all agree on which capture is the last one.
    var lastCapture: CaptureEntry? { capture.store.entries.first }

    /// ⇧⌘6 / menu "Edit Last Capture": open the newest capture in its editor
    /// (a recording opens the video editor). The toast already offers this,
    /// but it fades; this is the path that still works after it has gone.
    func editLastCapture() {
        guard let entry = lastCapture else { return }
        if entry.kind == .video { openRecording(entry.url) } else { editCapture(entry.url) }
    }

    /// The edit round-trip back to history (phase 11.5). Called from the editor's
    /// "Save to Capture History" command with the flattened composite. If the
    /// window was opened from a capture still in the folder, offer Override-in-place
    /// vs Save-as-new; otherwise just add a new entry. The history overlay observes
    /// `CaptureStore`, so it refreshes automatically.
    /// Returns the capture file the composite landed in (nil on cancel), so the
    /// editor can adopt it as its source and refresh its layered sidecar.
    @discardableResult
    func saveEditedCapture(sourceURL: URL?, image: CGImage, scale: CGFloat = 1) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        if let sourceURL, capture.store.entries.contains(where: { $0.url == sourceURL }) {
            let alert = NSAlert()
            alert.messageText = "Save to Capture History"
            alert.informativeText =
                "Replace the original capture with your edits, or keep both by saving as a new entry?"
            alert.addButton(withTitle: "Override Original")
            alert.addButton(withTitle: "Save as New")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                capture.store.replace(at: sourceURL, with: image, scale: scale)
                return sourceURL
            case .alertSecondButtonReturn:
                return capture.store.add(image, scale: scale)?.url
            default:
                return nil
            }
        } else {
            return capture.store.add(image, scale: scale)?.url
        }
    }

    /// Open an image / `.photonz` file in its own window.
    func openFileWindow(_ url: URL) {
        openWindow(.file(url))
    }

    /// Menu "Open…": runs an open panel from the agent (works with no window
    /// open), then opens the chosen file in its own editor window.
    func presentOpenPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, EditorState.photonzType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFileWindow(url)
    }

    // MARK: - Updater (phase 11.6; self-update 17.10)

    /// True while an update check is in flight, so the menu can disable the item
    /// and avoid overlapping checks.
    private(set) var isCheckingForUpdates = false

    /// A newer published version, found by the background check (or a manual
    /// one). Non-nil puts the dot on the menu-bar icon and the "Update &
    /// Restart" item in the menu.
    private(set) var availableUpdate: SemanticVersion?

    /// User-facing phase string while an install is running ("Downloading…" /
    /// "Verifying…" / "Installing…"); nil when idle. Drives the menu item label
    /// and re-entrancy.
    private(set) var updateStatus: String?

    /// Set right before the update flow terminates the app; the app delegate's
    /// `applicationWillTerminate` spawns the relauncher only when this is set,
    /// so a cancelled quit (unsaved changes) doesn't spawn a stray reopen.
    @ObservationIgnored var pendingRelaunchBundlePath: String?

    /// Hours between background update checks while the agent is resident.
    private static let updateCheckInterval: Duration = .seconds(6 * 3600)

    /// Background update discovery, started from `start()`. Skipped for dev
    /// builds — both the bare `swift build` kind (reports 0.0.0, every release
    /// would look new) and "Photonz Dev.app" bundles (self-updating would swap
    /// the dev bundle for the release app, defeating side-by-side installs).
    /// Purely reveals availability; installing stays a user action.
    func startUpdateChecks() {
        guard !AppInfo.isDevBuild else { return }
        guard UpdateChecker.currentVersion > SemanticVersion(major: 0, minor: 0, patch: 0) else { return }
        Task { [weak self] in
            // Small delay so launch isn't competing with the network check.
            try? await Task.sleep(for: .seconds(10))
            while let self, !Task.isCancelled {
                if case .updateAvailable(_, let latest) = await UpdateChecker.check() {
                    self.availableUpdate = latest
                }
                try? await Task.sleep(for: Self.updateCheckInterval)
            }
        }
    }

    /// Menu "Update to vX.Y.Z & Restart": download, verify, swap the bundle,
    /// and relaunch. On failure nothing was installed (the swap is the last
    /// step) and the alert offers the manual download page as a fallback.
    func installAvailableUpdate() {
        guard let version = availableUpdate, updateStatus == nil else { return }
        updateStatus = "Preparing…"
        Task {
            do {
                try await SelfUpdater.install(version: version, over: Bundle.main.bundleURL) { phase in
                    self.updateStatus = phase
                }
                updateStatus = nil
                availableUpdate = nil
                // Relaunch via the delegate hook: the helper only spawns if the
                // app really terminates (unsaved-changes review can cancel it —
                // then the new version simply starts on the next launch).
                pendingRelaunchBundlePath = Bundle.main.bundlePath
                NSApp.terminate(nil)
            } catch {
                updateStatus = nil
                presentUpdateInstallFailure(error)
            }
        }
    }

    private func presentUpdateInstallFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't install the update"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Download Manually…")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(UpdateChecker.downloadPageURL)
        }
    }

    /// Menu "Check for Updates…": compares the running build against the
    /// published `version.json` and reports the outcome in an alert. The
    /// comparison logic is the testable `SemanticVersion`; this just fetches and
    /// presents. An available update offers the in-place Update & Restart.
    func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        NSApp.activate(ignoringOtherApps: true)
        Task {
            let result = await UpdateChecker.check()
            isCheckingForUpdates = false
            presentUpdateResult(result)
        }
    }

    private func presentUpdateResult(_ result: UpdateChecker.Result) {
        let alert = NSAlert()
        switch result {
        case .upToDate(let current):
            alert.messageText = "You're up to date"
            alert.informativeText = "Photonz \(current) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .updateAvailable(let current, let latest):
            availableUpdate = latest
            // Dev builds (0.0.0) can't swap themselves meaningfully — they'd
            // "update" a dist/ bundle mid-development. Offer the page instead.
            let canSelfUpdate = current > SemanticVersion(major: 0, minor: 0, patch: 0)
                && Bundle.main.bundleURL.pathExtension == "app"
            alert.messageText = "Update available"
            alert.informativeText =
                "Photonz \(latest) is available. You have \(current)."
            alert.addButton(withTitle: canSelfUpdate ? "Update & Restart" : "Download…")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                if canSelfUpdate {
                    installAvailableUpdate()
                } else {
                    NSWorkspace.shared.open(UpdateChecker.downloadPageURL)
                }
            }
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Shared About panel (menu-bar menu + the editor windows' app menu).
    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "Fast photo & screenshot editing for the Mac.\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        if let url = URL(string: "https://dzearing.github.io/photonz/") {
            credits.append(NSAttributedString(
                string: "dzearing.github.io/photonz",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .link: url,
                ]))
        }
        // Name it after the running release ("Photonz Next"), not the bundle.
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: AppInfo.name,
        ])
    }
}
