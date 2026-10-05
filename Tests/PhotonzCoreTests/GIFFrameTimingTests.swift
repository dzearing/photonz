import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A GIF runs as long as the edit it came from.** The format keeps a frame's
/// delay in whole hundredths of a second, so 1/15 s is written as 7 and a four
/// second edit plays for 4.2. The delays are spread over whole hundredths
/// instead, so the running total keeps to the clock.
@Suite("A GIF's frame delays add up to the edit")
struct GIFFrameTimingTests {

    static func total(_ delays: [Int]) -> Int { delays.reduce(0, +) }

    @Test("Four seconds at every preset adds up to four seconds", arguments: VideoExportQuality.allCases)
    func fourSecondsAtEveryPreset(_ quality: VideoExportQuality) {
        let plan = DocumentVideoExport.plan(durationMS: 4_000, canvasSize: CGSize(width: 1600, height: 1000),
                                            format: .gif, quality: quality)
        let delays = plan.gifDelaysInHundredths
        #expect(delays.count == plan.frameCount)
        #expect(abs(Self.total(delays) - 400) <= 1)
    }

    @Test("Fifteen a second alternates sixes and sevens rather than every frame a seven")
    func fifteenASecondAlternates() {
        let delays = GIFFrameTiming.delaysInHundredths(frameCount: 15, fps: 15, durationMS: 1_000)
        #expect(Set(delays) == [6, 7])
        #expect(Self.total(delays) == 100)
    }

    @Test("Ten a second is ten hundredths every frame")
    func tenASecondIsExact() {
        let delays = GIFFrameTiming.delaysInHundredths(frameCount: 40, fps: 10, durationMS: 4_000)
        #expect(delays == Array(repeating: 10, count: 40))
    }

    @Test("A five minute edit does not drift")
    func fiveMinutesDoNotDrift() {
        for fps in [10.0, 15, 24, 30, 50] {
            let durationMS = 300_000
            let count = Int((Double(durationMS) / 1000 * fps).rounded())
            let delays = GIFFrameTiming.delaysInHundredths(frameCount: count, fps: fps, durationMS: durationMS)
            #expect(abs(Self.total(delays) - 30_000) <= 1, "at \(fps) a second")
            // Never off the frame grid by more than a hundredth at any point.
            var elapsed = 0
            for (index, delay) in delays.enumerated() {
                elapsed += delay
                let clock = Double(index + 1) * 100 / fps
                #expect(abs(Double(elapsed) - min(clock, 30_000)) <= 1, "frame \(index) at \(fps)")
            }
        }
    }

    @Test("An edit that is not a whole number of frames ends where the edit ends")
    func anOddLengthEndsOnTheEdit() {
        // 4,030 ms at 15 a second is 60 frames; the last one holds to 4.03 s.
        let delays = GIFFrameTiming.delaysInHundredths(frameCount: 60, fps: 15, durationMS: 4_030)
        #expect(Self.total(delays) == 403)
    }

    @Test("No frame is ever shorter than two hundredths, which readers would slow to a tenth")
    func noFrameTooShortToShow() {
        for fps in [10.0, 15, 24, 30, 50] {
            for durationMS in [40, 100, 1_010, 4_000, 4_017] {
                let count = max(1, Int((Double(durationMS) / 1000 * fps).rounded()))
                let delays = GIFFrameTiming.delaysInHundredths(frameCount: count, fps: fps, durationMS: durationMS)
                #expect(delays.allSatisfy { $0 >= 2 }, "\(durationMS) ms at \(fps): \(delays)")
            }
        }
    }

    @Test("Nothing to write has no delays")
    func nothingHasNoDelays() {
        #expect(GIFFrameTiming.delaysInHundredths(frameCount: 0, fps: 15, durationMS: 0).isEmpty)
    }

    @Test("A recording's GIF runs as long as its trim, its cuts or its whole")
    func aRecordingsPlanKeepsItsLength() {
        let size = CGSize(width: 1600, height: 1000)
        let whole = AnimatedExportPlanner.plan(duration: 4, sourceSize: size, targetFPS: 15)
        #expect(Self.total(whole.gifDelaysInHundredths) == 400)

        let trimmed = AnimatedExportPlanner.plan(trim: VideoTrim(inPoint: 1, outPoint: 5, duration: 6),
                                                 sourceSize: size, targetFPS: 24)
        #expect(abs(Self.total(trimmed.gifDelaysInHundredths) - 400) <= 1)

        let cuts = VideoCutList(pieces: [VideoPiece(start: 0, end: 2), VideoPiece(start: 4, end: 6)],
                                sourceDuration: 6)
        let cut = AnimatedExportPlanner.plan(cuts: cuts, sourceSize: size, targetFPS: 15)
        #expect(Self.total(cut.gifDelaysInHundredths) == 400)
    }

    @Test("A GIF read back is the edit when its delays add up within a hundredth")
    func aGIFRunsAsLongWithinAHundredth() {
        #expect(VideoClipboardCopy.gifRunsAsLong(fileMS: 4_000, asEditMS: 4_000))
        #expect(VideoClipboardCopy.gifRunsAsLong(fileMS: 4_010, asEditMS: 4_000))
        #expect(VideoClipboardCopy.gifRunsAsLong(fileMS: 3_990, asEditMS: 4_000))
        // A hundredth of rounding on top of an edit that is not whole hundredths.
        #expect(VideoClipboardCopy.gifRunsAsLong(fileMS: 4_030, asEditMS: 4_017))
        #expect(!VideoClipboardCopy.gifRunsAsLong(fileMS: 4_200, asEditMS: 4_000))
        #expect(!VideoClipboardCopy.gifRunsAsLong(fileMS: 3_840, asEditMS: 4_000))
        #expect(!VideoClipboardCopy.gifRunsAsLong(fileMS: 0, asEditMS: 0))
    }
}
