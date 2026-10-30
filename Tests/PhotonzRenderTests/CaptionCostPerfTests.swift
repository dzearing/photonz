import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Every click on the canvas now measures each captioned arrow's label, so it
/// can tell the label apart from the blank picture beside it. This is the
/// budget that made that affordable: a document with twenty captioned arrows
/// spends well under a millisecond deciding what a click landed on.
@Suite("Caption measuring cost", .serialized)
struct CaptionCostPerfTests {

    @Test func measuringACaptionIsCheapEnoughForEveryClick() {
        var a = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        a.caption = "Save all the changes here"
        _ = CaptionMetrics.pillSize(for: a.caption ?? "", in: a)   // warm the font cache
        // Read the way every other timing check in the suite reads: on this
        // thread's own CPU clock, and the FASTEST of several batches rather
        // than the mean of one. A mean off the wall clock counts every moment
        // the thread was parked, which is why two idle runs of this same test
        // reported 25.5µs and 37.4µs on 2026-09-17 — a 47% swing with nothing
        // changed. What is being claimed here is what a call costs, not what
        // the scheduler was doing at the time.
        let each = PerfClock.fastestCallMS(batches: 20, callsPerBatch: 200) {
            _ = CaptionMetrics.pillSize(for: a.caption ?? "", in: a)
        } * 1000
        print("[perf] CaptionMetrics.pillSize: \(String(format: "%.1f", each))µs per call")
        // ~22µs on the machine this landed on; the ceiling is loose on purpose
        // so a busy runner does not fail the build, and tight enough that
        // losing the font cache would be caught.
        if MachineSpeed.isGating {
            #expect(each < 200)
        }
    }

    /// A caption whose word pops is drawn again on every frame the word is
    /// moving, so one draw has to fit inside a frame at 60 frames a second
    /// with room left for the picture: a 1080p caption box at 2x, the word
    /// grown, glowing, stroked and on a plate (`CaptionWordStyle.swift`).
    @Test func drawingAPoppingCaptionFitsInAFrame() {
        var text = TextContent(string: "Capture the screen and let it", fontSize: 58, colorHex: "#FFFFFF",
                               weight: .bold, alignment: .center, verticalAlignment: .bottom)
        text.plateHex = "#00000099"
        text.wordPaint = CaptionWordPaint(word: CaptionActiveWord.Span(location: 12, length: 6),
                                          said: .dim, coming: .dim, colorHex: "#FFD76A",
                                          glowHex: "#FF4FD8", strokeHex: "#000000", shadow: true,
                                          scale: 1.25, drawnAlone: true)
        let size = CGSize(width: 1536, height: 151)
        _ = TextRasterizer.rasterize(text, size: size, scale: 2)
        // Each draw beside the fastest of three CPU ruler rounds, both on this
        // thread's CPU clock, and the middle round's ratio scaled to the
        // calibration machine. It was
        // the fastest of fifteen batches against 8ms scaled by the filter
        // graph read once when the process started: 6.6 to 7.5ms against
        // bounds of 8.6 to 30 across five full runs (2026-10-30), and 8.03
        // against 8 once on unchanged code (2026-10-26), since a Core Image
        // ruler read at a quiet moment knows nothing about a busy CPU now.
        let reading = PerfClock.calibrated(rounds: 15, rulerRounds: 3) { _ in
            _ = TextRasterizer.rasterize(text, size: size, scale: 2)
        }
        let each = MachineSpeed.median(of: reading.subject) ?? .infinity
        print("[perf] popping caption at 1080p, 2x: \(String(format: "%.2f", each))ms per frame")
        // Half a 60fps frame on the calibration machine, where it reads 4.9 to
        // 5.1ms alone (2026-10-30): twice the drawing crosses it.
        PerfClock.check("a popping caption at 1080p, 2x", ms: reading.medianMS, rulerMS: reading.rulerMS,
                        baselineMS: 5, tolerance: 1.6)
    }
}
