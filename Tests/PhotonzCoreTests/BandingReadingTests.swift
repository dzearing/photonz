import Foundation
import PhotonzCore
import Testing

/// How banded a line of pixels is: the numbers the deband bar is written in
/// (task `soft-gradients-in-a-recording-come-out-smooth-ev`).
@Suite("Reading the bands down a line of pixels")
struct BandingReadingTests {

    @Test("Counts the distinct levels, the changes and the longest flat run")
    func readsAStaircase() {
        // Three bands, 4, 2 and 3 long.
        let reading = BandingReading(levels: [10, 10, 10, 10, 11, 11, 12, 12, 12])
        #expect(reading.distinctLevels == 3)
        #expect(reading.changes == 2)
        #expect(reading.longestFlatRun == 4)
        #expect(reading.largestStep == 1)
        #expect(reading.lowest == 10)
        #expect(reading.highest == 12)
    }

    @Test("A line that never changes is one long run")
    func flatLine() {
        let reading = BandingReading(levels: Array(repeating: 7, count: 50))
        #expect(reading.distinctLevels == 1)
        #expect(reading.changes == 0)
        #expect(reading.longestFlatRun == 50)
        #expect(reading.largestStep == 0)
    }

    @Test("An empty line reads as nothing at all")
    func emptyLine() {
        let reading = BandingReading(levels: [])
        #expect(reading.distinctLevels == 0)
        #expect(reading.longestFlatRun == 0)
    }

    @Test("Fractions of full scale become 10-bit codes, rounded")
    func tenBitCodes() {
        #expect(BandingReading.codes([0, 1, 0.5, 52.0 / 255], bits: 10) == [0, 1023, 512, 209])
        #expect(BandingReading.codes([52.0 / 255, 62.0 / 255], bits: 8) == [52, 62])
    }

    @Test("The bar: under 40 px flat and at least 35 levels, as the task sets it")
    func theBar() {
        let banded = BandingReading(levels: (0..<1300).map { 209 + ($0 / 130) * 4 })
        #expect(!banded.isSmooth(longestRunUnder: 40, levelsAtLeast: 35))
        let ramp = BandingReading(levels: (0..<1300).map { 209 + $0 * 40 / 1300 })
        #expect(ramp.isSmooth(longestRunUnder: 40, levelsAtLeast: 35))
    }
}
