import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Recordings and sounds brought into the Library without going onto the
/// timeline (`video.html`, onboarding step 2, "Fill the Library": Import, a
/// file dropped on the panel, or a capture). The shelf is a bin: what lands
/// there waits to be dragged onto a track.
struct LibraryImportTests {

    private let bRoll = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 4_200,
                                 hasSound: true)
    private let music = SoundRef(durationMS: 14_000)
    private let voice = SoundRef(durationMS: 9_000)

    private func doc() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080), layers: [])
        document.durationMS = 10_000
        return document
    }

    private func source(_ movie: MovieRef, _ name: String) -> DocumentMediaSource {
        DocumentMediaSource(media: .recording(movie), name: name)
    }

    private func source(_ sound: SoundRef, _ name: String) -> DocumentMediaSource {
        DocumentMediaSource(media: .sound(sound), name: name)
    }

    // MARK: - What lands

    @Test func filesBroughtInSitOnTheShelfInTheOrderTheyCame() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(bRoll, "b-roll.mov"), source(music, "music.wav")])
        #expect(DocumentMedia.clips(in: document).map(\.name) == ["b-roll.mov", "music.wav"])
        #expect(outcome.added == ["b-roll.mov", "music.wav"])
        #expect(outcome.firstNewID == bRoll.id)
    }

    /// The shelf is not the timeline: nothing plays them yet.
    @Test func nothingLandsOnTheTimeline() {
        var document = doc()
        document.bringIntoLibrary([source(bRoll, "b-roll.mov"), source(music, "music.wav")])
        #expect(document.layers.isEmpty)
        #expect(DocumentMedia.clips(in: document).allSatisfy { $0.uses == 0 })
        #expect(DocumentMedia.clips(in: document).first?.detail == "0:04, not on the timeline")
    }

    @Test func aFileAlreadyOnTheShelfIsNotAddedTwice() {
        var document = doc()
        document.bringIntoLibrary([source(music, "music.wav")])
        let outcome = document.bringIntoLibrary([source(music, "music copy.wav")])
        #expect(DocumentMedia.clips(in: document).map(\.name) == ["music.wav"])
        #expect(outcome.added.isEmpty)
        #expect(outcome.alreadyThere == ["music.wav"])
        #expect(outcome.firstNewID == nil)
        #expect(outcome.revealID == music.id)
    }

    /// The same file picked twice in one go is one tile.
    @Test func oneFilePickedTwiceIsOneTile() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(music, "music.wav"), source(music, "music.wav")])
        #expect(DocumentMedia.clips(in: document).count == 1)
        #expect(outcome.added == ["music.wav"])
        #expect(outcome.alreadyThere.isEmpty)
    }

    // MARK: - What it says

    @Test func oneFileSaysItsName() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(music, "music.wav")])
        #expect(outcome.title == "Added to Library")
        #expect(outcome.detail == "music.wav is in the Library")
    }

    @Test func twoFilesSayBothNames() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(bRoll, "b-roll.mov"), source(music, "music.wav")])
        #expect(outcome.detail == "b-roll.mov and music.wav are in the Library")
    }

    @Test func manyFilesSayHowMany() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(bRoll, "b-roll.mov"), source(music, "music.wav"),
                                                 source(voice, "voice.m4a")])
        #expect(outcome.detail == "3 files are in the Library")
    }

    @Test func aFileAlreadyThereSaysSo() {
        var document = doc()
        document.bringIntoLibrary([source(music, "music.wav")])
        let outcome = document.bringIntoLibrary([source(music, "music.wav")])
        #expect(outcome.title == "Already in Library")
        #expect(outcome.detail == "music.wav is already in the Library")
    }

    @Test func aFileThatWouldNotOpenSaysWhy() {
        var document = doc()
        let outcome = document.bringIntoLibrary([], unreadable: ["notes.mov"])
        #expect(outcome.title == "Not added")
        #expect(outcome.detail == "There is nothing in notes.mov the app can play")
        #expect(document.media.isEmpty)
    }

    @Test func someLandAndSomeDoNot() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(music, "music.wav")], unreadable: ["broken.mov"])
        #expect(outcome.title == "Added to Library")
        #expect(outcome.detail == "music.wav is in the Library. There is nothing in broken.mov the app can play")
    }

    /// The pill that says so reads the same words.
    @Test func theNoticeReadsTheOutcome() {
        var document = doc()
        let outcome = document.bringIntoLibrary([source(music, "music.wav")])
        let notice = CopyConfirmation(subject: .broughtIntoLibrary(outcome), shownAt: Date())
        #expect(notice.title == "Added to Library")
        #expect(notice.detail == "music.wav is in the Library")
    }
}
