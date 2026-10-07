import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Keying a value redraws only what the key changes (task
/// `keying-a-value-redraws-only-what-the-key-changes`).
///
/// Picking Position from Animate a property wrote one key and every section
/// of the panel was built again: Text, Appearance, Effects and Time read the
/// whole document, and a key on where a layer is changes nothing any of them
/// shows. The sections that show how a layer LOOKS ask this instead: the same
/// document, apart from keys on where a layer is, how big and how turned.
/// A key on a look value (opacity, a shadow's distance) is what those rows
/// read at the playhead, so it still counts.
@Suite("Documents the same apart from placement keys")
struct PlacementKeysTests {

    /// An eight second film with a title on it, and a group holding a shape.
    static func titleOnAFilm() -> (PhotonzDocument, title: UUID, inner: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        var title = Layer(name: "Title",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
                          frame: CGRect(x: 400, y: 300, width: 200, height: 120))
        title.time = LayerTime(inMS: 1000, outMS: 8000)
        let inner = Layer(name: "Inner",
                          content: .annotation(AnnotationContent(shape: .ellipse, colorHex: "#34C759")),
                          frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 600, y: 600, width: 100, height: 100))
        doc.layers = [clip, title, group]
        doc.durationMS = 8000
        return (doc, title.id, inner.id)
    }

    @Test func aDocumentIsTheSameAsItself() {
        let (doc, _, _) = Self.titleOnAFilm()
        #expect(doc.sameApartFromPlacementKeys(doc))
    }

    @Test func aPositionKeyChangesNothingTheLookRowsShow() {
        let (before, title, _) = Self.titleOnAFilm()
        var after = before
        let keyed = after.startKeying(layerID: title, .motion(.position), atDocumentTimeMS: 2000)
        #expect(keyed)
        #expect(after != before)
        #expect(after.sameApartFromPlacementKeys(before))
        #expect(before.sameApartFromPlacementKeys(after))
    }

    @Test func scaleAndTurnKeysAreLeftOutToo() {
        let (before, title, _) = Self.titleOnAFilm()
        var after = before
        after.startKeying(layerID: title, .motion(.scale), atDocumentTimeMS: 2000)
        after.startKeying(layerID: title, .motion(.rotation), atDocumentTimeMS: 2000)
        #expect(after.sameApartFromPlacementKeys(before))
    }

    @Test func movingAPositionKeysValueIsLeftOut() {
        let (start, title, _) = Self.titleOnAFilm()
        var before = start
        before.startKeying(layerID: title, .motion(.position), atDocumentTimeMS: 2000)
        var after = before
        after.setKeyedValue(.point(CGPoint(x: 900, y: 100)), layerID: title, .motion(.position),
                            atDocumentTimeMS: 5000)
        #expect(after != before)
        #expect(after.sameApartFromPlacementKeys(before))
    }

    @Test func anOpacityKeyIsWhatTheAppearanceRowReads() {
        let (before, title, _) = Self.titleOnAFilm()
        var after = before
        after.startKeying(layerID: title, .motion(.opacity), atDocumentTimeMS: 2000)
        #expect(!after.sameApartFromPlacementKeys(before))
    }

    @Test func aShadowDistanceKeyCountsToo() {
        var (before, title, _) = Self.titleOnAFilm()
        before.updateLayer(id: title) {
            $0.style.shadows = [ShadowStyle(radius: 3, offset: CGSize(width: 0, height: 4),
                                            colorHex: "#000000", opacity: 0.4)]
        }
        var after = before
        after.startKeying(layerID: title, .motion(.shadowDistance), atDocumentTimeMS: 2000)
        #expect(after != before)
        #expect(!after.sameApartFromPlacementKeys(before))
    }

    @Test func anEditToTheLayerItselfCounts() {
        let (before, title, _) = Self.titleOnAFilm()
        var after = before
        after.updateLayer(id: title) { $0.name = "Headline" }
        #expect(!after.sameApartFromPlacementKeys(before))
    }

    @Test func anEditOutsideTheLayersCounts() {
        let (before, _, _) = Self.titleOnAFilm()
        var after = before
        after.durationMS = 9000
        #expect(!after.sameApartFromPlacementKeys(before))
    }

    @Test func aLayerAddedOrTakenAwayCounts() {
        let (before, _, _) = Self.titleOnAFilm()
        var after = before
        after.layers.removeLast()
        #expect(!after.sameApartFromPlacementKeys(before))
        #expect(!before.sameApartFromPlacementKeys(after))
    }

    @Test func aPositionKeyOnALayerInsideAGroupIsLeftOut() {
        let (before, _, inner) = Self.titleOnAFilm()
        var after = before
        after.updateLayer(id: inner) { layer in
            layer.motions = [.keyed(.position, atMS: 0, value: .point(CGPoint(x: 20, y: 20)))]
        }
        #expect(after != before)
        #expect(after.sameApartFromPlacementKeys(before))
    }

    @Test func anOpacityKeyOnALayerInsideAGroupCounts() {
        let (before, _, inner) = Self.titleOnAFilm()
        var after = before
        after.updateLayer(id: inner) { layer in
            layer.motions = [.keyed(.opacity, atMS: 0, value: .number(0.5))]
        }
        #expect(!after.sameApartFromPlacementKeys(before))
    }

    @Test func noKeysAndAnEmptyListOfKeysAreTheSame() {
        let (before, title, _) = Self.titleOnAFilm()
        var after = before
        after.updateLayer(id: title) { $0.motions = [] }
        #expect(after.sameApartFromPlacementKeys(before))
    }
}
