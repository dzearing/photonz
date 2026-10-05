import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A clip put down at the playhead from the menu bar** (Sequence ▸ Add
/// Media at Playhead…): no pointer says which track, so the document picks
/// one. It goes on a picture track that is free for the whole of its length
/// and has nothing playing over it there, so it is seen the moment it lands
/// and nothing already cut is covered; where no track is, it gets a new one
/// on top of what is playing.
@Suite("Putting a clip down at the playhead")
struct ClipLandingAtPlayheadTests {

    static let broll = ClipLandingTests.broll

    @Test("Where the picture is busy all the way up, the clip gets a new track on top")
    func everyTrackBusyMakesANewOne() throws {
        let (doc, _, _, _) = ClipLandingTests.edit()
        // 2s to 6s: the recording on V1 the whole way, the title from 5s.
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 2000)
        #expect(landing.target == .newTrack(at: 0))
        #expect(landing.startMS == 2000)
        #expect(landing.lengthMS == 4000)
        #expect(landing.edit == .overwrite)
        #expect(landing.allowed)
        #expect(landing.trackName == "V2")
    }

    @Test("A picture track free for the clip's whole length, over what is playing, takes it")
    func aFreeTrackOverThePictureTakesIt() throws {
        let (doc, _, title, _) = ClipLandingTests.edit()
        let titleTrack = try #require(doc.trackID(ofClip: title))
        // 0s to 4s: the title does not start until 5s, so its track is free.
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 0)
        #expect(landing.target == .onto(titleTrack))
        #expect(landing.allowed)
    }

    @Test("Past the end of everything, the clip goes on the bottom picture track, after what is there")
    func pastTheEndAppendsToV1() throws {
        let (doc, _, _, _) = ClipLandingTests.edit()
        let v1 = try #require(ClipLandingTests.track(named: "V1", in: doc))
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 8000)
        #expect(landing.target == .onto(v1))
        #expect(landing.trackName == "V1")
    }

    @Test("A playhead parked on the last frame of the recording still puts the clip on the end of V1")
    func aFrameShortOfTheEndSnapsOn() throws {
        let (doc, _, _, _) = ClipLandingTests.edit()
        let v1 = try #require(ClipLandingTests.track(named: "V1", in: doc))
        // Where the playhead rests at the end of an eight second document, and
        // a frame before it.
        for ms in [7999, 7967] {
            let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: ms)
            #expect(landing.target == .onto(v1))
            #expect(landing.startMS == 8000)
        }
        // Further off than a frame is a moment of its own.
        #expect(doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 7900).startMS == 7900)
    }

    @Test("A locked track is passed over, and the new track goes straight over the busy one")
    func lockedTrackIsPassedOver() throws {
        var (doc, _, title, _) = ClipLandingTests.edit()
        let titleTrack = try #require(doc.trackID(ofClip: title))
        doc.updateTrack(titleTrack) { $0.isLocked = true }
        let v1 = try #require(ClipLandingTests.track(named: "V1", in: doc))
        let v1Index = try #require(doc.timelineTracks.firstIndex { $0.id == v1 })
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 0)
        #expect(landing.target == .newTrack(at: v1Index))
        #expect(landing.allowed)
    }

    @Test("A free track under one that is playing is not used: the clip would land unseen")
    func freeTrackUnderTheBusyOneIsNotUsed() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        // An empty picture track under V1.
        let v1 = try #require(ClipLandingTests.track(named: "V1", in: doc))
        let v1Index = try #require(doc.timelineTracks.firstIndex { $0.id == v1 })
        let under = doc.addTrack(.video, at: v1Index + 1)
        #expect(doc.trackID(ofClip: take) == v1)
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 1000, atMS: 1000)
        #expect(landing.target != .onto(under))
    }

    @Test("Landing it covers nothing already cut, and its own sound comes in linked under it")
    func landingKeepsEverythingAndLinksTheSound() throws {
        var (doc, take, title, music) = ClipLandingTests.edit()
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 2000)
        let put = doc.land(ClipLandingTests.clip(), at: landing)
        let clip = try #require(put)
        #expect(doc.layer(id: clip)?.time?.inMS == 2000)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
        #expect(doc.layer(id: title)?.time?.inMS == 5000)
        #expect(doc.layer(id: music)?.time?.outMS == 14000)
        #expect(doc.linkedSoundTrackID(ofClip: clip) != nil)
        // On top of the picture, so it is seen.
        let landed = try #require(doc.trackID(ofClip: clip))
        #expect(doc.timelineTracks.first?.id == landed)
    }

    @Test("A document with no picture track gives the clip a new one")
    func noPictureTrackMakesOne() throws {
        var doc = PhotonzDocument.recording(ClipLandingTests.take, name: "take")
        doc.removeLayers(ids: Set(doc.layers.map(\.id)))
        _ = doc.addSound(SoundRef(durationMS: 6000), name: "music", atMS: 0)
        let landing = doc.pictureLandingAtPlayhead(lengthMS: 4000, atMS: 0)
        #expect(landing.target == .newTrack(at: 0))
        #expect(landing.trackName == "V1")
    }
}
