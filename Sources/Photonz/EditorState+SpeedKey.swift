import Foundation
import PhotonzCore

/// **⌘R**, Premiere's Speed/Duration: the speeds of the piece in hand, opened
/// where they already live, the panel's Time section.
///
/// No dialog of its own. The panel's Speed dropdown is the one list of speeds,
/// so the key brings the panel out if it was put away, opens a folded Time
/// section, and drops that list open. A held frame
/// has no speed, so its Hold list opens instead, which is what Premiere's
/// Speed/Duration does to a still: sets how long it lasts.
extension EditorState {

    /// Whether there is a piece for ⌘R to open the speeds of. The Clip menu
    /// row reads this, the same rule the Time section is offered by.
    var canOpenClipSpeed: Bool { canRetimeAClip }

    /// Open the speeds of the piece in hand, or say what the key needs. False
    /// where a clip has no speed to set at all (retiming switched off), so
    /// the press goes on to whatever would have had it.
    @discardableResult
    func openClipSpeed() -> Bool {
        guard Experiments.shared.cutRecordingEnabled else { return false }
        guard canOpenClipSpeed, let id = clipInHandID, let index = clipPieceInHand else {
            raiseCanvasNotice(.speedNeedsAClip)
            return true
        }
        // The piece the list will change is the one lit on the timeline, so
        // the playhead's piece is picked rather than only meant.
        selectClipPiece(layerID: id, index: index)
        if !isInspectorShown { setInspectorVisible(true) }
        pendingClipSpeedChoices = true
        // An ask no dropdown took (the piece changed under it) must not open
        // a list later, out of nowhere, so it lapses.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.pendingClipSpeedChoices = false
        }
        return true
    }

    /// The dropdown has opened, or found it could not.
    func clipSpeedChoicesOpened() { pendingClipSpeedChoices = false }
}
