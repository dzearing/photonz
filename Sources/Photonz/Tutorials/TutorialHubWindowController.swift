import AppKit
import PhotonzCore
import SwiftUI

/// Hosts the Tutorials window. One instance, reused: opening it again from the
/// menu brings the window forward instead of stacking copies.
///
/// The same shape as the Experiments window (`ExperimentsWindowController`) on
/// purpose. This is a place you sit in and read, so it is an ordinary titled
/// window rather than a floating panel, it works with no editor open, and the
/// menu-bar agent owns it. The app already has exactly three kinds of window
/// surface, and this is the third one again rather than a fourth.
@MainActor
final class TutorialHubWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(coordinator: AppCoordinator) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = TutorialHubView(coordinator: coordinator) { [weak self] in self?.dismiss() }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = TutorialHubModel.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(CGSize(width: 560, height: 560))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// Starting a guide closes the hub. A guide points at a control in the
    /// editor window, and a window sitting in front of that control is the one
    /// thing a walkthrough cannot survive.
    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
