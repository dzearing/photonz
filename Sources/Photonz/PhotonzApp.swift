import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

@main
struct PhotonzApp: App {
    /// The resident menu-bar agent. Owns capture, hotkeys, history, and the
    /// window registry; survives with zero editor windows open (phase 11.1).
    @State private var coordinator: AppCoordinator
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // The document model measures text — a box around words has to know how
        // tall the words are — and it is pure, so CoreText's answer is handed
        // in here, once, before any document exists.
        TextMeasurement.use { text, maxWidth in
            TextRasterizer.naturalSize(text, maxWidth: maxWidth)
        }
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
                // A low floor on purpose: the responsive chrome (toolbar
                // overflow, inspector auto-collapse) must kick in ABOVE this,
                // since people resize to arbitrary sizes, not just the minimum.
                .frame(minWidth: EditorChromeLayout.minWindowWidth,
                       minHeight: EditorChromeLayout.minWindowHeight)
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
        MainActor.assumeIsolated {
            AppDelegate.coordinator?.start()
            #if PHOTONZ_PLAYTEST
            // Non-shipping builds only; the probe alone acts on either of these.
            ProbeGrants.recordOnLaunch()
            CaptureDiag.runIfRequested()
            if let coordinator = AppDelegate.coordinator {
                PlaytestHarness.startIfRequested(coordinator: coordinator)
            }
            #endif
        }
    }

    /// Resident agent: closing the last editor window must NOT quit. Only the
    /// menu's Quit (NSApplication.terminate) ends the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Self-update hand-off: once the new bundle is swapped in and the app is
    /// really quitting, spawn a detached relauncher. Living here (not in the
    /// update flow) means a user-cancelled quit never spawns a stray reopen.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let path = AppDelegate.coordinator?.pendingRelaunchBundlePath else { return }
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
            relauncher.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(path)\""]
            try? relauncher.run()
        }
    }

    /// ⌘Q with unsaved editor windows gets the standard quit protection:
    /// review each window's save sheet, discard everything, or cancel.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let dirty = CloseGuards.dirtyEditorWindows()
            guard !dirty.isEmpty else { return .terminateNow }
            // The agent may be quitting from the (non-activating) menu-bar menu;
            // the alert needs the app frontmost to be seen.
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = dirty.count == 1
                ? "You have a window with unsaved changes."
                : "You have \(dirty.count) windows with unsaved changes."
            alert.informativeText = "Review your changes before quitting, or discard them."
            alert.addButton(withTitle: "Review Changes…")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard Changes and Quit")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                CloseGuards.reviewAndClose(windows: dirty) { allResolved in
                    // A cancelled review keeps the app alive — a later,
                    // unrelated Quit must not fire a stale update-relaunch.
                    if !allResolved { AppDelegate.coordinator?.pendingRelaunchBundlePath = nil }
                    NSApp.reply(toApplicationShouldTerminate: allResolved)
                }
                return .terminateLater
            case .alertThirdButtonReturn:
                return .terminateNow
            default:
                AppDelegate.coordinator?.pendingRelaunchBundlePath = nil
                return .terminateCancel
            }
        }
    }
}

/// Root of an editor window. A `.video` id opens the in-app video editor with
/// its own `VideoEditorState`; every other id opens the image editor. Branching
/// up front keeps `EditorState` image-pure (no AVFoundation) and gives each
/// surface its own focused-scene value for the menu commands.
///
/// Which version of those roots you get is the running release's call, so both
/// go through `ReleaseExperience` rather than being named directly.
struct EditorRootView: View {
    let windowID: EditorWindowID?
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        if case .video(let url) = windowID {
            ReleaseExperience.videoEditor(url: url)
        } else {
            ReleaseExperience.imageEditor(windowID: windowID)
        }
    }
}

/// The menu-bar icon. Always rendered, so its `.task` is a reliable launch-time
/// hook to capture `openWindow` for the agent (the menu content is lazy). Gains
/// a dot badge when an update is available (17.10).
struct MenuBarLabel: View {
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(updateAvailable: coordinator.availableUpdate != nil))
            .task { coordinator.openWindowAction = { openWindow(value: $0) } }
    }
}


/// The resident agent's status-item drop-down (phase 11.2). Every action works
/// with no editor window open — capture, history, window-spawning, and the
/// updater all route through the `AppCoordinator`. Every item here does
/// something: a menu item that only promises a feature is a dead end, so
/// nothing is listed until it works (Preferences returns when there is a
/// settings window behind it).
struct MenuBarMenu: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        // Capture
        Button("Capture Region") { coordinator.capture.beginRectCapture() }
            .keyboardShortcut("4", modifiers: [.command, .shift])
        Button("Capture Full Screen") { coordinator.capture.captureFullScreen() }
            .keyboardShortcut("3", modifiers: [.command, .shift])
        Button(coordinator.capture.isRecording ? "Stop Recording" : "Record Screen / Video…") {
            coordinator.capture.toggleRecording()
        }
        .keyboardShortcut("5", modifiers: [.command, .shift])

        Divider()

        // History. Edit Last Capture is the keyboard path from a capture to
        // its editor once the toast has faded (a recording opens the video
        // editor); the shortcut is also a global hotkey (CaptureCenter).
        Button("Edit Last Capture") { coordinator.editLastCapture() }
            .keyboardShortcut("6", modifiers: [.command, .shift])
            .disabled(coordinator.lastCapture == nil)
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
        if let update = coordinator.availableUpdate {
            // One click: download, verify, swap the bundle, relaunch (17.10).
            Button(coordinator.updateStatus ?? "Update to v\(update) & Restart") {
                coordinator.installAvailableUpdate()
            }
            .disabled(coordinator.updateStatus != nil)
        }
        Button(coordinator.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
            coordinator.checkForUpdates()
        }
        .disabled(coordinator.isCheckingForUpdates)
        Button("Welcome & Permissions…") { coordinator.showWelcome() }
        Button("Experiments…") { coordinator.showExperiments() }
        Button("About \(AppInfo.name)") { coordinator.showAbout() }

        Divider()

        Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
