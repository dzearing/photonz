import Foundation
import PhotonzCore

/// A picture animated by setting moments and changing things
/// (`PictureKeys.swift`, `docs/design/mocks/pages/picture-keys.html`).
///
/// A thin layer over the model, like the video editor's keys, which is what
/// these are: `keyLayer`, the lanes and the panel rows all answer on a keyed
/// picture, on the window's one playhead (`documentTimeMS`).
extension EditorState {

    // MARK: Whether keys have a clock here

    /// A document with time, or a keyed picture.
    var documentHasKeyClock: Bool { document?.hasKeyClock ?? false }

    /// A picture with keys on its lap. It stays a picture: same chip, same
    /// tool bar, and `documentHasTime` stays false.
    var isKeyedPicture: Bool { document?.isKeyedPicture ?? false }

    // MARK: The way in

    /// The layer Add Key would key on a still picture: there is no key clock
    /// yet, so `keyLayer` has nothing to say.
    private var stillPictureKeyLayer: Layer? {
        guard Experiments.shared.pictureKeysEnabled, !documentHasKeyClock else { return nil }
        return motionLayer
    }

    /// Whether a still picture offers Add Key: one unlocked layer picked.
    var offersAddKeyOnAStill: Bool { stillPictureKeyLayer != nil }

    /// The layer Add Key and Animate a property are about, with or without
    /// keys on the document yet.
    var addKeyLayer: Layer? { keyLayer ?? stillPictureKeyLayer }

    /// Where the Motion section has a job. With keys on the document it lists
    /// only a motion that loops: everything else is in Animating.
    var motionSectionHasAPlace: Bool {
        guard documentHasKeyClock else { return true }
        return !motionRows.isEmpty || (isKeyedPicture && motionNeedsOneLayer)
    }

    /// The first key on a still picture: the playhead at the top of a new lap,
    /// the strip up, and one hollow moment, as one step to undo.
    func addFirstPictureKey() {
        guard let layer = stillPictureKeyLayer else { return }
        let ease = newKeyEaseToWrite
        beginPictureLap()
        perform { $0.addKeyMoment(layerID: layer.id, atDocumentTimeMS: 0, ease: ease) }
    }

    /// Animate a property's list, picked: on a still picture that starts the
    /// lap too, with the one key.
    func animateFromThePicker(_ property: KeyedProperty) {
        guard let layer = stillPictureKeyLayer else { return startAnimating(property) }
        let ease = newKeyEaseToWrite
        activeKeyProperty = property
        beginPictureLap()
        perform { $0.animate(layerID: layer.id, property, atDocumentTimeMS: 0, ease: ease) }
    }

    private func beginPictureLap() {
        pauseMotionPreview()
        documentTimeMS = 0
        isMotionStripOpen = true
    }

    /// A key is being written on a picture that may be playing: the lap stops
    /// where it is, and that is the moment the key lands on.
    func stopPictureForAKey() {
        if isMotionPlaying, isKeyedPicture { pauseMotionPreview() }
    }

    // MARK: The strip

    /// What the strip lists, top of the Layers list first: every layer with
    /// keys, and the picked one, so its diamond is always in reach.
    var pictureKeyLayers: [Layer] {
        guard let document, isKeyedPicture else { return [] }
        let picked = keyLayer?.id
        return document.allLayersTopDown.filter { layer in
            !layer.isLocked && (layer.id == picked || document.isAnimating(layerID: layer.id))
        }
    }

    /// Whether the layer has a moment under the playhead.
    func hasKeyMomentUnderPlayhead(_ layerID: UUID) -> Bool {
        headerKeyDiamond(layerID) == .onKey
    }

    // MARK: Right clicks

    /// Add Key on a layer's right-click, on the canvas and in Layers: the
    /// button's verb, and Animate ▸ for the one value. Empty on a video, whose
    /// clips say it for themselves, and on a locked layer.
    func addKeyMenuRows(layerID: UUID) -> [MenuRow] {
        guard Experiments.shared.pictureKeysEnabled, !documentHasTime,
              let layer = document?.layer(id: layerID), !layer.isLocked else { return [] }
        var rows: [MenuRow] = [.command("Add Key", MenuShortcut(key: "k", modifiers: [])) {
            if self.selectedLayerID != layerID { self.selectLayer(layerID) }
            self.run(.keyAtPlayhead)
        }]
        if let animate = animateMenuRow(layerID: layerID) { rows.append(animate) }
        return rows
    }

    /// A right click on a layer's bar in the strip.
    func pictureKeyLineMenuRows(layerID: UUID) -> [MenuRow] {
        addKeyMenuRows(layerID: layerID)
    }

    // MARK: Repeat and the length

    var keyLapRepeats: Bool { document?.keyLap?.repeats ?? true }

    /// The Repeat button: go round, or play once and hold the last moment.
    func toggleKeyLapRepeats() {
        let repeats = !keyLapRepeats
        perform { $0.setKeyLapRepeats(repeats) }
    }

    /// The repeats mark, taken hold of: the ruler holds still under the hand.
    func beginKeyLapDrag() {
        stopPictureForAKey()
        let length = max(1, document?.motionCycleLengthMS ?? 1)
        keyLapDrag = KeyLapDrag(heldRulerMS: length, lengthMS: length)
    }

    /// ...moved. It stops at the last key, so no key is left past the end.
    func dragKeyLap(toMS ms: Int) {
        guard let document, var drag = keyLapDrag else { return }
        drag.lengthMS = max(document.shortestKeyLapMS, ms)
        keyLapDrag = drag
    }

    /// ...and let go: one step to undo, and the playhead kept inside the lap.
    func endKeyLapDrag() {
        guard let drag = keyLapDrag else { return }
        keyLapDrag = nil
        setMotionCycleMS(drag.lengthMS)
        if documentTimeMS > lastDocumentTimeMS { scrubDocument(toMS: lastDocumentTimeMS) }
    }

    /// Where the repeats mark is drawn.
    var keyLapMarkMS: Int { keyLapDrag?.lengthMS ?? document?.motionCycleLengthMS ?? 0 }
}

/// A hand on the repeats mark.
struct KeyLapDrag: Equatable {
    /// What the ruler keeps measuring until the hand lets go.
    var heldRulerMS: Int
    var lengthMS: Int
}
