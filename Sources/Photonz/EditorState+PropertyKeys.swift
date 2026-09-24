import Foundation
import PhotonzCore

/// Every value in the panel has a key diamond
/// (`every-value-in-the-panel-has-a-key-diamond`, `PropertyKeys.swift`).
///
/// A thin layer over the model, like Motion's: every change goes through
/// `perform`, so one key is one step to undo, and nothing here ever writes a
/// moved layer back into the document.
extension EditorState {

    // MARK: What the list answers for

    /// The layer the Animating list is about: ONE picked, unlocked layer in a
    /// document that runs for a length of time. A key is a value at a moment,
    /// and a document without moments has nowhere to put one.
    var keyLayer: Layer? {
        guard documentHasTime,
              let id = soleLayerID(layerStyleSelection.layerIDs),
              let layer = document?.layer(id: id), !layer.isLocked else { return nil }
        return layer
    }

    /// The values it lists, keyed or not, in the mock's order.
    var keyRows: [KeyedProperty] { keyLayer?.keyableProperties ?? [] }

    /// How many of them are keyed, for the header's count.
    var keyedRowCount: Int {
        guard let layer = keyLayer, let document else { return 0 }
        return keyRows.filter { document.keyCount(layerID: layer.id, $0) > 0 }.count
    }

    func keyDiamond(_ property: KeyedProperty) -> KeyDiamond {
        guard let layer = keyLayer, let document else { return .dormant }
        return document.keyDiamond(layerID: layer.id, property, atDocumentTimeMS: documentTimeMS)
    }

    func keyCount(_ property: KeyedProperty) -> Int {
        guard let layer = keyLayer, let document else { return 0 }
        return document.keyCount(layerID: layer.id, property)
    }

    /// The value at the playhead: where it has got to between keys, or the
    /// layer's own where nothing keys it.
    func keyedValue(_ property: KeyedProperty) -> MotionValue? {
        guard let layer = keyLayer, let document else { return nil }
        return document.keyedValue(layerID: layer.id, property, atDocumentTimeMS: documentTimeMS)
    }

    /// Whether there is a key before (or after) the playhead to step to.
    func canStepToKey(_ property: KeyedProperty, forward: Bool) -> Bool {
        neighbourKey(property, forward: forward) != nil
    }

    private func neighbourKey(_ property: KeyedProperty, forward: Bool) -> Int? {
        guard let layer = keyLayer, let document else { return nil }
        return document.neighbourKeyTime(layerID: layer.id, property,
                                         from: documentTimeMS, forward: forward)
    }

    // MARK: The diamond

    /// The diamond, clicked. Not keyed: start keying, with one key here.
    /// Keyed: stop, keeping the value it has now, and ASK first when that
    /// would lose keys. One key is a constant, so nothing is lost by it.
    func toggleKeying(_ property: KeyedProperty) {
        guard let layer = keyLayer else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        activeKeyProperty = property
        switch keyCount(property) {
        case 0:
            perform { $0.startKeying(layerID: layer.id, property, atDocumentTimeMS: time, ease: ease) }
        case 1:
            perform { $0.stopKeying(layerID: layer.id, property, atDocumentTimeMS: time) }
        default:
            keyStopQuestion = property
        }
    }

    /// The question answered yes: every key on it goes.
    func confirmStopKeying() {
        guard let property = keyStopQuestion, let layer = keyLayer else {
            keyStopQuestion = nil
            return
        }
        keyStopQuestion = nil
        let time = documentTimeMS
        perform { $0.stopKeying(layerID: layer.id, property, atDocumentTimeMS: time) }
    }

    func cancelStopKeying() { keyStopQuestion = nil }

    // MARK: Values and keys

    /// A value typed or picked in the row: a key here when it is keyed, the
    /// layer's own value when it is not.
    func setKeyedValue(_ value: MotionValue, for property: KeyedProperty) {
        guard let layer = keyLayer else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        activeKeyProperty = property
        perform { $0.setKeyedValue(value, layerID: layer.id, property, atDocumentTimeMS: time, ease: ease) }
    }

    /// Right-click, Add Key Here: a key holding the value it has now, which
    /// changes nothing on screen and gives a move a place to hold from.
    func addKeyHere(_ property: KeyedProperty) {
        guard let layer = keyLayer, keyDiamond(property) != .onKey,
              let value = keyedValue(property) else { return }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        activeKeyProperty = property
        perform { document in
            if document.keyCount(layerID: layer.id, property) == 0 {
                document.startKeying(layerID: layer.id, property, atDocumentTimeMS: time, ease: ease)
            } else {
                document.setKeyedValue(value, layerID: layer.id, property, atDocumentTimeMS: time, ease: ease)
            }
        }
    }

    /// Right-click, Remove Key Here.
    func removeKeyHere(_ property: KeyedProperty) {
        guard let layer = keyLayer, keyDiamond(property) == .onKey else { return }
        let time = documentTimeMS
        perform { $0.removeKey(layerID: layer.id, property, atDocumentTimeMS: time) }
    }

    /// The arrows: put the playhead on the key before or after it.
    func stepToKey(_ property: KeyedProperty, forward: Bool) {
        guard let moment = neighbourKey(property, forward: forward) else { return }
        activeKeyProperty = property
        if isDocumentPlaying { pauseDocument() }
        scrubDocument(toMS: moment)
    }

    // MARK: A hand on the canvas

    /// Whether a drag on this layer has to be read as keys rather than as a
    /// change to the layer: a document with time, and something on the layer
    /// keyed.
    func dragMakesKeys(_ id: UUID) -> Bool {
        guard documentHasTime, let layer = document?.layer(id: id) else { return false }
        return layer.hasMotion
    }

    /// The document the canvas hit-tests and draws handles on: every layer
    /// whose place, size or angle is keyed wears the ones it has at the
    /// playhead (`PhotonzDocument.posedForCanvas`), so the handles are round
    /// the picture rather than round where the layer was first drawn.
    var canvasGeometryDocument: PhotonzDocument? {
        guard let document else { return nil }
        guard documentHasTime else { return document }
        return document.posedForCanvas(atTimeMS: documentTimeMS)
            .hidingWhatIsOffScreen(atTimeMS: documentTimeMS)
    }

    /// The canvas edit `mutate` makes to layer `id`, with every change to a
    /// keyed value turned into a key at the playhead
    /// (`PhotonzDocument.foldEditIntoKeys`). The hand worked on the layer as
    /// POSED, so that is what its move is read against. Used for the live
    /// preview and the commit alike, so what the hand sees is what lands.
    func foldingIntoKeys(_ id: UUID, in document: inout PhotonzDocument,
                         _ mutate: (inout PhotonzDocument) -> Void) {
        guard dragMakesKeys(id), let stored = document.layer(id: id) else {
            mutate(&document)
            return
        }
        let time = documentTimeMS
        let posed = document.posedForCanvas(atTimeMS: time).layer(id: id) ?? stored
        mutate(&document)
        document.foldEditIntoKeys(layerID: id, before: posed, restoring: stored,
                                  atDocumentTimeMS: time, ease: newKeyEaseToWrite)
    }

    // MARK: The timeline bar

    /// The ease a new key is written with. Ease In and Out is what a key
    /// nobody eased already is (it follows its motion's curve, and the key's
    /// right-click ticks it as Ease In and Out), so the default writes nothing
    /// and every key made before this dropdown plays exactly as it did.
    var newKeyEaseToWrite: KeyEase? { newKeyEase == .easeInAndOut ? nil : newKeyEase }

    /// What the timeline bar says after "Playhead": the value last touched
    /// on the picked layer, or its first keyed one, and its reading here.
    var keyReadout: String? {
        guard let layer = keyLayer, let document else { return nil }
        return document.keyReadout(layerID: layer.id, preferring: activeKeyProperty,
                                   atDocumentTimeMS: documentTimeMS)
    }
}
