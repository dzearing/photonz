import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Opacity changes a shape on a video, and animates with keys (task
/// `opacity-changes-a-shape-on-a-video-and-animates`).
///
/// The user's words: "I can't seem to animate opacity. I select a rect, drag
/// opacity down in Appearance, no effect." Reproduced on 2026-09-26: a
/// rectangle drawn on a recording and keyed with the diamond on its timeline
/// row (which keys where it is, its size, its angle AND its opacity) wore the
/// key's 100% whatever the Appearance slider said, because the slider wrote the
/// layer's own opacity and a keyed value is read from its keys. The slider sat
/// on 28 over a rectangle drawn solid, beside an Animating row saying 100.
///
/// Written before the model. Premiere's stopwatch, said for the panel's look
/// rows: a value that is keyed changes by a key at the playhead; a value that
/// is not changes the whole layer; and the panel reads the value at the
/// playhead, so the knob follows it.
@Suite("Looks edited at the playhead")
struct LooksAtThePlayheadTests {

    // MARK: - Fixtures

    /// An eight second film with a red rectangle on it from 1s to the end.
    static func rectangleOnAFilm() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        var shape = Layer(name: "Rectangle",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
                          frame: CGRect(x: 400, y: 300, width: 200, height: 120))
        shape.time = LayerTime(inMS: 1000, outMS: 8000)
        doc.layers = [clip, shape]
        doc.durationMS = 8000
        return (doc, shape.id)
    }

    static func number(_ value: MotionValue?) -> Double? {
        if case let .number(number) = value { return number }
        return nil
    }

    /// The opacity the rectangle is DRAWN with at a moment: what the canvas and
    /// the export composite.
    static func drawnOpacity(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> Double? {
        doc.drawn(atTimeMS: ms).layer(id: id).map { Double($0.style.opacity) }
    }

    // MARK: - Not keyed: the whole layer

    @Test func anUnkeyedOpacityChangesTheWholeLayer() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 2000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.opacity = 0.3 }
        }
        #expect(doc.layer(id: id)?.style.opacity == 0.3)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 0)
        for moment in [1000, 4000, 7000] {
            #expect(Self.drawnOpacity(doc, id, atMS: moment) == 0.3)
        }
    }

    @Test func onAPictureItIsTheOrdinaryEditItAlwaysWas() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let shape = Layer(name: "Rectangle",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
                          frame: CGRect(x: 40, y: 30, width: 200, height: 120))
        doc.layers = [shape]
        doc.editLooks(layerIDs: [shape.id], atDocumentTimeMS: 0) {
            $0.updateLayerStyles(layerIDs: [shape.id]) { $0.opacity = 0.3 }
        }
        #expect(doc.layer(id: shape.id)?.style.opacity == 0.3)
        #expect(doc.layer(id: shape.id)?.motions == nil)
    }

    @Test func aValueNotKeyedOnALayerWithOtherKeysStillChangesTheWholeLayer() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.opacity = 0.4 }
        }
        #expect(doc.layer(id: id)?.style.opacity == 0.4)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 0)
        #expect(doc.keyCount(layerID: id, .motion(.position)) == 1)
    }

    // MARK: - Keyed: a key at the playhead

    /// The report itself: keyed by the row's diamond, then dragged in the
    /// panel. It used to change the layer's own opacity, which the key hid.
    @Test func aKeyedOpacityChangedInThePanelShowsOnTheCanvas() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.toggleTransformKey(layerID: id, atDocumentTimeMS: 1000)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 1)
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 1000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.opacity = 0.3 }
        }
        // On the key, so the key is rewritten rather than a second one made.
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 1)
        let drawn = Self.drawnOpacity(doc, id, atMS: 1000) ?? 1
        #expect(abs(drawn - 0.3) < 0.001)
    }

    @Test func aKeyedOpacityChangedAtAnotherMomentAddsAKeyAndFadesBetween() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.opacity = 0 }
        }
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 2)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)) == 0)
        let one = Self.drawnOpacity(doc, id, atMS: 1000) ?? 0
        // Part way: keys ease in and out by default, so the middle moment is
        // not the middle value (`PropertyKeys.curve`).
        let two = Self.drawnOpacity(doc, id, atMS: 2000) ?? 0
        let three = Self.drawnOpacity(doc, id, atMS: 3000) ?? 1
        #expect(abs(one - 1) < 0.001)
        #expect(two > 0.05 && two < 0.95)
        #expect(three < 0.001)
        // The layer's own value is untouched: the keys say what it is.
        #expect(doc.layer(id: id)?.style.opacity == 1)
    }

    @Test func aKeyedValueTheEditDidNotTouchGetsNoKeyAndDoesNotLeak() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        // Half way through the fade, the blur is changed and nothing else.
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 2000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.blurRadius = 6 }
        }
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 2)
        // The half faded opacity the edit was made against is not written
        // back as the layer's own.
        #expect(doc.layer(id: id)?.style.opacity == 1)
        #expect(doc.layer(id: id)?.style.blurRadius == 6)
    }

    @Test func aKeyedBlurChangedInThePanelAddsAKey() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.updateLayerStyles(layerIDs: [id]) { $0.blurRadius = 2 }
        doc.startKeying(layerID: id, .motion(.blur), atDocumentTimeMS: 1000)
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.blurRadius = 20 }
        }
        #expect(doc.keyCount(layerID: id, .motion(.blur)) == 2)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.blur), atDocumentTimeMS: 3000)) == 20)
        #expect(doc.layer(id: id)?.style.blurRadius == 2)
    }

    @Test func aKeyedCornerRadiusChangedInThePanelAddsAKey() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.startKeying(layerID: id, .motion(.cornerRadius), atDocumentTimeMS: 1000)
        let before = Self.number(doc.keyedValue(layerID: id, .motion(.cornerRadius), atDocumentTimeMS: 1000))
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) {
            $0.setCornerRadii(layerIDs: [id], to: CornerRadii(30))
        }
        #expect(doc.keyCount(layerID: id, .motion(.cornerRadius)) == 2)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.cornerRadius), atDocumentTimeMS: 3000)) == 30)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.cornerRadius), atDocumentTimeMS: 1000)) == before)
    }

    // MARK: - The panel reads the playhead

    @Test func thePanelReadsTheValueAtThePlayhead() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        let one = doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 1000).layer(id: id)?.style.opacity ?? 0
        let two = doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 2000).layer(id: id)?.style.opacity ?? 0
        let three = doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 3000).layer(id: id)?.style.opacity ?? 1
        #expect(abs(one - 1) < 0.001)
        #expect(two > 0.05 && two < 0.95)
        #expect(three < 0.001)
    }

    @Test func posingLeavesAnUnkeyedLayerExactlyAsItIs() {
        let (doc, id) = Self.rectangleOnAFilm()
        #expect(doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 2000) == doc)
    }

    @Test func aDragThatEndsWhereItStartedWritesNoKey() {
        var (doc, id) = Self.rectangleOnAFilm()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        let posed = doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 2000).layer(id: id)?.style.opacity ?? 0
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 2000) {
            $0.updateLayerStyles(layerIDs: [id]) { $0.opacity = posed }
        }
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 2)
    }
}
