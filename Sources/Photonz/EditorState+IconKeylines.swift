import CoreGraphics
import Foundation
import PhotonzCore

// The space an icon has to live inside (Next, `next-icon-frames`).
//
// Nothing to set: a frame that is icon sized draws its own live area and its
// own center lines the moment it exists, because its SIZE already says what
// they are. The one switch is View ▸ Show Icon Keylines, and it is a
// preference rather than something a document carries, so it holds across every
// frame and every launch. The arithmetic is `IconKeylines`; the drawing is
// `CanvasIconKeylines.swift`.
extension EditorState {

    /// Whether the guides exist at all in this release.
    var iconKeylinesEnabled: Bool { Experiments.shared.iconFramesEnabled }

    /// Whether an icon frame should be drawing them right now.
    var iconKeylinesShowing: Bool {
        iconKeylinesEnabled && IconKeylinesStore.shared.isVisible
    }

    /// Whether this document holds anything the guides could be drawn on, which
    /// is what dims the menu row: a document of screenshots has no icon in it,
    /// and a switch that plainly does nothing is worse than one that says so.
    var hasIconFrames: Bool {
        iconKeylinesEnabled && (document?.hasIconFrames ?? false)
    }

    func toggleIconKeylines() {
        guard iconKeylinesEnabled else { return }
        IconKeylinesStore.shared.isVisible.toggle()
        // The Icons track waits for them rather than asking and hoping, so the
        // one switch says when it has been thrown.
        if IconKeylinesStore.shared.isVisible {
            TutorialController.shared.note(.keylinesShown, from: self)
        }
    }
}
