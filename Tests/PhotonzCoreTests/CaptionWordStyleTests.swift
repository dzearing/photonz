import CoreGraphics
import Foundation
import XCTest
@testable import PhotonzCore

// How the words of a caption show (`Sources/PhotonzCore/CaptionWordStyle.swift`).
//
// The user, 2026-09-25: "maybe I want to have a sentence at a time, or 3 words
// at a time, or 1... maybe the current word should have a soft grow animation
// with a bounce ... Maybe glow on the overall text vs the active word. I want
// it to be easy to tweak." Pinned here: Show regroups the transcript and keeps
// every word, time and hand fix; the current word's motion is a pure function
// of time, so the canvas and the exported film draw the same frame; the named
// styles set everything at once; a style of your own can be kept.
final class CaptionWordStyleTests: XCTestCase {

    private let heard: [TranscribedWord] = [
        TranscribedWord("Capture", startMS: 200, endMS: 700),
        TranscribedWord("the", startMS: 700, endMS: 900),
        TranscribedWord("screen,", startMS: 900, endMS: 1_500),
        TranscribedWord("design", startMS: 1_600, endMS: 2_100),
        TranscribedWord("it.", startMS: 2_100, endMS: 2_500),
        TranscribedWord("Then", startMS: 3_000, endMS: 3_300),
        TranscribedWord("let", startMS: 3_300, endMS: 3_500),
        TranscribedWord("the", startMS: 3_500, endMS: 3_600),
        TranscribedWord("agent", startMS: 3_600, endMS: 4_000),
        TranscribedWord("finish.", startMS: 4_000, endMS: 4_600),
    ]

    private let size = CGSize(width: 1920, height: 1080)

    private func captioned(look: CaptionLook? = nil) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: size)
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(origin: .zero, size: size))
        clip.time = LayerTime(inMS: 0, outMS: 8_000)
        document.addLayer(clip)
        document.landCaptions(CaptionCues.cues(from: heard), look: look)
        return document
    }

    private func texts(_ document: PhotonzDocument) -> [String] {
        document.captionLayers.sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }.compactMap {
            guard case .text(let content) = $0.content else { return nil }
            return content.string
        }
    }

    private func allWords(_ document: PhotonzDocument) -> [String] {
        document.captionLayers.sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
            .flatMap { $0.captionWords ?? [] }.map(\.text)
    }

    // MARK: - Show

    func testShowOffersTheFiveGroupingsInOrder() {
        XCTAssertEqual(CaptionGrouping.allCases.map(\.title),
                       ["Sentence", "Line", "3 words", "2 words", "1 word"])
        XCTAssertEqual(CaptionLook.standard.show, .line, "a line at a time until somebody picks another")
        XCTAssertEqual(CaptionLook.standard.lines, 1)
    }

    func testOneWordAtATimeGivesEveryWordItsOwnCaption() {
        let cues = CaptionCues.cues(from: heard, showing: .oneWord, lines: 1, charactersPerLine: 42)
        XCTAssertEqual(cues.map(\.text), heard.map(\.text))
        for (cue, next) in zip(cues, cues.dropFirst()) {
            XCTAssertLessThanOrEqual(cue.outMS, next.inMS, "never two on screen at once")
        }
        XCTAssertEqual(cues[0].outMS, cues[1].inMS, "a word stays up until the next one arrives")
    }

    func testThreeWordsAtATimeAlsoBreaksWhereASentenceEnds() {
        let cues = CaptionCues.cues(from: heard, showing: .threeWords, lines: 1, charactersPerLine: 42)
        XCTAssertEqual(cues.map(\.text), ["Capture the screen,", "design it.", "Then let the", "agent finish."])
        let two = CaptionCues.cues(from: heard, showing: .twoWords, lines: 1, charactersPerLine: 42)
        XCTAssertTrue(two.allSatisfy { $0.words.count <= 2 })
    }

    func testASentenceAtATimeHoldsEachSentenceWhole() {
        let cues = CaptionCues.cues(from: heard, showing: .sentence, lines: 2, charactersPerLine: 42)
        XCTAssertEqual(cues.map(\.text), ["Capture the screen, design it.", "Then let the agent finish."])
    }

    func testLinesIsHowManyLinesACaptionMayFill() {
        let one = CaptionCues.cues(from: heard, showing: .line, lines: 1, charactersPerLine: 12)
        let two = CaptionCues.cues(from: heard, showing: .line, lines: 2, charactersPerLine: 12)
        XCTAssertTrue(one.allSatisfy { $0.text.count <= 12 }, one.map(\.text).description)
        XCTAssertLessThan(two.count, one.count, "two lines hold more words per caption")
        XCTAssertTrue(two.allSatisfy { $0.text.count <= 24 })
    }

    func testPickingOneWordRegroupsTheCaptionsLayerKeepingEveryWordAndTime() throws {
        var document = captioned()
        let layer = try XCTUnwrap(document.captionsLayers.first)
        let before = document.captionLayers.flatMap { $0.captionWords ?? [] }
        var look = document.captionLook ?? .standard
        look.show = .oneWord
        document.applyCaptionLook(look, toCaptions: layer.id)
        XCTAssertEqual(texts(document), heard.map(\.text), "one caption per word")
        let after = document.captionLayers.flatMap { $0.captionWords ?? [] }
        XCTAssertEqual(after.map(\.startMS), before.map(\.startMS), "every word keeps its moment")
        let still = try XCTUnwrap(document.captionsLayers.first)
        XCTAssertEqual(still.id, layer.id, "the same Captions layer")
        XCTAssertEqual(still.frame, layer.frame, "in the same place")
        look.show = .line
        document.applyCaptionLook(look, toCaptions: layer.id)
        XCTAssertEqual(texts(document), CaptionCues.cues(from: heard).map(\.text),
                       "and back to lines, as they were")
    }

    func testAWordFixedByHandSurvivesRegrouping() throws {
        var document = captioned()
        let first = try XCTUnwrap(document.captionLayers.min { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) })
        guard case .text(let content) = first.content else { return XCTFail() }
        document.setCaptionText(id: first.id, to: content.string.replacingOccurrences(of: "the", with: "a"))
        var look = document.captionLook ?? .standard
        look.show = .oneWord
        document.applyCaptionLook(look, toCaptions: try XCTUnwrap(document.captionsLayers.first).id)
        XCTAssertEqual(Array(allWords(document).prefix(3)), ["Capture", "a", "screen,"])
    }

    func testFreshCaptionsLandInTheLooksGrouping() {
        var look = CaptionLook.standard
        look.show = .twoWords
        let document = captioned(look: look)
        XCTAssertTrue(document.captionLayers.allSatisfy { ($0.captionWords?.count ?? 0) <= 2 })
        XCTAssertEqual(allWords(document), heard.map(\.text))
    }

    // MARK: - The current word's motion

    func testGrowRisesToItsScaleAndStays() {
        let word = CaptionWordLook(scale: 1.3, motion: .grow, speedMS: 200)
        XCTAssertEqual(word.drawnScale(msIntoWord: 0), 1, accuracy: 0.001)
        let mid = word.drawnScale(msIntoWord: 100)
        XCTAssertGreaterThan(mid, 1)
        XCTAssertLessThan(mid, 1.3)
        XCTAssertEqual(word.drawnScale(msIntoWord: 200), 1.3, accuracy: 0.001)
        XCTAssertEqual(word.drawnScale(msIntoWord: 5_000), 1.3, accuracy: 0.001)
    }

    func testGrowWithBounceOvershootsThenSettles() {
        let word = CaptionWordLook(scale: 1.3, motion: .growBounce, speedMS: 200)
        XCTAssertEqual(word.drawnScale(msIntoWord: 0), 1, accuracy: 0.001)
        let peak = stride(from: 0, through: 600, by: 10).map { word.drawnScale(msIntoWord: $0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.33, "a soft spring goes past and comes back")
        XCTAssertLessThan(peak, 1.45, "soft, not a jolt")
        XCTAssertEqual(word.drawnScale(msIntoWord: word.settleMS), 1.3, accuracy: 0.01)
    }

    func testPopComesInSmallAndLandsAtItsScale() {
        let word = CaptionWordLook(scale: 1.0, motion: .pop, speedMS: 200)
        XCTAssertLessThan(word.drawnScale(msIntoWord: 0), 0.8)
        XCTAssertEqual(word.drawnScale(msIntoWord: 400), 1.0, accuracy: 0.01)
    }

    func testUnderlineSweepsAcrossTheWord() {
        let word = CaptionWordLook(motion: .underline, speedMS: 200)
        XCTAssertEqual(word.drawnUnderline(msIntoWord: 0) ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(word.drawnUnderline(msIntoWord: 400) ?? -1, 1, accuracy: 0.001)
        XCTAssertNil(CaptionWordLook(motion: .grow).drawnUnderline(msIntoWord: 100))
        XCTAssertEqual(CaptionWordMotion.allCases.map(\.title),
                       ["None", "Grow", "Grow with bounce", "Pop", "Underline sweep"])
    }

    func testPickingAGrowAtFullSizeGivesItSomewhereToGrow() {
        var word = CaptionWordLook(scale: 1.0, motion: .none)
        word.pick(.growBounce)
        XCTAssertGreaterThan(word.scale, 1, "a grow at 100% would do nothing you could see")
        word.scale = 1.4
        word.pick(.grow)
        XCTAssertEqual(word.scale, 1.4, "a size somebody chose is kept")
    }

    // MARK: - The moment drawn

    private func shownCaption(_ document: PhotonzDocument, at ms: Int) -> TextContent? {
        let caption = document.drawn(atTimeMS: ms).allLayers.first { $0.isCaption && $0.isVisible }
        guard let caption, case .text(let content) = caption.content else { return nil }
        return content
    }

    func testTheDrawnFrameCarriesTheCurrentWordMidPop() throws {
        var look = CaptionLook.preset(.boldPop)
        look.word.speedMS = 300
        let document = captioned(look: look)
        let content = try XCTUnwrap(shownCaption(document, at: 950))
        let paint = try XCTUnwrap(content.wordPaint)
        XCTAssertEqual(paint.word, CaptionActiveWord.Span(location: 12, length: 7), "screen,")
        XCTAssertGreaterThan(paint.scale, 1, "50ms into a word, it is on its way up")
        XCTAssertLessThan(paint.scale, look.word.scale)
        let later = try XCTUnwrap(shownCaption(document, at: 1_450)?.wordPaint)
        XCTAssertEqual(later.scale, look.word.scale, accuracy: 0.02, "and settled by the end of it")
        guard case .text(let stored) = document.captionLayers[0].content else { return XCTFail() }
        XCTAssertNil(stored.wordPaint, "the document itself never holds a moment")
    }

    func testSaidAndComingWordsCarryTheirShade() throws {
        var look = CaptionLook.standard
        look.said = .dim
        look.coming = .hidden
        let document = captioned(look: look)
        let paint = try XCTUnwrap(shownCaption(document, at: 750)?.wordPaint)
        XCTAssertEqual(paint.said, .dim)
        XCTAssertEqual(paint.coming, .hidden)
        XCTAssertEqual(paint.word.location, 8, "the")
        XCTAssertEqual(CaptionWordShade.saidChoices.map(\.title), ["Full", "Dim", "Lit"])
        XCTAssertEqual(CaptionWordShade.comingChoices.map(\.title), ["Full", "Dim", "Hidden"])
    }

    func testAPlainLookDrawsExactlyAsBefore() throws {
        let document = captioned(look: .preset(.caption))
        let content = try XCTUnwrap(shownCaption(document, at: 950))
        XCTAssertNil(content.wordPaint, "only the lit colour: nothing new to draw")
        XCTAssertEqual(content.highlight?.location, 12)
    }

    // MARK: - Glow, shadow and stroke

    func testWholeTextGlowStrokeAndShadowLandOnEveryCaption() throws {
        var look = CaptionLook.standard
        look.backgroundHex = nil
        look.glowHex = "#7FE7FF"
        look.strokeHex = "#000000"
        look.shadow = .deep
        let document = captioned(look: look)
        for cue in document.captionLayers {
            XCTAssertEqual(cue.style.effects.compactMap(\.glow).first?.colorHex, "#7FE7FF")
            XCTAssertEqual(cue.style.effects.compactMap(\.border).first?.colorHex, "#000000")
            XCTAssertNotNil(cue.style.shadow)
        }
        look.glowHex = nil
        look.strokeHex = nil
        look.shadow = CaptionShadow.none
        var off = document
        off.applyCaptionLook(look)
        XCTAssertTrue(off.captionLayers.allSatisfy { $0.style.effects.isEmpty }, "and off again")
    }

    func testTheCurrentWordsOwnGlowIsSeparateFromTheText() throws {
        var look = CaptionLook.standard
        look.word.glowHex = "#FFD76A"
        let document = captioned(look: look)
        XCTAssertTrue(document.captionLayers.allSatisfy { $0.style.effects.compactMap(\.glow).isEmpty },
                      "the text itself does not glow")
        let paint = try XCTUnwrap(shownCaption(document, at: 950)?.wordPaint)
        XCTAssertEqual(paint.glowHex, "#FFD76A")
    }

    // MARK: - Styles

    func testTheNamedStylesAreTheMocksThreeAndTwoMore() {
        XCTAssertEqual(CaptionLook.Preset.allCases.map(\.title),
                       ["Caption", "Lower third", "Karaoke", "Bold pop", "Neon"])
        XCTAssertEqual(CaptionLook.preset(.karaoke).coming, .dim, "the mock's karaoke: words to come at half white")
        XCTAssertEqual(CaptionLook.preset(.boldPop).word.motion, .growBounce)
        XCTAssertEqual(CaptionLook.preset(.boldPop).show, .threeWords)
        XCTAssertNotNil(CaptionLook.preset(.neon).glowHex)
        let looks = CaptionLook.Preset.allCases.map(CaptionLook.preset)
        XCTAssertEqual(Set(looks).count, looks.count, "every one looks different")
    }

    func testALookIsItsStyleWhateverFontItWears() {
        var look = CaptionLook.preset(.neon)
        look.fontName = "Menlo"
        look.fontSize = 72
        XCTAssertTrue(look.wears(.preset(.neon)))
        look.word.scale = 1.5
        XCTAssertFalse(look.wears(.preset(.neon)), "a tweak is no longer the style")
    }

    func testAnOldLookOpensAsItWas() throws {
        let old = ##"{"preset":"karaoke","fontName":"SF Pro","weight":"bold","colorHex":"#FFFFFF","activeHex":"#FFD76A","alignment":"center"}"##
        let look = try JSONDecoder().decode(CaptionLook.self, from: Data(old.utf8))
        XCTAssertEqual(look.show, .line)
        XCTAssertEqual(look.lines, 1)
        XCTAssertEqual(look.said, .lit, "an old karaoke look still lights what was sung")
        XCTAssertEqual(look.activeHex, "#FFD76A")
        XCTAssertEqual(look.word.motion, CaptionWordMotion.none)
        let plain = ##"{"preset":"caption","fontName":"SF Pro","weight":"semibold","colorHex":"#FFFFFF","alignment":"center"}"##
        XCTAssertEqual(try JSONDecoder().decode(CaptionLook.self, from: Data(plain.utf8)).said, .full)
    }

    func testANewLookRoundTrips() throws {
        var look = CaptionLook.preset(.boldPop)
        look.coming = .dim
        look.word.pillHex = "#FF7AB6"
        look.shadow = .soft
        let back = try JSONDecoder().decode(CaptionLook.self, from: JSONEncoder().encode(look))
        XCTAssertEqual(back, look)
    }

    func testAStyleOfYourOwnIsKeptUnderANameOfItsOwn() throws {
        var library = CaptionStyleLibrary()
        var mine = CaptionLook.preset(.neon)
        mine.word.scale = 1.5
        let first = library.save(mine)
        XCTAssertEqual(first.name, "My style")
        let second = library.save(.preset(.karaoke))
        XCTAssertEqual(second.name, "My style 2")
        XCTAssertEqual(library.styles.map(\.name), ["My style", "My style 2"])
        library.remove(id: first.id)
        XCTAssertEqual(library.styles.map(\.name), ["My style 2"])
        let back = try JSONDecoder().decode(CaptionStyleLibrary.self,
                                            from: JSONEncoder().encode(library))
        XCTAssertEqual(back, library)
    }
}

extension CaptionWordStyleTests {

    func testAStyleTilePlaysTheRealCaptionInThatStyle() throws {
        let look = CaptionLook.preset(.boldPop)
        let early = try XCTUnwrap(look.previewText(atMS: 100, fontSize: 14, width: 90))
        XCTAssertLessThanOrEqual(early.string.split(separator: " ").count, 3, "three words at a time")
        XCTAssertNotNil(early.wordPaint, "with its word popping")
        XCTAssertEqual(early.fontSize, 14)
        let later = try XCTUnwrap(look.previewText(atMS: 1_900, fontSize: 14, width: 90))
        XCTAssertNotEqual(later.string, early.string, "and moves on through the words")
        let lower = try XCTUnwrap(CaptionLook.preset(.lowerThird).previewText(atMS: 100, fontSize: 14, width: 90))
        XCTAssertEqual(lower.alignment, .left)
    }
}
