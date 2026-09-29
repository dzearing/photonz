import CoreGraphics
import Testing
@testable import PhotonzCore

/// The segmented control's thumb moving between options, and following a drag
/// (`docs/design/mocks/pages/comp-segmented.html`, `shared/components/segmented.js`).
///
/// The user, 2026-09-29: the thumb should "use liquid glass animation effect
/// when snapping between options", then, of the first try, that the overshoot
/// was obnoxious on a move of more than one step because it left the rail, and
/// that afternoon that it "overshoots like CRAZY... This doesn't feel mac
/// native". So it glides and stops: no overshoot, no settle, no bounce.
@Suite("The segmented thumb's morph and drag")
struct SegmentThumbMotionTests {
    /// Three 60pt segments, 2pt apart, 24pt tall, in a 184pt row.
    static let slots = [
        CGRect(x: 0, y: 0, width: 60, height: 24),
        CGRect(x: 62, y: 0, width: 60, height: 24),
        CGRect(x: 124, y: 0, width: 60, height: 24),
    ]
    static let row: ClosedRange<CGFloat> = 0...184

    private func morph(_ from: Int, _ to: Int) -> SegmentThumbMorph {
        SegmentThumbMorph(from: Self.slots[from], to: Self.slots[to], row: Self.row)
    }

    private func samples(_ morph: SegmentThumbMorph) -> [CGRect] {
        stride(from: 0.0, through: SegmentThumbMorph.duration, by: 0.002).map { morph.frame(at: $0) }
    }

    @Test("It starts where the thumb was and ends in the new slot")
    func endsInTheSlot() {
        let move = morph(0, 2)
        #expect(move.frame(at: 0) == Self.slots[0])
        #expect(move.frame(at: SegmentThumbMorph.duration) == Self.slots[2])
        #expect(move.frame(at: 5) == Self.slots[2])
        #expect(move.isFinished(at: SegmentThumbMorph.duration))
        #expect(!move.isFinished(at: 0.1))
    }

    @Test("Part way through it stretches over both slots, squashed a little")
    func stretchesAcrossBoth() {
        let stretched = morph(0, 2).frame(at: SegmentThumbMorph.duration * 0.45)
        #expect(abs(stretched.minX - Self.slots[0].minX) < 0.01)
        #expect(abs(stretched.maxX - Self.slots[2].maxX) < 0.01)
        #expect(stretched.height < Self.slots[2].height)
        #expect(abs(stretched.midY - Self.slots[2].midY) < 0.01)
    }

    @Test("However far it goes, it never leaves the row", arguments: [(0, 1), (0, 2), (2, 0), (1, 0), (2, 1)])
    func staysInTheRow(from: Int, to: Int) {
        for frame in samples(morph(from, to)) {
            #expect(frame.minX >= Self.row.lowerBound - 0.001)
            #expect(frame.maxX <= Self.row.upperBound + 0.001)
            #expect(frame.minY >= -0.001)
            #expect(frame.maxY <= 24.001)
        }
    }

    @Test("It never goes past its new slot, or back past its old one", arguments: [(0, 1), (0, 2), (2, 0), (1, 0), (2, 1)])
    func noOvershoot(from: Int, to: Int) {
        let low = min(Self.slots[from].minX, Self.slots[to].minX)
        let high = max(Self.slots[from].maxX, Self.slots[to].maxX)
        for frame in samples(morph(from, to)) {
            #expect(frame.minX >= low - 0.001)
            #expect(frame.maxX <= high + 0.001)
        }
    }

    @Test("Each edge travels one way only: nothing bounces", arguments: [(0, 1), (0, 2), (2, 0), (1, 2)])
    func edgesAreMonotonic(from: Int, to: Int) {
        let frames = samples(morph(from, to))
        let rightward = Self.slots[to].minX > Self.slots[from].minX
        for (a, b) in zip(frames, frames.dropFirst()) {
            if rightward {
                #expect(b.minX >= a.minX - 0.001)
                #expect(b.maxX >= a.maxX - 0.001)
            } else {
                #expect(b.minX <= a.minX + 0.001)
                #expect(b.maxX <= a.maxX + 0.001)
            }
        }
    }

    @Test("It takes about three tenths of a second, like the component page")
    func quick() {
        #expect(SegmentThumbMorph.duration == 0.3)
        #expect(SegmentThumbMorph.squash > 0.9)
    }

    @Test("A thumb that is already there does not move")
    func noMoveNoMorph() {
        let still = morph(1, 1)
        #expect(samples(still).allSatisfy { $0 == Self.slots[1] })
    }

    @Test("A second choice mid-flight carries on from where the thumb is")
    func interruptible() {
        let first = morph(0, 2)
        let now = first.frame(at: 0.15)
        let second = SegmentThumbMorph(from: now, to: Self.slots[0], row: Self.row)
        #expect(second.frame(at: 0) == now)
        #expect(second.frame(at: SegmentThumbMorph.duration) == Self.slots[0])
    }

    @Test("Position and size move together: no jump where one leg of the move hands to the next")
    func noJumps() {
        let move = morph(0, 2)
        for offset in [0.45] {
            let join = SegmentThumbMorph.duration * offset
            let before = move.frame(at: join - 0.0001), after = move.frame(at: join + 0.0001)
            #expect(abs(before.minX - after.minX) < 0.5)
            #expect(abs(before.width - after.width) < 0.5)
            #expect(abs(before.height - after.height) < 0.5)
        }
    }

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
