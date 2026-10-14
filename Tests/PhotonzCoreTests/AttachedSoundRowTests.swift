import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A clip's own sound sits right under its video** (`DocumentTracks.swift`).
///
/// The sound a recording came with belongs to it. It is drawn on a row that
/// belongs to the clip's own picture track, directly under it, the way Final
/// Cut keeps a clip's audio under its video, and it stays there whatever is
/// done to the tracks around it. Detach Audio is what sends it to the Audio
/// tracks at the bottom (the user, 2026-10-13: "Audio that is attached to a
/// track should always appear below it").
@Suite("Attached sound row")
struct AttachedSoundRowTests {

    typealias Fixture = LinkedSoundTests

    /// The track names top to bottom, with a clip's own sound row written as
    /// `>owner` so a test reads the whole timeline at a glance.
    static func shape(_ doc: PhotonzDocument) -> [String] {
        let tracks = doc.timelineTracks
        return tracks.map { track in
            guard let owner = track.attachedTo else { return track.name }
            return ">" + (tracks.first { $0.id == owner }?.name ?? "?")
        }
    }

    /// The user's screenshot: the recording on V3, two empty tracks under it.
    static func userLayout() throws -> (doc: PhotonzDocument, clip: UUID) {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "Recording")
        let clip = doc.layers[0].id
        doc.addTrack(.video)
        doc.addTrack(.video)
        let v3 = try #require(doc.timelineTracks.first { $0.name == "V3" }?.id)
        let done1 = doc.moveClip(clip, toTrack: v3)
        #expect(done1)
        return (doc, clip)
    }

    /// The clip's sound row is the very next row after the clip's own track.
    static func soundIsUnderItsVideo(_ doc: PhotonzDocument, _ clip: UUID) -> Bool {
        let tracks = doc.timelineTracks
        guard let picture = doc.trackID(ofClip: clip), let sound = doc.linkedSoundTrackID(ofClip: clip),
              let at = tracks.firstIndex(where: { $0.id == picture }), at + 1 < tracks.count
        else { return false }
        return tracks[at + 1].id == sound && tracks[at + 1].attachedTo == picture
    }

    // MARK: - Where it is drawn

    @Test("A recording opens with its sound on a row of V1's, right under it")
    func opensUnderItsVideo() throws {
        let doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        #expect(Self.shape(doc) == ["V1", ">V1"])
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        let row = try #require(doc.timelineTracks.first { $0.attachedTo != nil })
        #expect(row.kind == .audio)
        #expect(doc.linkedSoundClipIDs(onTrack: row.id) == [clip])
        // Reading it writes nothing.
        #expect(doc.tracks.isEmpty)
    }

    @Test("The user's layout: the sound is under V3, not under the empty tracks below it")
    func userLayoutSoundUnderV3() throws {
        let (doc, clip) = try Self.userLayout()
        #expect(Self.shape(doc) == ["V3", ">V3", "V2", "V1"])
        #expect(Self.soundIsUnderItsVideo(doc, clip))
    }

    @Test("Adding tracks above, between and below never parts the sound from its video")
    func addingTracks() throws {
        var (doc, clip) = try Self.userLayout()
        doc.addTrack(.video, at: 0)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        // A track asked for between V3 and its sound lands under the sound.
        let between = try #require(doc.timelineTracks.firstIndex { $0.attachedTo != nil })
        doc.addTrack(.video, at: between)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        doc.addTrack(.audio)
        doc.addTrack(.audio, at: 0)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
    }

    @Test("Deleting the tracks around it never moves the sound")
    func deletingTracks() throws {
        var (doc, clip) = try Self.userLayout()
        let v2 = try #require(doc.timelineTracks.first { $0.name == "V2" }?.id)
        doc.deleteTrack(v2)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        doc.deleteTrack(v1)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        let music = doc.addTrack(.audio)
        doc.deleteTrack(music)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        #expect(doc.layer(id: clip)?.sound != nil)
    }

    @Test("Moving the clip to another track takes its sound with it")
    func movingTheClipBetweenTracks() throws {
        var (doc, clip) = try Self.userLayout()
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        let done2 = doc.moveClip(clip, toTrack: v1)
        #expect(done2)
        #expect(Self.shape(doc) == ["V3", "V2", "V1", ">V1"])
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        _ = doc.moveClipToNewTrack(clip, at: 0)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
    }

    @Test("Carrying the video track carries its sound row with it")
    func carryingTheVideoTrack() throws {
        var (doc, clip) = try Self.userLayout()
        let v3 = try #require(doc.trackID(ofClip: clip))
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        let done3 = doc.moveTrack(v3, .below(v1))
        #expect(done3)
        #expect(Self.shape(doc) == ["V2", "V1", "V3", ">V3"])
        #expect(Self.soundIsUnderItsVideo(doc, clip))
        // Dropped right under a track that has a sound row, it goes under
        // that row rather than between the two.
        let fresh = try Self.userLayout()
        var other = fresh.doc
        let top = try #require(other.trackID(ofClip: fresh.clip))
        let bottom = try #require(other.timelineTracks.first { $0.name == "V1" }?.id)
        let done4 = other.moveTrack(bottom, .below(top))
        #expect(done4)
        #expect(Self.shape(other) == ["V3", ">V3", "V1", "V2"])
    }

    @Test("A sound row cannot be carried away from its video, and takes no clips")
    func theRowIsTheVideosOwn() throws {
        var (doc, clip) = try Self.userLayout()
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(!doc.canMoveTrack(row))
        let top = try #require(doc.timelineTracks.first?.id)
        let carried = doc.moveTrack(row, .above(top))
        #expect(!carried)
        let music = doc.addSound(SoundRef(durationMS: 2000), name: "music", atMS: 20_000)
        #expect(!doc.canPlace(music, onTrack: row))
        let landed = doc.moveClip(music, toTrack: row)
        #expect(!landed)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
    }

    @Test("Several clips on one track share its sound row")
    func clipsInARowShareTheRow() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "intro")
        let intro = doc.layers[0].id
        doc.materializeTracks()
        let v1 = try #require(doc.timelineTracks.first?.id)
        var demo = Fixture.clip(Fixture.movie(4000), name: "demo", atMS: 6000)
        demo.trackID = v1
        doc.addLayer(demo)
        #expect(Self.shape(doc) == ["V1", ">V1"])
        let row = try #require(doc.linkedSoundTrackID(ofClip: intro))
        #expect(doc.linkedSoundTrackID(ofClip: demo.id) == row)
    }

    @Test("A picture-in-picture over the recording gets its sound row under its own track")
    func eachVideoTrackHasItsOwnRow() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "screen")
        let screen = doc.layers[0].id
        let pip = Fixture.clip(Fixture.movie(3000), name: "face", atMS: 1000)
        doc.addLayer(pip)
        #expect(Self.shape(doc) == ["V2", ">V2", "V1", ">V1"])
        #expect(Self.soundIsUnderItsVideo(doc, screen))
        #expect(Self.soundIsUnderItsVideo(doc, pip.id))
    }

    @Test("The sound row is named for its video track and follows a rename")
    func rowNameFollowsItsVideo() throws {
        var (doc, clip) = try Self.userLayout()
        let v3 = try #require(doc.trackID(ofClip: clip))
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.track(id: row)?.name == "V3 sound")
        doc.renameTrack(v3, to: "Screen")
        #expect(doc.track(id: row)?.name == "Screen sound")
    }

    @Test("A sound row sits in its video track's group")
    func rowFollowsTheGroup() throws {
        var (doc, clip) = try Self.userLayout()
        let v3 = try #require(doc.trackID(ofClip: clip))
        let v2 = try #require(doc.timelineTracks.first { $0.name == "V2" }?.id)
        let grouped = doc.groupTracks([v3, v2])
        let group = try #require(grouped)
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.track(id: row)?.groupID == group)
        #expect(Self.soundIsUnderItsVideo(doc, clip))
    }

    // MARK: - Heard or not

    @Test("Muting the sound row silences the sound and keeps the switch through track edits")
    func muteStaysOnTheRow() throws {
        var (doc, clip) = try Self.userLayout()
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.updateTrack(row) { $0.isMuted = true }
        #expect(!doc.audioMix().contains { $0.layerID == clip })
        doc.addTrack(.video, at: 0)
        let v2 = try #require(doc.timelineTracks.first { $0.name == "V2" }?.id)
        doc.deleteTrack(v2)
        #expect(doc.linkedSoundTrackID(ofClip: clip) == row)
        #expect(doc.track(id: row)?.isMuted == true)
        #expect(!doc.audioMix().contains { $0.layerID == clip })
    }

    // MARK: - Detach and attach

    @Test("Detach Audio puts the sound on an Audio track at the bottom, off its video")
    func detachGoesToTheAudioSection() throws {
        let (doc, clip) = try Self.userLayout()
        let split = try #require(doc.detachingSound(ofLayer: clip))
        let after = split.document
        #expect(after.linkedSoundTrackID(ofClip: clip) == nil)
        #expect(Self.shape(after) == ["V3", "V2", "V1", "Audio"])
        let audio = try #require(after.timelineTracks.last)
        #expect(audio.attachedTo == nil)
        #expect(after.trackID(ofClip: split.soundLayerID) == audio.id)
    }

    @Test("Detach Audio makes a new Audio track when the one there is busy")
    func detachMakesRoom() throws {
        var (doc, clip) = try Self.userLayout()
        let audio = doc.addTrack(.audio)
        let music = doc.addSound(SoundRef(durationMS: 9000), name: "music", atMS: 0)
        doc.updateLayer(id: music) { $0.trackID = audio }
        #expect(doc.trackID(ofClip: music) == audio)
        let split = try #require(doc.detachingSound(ofLayer: clip))
        let after = split.document
        let home = try #require(after.trackID(ofClip: split.soundLayerID))
        let track = try #require(after.track(id: home))
        #expect(track.kind == .audio && track.attachedTo == nil)
        #expect(after.timelineTracks.last?.id == home)
    }

    @Test("Re-attach puts the sound back under its video")
    func reattachComesBackUnder() throws {
        let (doc, clip) = try Self.userLayout()
        let split = try #require(doc.detachingSound(ofLayer: clip))
        let back = try #require(split.document.reattachingSound(ofLayer: split.soundLayerID))
        #expect(Self.soundIsUnderItsVideo(back.document, clip))
    }

    @Test("Deleting a video track takes its sound row with it")
    func deletingTheVideoTakesTheRow() throws {
        var (doc, clip) = try Self.userLayout()
        let v3 = try #require(doc.trackID(ofClip: clip))
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.deleteTrack(v3)
        #expect(!doc.tracks.contains { $0.id == row })
        #expect(!doc.timelineTracks.contains { $0.attachedTo != nil })
    }

    // MARK: - Old documents

    @Test("An old document's linked Audio track becomes the row under the video, its mute kept")
    func oldDocumentsMigrate() throws {
        var doc = PhotonzDocument.recording(Fixture.movie(), name: "take")
        let clip = doc.layers[0].id
        // How a document written before this saved it: V1 and an Audio
        // track, the clip pinned to the Audio track, which was muted.
        let v1 = DocumentTrack(name: "V1", kind: .video)
        let audio = DocumentTrack(name: "Audio", kind: .audio, isMuted: true)
        doc.tracks = [v1, audio]
        doc.updateLayer(id: clip) {
            $0.trackID = v1.id
            $0.soundTrackID = audio.id
        }
        #expect(Self.shape(doc) == ["V1", ">V1"])
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.track(id: row)?.isMuted == true)
        #expect(!doc.audioMix().contains { $0.layerID == clip })
        // The old Audio track is gone: it only ever held the sound.
        #expect(!doc.timelineTracks.contains { $0.id == audio.id })
        // Writing the tracks down keeps the same picture and drops the pin.
        doc.materializeTracks()
        #expect(Self.shape(doc) == ["V1", ">V1"])
        #expect(doc.layer(id: clip)?.soundTrackID == nil)
        #expect(doc.track(id: row)?.isMuted == true)
    }

    @Test("A sound row saves which video track it belongs to; a plain track writes no such key")
    func coding() throws {
        let owner = UUID()
        let row = DocumentTrack(name: "V1 sound", kind: .audio, attachedTo: owner)
        let data = try JSONEncoder().encode(row)
        let back = try JSONDecoder().decode(DocumentTrack.self, from: data)
        #expect(back.attachedTo == owner)
        let plain = try JSONEncoder().encode(DocumentTrack(name: "Audio", kind: .audio))
        #expect(!(String(data: plain, encoding: .utf8) ?? "").contains("attachedTo"))
    }

    // MARK: - Letting go over it

    @Test("A clip let go over a sound row lands on the row's picture track; the two read as one row")
    func dropOverTheSoundRowIsTheTrack() throws {
        let (doc, clip) = try Self.userLayout()
        let tracks = doc.timelineTracks
        let v3 = try #require(doc.trackID(ofClip: clip))
        let row = try #require(doc.linkedSoundTrackID(ofClip: clip))
        let v2 = try #require(tracks.first { $0.name == "V2" }?.id)
        let drawn = [TrackDropRow(trackID: v3, minY: 0, maxY: 28),
                     TrackDropRow(trackID: row, minY: 32, maxY: 72),
                     TrackDropRow(trackID: v2, minY: 76, maxY: 104)]
        let joined = TrackDropRow.joiningSoundRows(drawn, of: tracks)
        #expect(joined == [TrackDropRow(trackID: v3, minY: 0, maxY: 72),
                           TrackDropRow(trackID: v2, minY: 76, maxY: 104)])
        // Over the sound row, and in the gap between it and its picture: the
        // picture track, never a new track squeezed between the two.
        #expect(TrackDrop.resolve(y: 50, rows: joined) == .onto(v3))
        #expect(TrackDrop.resolve(y: 30, rows: joined) == .onto(v3))
        #expect(TrackDrop.resolve(y: 74, rows: joined) == .newTrack(at: 1))
    }
}
