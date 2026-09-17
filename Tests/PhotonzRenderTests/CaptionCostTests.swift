import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Every click on the canvas now measures each captioned arrow's label, so it
/// can tell the label apart from the blank picture beside it. This is the
/// budget that made that affordable: a document with twenty captioned arrows
/// spends well under a millisecond deciding what a click landed on.
@Suite("Caption measuring cost")
struct CaptionCostTests {

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
}
