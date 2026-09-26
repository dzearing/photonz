import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A shape's bar never vanishes from its track, and an empty track can take
/// one back** (`a-shape-s-bar-never-vanishes-from-its-track-and`).
///
/// The user's words: "I made a rectangle. It was in the timeline. I did
/// something which caused it to be removed (the box in the timeline
/// disappeared) but the track was still there ... There is no way to bring it
/// back and size it in the timeline."
///
/// Written before the model. What they reproduced, on a rectangle drawn on a
/// recording with its tracks written down: Delete, ripple delete, extract and
/// lift over it all took the layer and left its track behind empty; grouping
/// it or carrying it to another track left its old track empty; and dragging
/// one end past the other shrank it to ten milliseconds, a bar a pixel wide.
@Suite("Empty tracks")
struct EmptyTracksTests {

    /// A rectangle from one to three seconds over an eight second take, with
    /// the tracks written down, the way any change to a track leaves them.
    static func shapeOnATake() -> (doc: PhotonzDocument, shape: UUID) {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let shape = DrawnOnTheTimelineTests.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        _ = doc.moveLayerEnd(shape.id, toMS: 3000)
        doc.materializeTracks()
        return (doc, shape.id)
    }

    static func pictureTrackNames(_ doc: PhotonzDocument) -> [String] {
        doc.timelineTracks.filter { $0.kind == .video }.map(\.name)
    }

    // MARK: - A bar is never shorter than a frame

    @Test("Dragging a bar's end past its start stops a frame after it")
    func endStopsAFrameIn() {
        var (doc, shape) = Self.shapeOnATake()
        _ = doc.moveLayerEnd(shape, toMS: 0)
        #expect(doc.layer(id: shape)?.time?.lengthMS == LayerTime.shortestMS)
        #expect(LayerTime.shortestMS >= MovieRef.frameStepMS)
    }

    @Test("Dragging a bar's start past its end stops a frame before it")
    func startStopsAFrameIn() {
        var (doc, shape) = Self.shapeOnATake()
        _ = doc.moveLayerStart(shape, toMS: 8000)
        #expect(doc.layer(id: shape)?.time == LayerTime(inMS: 3000 - LayerTime.shortestMS, outMS: 3000))
    }

    // MARK: - A track the app made goes with what made it

    @Test("Deleting a shape takes the track the app made for it too")
    func deleteTakesItsTrack() {
        let (before, shape) = Self.shapeOnATake()
        var doc = before
        doc.removeLayers(ids: [shape])
        #expect(Self.pictureTrackNames(doc) == ["Rectangle", "V1"])
        do { let did = doc.dropTracksEmptied(since: before); #expect(did) }
        #expect(Self.pictureTrackNames(doc) == ["V1"])
    }

    @Test("Ripple delete, extract and lift over the shape take its track too")
    func everyDeleteTakesItsTrack() {
        let (before, shape) = Self.shapeOnATake()
        let edits: [(inout PhotonzDocument) -> Void] = [
            { _ = $0.rippleDeleteLayer(shape) },
            { _ = $0.extractStretch(fromMS: 500, toMS: 3500) },
            { _ = $0.liftStretch(fromMS: 500, toMS: 3500) },
        ]
        for edit in edits {
            var doc = before
            edit(&doc)
            doc.dropTracksEmptied(since: before)
            #expect(doc.layer(id: shape) == nil)
            #expect(Self.pictureTrackNames(doc) == ["V1"])
        }
    }

    @Test("Grouping a shape leaves no empty track where it was")
    func groupingLeavesNoEmptyTrack() {
        let (before, shape) = Self.shapeOnATake()
        var doc = before
        let group = doc.groupLayers(ids: [shape])
        doc.dropTracksEmptied(since: before)
        #expect(doc.emptyTrackIDs.isEmpty)
        #expect(doc.trackID(ofClip: shape) != nil)
        #expect(doc.timelineClipLayers.contains { $0.id == group?.id })
    }

    @Test("Carrying a shape to a new track leaves no empty track behind")
    func carryingLeavesNoEmptyTrack() {
        let (before, shape) = Self.shapeOnATake()
        var doc = before
        let made = doc.moveClipToNewTrack(shape, at: 0)
        doc.dropTracksEmptied(since: before)
        #expect(doc.emptyTrackIDs.isEmpty)
        #expect(doc.trackID(ofClip: shape) == made)
    }

    @Test("A track somebody added stays, empty, when its clip goes")
    func anAddedTrackStays() {
        var (doc, shape) = Self.shapeOnATake()
        let added = doc.addTrack(.video)
        let beforeTheMove = doc
        do { let did = doc.moveClip(shape, toTrack: added); #expect(did) }
        doc.dropTracksEmptied(since: beforeTheMove)
        let before = doc
        doc.removeLayers(ids: [shape])
        do { let did = doc.dropTracksEmptied(since: before); #expect(!did) }
        #expect(doc.emptyTrackIDs == [added])
    }

    @Test("An edit that empties nothing changes nothing")
    func nothingEmptied() {
        let (before, shape) = Self.shapeOnATake()
        var doc = before
        _ = doc.moveClip(shape, toInMS: 2000)
        let moved = doc
        do { let did = doc.dropTracksEmptied(since: before); #expect(!did) }
        #expect(doc == moved)
    }

    // MARK: - Empty tracks, by hand

    @Test("Delete Empty Tracks takes every empty picture track and keeps the rest")
    func deleteEmptyTracks() {
        var (doc, _) = Self.shapeOnATake()
        let one = doc.addTrack(.video)
        let two = doc.addTrack(.video)
        #expect(Set(doc.emptyTrackIDs) == [one, two])
        do { let did = doc.deleteEmptyTracks(); #expect(did) }
        #expect(doc.emptyTrackIDs.isEmpty)
        #expect(Self.pictureTrackNames(doc) == ["Rectangle", "V1"])
        do { let did = doc.deleteEmptyTracks(); #expect(!did) }
    }

    @Test("The Audio track waiting under a silent recording is not an empty track to clear")
    func theWaitingAudioTrackStays() {
        // The take has no sound of its own, so an Audio track waits under it.
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        doc.materializeTracks()
        #expect(doc.timelineTracks.contains { $0.id == PhotonzDocument.waitingAudioTrackID })
        #expect(!doc.emptyTrackIDs.contains(PhotonzDocument.waitingAudioTrackID))
    }

    // MARK: - Putting a layer back on the timeline

    /// A rectangle on the take's picture with no time: on the canvas, on no track.
    static func shapeOffTheTimeline() -> (doc: PhotonzDocument, shape: UUID) {
        var doc = DrawnOnTheTimelineTests.eightSeconds()
        let shape = DrawnOnTheTimelineTests.rectangle()
        doc.addLayer(shape)
        return (doc, shape.id)
    }

    @Test("A layer on the canvas and on no track can be put on the timeline, from the playhead for five seconds")
    func putOnTimeline() {
        var (doc, shape) = Self.shapeOffTheTimeline()
        #expect(doc.layersOffTheTimeline.map(\.id) == [shape])
        #expect(doc.canPutOnTimeline(shape))
        do { let did = doc.putOnTimeline(shape, atMS: 1000); #expect(did) }
        #expect(doc.layer(id: shape)?.time == LayerTime(inMS: 1000, outMS: 6000))
        #expect(doc.trackID(ofClip: shape) != nil)
        #expect(!doc.canPutOnTimeline(shape))
        #expect(doc.layersOffTheTimeline.isEmpty)
    }

    @Test("Put on the timeline near the end, it takes the last five seconds so it is still where it was put")
    func putNearTheEnd() {
        var (doc, shape) = Self.shapeOffTheTimeline()
        do { let did = doc.putOnTimeline(shape, atMS: 7900); #expect(did) }
        #expect(doc.layer(id: shape)?.time == LayerTime(inMS: 3000, outMS: 8000))
    }

    @Test("A layer can be put onto an empty track, and lands there")
    func putOntoAnEmptyTrack() {
        var (doc, shape) = Self.shapeOffTheTimeline()
        let empty = doc.addTrack(.video)
        do { let did = doc.putOnTimeline(shape, atMS: 2000, onTrack: empty); #expect(did) }
        #expect(doc.trackID(ofClip: shape) == empty)
        #expect(doc.emptyTrackIDs.isEmpty)
    }

    @Test("A layer already on the timeline is carried onto the track and to the moment it is put at")
    func putMovesOneAlreadyThere() {
        var (doc, shape) = Self.shapeOnATake()
        let empty = doc.addTrack(.video)
        do { let did = doc.putOnTimeline(shape, atMS: 4000, onTrack: empty); #expect(did) }
        #expect(doc.trackID(ofClip: shape) == empty)
        #expect(doc.layer(id: shape)?.time == LayerTime(inMS: 4000, outMS: 6000))
    }

    @Test("Nothing lands on a locked track, on a sound track, or over another clip")
    func putRefused() {
        var (doc, shape) = Self.shapeOffTheTimeline()
        let locked = doc.addTrack(.video)
        doc.updateTrack(locked) { $0.isLocked = true }
        let sound = doc.addTrack(.audio)
        let recordingTrack = doc.trackID(ofClip: doc.layers[0].id)
        do { let did = doc.putOnTimeline(shape, atMS: 0, onTrack: locked); #expect(!did) }
        do { let did = doc.putOnTimeline(shape, atMS: 0, onTrack: sound); #expect(!did) }
        do { let did = doc.putOnTimeline(shape, atMS: 0, onTrack: recordingTrack); #expect(!did) }
        #expect(doc.layer(id: shape)?.time == nil)
    }

    @Test("The recording itself, a layer in a group, and a picture with no time are never offered")
    func notOffered() {
        let (doc, _) = Self.shapeOffTheTimeline()
        #expect(!doc.canPutOnTimeline(doc.layers[0].id))
        var picture = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let shape = DrawnOnTheTimelineTests.rectangle()
        picture.addLayer(shape)
        #expect(!picture.canPutOnTimeline(shape.id))
        #expect(picture.layersOffTheTimeline.isEmpty)
    }

    @Test("What an edit adds lands on the track it was asked for, at the playhead")
    func newLayersLandOnTheTrack() {
        var (doc, _) = Self.shapeOnATake()
        let empty = doc.addTrack(.video)
        let before = doc
        let text = DrawnOnTheTimelineTests.rectangle("Second")
        doc.addLayerDrawn(text, atTimeMS: 2000, placingInTime: true)
        do { let did = doc.landNewLayers(since: before, onTrack: empty, atMS: 2000); #expect(did) }
        #expect(doc.trackID(ofClip: text.id) == empty)
        #expect(doc.layer(id: text.id)?.time?.inMS == 2000)
        #expect(doc.emptyTrackIDs.isEmpty)
    }

    @Test("V1 stays when the recording is carried off it, the way every editor keeps it")
    func v1Stays() {
        let (before, _) = Self.shapeOnATake()
        var doc = before
        let recording = doc.layers[0].id
        let v1 = doc.trackID(ofClip: recording)
        _ = doc.moveClipToNewTrack(recording, at: 0)
        do { let did = doc.dropTracksEmptied(since: before); #expect(!did) }
        #expect(doc.emptyTrackIDs == [v1].compactMap { $0 })
    }
}
