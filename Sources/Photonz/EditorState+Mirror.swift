import Foundation
import PhotonzCore

// MARK: - Mirror Across Center (Next flag `next-mirror-across-center`)

extension EditorState {

    /// Whether Mirror Across Center is offered here at all. Never on a
    /// document with time: there ⇧⌘M is Go to Previous Marker, and a copy of a
    /// moving layer would carry its movement unreflected.
    var offersMirrorAcrossCenter: Bool {
        Experiments.shared.mirrorAcrossCenterEnabled && !documentHasTime
    }

    /// Whether Layer ▸ Mirror Across Center would do anything to the picked
    /// layers.
    var canMirrorSelectionAcrossCenter: Bool { canMirror(ids: actionableLayerIDs) }

    /// Whether the right-click menu's row has something to mirror: the whole
    /// selection when the clicked layer is in it, else that layer alone.
    func canMirrorRowAcrossCenter(id: UUID) -> Bool { canMirror(ids: rowMenuTargets(id)) }

    /// Layer ▸ Mirror Across Center (⇧⌘M): copies the picked layers reflected
    /// about the middle of their frame, in one undo step, and picks the copies,
    /// so the next nudge or colour change lands on the half just made.
    func mirrorSelectionAcrossCenter() { mirror(ids: actionableLayerIDs) }

    /// The right-click menu's Mirror Across Center, on the same targets as
    /// every other row there.
    func mirrorRowAcrossCenter(id: UUID) { mirror(ids: rowMenuTargets(id)) }

    private func canMirror(ids: Set<UUID>) -> Bool {
        guard offersMirrorAcrossCenter, let document else { return false }
        return document.canMirrorAcrossCenter(ids: ids)
    }

    private func mirror(ids: Set<UUID>) {
        guard canMirror(ids: ids) else { return }
        discardDragPreview()
        var made: [UUID] = []
        perform { made = $0.mirrorAcrossCenter(ids: ids) }
        guard !made.isEmpty else { return }
        selectLayers(Set(made))
    }
}
