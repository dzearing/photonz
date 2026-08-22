import AppKit
import SwiftUI

/// Hosts the Experiments window. One instance, reused: reopening from the menu
/// brings the existing window forward instead of stacking copies.
///
/// A real window rather than a floating panel, because Experiments is a place
/// you sit in and read, not a heads-up overlay. It has to work with no editor
/// window open, so the menu-bar agent owns it.
@MainActor
final class ExperimentsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(experiments: Experiments = .shared) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: ExperimentsDialog(experiments: experiments))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Experiments"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(CGSize(width: 560, height: 640))
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
