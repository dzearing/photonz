import Foundation
import PhotonzCore

// Reshaping a path (Next, `next-reshape-a-path`): the editor's side of dragging
// an anchor, pulling a handle, adding a point and taking one out.
//
// Every decision about WHAT the new shape is belongs to `PathContent` in
// PhotonzCore, tested there. This file only puts the answer in the document:
// live while the pointer is down, and once through `History.perform` when it
// comes up, so a whole drag is one step back.

extension EditorState {

    /// The shape under the hand, drawn but not recorded. The same live/commit
    /// pair a corner-radius pull uses: the picture follows the pointer and the
    /// history stack stays empty until the drag ends.
    func previewPath(_ id: UUID, _ content: PathContent) {
        guard var doc = document else { return }
        discardDragPreview()
        doc.updateLayer(id: id) { $0 = PathBuilder.refit($0, content: content) }
        submit(doc)
    }

    /// Letting go: ONE undo step for the whole drag, however many frames of it
    /// were drawn on the way.
    func commitPath(_ id: UUID, _ content: PathContent) {
        discardDragPreview()
        perform { $0.updateLayer(id: id) { $0 = PathBuilder.refit($0, content: content) } }
    }

    /// The line on the chip under the canvas while a path's points are on show.
    /// Live state, never in the document.
    var pathEditHintText: String {
        pathEditHint ?? PathEditHint.opening
    }

    /// Whether that chip is up: a path picked, with the Select tool in hand,
    /// in a release that can reshape one.
    ///
    /// Asked of the DOCUMENT rather than waiting to be told, so the chip is up
    /// the moment a path is picked — which is the moment somebody needs to be
    /// told that the dots on it can be dragged at all.
    var showsPathEditHint: Bool {
        guard Experiments.shared.reshapePathEnabled, activeTool == .select,
              let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
              layer.path != nil, !layer.isLocked, layer.transform.isIdentity else {
            return false
        }
        return true
    }
}

/// What the chip under the canvas says while a path's points are showing.
///
/// Three gestures decide whether this feels like a drawing app or like a
/// puzzle, and none of them is guessable: double click to add a point, double
/// click a point to curve it, Option to break a point's two sides apart. The
/// chip says the one that applies to what is picked right now rather than
/// listing all three at once.
enum PathEditHint {

    /// What the chip is called while a path's points are showing.
    static let title = "Path"

    static let opening = "Drag a point to reshape. Double click a point to curve it, "
        + "or the outline to add one."

    static let pointPicked = "Drag a lever to bend the curve. "
        + "Option drag frees the two sides, Delete takes the point out."

    static let severalPicked = "Arrow keys nudge the points you picked. "
        + "Delete takes them out."

    /// The line for a path with `picked` of its points selected.
    static func line(picked: Int) -> String {
        switch picked {
        case 0: opening
        case 1: pointPicked
        default: severalPicked
        }
    }
}
