import CoreGraphics
import XCTest
@testable import PhotonzCore

// Captions as a track, a look and a lit word (`Sources/PhotonzCore/CaptionLook.swift`,
// `docs/design/mocks/pages/video-captions.html`).
//
// The mock puts every cue on ONE Captions track, side by side, restyles the
// whole lot from one Caption style row, and lights the word being said. What is
// pinned here is the arithmetic under each: which track the captions land on,
// what a look does to every caption at once, which characters are lit at a
// moment, and when the app listens by itself.
final class CaptionTrackTests: XCTestCase {

    private func word(_ text: String, _ startMS: Int, _ endMS: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: startMS, endMS: endMS, confidence: 0.9)
    }

    private let heard: [TranscribedWord] = [
        TranscribedWord("Capture", startMS: 200, endMS: 700, confidence: 0.9),
        TranscribedWord("the", startMS: 700, endMS: 900, confidence: 0.9),
        TranscribedWord("screen.", startMS: 900, endMS: 1_500, confidence: 0.9),
        TranscribedWord("Design", startMS: 2_600, endMS: 3_100, confidence: 0.9),
        TranscribedWord("it.", startMS: 3_100, endMS: 3_600, confidence: 0.9),
    ]

    /// A recording-shaped document with captions landed the way the app lands
    /// them: every cue in one Captions group.
    private func documentWithCaptionTrack(look: CaptionLook? = nil) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 6_000)
        document.addLayer(clip)
        document.landCaptions(CaptionCues.cues(from: heard), look: look)
        return document
    }

    // MARK: - One track

    func testCaptionsLandOnOneCaptionsTrack() {
        let document = documentWithCaptionTrack()
        let captionTracks = document.timelineTracks.filter { $0.kind == .captions }
        XCTAssertEqual(captionTracks.count, 1, "every cue on one row, the way the mock draws it")
        XCTAssertEqual(captionTracks.first?.name, "Captions")
        guard let track = captionTracks.first else { return }
        let onIt = document.clipIDs(onTrack: track.id)
        XCTAssertEqual(onIt.count, 1, "the group of cues is the one thing on the track")
        XCTAssertEqual(document.captionCueIDs(onTrack: track.id), document.captionLayers.map(\.id),
                       "and the cues on it are every caption, earliest first")
    }

    func testTheCaptionsTrackSitsOverThePicture() {
        let document = documentWithCaptionTrack()
        let kinds = document.timelineTracks.map(\.kind)
        XCTAssertEqual(kinds.first, .captions)
    }

    func testWritingAgainReplacesTheTrackRatherThanAddingASecond() {
        var document = documentWithCaptionTrack()
        document.landCaptions(CaptionCues.cues(from: heard), look: nil)
        XCTAssertEqual(document.timelineTracks.filter { $0.kind == .captions }.count, 1)
        XCTAssertEqual(document.captionLayers.count, CaptionCues.cues(from: heard).count)
    }

    func testTheLastCaptionNeverRunsPastTheEndOfTheFilm() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 3_700)
        document.addLayer(clip)
        let before = document.documentDurationMS
        // The last word ends at 3,600 ms and a line lingers after its last word,
        // which would carry it past the end of the film and make it longer.
        document.landCaptions(CaptionCues.cues(from: heard))
        XCTAssertEqual(document.captionLayers.last?.time?.outMS, 3_700)
        XCTAssertEqual(document.documentDurationMS, before, "captions never lengthen the film")
    }

    func testWordsFollowABarThatWasMovedOffThem() {
        let words = Array(heard.prefix(3))
        let moved = CaptionCue.words(words, fittedTo: LayerTime(inMS: 5_000, outMS: 6_300))
        XCTAssertEqual(moved.first?.startMS, 5_000)
        XCTAssertEqual(moved.last?.endMS, 6_300)
        XCTAssertEqual(CaptionCue.words(words, fittedTo: LayerTime(inMS: 0, outMS: 2_000)), words,
                       "words still under their bar keep the moments they were heard at")
    }

    func testAGroupOfOrdinaryLayersIsStillAPictureClip() {
        var group = Layer(name: "G", content: .group(GroupContent(children: [
            Layer(name: "a", content: .text(TextContent(string: "a")),
                  frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
        ])), frame: .zero)
        group.time = LayerTime(inMS: 0, outMS: 1_000)
        XCTAssertFalse(group.isCaptionGroup)
        XCTAssertEqual(group.clipTrackKind, .video)
    }

    // MARK: - Editing a cue in place

    func testAClickOnThePictureFindsTheCaptionOnScreenNotOneStillToCome() throws {
        let document = documentWithCaptionTrack()
        // Every cue fills the Captions layer's box; at 950 ms only the first is
        // on screen, and the second (later in the stack) must not take the click.
        let band = try XCTUnwrap(document.captionsLayers.first).frame
        let point = CGPoint(x: band.midX, y: band.midY)
        let first = document.captionLayers[0].id
        XCTAssertEqual(document.hidingWhatIsOffScreen(atTimeMS: 950).hitTest(point)?.id, first)
        let second = document.captionLayers[1]
        let atSecond = document.hidingWhatIsOffScreen(atTimeMS: second.time?.inMS ?? 0).hitTest(point)
        XCTAssertEqual(atSecond?.id, second.id)
        XCTAssertEqual(document.hidingWhatIsOffScreen(atTimeMS: 950).layers.map(\.frame),
                       document.layers.map(\.frame), "nothing moves, it is only not there to click")
    }

    func testRetypingACueChangesItsWordsAndItsNameAndKeepsItsTime() {
        var document = documentWithCaptionTrack()
        let first = document.captionLayers[0]
        XCTAssertTrue(document.setCaptionText(id: first.id, to: "Capture the screen!"))
        let after = document.captionLayers[0]
        guard case .text(let content) = after.content else { return XCTFail("still text") }
        XCTAssertEqual(content.string, "Capture the screen!")
        XCTAssertEqual(after.name, "Capture the screen!")
        XCTAssertEqual(after.time, first.time)
        XCTAssertEqual(document.captionCues[0].words.map(\.startMS), [200, 700, 900])
    }

    func testBlankWordsAreNotACaption() {
        var document = documentWithCaptionTrack()
        let id = document.captionLayers[0].id
        XCTAssertFalse(document.setCaptionText(id: id, to: "   "))
    }

    // MARK: - One look for every caption

    func testALookRestylesEveryCaptionAtOnce() {
        var document = documentWithCaptionTrack()
        var look = CaptionLook.preset(.caption)
        look.fontName = "Avenir Next"
        look.colorHex = "#FFD76A"
        look.backgroundHex = "#000000CC"
        look.fontSize = 60
        document.applyCaptionLook(look)
        XCTAssertEqual(document.captionLook, look)
        for layer in document.captionLayers {
            guard case .text(let content) = layer.content else { return XCTFail("still text") }
            XCTAssertEqual(content.fontName, "Avenir Next")
            XCTAssertEqual(content.colorHex, "#FFD76A")
            XCTAssertEqual(content.fontSize, 60)
            XCTAssertEqual(content.plateHex, "#000000CC")
        }
    }

    func testTheThreePresetsLookDifferent() {
        let caption = CaptionLook.preset(.caption)
        let lower = CaptionLook.preset(.lowerThird)
        let karaoke = CaptionLook.preset(.karaoke)
        XCTAssertNotNil(caption.backgroundHex, "the mock's caption sits on a plate")
        XCTAssertEqual(lower.alignment, .left, "a lower third hangs off the left")
        XCTAssertNil(karaoke.backgroundHex)
        XCTAssertNotNil(karaoke.activeHex)
        XCTAssertNotEqual(caption, lower)
        XCTAssertNotEqual(caption, karaoke)
        XCTAssertEqual(CaptionLook.Preset.allCases.map(\.title),
                       ["Caption", "Lower third", "Karaoke", "Bold pop", "Neon"])
    }

    func testNewCaptionsComeOutInTheDocumentsLook() {
        var look = CaptionLook.preset(.lowerThird)
        look.colorHex = "#FF0000"
        let document = documentWithCaptionTrack(look: look)
        XCTAssertEqual(document.captionLook, look)
        guard case .text(let content) = document.captionLayers[0].content else { return XCTFail() }
        XCTAssertEqual(content.colorHex, "#FF0000")
        XCTAssertEqual(content.alignment, .left)
    }

    func testAPlateTakesTheShadowOffAndNoPlatePutsItBack() {
        var document = documentWithCaptionTrack()
        var look = CaptionLook.preset(.caption)
        look.backgroundHex = "#000000CC"
        document.applyCaptionLook(look)
        XCTAssertNil(document.captionLayers[0].style.shadow, "a plate is what makes it readable")
        look.backgroundHex = nil
        document.applyCaptionLook(look)
        XCTAssertNotNil(document.captionLayers[0].style.shadow, "without one, the readable shadow")
    }

    // MARK: - The word being said

    func testTheWordBeingSaidIsLit() {
        let words = Array(heard.prefix(3))
        let string = "Capture the screen."
        XCTAssertNil(CaptionActiveWord.range(in: string, words: words, atMS: 100, sung: false),
                     "nothing is lit before the first word is said")
        let lit = CaptionActiveWord.range(in: string, words: words, atMS: 950, sung: false)
        XCTAssertEqual(lit, CaptionActiveWord.Span(location: 12, length: 7), "screen.")
        let held = CaptionActiveWord.range(in: string, words: words, atMS: 1_800, sung: false)
        XCTAssertEqual(held, CaptionActiveWord.Span(location: 12, length: 7),
                       "the last word said stays lit while the line lingers")
    }

    func testKaraokeLightsEverythingSaidSoFar() {
        let words = Array(heard.prefix(3))
        let lit = CaptionActiveWord.range(in: "Capture the screen.", words: words, atMS: 750, sung: true)
        XCTAssertEqual(lit, CaptionActiveWord.Span(location: 0, length: 11), "Capture the")
    }

    func testARetypedLineWithADifferentWordCountStillLightsSomething() {
        let words = Array(heard.prefix(3))
        let lit = CaptionActiveWord.range(in: "Grab it", words: words, atMS: 1_400, sung: false)
        XCTAssertEqual(lit, CaptionActiveWord.Span(location: 5, length: 2), "the time share lands on it")
    }

    func testTheDrawnFrameCarriesTheLitWord() {
        var document = documentWithCaptionTrack()
        document.applyCaptionLook(CaptionLook.preset(.caption))
        let frame = document.drawn(atTimeMS: 950)
        let caption = frame.allLayers.first { $0.isCaption && $0.isVisible }
        guard let caption, case .text(let content) = caption.content else {
            return XCTFail("the first caption is on screen at 950 ms")
        }
        XCTAssertEqual(content.highlight?.location, 12)
        XCTAssertEqual(content.highlight?.colorHex, CaptionLook.preset(.caption).activeHex)
        guard case .text(let stored) = document.captionLayers[0].content else { return XCTFail() }
        XCTAssertNil(stored.highlight, "the document itself never has a word lit")
    }

    func testALookWithNoActiveColourLightsNothing() {
        var document = documentWithCaptionTrack()
        document.applyCaptionLook(CaptionLook.preset(.lowerThird))
        let caption = document.drawn(atTimeMS: 950).allLayers.first { $0.isCaption && $0.isVisible }
        guard let caption, case .text(let content) = caption.content else { return XCTFail() }
        XCTAssertNil(content.highlight)
    }

    // MARK: - Listening by itself

    func testItListensToASoundItHasNotHeardBefore() {
        let sound = UUID()
        XCTAssertTrue(CaptionAutoRun.shouldListen(isOn: true, hasTime: true, soundID: sound,
                                                  listenedTo: [], hasCaptions: false))
        XCTAssertFalse(CaptionAutoRun.shouldListen(isOn: false, hasTime: true, soundID: sound,
                                                   listenedTo: [], hasCaptions: false),
                       "the one toggle turns it off")
        XCTAssertFalse(CaptionAutoRun.shouldListen(isOn: true, hasTime: true, soundID: sound,
                                                   listenedTo: [sound], hasCaptions: false),
                       "a sound already listened to is not heard again, even when its captions were cleared")
        XCTAssertFalse(CaptionAutoRun.shouldListen(isOn: true, hasTime: true, soundID: sound,
                                                   listenedTo: [], hasCaptions: true),
                       "captions somebody has are never replaced behind their back")
        XCTAssertFalse(CaptionAutoRun.shouldListen(isOn: true, hasTime: true, soundID: nil,
                                                   listenedTo: [], hasCaptions: false))
        XCTAssertFalse(CaptionAutoRun.shouldListen(isOn: true, hasTime: false, soundID: sound,
                                                   listenedTo: [], hasCaptions: false))
    }

    func testWhatItListenedToAndTheLookAreSaved() throws {
        var document = documentWithCaptionTrack(look: CaptionLook.preset(.karaoke))
        let sound = UUID()
        document.noteCaptionsListened(to: sound)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        XCTAssertEqual(back.captionsListenedTo, [sound])
        XCTAssertEqual(back.captionLook, CaptionLook.preset(.karaoke))
        guard case .text(let content) = back.captionLayers[0].content else { return XCTFail() }
        XCTAssertEqual(content.activeWordHex, CaptionLook.preset(.karaoke).activeHex)
    }

    // MARK: - Out as a film

    func testAFilmWithASubtitleFileBesideItLeavesTheWordsOffThePicture() {
        let document = documentWithCaptionTrack()
        XCTAssertTrue(document.forExport(captions: .burnedIn).hasCaptions, "burned in: drawn on the picture")
        let beside = document.forExport(captions: .file(.srt))
        XCTAssertFalse(beside.hasCaptions, "a file beside it: the picture is left clean")
        XCTAssertEqual(beside.documentDurationMS, document.documentDurationMS)
        XCTAssertEqual(CaptionExport.choices.map(\.title), ["Burned in", "SRT file", "VTT file"])
    }

    // MARK: - WebVTT

    func testWebVTTComesOutInTheFormBrowsersRead() {
        let text = CaptionsVTT.text([
            CaptionCue(words: [TranscribedWord("Hello", startMS: 1_500, endMS: 3_200)],
                       inMS: 1_500, outMS: 3_200),
            CaptionCue(words: [TranscribedWord("there", startMS: 3_700_000, endMS: 3_702_000)],
                       inMS: 3_700_000, outMS: 3_702_000),
        ])
        XCTAssertTrue(text.hasPrefix("WEBVTT\n\n00:00:01.500 --> 00:00:03.200\nHello\n"), text)
        XCTAssertTrue(text.contains("\n01:01:40.000 --> 01:01:42.000\nthere\n"), text)
    }

    func testSubtitleFormatsNameTheirOwnExtension() {
        XCTAssertEqual(CaptionFileFormat.srt.fileExtension, "srt")
        XCTAssertEqual(CaptionFileFormat.vtt.fileExtension, "vtt")
        let cues = documentWithCaptionTrack().captionCues
        XCTAssertTrue(CaptionFileFormat.vtt.text(cues).hasPrefix("WEBVTT"))
        XCTAssertTrue(CaptionFileFormat.srt.text(cues).hasPrefix("1\n"))
    }
}
