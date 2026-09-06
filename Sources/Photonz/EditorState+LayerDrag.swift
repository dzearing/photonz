import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Dragging a layer on the canvas: option-drag to leave the original
// behind, and the frame, transform and endpoints a drag hands back.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: ⌥-drag: leave the original, carry a copy

    /// Live ⌥-drag from the canvas: every original stays exactly where it is
    /// and a copy of each travels with the pointer.
    ///
    /// Nothing is recorded here. The whole gesture lands as ONE undo step on
    /// mouse-up (`commitCopyDrag`), which is what makes a cancelled drag, or a
    /// press that never left the click tolerance, cost nothing at all — there
    /// is no half-made copy to take back.
    ///
    /// There is no floated sprite on purpose. A sprite is one layer lifted off
    /// a picture that HIDES it, and a copy drag needs the picture whole with
    /// the original still in it, so the composite re-renders per move the way a
    /// multi-selection drag already does.
    func previewCopyDrag(_ origins: [UUID: CGPoint]) {
        guard !origins.isEmpty, var doc = document else { return }
        // The rubber band that picked these described where they WERE, and it
        // is about to stop being the truth — same rule as a multi-drag.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        if dragPreview != nil { discardDragPreview() }
        // The numbers, the outline and the handles follow the COPY, even though
        // the copy has no id yet and the selection is still the original. The
        // copy is the thing under the pointer and the thing that will be
        // selected the moment you let go, so X and Y reading the original's
        // resting place would be the inspector describing something nobody is
        // touching. The copy is the same size in the same parent, so the
        // original's own box is all that is needed to say where it is.
        previewMoves = origins.reduce(into: [:]) { frames, move in
            guard let size = doc.canvasBounds(of: move.key)?.size else { return }
            frames[move.key] = CGRect(origin: move.value, size: size)
        }
        doc.duplicateLayers(movingCopiesTo: origins)
        submit(doc)
    }

    /// Mouse-up on an ⌥-drag: the copies and where they landed go in as ONE
    /// undo step, so one ⌘Z leaves the document exactly as it was. The copies
    /// become the selection, so a follow-up nudge, restyle or arrange moves
    /// what you just made rather than what you made it from.
    func commitCopyDrag(_ origins: [UUID: CGPoint]) {
        previewMoves = [:]
        guard !origins.isEmpty else { return cancelCopyDrag() }
        discardDragPreview()
        var made: [UUID] = []
        var joined: [UUID] = []
        perform { document in
            made = document.duplicateLayers(movingCopiesTo: origins)
            // A copy dragged onto a screen joins it, exactly as the original
            // would have if it had been the thing that travelled.
            joined = document.adoptMovedLayers(ids: made)
        }
        guard !made.isEmpty else { return }
        revealJoinedScreens(joined)
        selectLayers(Set(made))
    }

    /// Esc, or a press that never travelled far enough to be a drag: nothing
    /// was ever recorded, so the only work is putting the real picture back.
    func cancelCopyDrag() {
        previewMoves = [:]
        discardDragPreview()
        rerender()
    }

    /// Live drag update (move or resize) in the layer's own parent space. With
    /// a CA preview active the canvas already shows the move, so this only
    /// records state; otherwise it renders the new frame without touching
    /// history.
    func previewLayerFrame(id: UUID, frame: CGRect) {
        let origin = document?.parentOrigin(of: id) ?? .zero
        previewMoves = [id: frame.offsetBy(dx: origin.x, dy: origin.y)]
        // A RESIZE (size change) of a layer whose look is sized in fixed points —
        // border/corner-radius/blur/shadow, or annotation strokes, text, callouts,
        // measures — can't be shown by scaling the drag sprite: the stroke would
        // stretch and, once the sprite's padding scales too, the anchored edge
        // would drift. Drop the sprite so the frame re-renders live each move
        // (moves keep their sprite — same-size scaling is faithful). The doc still
        // holds the pre-drag frame while a sprite is active, so a differing size
        // is exactly the resize signal.
        if dragPreview?.layerID == id, let layer = document?.layer(id: id),
           frame.size != layer.frame.size, !layer.resizeScalesUniformly {
            discardDragPreview()
        }
        guard dragPreview?.layerID != id else { return }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0 = $0.resized(to: frame) }
        submit(doc)
    }

    /// Mouse-up: one undoable step from the pre-drag frame to the final one.
    /// Committing back to the original frame is a recognized no-op (History
    /// skips it), which is how an Esc-cancelled drag restores the real render.
    /// `resized(to:)` remaps annotation endpoints so resize scales the shape.
    /// A captioned arrow then re-picks its pill spot: a whole-arrow drag or
    /// nudge that parks the tail at the picture's edge would otherwise carry
    /// the label off the picture, and one dragged back into the open gets its
    /// default spot behind the tail again. Captionless layers pass through.
    func commitLayerFrame(id: UUID, frame: CGRect, joiningScreens: Bool = false) {
        previewMoves = [:]
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        var joined: [UUID] = []
        perform { document in
            let canvas = document.canvasSize
            document.updateLayer(id: id) {
                $0 = AnnotationBuilder.planningCaption(
                    $0.resized(to: frame), canvas: canvas,
                    captionPillSize: $0.measuredCaptionPillSize)
            }
            // In the SAME mutation as the move, so one undo puts the layer back
            // where it was and back in what held it.
            if joiningScreens { joined = document.adoptMovedLayers(ids: [id]) }
        }
        revealJoinedScreens(joined)
    }

    /// After a drop changed what holds a layer, open the screen it went into,
    /// so the layers list shows where it landed instead of losing it in a shut
    /// row. A layer that came OUT is already at the top level and needs
    /// nothing opened.
    func revealJoinedScreens(_ ids: [UUID]) {
        guard !ids.isEmpty, let document else { return }
        for id in ids { expandedGroupIDs.formUnion(document.ancestorIDs(of: id)) }
    }

    /// Live rotate/skew update. With a CA preview active the canvas applies
    /// the transform to the floated sprite, so this only renders when the
    /// preview pieces haven't landed yet.
    func previewLayerTransform(id: UUID, transform: LayerTransform) {
        guard dragPreview?.layerID != id else { return }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0.transform = transform }
        submit(doc)
    }

    /// Mouse-up on a rotate/skew drag: one undo step. Committing the original
    /// transform is a History no-op (the Esc-cancel path).
    func commitLayerTransform(id: UUID, transform: LayerTransform) {
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0.transform = transform } }
    }

    /// Endpoint-drag commit from the canvas (document coords, ⇧ already
    /// applied). Rebuilds the layer's frame around the new endpoints in one
    /// undo step; committing the original endpoints is a History no-op (how
    /// an Esc-cancelled endpoint drag restores the real render).
    func commitAnnotationEndpoints(id: UUID, start: CGPoint, end: CGPoint) {
        let start = parentPoint(start, of: id)
        let end = parentPoint(end, of: id)
        previewMoves = [:]
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { document in
            // A moved tail can push the caption off the picture (or free the
            // room it was missing), so the pill re-picks its spot.
            let canvas = document.canvasSize
            document.updateLayer(id: id) {
                $0 = AnnotationBuilder.planningCaption(
                    AnnotationBuilder.updating($0, start: start, end: end), canvas: canvas,
                    captionPillSize: $0.measuredCaptionPillSize)
            }
        }
    }
}
