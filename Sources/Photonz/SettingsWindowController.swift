import AppKit
import Observation
import PhotonzCore
import SwiftUI

/// Hosts the Settings window. One instance, reused: asking for it again brings
/// the window you already have forward instead of stacking copies, the same way
/// the Experiments window behaves.
///
/// A real window rather than a sheet, because it has to open with no document
/// on screen: the app spends most of its life as a menu-bar agent with no
/// editor window at all, and that is exactly the state somebody is in when they
/// go looking for a setting.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(store: SilencedQuestions, shortcuts: @escaping () -> [CaptureShortcutReport.Row],
                 at section: SettingsSection? = nil) {
        AppFront.activate()
        if let section { SettingsJump.shared.go(to: section) }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsDialog(store: store, shortcuts: shortcuts))
        let window = NSWindow(contentViewController: hosting)
        window.title = SettingsWindowModel.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Tall enough from Ask for its whole list of models.
        window.setContentSize(CGSize(width: 520, height: section == .ask ? 620 : 560))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// A part of the Settings page that can be opened straight to.
enum SettingsSection: String, Hashable {
    case ask
}

/// Asks the Settings page to bring a section to the top, whether the window
/// is new or already open.
@MainActor
@Observable
final class SettingsJump {
    static let shared = SettingsJump()
    private(set) var section: SettingsSection?
    private(set) var pass = 0

    func go(to section: SettingsSection) {
        self.section = section
        pass &+= 1
    }

    /// The page is there: a later ⌘, opens at the top as usual.
    func landed() { section = nil }
}
