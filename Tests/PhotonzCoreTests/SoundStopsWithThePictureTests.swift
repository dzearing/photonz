import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A song longer than the edit stops where the picture stops.
///
/// Settled on 2026-10-20: a person who has cut a talk to ninety seconds and
/// lays a three minute song under it expects ninety seconds out, not ninety
/// seconds of talk and ninety of song over a blank picture. iMovie and Clips
/// trim background music to the movie; the rest of the song is still in the
/// clip, so dragging its right edge brings it back.
@Suite("Music longer than the edit stops where the picture stops")
struct SoundStopsWithThePictureTests {

    static func recording(durationMS: Int) -> PhotonzDocument {
        let movie = MovieRef(id: UUID(), pixelSize: CGSize(width: 1920, height: 1080),
                             durationMS: durationMS, hasSound: true)
        return PhotonzDocument.recording(movie, name: "Talk")
    }

    @Test("A three minute song under a ninety second cut stops at ninety seconds")
    func songStopsWithTheCut() throws {
        var doc = Self.recording(durationMS: 90_000)
        let id = doc.addSound(SoundRef(durationMS: 180_000), name: "Song", atMS: 0)
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.inMS == 0)
        #expect(time.outMS == 90_000)
        #expect(doc.documentDurationMS == 90_000)
        #expect(doc.timelineLengthMS == 90_000)
    }

    @Test("The rest of the song stays in the clip, to be dragged back out")
    func restOfTheSongIsKept() throws {
        var doc = Self.recording(durationMS: 90_000)
        let id = doc.addSound(SoundRef(durationMS: 180_000), name: "Song", atMS: 0)
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.sourceInMS == 0)
        #expect(time.sourceLengthMS == 180_000)
    }

    @Test("A song put down part way in stops at the last picture too")
    func songFromPartWay() throws {
        var doc = Self.recording(durationMS: 8_000)
        let id = doc.addSound(SoundRef(durationMS: 14_000), name: "Song", atMS: 2_000)
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.inMS == 2_000)
        #expect(time.outMS == 8_000)
        #expect(doc.documentDurationMS == 8_000)
    }

    @Test("A sound shorter than the edit lands whole, exactly as before")
    func shorterSoundIsWhole() throws {
        var doc = Self.recording(durationMS: 8_000)
        let id = doc.addSound(SoundRef(durationMS: 4_000), name: "Ping", atMS: 1_000)
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.inMS == 1_000)
        #expect(time.outMS == 5_000)
        #expect(doc.documentDurationMS == 8_000)
    }

    @Test("A sound in a video with no picture at all lands whole and the video grows to hold it")
    func noPictureLandsWhole() throws {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 30_000)
        let id = doc.addSound(SoundRef(durationMS: 60_000), name: "Song", atMS: 0)
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.outMS == 60_000)
        #expect(doc.documentDurationMS == 60_000)
    }

    @Test("Sound already in the edit is not picture: a second song stops at the picture, not the first song")
    func otherSoundIsNotPicture() throws {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 30_000)
        _ = doc.addSound(SoundRef(durationMS: 60_000), name: "First", atMS: 0)
        let second = doc.addSound(SoundRef(durationMS: 90_000), name: "Second", atMS: 0)
        // No picture still, so the second lands whole as well.
        #expect(doc.layer(id: second)?.time?.outMS == 90_000)
        #expect(doc.soundLengthUnderThePicture(atMS: 0, lengthMS: 120_000) == 120_000)
    }

    @Test("A sound put down at or after the last picture lands whole: it was put there on purpose")
    func pastTheEndLandsWhole() throws {
        var doc = Self.recording(durationMS: 8_000)
        let id = doc.addSound(SoundRef(durationMS: 5_000), name: "Tail", atMS: 8_000)
        #expect(doc.layer(id: id)?.time?.outMS == 13_000)
    }

    @Test("A video that holds past its last clip keeps the song to the video's own end")
    func writtenLengthHolds() throws {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 30_000)
        let v1 = try #require(doc.tracks.first { $0.kind == .video })
        let movie = MovieRef(id: UUID(), pixelSize: CGSize(width: 1920, height: 1080),
                             durationMS: 8_000, hasSound: false)
        var clip = Layer(name: "Clip", content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 8_000, sourceLengthMS: 8_000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 8_000, atMS: 0, over: .onto(v1.id), edit: .overwrite)
        _ = doc.land(clip, at: landing)
        #expect(doc.documentDurationMS == 30_000)
        let id = doc.addSound(SoundRef(durationMS: 60_000), name: "Song", atMS: 0)
        #expect(doc.layer(id: id)?.time?.outMS == 30_000)
        #expect(doc.documentDurationMS == 30_000)
    }

    @Test("What a file let go on the timeline is trimmed to, read the same way")
    func lengthForADrop() {
        let doc = Self.recording(durationMS: 90_000)
        #expect(doc.soundLengthUnderThePicture(atMS: 0, lengthMS: 180_000) == 90_000)
        #expect(doc.soundLengthUnderThePicture(atMS: 30_000, lengthMS: 180_000) == 60_000)
        #expect(doc.soundLengthUnderThePicture(atMS: 30_000, lengthMS: 10_000) == 10_000)
        #expect(doc.soundLengthUnderThePicture(atMS: 90_000, lengthMS: 10_000) == 10_000)
    }
}
