import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// **Which stretches of a video the Export sheet writes to find out what the
/// whole file will weigh, and how it counts them up.**
///
/// A budget is not a promise the encoder keeps. On a page of text scrolling at
/// 900 pixels a second the system's H.264 encoder cannot get Small under 1.3
/// times its budget whatever it is asked for (`VideoExportBudgetTests`), and
/// nothing about the recording on disk says in advance which recordings are
/// like that. So the sheet writes a few short stretches at the chosen setting
/// and scales what they weigh up to the whole length.
@Suite("Which stretches of a video are written to weigh it")
struct VideoExportSampleTests {

    /// A video short enough to write in a moment is written whole: its answer
    /// is the file itself rather than an estimate from pieces of it.
    @Test func aShortVideoIsWrittenWhole() {
        #expect(VideoExportSample.stretches(of: 0..<3000) == [0..<3000])
        #expect(VideoExportSample.stretches(of: 4000..<16000) == [4000..<16000])
    }

    /// A long one is weighed from a handful of two second stretches spread
    /// across it, each starting on a two second step from the start of the
    /// file, which is where the export puts a key frame. A stretch that starts
    /// anywhere else would pay for a key frame the real file does not have.
    @Test func aLongVideoIsWeighedFromStretchesSpreadAcrossIt() {
        let span = 0..<300_000
        let stretches = VideoExportSample.stretches(of: span)
        #expect(stretches.count == VideoExportSample.stretchCount)
        for stretch in stretches {
            #expect(stretch.count == VideoExportSample.stretchMS)
            #expect(stretch.lowerBound % VideoExportSample.stretchMS == 0)
            #expect(span.contains(stretch.lowerBound) && stretch.upperBound <= span.upperBound)
        }
        // In order, none overlapping, and reaching into both ends of the video.
        #expect(zip(stretches, stretches.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound })
        let first = stretches.first?.lowerBound ?? .max
        let last = stretches.last?.upperBound ?? 0
        #expect(first < 60_000, "the first stretch starts at \(first)")
        #expect(last > 240_000, "the last stretch ends at \(last)")
    }

    /// The steps are counted from the start of what is written, so a stretch
    /// from the In mark on still lines up with the file's own key frames.
    @Test func theStepsAreCountedFromTheStartOfTheFile() {
        let span = 1_234..<61_234
        for stretch in VideoExportSample.stretches(of: span) {
            #expect((stretch.lowerBound - span.lowerBound) % VideoExportSample.stretchMS == 0)
            #expect(stretch.upperBound <= span.upperBound)
        }
    }

    /// A long video's stretches are written one after another behind a copy
    /// of the first, which warms the encoder up and is not counted: a file's
    /// first two seconds cost it far more than any two after them.
    @Test func aLongVideoIsWrittenBehindAWarmUp() {
        let span = 0..<60_000
        let order = VideoExportSample.writingOrder(of: span)
        let stretches = VideoExportSample.stretches(of: span)
        #expect(order.stretches == [stretches[0]] + stretches)
        #expect(order.countedFromMS == VideoExportSample.stretchMS)
    }

    /// A short one is written whole, warm-up and all, just as the export
    /// writes it, and all of it counts.
    @Test func aShortVideoIsWrittenWholeAndAllOfItCounts() {
        let order = VideoExportSample.writingOrder(of: 1000..<9000)
        #expect(order.stretches == [1000..<9000])
        #expect(order.countedFromMS == 0)
    }

    /// The encoder is held to its budget only where the picture would spend
    /// more than it: holding it anywhere else takes bits away from an easy
    /// recording that was nowhere near its budget.
    @Test func onlyAPictureThatWouldOvershootIsHeldToItsBudget() {
        #expect(!VideoExportSample.holdsToBudget(pictureBytes: 100_000, budgetBytes: 1_000_000))
        #expect(!VideoExportSample.holdsToBudget(pictureBytes: 1_000_000, budgetBytes: 1_000_000))
        #expect(VideoExportSample.holdsToBudget(pictureBytes: 1_050_000, budgetBytes: 1_000_000))
        // No budget, as on an animated picture, is nothing to hold to.
        #expect(!VideoExportSample.holdsToBudget(pictureBytes: 1_000, budgetBytes: 0))
    }

    @Test func nothingToWriteIsNoStretches() {
        #expect(VideoExportSample.stretches(of: 500..<500).isEmpty)
    }

    /// What the stretches weighed, scaled up to the whole length, and the sound
    /// on top as it was written: the stretches are written without it, and the
    /// sound weighs what it weighs whatever the picture does.
    @Test func theWeightIsTheStretchesScaledUpWithTheSoundOnTop() {
        #expect(VideoExportSample.estimate(pictureBytes: 100_000, sampledMS: 12_000,
                                           spanMS: 120_000) == 1_000_000)
        #expect(VideoExportSample.estimate(pictureBytes: 100_000, sampledMS: 12_000,
                                           spanMS: 120_000, soundBytes: 40_000) == 1_040_000)
        #expect(VideoExportSample.estimate(pictureBytes: 50_000, sampledMS: 3_000,
                                           spanMS: 3_000) == 50_000)
    }

    @Test func nothingWrittenIsNoAnswer() {
        #expect(VideoExportSample.estimate(pictureBytes: 0, sampledMS: 2_000, spanMS: 10_000,
                                           soundBytes: 500) == 0)
        #expect(VideoExportSample.estimate(pictureBytes: 10, sampledMS: 0,
                                           spanMS: 10_000) == 0)
    }
}
