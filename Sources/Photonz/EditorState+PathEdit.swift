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
        doc.holdingTurnedPivots(above: id) {
            $0.updateLayer(id: id) { $0 = PathBuilder.refit($0, content: content) }
        }
        // The box the shape occupies RIGHT NOW, in the one place everything
        // that reads a live box already looks. `submit` renders without
        // touching `document`, so without this the app holds the shape as it
        // was before the press for the whole gesture, and the Position and Size
        // fields sat on the pre-drag numbers and jumped on release — reproduced
        // 2026-09-15 with the canvas reading 420 × 320 under the pointer while
        // the panel beside it still said 300 × 200.
        if let box = doc.canvasBounds(of: id) { previewMoves = [id: box] }
        submit(doc)
    }

    /// Letting go: ONE undo step for the whole drag, however many frames of it
    /// were drawn on the way.
    func commitPath(_ id: UUID, _ content: PathContent) {
        // The document is about to hold the real shape, so the stand-in goes.
        previewMoves = [:]
        discardDragPreview()
        // A card on a slant swings about the middle of the box its contents
        // make, so reshaping one piece inside it would walk every other piece
        // a few points across the screen. Held, the same way a move or a
        // resize inside a turned card already is (`holdingTurnedPivots`).
        perform {
            $0.holdingTurnedPivots(above: id) {
                $0.updateLayer(id: id) { $0 = PathBuilder.refit($0, content: content) }
            }
        }
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
    /// (`CanvasNSView.editablePath`). A TURNED path counts like any other: it
    /// shows its points and reshapes the same way, so the chip says the same
    /// things about it.
    private var pathEditChipLayer: Layer? {
        guard pathEditChipIsAllowed,
              let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
              layer.path != nil, !layer.isLocked else { return nil }
        return layer
    }

    /// Whether the chip may be up at all: a release that can reshape a path,
    /// and a hand on a tool that shows points.
    private var pathEditChipIsAllowed: Bool {
        Experiments.shared.reshapePathEnabled
            && (activeTool == .select || (activeTool == .pen && Experiments.shared.penEnabled))
    }

    /// The line on the chip under the canvas while a path's points are on show.
    /// Live state, never in the document.
    var pathEditHintText: String {
        // A line left behind by a join or a close speaks for the SELECTION,
        // and a join is only ever asked for with two or more paths picked —
        // which means no single primary pick, which meant no chip, which meant
        // "Nothing joined: no two ends are within 2 pt of each other" could
        // never be read by anybody. Asking Join Paths on two runs that do not
        // meet then did nothing and said nothing, which is the one thing the
        // command promised not to do (`join-two-pen-paths-walk`, 2026-09-20).
        guard pathEditChipLayer != nil else {
            return turnedIntoPathNotice ?? PathEditHint.opening
        }
        // A shape that has JUST been turned says so first, because the question
        // that would have said it can be silenced and then nothing does.
        if let turnedIntoPathNotice { return turnedIntoPathNotice }
        return pathEditHint
            ?? PathEditHint.line(picked: 0, penInHand: activeTool == .pen)
    }

    /// Whether that chip is up: a path picked, with Select or the Pen in hand,
    /// in a release that can reshape one.
    var showsPathEditHint: Bool {
        pathEditChipLayer != nil || (pathEditChipIsAllowed && turnedIntoPathNotice != nil)
    }
}
