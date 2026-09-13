import Foundation
import PhotonzCore

// The Pen's side of the editor (Next, `next-pen`): a finished path becomes one
// layer, and the chip under the canvas says what to do next.

extension EditorState {

    /// A path the Pen finished, in document coordinates. One undo step for the
    /// whole drawing, however many anchors went into it, then the tool hands
    /// back to Select with the new layer picked — the same ending every other
    /// drawing tool has.
    func addPath(_ content: PathContent) {
        guard content.anchors.count >= 2 else { return }
        let layer = PenSession.layer(from: content)
        perform { $0.addLayerDrawnOnFrame(layer) }
        finishCreating(layer.id)
    }

    /// The line on the chip under the canvas while the Pen is in hand. Live
    /// state, never in the document.
    var penHintText: String {
        penHint ?? PenSession.hint(for: PenSession())
    }

    /// Whether that chip is up: only with the Pen in hand, and only in a
    /// release that has a Pen.
    var showsPenHint: Bool {
        Experiments.shared.penEnabled && activeTool == .pen
    }
}
