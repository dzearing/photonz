import Foundation
import Synchronization
import Testing
@testable import PhotonzRender

/// A dab's own pixels are worked out side by side on as many cores as pay
/// (`PixelBands`). A dab works out a good deal at every pixel (the paper's
/// tooth, a stick's streaks, an oil brush's bristles), so a box far smaller
/// than a plain copy of values is worth splitting. On 2026-10-30 the thinned
/// end a mouse stroke draws as it goes was laid one dab at a time on the main
/// thread: its dabs are narrower, so every one fell under the size a copy
/// splits at, and so did a whole 150 point oil dab (23,716 pixels). Laying the
/// end took half of every move at 150 points.
@Suite("Pixel bands")
struct PixelBandsTests {
    private func box(_ side: Int) -> PixelBox { PixelBox(minX: 10, minY: 20, maxX: 10 + side, maxY: 20 + side) }

    @Test func aThinnedDabAtOneHundredAndFiftyPointsIsSplit() {
        // The end of a 150 point stroke at a pixel a point: about 100 pixels
        // across where it has thinned to two thirds.
        let dab = box(100)
        #expect(PixelBands.count(for: dab) == 1, "a plain copy of values this size is not worth splitting")
        #expect(PixelBands.count(forDab: dab) == min(PixelBands.ways, 4))
    }

    @Test func aWholeOneHundredAndFiftyPointOilDabIsSplitAsWideAsItCan() {
        #expect(PixelBands.count(forDab: box(154)) == PixelBands.ways)
    }

    @Test func aSmallDabStaysOnOneCore() {
        // Handing 400 pixels to other cores costs more than working them out.
        #expect(PixelBands.count(forDab: box(20)) == 1)
        #expect(PixelBands.count(forDab: box(63)) == 1)
    }

    @Test func aBoxOneRowHighIsNeverSplit() {
        #expect(PixelBands.count(forDab: PixelBox(minX: 0, minY: 0, maxX: 9000, maxY: 1)) == 1)
        #expect(PixelBands.count(forDab: .empty) == 0)
    }

    @Test func bandsCoverEveryRowOnce() {
        let dab = box(100)
        let bands = PixelBands.count(forDab: dab)
        let rows = Mutex<[Int]>([])
        PixelBands.run(dab, bands: bands) { _, minRow, maxRow in
            rows.withLock { $0 += Array(minRow..<maxRow) }
        }
        #expect(rows.withLock { $0.sorted() } == Array(dab.minY..<dab.maxY))
    }
}
