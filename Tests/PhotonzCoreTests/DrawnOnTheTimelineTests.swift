import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Anything drawn on a video gets its own row on the timeline
/// (`anything-you-draw-on-a-video-gets-its-own-row-on`).
///
/// The user's words: "If I drag a rectangle on the video canvas, I expect that
/// to show up on the timeline in its own layer, this lets me say when it's
/// visible and when it's not. It lets me take a keyframe, move the cursor over,
/// and take another keyframe to animate it tweening between points."
///
/// Written before the model. Three things are pinned here: the stretch a thing
/// drawn at the playhead is given, the row it lands on, and the one press that
/// keys where it is, how big, how turned and how faded.
@Suite("Anything drawn on a video is on the timeline")
struct DrawnOnTheTimelineTests {

    // MARK: - Fixtures

    static func clip(_ name: String, inMS: Int, outMS: Int) -> Layer {
        var clip = Layer(name: name,
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: inMS, outMS: outMS, sourceInMS: 0, sourceLengthMS: outMS - inMS)
        return clip
    }

    /// An eight second recording as the document it opens as.
    static func eightSeconds() -> PhotonzDocument {
        PhotonzDocument.recording(HeldFrameTests.movie(), name: "Take 1")
    }

    /// Two four second clips back to back.
    static func twoClips() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        doc.layers = [clip("First", inMS: 0, outMS: 4000), clip("Second", inMS: 4000, outMS: 8000)]
        doc.durationMS = 8000
        return doc
    }

    static func rectangle(_ name: String = "Rectangle") -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
              frame: CGRect(x: 400, y: 300, width: 200, height: 120))
    }

    // MARK: - The stretch it is given

    @Test func aShapeDrawnOnARecordingRunsFromThePlayheadToTheEndOfTheClip() {
        let doc = Self.eightSeconds()
        #expect(doc.drawnSpan(atTimeMS: 1000) == LayerTime(inMS: 1000, outMS: 8000))
    }

    @Test func itRunsToTheEndOfTheClipUnderThePlayheadNotTheWholeFilm() {
        let doc = Self.twoClips()
        #expect(doc.drawnSpan(atTimeMS: 1000) == LayerTime(inMS: 1000, outMS: 4000))
        #expect(doc.drawnSpan(atTimeMS: 5000) == LayerTime(inMS: 5000, outMS: 8000))
    }

    @Test func drawnAtTheEndItTakesTheLastFiveSecondsSoItIsStillOnScreen() {
        let doc = Self.eightSeconds()
        let span = doc.drawnSpan(atTimeMS: 7999)
        #expect(span == LayerTime(inMS: 3000, outMS: 8000))
        #expect(span?.contains(ms: 7999) == true)
        #expect(DrawnTime.atTheEndMS == 5000)
    }

    @Test func drawnAtTheEndOfAShortFilmItTakesAllOfIt() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.clip("Short", inMS: 0, outMS: 2000)]
        doc.durationMS = 2000
        #expect(doc.drawnSpan(atTimeMS: 2000) == LayerTime(inMS: 0, outMS: 2000))
    }

    @Test func drawnOnAHeldFrameItTakesTheHold() {
        var (doc, _) = HeldFrameTests.held()
        guard let held = doc.heldFrame(atTimeMS: 4500) else {
            Issue.record("no held frame at 4.5s")
            return
        }
        #expect(doc.drawnSpan(atTimeMS: 4500) == held.span)
        doc.addLayerDrawn(Self.rectangle(), atTimeMS: 4500, placingInTime: true)
        #expect(doc.layers.last?.time == held.span)
    }

    @Test func aPictureHasNoTimeToPlaceAnythingIn() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        #expect(doc.drawnSpan(atTimeMS: 0) == nil)
    }

    // MARK: - The row it lands on

    @Test func aShapeDrawnOnARecordingGetsItsOwnRowNamedAfterIt() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        let placed = doc.layer(id: shape.id)
        #expect(placed?.time == LayerTime(inMS: 1000, outMS: 8000))
        #expect(placed?.isPlacedInTime == true)
        #expect(doc.timelineClipLayers.map(\.id).contains(shape.id))
        let track = doc.trackID(ofClip: shape.id).flatMap { doc.track(id: $0) }
        #expect(track?.name == "Rectangle")
        #expect(track?.kind == .video)
        // Its own row, above the recording's.
        #expect(doc.timelineTracks.map(\.name) == ["Rectangle", "V1", "Audio"])
    }

    @Test func twoShapesOfOneNameGetTwoRowsYouCanTellApart() {
        var doc = Self.eightSeconds()
        doc.addLayerDrawn(Self.rectangle(), atTimeMS: 1000, placingInTime: true)
        doc.addLayerDrawn(Self.rectangle(), atTimeMS: 2000, placingInTime: true)
        let names = doc.timelineTracks.map(\.name)
        #expect(names.filter { $0.hasPrefix("Rectangle") }.count == 2)
        #expect(Set(names).count == names.count)
    }

    @Test func aDrawingOnARecordingIsUnchangedWhenNotAskedToPlaceIt() {
        // Current and every release without the switch: a mark drawn over a
        // stretch that plays stands over the whole film, as it always has.
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000)
        #expect(doc.layer(id: shape.id)?.time == nil)
        #expect(!doc.timelineClipLayers.map(\.id).contains(shape.id))
    }

    @Test func aShapeDrawnOnAPictureHasNoTimeAndNoTimeline() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 0, placingInTime: true)
        #expect(doc.layer(id: shape.id)?.time == nil)
        #expect(doc.timelineTracks.isEmpty)
    }

    @Test func somethingThatAlreadyHasAStretchKeepsIt() {
        var doc = Self.eightSeconds()
        var title = Self.rectangle("Hello")
        title.time = LayerTime(inMS: 2000, outMS: 5000)
        doc.addLayerDrawn(title, atTimeMS: 1000, placingInTime: true)
        #expect(doc.layer(id: title.id)?.time == LayerTime(inMS: 2000, outMS: 5000))
    }

    @Test func itsBarsEndsMoveLikeATitles() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        let did1 = doc.moveLayerEnd(shape.id, toMS: 3000)
        #expect(did1)
        let did2 = doc.moveLayerStart(shape.id, toMS: 1500)
        #expect(did2)
        #expect(doc.layer(id: shape.id)?.time == LayerTime(inMS: 1500, outMS: 3000))
        // Off screen outside its stretch, on screen inside it.
        #expect(doc.drawn(atTimeMS: 1000).layer(id: shape.id)?.isVisible != true)
        #expect(doc.drawn(atTimeMS: 2000).layer(id: shape.id)?.isVisible == true)
    }

    @Test func itsBarSlidesAndCarriesOntoAnotherTrackLikeAClip() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        _ = doc.moveLayerEnd(shape.id, toMS: 3000)
        let slid = doc.moveClip(shape.id, toInMS: 2000)
        #expect(slid)
        #expect(doc.layer(id: shape.id)?.time == LayerTime(inMS: 2000, outMS: 4000))
        let other = doc.addTrack(.video)
        let carried = doc.moveClip(shape.id, toTrack: other)
        #expect(carried)
        #expect(doc.trackID(ofClip: shape.id) == other)
    }

    // MARK: - One press keys the whole of where it is

    @Test func onePressKeysPlaceSizeTurnAndFadeAtThePlayhead() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        #expect(doc.transformKeyDiamond(layerID: shape.id, atDocumentTimeMS: 1000) == .dormant)
        let did3 = doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 1000)
        #expect(did3)
        for property in PhotonzDocument.transformKeyProperties {
            #expect(doc.keyCount(layerID: shape.id, .motion(property)) == 1, "\(property)")
        }
        #expect(doc.transformKeyDiamond(layerID: shape.id, atDocumentTimeMS: 1000) == .onKey)
        #expect(doc.transformKeyDiamond(layerID: shape.id, atDocumentTimeMS: 2500) == .betweenKeys)
    }

    @Test func theTransformKeyIsPlaceSizeTurnAndFade() {
        #expect(PhotonzDocument.transformKeyProperties == [.position, .scale, .rotation, .opacity])
    }

    @Test func aDragLaterOnMakesTheSecondKeyAndItTweens() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        _ = doc.moveLayerEnd(shape.id, toMS: 3000)
        doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 1000)

        // The hand drags it 300 across at three seconds.
        guard let before = doc.layer(id: shape.id) else { return }
        doc.updateLayer(id: shape.id) { $0.frame.origin.x += 300 }
        let did4 = doc.foldEditIntoKeys(layerID: shape.id, before: before, atDocumentTimeMS: 3000)
        #expect(did4)
        #expect(doc.keyCount(layerID: shape.id, .motion(.position)) == 2)

        guard case let .point(start)? = doc.keyedValue(layerID: shape.id, .motion(.position), atDocumentTimeMS: 1000),
              case let .point(middle)? = doc.keyedValue(layerID: shape.id, .motion(.position), atDocumentTimeMS: 2000),
              case let .point(end)? = doc.keyedValue(layerID: shape.id, .motion(.position), atDocumentTimeMS: 3000)
        else {
            Issue.record("position is not keyed")
            return
        }
        #expect(end.x - start.x == 300)
        #expect(middle.x > start.x && middle.x < end.x)
    }

    @Test func pressedOnAKeyItTakesThoseKeysAway() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 1000)
        doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: shape.id, .motion(.position)) == 2)
        let did5 = doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 3000)
        #expect(did5)
        #expect(doc.keyCount(layerID: shape.id, .motion(.position)) == 1)
        let did6 = doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 1000)
        #expect(did6)
        #expect(doc.transformKeyDiamond(layerID: shape.id, atDocumentTimeMS: 1000) == .dormant)
        #expect(doc.layer(id: shape.id)?.hasMotion == false)
    }

    @Test func betweenKeysAPressAddsAKeyForEveryOneOfThem() {
        var doc = Self.eightSeconds()
        let shape = Self.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 1000)
        let did7 = doc.toggleTransformKey(layerID: shape.id, atDocumentTimeMS: 2000)
        #expect(did7)
        for property in PhotonzDocument.transformKeyProperties {
            #expect(doc.keyCount(layerID: shape.id, .motion(property)) == 2, "\(property)")
        }
    }
}
