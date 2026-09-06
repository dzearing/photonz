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
        let began = Date()
        for _ in 0..<1000 { _ = CaptionMetrics.pillSize(for: a.caption ?? "", in: a) }
        let each = Date().timeIntervalSince(began) / 1000 * 1_000_000
        print("[perf] CaptionMetrics.pillSize: \(String(format: "%.1f", each))µs per call")
        // ~22µs on the machine this landed on; the ceiling is loose on purpose
        // so a busy runner does not fail the build, and tight enough that
        // losing the font cache would be caught.
        #expect(each < 200)
    }
}
