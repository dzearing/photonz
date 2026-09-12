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

    /// The guide the Help menu's own row runs.
    static var tour: TutorialGuide? { TutorialCatalog.guide(id: TutorialCatalog.tourID) }
}
