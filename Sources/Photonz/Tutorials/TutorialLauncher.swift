import AppKit
import PhotonzCore
import SwiftUI

/// How a guide gets started from anywhere in the app: a menu row, the hub
/// window, or a first run offer.
///
/// One rule decides where it runs. A guide that brings a sample picture opens a
/// window of its own and teaches in there, so it never touches what you have
/// open. A guide that teaches something about YOUR document runs over the
/// window you are already in, and says so in its first step.
@MainActor
enum TutorialLauncher {
    /// Windows a guide has opened, so picking the same tutorial twice comes
    /// back to the one already on screen rather than piling up windows.
    private static var windows: [String: EditorWindowID] = [:]

    static func start(_ guide: TutorialGuide, coordinator: AppCoordinator,
                      editor: EditorState?) {
        // A guide already running is closed first: two callouts pointing at two
        // controls is nobody's idea of a walkthrough.
        TutorialController.shared.close()
        guard guide.sample != nil else {
            guard let editor else { return }
            TutorialController.shared.start(guide, in: editor)
            return
        }
        let id = windows[guide.id] ?? .tutorial(UUID(), guide.id)
        windows[guide.id] = id
        coordinator.openWindow(id)
        // A brand new window starts the guide itself as it seeds its sample
        // (`ImageEditorRootView`). Re-opening a window that is ALREADY on
        // screen only focuses it, and nothing seeds, so the guide has to be
        // restarted from here. Either way it picks up the saved place.
        DispatchQueue.main.async {
            guard !TutorialController.shared.isRunning,
                  let open = TutorialController.shared.lastEditor(forGuide: guide.id),
                  open.hostWindow?.isVisible == true
            else { return }
            TutorialController.shared.start(guide, in: open)
        }
    }

    /// The guide the Help menu's own row promotes to the top.
    static var tour: TutorialGuide? { TutorialCatalog.guide(id: TutorialCatalog.tourID) }

    // MARK: - Finding the window a guide would teach in

    /// Every editor window's state while it is alive, so a surface OUTSIDE the
    /// editor (the Tutorials window) can start a guide that teaches over the
    /// picture you have open.
    ///
    /// Held weakly and swept on every read: an editor is owned by its window,
    /// and a registry that kept them alive would keep a closed document's
    /// bitmaps in memory too. The menu rows do not need this (SwiftUI hands
    /// them the focused window's state), but the hub is its own window and by
    /// definition has no focused editor.
    private static var editors: [WeakEditor] = []

    private final class WeakEditor {
        weak var value: EditorState?
        init(_ value: EditorState) { self.value = value }
    }

    /// Called when an editor's canvas lands in a window.
    static func register(_ editor: EditorState) {
        editors.removeAll { $0.value == nil || $0.value === editor }
        editors.append(WeakEditor(editor))
    }

    /// The editor a guide with no sample would run over: the frontmost editor
    /// window, or none when there is no picture open.
    ///
    /// "Frontmost" is read off the window order rather than off the key window,
    /// because the Tutorials window is the key one at the moment this is asked.
    static func frontEditor() -> EditorState? {
        editors.removeAll { $0.value == nil }
        let live = editors.compactMap(\.value).filter { $0.hostWindow?.isVisible == true }
        guard !live.isEmpty else { return nil }
        for window in NSApp.orderedWindows where window.isVisible {
            if let match = live.first(where: { $0.hostWindow === window }) { return match }
        }
        return live.last
    }
}
