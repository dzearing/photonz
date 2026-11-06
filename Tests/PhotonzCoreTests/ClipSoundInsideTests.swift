import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A clip's own sound is the bottom half of the clip** (`ClipHalves.swift`).
///
/// The user, 2026-11-05: "If audio is attached to a video segment, it should
/// appear in the same lane as sort of the bottom half of the video rectangle,
/// rather than its own track. if you right click and separate the audio then
/// yes, separate track. but having the 2 rows implicitly attached to each
/// other is really confusing."
@Suite("A clip's sound inside the clip")
struct ClipSoundInsideTests {

    typealias Fixture = LinkedSoundTests

    private static func names(_ doc: PhotonzDocument) -> [String] { doc.timelineLanes.map(\.name) }

    // MARK: - What the timeline lists

    @Test("A recording with sound lists V1 and the Audio track waiting, and no sound row")
    func noSoundRowListed() {
        let doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        #expect(Self.names(doc) == ["V1", "Audio"])
        #expect(!doc.timelineLanes.contains { $0.attachedTo != nil })
    }

    @Test("The sound still has its switches, found from the picture track")
    func switchesFoundFromThePicture() throws {
        let doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        let picture = try #require(doc.trackID(ofClip: clip))
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.soundRowIDs(ofTrack: picture) == [row])
        #expect(doc.soundTrackID(ofLayer: clip) == row)
    }

    @Test("A track with no sound inside its clips has no sound rows")
    func silentTrackHasNone() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        let picture = try #require(doc.trackID(ofClip: clip))
        let split = try #require(doc.detachingSound(ofLayer: clip))
        doc = split.document
        #expect(doc.soundRowIDs(ofTrack: picture).isEmpty)
    }

    // MARK: - Detach and Re-attach

    @Test("Detach Audio uses the Audio track that was waiting, and Re-attach empties it again")
    func detachUsesTheWaitingTrack() throws {
        let doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        let split = try #require(doc.detachingSound(ofLayer: clip))
        #expect(Self.names(split.document) == ["V1", "Audio"])
        let audio = try #require(split.document.timelineLanes.first { $0.kind == .audio })
        #expect(split.document.clipIDs(onTrack: audio.id) == [split.soundLayerID])
        let joined = try #require(split.document.reattachingSound(ofLayer: clip))
        #expect(joined.document.timelineLanes.filter { $0.kind == .audio }.count == 1)
        #expect(joined.document.linkedSoundTrackID(ofClip: clip) != nil)
    }

    @Test("Detach Audio makes a new Audio track when the one there has no room")
    func detachMakesANewTrack() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        let audio = try #require(doc.timelineLanes.first { $0.kind == .audio }?.id)
        doc.materializeTracks()
        doc.updateTrack(audio) { $0.isLocked = true }
        let split = try #require(doc.detachingSound(ofLayer: clip))
        #expect(Self.names(split.document) == ["V1", "Audio", "Audio 2"])
    }

    @Test("Music added once the tracks are written down goes on the Audio track waiting, not under it")
    func musicTakesTheWaitingTrack() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        doc.addTrack(.video, at: 0)
        let waiting = try #require(doc.timelineLanes.first { $0.kind == .audio }?.id)
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        #expect(doc.timelineLanes.filter { $0.kind == .audio }.count == 1)
        #expect(doc.trackID(ofClip: music) == waiting)
    }

    // MARK: - Lock

    @Test("Locking a picture track locks the sound inside its clips")
    func lockFollowsThePicture() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        let picture = try #require(doc.trackID(ofClip: clip))
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.materializeTracks()
        doc.updateTrack(picture) { $0.isLocked = true }
        #expect(doc.track(id: row)?.isLocked == true)
        doc.updateTrack(picture) { $0.isLocked = false }
        #expect(doc.track(id: row)?.isLocked == false)
    }

    @Test("A sound row locked in an older document cannot stay locked with nothing to unlock it")
    func oldLockIsLetGo() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.materializeTracks()
        doc.updateTrack(row) { $0.isLocked = true }
        #expect(doc.track(id: row)?.isLocked == false)
    }

    // MARK: - The two halves

    @Test("The picture keeps the height of a clip with no sound and the sound gets the rest")
    func halvesAtRest() {
        let halves = ClipHalves(laneHeight: ClipHalves.restingLaneHeight)
        #expect(halves.picture == 28)
        #expect(halves.sound == ClipHalves.restingLaneHeight - 28)
        #expect(halves.sound >= 20)
    }

    @Test("Tall rows share the height in the same proportion, and nothing is lost")
    func halvesZoomed() {
        for lane in [CGFloat(50), 75, 100, 137] {
            let halves = ClipHalves(laneHeight: lane)
            #expect(halves.picture + halves.sound == lane)
            let share = halves.picture / lane
            #expect(abs(share - 28 / ClipHalves.restingLaneHeight) < 0.02)
        }
    }
}
