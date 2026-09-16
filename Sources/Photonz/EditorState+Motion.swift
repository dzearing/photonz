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

    // MARK: THE ONE RULE for when the loop plays

    /// **Motion plays unless you stop it.**
    ///
    /// Written out in `docs/design/layer-motion.md`. Every place in the app
    /// that could start the preview comes through the two calls below, so
    /// there is one rule rather than one habit per gesture. There used to be
    /// three: adding a motion started the loop, grabbing the pivot started it
    /// if it was stopped, and typing a number into a paused row started
    /// nothing at all, so the edit landed with nothing on screen to show it
    /// and you could not tell whether it had taken.
    ///
    /// - A document that arrives with motion in it arrives moving.
    /// - Anything you change about HOW THE LAYER MOVES plays it, from the top
    ///   of the lap: adding a motion, taking one off, the switch on a row, any
    ///   number on a row, the pivot, a bar on the timing strip, the lap length.
    /// - A drag gets the loop running the moment you take hold, so your hand
    ///   can see its own work; the change itself lands when you let go.
    /// - Only you stop it, with the play button or the space bar. It also
    ///   stops on its own once nothing is moving any more.
    /// - Two things deliberately do NOT start it, because neither is a change
    ///   to the motion: working on the DRAWING rather than the motion, so
    ///   pausing to edit the picture keeps the picture still, and the preview
    ///   SPEED, which is how you are watching rather than what is moving. Undo
    ///   and redo go with them: they put back a picture you have already seen.

    /// A change to the motion landed. Play it, from the top of the lap,
    /// whether or not it was running: a number you just changed is a thing you
    /// want to SEE, and half a lap of the old timing is not it.
    func motionChanged() {
        playMotionPreview()
    }

    /// A hand took hold of something that moves the motion (the pivot on the
    /// picture, a bar on the strip). Get the loop running so the drag can be
    /// judged, but leave a lap already on screen where it is: nothing has
    /// changed yet, and snapping to the top under the hand is a jolt rather
    /// than an answer.
    func motionGestureBegan() {
        guard !isMotionPlaying else { return }
        playMotionPreview()
    }

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

    /// More than one layer is picked, so the list has nothing it can honestly
    /// show and the section says why instead of disappearing.
    ///
    /// Motion sits directly under Effects and Effects speaks for everything
    /// picked, so the one section that cannot is the one most likely to be read
    /// as broken: you add a second layer and the whole section goes, with
    /// nothing anywhere saying it was your second click that did it. Asked for
    /// in the 2026-09-16 design review, which put it exactly this way: say what
    /// Motion shows with two layers picked instead of just vanishing, even if
    /// that is one line explaining why.
    ///
    /// A locked layer on its own is NOT this: nothing about it can be changed,
    /// and a section explaining that would be one of many.
    var motionNeedsOneLayer: Bool {
        guard Experiments.shared.motionEnabled, motionLayer == nil else { return false }
        return layerStyleSelection.layerIDs.count > 1
    }

    /// The entries in the list, top to bottom.
    ///
    /// A bar being dragged on the timing strip is shown here as the hand has
    /// it, not as the document still stores it, which is the whole of "one
    /// model, two views": drag the bar and Start and Over follow it at once,
    /// type into Start and Over and the bar follows them
    /// (`EditorState+MotionStrip`).
    var motionRows: [LayerMotion] {
        var rows = motionLayer?.motions ?? []
        if let drag = motionTimingDrag,
           let index = rows.firstIndex(where: { $0.id == drag.motionID }) {
            rows[index].timing = drag.timing
        }
        // ...and the same for a colour still being chosen: the swatch and the
        // summary beside it show what the hand is on, not what is written down.
        if let preview = motionValuePreview,
           let index = rows.firstIndex(where: { $0.id == preview.motionID }) {
            if preview.isFrom { rows[index].from = preview.value } else { rows[index].to = preview.value }
        }
        return rows
    }

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
        motionChanged()
    }

    /// The cross on a row: takes the entry out. Different from the switch
    /// beside it, which keeps every number on it and stops it moving.
    func removeMotion(id: UUID) {
        guard let layer = motionLayer else { return }
        perform { document in
            document.updateLayer(id: layer.id) { $0.motions = ($0.motions ?? []).filter { $0.id != id } }
        }
        // What is LEFT plays, so taking one motion off a layer that has three
        // shows you the two. `stopIfNothingMoves` has the last word when that
        // was the only one.
        motionChanged()
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
        motionChanged()
    }

    // MARK: A colour being chosen for a From or a To

    /// The colour under the hand in the picker: painted straight away and kept
    /// out of history, so the swing recolours as you slide and the whole pick
    /// is one step to undo rather than one per frame.
    func previewMotionValue(id: UUID, isFrom: Bool, _ value: MotionValue) {
        guard motionLayer != nil else { return }
        motionValuePreview = (id, isFrom, value)
        // Redrawn through `displayDocument` rather than by handing a changed
        // copy to the renderer, for the reason `previewMotionPivot` gives: the
        // preview's own frame loop submits the STORED document thirty times a
        // second and would paint straight back over it.
        rerender()
    }

    /// The pick landed: one step for undo covering the whole of it.
    func commitMotionValue(id: UUID, isFrom: Bool, _ value: MotionValue) {
        motionValuePreview = nil
        updateMotion(id: id) { edited in
            if isFrom { edited.from = value } else { edited.to = value }
        }
    }

    /// What the CANVAS is handed while a colour is being chosen: the same
    /// document with the half-chosen endpoint written onto it, so the blend
    /// that runs after this reads the pair the hand has (`displayDocument`).
    func withPreviewedMotionValue(_ document: PhotonzDocument) -> PhotonzDocument {
        guard Experiments.shared.motionEnabled,
              let preview = motionValuePreview, let layer = motionLayer else { return document }
        var document = document
        document.updateLayer(id: layer.id) { edited in
            guard var motions = edited.motions,
                  let index = motions.firstIndex(where: { $0.id == preview.motionID }) else { return }
            if preview.isFrom { motions[index].from = preview.value } else { motions[index].to = preview.value }
            edited.motions = motions
        }
        return document
    }

    /// The switch on a row.
    func setMotionEnabled(id: UUID, on: Bool) {
        updateMotion(id: id) { $0.isOn = on }
        stopIfNothingMoves()
    }

    // MARK: What the turn turns around

    /// The turn on the picked layer, if it has one. Only a rotation has a
    /// pivot, and one property is one answer, so there is at most one.
    var turningMotion: LayerMotion? {
        motionRows.first { $0.property == .rotation }
    }

    /// What the canvas draws a crosshair for, and drags: nil whenever nothing
    /// picked is turning.
    ///
    /// The point comes off the STORED layer, never the moving one. A rotation
    /// is the one thing that leaves its own pivot still, so while the bell
    /// swings the crosshair sits dead under it, which is both what makes it
    /// catchable and what teaches what a pivot IS.
    var motionPivotHandle: MotionPivotHandle? {
        guard let layer = motionLayer, let motion = turningMotion else { return nil }
        let pivot = motionPivotPreview?.motionID == motion.id
            ? motionPivotPreview!.pivot : motion.turnsAbout
        return MotionPivotHandle(layerID: layer.id, motionID: motion.id,
                                 point: pivot.point(in: layer.turnPivotBox),
                                 box: layer.turnPivotBox)
    }

    /// Where the pivot is right now as two numbers on the canvas, which is
    /// what the Around row types into. Nil where nothing is turning.
    var motionPivotPoint: CGPoint? { motionPivotHandle?.point }

    /// The spot the pivot is sitting on, or nil where it is somewhere of its
    /// own — what the Around menu shows as its current answer.
    var motionPivotNamed: MotionPivot.Named? {
        guard let motion = turningMotion else { return nil }
        if let preview = motionPivotPreview, preview.motionID == motion.id { return preview.pivot.named }
        return motion.turnsAbout.named
    }

    /// The pivot handle grabbed. The loop starts if it is not already running,
    /// because a pivot cannot be judged on a still picture: with the layer
    /// sitting at nought degrees, changing what it turns around changes
    /// nothing you can see. Same call the timing strip's bar makes, and the
    /// same rule (`motionGestureBegan`).
    func beginMotionPivotDrag() {
        motionGestureBegan()
    }

    /// The pivot under the hand: rendered straight away and kept out of
    /// history, so the swing follows the drag and the whole drag is one step
    /// to undo rather than forty.
    func previewMotionPivot(at point: CGPoint) {
        guard let layer = motionLayer, let motion = turningMotion else { return }
        motionPivotPreview = (motion.id, MotionPivot(at: point, in: layer.turnPivotBox))
        // Redrawn through `displayDocument` rather than by handing a changed
        // copy straight to the renderer, because the preview's own frame loop
        // submits the STORED document thirty times a second: a copy pushed
        // from here would be painted back over before the hand had moved.
        rerender()
    }

    /// The button up: one undo step from where the pivot started to where it
    /// ended.
    func commitMotionPivot() {
        guard let preview = motionPivotPreview else { return }
        motionPivotPreview = nil
        setMotionPivot(preview.pivot, of: preview.motionID)
    }

    /// A drag that went nowhere leaves nothing behind, not even a redraw of
    /// the picture it never changed.
    func cancelMotionPivot() {
        guard motionPivotPreview != nil else { return }
        motionPivotPreview = nil
        rerender()
    }

    /// The pivot set outright: the Around menu's three named spots, and the
    /// two numbers beside it. One step for undo, exactly like the drag.
    func setMotionPivot(_ pivot: MotionPivot, of motionID: UUID? = nil) {
        guard let id = motionID ?? turningMotion?.id else { return }
        updateMotion(id: id) { $0.pivot = pivot }
    }

    // MARK: The preview

    /// Whether there is anything to play at all.
    ///
    /// Asked of what is SWITCHED ON, not of the written lap length. A lap
    /// length dragged onto the strip stays written down after every row on it
    /// has been switched off, and reading that would say yes to a picture where
    /// nothing whatsoever moves: the play button would stay live and, under the
    /// one rule, the next number typed would start a loop of a still icon.
    var canPlayMotion: Bool {
        guard Experiments.shared.motionEnabled, let document else { return false }
        return document.automaticMotionCycleLengthMS > 0
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
                // Real time through the speed, so a quarter rate is a quarter
                // of the loop per second and everything in the picture, the
                // lags between its parts included, slows together.
                let elapsed = self.motionSpeed.motionMS(
                    afterRealSeconds: Date().timeIntervalSince(started))
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

    /// The speed control, on the previews card and on the timing strip.
    ///
    /// A running preview is NOT started over. The loop is wherever it is, and
    /// the only thing changing is how long it now takes to leave there, so the
    /// clock is re-anchored to the moment this playhead would have been reached
    /// at the new rate. Snapping back to the top would throw away the half of
    /// the lap you were watching, every time you reached for the control.
    func setMotionSpeed(_ speed: MotionSpeed) {
        guard speed != motionSpeed else { return }
        motionSpeed = speed
        guard isMotionPlaying else { return }
        motionStartedAt = Date().addingTimeInterval(-speed.realSeconds(forMotionMS: motionPlayheadMS))
    }

    /// Called after anything that could have taken the last moving thing away.
    private func stopIfNothingMoves() {
        if !canPlayMotion { pauseMotionPreview() }
    }
}
