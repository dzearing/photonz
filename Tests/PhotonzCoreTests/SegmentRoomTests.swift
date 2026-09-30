import CoreGraphics
import Testing
@testable import PhotonzCore

/// How a row of segments uses the room it is given. Measured in the app on
/// 2026-09-30: Free | Stack | Grid asks 133pt at the small size and a Mixed
/// Arrangement row gives it 113pt, and the colour picker's four swatch scopes
/// did not fit their row either. Both had turned into dropdowns, the Mixed
/// one an EMPTY dropdown.
@Suite("A row of segments keeps its words whole before it becomes a dropdown")
struct SegmentRoomTests {

    @Test("Room for equal columns gets equal columns")
    func equalColumns() {
        #expect(SegmentRoom.layout(available: 300, equal: 292, systemFit: 245, tight: 213) == .equal)
    }

    @Test("Room for the system's own widths gets them, the rest shared out")
    func systemWidths() {
        #expect(SegmentRoom.layout(available: 270, equal: 292, systemFit: 245, tight: 213) == .proportional)
        #expect(SegmentRoom.layout(available: 245, equal: 292, systemFit: 245, tight: 213) == .proportional)
    }

    @Test("Short of the system's widths, each word keeps its own width with a tighter margin")
    func tighterMargins() {
        #expect(SegmentRoom.layout(available: 244, equal: 292, systemFit: 245, tight: 213) == .tight)
        #expect(SegmentRoom.layout(available: 115, equal: 147, systemFit: 133, tight: 109) == .tight)
        #expect(SegmentRoom.layout(available: 109, equal: 147, systemFit: 133, tight: 109) == .tight)
    }

    @Test("Only when even that cuts a word short does the row become a dropdown")
    func dropdown() {
        #expect(SegmentRoom.layout(available: 108, equal: 147, systemFit: 133, tight: 109) == .tooNarrow)
    }

    @Test("A tight row hands its spare room out evenly, so no word loses its margin")
    func tightWidths() {
        let widths = SegmentRoom.tightWidths(words: [37, 40, 52, 38], available: 223, chrome: 3)
        // 167 of words, 4 margins of 10, 3 of chrome: 210, and 13 to spare.
        #expect(widths.count == 4)
        #expect(abs(widths.reduce(0, +) - 220) < 0.001)
        #expect(abs(widths[2] - (52 + SegmentRoom.tightMargin + 13.0 / 4)) < 0.001)
    }

    @Test("A row squeezed below its words never hands out negative room")
    func neverShrinksAWord() {
        let widths = SegmentRoom.tightWidths(words: [24, 30, 25], available: 50, chrome: 3)
        #expect(widths == [24 + SegmentRoom.tightMargin, 30 + SegmentRoom.tightMargin, 25 + SegmentRoom.tightMargin])
    }

    @Test("The tight width is the words, a margin each, and the control's edge")
    func tightWidth() {
        #expect(SegmentRoom.tightWidth(words: [24, 30, 25], chrome: 3) == 79 + 3 * SegmentRoom.tightMargin + 3)
    }
}
