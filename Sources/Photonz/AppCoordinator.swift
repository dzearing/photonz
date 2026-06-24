import AppKit
import Observation
import PhotonzCore
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
    /// when the overlay was opened manually (⌘⇧H) or after it's dismissed.
    private(set) var highlightedCaptureURL: URL?

    /// Pin-to-screen floating windows (phase 11.8).
    @ObservationIgnored private let pinned = PinnedWindowController()

    /// Floating tooltips for the history overlay's per-item icons (their own
    /// window so they escape the overlay bounds — no reserved space per cell).
    @ObservationIgnored private let tooltip = TooltipController()

    /// Runs once at launch (from the `AppDelegate`). Becomes a menu-bar agent
    /// (`.accessory`: no Dock icon, stays alive windowless) and starts capture.
    func start() {
        // Agent lifecycle: no Dock icon, the app keeps running with no windows.
        // The bundled app also sets LSUIElement, but this makes plain
        // `swift build` dev runs behave the same.
        NSApp.setActivationPolicy(.accessory)
        // History presentation: capture signals; the overlay is ours to drive.
        capture.onToggleHistory = { [weak self] in self?.toggleHistory() }
        capture.onRequestHistory = { [weak self] in self?.showHistory() }
        capture.onCaptureComplete = { [weak self] entry in
            // Auto-copy so the user can paste immediately (image data for
            // screenshots, the file for recordings).
            self?.capture.store.copyToPasteboard(entry)
            self?.flashNewCapture(entry.url)
        }
        historyOverlay.onDismiss = { [weak self] in
            self?.isHistoryShown = false
            self?.highlightedCaptureURL = nil
            self?.tooltip.hide()
        }
        capture.start()
    }

    // MARK: - Post-capture feedback

    /// After a capture/recording lands, surface the history overlay with the new
    /// entry highlighted (replaces the old corner toast — the overlay is the one
    /// place captures live, and it's recallable with ⌘⇧H).
    func flashNewCapture(_ url: URL) {
        highlightedCaptureURL = url
        if historyOverlay.isShown {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showHistory()
        }
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

    /// Convert a recording to an animated GIF / HEIC and save it where the user
    /// picks (the "quick convert" path of 12.5; the MP4 is already auto-saved).
    func saveRecording(_ sourceURL: URL, as format: RecordingFormat) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.savePanelType]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".\(format.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if format == .mp4 {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: sourceURL, to: url)
        } else {
            Task {
                do {
                    try await VideoExporter.exportAnimated(from: sourceURL, to: url, format: format)
                } catch {
                    NSLog("Recording export failed: \(error)")
                }
            }
        }
    }

    /// Export the recording open in the video editor, honoring its in-memory
    /// trim/crop (phase 13.5). MP4 with no edits is a fast verbatim copy; with
    /// trim/crop it's a real re-encode. GIF/HEIC always re-encode (trim+crop
    /// threaded through). Runs off the main actor with basic error reporting.
    func saveRecording(_ state: VideoEditorState, as format: RecordingFormat,
                       quality: VideoExportQuality = .standard) {
        guard let sourceURL = state.url else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.savePanelType]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".\(format.fileExtension)"
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

    /// Pin a capture as a floating, always-on-top window (phase 11.8).
    func pinCapture(_ url: URL) {
        guard let entry = capture.store.entries.first(where: { $0.url == url }),
              let image = capture.store.image(for: entry) else { return }
        pinned.pin(image: image, on: activeScreen())
    }

    // MARK: - History overlay

    /// ⌘⇧H / menu: show the global history overlay, or hide it if already up.
    func toggleHistory() {
        if historyOverlay.isShown { hideHistory() } else { showHistory() }
    }

    func showHistory() {
        guard !historyOverlay.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        historyOverlay.show(content: HistoryOverlay(coordinator: self), on: activeScreen())
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

    /// Opens (or focuses) an editor window for `id`. Brings the app forward so
    /// the window can take focus from an accessory (no-Dock) agent.
    func openWindow(_ id: EditorWindowID) {
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id)
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

    /// The edit round-trip back to history (phase 11.5). Called from the editor's
    /// "Save to Capture History" command with the flattened composite. If the
    /// window was opened from a capture still in the folder, offer Override-in-place
    /// vs Save-as-new; otherwise just add a new entry. The history overlay observes
    /// `CaptureStore`, so it refreshes automatically.
    func saveEditedCapture(sourceURL: URL?, image: CGImage) {
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
            case .alertFirstButtonReturn: capture.store.replace(at: sourceURL, with: image)
            case .alertSecondButtonReturn: capture.store.add(image)
            default: return
            }
        } else {
            capture.store.add(image)
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

    // MARK: - Updater (phase 11.6)

    /// True while an update check is in flight, so the menu can disable the item
    /// and avoid overlapping checks.
    private(set) var isCheckingForUpdates = false

    /// Menu "Check for Updates…": compares the running build against the
    /// published `version.json` and reports the outcome in an alert. The
    /// comparison logic is the testable `SemanticVersion`; this just fetches and
    /// presents.
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
            alert.messageText = "Update available"
            alert.informativeText =
                "Photonz \(latest) is available — you have \(current). Download the latest version?"
            alert.addButton(withTitle: "Download…")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(UpdateChecker.downloadPageURL)
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
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
