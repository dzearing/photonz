import CoreGraphics
import XCTest
@testable import PhotonzCore

// Fixing a caption one word at a time (`Sources/PhotonzCore/CaptionWordEdits.swift`,
// `docs/design/mocks/pages/video-captions.html`, the Words lane).
//
// The user's report, 2026-09-25: the captions misspelled some words, a double
// click on one word opened the whole caption, and the words on the Words lane
// could not be dragged or stretched. What is pinned here is the arithmetic
// under each fix: which characters of the line change, where the time goes
// when one word becomes two or two become one, how far a dragged word may go
// and what it carries with it, and that a fix survives the captions being
// written again.
final class CaptionWordEditTests: XCTestCase {

    private func word(_ text: String, _ startMS: Int, _ endMS: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: startMS, endMS: endMS, confidence: 0.9)
    }

    /// Two captions, side by side on one Captions track, with a gap between
    /// them: "Fodons opens alot" 1.0s to 2.5s, "the video captions" 3.0s to
    /// 4.6s, and a third, "done.", 6.0s to 7.0s.
    private func document() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        clip.time = LayerTime(inMS: 0, outMS: 10_000)
        document.addLayer(clip)
        document.landCaptions([
            CaptionCue(words: [word("Fodons", 1_000, 1_500), word("opens", 1_500, 1_900),
                               word("alot", 1_900, 2_400)], inMS: 1_000, outMS: 2_500),
            CaptionCue(words: [word("the", 3_000, 3_200), word("video", 3_200, 3_700),
                               word("captions", 3_700, 4_500)], inMS: 3_000, outMS: 4_600),
            CaptionCue(words: [word("done.", 6_000, 6_800)], inMS: 6_000, outMS: 7_000),
        ])
        return document
    }

    private func cue(_ document: PhotonzDocument, _ index: Int) -> Layer {
        document.captionLayers[index]
    }

    private func ref(_ document: PhotonzDocument, _ cue: Int, _ word: Int) -> CaptionWordRef {
        CaptionWordRef(cueID: document.captionLayers[cue].id, index: word)
    }

    private func text(_ layer: Layer) -> String {
        guard case .text(let content) = layer.content else { return "" }
        return content.string
    }

    private func words(_ document: PhotonzDocument, _ cue: Int) -> [TranscribedWord] {
        document.captionWordsAsShown(of: document.captionLayers[cue].id) ?? []
    }

    private func spans(_ words: [TranscribedWord]) -> [[Int]] {
        words.map { [$0.startMS, $0.endMS] }
    }

    // MARK: - One word, retyped

    func testRetypingOneWordChangesOnlyThatWordAndKeepsItsTime() {
        var document = document()
        let before = cue(document, 0)
        XCTAssertTrue(document.setCaptionWord(ref(document, 0, 0), to: "Photonz"))
        let after = cue(document, 0)
        XCTAssertEqual(text(after), "Photonz opens alot")
        XCTAssertEqual(spans(words(document, 0)), [[1_000, 1_500], [1_500, 1_900], [1_900, 2_400]])
        XCTAssertEqual(after.time, before.time)
        XCTAssertEqual(after.frame, before.frame, "a word fix never reflows the caption's box")
        XCTAssertEqual(after.name, "Photonz opens alot", "the bar says what is on screen")
    }

    func testAFixedWordIsNoLongerMarkedUnsure() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        document.landCaptions([CaptionCue(words: [TranscribedWord("Fodons", startMS: 0, endMS: 500,
                                                                  confidence: 0.1)],
                                          inMS: 0, outMS: 600)])
        XCTAssertTrue(document.captionCues[0].isUncertain)
        XCTAssertTrue(document.setCaptionWord(ref(document, 0, 0), to: "Photonz"))
        XCTAssertFalse(document.captionCues[0].isUncertain)
    }

    func testRetypingKeepsTheRestOfTheLineByteForByte() {
        var document = document()
        let id = cue(document, 1).id
        // Somebody broke the line by hand; a word fix must not undo that.
        XCTAssertTrue(document.setCaptionText(id: id, to: "the video\ncaptions"))
        XCTAssertTrue(document.setCaptionWord(CaptionWordRef(cueID: id, index: 1), to: "movie"))
        XCTAssertEqual(text(cue(document, 1)), "the movie\ncaptions")
    }

    func testTypingTheSameWordChangesNothing() {
        var document = document()
        XCTAssertFalse(document.setCaptionWord(ref(document, 0, 1), to: "opens"))
        XCTAssertFalse(document.setCaptionWord(ref(document, 0, 1), to: "  opens "))
    }

    func testRetypingAWordAsTwoSplitsItsTimeEvenly() {
        var document = document()
        XCTAssertTrue(document.setCaptionWord(ref(document, 0, 2), to: "a lot"))
        XCTAssertEqual(text(cue(document, 0)), "Fodons opens a lot")
        XCTAssertEqual(spans(words(document, 0)),
                       [[1_000, 1_500], [1_500, 1_900], [1_900, 2_150], [2_150, 2_400]])
    }

    func testRetypingAWordAsNothingDeletesIt() {
        var document = document()
        XCTAssertTrue(document.setCaptionWord(ref(document, 0, 1), to: "   "))
        XCTAssertEqual(text(cue(document, 0)), "Fodons alot")
        XCTAssertEqual(spans(words(document, 0)), [[1_000, 1_500], [1_900, 2_400]])
    }

    func testAWordOutOfRangeIsRefused() {
        var document = document()
        XCTAssertFalse(document.setCaptionWord(ref(document, 0, 9), to: "x"))
        XCTAssertFalse(document.setCaptionWord(CaptionWordRef(cueID: UUID(), index: 0), to: "x"))
    }

    // MARK: - Split, merge, delete

    func testSplitHereCutsTheWordAtTheMomentAndTheLettersInProportion() {
        var document = document()
        // "alot" runs 1900 to 2400; a quarter of the way in is "a" | "lot".
        XCTAssertTrue(document.splitCaptionWord(ref(document, 0, 2), atMS: 2_025))
        XCTAssertEqual(text(cue(document, 0)), "Fodons opens a lot")
        XCTAssertEqual(spans(words(document, 0)).suffix(2), [[1_900, 2_025], [2_025, 2_400]])
    }

    func testSplitWithNoMomentCutsInTheMiddle() {
        var document = document()
        XCTAssertTrue(document.splitCaptionWord(ref(document, 1, 1), atMS: nil))
        XCTAssertEqual(text(cue(document, 1)), "the vid eo captions")
        XCTAssertEqual(spans(words(document, 1))[1...2], [[3_200, 3_450], [3_450, 3_700]])
    }

    func testAOneLetterWordCannotBeSplit() {
        var document = document()
        XCTAssertTrue(document.setCaptionWord(ref(document, 0, 2), to: "a"))
        XCTAssertFalse(document.splitCaptionWord(ref(document, 0, 2), atMS: nil))
    }

    func testMergeWithNextJoinsTheLettersAndTheTime() {
        var document = document()
        XCTAssertTrue(document.setCaptionWord(ref(document, 0, 2), to: "a lot"))
        XCTAssertTrue(document.mergeCaptionWordWithNext(ref(document, 0, 2)))
        XCTAssertEqual(text(cue(document, 0)), "Fodons opens alot")
        XCTAssertEqual(spans(words(document, 0)).last, [1_900, 2_400])
        XCTAssertFalse(document.mergeCaptionWordWithNext(ref(document, 0, 2)),
                       "the last word of a line has nothing after it to merge with")
    }

    func testDeletingTheOnlyWordTakesTheCaptionOff() {
        var document = document()
        let id = cue(document, 2).id
        XCTAssertTrue(document.deleteCaptionWord(ref(document, 2, 0)))
        XCTAssertNil(document.layer(id: id))
        XCTAssertEqual(document.captionLayers.count, 2)
    }

    // MARK: - Move to the next line

    func testMoveToNextLineCarriesTheWordAndTheOnesAfterIt() {
        var document = document()
        XCTAssertTrue(document.moveCaptionWordsToNextCue(from: ref(document, 0, 1)))
        XCTAssertEqual(text(cue(document, 0)), "Fodons")
        XCTAssertEqual(text(cue(document, 1)), "opens alot the video captions")
        XCTAssertEqual(cue(document, 0).time?.outMS, 1_500, "the line ends where its words were taken from")
        XCTAssertEqual(cue(document, 1).time?.inMS, 1_500, "the next line starts where they begin")
        XCTAssertEqual(spans(words(document, 1)).prefix(3), [[1_500, 1_900], [1_900, 2_400], [3_000, 3_200]])
    }

    func testMovingTheFirstWordMovesTheWholeLineIntoTheNext() {
        var document = document()
        let id = cue(document, 0).id
        XCTAssertTrue(document.moveCaptionWordsToNextCue(from: ref(document, 0, 0)))
        XCTAssertNil(document.layer(id: id))
        XCTAssertEqual(text(cue(document, 0)), "Fodons opens alot the video captions")
    }

    func testMoveToNextLineOnTheLastLineMakesANewLine() {
        var document = document()
        document.setCaptionWord(ref(document, 2, 0), to: "all done.")
        XCTAssertTrue(document.moveCaptionWordsToNextCue(from: ref(document, 2, 1)))
        XCTAssertEqual(document.captionLayers.count, 4)
        XCTAssertEqual(text(cue(document, 2)), "all")
        XCTAssertEqual(text(cue(document, 3)), "done.")
        XCTAssertEqual(cue(document, 3).time?.inMS, 6_400)
        XCTAssertEqual(cue(document, 3).time?.outMS, 7_000)
        XCTAssertEqual(document.parentID(of: cue(document, 3).id), document.parentID(of: cue(document, 2).id),
                       "the new line sits on the same Captions track")
    }

    // MARK: - Dragging a word

    func testAPlainDragCarriesTheRestOfTheLineAndKeepsTheirSpacing() {
        var document = document()
        // "video" 200 ms later: "video" and "captions" move, "the" stays.
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .carryRest, byMS: 200), 200)
        XCTAssertEqual(spans(words(document, 1)), [[3_000, 3_200], [3_400, 3_900], [3_900, 4_700]])
        XCTAssertEqual(cue(document, 1).time?.inMS, 3_000)
        XCTAssertEqual(cue(document, 1).time?.outMS, 4_800, "the line's tail moves with its last word")
    }

    func testDraggingTheFirstWordMovesTheWholeLine() {
        var document = document()
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 0), grab: .carryRest, byMS: -300), -300)
        XCTAssertEqual(cue(document, 1).time, LayerTime(inMS: 2_700, outMS: 4_300))
        XCTAssertEqual(spans(words(document, 1)).first, [2_700, 2_900])
    }

    func testAPlainDragEarlierSqueezesTheWordBefore() {
        var document = document()
        // Spoken words sit end to end, so "video" carried earlier takes the
        // time from the end of "the", which keeps a sliver of it.
        XCTAssertEqual(document.captionWordDragRange(ref(document, 1, 1), grab: .carryRest),
                       -160...1_500, "later it may go until its last word meets the next line's first")
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .carryRest, byMS: -500), -160)
        XCTAssertEqual(spans(words(document, 1)), [[3_000, 3_040], [3_040, 3_540], [3_540, 4_340]])
    }

    func testACommandDragEarlierStopsAtTheWordBefore() {
        var document = document()
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .alone, byMS: -500), 0)
    }

    func testDraggingIntoTheNextLineRollsTheBoundaryNotTheWords() {
        var document = document()
        // The line's last word may run up to the next line's first word; the
        // next line gives up the start it no longer needs.
        XCTAssertEqual(document.dragCaptionWord(ref(document, 0, 0), grab: .carryRest, byMS: 5_000), 600)
        XCTAssertEqual(cue(document, 0).time?.outMS, 3_000)
        XCTAssertEqual(cue(document, 1).time?.inMS, 3_000)
        XCTAssertEqual(spans(words(document, 0)).last, [2_500, 3_000])
    }

    func testDraggingBackIntoTheLineBeforeRollsItsEnd() {
        var document = document()
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 0), grab: .carryRest, byMS: -5_000), -600)
        XCTAssertEqual(cue(document, 1).time?.inMS, 2_400)
        XCTAssertEqual(cue(document, 0).time?.outMS, 2_400, "the line before ends where its last word does")
    }

    func testAShiftDragCarriesEveryLaterLineToo() {
        var document = document()
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .carryTrack, byMS: 2_000), 2_000)
        XCTAssertEqual(spans(words(document, 1)), [[3_000, 3_200], [5_200, 5_700], [5_700, 6_500]])
        XCTAssertEqual(cue(document, 2).time, LayerTime(inMS: 8_000, outMS: 9_000))
        XCTAssertEqual(spans(words(document, 2)), [[8_000, 8_800]])
        XCTAssertEqual(cue(document, 0).time, LayerTime(inMS: 1_000, outMS: 2_500), "earlier lines stay put")
    }

    func testAShiftDragStopsAtTheEndOfTheFilm() {
        var document = document()
        document.durationMS = 10_000
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .carryTrack, byMS: 9_000), 3_000)
    }

    func testACommandDragMovesOneWordAloneBetweenItsNeighbours() {
        var document = document()
        // Open a gap after "video" so it has room.
        document.dragCaptionWord(ref(document, 1, 2), grab: .carryRest, byMS: 100)
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .alone, byMS: 400), 100)
        XCTAssertEqual(spans(words(document, 1)), [[3_000, 3_200], [3_300, 3_800], [3_800, 4_600]])
    }

    func testDraggingAnEdgeResizesOnlyThatWord() {
        var document = document()
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 2), grab: .end, byMS: 50), 50)
        XCTAssertEqual(spans(words(document, 1)), [[3_000, 3_200], [3_200, 3_700], [3_700, 4_550]])
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .start, byMS: 200), 200)
        XCTAssertEqual(spans(words(document, 1))[1], [3_400, 3_700])
        // An edge never passes the word next to it, nor makes a word vanish.
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .start, byMS: 5_000),
                       300 - CaptionWordEdits.shortestWordMS)
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 0), grab: .end, byMS: 5_000), 460,
                       "the end of 'the' stops where 'video' now starts")
    }

    func testAnEdgeDraggedPastTheLinesEndGrowsTheLine() {
        var document = document()
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 2), grab: .end, byMS: 300), 300)
        XCTAssertEqual(cue(document, 1).time?.outMS, 4_800)
    }

    func testADragThatGoesNowhereChangesNothing() {
        var document = document()
        let before = document
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 1), grab: .carryRest, byMS: 0), 0)
        XCTAssertEqual(document, before)
    }

    func testAMovedCaptionBarCarriesItsWordsBeforeTheyAreDragged() {
        // A bar dragged by hand leaves its words where they were heard; the
        // lane shows them fitted to the bar, and a drag starts from there.
        var document = document()
        let id = cue(document, 1).id
        document.updateLayer(id: id) { $0.time = LayerTime(inMS: 3_500, outMS: 5_000) }
        XCTAssertEqual(spans(words(document, 1)).first, [3_500, 3_700])
        XCTAssertEqual(document.dragCaptionWord(ref(document, 1, 0), grab: .carryRest, byMS: 100), 100)
        XCTAssertEqual(spans(words(document, 1)).first, [3_600, 3_800])
    }

    // MARK: - Snapping

    func testASnapPullsTheNearestEdgeOntoATarget() {
        XCTAssertEqual(CaptionWordSnap.snapped(deltaMS: 190, edges: [1_000, 1_500], targets: [1_700],
                                               withinMS: 20), 200)
        XCTAssertEqual(CaptionWordSnap.snapped(deltaMS: 150, edges: [1_000, 1_500], targets: [1_700],
                                               withinMS: 20), 150, "too far to snap")
        XCTAssertEqual(CaptionWordSnap.snapped(deltaMS: -95, edges: [1_000], targets: [890, 910],
                                               withinMS: 20), -90, "the nearest target wins")
    }

    // MARK: - Which word a click is on

    func testAClickFindsTheWordUnderItOrTheNearestOnItsLine() {
        let rects: [CGRect?] = [CGRect(x: 0, y: 0, width: 40, height: 20),
                                CGRect(x: 50, y: 0, width: 60, height: 20),
                                nil,
                                CGRect(x: 0, y: 30, width: 40, height: 20)]
        XCTAssertEqual(CaptionWordHit.index(at: CGPoint(x: 60, y: 10), in: rects, slack: 6), 1)
        XCTAssertEqual(CaptionWordHit.index(at: CGPoint(x: 43, y: 10), in: rects, slack: 6), 0,
                       "the gap between two words goes to the nearer")
        XCTAssertEqual(CaptionWordHit.index(at: CGPoint(x: 10, y: 40), in: rects, slack: 6), 3)
        XCTAssertNil(CaptionWordHit.index(at: CGPoint(x: 200, y: 10), in: rects, slack: 6))
        XCTAssertNil(CaptionWordHit.index(at: CGPoint(x: 10, y: 25), in: rects, slack: 6),
                     "between two lines is on no word")
    }

    // MARK: - Stepping word to word

    func testTabSteppingRunsAcrossLines() {
        let document = document()
        XCTAssertEqual(document.captionWord(from: ref(document, 0, 1), step: 1), ref(document, 0, 2))
        XCTAssertEqual(document.captionWord(from: ref(document, 0, 2), step: 1), ref(document, 1, 0))
        XCTAssertEqual(document.captionWord(from: ref(document, 1, 0), step: -1), ref(document, 0, 2))
        XCTAssertNil(document.captionWord(from: ref(document, 0, 0), step: -1))
        XCTAssertNil(document.captionWord(from: ref(document, 2, 0), step: 1))
    }

    // MARK: - A fix survives the captions being written again

    func testAFixedWordComesBackWhenTheSameWordIsHeardAgain() {
        var document = document()
        document.setCaptionWord(ref(document, 0, 0), to: "Photonz")
        document.setCaptionWord(ref(document, 0, 2), to: "a lot")
        // Written again: the recogniser mishears the same words the same way,
        // a few milliseconds off where it did before.
        document.landCaptions([
            CaptionCue(words: [word("Fodons", 1_020, 1_480), word("opens", 1_480, 1_900),
                               word("alot", 1_910, 2_400)], inMS: 1_000, outMS: 2_500),
            CaptionCue(words: [word("the", 3_000, 3_200), word("video", 3_200, 3_700)],
                       inMS: 3_000, outMS: 3_800),
        ])
        XCTAssertEqual(text(cue(document, 0)), "Photonz opens a lot")
        XCTAssertEqual(words(document, 0).count, 4)
        XCTAssertEqual(text(cue(document, 1)), "the video", "words nobody fixed are as heard")
    }

    func testAFixDoesNotLandOnADifferentWordSaidElsewhere() {
        var document = document()
        document.setCaptionWord(ref(document, 0, 0), to: "Photonz")
        document.landCaptions([
            CaptionCue(words: [word("Fodons", 6_000, 6_500)], inMS: 6_000, outMS: 6_600),
            CaptionCue(words: [word("Hello", 1_000, 1_500)], inMS: 1_000, outMS: 1_600),
        ])
        XCTAssertEqual(document.captionCues.map(\.text), ["Hello", "Fodons"])
    }

    func testTheHeardWordRidesAlongThroughSaveAndLoad() throws {
        var document = document()
        document.setCaptionWord(ref(document, 0, 0), to: "Photonz")
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        XCTAssertEqual(back.captionLayers[0].captionWords?.first?.heardAs, "Fodons")
    }

    func testAWordSavedBeforeFixesExistedStillOpens() throws {
        let old = #"{"text":"hello","startMS":0,"endMS":100}"#
        let decoded = try JSONDecoder().decode(TranscribedWord.self, from: Data(old.utf8))
        XCTAssertNil(decoded.heardAs)
    }
}
