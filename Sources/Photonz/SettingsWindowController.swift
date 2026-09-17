import AppKit
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

    func present(store: SilencedQuestions) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsDialog(store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = SettingsWindowModel.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(CGSize(width: 520, height: 320))
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
