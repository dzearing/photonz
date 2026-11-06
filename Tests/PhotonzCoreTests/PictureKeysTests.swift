import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Animating a picture is setting moments and changing things
/// (`animating-a-picture-is-as-simple-as-setting-a-mo`,
/// `docs/design/mocks/pages/picture-keys.html`).
///
/// The user's words (2026-11-04): "I want to just start creating keyframes
/// where maybe I position something, save a keyframe, or click on one, adjust
/// some things ... and it persists on that keyframe and auto tweens." Their
/// answer on the card (2026-11-05): build it as shown.
///
/// Written before the model. Pinned here: the first Add Key on a still picture
/// is a hollow moment on a two second repeating lap, and it stays a picture; a
/// change on that layer keys itself and a value that was not animating joins;
/// a layer with no keys still changes for the whole picture; the lap repeats
/// or plays once; the last key going leaves a still; an animated SVG carries
/// it. Nothing about a picture nobody pressed Add Key on changes.
@Suite("A picture is animated by setting moments")
struct PictureKeysTests {

    // MARK: - Fixtures

    static func rectangle(_ name: String = "Bell", at origin: CGPoint = CGPoint(x: 100, y: 100)) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#336699")),
              frame: CGRect(origin: origin, size: CGSize(width: 80, height: 80)))
    }

    /// A still picture with two layers on it.
    static func still() -> (doc: PhotonzDocument, bell: UUID, badge: UUID) {
        let bell = rectangle()
        let badge = rectangle("Badge", at: CGPoint(x: 300, y: 300))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 900, height: 700), layers: [bell, badge])
        return (doc, bell.id, badge.id)
    }

    static func drag(_ doc: inout PhotonzDocument, _ id: UUID, by shift: CGPoint, atMS ms: Int) {
        doc.editPosedForCanvas(layerID: id, atDocumentTimeMS: ms) { document in
            document.updateLayer(id: id) {
                $0.frame.origin.x += shift.x
                $0.frame.origin.y += shift.y
            }
        }
    }

    static func point(_ value: MotionValue?) -> CGPoint? {
        if case let .point(point)? = value { return point }
        return nil
    }

    static func number(_ value: MotionValue?) -> Double? {
        if case let .number(number)? = value { return number }
        return nil
    }

    // MARK: - The first Add Key

    @Test func aStillPictureHasNoKeyClock() {
        let (doc, bell, _) = Self.still()
        #expect(!doc.hasKeyClock)
        #expect(!doc.isKeyedPicture)
        #expect(!doc.isAnimating(layerID: bell))
        #expect(doc.keyMomentDiamond(layerID: bell, atDocumentTimeMS: 0) == .dormant)
    }

    @Test func theFirstAddKeyIsAHollowMomentOnATwoSecondRepeatingLap() {
        var (doc, bell, _) = Self.still()
        let added = doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(added)
        #expect(doc.isKeyedPicture)
        #expect(doc.hasKeyClock)
        #expect(doc.motionCycleLengthMS == 2000)
        #expect(doc.keyLap?.repeats == true)
        #expect(doc.keyLanes(layerID: bell).isEmpty)
        #expect(doc.clipKeyMarks(layerID: bell).map(\.isHollow) == [true])
        #expect(doc.keyMomentDiamond(layerID: bell, atDocumentTimeMS: 0) == .onKey)
        #expect(doc.keyMomentDiamond(layerID: bell, atDocumentTimeMS: 900) == .betweenKeys)
    }

    @Test func itStaysAPicture() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(!doc.hasTime)
        #expect(doc.timelineLengthMS == 2000)
    }

    @Test func aLapSomebodyWroteDownIsKept() {
        var (doc, bell, _) = Self.still()
        doc.motionCycleMS = 3500
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(doc.motionCycleLengthMS == 3500)
    }

    @Test func addKeyTwiceAtOneMomentDoesNothing() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        let again = doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(!again)
    }

    // MARK: - A change keys itself

    @Test func aDragFillsTheHollowMoment() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 40, y: 0), atMS: 0)
        #expect(doc.keyLanes(layerID: bell).map(\.property) == [.position])
        #expect(doc.clipKeyMarks(layerID: bell).map(\.isHollow) == [false])
        #expect(Self.point(doc.keyedValue(layerID: bell, .motion(.position), atDocumentTimeMS: 0))
            == CGPoint(x: 140, y: 100))
    }

    @Test func aSecondMomentTweens() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        #expect(doc.keyCount(layerID: bell, .motion(.position)) == 2)
        let middle = Self.point(doc.keyedValue(layerID: bell, .motion(.position), atDocumentTimeMS: 500))
        #expect((middle?.x ?? 0) > 101 && (middle?.x ?? 0) < 200)
        let shown = doc.moved(toMotionTimeMS: 500).layer(id: bell)?.frame.minX ?? 0
        #expect(abs(shown - (middle?.x ?? 0)) < 0.5)
    }

    @Test func theLayerStaysWhereItWasStored() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 40, y: 0), atMS: 0)
        #expect(doc.layer(id: bell)?.frame.minX == 100)
    }

    @Test func aDragAtAMomentReadsThePoseNotTheStoredPlace() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        Self.drag(&doc, bell, by: CGPoint(x: 10, y: 0), atMS: 1000)
        #expect(Self.point(doc.keyedValue(layerID: bell, .motion(.position), atDocumentTimeMS: 1000))?.x == 210)
    }

    @Test func aFadeJoinsHoldingItsOldValueAtTheKeyBefore() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 40, y: 0), atMS: 0)
        doc.editLooks(layerIDs: [bell], atDocumentTimeMS: 1000) { document in
            document.updateLayer(id: bell) { $0.style.opacity = 0.4 }
        }
        #expect(Set(doc.keyLanes(layerID: bell).map(\.property)) == [.position, .opacity])
        #expect(Self.number(doc.keyedValue(layerID: bell, .motion(.opacity), atDocumentTimeMS: 0)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: bell, .motion(.opacity), atDocumentTimeMS: 1000)) == 40)
        #expect(doc.layer(id: bell)?.style.opacity == 1)
    }

    @Test func thePanelRowsReadTheLookAtThePlayhead() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        doc.editLooks(layerIDs: [bell], atDocumentTimeMS: 1000) { document in
            document.updateLayer(id: bell) { $0.style.opacity = 0.4 }
        }
        let worn = doc.lookPosed(layerIDs: [bell], atDocumentTimeMS: 1000).layer(id: bell)?.style.opacity ?? 0
        #expect(abs(worn - 0.4) < 0.001)
    }

    @Test func theCanvasIsPosedAtThePlayhead() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        #expect(doc.posedForCanvas(atTimeMS: 1000).layer(id: bell)?.frame.minX == 200)
    }

    @Test func aTurnAndAResizeKeyThemselves() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        doc.editPosedForCanvas(layerID: bell, atDocumentTimeMS: 500) { document in
            document.updateLayer(id: bell) { $0.transform.rotation = .pi / 2 }
        }
        doc.editPosedForCanvas(layerID: bell, atDocumentTimeMS: 1000) { document in
            document.updateLayer(id: bell) { $0.frame = $0.frame.insetBy(dx: -20, dy: -20) }
        }
        #expect(Set(doc.keyLanes(layerID: bell).map(\.property)).isSuperset(of: [.rotation, .scale]))
        #expect(doc.layer(id: bell)?.transform.rotation == 0)
        #expect(doc.layer(id: bell)?.frame.width == 80)
    }

    @Test func aLayerInsideAFrameIsPosedAtThePlayhead() throws {
        var doc = SVGMotionExportTests.iconInAFrame()
        let frame = try #require(doc.layers.first { $0.isFrame })
        let child = try #require(frame.children.first)
        doc.updateLayer(id: child.id) { $0.motions = nil }
        let start = child.frame.minX
        doc.addKeyMoment(layerID: child.id, atDocumentTimeMS: 0)
        Self.drag(&doc, child.id, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, child.id, by: CGPoint(x: 9, y: 0), atMS: 400)
        #expect(doc.posedForCanvas(atTimeMS: 400).layer(id: child.id)?.frame.minX == start + 10)
        #expect(doc.layer(id: child.id)?.frame.minX == start)
    }

    // MARK: - Never by surprise

    @Test func aLayerWithNoKeysChangesForTheWholePicture() {
        var (doc, bell, badge) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(!doc.isAnimating(layerID: badge))
        Self.drag(&doc, badge, by: CGPoint(x: 25, y: 0), atMS: 1000)
        #expect(doc.layer(id: badge)?.frame.minX == 325)
        #expect(doc.layer(id: badge)?.hasMotion == false)
    }

    // MARK: - Repeat, and the length

    @Test func theLapRepeatsWhenItPlaysPastTheEnd() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        #expect(doc.moved(toMotionTimeMS: 2000).layer(id: bell)?.frame.minX == 101)
        #expect(!doc.motionHasSettled(atMS: 60000))
    }

    @Test func playOnceHoldsTheLastKeyAndSettles() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        doc.setKeyLapRepeats(false)
        #expect(doc.moved(toMotionTimeMS: 2500).layer(id: bell)?.frame.minX == 200)
        #expect(doc.motionHasSettled(atMS: 2000))
        #expect(!doc.motionHasSettled(atMS: 1999))
    }

    @Test func aMotionOfItsOwnPaceKeepsItsPaceThroughTheLap() {
        var (doc, bell, badge) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        let spin = LayerMotion(property: .rotation, from: .number(0), to: .number(360),
                               timing: MotionTiming(startMS: 0, durationMS: 700), repeats: .forever)
        doc.updateLayer(id: badge) { $0.motions = [spin] }
        let reference = spin.value(atMS: 2100, cycleMS: 2000)
        #expect(doc.moved(toMotionTimeMS: 2100).layer(id: badge)?.transform.rotation
            == (Self.number(reference).map { CGFloat($0 * .pi / 180) }))
    }

    @Test func theLengthCannotCrossTheLastKey() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 1200)
        #expect(doc.shortestKeyLapMS == 1201)
    }

    @Test func theRulerReadsSecondsAndLeavesTheEndToTheWord() {
        #expect(KeyLap.ticks(lapMS: 2000).map(\.label) == ["0s", "1s"])
        #expect(KeyLap.ticks(lapMS: 900).map(\.label) == ["0s", "0.5s"])
        #expect(KeyLap.ticks(lapMS: 400).map(\.label) == ["0s", "0.1s", "0.2s", "0.3s"])
    }

    @Test func theBarReadsHundredths() {
        #expect(KeyLap.timecode(ms: 1500) == "0:01.50")
        #expect(KeyLap.timecode(ms: 2000) == "0:02.00")
        #expect(KeyLap.timecode(ms: 61230) == "1:01.23")
    }

    // MARK: - Back to a still

    @Test func theLastKeyGoingLeavesAStill() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 40, y: 0), atMS: 0)
        doc.removeKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(!doc.isKeyedPicture)
        #expect(!doc.hasKeyClock)
        #expect(doc.layer(id: bell)?.frame.minX == 140)
        #expect(doc.layer(id: bell)?.hasMotion == false)
    }

    @Test func removingAHollowMomentLeavesAStill() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        doc.removeKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(!doc.isKeyedPicture)
    }

    @Test func theLapOutlivesOneLayerLosingItsKeys() {
        var (doc, bell, badge) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        doc.addKeyMoment(layerID: badge, atDocumentTimeMS: 0)
        doc.removeKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        #expect(doc.isKeyedPicture)
    }

    // MARK: - Animate a property, the way in that stays

    @Test func animateOnAStillPictureStartsTheLapWithOneKey() {
        var (doc, bell, _) = Self.still()
        let started = doc.animate(layerID: bell, .motion(.opacity), atDocumentTimeMS: 0)
        #expect(started)
        #expect(doc.isKeyedPicture)
        #expect(doc.keyCount(layerID: bell, .motion(.opacity)) == 1)
    }

    // MARK: - What nobody pressed Add Key on

    @Test func aFromAndToMotionOnAPictureIsLeftAlone() {
        var (doc, bell, _) = Self.still()
        let swing = LayerMotion(property: .rotation, from: .number(-15), to: .number(15),
                                timing: MotionTiming(startMS: 0, durationMS: 900), repeats: .foreverThereAndBack)
        doc.updateLayer(id: bell) { $0.motions = [swing] }
        #expect(!doc.hasKeyClock)
        #expect(!doc.isAnimating(layerID: bell))
        #expect(doc.posedForCanvas(atTimeMS: 300).layer(id: bell)?.transform.rotation == 0)
    }

    @Test func aMotionSavedAsOnceIsNotKeysUntilAddKeyIsPressed() {
        var (doc, bell, _) = Self.still()
        let once = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                               timing: MotionTiming(startMS: 0, durationMS: 900), repeats: .once)
        doc.updateLayer(id: bell) { $0.motions = [once] }
        #expect(!doc.isKeyedPicture)
        #expect(doc.motionHasSettled(atMS: 900))
    }

    // MARK: - The file

    @Test func aStillPictureWritesNoLap() throws {
        let (doc, _, _) = Self.still()
        let text = String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
        #expect(!text.contains("keyLap"))
    }

    @Test func theLapSurvivesSaving() throws {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        doc.setKeyLapRepeats(false)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
        #expect(back.keyLap?.repeats == false)
        #expect(back.isKeyedPicture)
    }

    @Test func oneFrameTakenOutOfThePictureKeepsItsLap() {
        var doc = SVGMotionExportTests.iconInAFrame()
        let frame = doc.layers.first { $0.isFrame }
        let child = frame?.children.first
        doc.addKeyMoment(layerID: child?.id ?? UUID(), atDocumentTimeMS: 0)
        #expect(doc.keyLap != nil)
        #expect(doc.frameDocument(id: frame?.id ?? UUID())?.keyLap == doc.keyLap)
    }

    // MARK: - A still out of a keyed picture

    @Test func aStillIsTheFirstMomentNotWhereTheLayerWasStored() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 40, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 60, y: 0), atMS: 1000)
        #expect(doc.layer(id: bell)?.frame.minX == 100)
        #expect(doc.keyedStill.layer(id: bell)?.frame.minX == 140)
    }

    @Test func aStillSVGIsTheFirstMomentToo() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 40, y: 0), atMS: 0)
        let svg = SVGExport.write(doc).text
        #expect(svg.contains("translate(140 100)"))
        #expect(!svg.contains("animate"))
    }

    @Test func aStillOfAPictureWithNoKeysIsThePicture() {
        let (doc, _, _) = Self.still()
        #expect(doc.keyedStill == doc)
    }

    // MARK: - The animated SVG

    @Test func anAnimatedSVGRepeatsAndCarriesTheKeyTimes() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        let svg = SVGMotionExportTests.moving(doc)
        #expect(svg.contains("dur=\"2000ms\""))
        #expect(svg.contains("repeatCount=\"indefinite\""))
        #expect(svg.contains("keyTimes=\"0;0.5"))
    }

    @Test func aPictureThatPlaysOnceWritesOneLapAndFreezes() {
        var (doc, bell, _) = Self.still()
        doc.addKeyMoment(layerID: bell, atDocumentTimeMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 1, y: 0), atMS: 0)
        Self.drag(&doc, bell, by: CGPoint(x: 99, y: 0), atMS: 1000)
        doc.setKeyLapRepeats(false)
        let svg = SVGMotionExportTests.moving(doc)
        #expect(svg.contains("repeatCount=\"1\""))
        #expect(svg.contains("fill=\"freeze\""))
    }
}
