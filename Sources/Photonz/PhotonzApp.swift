import AppKit
import SwiftUI

@main
struct PhotonzApp: App {
    /// The resident menu-bar agent. Owns capture, hotkeys, history, and the
    /// window registry; survives with zero editor windows open (phase 11.1).
    @State private var coordinator: AppCoordinator
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let coordinator = AppCoordinator()
        _coordinator = State(initialValue: coordinator)
        // Hand the coordinator to the delegate so its launch hook can start the
        // agent (activation policy + capture) — the menu's content is built
        // lazily, so it can't be the launch hook.
        AppDelegate.coordinator = coordinator
    }

    var body: some Scene {
        // Editor windows: one per document, value-based so `openWindow(value:)`
        // with an id already on screen reuses that window (focus-existing for
        // free — phase 11.5) and opens a fresh one otherwise. A value-typed
        // WindowGroup also means no window is forced open at launch, which is
        // what lets Photonz run as a windowless agent.
        WindowGroup(for: EditorWindowID.self) { $windowID in
            EditorRootView(windowID: windowID)
                .environment(coordinator)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        // Don't pop an editor window at launch — Photonz starts as a pure
        // menu-bar agent; windows open on demand (capture/edit/New/Open).
        .defaultLaunchBehavior(.suppressed)
        .commands { EditorCommands(coordinator: coordinator) }

        // The always-present menu-bar item keeps the agent alive and is the
        // entry point with no window open. Its label (the icon, always
        // rendered) captures SwiftUI's openWindow action so the agent can spawn
        // editor windows from anywhere. The full menu is phase 11.2.
        MenuBarExtra {
            MenuBarMenu(coordinator: coordinator)
        } label: {
            MenuBarLabel(coordinator: coordinator)
        }
    }
}

/// Launch + lifecycle hooks an `App` struct can't express directly. The menu's
/// content is built lazily (on first open), so agent startup must run here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set from `PhotonzApp.init` before launch finishes.
    @MainActor static var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppDelegate.coordinator?.start() }
    }

    /// Resident agent: closing the last editor window must NOT quit. Only the
    /// menu's Quit (NSApplication.terminate) ends the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Root of an editor window: owns this window's `EditorState`, seeds it once
/// from the window identity, and publishes it as the focused editor for the
/// menu commands.
struct EditorRootView: View {
    let windowID: EditorWindowID?
    @Environment(AppCoordinator.self) private var coordinator
    @State private var editorState = EditorState()

    var body: some View {
        EditorView()
            .environment(editorState)
            .focusedSceneValue(\.editorState, editorState)
            .task {
                if let windowID {
                    editorState.seed(from: windowID, capture: coordinator.capture)
                }
            }
    }
}

/// The menu-bar icon. Always rendered, so its `.task` is a reliable launch-time
/// hook to capture `openWindow` for the agent (the menu content is lazy).
struct MenuBarLabel: View {
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "camera.viewfinder")
            .task { coordinator.openWindowAction = { openWindow(value: $0) } }
    }
}

/// The resident agent's status-item drop-down (phase 11.2). Every action works
/// with no editor window open — capture, history, window-spawning, and the
/// updater all route through the `AppCoordinator`. Items not yet implemented
/// (Record → phase 12, Preferences → later) are present-but-disabled so the
/// shape of the app is visible without pretending to work.
struct MenuBarMenu: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        // Capture
        Button("Capture Region") { coordinator.capture.beginRectCapture() }
            .keyboardShortcut("4", modifiers: [.command, .shift])
        Button("Capture Full Screen") { coordinator.capture.captureFullScreen() }
            .keyboardShortcut("3", modifiers: [.command, .shift])
        Button("Record Screen / Video…") {}
            .disabled(true)  // wired in phase 12
            .help("Screen recording arrives in a later update.")

        Divider()

        // History
        Button(coordinator.isHistoryShown ? "Hide History" : "Show History") {
            coordinator.toggleHistory()
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])

        Divider()

        // Windows
        Button("New Window") { coordinator.newDocumentWindow() }
        Button("New from Clipboard") { coordinator.newFromClipboardWindow() }
        Button("Open…") { coordinator.presentOpenPanel() }

        Divider()

        // App
        Button(coordinator.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
            coordinator.checkForUpdates()
        }
        .disabled(coordinator.isCheckingForUpdates)
        Button("Preferences…") {}
            .disabled(true)  // settings UI lands in a later phase
        Button("About Photonz") { coordinator.showAbout() }

        Divider()

        Button("Quit Photonz") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
