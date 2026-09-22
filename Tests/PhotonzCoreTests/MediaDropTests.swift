import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a sound or a recording let go over an open document does, and what the
/// app says when the answer is no. The pointer, the sentence the canvas draws
/// and the thing that actually lands all read this, so a promise and a result
/// cannot drift apart.
@Suite("A sound or a recording dropped on a document")
struct MediaDropTests {

    // MARK: - Reading the file

    @Test(arguments: ["track.m4a", "track.mp3", "voice.wav", "bell.aiff", "note.caf",
                      "TRACK.MP3", "mix.aac", "loop.flac"])
    func aSoundFileIsReadAsSound(name: String) {
        #expect(MediaFiles.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == .sound)
    }

    @Test(arguments: ["screen.mp4", "clip.mov", "cut.m4v", "SCREEN.MOV"])
    func aRecordingIsReadAsARecording(name: String) {
        #expect(MediaFiles.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == .recording)
    }

    @Test(arguments: ["shot.png", "notes.txt", "board.photonz", "folder"])
    func everythingElseIsNeitherOfThose(name: String) {
        #expect(MediaFiles.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == nil)
    }

    // MARK: - A sound

    @Test func aSoundLandsOnATimelineAndSaysWhere() {
        let answer = MediaDrop.answer(for: .sound, named: "Sample Music.m4a",
                                      documentHasTime: true, atMS: 4_200)
        #expect(answer.landing == .soundLayer)
        #expect(answer.lands)
        #expect(answer.note == "Sample Music lands on the timeline at 0:04")
    }

    @Test func aSoundOnSomethingWithNoTimeIsRefusedInWordsWithSomethingToDo() {
        let answer = MediaDrop.answer(for: .sound, named: "Sample Music.m4a",
                                      documentHasTime: false, atMS: 0)
        #expect(answer.landing == .refused)
        #expect(!answer.lands)
        // The three things a refusal owes: what was refused, why, and the one
        // move that works (`UX-PATTERNS` §refusals).
        #expect(answer.note.contains("Sample Music"))
        #expect(answer.note.contains("timeline"))
        #expect(answer.note.contains("Open a recording"))
    }

    // MARK: - A recording

    @Test func aRecordingOnADocumentWithTimeLandsAsAClip() {
        let answer = MediaDrop.answer(for: .recording, named: "B Roll.mp4",
                                      documentHasTime: true, atMS: 61_000)
        #expect(answer.landing == .clipLayer)
        #expect(answer.lands)
        #expect(answer.note == "B Roll lands as a clip at 1:01")
    }

    @Test func aRecordingOnAPictureOpensInItsOwnWindow() {
        // A recording IS a document, so it behaves exactly as a .photonz
        // dropped on a canvas does: it opens rather than landing here.
        let answer = MediaDrop.answer(for: .recording, named: "B Roll.mp4",
                                      documentHasTime: false, atMS: 0)
        #expect(answer.landing == .openDocument)
        #expect(answer.lands)
        #expect(answer.note == "B Roll opens in its own window")
    }

    @Test func nothingIsPromisedWithNoDocumentToLandOn() {
        // An empty window: both open, because opening is all there is to do.
        for kind in [MediaDrop.Kind.sound, .recording] {
            let answer = MediaDrop.answer(for: kind, named: "Thing.mp4",
                                          documentHasTime: false, atMS: 0,
                                          hasDocument: false)
            #expect(answer.landing == (kind == .recording ? .openDocument : .refused))
        }
    }

    // MARK: - The words themselves

    @Test func theSentenceNeverShowsAFileExtension() {
        for (kind, hasTime) in [(MediaDrop.Kind.sound, true), (.sound, false),
                                (.recording, true), (.recording, false)] {
            let answer = MediaDrop.answer(for: kind, named: "Holiday Cut.mp4",
                                          documentHasTime: hasTime, atMS: 0)
            #expect(!answer.note.contains(".mp4"))
            #expect(answer.note.contains("Holiday Cut"))
        }
    }

    @Test func everyAnswerSaysSomething() {
        // The whole point of this task: no drop of a sound or a recording is
        // allowed to be silent, whichever way it goes.
        for (kind, hasTime) in [(MediaDrop.Kind.sound, true), (.sound, false),
                                (.recording, true), (.recording, false)] {
            let answer = MediaDrop.answer(for: kind, named: "Thing.mp4",
                                          documentHasTime: hasTime, atMS: 0)
            #expect(!answer.note.isEmpty)
        }
    }
}

/// Putting a second recording into a document that already runs in time. The
/// same shape `addSound` has, because a clip and a piece of sound are the same
/// kind of thing: a layer with an in and an out.
@Suite("A clip added to a document")
struct DocumentAddClipTests {

    private func recording(seconds: Double, size: CGSize = CGSize(width: 1280, height: 800))
    -> MovieRef {
        MovieRef(pixelSize: size, durationMS: Int(seconds * 1000), hasSound: true)
    }

    private func documentWithTime() -> PhotonzDocument {
        PhotonzDocument.recording(recording(seconds: 8), name: "Screen")
    }

    @Test func theClipLandsAtTheMomentItWasDroppedAndRunsTheLengthOfTheFile() {
        var doc = documentWithTime()
        let movie = recording(seconds: 3)
        let id = doc.addClip(movie, name: "B Roll", atMS: 2_000,
                             frame: CGRect(x: 100, y: 50, width: 640, height: 400))
        let clip = try! #require(doc.layer(id: id))
        #expect(clip.movie == movie)
        #expect(clip.time?.inMS == 2_000)
        #expect(clip.time?.outMS == 5_000)
        #expect(clip.time?.sourceLengthMS == 3_000)
        #expect(clip.frame == CGRect(x: 100, y: 50, width: 640, height: 400))
        #expect(clip.isClip)
    }

    @Test func theDocumentGrowsToHoldAClipThatRunsPastItsEnd() {
        var doc = documentWithTime()
        #expect(doc.durationMS == 8_000)
        _ = doc.addClip(recording(seconds: 5), name: "B Roll", atMS: 6_000,
                        frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(doc.durationMS == 11_000)
    }

    @Test func aDocumentLongEnoughAlreadyIsLeftAlone() {
        var doc = documentWithTime()
        _ = doc.addClip(recording(seconds: 1), name: "B Roll", atMS: 1_000,
                        frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(doc.durationMS == 8_000)
    }

    @Test func aClipDroppedBeforeTheStartLandsAtTheStart() {
        var doc = documentWithTime()
        let id = doc.addClip(recording(seconds: 2), name: "B Roll", atMS: -4_000,
                             frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(doc.layer(id: id)?.time?.inMS == 0)
    }

    @Test func itArrivesAboveWhatWasThereSoItCanBeSeen() {
        var doc = documentWithTime()
        let id = doc.addClip(recording(seconds: 2), name: "B Roll", atMS: 0,
                             frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(doc.layers.last?.id == id)
    }

    @Test func itShowsItsOwnFirstFrameBeforeAnybodyPlaysAnything() {
        var doc = documentWithTime()
        let movie = recording(seconds: 2)
        let id = doc.addClip(movie, name: "B Roll", atMS: 0,
                             frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(doc.layer(id: id)?.content == .image(movie.frameRef(atSourceMS: 0)))
    }
}
