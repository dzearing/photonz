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
        historyOverlay.onDismiss = { [weak self] in self?.isHistoryShown = false }
        capture.start()
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
    func editCapture(_ entryID: UUID) {
        if isHistoryShown { hideHistory() }
        openWindow(.capture(entryID))
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
