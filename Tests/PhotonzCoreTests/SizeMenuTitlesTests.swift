import CoreGraphics
import Testing
@testable import PhotonzCore

/// The words a size wears in the Size menu.
///
/// A Mac pop-up takes its width from the widest row in its list, so a menu of
/// numbers changes size the moment a bigger number joins it: the presets alone
/// need 69pt, a "128 pt" carried in by an opened document needs 73pt, and even
/// the word Mixed needs 72pt. The menu cannot be told to be wider than its
/// content, so the only way to hold one width is to make every row take the
/// same room — each number padded out to three digits with a figure space,
/// which is exactly one digit wide.
///
/// The width itself is AppKit's to measure. What is ours, and what is tested
/// here, is that every title carries the same number of digit slots and that
/// nothing reading a size back in a sentence ever sees the padding.
@Suite struct SizeMenuTitlesTests {

    /// How wide a title is, counted the way the menu font counts it: a figure
    /// space and a digit are the same width, so this is the real comparison.
    private func slots(_ title: String) -> Int {
        title.count
    }

    @Test func padsATwoDigitSizeOutToThree() {
        #expect(TextStyles.sizeTitle(24) == "24 pt\u{2007}")
    }

    @Test func padsAOneDigitSizeOutToThree() {
        #expect(TextStyles.sizeTitle(8) == "8 pt\u{2007}\u{2007}")
    }

    @Test func leavesAThreeDigitSizeAlone() {
        #expect(TextStyles.sizeTitle(128) == "128 pt")
    }

    /// The whole point: every size the menu can offer takes the same room, so
    /// the box holds one width and the Weight menu beside it never moves.
    @Test func everySizeFromOneToThreeDigitsTakesTheSameRoom() {
        let widths = Set((1...999).map { slots(TextStyles.sizeTitle(CGFloat($0))) })
        #expect(widths == [slots("128 pt")])
    }

    @Test func everyPresetTakesTheSameRoom() {
        let widths = Set(TextStyles.fontSizes.map { slots(TextStyles.sizeTitle($0)) })
        #expect(widths.count == 1)
    }

    /// A size past 999 is wider than the room held for it. It is not shortened
    /// — a number nobody can read is worse than a box that grew — so this is
    /// the one case where the menu still changes width, and it says so.
    @Test func aFourDigitSizeIsSaidInFullEvenThoughItOutgrowsTheBox() {
        #expect(TextStyles.sizeTitle(1024) == "1024 pt")
    }

    @Test func dropsTheFractionTheWayTheMenuAlwaysHas() {
        #expect(TextStyles.sizeTitle(24.7) == "24 pt\u{2007}")
    }

    // MARK: - What anything that reads a size back sees

    @Test func theWordsForASentenceCarryNoPadding() {
        #expect(TextStyles.sizeWords(24) == "24 pt")
        #expect(TextStyles.sizeWords(128) == "128 pt")
    }

    @Test func aPaddedTitleReadsBackAsTheWordsOnScreen() {
        #expect(TextStyles.unpadded(TextStyles.sizeTitle(24)) == "24 pt")
        #expect(TextStyles.unpadded(TextStyles.sizeTitle(8)) == "8 pt")
    }

    @Test func readingBackLeavesATitleThatWasNeverPaddedAlone() {
        #expect(TextStyles.unpadded("Helvetica Neue") == "Helvetica Neue")
        #expect(TextStyles.unpadded("Mixed") == "Mixed")
    }
}
