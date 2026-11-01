import Foundation
import PhotonzCore

// MARK: - Skew & distort (`next-transform-modes`)
//
// The chip's middle mode reshapes the picture itself (`LayerReshape.swift`,
// the canvas side in `CanvasSelectionGrips`). The drag previews live and lets
// go in one undo step; Edit ▸ Transform ▸ Skew, Distort and Keystone put the
// picked layer's grips in the mode.

extension EditorState {

    /// An ask from the menu for the picked layer's grips to switch mode. Each
    /// new token is one ask; the canvas acts on a token once.
    struct TransformModeRequest: Equatable, Sendable {
        let layerID: UUID
        let mode: TransformMode
        let keystone: Bool
        let token: Int
    }

    /// Whether Skew, Distort and Keystone have a layer to reshape.
    var canReshapePicked: Bool {
        guard Experiments.shared.transformModesEnabled, activeTool == .select, let id = pickedLayerID,
              let layer = document?.layer(id: id), !layer.isLocked else { return false }
        return layer.canBeReshaped
    }

    /// Whether Turn in 3D has a layer to put in 3D.
    var canTurnPickedIn3D: Bool {
        guard Experiments.shared.transformModesEnabled, Experiments.shared.turnInDepthEnabled,
              activeTool == .select, let id = pickedLayerID,
              let layer = document?.layer(id: id) else { return false }
        return !layer.isLocked && !layer.isSoundOnly
    }

    /// Edit ▸ Transform ▸ Skew, Distort, Keystone or Turn in 3D.
    func askForTransformMode(_ mode: TransformMode, keystone: Bool) {
        let allowed = switch mode {
        case .size: pickedLayerID != nil
        case .reshape: canReshapePicked
        case .space: canTurnPickedIn3D
        }
        guard allowed, let id = pickedLayerID else { return }
        transformModeRequestCount += 1
        transformModeRequest = TransformModeRequest(layerID: id, mode: mode, keystone: keystone,
                                                    token: transformModeRequestCount)
    }

    /// A reshape in the hand: the picture follows the pointer.
    func previewLayerReshape(id: UUID, _ reshape: LayerReshape?) {
        if dragPreview?.layerID == id { discardDragPreview() }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0.reshape = Self.stored(reshape) }
        submit(doc)
    }

    /// ...and let go: ONE undo step. Committing the reshape the drag started
    /// from is a no-op that puts the picture back (how Escape cancels).
    func commitLayerReshape(id: UUID, _ reshape: LayerReshape?) {
        perform { $0.updateLayer(id: id) { $0.reshape = Self.stored(reshape) } }
    }

    /// No reshape is stored as none, so a layer reshaped and put back writes
    /// what it wrote before.
    private static func stored(_ reshape: LayerReshape?) -> LayerReshape? {
        guard let reshape, !reshape.isNone else { return nil }
        return reshape
    }
}
