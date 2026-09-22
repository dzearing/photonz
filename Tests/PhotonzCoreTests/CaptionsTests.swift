import CoreGraphics
import XCTest
@testable import PhotonzCore

// Captions: the arithmetic that decides whether an automatic caption is usable
// (`Sources/PhotonzCore/Captions.swift`).
//
// Nothing here listens to anything. What is pinned is the three places a
// caption feature actually goes wrong: the joins between pieces of a long
// recording, where the lines break, and whether correcting one costs the
// timings.
final class CaptionsTests: XCTestCase {

    private func word(_ text: String, _ startMS: Int, _ endMS: Int,
                      confidence: Double? = nil) -> TranscribedWord {
        TranscribedWord(text, startMS: startMS, endMS: endMS, confidence: confidence)
    }

    // MARK: - Where the pieces join

    func testSeamKeepsAnOverlappingPhraseExactlyOnce() {
        // The last three words of one piece are the first three of the next,
        // because the pieces were cut to overlap.
        let kept = [word("open", 0, 300), word("a", 300, 400), word("screen", 400, 700),
                    word("recording", 700, 1200)]
        let next = [word("a", 300, 400), word("screen", 400, 700), word("recording", 700, 1200),
                    word("and", 1200, 1400), word("cut", 1400, 1700)]
        let joined = TranscriptSeam.joined(kept, with: next)
        XCTAssertEqual(joined.map(\.text), ["open", "a", "screen", "recording", "and", "cut"])
        XCTAssertEqual(joined.map(\.startMS), [0, 300, 400, 700, 1200, 1400])
    }

    func testSeamMatchesThroughPunctuationAndCase() {
        // The same words heard twice do not come back spelled the same: one
        // piece ends a sentence the other carries on.
        let kept = [word("is", 0, 200), word("a", 200, 300), word("Recording.", 300, 900)]
        let next = [word("is", 0, 200), word("A", 200, 300), word("recording", 300, 900),
                    word("you", 900, 1100)]
        let joined = TranscriptSeam.joined(kept, with: next)
        XCTAssertEqual(joined.map(\.text), ["is", "a", "Recording.", "you"])
    }

    func testSeamLosesNothingWhenTheTwoPiecesDisagreeOutright() {
        // A join where the recogniser heard the overlap completely differently
        // must still not double anything or reorder anything.
        let kept = [word("the", 0, 200), word("timeline", 200, 800)]
        let next = [word("thin", 200, 400), word("line", 400, 800),
                    word("dock", 900, 1300)]
        let joined = TranscriptSeam.joined(kept, with: next)
        XCTAssertEqual(joined.map(\.text), ["the", "timeline", "dock"])
        XCTAssertEqual(joined.map(\.startMS).sorted(), joined.map(\.startMS))
    }

    func testSeamWithNoOverlapAtAllSimplyMeets() {
        let kept = [word("one", 0, 400)]
        let next = [word("two", 500, 900)]
        XCTAssertEqual(TranscriptSeam.joined(kept, with: next).map(\.text), ["one", "two"])
    }

    func testAWholeRecordingStitchedFromOverlappingPiecesReadsBackWordForWord() {
        // The real shape of the thing: one sentence heard in four overlapping
        // pieces, each returned on its own clock and offset back.
        let said = (0..<60).map { word("w\($0)", $0 * 500, $0 * 500 + 400) }
        let window = ChunkWindow(targetMS: 8_000, slackMS: 1_000, overlapMS: 3_000)
        let chunks = TranscriptChunks.plan(durationMS: 30_000, window: window)
        XCTAssertGreaterThan(chunks.count, 2, "a 30s recording at 8s a piece is several pieces")

        var stitched: [TranscribedWord] = []
        for chunk in chunks {
            // What a recogniser handed this piece would return: its own clock,
            // starting at nought.
            let heard = said
                .filter { $0.startMS >= chunk.startMS && $0.endMS <= chunk.endMS }
                .map { $0.shifted(byMS: -chunk.startMS) }
            // ...put straight back on the recording's clock, which is the step
            // an off-by-one-chunk error hides in.
            stitched = TranscriptSeam.joined(stitched, with: heard.map { $0.shifted(byMS: chunk.startMS) })
        }
        XCTAssertEqual(stitched.map(\.text), said.map(\.text))
        XCTAssertEqual(stitched.map(\.startMS), said.map(\.startMS),
                       "timings stay absolute across every seam, including the last")
    }

    // MARK: - Cutting a recording into pieces

    func testAShortRecordingIsOnePiece() {
        XCTAssertEqual(TranscriptChunks.plan(durationMS: 30_000).count, 1)
    }

    func testPiecesCoverTheWholeRecordingWithNoGap() {
        let chunks = TranscriptChunks.plan(durationMS: 2_526_000)
        XCTAssertGreaterThan(chunks.count, 10, "42 minutes is many pieces")
        XCTAssertEqual(chunks.first?.startMS, 0)
        XCTAssertEqual(chunks.last?.endMS, 2_526_000)
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            XCTAssertLessThanOrEqual(b.startMS, a.endMS, "no gap between pieces")
        }
    }

    func testACutLandsInASilenceWhenThereIsOneNearby() {
        let window = ChunkWindow(targetMS: 10_000, slackMS: 2_000, overlapMS: 3_000)
        let chunks = TranscriptChunks.plan(durationMS: 60_000, quietMS: [11_200], window: window)
        XCTAssertEqual(chunks.first?.endMS, 11_200)
        XCTAssertEqual(chunks[1].startMS, 11_200, "a cut in a silence needs no overlap")
    }

    func testACutInTheMiddleOfSpeechOverlapsSoNoWordIsLost() {
        let window = ChunkWindow(targetMS: 10_000, slackMS: 500, overlapMS: 3_000)
        let chunks = TranscriptChunks.plan(durationMS: 60_000, window: window)
        XCTAssertEqual(chunks.first?.endMS, 10_000)
        XCTAssertEqual(chunks[1].startMS, 7_000)
    }

    // MARK: - Lines

    func testALineBreaksAtAFullStop() {
        let words = [word("Open", 0, 300), word("a", 300, 400), word("recording.", 400, 900),
                     word("It", 1000, 1200), word("has", 1200, 1400), word("time.", 1400, 1900)]
        let cues = CaptionCues.cues(from: words)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Open a recording.")
        XCTAssertEqual(cues[1].text, "It has time.")
    }

    func testALineBreaksWhenSomebodyStoppedTalking() {
        let words = [word("first", 0, 400), word("thought", 400, 900),
                     word("second", 4_000, 4_400), word("thought", 4_400, 4_900)]
        XCTAssertEqual(CaptionCues.cues(from: words).count, 2)
    }

    func testALineBreaksBeforeItGetsTooWideToRead() {
        let words = (0..<20).map { word("word\($0)", $0 * 200, $0 * 200 + 150) }
        let cues = CaptionCues.cues(from: words)
        XCTAssertGreaterThan(cues.count, 1)
        for cue in cues {
            XCTAssertLessThanOrEqual(cue.text.count, CaptionCueRule().maxCharacters)
        }
    }

    func testEveryWordEndsUpInExactlyOneLine() {
        let words = (0..<200).map { word("w\($0)", $0 * 300, $0 * 300 + 250) }
        let cues = CaptionCues.cues(from: words)
        XCTAssertEqual(cues.flatMap { $0.words }.map(\.text), words.map(\.text))
    }

    func testAShortLineIsHeldLongEnoughToReadButNeverIntoTheNext() {
        let words = [word("Yes.", 0, 200), word("Now", 1_000, 1_300), word("watch.", 1_300, 1_900)]
        let cues = CaptionCues.cues(from: words)
        XCTAssertEqual(cues.count, 2)
        XCTAssertLessThanOrEqual(cues[0].outMS, cues[1].inMS,
                                 "two captions on screen at once is worse than one that went early")
    }

    func testNoLineIsEverOnScreenWhileTheNextOneIs() {
        // Continuous speech: every word starts the instant the last one ended,
        // so a line that lingers after its last word lingers over the line
        // after it. Found by the walk on real speech, at 2160ms.
        let words = (0..<40).map { word("word\($0)\($0 % 7 == 6 ? "." : "")",
                                        $0 * 300, $0 * 300 + 300) }
        let cues = CaptionCues.cues(from: words)
        XCTAssertGreaterThan(cues.count, 3)
        for (a, b) in zip(cues, cues.dropFirst()) {
            XCTAssertLessThanOrEqual(a.outMS, b.inMS,
                                     "a caption at \(a.inMS) runs to \(a.outMS), past \(b.inMS)")
        }
    }

    func testALineIsNeverShorterThanTheShortestStretchTheModelAllows() {
        let cues = CaptionCues.cues(from: [word("Hm.", 0, 40)])
        XCTAssertGreaterThanOrEqual(cues[0].lengthMS, LayerTime.shortestMS)
    }

    // MARK: - A caption is a text layer

    private func documentWithCaptions() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        let cues = CaptionCues.cues(from: [
            word("Photonz", 500, 1100, confidence: 0.2),
            word("opens", 1100, 1400, confidence: 0.9),
            word("a", 1400, 1500, confidence: 0.9),
            word("recording.", 1500, 2100, confidence: 0.9),
        ])
        for layer in CaptionLayers.layers(for: cues, in: document.canvasSize) {
            document.addLayer(layer)
        }
        return document
    }

    func testACaptionIsATextLayerWithAnInAndAnOut() {
        let document = documentWithCaptions()
        let caption = document.captionLayers[0]
        guard case .text(let content) = caption.content else {
            return XCTFail("a caption is a text layer, nothing else special")
        }
        XCTAssertEqual(content.string, "Photonz opens a recording.")
        XCTAssertEqual(caption.time?.inMS, 500)
        XCTAssertNotNil(caption.time?.outMS)
        XCTAssertTrue(caption.isPlacedInTime, "placed in time, not played")
    }

    func testACaptionSitsInsideTheTitleSafeAreaAndCarriesTheReadableShadow() {
        let document = documentWithCaptions()
        let caption = document.captionLayers[0]
        let size = document.canvasSize
        XCTAssertGreaterThanOrEqual(caption.frame.minX, size.width * CaptionLayers.titleSafeInset - 0.5)
        XCTAssertLessThanOrEqual(caption.frame.maxY, size.height * (1 - CaptionLayers.titleSafeInset) + 0.5)
        XCTAssertNotNil(caption.style.shadow, "the same shadow every text layer gets over a picture")
    }

    func testCorrectingTheWordsKeepsTheTimings() {
        var document = documentWithCaptions()
        let id = document.captionLayers[0].id
        let before = document.captionCues[0]
        document.updateLayer(id: id) { layer in
            guard case .text(var content) = layer.content else { return }
            content.string = "Photonz opens a recording."
                .replacingOccurrences(of: "Photonz", with: "Photons")
            layer.content = .text(content)
        }
        let after = document.captionCues[0]
        XCTAssertEqual(after.inMS, before.inMS)
        XCTAssertEqual(after.outMS, before.outMS)
        XCTAssertEqual(after.words.map(\.startMS), before.words.map(\.startMS),
                       "a correction does not throw the word timings away")
        XCTAssertEqual(after.words[0].text, "Photons")
    }

    func testAWordTheMachineWasNotSureOfIsMarkedRatherThanPassedOff() {
        let document = documentWithCaptions()
        XCTAssertTrue(document.captionCues[0].isUncertain)
        XCTAssertTrue(document.captionCues[0].words[0].isUncertain)
        XCTAssertFalse(document.captionCues[0].words[1].isUncertain)
    }

    func testCorrectingAnUncertainWordClearsTheDoubtAboutIt() {
        var document = documentWithCaptions()
        let id = document.captionLayers[0].id
        document.updateLayer(id: id) { layer in
            guard case .text(var content) = layer.content else { return }
            content.string = "Photons opens a recording."
            layer.content = .text(content)
        }
        XCTAssertNil(document.captionCues[0].words[0].confidence,
                     "a word somebody typed is nobody's guess")
    }

    func testNudgingTheWholeTrackMovesEveryCaptionAndItsWords() {
        var document = documentWithCaptions()
        let before = document.captionCues
        document.shiftCaptions(byMS: 250)
        let after = document.captionCues
        XCTAssertEqual(after.map(\.inMS), before.map { $0.inMS + 250 })
        XCTAssertEqual(after[0].words[0].startMS, before[0].words[0].startMS + 250)
    }

    func testNudgingBackwardsNeverPushesACaptionOffTheFrontOfTheRecording() {
        var document = documentWithCaptions()
        document.shiftCaptions(byMS: -5_000)
        XCTAssertEqual(document.captionLayers.first?.time?.inMS, 0)
        XCTAssertGreaterThan(document.captionCues[0].outMS, 0, "the track keeps its shape")
    }

    func testClearingCaptionsLeavesEverythingElseWhereItWas() {
        var document = documentWithCaptions()
        document.addLayer(Layer(name: "Title", content: .text(TextContent(string: "Hello")),
                                frame: CGRect(x: 0, y: 0, width: 100, height: 40)))
        document.clearCaptions()
        XCTAssertFalse(document.hasCaptions)
        XCTAssertEqual(document.allLayers.map(\.name), ["Title"])
    }

    func testACaptionSurvivesBeingSavedAndOpenedAgain() throws {
        let document = documentWithCaptions()
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        XCTAssertEqual(back.captionCues.map(\.text), document.captionCues.map(\.text))
        XCTAssertEqual(back.captionCues[0].words.map(\.startMS),
                       document.captionCues[0].words.map(\.startMS))
    }

    func testADocumentWithoutCaptionsWritesNothingAboutThem() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        document.addLayer(Layer(name: "Box", content: .text(TextContent(string: "x")),
                                frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let json = String(data: try JSONEncoder().encode(document), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("caption"),
                       "a document written before captions existed reads back byte for byte the same")
    }

    // MARK: - The way out that is not a picture

    func testSubtitlesComeOutInTheFormEverythingReads() {
        let cues = [CaptionCue(words: [], inMS: 1_500, outMS: 3_200),
                    CaptionCue(words: [], inMS: 3_700_000, outMS: 3_702_000)]
        let text = CaptionsSRT.text([
            CaptionCue(words: [TranscribedWord("Hello", startMS: 1_500, endMS: 3_200)],
                       inMS: cues[0].inMS, outMS: cues[0].outMS),
            CaptionCue(words: [TranscribedWord("there", startMS: 3_700_000, endMS: 3_702_000)],
                       inMS: cues[1].inMS, outMS: cues[1].outMS),
        ])
        XCTAssertTrue(text.hasPrefix("1\n00:00:01,500 --> 00:00:03,200\nHello\n"), text)
        XCTAssertTrue(text.contains("2\n01:01:40,000 --> 01:01:42,000\nthere\n"), text)
    }

    // MARK: - What it says while it works

    func testProgressSaysHowFarAlongInMinutesRatherThanPercent() {
        XCTAssertEqual(CaptionProgress.reading(doneMS: 250_000, ofMS: 2_526_000, words: 612),
                       "Listening · 4:10 of 42:06 · 612 words so far")
        XCTAssertEqual(CaptionProgress.share(doneMS: 0, ofMS: 1_000), 0)
        XCTAssertEqual(CaptionProgress.share(doneMS: 2_000, ofMS: 1_000), 1)
    }

    func testStoppingPartWaySaysWhatItKept() {
        XCTAssertEqual(CaptionProgress.stopped(doneMS: 60_000, ofMS: 600_000, words: 210),
                       "Stopped at 1:00 of 10:00. 210 words kept.")
        XCTAssertEqual(CaptionProgress.stopped(doneMS: 0, ofMS: 600_000, words: 0),
                       "Stopped before anything was heard.")
    }

    func testHearingNothingSaysSoRatherThanLeavingAnEmptyTrack() {
        XCTAssertEqual(CaptionProgress.heard(words: 0, cues: 0, ofMS: 60_000),
                       Captions.heardNothing)
        XCTAssertEqual(CaptionProgress.heard(words: 1, cues: 1, ofMS: 60_000),
                       "1 word in 1 caption, from 1:00 of sound")
    }
}
