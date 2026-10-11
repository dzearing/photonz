import Foundation
import PhotonzCore

/// Turning layers in space by hand, and the camera they are seen through
/// (Next, `next-turn-in-depth`; `SpaceEditing.swift`, `video-depth.html`).
///
/// A thin layer over the model, like the key diamonds': every change goes
/// through `perform`, so a drag, a typed number, a nudge or a menu row is one
/// step to undo.
extension EditorState {

    // MARK: What the 3D rows speak for

    /// The picked layers the 3D section speaks for: every unlocked one that
    /// draws something, the same set the Effects rows speak for.
    var spaceTargetIDs: [UUID] {
        guard Experiments.shared.turnInDepthEnabled, let document else { return [] }
        return colorStyleTargetIDs.filter { id in
            guard let layer = document.layer(id: id) else { return false }
            return !layer.isLocked && !layer.isSoundOnly
        }
    }

    /// Whether the panel shows its 3D section: in a document that runs over
    /// time, where titles and clips are animated, or once a picked layer in
    /// a still picture has actually been turned (by the knob's arcs). A
    /// marked-up screenshot keeps the panel it always had.
    var showsSpaceSection: Bool {
        let ids = spaceTargetIDs
        guard !ids.isEmpty, let document else { return false }
        if documentHasTime { return true }
        return ids.contains { document.layer(id: $0)?.turn3D != nil }
    }

    /// One of the four values, as every picked layer shows it at the
    /// playhead; nil where they differ (the row says Mixed). Follows a canvas
    /// drag in flight, so the panel moves with the hand.
    func spaceValue(_ property: MotionProperty) -> Double? {
        guard let document else { return nil }
        let ids = spaceTargetIDs
        if let live = spaceTurnPreview, ids == [live.id] { return live.turn.value(property) }
        return document.sharedSpaceValue(property, layerIDs: ids, atDocumentTimeMS: documentTimeMS)
    }

    /// Whether any picked layer is turned about X or Y at the playhead: the
    /// Pivot depth row only shows then, because on a flat layer it has
    /// nothing to do.
    var spaceSelectionIsTurned: Bool {
        guard let document else { return false }
        if let live = spaceTurnPreview, spaceTargetIDs == [live.id] {
            return live.turn.rotationX != 0 || live.turn.rotationY != 0
        }
        return spaceTargetIDs.contains { id in
            let turn = document.shownSpaceTurn(layerID: id, atDocumentTimeMS: documentTimeMS)
            return turn.rotationX != 0 || turn.rotationY != 0
        }
    }

    /// A number typed into a 3D row: every picked layer takes it.
    func setSpaceValue(_ property: MotionProperty, _ value: Double) {
        let ids = spaceTargetIDs
        guard !ids.isEmpty else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        if documentHasTime { activeKeyProperty = .motion(property) }
        perform { $0.setSpaceValue(property, value, layerIDs: ids, atDocumentTimeMS: time, ease: ease) }
    }

    /// An arrow key on a 3D row: each picked layer steps from its own value,
    /// so Mixed stays mixed and every layer moves by the same amount.
    func nudgeSpaceValue(_ property: MotionProperty, by step: Double) {
        guard let document else { return }
        let ids = spaceTargetIDs
        guard !ids.isEmpty else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        let from = ids.map { (id: $0, value: document.spaceValue(property, layerID: $0, atDocumentTimeMS: time)) }
        perform { doc in
            for item in from {
                guard let value = item.value else { continue }
                doc.setSpaceValue(property, value + step, layerIDs: [item.id], atDocumentTimeMS: time, ease: ease)
            }
        }
    }

    // MARK: The canvas

    /// A 3D handle being dragged: the picture follows, nothing is recorded.
    func previewSpaceTurn(id: UUID, _ turn: LayerTurn3D) {
        guard var doc = document else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        doc.setSpaceTurn(turn, layerID: id, atDocumentTimeMS: time, ease: ease)
        spaceTurnPreview = (id, turn)
        submit(doc)
    }

    /// ...and let go: ONE undo step, a key at the playhead where the value is
    /// keyed.
    func commitSpaceTurn(id: UUID, _ turn: LayerTurn3D) {
        spaceTurnPreview = nil
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        perform { $0.setSpaceTurn(turn, layerID: id, atDocumentTimeMS: time, ease: ease) }
    }

    // MARK: The Layer menu and the right click

    /// Whether Reset 3D Rotation has anything to put back.
    var canResetSpaceRotation: Bool {
        guard let document else { return false }
        return document.hasSpaceRotation(layerIDs: spaceTargetIDs)
    }

    /// Layer, Reset 3D Rotation.
    func resetSpaceRotation(ids given: [UUID]? = nil) {
        let ids = given ?? spaceTargetIDs
        guard let document, document.hasSpaceRotation(layerIDs: ids) else { return }
        perform { $0.resetSpaceRotation(layerIDs: ids) }
    }

    /// Whether Bring Nearer and Send Further have a layer to move.
    var canPushDepth: Bool { !spaceTargetIDs.isEmpty }

    /// The layers a right click on a layer's row or picture turns: the whole
    /// selection when it is part of it, else that layer (`rowMenuTargets`).
    func spaceRowTargets(_ id: UUID) -> [UUID] {
        guard Experiments.shared.turnInDepthEnabled, let document else { return [] }
        let picked = rowMenuTargets(id)
        return document.allLayerIDs.filter { picked.contains($0) }.filter { id in
            guard let layer = document.layer(id: id) else { return false }
            return !layer.isLocked && !layer.isSoundOnly
        }
    }

    /// Layer, Bring Nearer (⌥⌘]) and Send Further (⌥⌘[).
    func pushDepth(nearer: Bool, ids given: [UUID]? = nil) {
        let ids = given ?? spaceTargetIDs
        guard !ids.isEmpty else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        let step = nearer ? PhotonzDocument.depthStep : -PhotonzDocument.depthStep
        perform { $0.pushDepth(by: step, layerIDs: ids, atDocumentTimeMS: time, ease: ease) }
    }

    // MARK: The camera

    /// Whether the panel shows the frame's Camera section: the canvas itself
    /// is picked, in a document that runs over time or has something turned
    /// in space. A marked-up screenshot never shows it.
    var showsCameraSection: Bool {
        guard Experiments.shared.turnInDepthEnabled, isCanvasSelected, let document else { return false }
        return documentHasTime || document.isSeenInSpace || document.hasCameraChanges
    }

    func cameraValue(_ property: MotionProperty) -> Double? {
        document?.cameraValue(property, atDocumentTimeMS: documentTimeMS)
    }

    func setCameraValue(_ property: MotionProperty, _ value: Double) {
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        perform { $0.setCameraValue(property, value, atDocumentTimeMS: time, ease: ease) }
    }

    func cameraKeyDiamond(_ property: MotionProperty) -> KeyDiamond {
        document?.cameraKeyDiamond(property, atDocumentTimeMS: documentTimeMS) ?? .dormant
    }

    func toggleCameraKey(_ property: MotionProperty) {
        guard documentHasTime else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        perform { $0.toggleCameraKey(property, atDocumentTimeMS: time, ease: ease) }
    }

    /// Whether View, Reset Camera has anything to put back.
    var canResetCamera: Bool { document?.hasCameraChanges ?? false }

    /// View, Reset Camera.
    func resetCamera() {
        guard canResetCamera else { return }
        perform { $0.resetCamera() }
    }

    /// View, Show Camera Settings: picks the frame, so the panel shows its
    /// Camera section.
    func showCameraSettings() {
        selectCanvas()
    }
}

extension LayerTurn3D {
    /// One of the four values, by name.
    func value(_ property: MotionProperty) -> Double? {
        switch property {
        case .rotationX: rotationX
        case .rotationY: rotationY
        case .depth: depth
        case .pivotDepth: pivotDepth
        default: nil
        }
    }
}
