import Foundation
import PhotonzCore

// MARK: - Flip Horizontal and Flip Vertical (Next flag `next-flip-layers`)

extension EditorState {

    /// Whether Flip Horizontal and Flip Vertical are offered at all.
    var offersFlip: Bool { Experiments.shared.flipLayersEnabled }

    /// Whether Edit ▸ Transform ▸ Flip would do anything to the picked layers.
    var canFlipSelection: Bool { canFlip(ids: actionableLayerIDs) }

    /// Whether the right-click menu's rows have something to flip: the whole
    /// selection when the clicked layer is in it, else that layer alone.
    func canFlipRow(id: UUID) -> Bool { canFlip(ids: rowMenuTargets(id)) }

    /// Edit ▸ Transform ▸ Flip: the picked layers mirrored in place, one about
    /// its own middle and several about their shared middle, in one undo step
    /// (`LayerFlip.swift`).
    func flipSelection(_ axis: FlipAxis) { flip(ids: actionableLayerIDs, axis) }

    /// The right-click menu's Flip rows, on the same targets as every other
    /// row there.
    func flipRow(id: UUID, _ axis: FlipAxis) { flip(ids: rowMenuTargets(id), axis) }

    private func canFlip(ids: Set<UUID>) -> Bool {
        guard offersFlip, let document else { return false }
        return document.canFlip(ids: ids)
    }

    private func flip(ids: Set<UUID>, _ axis: FlipAxis) {
        guard canFlip(ids: ids) else { return }
        discardDragPreview()
        perform { _ = $0.flip(ids: ids, axis) }
    }
}
