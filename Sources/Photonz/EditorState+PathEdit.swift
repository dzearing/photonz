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

    /// The picked path layer the chip is about, whatever state it is in, or
    /// nil when no chip belongs on screen.
    ///
    /// Asked of the DOCUMENT rather than waiting to be told, so the chip is up
    /// the moment a path is picked — which is the moment somebody needs to be
    /// told that the dots on it can be dragged at all.
    ///
    /// The PEN counts as well as Select, because pressing P over a finished
    /// path is how somebody reaches for its points to round a corner
    /// (`CanvasNSView.editablePath`). A TURNED path counts too, where it used
    /// to be excluded: it cannot be reshaped, and the chip is the only thing
    /// that can say so instead of leaving the points quietly missing.
    private var pathEditChipLayer: Layer? {
        guard Experiments.shared.reshapePathEnabled,
              activeTool == .select || (activeTool == .pen && Experiments.shared.penEnabled),
              let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
              layer.path != nil, !layer.isLocked else { return nil }
        return layer
    }

    /// The line on the chip under the canvas while a path's points are on show.
    /// Live state, never in the document.
    ///
    /// The turned case is read HERE rather than taken from the canvas, because
    /// a turned path has no points and so the canvas has nothing to announce:
    /// the line it last pushed is about the shape as it was before the turn.
    var pathEditHintText: String {
        guard let layer = pathEditChipLayer else { return PathEditHint.opening }
        guard layer.transform.isIdentity else { return PathEditHint.turned }
        return pathEditHint
            ?? PathEditHint.line(picked: 0, penInHand: activeTool == .pen)
    }

    /// Whether that chip is up: a path picked, with Select or the Pen in hand,
    /// in a release that can reshape one.
    var showsPathEditHint: Bool { pathEditChipLayer != nil }
}
