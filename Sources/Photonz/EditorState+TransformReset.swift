import Foundation
import PhotonzCore

// MARK: - Reset each transform mode on its own (`next-transform-modes`)
//
// Right-click a mode on the selection chip, or Edit ▸ Transform: Reset Size,
// Reset Skew & Distort, Reset 3D and Reset All, each one undo step, each
// greyed when it has nothing to put back. What each puts back is
// `TransformReset.swift` in PhotonzCore; the chip's dot reads the same answer.

extension EditorState {

    /// The layers a reset row acts on: the picked ones, less any locked one
    /// or a sound with nothing to draw.
    var transformResetTargetIDs: [UUID] {
        guard Experiments.shared.transformModesEnabled, let document else { return [] }
        return colorStyleTargetIDs.filter { id in
            guard let layer = document.layer(id: id) else { return false }
            return !layer.isLocked && !layer.isSoundOnly
        }
    }

    /// Whether `reset` has anything to put back on `ids` (the picked layers
    /// when nil).
    func canResetTransform(_ reset: TransformReset, ids given: [UUID]? = nil) -> Bool {
        guard let document else { return false }
        return (given ?? transformResetTargetIDs).contains { document.hasTransformChange(reset, layerID: $0) }
    }

    /// Puts `reset` back on `ids` (the picked layers when nil), in one undo
    /// step. Says so on the tag under the selection for a moment.
    func resetTransform(_ reset: TransformReset, ids given: [UUID]? = nil) {
        let ids = given ?? transformResetTargetIDs
        guard canResetTransform(reset, ids: ids) else { return }
        discardDragPreview()
        previewMoves = [:]
        previewRotations = [:]
        spaceTurnPreview = nil
        perform { $0.resetTransform(reset, layerIDs: ids) }
        transformResetSaid = TransformResetSaid(words: reset == .all ? "Reset all" : reset.title,
                                                token: (transformResetSaid?.token ?? 0) + 1)
    }

    /// The words the tag under the selection shows for a moment after a
    /// reset: the prototype's "Reset Size" hint. A new token is a new reset.
    struct TransformResetSaid: Equatable, Sendable {
        let words: String
        let token: Int
    }
}
