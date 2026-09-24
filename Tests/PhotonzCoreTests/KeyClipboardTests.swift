import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Keys copy between layers and the playhead lands on them
/// (task `keys-copy-between-layers-and-the-playhead-lands`).
///
/// Written before the model. Picked keys copy, and paste at the playhead onto
/// the matching values of whatever layer is picked, keeping their spacing and
/// how they ease. The playhead is pulled onto a key it is dragged near, and
/// steps from key to key.
@Suite("Key clipboard and the playhead on keys")
struct KeyClipboardTests {

    // MARK: - Fixtures

    /// Ten seconds, a title "Hello" from 2s to 8s, a second title "World" from
    /// 1s to 9s.
    static func twoTitles() -> (PhotonzDocument, UUID, UUID) {
        var (doc, first) = KeyLanesTests.keyed()
        var second = Layer(name: "World",
                           content: .text(TextContent(string: "World", fontSize: 48)),
                           frame: CGRect(x: 300, y: 500, width: 400, height: 80))
        second.time = LayerTime(inMS: 1000, outMS: 9000)
        doc.layers.append(second)
        return (doc, first, second.id)
    }

    static func lane(_ doc: PhotonzDocument, _ id: UUID, _ property: MotionProperty) -> KeyLane? {
        KeyLanesTests.lane(doc, id, property)
    }

    static func value(_ doc: PhotonzDocument, _ id: UUID, _ property: MotionProperty, _ ms: Int) -> Double? {
        KeyLanesTests.value(doc, id, property, ms)
    }

    // MARK: - Copying

    @Test func copyingPickedKeysKeepsTheirSpacingFromTheEarliest() throws {
        let (doc, id) = KeyLanesTests.keyed()
        let refs = KeyLanesTests.refs(doc, id, .scale, at: [3000, 6000])
            .union(KeyLanesTests.refs(doc, id, .opacity, at: [5000]))
        let copied = try #require(doc.copyKeys(layerID: id, refs))
        #expect(copied.keys.count == 3)
        let scale = copied.keys.filter { $0.property == .scale }
        #expect(scale.map(\.offsetMS) == [0, 3000])
        #expect(copied.keys.first { $0.property == .opacity }?.offsetMS == 2000)
        #expect(copied.properties == [.scale, .opacity])
    }

    @Test func copyingNothingPickedCopiesNothing() {
        let (doc, id) = KeyLanesTests.keyed()
        #expect(doc.copyKeys(layerID: id, []) == nil)
    }

    @Test func copiedKeysSurviveTheClipboard() throws {
        let (doc, id) = KeyLanesTests.keyed()
        let refs = KeyLanesTests.refs(doc, id, .scale, at: [3000, 6000])
        let copied = try #require(doc.copyKeys(layerID: id, refs))
        let data = try JSONEncoder().encode(copied)
        #expect(try JSONDecoder().decode(CopiedKeys.self, from: data) == copied)
    }

    @Test func aCopiedKeyCarriesHowItEasesEvenWhereNobodyChose() throws {
        var (doc, id) = KeyLanesTests.keyed()
        let late = KeyLanesTests.refs(doc, id, .scale, at: [6000])
        doc.easeKeys(layerID: id, late, .hold)
        let refs = KeyLanesTests.refs(doc, id, .scale, at: [3000, 6000])
        let copied = try #require(doc.copyKeys(layerID: id, refs))
        #expect(copied.keys.map(\.ease) == [KeyEase(following: PropertyKeys.curve), .hold])
    }

    // MARK: - Pasting

    @Test func pastedKeysLandAtThePlayheadOnAnotherLayersMatchingValues() {
        var (doc, first, second) = Self.twoTitles()
        let refs = KeyLanesTests.refs(doc, first, .scale, at: [3000, 6000])
            .union(KeyLanesTests.refs(doc, first, .opacity, at: [3000, 5000]))
        guard let copied = doc.copyKeys(layerID: first, refs) else {
            Issue.record("nothing copied")
            return
        }
        let landed = doc.pasteKeys(copied, layerID: second, atDocumentMS: 4000)
        #expect(landed.count == 4)
        #expect(Self.lane(doc, second, .scale)?.keys.map(\.documentMS) == [4000, 7000])
        #expect(Self.lane(doc, second, .opacity)?.keys.map(\.documentMS) == [4000, 6000])
        #expect(Self.value(doc, second, .scale, 7000) == 200)
        #expect(Self.value(doc, second, .opacity, 6000) == 0)
        // The layer copied from is left exactly as it was.
        #expect(Self.lane(doc, first, .scale)?.keys.map(\.documentMS) == [3000, 6000])
    }

    @Test func pastedKeysAreWhatIsPickedAfterwards() {
        var (doc, first, second) = Self.twoTitles()
        let refs = KeyLanesTests.refs(doc, first, .scale, at: [3000, 6000])
        guard let copied = doc.copyKeys(layerID: first, refs) else { return }
        let landed = doc.pasteKeys(copied, layerID: second, atDocumentMS: 2000)
        let lane = Self.lane(doc, second, .scale)
        #expect(Set(lane?.keys.map(\.ref) ?? []) == landed)
    }

    @Test func pastingOntoTheSameLayerAtAnotherMomentAddsTheKeysThere() {
        var (doc, id) = KeyLanesTests.keyed()
        let refs = KeyLanesTests.refs(doc, id, .opacity, at: [3000, 5000])
        guard let copied = doc.copyKeys(layerID: id, refs) else { return }
        doc.pasteKeys(copied, layerID: id, atDocumentMS: 6000)
        #expect(Self.lane(doc, id, .opacity)?.keys.map(\.documentMS) == [3000, 5000, 6000, 8000])
        #expect(Self.value(doc, id, .opacity, 6000) == 100)
    }

    @Test func aPastedKeyLandingOnOneReplacesIt() {
        var (doc, first, second) = Self.twoTitles()
        doc.startKeying(layerID: second, .motion(.scale), atDocumentTimeMS: 4000)
        doc.setKeyedValue(.number(50), layerID: second, .motion(.scale), atDocumentTimeMS: 8000)
        let refs = KeyLanesTests.refs(doc, first, .scale, at: [3000, 6000])
        guard let copied = doc.copyKeys(layerID: first, refs) else { return }
        doc.pasteKeys(copied, layerID: second, atDocumentMS: 4000)
        #expect(Self.lane(doc, second, .scale)?.keys.map(\.documentMS) == [4000, 7000, 8000])
        #expect(Self.value(doc, second, .scale, 4000) == 100)
        #expect(Self.value(doc, second, .scale, 7000) == 200)
    }

    @Test func aValueTheLayerDoesNotHaveIsLeftOut() {
        var (doc, first) = KeyLanesTests.keyed()
        doc.startKeying(layerID: first, .motion(.textSize), atDocumentTimeMS: 3000)
        var box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                       colorHex: "#FF0000", start: .zero,
                                                                       end: CGPoint(x: 100, y: 100),
                                                                       fillColorHex: "#FF0000")),
                        frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        box.time = LayerTime(inMS: 0, outMS: 10_000)
        doc.layers.append(box)
        let refs = KeyLanesTests.refs(doc, first, .textSize, at: [3000])
            .union(KeyLanesTests.refs(doc, first, .scale, at: [3000]))
        guard let copied = doc.copyKeys(layerID: first, refs) else { return }
        #expect(doc.canPasteKeys(copied, layerID: box.id))
        let landed = doc.pasteKeys(copied, layerID: box.id, atDocumentMS: 1000)
        #expect(landed.count == 1)
        #expect(doc.keyLanes(layerID: box.id).map(\.property) == [.scale])
    }

    @Test func nothingPastesOntoASoundOrAMissingLayer() {
        var (doc, first) = KeyLanesTests.keyed()
        var sound = Layer(name: "Music", content: .sound(SoundRef(durationMS: 10_000)), frame: .zero)
        sound.time = LayerTime(inMS: 0, outMS: 10_000, sourceLengthMS: 10_000)
        doc.layers.append(sound)
        let refs = KeyLanesTests.refs(doc, first, .scale, at: [3000, 6000])
        guard let copied = doc.copyKeys(layerID: first, refs) else { return }
        #expect(!doc.canPasteKeys(copied, layerID: sound.id))
        #expect(doc.pasteKeys(copied, layerID: sound.id, atDocumentMS: 1000).isEmpty)
        #expect(doc.pasteKeys(copied, layerID: UUID(), atDocumentMS: 1000).isEmpty)
    }

    @Test func pastedKeysKeepHowTheyEase() {
        var (doc, first, second) = Self.twoTitles()
        doc.easeKeys(layerID: first, KeyLanesTests.refs(doc, first, .scale, at: [3000]), .easeOut)
        let refs = KeyLanesTests.refs(doc, first, .scale, at: [3000, 6000])
        guard let copied = doc.copyKeys(layerID: first, refs) else { return }
        doc.pasteKeys(copied, layerID: second, atDocumentMS: 2000)
        #expect(Self.lane(doc, second, .scale)?.keys.first?.ease == .easeOut)
    }

    // MARK: - The playhead on keys

    @Test func everyKeyOnTheTimelineIsAMomentThePlayheadCanLandOn() {
        var (doc, first, second) = Self.twoTitles()
        doc.startKeying(layerID: second, .motion(.opacity), atDocumentTimeMS: 1500)
        #expect(doc.keyMoments(layerIDs: nil) == [1500, 3000, 5000, 6000])
        #expect(doc.keyMoments(layerIDs: [first]) == [3000, 5000, 6000])
        #expect(doc.keyMoments(layerIDs: [second]) == [1500])
    }

    @Test func volumeKeysAreMomentsToo() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var sound = Layer(name: "Music", content: .sound(SoundRef(durationMS: 10_000)), frame: .zero)
        sound.time = LayerTime(inMS: 1000, outMS: 9000, sourceLengthMS: 10_000)
        doc.layers = [sound]
        doc.durationMS = 10_000
        doc.startKeying(layerID: sound.id, .volume, atDocumentTimeMS: 2000)
        doc.setKeyedValue(.number(-12), layerID: sound.id, .volume, atDocumentTimeMS: 5000)
        #expect(doc.keyMoments(layerIDs: nil) == [2000, 5000])
    }

    @Test func aPlayheadDraggedNearAKeyIsPulledOntoIt() {
        let moments = [3000, 5000, 6000]
        #expect(KeySnap.snapped(3060, to: moments, withinMS: 80) == 3000)
        #expect(KeySnap.snapped(4950, to: moments, withinMS: 80) == 5000)
        #expect(KeySnap.snapped(4000, to: moments, withinMS: 80) == 4000)
        // The nearest wins where two are in reach.
        #expect(KeySnap.snapped(5600, to: moments, withinMS: 500) == 6000)
        #expect(KeySnap.snapped(3060, to: [], withinMS: 80) == 3060)
    }

    @Test func thePlayheadStepsFromKeyToKeyAcrossEveryValue() {
        let (doc, first, second) = Self.twoTitles()
        #expect(doc.neighbourKeyMoment(layerIDs: [first], from: 0, forward: true) == 3000)
        #expect(doc.neighbourKeyMoment(layerIDs: [first], from: 3000, forward: true) == 5000)
        #expect(doc.neighbourKeyMoment(layerIDs: [first], from: 3010, forward: true) == 5000)
        #expect(doc.neighbourKeyMoment(layerIDs: [first], from: 6000, forward: true) == nil)
        #expect(doc.neighbourKeyMoment(layerIDs: [first], from: 6000, forward: false) == 5000)
        #expect(doc.neighbourKeyMoment(layerIDs: [first], from: 3000, forward: false) == nil)
        #expect(doc.neighbourKeyMoment(layerIDs: [second], from: 0, forward: true) == nil)
    }
}
