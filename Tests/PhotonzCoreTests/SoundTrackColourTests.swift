import Foundation
import PhotonzCore
import Testing

/// **Which colour a sound track wears** (`DocumentTracks.swift`,
/// `docs/design/mocks/pages/video-audio.html`).
///
/// The mock gives each sound lane a colour of its own, top to bottom: cyan
/// for the first, purple for the second, and its fade diamonds and level
/// points wear that colour. The timeline asks which sound track a track is,
/// counting only sound tracks, and picks the colour from that.
@Suite("Sound track colour")
struct SoundTrackColourTests {

    @Test("Sound tracks are counted top to bottom, skipping picture and captions")
    func countsOnlySound() {
        let v1 = DocumentTrack(name: "V1", kind: .video)
        let a1 = DocumentTrack(name: "Audio 1", kind: .audio)
        let captions = DocumentTrack(name: "Captions", kind: .captions)
        let a2 = DocumentTrack(name: "Audio 2", kind: .audio)
        let a3 = DocumentTrack(name: "Audio 3", kind: .audio)
        let tracks = [v1, a1, captions, a2, a3]
        #expect(tracks.soundTrackNumber(of: a1.id) == 0)
        #expect(tracks.soundTrackNumber(of: a2.id) == 1)
        #expect(tracks.soundTrackNumber(of: a3.id) == 2)
    }

    @Test("A picture track, or a track that is not there, has no sound number")
    func notSound() {
        let v1 = DocumentTrack(name: "V1", kind: .video)
        let a1 = DocumentTrack(name: "Audio 1", kind: .audio)
        #expect([v1, a1].soundTrackNumber(of: v1.id) == nil)
        #expect([v1, a1].soundTrackNumber(of: UUID()) == nil)
    }

    @Test("A recording's own sound and music dropped under it are the first and second sound tracks")
    func recordingAndMusic() {
        var doc = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: 6000, hasSound: true),
            name: "take")
        let music = doc.addSound(SoundRef(durationMS: 5000), name: "music", atMS: 0)
        let tracks = doc.timelineTracks
        let linkedTrack = doc.linkedSoundsByTrack.first { !$0.value.isEmpty }?.key
        let musicTrack = doc.trackID(ofClip: music)
        #expect(linkedTrack.flatMap { tracks.soundTrackNumber(of: $0) } == 0)
        #expect(musicTrack.flatMap { tracks.soundTrackNumber(of: $0) } == 1)
    }
}
