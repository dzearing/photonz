import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Export keeps to the In and Out marks** (`VideoExportRange.swift`).
///
/// Premiere's Export writes Source In/Out when the marks are set, and Entire
/// Source when asked. Here the file starts at the In and runs to the Out, the
/// frames are exactly the window's frames over that stretch, and the sound and
/// a subtitle file beside the film start at the In with it.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Export keeps to the In and Out marks")
struct VideoExportRangeTests {

    static func talk(durationMS: Int = 10_000) -> PhotonzDocument {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 720),
                             durationMS: durationMS, hasSound: true)
        return .recording(movie, name: "Talk")
    }

    // MARK: - Which stretch

    @Test func withNoMarksBothChoicesWriteTheWholeDocument() {
        let doc = Self.talk()
        #expect(doc.exportRangeMS(.marked) == 0..<10_000)
        #expect(doc.exportRangeMS(.whole) == 0..<10_000)
        #expect(!doc.offersMarkedExport)
    }

    @Test func withBothMarksSetTheMarkedChoiceWritesInToOut() {
        var doc = Self.talk()
        doc.setMarkIn(atMS: 2000)
        doc.setMarkOut(atMS: 6000)
        #expect(doc.offersMarkedExport)
        #expect(doc.exportRangeMS(.marked) == 2000..<6000)
        #expect(doc.exportRangeMS(.whole) == 0..<10_000)
    }

    @Test func anInAloneRunsToTheEndAndAnOutAloneRunsFromTheStart() {
        var doc = Self.talk()
        doc.setMarkIn(atMS: 3000)
        #expect(doc.exportRangeMS(.marked) == 3000..<10_000)
        doc.clearMarkInOut()
        doc.setMarkOut(atMS: 4000)
        #expect(doc.exportRangeMS(.marked) == 0..<4000)
    }

    @Test func marksAroundTheWholeDocumentOfferNothingToChoose() {
        // An In at the start and an Out at the end is the whole video: a row
        // offering the whole video instead would offer the same file twice.
        var doc = Self.talk()
        doc.setMarkIn(atMS: 0)
        doc.setMarkOut(atMS: 10_000)
        #expect(!doc.offersMarkedExport)
    }

    // MARK: - The pictures

    @Test func thePlanForAStretchPhotographsFromTheInAndRunsAsLongAsTheStretch() {
        let plan = DocumentVideoExport.plan(range: 2000..<6000,
                                            canvasSize: CGSize(width: 1280, height: 720),
                                            format: .mp4, quality: .standard)
        #expect(plan.durationMS == 4000)
        #expect(plan.startMS == 2000)
        // The file's own clock starts at nought...
        #expect(plan.timeMS(at: 0) == 0)
        // ...and each of its pictures is the document's at the In plus that.
        #expect(plan.documentTimeMS(at: 0) == 2000)
        #expect(plan.documentTimeMS(at: 1) == 2033)
        for index in 0..<plan.frameCount {
            #expect(plan.documentTimeMS(at: index) >= 2000)
            #expect(plan.documentTimeMS(at: index) < 6000)
        }
    }

    @Test func aPlanForTheWholeDocumentIsTheOneItAlwaysWas() {
        let whole = DocumentVideoExport.plan(range: 0..<3000,
                                             canvasSize: CGSize(width: 640, height: 480),
                                             format: .mp4, quality: .standard)
        let before = DocumentVideoExport.plan(durationMS: 3000,
                                              canvasSize: CGSize(width: 640, height: 480),
                                              format: .mp4, quality: .standard)
        #expect(whole == before)
        #expect(whole.documentTimeMS(at: 5) == whole.timeMS(at: 5))
    }

    // MARK: - The sound

    static func segment(startMS: Int, lengthMS: Int, sourceInMS: Int = 0,
                        speedPercent: Int = 100,
                        ramps: [AudioGainRamp]? = nil) -> AudioMixSegment {
        let sound = SoundRef(durationMS: 60_000)
        let sourceLength = lengthMS * speedPercent / 100
        return AudioMixSegment(layerID: UUID(), sound: sound, startMS: startMS, lengthMS: lengthMS,
                               sourceInMS: sourceInMS, sourceLengthMS: sourceLength,
                               speedPercent: speedPercent,
                               ramps: ramps ?? [AudioGainRamp(fromMS: startMS,
                                                              toMS: startMS + lengthMS,
                                                              fromGain: 1, toGain: 1)])
    }

    @Test func soundWhollyInsideTheStretchMovesEarlierByTheIn() {
        let mix = [Self.segment(startMS: 3000, lengthMS: 1000, sourceInMS: 500)]
        let windowed = AudioMixSegment.windowed(mix, to: 2000..<6000)
        #expect(windowed.count == 1)
        #expect(windowed[0].startMS == 1000)
        #expect(windowed[0].lengthMS == 1000)
        #expect(windowed[0].sourceInMS == 500)
        #expect(windowed[0].ramps == [AudioGainRamp(fromMS: 1000, toMS: 2000, fromGain: 1, toGain: 1)])
    }

    @Test func soundOutsideTheStretchIsLeftOut() {
        let mix = [Self.segment(startMS: 0, lengthMS: 1500),
                   Self.segment(startMS: 7000, lengthMS: 1000)]
        #expect(AudioMixSegment.windowed(mix, to: 2000..<6000).isEmpty)
    }

    @Test func soundAcrossTheInLosesItsHeadAndReadsFurtherIntoTheFile() {
        let mix = [Self.segment(startMS: 1000, lengthMS: 3000, sourceInMS: 400)]
        let windowed = AudioMixSegment.windowed(mix, to: 2000..<6000)
        #expect(windowed.count == 1)
        #expect(windowed[0].startMS == 0)
        #expect(windowed[0].lengthMS == 2000)
        #expect(windowed[0].sourceInMS == 1400)
        #expect(windowed[0].sourceLengthMS == 2000)
    }

    @Test func soundAcrossTheOutLosesItsTail() {
        let mix = [Self.segment(startMS: 5000, lengthMS: 3000)]
        let windowed = AudioMixSegment.windowed(mix, to: 2000..<6000)
        #expect(windowed[0].startMS == 3000)
        #expect(windowed[0].lengthMS == 1000)
        #expect(windowed[0].sourceInMS == 0)
        #expect(windowed[0].sourceLengthMS == 1000)
    }

    @Test func aSpedUpPieceCutAtTheInReadsTwiceAsFarIntoTheFile() {
        // At 200% every millisecond of timeline reads two of the file.
        let mix = [Self.segment(startMS: 1000, lengthMS: 2000, sourceInMS: 0, speedPercent: 200)]
        let windowed = AudioMixSegment.windowed(mix, to: 2000..<6000)
        #expect(windowed[0].lengthMS == 1000)
        #expect(windowed[0].sourceInMS == 2000)
        #expect(windowed[0].sourceLengthMS == 2000)
        #expect(windowed[0].speedPercent == 200)
    }

    @Test func aFadeCutAtTheInStartsAtTheLevelItHadReachedThere() {
        // Fading up from silence over four seconds, cut half way: the file
        // starts at half, not at silence.
        let fade = [AudioGainRamp(fromMS: 0, toMS: 4000, fromGain: 0, toGain: 1)]
        let mix = [Self.segment(startMS: 0, lengthMS: 4000, ramps: fade)]
        let windowed = AudioMixSegment.windowed(mix, to: 2000..<6000)
        #expect(windowed[0].ramps.count == 1)
        #expect(windowed[0].ramps[0].fromMS == 0)
        #expect(windowed[0].ramps[0].toMS == 2000)
        #expect(abs(windowed[0].ramps[0].fromGain - 0.5) < 0.0001)
        #expect(windowed[0].ramps[0].toGain == 1)
    }

    @Test func theWholeDocumentWindowLeavesTheMixAlone() {
        let mix = [Self.segment(startMS: 1000, lengthMS: 3000, sourceInMS: 400)]
        #expect(AudioMixSegment.windowed(mix, to: 0..<10_000) == mix)
    }

    // MARK: - A subtitle file beside the film

    @Test func captionsBesideTheFilmStartAtTheIn() {
        let cues = [
            CaptionCue(words: [TranscribedWord("before", startMS: 500, endMS: 1500)],
                       inMS: 500, outMS: 1500),
            CaptionCue(words: [TranscribedWord("over", startMS: 1500, endMS: 2200),
                               TranscribedWord("the", startMS: 2200, endMS: 2600),
                               TranscribedWord("in", startMS: 2600, endMS: 3000)],
                       inMS: 1500, outMS: 3000),
            CaptionCue(words: [TranscribedWord("inside", startMS: 4000, endMS: 5000)],
                       inMS: 4000, outMS: 5000),
            CaptionCue(words: [TranscribedWord("after", startMS: 7000, endMS: 8000)],
                       inMS: 7000, outMS: 8000),
        ]
        let windowed = CaptionCue.windowed(cues, to: 2000..<6000)
        #expect(windowed.map(\.text) == ["over the in", "inside"])
        // One across the In starts with the film, its words kept where they
        // were said.
        #expect(windowed[0].inMS == 0)
        #expect(windowed[0].outMS == 1000)
        #expect(windowed[0].words.map(\.startMS) == [0, 200, 600])
        #expect(windowed[1].inMS == 2000)
        #expect(windowed[1].outMS == 3000)
    }

    @Test func captionedSecondsCountOnlyTheStretch() {
        var doc = Self.talk()
        doc.landCaptions([
            CaptionCue(words: [TranscribedWord("one", startMS: 1000, endMS: 3000)], inMS: 1000, outMS: 3000),
            CaptionCue(words: [TranscribedWord("two", startMS: 7000, endMS: 9000)], inMS: 7000, outMS: 9000),
        ])
        #expect(doc.captionedSeconds(in: 0..<10_000) == doc.captionedSeconds)
        #expect(doc.captionedSeconds(in: 2000..<6000) == 1)
    }
}
