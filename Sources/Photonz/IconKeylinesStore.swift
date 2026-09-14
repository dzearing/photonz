import Foundation
import Observation
import PhotonzCore

/// Whether icon frames draw the space an icon has to live inside (Next,
/// `next-icon-frames`).
///
/// The guides are a view preference, not document content, so there is exactly
/// one switch for them: turn them off on one icon and every other icon, in
/// every window, in every document, is off too, and it is still off after a
/// relaunch. That is what "the choice sticks between frames" means — you are
/// saying how you like to draw, not decorating one frame.
///
/// Same shape as `CanvasGridStore`, for the same reason, and reached the same
/// way: `EditorState.iconKeylinesShowing` is the door every view and menu uses.
@MainActor
@Observable
final class IconKeylinesStore {
    static let shared = IconKeylinesStore()
    static let defaultsKey = "icon.keylines.visible"

    /// On until somebody turns it off. An icon frame that showed nothing until
    /// a menu was found would be the blank square this feature exists to fix.
    var isVisible: Bool {
        didSet {
            guard isVisible != oldValue else { return }
            UserDefaults.standard.set(isVisible, forKey: Self.defaultsKey)
        }
    }

    private init() {
        isVisible = Self.stored()
    }

    /// Reads the setting back off disk. Only a scripted walk asking to forget
    /// it needs this: it wipes the setting after the app has already read it.
    func reload() { isVisible = Self.stored() }

    private static func stored() -> Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }
}
