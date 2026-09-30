import CoreGraphics
import Testing
@testable import PhotonzCore

/// The segmented control's thumb under a hand
/// (`docs/design/mocks/pages/comp-segmented.html`, `shared/components/segmented.js`).
///
/// A pick moves the thumb by the system's own Liquid Glass animation, so the
/// only motion the app works out for itself is the drag: the thumb follows the
/// pointer and lands on the nearest segment it can.
@Suite("The segmented thumb's drag")
struct SegmentThumbMotionTests {
    /// Three 60pt segments, 2pt apart, 24pt tall, in a 184pt row.
    static let slots = [
        CGRect(x: 0, y: 0, width: 60, height: 24),
        CGRect(x: 62, y: 0, width: 60, height: 24),
        CGRect(x: 124, y: 0, width: 60, height: 24),
    ]
    static let row: ClosedRange<CGFloat> = 0...184

    // MARK: Drag

    @Test("A dragged thumb follows the pointer and stays in the row")
    func dragFollows() {
        let mid = SegmentThumbDrag.frame(centerX: 92, slots: Self.slots, row: Self.row)
        #expect(abs(mid.midX - 92) < 0.01)
        #expect(mid.width == 60)
        let past = SegmentThumbDrag.frame(centerX: 400, slots: Self.slots, row: Self.row)
        #expect(past.maxX == Self.row.upperBound)
        let before = SegmentThumbDrag.frame(centerX: -50, slots: Self.slots, row: Self.row)
        #expect(before.minX == Self.row.lowerBound)
    }

    @Test("Between two segments of different widths the dragged thumb takes a width between theirs")
    func dragWidthBlends() {
        let uneven = [CGRect(x: 0, y: 0, width: 40, height: 24),
                      CGRect(x: 42, y: 0, width: 80, height: 24)]
        let halfway = SegmentThumbDrag.frame(centerX: (uneven[0].midX + uneven[1].midX) / 2,
                                             slots: uneven, row: 0...122)
        #expect(abs(halfway.width - 60) < 0.01)
    }

    @Test("Letting go picks the segment under the thumb's middle, skipping ones that cannot be picked")
    func dragLands() {
        #expect(SegmentThumbDrag.landing(centerX: 20, slots: Self.slots) == 0)
        #expect(SegmentThumbDrag.landing(centerX: 100, slots: Self.slots) == 1)
        #expect(SegmentThumbDrag.landing(centerX: 170, slots: Self.slots) == 2)
        #expect(SegmentThumbDrag.landing(centerX: 85, slots: Self.slots, available: [true, false, true]) == 0)
        #expect(SegmentThumbDrag.landing(centerX: 100, slots: Self.slots, available: [false, false, false]) == nil)
    }
}
