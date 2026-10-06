import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A copied clip pasted at the playhead** (Edit ▸ Paste on a video), the
/// way Premiere pastes one: it starts at the playhead on the track it was
/// copied off when that stretch of the track is free, and on a new track just
/// over it when it is not, so nothing already cut is covered. Its own sound
/// comes with it, linked under it.
@Suite("Pasting a copied clip at the playhead")
struct ClipPasteAtPlayheadTests {

    static func copy(of id: UUID, in doc: PhotonzDocument) throws -> Layer {
        try #require(doc.layer(id: id)).duplicated()
    }

    @Test("Where its own track is free there, the copy lands on it at the playhead")
    func ownTrackFreeTakesIt() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try Self.copy(of: take, in: doc)
        let landing = try #require(doc.pasteLanding(for: copy, fromTrack: v1, atMS: 9000))
        #expect(landing.target == .onto(v1))
        #expect(landing.startMS == 9000)
        #expect(landing.lengthMS == 8000)
        #expect(landing.edit == .overwrite)
        let landedPut = doc.pasteClip(copy, fromTrack: v1, atMS: 9000)
        let landed = try #require(landedPut)
        #expect(doc.trackID(ofClip: landed) == v1)
        #expect(doc.layer(id: landed)?.time?.inMS == 9000)
        #expect(doc.layer(id: landed)?.time?.outMS == 17000)
        // The original stays exactly where it was.
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
    }

    @Test("Where its own track is busy there, the copy gets a new track straight over it")
    func ownTrackBusyMakesANewOneOverIt() throws {
        var (doc, take, title, music) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let v1Index = try #require(doc.timelineTracks.firstIndex { $0.id == v1 })
        let copy = try Self.copy(of: take, in: doc)
        let landing = try #require(doc.pasteLanding(for: copy, fromTrack: v1, atMS: 5000))
        #expect(landing.target == .newTrack(at: v1Index))
        #expect(landing.startMS == 5000)
        let landedPut = doc.pasteClip(copy, fromTrack: v1, atMS: 5000)
        let landed = try #require(landedPut)
        let track = try #require(doc.trackID(ofClip: landed))
        #expect(track != v1)
        let tracks = doc.timelineTracks
        let landedIndex = try #require(tracks.firstIndex { $0.id == track })
        // Straight over V1.
        #expect(tracks[landedIndex + 1].id == v1)
        #expect(doc.layer(id: landed)?.time?.inMS == 5000)
        // Nothing already cut moved or was covered.
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
        #expect(doc.layer(id: title)?.time?.inMS == 5000)
        #expect(doc.layer(id: music)?.time?.outMS == 14000)
    }

    @Test("The copy's own sound comes in with it, linked under it, at the playhead")
    func linkedSoundComesAlong() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try Self.copy(of: take, in: doc)
        let landedPut = doc.pasteClip(copy, fromTrack: v1, atMS: 5000)
        let landed = try #require(landedPut)
        let sound = try #require(doc.linkedSoundTrackID(ofClip: landed))
        #expect(doc.timelineTracks.first { $0.id == sound }?.kind == .audio)
        // The original's sound keeps its own track.
        #expect(doc.linkedSoundTrackID(ofClip: take) != sound)
    }

    @Test("Pasting the same copy again at the end of the first puts it after the first")
    func secondPasteFollowsTheFirst() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let original = try #require(doc.layer(id: take))
        let firstPut = doc.pasteClip(original.duplicated(), fromTrack: v1, atMS: 8000)
        let first = try #require(firstPut)
        let secondPut = doc.pasteClip(original.duplicated(), fromTrack: v1, atMS: 16000)
        let second = try #require(secondPut)
        #expect(doc.trackID(ofClip: first) == v1)
        #expect(doc.trackID(ofClip: second) == v1)
        #expect(doc.layer(id: first)?.time?.inMS == 8000)
        #expect(doc.layer(id: second)?.time?.inMS == 16000)
    }

    @Test("A playhead parked a frame short of the end of the recording pastes the copy on the end of it")
    func aFrameShortOfTheEndSnapsOn() throws {
        let (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try Self.copy(of: take, in: doc)
        let landing = try #require(doc.pasteLanding(for: copy, fromTrack: v1, atMS: 7999))
        #expect(landing.target == .onto(v1))
        #expect(landing.startMS == 8000)
    }

    @Test("A locked track of its own is passed over for a new one straight over it")
    func lockedOwnTrackIsPassedOver() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(v1) { $0.isLocked = true }
        let v1Index = try #require(doc.timelineTracks.firstIndex { $0.id == v1 })
        let copy = try Self.copy(of: take, in: doc)
        let landing = try #require(doc.pasteLanding(for: copy, fromTrack: v1, atMS: 9000))
        #expect(landing.target == .newTrack(at: v1Index))
        #expect(landing.allowed)
    }

    @Test("A copy whose track is not in this document lands the way Add Media at Playhead puts one down")
    func unknownTrackLandsLikeAddMedia() throws {
        let (doc, _, _, _) = ClipLandingTests.edit()
        let copy = ClipLandingTests.clip()
        let landing = try #require(doc.pasteLanding(for: copy, fromTrack: nil, atMS: 2000))
        #expect(landing == doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 2000))
    }

    @Test("A copied sound lands at the playhead on its own sound track when that is free")
    func soundOnItsOwnTrack() throws {
        var (doc, _, _, music) = ClipLandingTests.edit()
        let track = try #require(doc.trackID(ofClip: music))
        let copy = try Self.copy(of: music, in: doc)
        let landedPut = doc.pasteClip(copy, fromTrack: track, atMS: 14000)
        let landed = try #require(landedPut)
        #expect(doc.layer(id: landed)?.time?.inMS == 14000)
        let landedTrack = try #require(doc.trackID(ofClip: landed))
        #expect(doc.timelineTracks.first { $0.id == landedTrack }?.kind == .audio)
        #expect(doc.layer(id: music)?.time?.inMS == 0)
    }

    @Test("A copied sound where its track is busy gets a new sound track, and the music it came off plays on")
    func soundOnABusyTrackGetsANewOne() throws {
        var (doc, _, _, music) = ClipLandingTests.edit()
        let track = try #require(doc.trackID(ofClip: music))
        let copy = try Self.copy(of: music, in: doc)
        let landedPut = doc.pasteClip(copy, fromTrack: track, atMS: 3000)
        let landed = try #require(landedPut)
        #expect(doc.layer(id: landed)?.time?.inMS == 3000)
        #expect(doc.trackID(ofClip: landed) != track)
        #expect(doc.layer(id: music)?.time?.inMS == 0)
        #expect(doc.layer(id: music)?.time?.outMS == 14000)
    }

    @Test("A copied title lands at the playhead on its own track when that is free")
    func titleOnItsOwnTrack() throws {
        var (doc, _, title, _) = ClipLandingTests.edit()
        let track = try #require(doc.trackID(ofClip: title))
        let copy = try Self.copy(of: title, in: doc)
        let landedPut = doc.pasteClip(copy, fromTrack: track, atMS: 1000)
        let landed = try #require(landedPut)
        #expect(doc.trackID(ofClip: landed) == track)
        #expect(doc.layer(id: landed)?.time?.inMS == 1000)
        #expect(doc.layer(id: landed)?.time?.outMS == 3000)
    }

    @Test("A layer with no time of its own has no landing at the playhead")
    func timelessLayerHasNoLanding() throws {
        let (doc, _, _, _) = ClipLandingTests.edit()
        let still = Layer(name: "note", content: .text(TextContent(string: "x")),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(doc.pasteLanding(for: still, fromTrack: nil, atMS: 1000) == nil)
    }
}
