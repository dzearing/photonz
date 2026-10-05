import CoreGraphics
import Testing
@testable import PhotonzCore

/// A layer's heading on the timing strip wraps a long name onto a second line,
/// as the Make a bell swing mock does, instead of cutting it.
@Suite struct MotionStripHeadingTests {
    @Test func aNameOnOneLineKeepsTheRowItAlwaysHad() {
        #expect(MotionStripHeading.rowHeight(base: 16, lines: 1, lineHeight: 12) == 16)
        #expect(MotionStripHeading.rowHeight(base: 22, lines: 1, lineHeight: 12) == 22)
    }

    @Test func aNameOnTwoLinesGrowsItsRowToHoldBoth() {
        let height = MotionStripHeading.rowHeight(base: 16, lines: 2, lineHeight: 12)
        #expect(height >= 24)
        #expect(height <= 28)
    }

    @Test func aBarRowAlreadyTallEnoughDoesNotGrow() {
        #expect(MotionStripHeading.rowHeight(base: 42, lines: 2, lineHeight: 12) == 42)
    }

    @Test func aNameNeverTakesMoreThanTwoLines() {
        #expect(MotionStripHeading.shownLines(forNeeded: 0) == 1)
        #expect(MotionStripHeading.shownLines(forNeeded: 1) == 1)
        #expect(MotionStripHeading.shownLines(forNeeded: 2) == 2)
        #expect(MotionStripHeading.shownLines(forNeeded: 5) == 2)
        #expect(MotionStripHeading.rowHeight(base: 16, lines: 5, lineHeight: 12)
                == MotionStripHeading.rowHeight(base: 16, lines: 2, lineHeight: 12))
    }

    @Test func onlyANameTwoLinesCannotHoldIsCutAndTipped() {
        #expect(!MotionStripHeading.isCut(neededLines: 1))
        #expect(!MotionStripHeading.isCut(neededLines: 2))
        #expect(MotionStripHeading.isCut(neededLines: 3))
    }
}
