import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The edits the timeline's right-click menus reach that nothing else did
/// before: markers and an In and Out on the ruler, a ripple delete that keeps
/// everything after the gap in step, a cut through every clip at once, and a
/// join rolled to the playhead.
@Suite("What the timeline's right-click menus do")
struct TimelineMenuEditsTests {

    static func movie(durationMS: Int = 8000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    /// An eight second recording, cut at two and five seconds.
    static func cutRecording() -> (doc: PhotonzDocument, clip: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Take 1")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 2000)
        doc.splitClip(clip, atMS: 5000)
        return (doc, clip)
    }

    // MARK: - Markers

    @Test("A marker lands where it is asked for, and only once there")
    func markerLandsOnce() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let r1 = doc.addMarker(atMS: 3000)
        let first = try #require(r1)
        #expect(doc.markers.map(\.atMS) == [3000])
        let r2 = doc.addMarker(atMS: 3000)
        #expect(r2 == nil)
        doc.addMarker(atMS: 1000)
        #expect(doc.markers.map(\.atMS) == [1000, 3000])
        let r3 = doc.removeMarker(first)
        #expect(r3)
        #expect(doc.markers.map(\.atMS) == [1000])
        let r4 = doc.removeMarker(first)
        #expect(!r4)
    }

    @Test("A marker never lands off the end of the document")
    func markerIsClamped() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        doc.addMarker(atMS: 20_000)
        doc.addMarker(atMS: -50)
        #expect(doc.markers.map(\.atMS) == [0, 8000])
    }

    @Test("Clearing every marker is one edit, and refuses when there are none")
    func clearMarkers() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let r5 = doc.removeAllMarkers()
        #expect(!r5)
        doc.addMarker(atMS: 1000)
        doc.addMarker(atMS: 2000)
        let r6 = doc.removeAllMarkers()
        #expect(r6)
        #expect(doc.markers.isEmpty)
    }

    // MARK: - In and Out

    @Test("In and Out mark a stretch; either one alone runs to the document's end")
    func inAndOut() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        #expect(doc.markedRangeMS == nil)
        doc.setMarkIn(atMS: 2000)
        #expect(doc.markedRangeMS == 2000..<8000)
        doc.setMarkOut(atMS: 6000)
        #expect(doc.markedRangeMS == 2000..<6000)
        let r7 = doc.clearMarkInOut()
        #expect(r7)
        #expect(doc.markInMS == nil && doc.markOutMS == nil)
        let r8 = doc.clearMarkInOut()
        #expect(!r8)
        doc.setMarkOut(atMS: 4000)
        #expect(doc.markedRangeMS == 0..<4000)
    }

    @Test("An In set after the Out lets the Out go, and the other way round")
    func inAfterOutClearsOut() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        doc.setMarkOut(atMS: 3000)
        doc.setMarkIn(atMS: 5000)
        #expect(doc.markInMS == 5000)
        #expect(doc.markOutMS == nil)
        doc.setMarkOut(atMS: 1000)
        #expect(doc.markOutMS == 1000)
        #expect(doc.markInMS == nil)
    }

    @Test("Markers and marks survive a save, and a document with none saves no keys for them")
    func marksRoundTrip() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let plain = String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
        #expect(!plain.contains("markers"))
        #expect(!plain.contains("markIn"))
        doc.addMarker(atMS: 1500)
        doc.setMarkIn(atMS: 1000)
        doc.setMarkOut(atMS: 7000)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
        #expect(back.markers == doc.markers)
        #expect(back.markInMS == 1000)
        #expect(back.markOutMS == 7000)
    }

    // MARK: - Ripple delete

    @Test("Ripple deleting a piece pulls everything after it back by the piece's length")
    func rippleDeletePiece() throws {
        var (doc, clip) = Self.cutRecording()
        let voice = doc.addSound(SoundRef(durationMS: 2000), name: "voice", atMS: 6000)
        let r9 = doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(r9)
        #expect(doc.layer(id: clip)?.time?.outMS == 5000)
        #expect(doc.layer(id: voice)?.time?.inMS == 3000)
    }

    @Test("A plain delete of a piece leaves everything after it where it was")
    func plainDeleteLeavesOthers() {
        var (doc, clip) = Self.cutRecording()
        let voice = doc.addSound(SoundRef(durationMS: 2000), name: "voice", atMS: 6000)
        let r10 = doc.removeClipPiece(clip, at: 1)
        #expect(r10)
        #expect(doc.layer(id: voice)?.time?.inMS == 6000)
    }

    @Test("A layer running across the gap is left exactly as it was")
    func rippleLeavesAStraddlerAlone() throws {
        var (doc, clip) = Self.cutRecording()
        let music = doc.addSound(SoundRef(durationMS: 8000), name: "music", atMS: 1000)
        let before = try #require(doc.layer(id: music)?.time)
        let r11 = doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(r11)
        #expect(doc.layer(id: music)?.time == before)
    }

    @Test("A clip on a locked track is not pulled back")
    func rippleSkipsLockedTracks() throws {
        var (doc, clip) = Self.cutRecording()
        let voice = doc.addSound(SoundRef(durationMS: 2000), name: "voice", atMS: 6000)
        let track = try #require(doc.trackID(ofClip: voice))
        doc.updateTrack(track) { $0.isLocked = true }
        let r12 = doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(r12)
        #expect(doc.layer(id: voice)?.time?.inMS == 6000)
    }

    @Test("Ripple deleting a whole clip takes it away and closes its gap")
    func rippleDeleteClip() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let clip = doc.layers[0].id
        let voice = doc.addSound(SoundRef(durationMS: 3000), name: "voice", atMS: 8000)
        let r13 = doc.rippleDeleteLayer(clip)
        #expect(r13)
        #expect(doc.layer(id: clip) == nil)
        #expect(doc.layer(id: voice)?.time?.inMS == 0)
        #expect(doc.documentDurationMS == 3000)
    }

    @Test("A ripple delete that has nothing to delete refuses")
    func rippleRefusesNothing() {
        var (doc, clip) = Self.cutRecording()
        let r14 = doc.rippleDeleteClipPiece(clip, at: 7)
        #expect(!r14)
        let r15 = doc.rippleDeleteLayer(UUID())
        #expect(!r15)
    }

    // MARK: - Split everything here

    @Test("Split everything cuts every clip the moment runs through")
    func splitEverything() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let clip = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 6000), name: "music", atMS: 2000)
        let r16 = doc.splitEveryClip(atMS: 4000)
        #expect(r16 == 2)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 2)
        #expect(doc.layer(id: music)?.clipPieces?.count == 2)
    }

    @Test("Split everything leaves a clip that starts or ends there alone")
    func splitEverythingSkipsEdges() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let music = doc.addSound(SoundRef(durationMS: 6000), name: "music", atMS: 2000)
        let r17 = doc.splitEveryClip(atMS: 2000)
        #expect(r17 == 1)
        #expect(doc.layer(id: music)?.clipPieces?.count == 1)
        let r18 = doc.splitEveryClip(atMS: 9000)
        #expect(r18 == 0)
    }

    @Test("Split everything leaves a clip on a locked track alone")
    func splitEverythingSkipsLocked() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let music = doc.addSound(SoundRef(durationMS: 6000), name: "music", atMS: 2000)
        let track = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(track) { $0.isLocked = true }
        let r19 = doc.splitEveryClip(atMS: 4000)
        #expect(r19 == 1)
        #expect(doc.layer(id: music)?.clipPieces?.count == 1)
    }

    // MARK: - Roll edit to the playhead

    @Test("Rolling a join later makes the piece before it longer and the one after it shorter")
    func rollLater() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        let r20 = doc.rollClipCut(clip, atCut: 1, toMS: 5000)
        #expect(r20)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        #expect(pieces.piece(at: 0)?.lengthMS == 5000)
        #expect(pieces.piece(at: 1)?.lengthMS == 3000)
        #expect(pieces.piece(at: 1)?.sourceInMS == 5000)
        #expect(doc.layer(id: clip)?.time?.outMS == 8000)
    }

    @Test("Rolling a join earlier works the other way round")
    func rollEarlier() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        let r21 = doc.rollClipCut(clip, atCut: 1, toMS: 3000)
        #expect(r21)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        #expect(pieces.piece(at: 0)?.lengthMS == 3000)
        #expect(pieces.piece(at: 1)?.sourceInMS == 3000)
        #expect(pieces.piece(at: 1)?.lengthMS == 5000)
    }

    @Test("A roll refuses to run past the recording or leave a piece too short to hold")
    func rollRefuses() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        // Past the end of the piece after it.
        let r22 = doc.rollClipCut(clip, atCut: 1, toMS: 7999)
        #expect(!r22)
        // Onto the join itself, which is no roll at all.
        let r23 = doc.rollClipCut(clip, atCut: 1, toMS: 4000)
        #expect(!r23)
        // A cut that is not there.
        let r24 = doc.rollClipCut(clip, atCut: 3, toMS: 5000)
        #expect(!r24)
        // The last piece moved first, so the one before the join has no
        // recording left after it to grow into.
        var moved = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let other = moved.layers[0].id
        moved.splitClip(other, atMS: 4000)
        moved.moveClipPiece(other, from: 1, to: 0)
        let r25 = moved.rollClipCut(other, atCut: 1, toMS: 5000)
        #expect(!r25)
    }
}
