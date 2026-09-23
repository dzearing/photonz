import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Every value in the panel has a key diamond (task
/// `every-value-in-the-panel-has-a-key-diamond`).
///
/// Written before the model. The whole of it is Premiere's stopwatch: a
/// diamond beside a value starts keying it with one key at the playhead; after
/// that, changing the value at another moment, in the panel or on the canvas,
/// adds a key there; the diamond is filled on a key and hollow between keys;
/// arrows step to the key before and after. There is no second model: a keyed
/// value IS a `LayerMotion` that plays once, and a keyed volume IS the level
/// points the mixer already follows.
@Suite("Key diamonds")
struct PropertyKeysTests {

    // MARK: - Fixtures

    /// Ten seconds, with a title on screen from 2s to 8s.
    static func withTitle() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers = [title]
        doc.durationMS = 10_000
        return (doc, title.id)
    }

    /// A clip whose first two seconds were trimmed off: its own clock runs two
    /// seconds ahead of the document's.
    static func withTrimmedClip() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 6000, sourceInMS: 2000, sourceLengthMS: 8000)
        doc.layers = [clip]
        doc.durationMS = 6000
        return (doc, clip.id)
    }

    static func number(_ value: MotionValue?) -> Double? {
        if case let .number(number) = value { return number }
        return nil
    }

    // MARK: - The diamond starts keying

    @Test func aValueNobodyHasKeyedIsDormant() {
        let (doc, id) = Self.withTitle()
        #expect(doc.keyDiamond(layerID: id, .motion(.scale), atDocumentTimeMS: 3000) == .dormant)
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 0)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)) == 100)
    }

    @Test func theDiamondStartsKeyingWithOneKeyAtThePlayhead() {
        var (doc, id) = Self.withTitle()
        let done1 = doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        #expect(done1)
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 1)
        #expect(doc.keyDiamond(layerID: id, .motion(.scale), atDocumentTimeMS: 3000) == .onKey)
        #expect(doc.keyDiamond(layerID: id, .motion(.scale), atDocumentTimeMS: 5000) == .betweenKeys)
        // One key is a constant: the value it was keyed at, everywhere.
        for moment in [2000, 3000, 7000] {
            #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: moment)) == 100)
        }
        // Keyed on the title's own clock, a second after it comes on.
        let motion = doc.layer(id: id)?.motions?.first
        #expect(motion?.keyframes.map(\.atMS) == [1000])
        #expect(motion?.repeats == .once)
    }

    @Test func changingTheValueAtAnotherMomentAddsAKey() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        let done2 = doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        #expect(done2)
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 2)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 6000)) == 200)
        // Between the two it is on its way, and before and after it holds.
        let middle = Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 4500)) ?? 0
        #expect(middle > 100 && middle < 200)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 2100)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 7900)) == 200)
        #expect(doc.keyDiamond(layerID: id, .motion(.scale), atDocumentTimeMS: 4500) == .betweenKeys)
    }

    @Test func changingTheValueOnAKeyRewritesThatKey() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(40), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 1)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 7000)) == 40)
    }

    @Test func aKeyAddedBeforeTheFirstOrBetweenTwoLandsInOrder() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 5000)
        doc.setKeyedValue(.number(90), layerID: id, .motion(.rotation), atDocumentTimeMS: 7000)
        doc.setKeyedValue(.number(-30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(45), layerID: id, .motion(.rotation), atDocumentTimeMS: 6000)
        let keys = doc.layer(id: id)?.motions?.first?.keyframes
        #expect(keys?.map(\.atMS) == [1000, 3000, 4000, 5000])
        #expect(keys?.map { Self.number($0.value) } == [-30, 0, 45, 90])
    }

    @Test func changingADormantValueChangesTheLayerAndKeysNothing() {
        var (doc, id) = Self.withTitle()
        let done3 = doc.setKeyedValue(.number(50), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        #expect(done3)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 0)
        #expect(doc.layer(id: id)?.style.opacity == 0.5)
    }

    // MARK: - Arrows step between keys

    @Test func theArrowsStepToTheKeyBeforeAndAfter() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(150), layerID: id, .motion(.scale), atDocumentTimeMS: 5000)
        doc.setKeyedValue(.number(120), layerID: id, .motion(.scale), atDocumentTimeMS: 7000)
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 4000, forward: true) == 5000)
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 5000, forward: true) == 7000)
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 7000, forward: true) == nil)
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 5000, forward: false) == 3000)
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 3000, forward: false) == nil)
    }

    @Test func onAClipKeysFollowTheFramesNotTheDocument() {
        // The clip's first two seconds were trimmed off, so a key made at 1s
        // of the document sits on 3s of the recording, and stepping to it
        // lands back on 1s of the document.
        var (doc, id) = Self.withTrimmedClip()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 4000)
        #expect(doc.layer(id: id)?.motions?.first?.keyframes.map(\.atMS) == [3000, 6000])
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 2500, forward: false) == 1000)
        #expect(doc.neighbourKeyTime(layerID: id, .motion(.scale), from: 2500, forward: true) == 4000)
    }

    // MARK: - Taking keys away

    @Test func removingAKeyLeavesTheRest() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(150), layerID: id, .motion(.scale), atDocumentTimeMS: 5000)
        doc.setKeyedValue(.number(120), layerID: id, .motion(.scale), atDocumentTimeMS: 7000)
        let done4 = doc.removeKey(layerID: id, .motion(.scale), atDocumentTimeMS: 5000)
        #expect(done4)
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 2)
        let done5 = doc.removeKey(layerID: id, .motion(.scale), atDocumentTimeMS: 4000)
        #expect(!done5)
    }

    @Test func stoppingKeyingKeepsTheValueAtThePlayhead() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(20), layerID: id, .motion(.opacity), atDocumentTimeMS: 5000)
        let done6 = doc.stopKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 6000)
        #expect(done6)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 0)
        #expect(doc.layer(id: id)?.motions == nil)
        #expect(doc.layer(id: id)?.style.opacity == 0.2)
        #expect(doc.keyDiamond(layerID: id, .motion(.opacity), atDocumentTimeMS: 6000) == .dormant)
    }

    @Test func stoppingAKeyedScaleKeepsTheSizeAtThePlayhead() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 5000)
        doc.stopKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        // Twice as wide; words re-fit their box's height to the type they carry.
        #expect(doc.layer(id: id)?.frame.width == 800)
        #expect((doc.layer(id: id)?.frame.height ?? 0) > 80)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 6000)) == 100)
    }

    // MARK: - The picture moves between keys

    @Test func thePictureMovesBetweenKeys() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        let before = doc.drawn(atTimeMS: 3000).layer(id: id)?.frame.width
        let between = doc.drawn(atTimeMS: 4500).layer(id: id)?.frame.width ?? 0
        let after = doc.drawn(atTimeMS: 7000).layer(id: id)?.frame.width
        #expect(before == 400)
        #expect(between > 400 && between < 800)
        #expect(after == 800)
    }

    // MARK: - New things that key

    @Test func cornersShadowAndTypeSizeKeyToo() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.textSize), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(96), layerID: id, .motion(.textSize), atDocumentTimeMS: 6000)
        doc.startKeying(layerID: id, .motion(.shadow), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(20), layerID: id, .motion(.shadow), atDocumentTimeMS: 6000)
        let late = doc.drawn(atTimeMS: 7000).layer(id: id)
        #expect(late?.text?.fontSize == 96)
        #expect(late?.style.shadows.first?.radius == 20)
        // ...and before the second key there was no shadow to speak of.
        #expect((doc.drawn(atTimeMS: 3000).layer(id: id)?.style.shadows.first?.radius ?? 0) == 0)

        var (clipDoc, clip) = Self.withTrimmedClip()
        clipDoc.startKeying(layerID: clip, .motion(.cornerRadius), atDocumentTimeMS: 0)
        clipDoc.setKeyedValue(.number(40), layerID: clip, .motion(.cornerRadius), atDocumentTimeMS: 2000)
        #expect(clipDoc.drawn(atTimeMS: 3000).layer(id: clip)?.roundedCornerRadii.uniform == 40)
    }

    @Test func aLayerListsTheValuesItCanKey() {
        let (doc, id) = Self.withTitle()
        let title = doc.layer(id: id)
        #expect(title?.keyableProperties.contains(.motion(.textSize)) == true)
        #expect(title?.keyableProperties.contains(.motion(.position)) == true)
        #expect(title?.keyableProperties.contains(.volume) == false)
        let (clipDoc, clip) = Self.withTrimmedClip()
        #expect(clipDoc.layer(id: clip)?.keyableProperties.contains(.motion(.textSize)) == false)
        #expect(clipDoc.layer(id: clip)?.keyableProperties.contains(.motion(.cornerRadius)) == true)
        #expect(clipDoc.layer(id: clip)?.keyableProperties.contains(.motion(.blur)) == true)
    }

    // MARK: - Volume keys are the mixer's own points

    @Test func volumeKeysAreTheLevelPoints() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var sound = Layer(name: "Music", content: .sound(SoundRef(durationMS: 10_000)),
                          frame: .zero)
        sound.time = LayerTime(inMS: 1000, outMS: 9000, sourceLengthMS: 10_000)
        doc.layers = [sound]
        doc.durationMS = 10_000
        let id = sound.id
        #expect(doc.layer(id: id)?.keyableProperties.contains(.volume) == true)
        #expect(doc.layer(id: id)?.keyableProperties.contains(.motion(.position)) == false)
        #expect(doc.keyDiamond(layerID: id, .volume, atDocumentTimeMS: 2000) == .dormant)
        let done7 = doc.startKeying(layerID: id, .volume, atDocumentTimeMS: 2000)
        #expect(done7)
        doc.setKeyedValue(.number(-12), layerID: id, .volume, atDocumentTimeMS: 5000)
        let points = doc.layer(id: id)?.soundLevel?.points ?? []
        #expect(points.map(\.atMS) == [1000, 4000])
        #expect(doc.keyDiamond(layerID: id, .volume, atDocumentTimeMS: 5000) == .onKey)
        let late = Self.number(doc.keyedValue(layerID: id, .volume, atDocumentTimeMS: 6000)) ?? 0
        #expect(abs(late - -12) < 0.01)
        #expect(doc.neighbourKeyTime(layerID: id, .volume, from: 5000, forward: false) == 2000)
        doc.stopKeying(layerID: id, .volume, atDocumentTimeMS: 6000)
        #expect(doc.layer(id: id)?.soundLevel?.points.isEmpty ?? true)
        let fader = doc.layer(id: id)?.soundLevel?.gain ?? 1
        #expect(abs((AudioLevel.decibels(forGain: fader) ?? 0) - -12) < 0.01)
    }

    // MARK: - A drag on the canvas becomes a key

    @Test func draggingAKeyedLayerOnTheCanvasAddsAPositionKey() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        guard let before = doc.layer(id: id) else { Issue.record("no layer"); return }
        // The canvas moved the drawn layer 300 to the right at 6s.
        doc.updateLayer(id: id) { $0.frame.origin.x += 300 }
        let done8 = doc.foldEditIntoKeys(layerID: id, before: before, atDocumentTimeMS: 6000)
        #expect(done8)
        // The layer as drawn has not moved: the move is a key.
        #expect(doc.layer(id: id)?.frame.origin == CGPoint(x: 100, y: 100))
        #expect(doc.keyCount(layerID: id, .motion(.position)) == 2)
        #expect(doc.drawn(atTimeMS: 6000).layer(id: id)?.frame.origin == CGPoint(x: 400, y: 100))
        #expect(doc.drawn(atTimeMS: 3000).layer(id: id)?.frame.origin == CGPoint(x: 100, y: 100))
    }

    @Test func aDragOnAnUnkeyedLayerIsLeftAlone() {
        var (doc, id) = Self.withTitle()
        guard let before = doc.layer(id: id) else { Issue.record("no layer"); return }
        doc.updateLayer(id: id) { $0.frame.origin.x += 300 }
        let done9 = doc.foldEditIntoKeys(layerID: id, before: before, atDocumentTimeMS: 6000)
        #expect(!done9)
        #expect(doc.layer(id: id)?.frame.origin.x == 400)
    }

    @Test func turningAndResizingAKeyedLayerAddKeys() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        guard let before = doc.layer(id: id) else { Issue.record("no layer"); return }
        doc.updateLayer(id: id) {
            $0.transform.rotation = .pi / 2
            $0.frame = CGRect(x: 100, y: 100, width: 600, height: 120)
        }
        doc.foldEditIntoKeys(layerID: id, before: before, atDocumentTimeMS: 6000)
        // Its size goes back to the stored one; with its place NOT keyed, the
        // stored layer moves by as far as the middle travelled, so the corner
        // the hand held stays where it was.
        #expect(doc.layer(id: id)?.frame == before.frame.offsetBy(dx: 100, dy: 20))
        #expect(doc.layer(id: id)?.transform.rotation == before.transform.rotation)
        let turned = Self.number(doc.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 6000)) ?? 0
        #expect(abs(turned - 90) < 0.001)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 6000)) == 150)
    }

    // MARK: - What a document written before this reads as

    @Test func existingMotionsReadAsKeys() {
        // A title's fade is four keys on one Opacity motion, and the diamond
        // reads it that way with nothing converted.
        var (doc, id) = Self.withTitle()
        doc.setTitleFade(id, toMS: 500)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 4)
        #expect(doc.keyDiamond(layerID: id, .motion(.opacity), atDocumentTimeMS: 2000) == .onKey)
    }

    @Test func aKeyedMotionRoundTrips() throws {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.textSize), atDocumentTimeMS: 3000)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.keyCount(layerID: id, .motion(.textSize)) == 1)
    }

    // MARK: - The handles go where the picture is

    @Test func theCanvasIsHandedTheLayerWhereItsKeysPutIt() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 700, y: 100)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 6000)
        let posed = doc.posedForCanvas(atTimeMS: 7000)
        #expect(posed.layer(id: id)?.frame.origin == CGPoint(x: 700, y: 100))
        // ...and nothing about the stored layer moved.
        #expect(doc.layer(id: id)?.frame.origin == CGPoint(x: 100, y: 100))
    }

    @Test func aDragReadAgainstThePoseLandsAsAKeyFromThere() {
        // The hand grabbed the posed layer at (700, 100) and moved it 50 down.
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 700, y: 100)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 6000)
        guard let stored = doc.layer(id: id),
              let posed = doc.posedForCanvas(atTimeMS: 7000).layer(id: id) else {
            Issue.record("no layer"); return
        }
        doc.updateLayer(id: id) { $0.frame.origin = CGPoint(x: 700, y: 150) }
        doc.foldEditIntoKeys(layerID: id, before: posed, restoring: stored, atDocumentTimeMS: 7000)
        #expect(doc.layer(id: id)?.frame.origin == CGPoint(x: 100, y: 100))
        #expect(doc.drawn(atTimeMS: 7000).layer(id: id)?.frame.origin == CGPoint(x: 700, y: 150))
        #expect(doc.keyCount(layerID: id, .motion(.position)) == 3)
    }

    @Test func aStillDocumentIsHandedOverAsItIs() {
        let (doc, id) = Self.withTitle()
        #expect(doc.posedForCanvas(atTimeMS: 5000).layer(id: id) == doc.layer(id: id))
    }

    @Test func aMoveOnALayerWhoseSizeAloneIsKeyedMovesItAndKeepsItsSize() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        guard let stored = doc.layer(id: id),
              let posed = doc.posedForCanvas(atTimeMS: 7000).layer(id: id) else {
            Issue.record("no layer"); return
        }
        // Dragged 40 to the right, as posed: twice the size it is stored at.
        doc.updateLayer(id: id) { $0.frame = posed.frame.offsetBy(dx: 40, dy: 0) }
        let made = doc.foldEditIntoKeys(layerID: id, before: posed, restoring: stored, atDocumentTimeMS: 7000)
        #expect(!made)
        #expect(doc.layer(id: id)?.frame == stored.frame.offsetBy(dx: 40, dy: 0))
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 2)
    }

    @Test func anEditThatChangedNothingPutsTheStoredLayerBack() {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 700, y: 100)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 6000)
        guard let stored = doc.layer(id: id),
              let posed = doc.posedForCanvas(atTimeMS: 7000).layer(id: id) else {
            Issue.record("no layer"); return
        }
        // Escape: the canvas commits the frame it started from, the pose.
        doc.updateLayer(id: id) { $0.frame = posed.frame }
        doc.foldEditIntoKeys(layerID: id, before: posed, restoring: stored, atDocumentTimeMS: 7000)
        #expect(doc.layer(id: id) == stored)
    }
}
