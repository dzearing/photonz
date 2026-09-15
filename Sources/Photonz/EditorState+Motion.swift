import Foundation
import PhotonzCore

/// Motion: a layer told to change one of its properties over time
/// (`next-motion`, `LayerMotion.swift`).
///
/// Everything here is a thin layer over the model. Adding, removing, switching
/// and tuning all go through `perform`, so every one of them is a single step
/// for undo, and none of them ever writes a moved layer back into the
/// document: what moves is what the canvas is HANDED, worked out at the moment
/// it is drawn (`displayDocument`).
extension EditorState {

    // MARK: What the section answers for

    /// The layer the Motion list is about.
    ///
    /// ONE layer, unlike Effects, which speaks for everything picked. A motion
    /// carries the layer's own numbers in its From and To — this position, this
    /// angle, this colour — so one row standing for five layers would have to
    /// hold five different pairs of values and could only show one of them.
    /// Pick one thing and the list is about that thing.
    var motionLayer: Layer? {
        guard Experiments.shared.motionEnabled,
              let id = soleLayerID(layerStyleSelection.layerIDs),
              let layer = document?.layer(id: id), !layer.isLocked else { return nil }
        return layer
    }

    /// The entries in the list, top to bottom.
    var motionRows: [LayerMotion] { motionLayer?.motions ?? [] }

    /// What the plus offers: the properties this layer actually has, each with
    /// the value it is wearing right now.
    var motionOffers: [MotionProperty.Offer] {
        guard let motionLayer else { return [] }
        return MotionProperty.offered(for: motionLayer)
    }

    // MARK: The gestures

    /// The plus: one press, one new entry, one undo. It arrives already moving
    /// and the preview starts, so the answer to "did that do anything" is on
    /// screen before you read a single field.
    func addMotion(_ property: MotionProperty) {
        guard let layer = motionLayer,
              !(layer.motions ?? []).contains(where: { $0.property == property }) else { return }
        let motion = LayerMotion.starting(property, on: layer)
        perform { document in
            document.updateLayer(id: layer.id) { $0.motions = ($0.motions ?? []) + [motion] }
        }
        playMotionPreview()
    }

    /// The cross on a row: takes the entry out. Different from the switch
    /// beside it, which keeps every number on it and stops it moving.
    func removeMotion(id: UUID) {
        guard let layer = motionLayer else { return }
        perform { document in
            document.updateLayer(id: layer.id) { $0.motions = ($0.motions ?? []).filter { $0.id != id } }
        }
        stopIfNothingMoves()
    }

    /// One entry, changed. Every field on the row lands through here, so every
    /// one of them is a step undo can take back on its own.
    func updateMotion(id: UUID, _ mutate: @escaping (inout LayerMotion) -> Void) {
        guard let layer = motionLayer else { return }
        perform { document in
            document.updateLayer(id: layer.id) { edited in
                guard var motions = edited.motions,
                      let index = motions.firstIndex(where: { $0.id == id }) else { return }
                mutate(&motions[index])
                edited.motions = motions
            }
        }
        // A number you just typed is a thing you want to SEE, so the preview
        // runs from the top of the cycle again rather than carrying on from
        // wherever the old timing had got to. It does NOT start a preview that
        // is stopped: somebody who pressed pause did it so they could look at
        // the picture they drew, and a field that started it up again would
        // take that away every time they typed.
        if isMotionPlaying { restartMotionPreview() }
    }

    /// The switch on a row.
    func setMotionEnabled(id: UUID, on: Bool) {
        updateMotion(id: id) { $0.isOn = on }
        stopIfNothingMoves()
    }

    // MARK: The preview

    /// Whether there is anything to play at all.
    var canPlayMotion: Bool {
        guard Experiments.shared.motionEnabled, let document else { return false }
        return document.hasMotion && document.motionCycleLengthMS > 0
    }

    func toggleMotionPreview() {
        if isMotionPlaying { pauseMotionPreview() } else { playMotionPreview() }
    }

    /// Start the preview from the top of the cycle.
    func playMotionPreview() {
        guard canPlayMotion else { return }
        restartMotionPreview()
    }

    func restartMotionPreview() {
        motionTask?.cancel()
        motionPlayheadMS = 0
        isMotionPlaying = true
        motionStartedAt = Date()
        rerender()
        motionTask = Task { @MainActor [weak self] in
            // Thirty frames a second. The composite is redrawn for each one,
            // and on an icon that is nothing; on a big photograph it is the
            // difference between a preview and a fan, which is why this is a
            // deliberate ceiling rather than "as fast as it will go".
            let frame = Duration.milliseconds(33)
            while !Task.isCancelled {
                try? await Task.sleep(for: frame)
                guard !Task.isCancelled, let self, self.isMotionPlaying,
                      let document = self.document, let started = self.motionStartedAt else { return }
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                self.motionPlayheadMS = elapsed
                self.submit(document)
                // Once nothing is moving any more the preview stops on its own
                // rather than burning frames on a finished icon. The picture
                // stays where the motion left it until you press play again.
                if document.motionHasSettled(atMS: elapsed) {
                    self.isMotionPlaying = false
                    self.motionTask = nil
                    return
                }
            }
        }
    }

    /// Stop, and put the picture back to the one you drew.
    func pauseMotionPreview() {
        motionTask?.cancel()
        motionTask = nil
        motionStartedAt = nil
        guard isMotionPlaying else { return }
        isMotionPlaying = false
        motionPlayheadMS = 0
        rerender()
    }

    /// Called after anything that could have taken the last moving thing away.
    private func stopIfNothingMoves() {
        if !canPlayMotion { pauseMotionPreview() }
    }
}
