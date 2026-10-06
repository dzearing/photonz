import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Why a track turns a clip away** (`ClipPlacementRefusal.swift`).
///
/// A clip carried onto a track that cannot take it used to read "no room on
/// Audio" under the hand whatever the reason, so an editor went looking for a
/// clip in the way that was not there. A refused landing now says which of the
/// three it is: the wrong kind of track, a locked one, or something already
/// there at that time.
@Suite("Why a track refuses a clip")
struct ClipPlacementRefusalTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 6000, hasSound: true)

    /// A recording at the bottom, a title over it, and some music: tracks
    /// top to bottom are the title's, V1, the recording's sound and the music's.
    static func cut() -> (doc: PhotonzDocument, recording: UUID, title: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let recording = doc.layers[0].id
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 1000, outMS: 3000)
        doc.addLayer(title)
        let music = doc.addSound(SoundRef(durationMS: 5000), name: "music", atMS: 0)
        return (doc, recording, title.id, music)
    }

    static func track(_ doc: PhotonzDocument, _ kind: DocumentTrack.Kind) throws -> DocumentTrack {
        try #require(doc.timelineTracks.first { $0.kind == kind })
    }

    // MARK: - One clip

    @Test("Picture carried onto a sound track is refused because the track takes sound only")
    func pictureOntoSound() throws {
        let (doc, _, title, _) = Self.cut()
        let audio = try Self.track(doc, .audio)
        let refusal = try #require(doc.placementRefusal(title, onTrack: audio.id))
        #expect(refusal.reason == .wrongKind)
        #expect(refusal.track.id == audio.id)
        #expect(!doc.canPlace(title, onTrack: audio.id))
    }

    @Test("Sound carried onto a picture track is refused because the track takes picture only")
    func soundOntoPicture() throws {
        let (doc, _, _, music) = Self.cut()
        let video = try Self.track(doc, .video)
        let refusal = try #require(doc.placementRefusal(music, onTrack: video.id))
        #expect(refusal.reason == .wrongKind)
    }

    @Test("A locked track says it is locked, even with room on it")
    func lockedTrack() throws {
        var (doc, recording, title, _) = Self.cut()
        doc.updateLayer(id: recording) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 6000) }
        let v1 = doc.timelineTracks[1].id
        doc.updateTrack(v1) { $0.isLocked = true }
        let refusal = try #require(doc.placementRefusal(title, onTrack: v1))
        #expect(refusal.reason == .locked)
        #expect(refusal.track.id == v1)
    }

    @Test("A clip on a locked track cannot leave it, and it is its own track that is named")
    func leavingALockedTrack() throws {
        var (doc, recording, title, _) = Self.cut()
        doc.updateLayer(id: recording) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 6000) }
        let home = try #require(doc.trackID(ofClip: title))
        doc.updateTrack(home) { $0.isLocked = true }
        let v1 = doc.timelineTracks[1].id
        let refusal = try #require(doc.placementRefusal(title, onTrack: v1))
        #expect(refusal.reason == .locked)
        #expect(refusal.track.id == home)
        #expect(doc.lockRefusal(ofClip: title)?.track.id == home)
    }

    @Test("A locked sound track turns picture away for being the wrong kind: unlocking it would not help")
    func kindBeforeLock() throws {
        var (doc, _, title, _) = Self.cut()
        let audio = try Self.track(doc, .audio)
        doc.updateTrack(audio.id) { $0.isLocked = true }
        #expect(doc.placementRefusal(title, onTrack: audio.id)?.reason == .wrongKind)
    }

    @Test("Something already there at that time is no room")
    func overlap() throws {
        let (doc, _, title, _) = Self.cut()
        let v1 = doc.timelineTracks[1].id
        #expect(doc.placementRefusal(title, onTrack: v1)?.reason == .noRoom)
    }

    @Test("A landing that is allowed has nothing to refuse")
    func allowed() throws {
        var (doc, recording, title, _) = Self.cut()
        doc.updateLayer(id: recording) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 6000) }
        let v1 = doc.timelineTracks[1].id
        #expect(doc.placementRefusal(title, onTrack: v1, atInMS: 1000) == nil)
        #expect(doc.placementRefusal(title, onTrack: v1, atInMS: 500)?.reason == .noRoom)
        #expect(doc.lockRefusal(ofClip: title) == nil)
    }

    // MARK: - Several clips

    /// Two clips on V1, end to end, and a title on a track of its own above.
    static func twoOnV1() throws -> (doc: PhotonzDocument, first: UUID, second: UUID, v1: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let first = doc.layers[0].id
        doc.updateLayer(id: first) { $0.time = LayerTime(inMS: 0, outMS: 3000, sourceLengthMS: 6000) }
        let second = doc.addClip(Self.movie, name: "b-roll", atMS: 3000,
                                 frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let v1 = try #require(doc.trackID(ofClip: first))
        let landedOn = try #require(doc.trackID(ofClip: second))
        let moved = doc.moveClip(second, toTrack: v1)
        #expect(moved)
        doc.deleteTrack(landedOn)
        return (doc, first, second, v1)
    }

    @Test("Several picture clips carried down onto sound are refused for the kind, naming the sound track")
    func severalOntoSound() throws {
        let (doc, first, second, _) = try Self.twoOnV1()
        let audio = try Self.track(doc, .audio)
        let refusal = try #require(doc.clipsMoveRefusal([first, second], carrying: first, to: .onto(audio.id)))
        #expect(refusal.reason == .wrongKind)
        #expect(refusal.track.id == audio.id)
        #expect(!doc.canMoveClips([first, second], carrying: first, to: .onto(audio.id)))
    }

    @Test("Several clips carried onto a locked track say it is locked")
    func severalOntoLocked() throws {
        var (doc, first, second, _) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        doc.updateTrack(v2) { $0.isLocked = true }
        let refusal = try #require(doc.clipsMoveRefusal([first, second], carrying: first, to: .onto(v2)))
        #expect(refusal.reason == .locked)
        #expect(refusal.track.id == v2)
    }

    @Test("Several clips meeting something already there are no room")
    func severalNoRoom() throws {
        var (doc, first, second, _) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        var inTheWay = Layer(name: "In the way", content: .text(TextContent(string: "x")),
                             frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        inTheWay.time = LayerTime(inMS: 3500, outMS: 4000)
        doc.addLayer(inTheWay)
        let moved = doc.moveClip(inTheWay.id, toTrack: v2)
        #expect(moved)
        let refusal = try #require(doc.clipsMoveRefusal([first, second], carrying: first, to: .onto(v2)))
        #expect(refusal.reason == .noRoom)
        #expect(refusal.track.id == v2)
    }

    @Test("Where another picked clip is the one turned away, that clip's track is named")
    func anotherClipRefused() throws {
        var (doc, first, _, v1) = try Self.twoOnV1()
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 0, outMS: 2000)
        doc.addLayer(title)
        // The title in the hand down onto V1 takes the first clip down onto Audio.
        let refusal = try #require(doc.clipsMoveRefusal([title.id, first], carrying: title.id, to: .onto(v1)))
        #expect(refusal.reason == .wrongKind)
        #expect(refusal.track.kind == .audio)
    }

    @Test("A move that is allowed has nothing to refuse")
    func severalAllowed() throws {
        var (doc, first, second, _) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        #expect(doc.clipsMoveRefusal([first, second], carrying: first, to: .onto(v2)) == nil)
        #expect(doc.canMoveClips([first, second], carrying: first, to: .onto(v2)))
    }

    // MARK: - What it says

    @Test("Each reason reads as a short label naming the track")
    func readings() {
        let audio = DocumentTrack(name: "Audio", kind: .audio)
        let video = DocumentTrack(name: "V2", kind: .video)
        let captions = DocumentTrack(name: "Captions", kind: .captions)
        #expect(ClipPlacementRefusal(reason: .wrongKind, track: audio).reading == "Audio takes sound only")
        #expect(ClipPlacementRefusal(reason: .wrongKind, track: video).reading == "V2 takes picture only")
        #expect(ClipPlacementRefusal(reason: .wrongKind, track: captions).reading == "Captions takes captions only")
        #expect(ClipPlacementRefusal(reason: .locked, track: video).reading == "V2 is locked")
        #expect(ClipPlacementRefusal(reason: .noRoom, track: audio).reading == "no room on Audio")
    }

    @Test("Every label fits the chrome's thirty characters with a track name of the usual length")
    func fitsTheChrome() {
        for kind in DocumentTrack.Kind.allCases {
            let track = DocumentTrack(name: "\(kind.title) 2", kind: kind)
            for reason in [ClipPlacementRefusal.Reason.wrongKind, .locked, .noRoom] {
                let words = ClipPlacementRefusal(reason: reason, track: track).reading
                #expect(words.count <= 30, "\(words)")
            }
        }
    }
}
