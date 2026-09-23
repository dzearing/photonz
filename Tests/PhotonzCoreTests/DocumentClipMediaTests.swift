import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The recordings and sounds on the Library's Media shelf: what a video
/// document has been given, one tile per file, kept there after its last clip
/// is cut away, the way a Premiere bin keeps what the sequence no longer uses.
struct DocumentClipMediaTests {

    private let bRoll = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 4_200,
                                 hasSound: true)
    private let music = SoundRef(durationMS: 14_000)

    private func clip(_ name: String, _ movie: MovieRef, at ms: Int = 0) -> Layer {
        var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)),
                          frame: CGRect(origin: .zero, size: movie.pixelSize))
        layer.movie = movie
        layer.time = LayerTime(inMS: ms, outMS: ms + movie.durationMS, sourceInMS: 0,
                               sourceLengthMS: movie.durationMS)
        return layer
    }

    private func sound(_ name: String, _ ref: SoundRef) -> Layer {
        Layer.sound(ref, name: name, time: LayerTime(inMS: 0, outMS: ref.durationMS,
                                                     sourceLengthMS: ref.durationMS))
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080), layers: layers)
        document.durationMS = 10_000
        return document
    }

    // MARK: - What is on the shelf

    @Test func aRecordingOnTheTimelineIsATileWithItsLength() {
        let clips = DocumentMedia.clips(in: doc([clip("b-roll", bRoll)]))
        #expect(clips.map(\.name) == ["b-roll"])
        #expect(clips.first?.durationMS == 4_200)
        #expect(clips.first?.length == "0:04")
        #expect(clips.first?.isSound == false)
    }

    @Test func aSoundOnTheTimelineIsATile() {
        let clips = DocumentMedia.clips(in: doc([sound("music", music)]))
        #expect(clips.map(\.name) == ["music"])
        #expect(clips.first?.isSound == true)
        #expect(clips.first?.length == "0:14")
    }

    /// A clip layer is a picture layer showing its frame, and that frame is not
    /// a picture the document holds: the recording is one tile, not two.
    @Test func aRecordingIsNotAlsoAPictureTile() {
        #expect(DocumentMedia.items(in: doc([clip("b-roll", bRoll)])).isEmpty)
    }

    /// Cut in two, or put down twice, it is still one file.
    @Test func twoClipsOfOneRecordingAreOneTile() {
        let clips = DocumentMedia.clips(in: doc([clip("b-roll 2", bRoll, at: 6_000),
                                                 clip("b-roll", bRoll)]))
        #expect(clips.count == 1)
        #expect(clips.first?.uses == 2)
        #expect(clips.first?.name == "b-roll")
    }

    /// Its sound taken off it is the same file, so it is the same tile.
    @Test func aRecordingsDetachedSoundIsTheRecordingsTile() {
        let detached = sound("b-roll audio", bRoll.soundRef ?? music)
        var picture = clip("b-roll", bRoll)
        picture.soundDetached = true
        let clips = DocumentMedia.clips(in: doc([detached, picture]))
        #expect(clips.count == 1)
        #expect(clips.first?.isSound == false)
        #expect(clips.first?.movie == bRoll)
    }

    // MARK: - What the document was given

    /// A file brought in is remembered under its own name, the way the mock
    /// captions b-roll.mov.
    @Test func aRememberedFileWearsItsFileName() {
        var document = doc([clip("b-roll", bRoll)])
        document.rememberMedia(.recording(bRoll), named: "b-roll.mov")
        #expect(DocumentMedia.clips(in: document).map(\.name) == ["b-roll.mov"])
    }

    /// Cutting the last clip of it away does not take the file out of the
    /// document: it is still there to be put down again.
    @Test func aFileStaysOnTheShelfAfterItsLastClipIsGone() {
        var document = doc([])
        document.rememberMedia(.sound(music), named: "music.wav")
        let clips = DocumentMedia.clips(in: document)
        #expect(clips.map(\.name) == ["music.wav"])
        #expect(clips.first?.uses == 0)
        #expect(clips.first?.detail == "0:14, not on the timeline")
    }

    @Test func rememberingTheSameFileTwiceIsOneEntry() {
        var document = doc([])
        document.rememberMedia(.recording(bRoll), named: "b-roll.mov")
        document.rememberMedia(.recording(bRoll), named: "b-roll copy.mov")
        #expect(document.media.count == 1)
        #expect(document.media.first?.name == "b-roll.mov")
    }

    /// The order things were brought in, first first, as the mock lists
    /// intro.mov, demo.mov, b-roll.mov, music.wav. What is on the timeline but
    /// was never remembered (a document from before the shelf held clips)
    /// comes after, oldest first.
    @Test func theShelfListsFilesInTheOrderTheyWereBroughtIn() {
        let intro = MovieRef(pixelSize: CGSize(width: 10, height: 10), durationMS: 6_000)
        let older = MovieRef(pixelSize: CGSize(width: 10, height: 10), durationMS: 1_000)
        var document = doc([clip("b-roll", bRoll), clip("older", older)])
        document.rememberMedia(.recording(intro), named: "intro.mov")
        document.rememberMedia(.recording(bRoll), named: "b-roll.mov")
        document.rememberMedia(.sound(music), named: "music.wav")
        #expect(DocumentMedia.clips(in: document).map(\.name)
                == ["intro.mov", "b-roll.mov", "music.wav", "older"])
    }

    @Test func aClipIsFoundByTheIdItsTileCarries() {
        var document = doc([])
        document.rememberMedia(.sound(music), named: "music.wav")
        #expect(DocumentMedia.clip(id: music.id.uuidString, in: document)?.name == "music.wav")
        #expect(DocumentMedia.clip(id: UUID().uuidString, in: document) == nil)
        #expect(DocumentMedia.item(id: music.id.uuidString, in: document) == nil)
    }

    @Test func entriesCarryTheNameAndTheLengthSearchReads() {
        var document = doc([clip("b-roll", bRoll)])
        document.rememberMedia(.recording(bRoll), named: "b-roll.mov")
        let entries = DocumentMedia.clipEntries(in: document)
        #expect(entries.map(\.name) == ["b-roll.mov"])
        #expect(entries.first?.detail == "0:04, used once")
        #expect(entries.first?.scope == .media)
    }

    // MARK: - Saving

    @Test func theFilesADocumentWasGivenSurviveASave() throws {
        var document = doc([])
        document.rememberMedia(.recording(bRoll), named: "b-roll.mov")
        document.rememberMedia(.sound(music), named: "music.wav")
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.media == document.media)
    }

    /// A document given nothing writes nothing about it, so every file saved
    /// before the shelf held clips is byte for byte what it was.
    @Test func aDocumentGivenNothingWritesNoMediaKey() throws {
        let data = try JSONEncoder().encode(doc([]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\"media\""))
    }
}
