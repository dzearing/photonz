import Foundation
import PhotonzCore

// Revert to Original, for a recording opened in the editor
// (`docs/design/video.md` §7).
//
// The small recording window had this too, and there it meant "put back the
// file a save wrote the trim into". In the editor Save never touches the
// recording, so the file on disk is always the original, and the row means
// what File > Revert means in Photoshop: throw every edit away and go back to
// the recording as it opened. It is one step in the history like any other
// edit, so one Command Z brings the edit back.
extension EditorState {

    /// Offered while this window holds a recording and something about it has
    /// changed since it opened. Nothing to go back to is a dimmed row, not a
    /// row that does nothing.
    var canRevertToOriginal: Bool {
        guard recordingURL != nil, let recordingAsOpened, let document else { return false }
        return document != recordingAsOpened
    }

    /// The Video menu's Revert to Original.
    func revertToOriginal() {
        guard canRevertToOriginal, let original = recordingAsOpened else { return }
        // A trim in hand is thrown away first, the way ⎋ throws it away, so
        // the revert does not land under a session laid out for the old clip.
        if trimSession != nil { cancelTrim() }
        pauseDocument()
        perform { $0 = original }
        selectedLayerID = nil
        selectedClipPieceIndex = nil
        // The playhead stays where it was, pulled in if the edit ran longer
        // than the recording does.
        documentTimeMS = max(0, min(documentTimeMS, lastDocumentTimeMS))
        documentMomentChanged()
    }
}
