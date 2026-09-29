import CoreGraphics
import Foundation

/// The segmented control's thumb going from one option to another
/// (`docs/design/mocks/pages/comp-segmented.html`, `shared/components/segmented.js`).
///
/// The user, 2026-09-29 morning: the thumb should "use liquid glass animation
/// effect when snapping between options". That afternoon, of the stretch,
/// squash and settle that followed: "the segmented control overshoots like
/// CRAZY... This doesn't feel mac native." So it moves the way a Mac segmented
/// control does: it glides to the new segment and stops, in 300ms, on the
/// component page's curve (efa1d36f). The only liquid left in it is a slight
/// stretch: the leading edge reaches the new slot first, the thumb spanning
/// both slots a little squashed, then the trailing edge follows it in.
///
/// Rules held here rather than in the view so a test can hold them:
///
/// * **No overshoot.** No frame reaches past the new slot or back past the
///   old one, and each edge only ever travels toward where it is going.
/// * **Position and size are one animation.** Every frame is one rect read
///   off one clock, so the thumb never reaches its slot still wide.
/// * **One animator.** This is the only thing that moves the thumb; the view
///   keeps every other animation off it (`DesignedSegments.thumbLayer`).
///
/// Interruptible: a second choice mid-flight starts a new morph from whatever
/// `frame(at:)` says right now.
public struct SegmentThumbMorph: Sendable, Equatable {
    /// The page's 300ms.
    public static let duration: TimeInterval = 0.3
    /// How much the stretched thumb is squashed, about its middle.
    public static let squash: CGFloat = 0.94
    /// Where in the move the thumb spans both slots.
    static let stretchAt: Double = 0.45

    public var from: CGRect
    public var to: CGRect
    /// The horizontal room the thumb may use: the row of segments. Every
    /// frame lies between the two slots, so this only keeps a thumb that
    /// starts outside the row (it never should) from being drawn there.
    public var row: ClosedRange<CGFloat>

    public init(from: CGRect, to: CGRect, row: ClosedRange<CGFloat>) {
        self.from = from
        self.to = to
        self.row = row
    }

    public func isFinished(at elapsed: TimeInterval) -> Bool { elapsed >= Self.duration }

    /// Where the thumb is `elapsed` seconds into the move.
    public func frame(at elapsed: TimeInterval) -> CGRect {
        if abs(from.minX - to.minX) < 0.5, abs(from.width - to.width) < 0.5,
           abs(from.minY - to.minY) < 0.5, abs(from.height - to.height) < 0.5 {
            return to
        }
        let t = min(max(elapsed / Self.duration, 0), 1)
        if t >= 1 { return to }
        // The page's keyframes: offsets 0, 0.45, 1, each leg with its own curve.
        let rect: CGRect
        if t <= Self.stretchAt {
            let eased = CubicBezier.value(t / Self.stretchAt, 0.33, 0, 0.4, 1)
            rect = Self.mix(from, stretched, CGFloat(eased))
        } else {
            let eased = CubicBezier.value((t - Self.stretchAt) / (1 - Self.stretchAt), 0.2, 0, 0, 1)
            rect = Self.mix(stretched, to, CGFloat(eased))
        }
        return clamped(rect)
    }

    /// Both slots under one pane, squashed a little about the middle.
    private var stretched: CGRect {
        let low = min(from.minX, to.minX)
        let high = max(from.maxX, to.maxX)
        let squashed = to.height * Self.squash
        return CGRect(x: low, y: to.midY - squashed / 2, width: high - low, height: squashed)
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        let minX = max(rect.minX, row.lowerBound)
        let maxX = min(rect.maxX, max(minX, row.upperBound))
        return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ amount: CGFloat) -> CGRect {
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * amount }
        return CGRect(x: lerp(a.minX, b.minX), y: lerp(a.minY, b.minY),
                      width: lerp(a.width, b.width), height: lerp(a.height, b.height))
    }
}

/// The thumb under a hand: grabbed on the picked segment and dragged along the
/// row, it follows the pointer, and letting go picks the segment under its
/// middle (the way the system's segmented control and the page both do).
public enum SegmentThumbDrag {
    /// The thumb centred on `centerX`, as wide as the segments either side of
    /// that point blended by how far between them it is, kept inside the row.
    public static func frame(centerX: CGFloat, slots: [CGRect], row: ClosedRange<CGFloat>) -> CGRect {
        guard let first = slots.first, let last = slots.last else { return .zero }
        let width: CGFloat
        if centerX <= first.midX {
            width = first.width
        } else if centerX >= last.midX {
            width = last.width
        } else if let right = slots.firstIndex(where: { $0.midX >= centerX }), right > 0 {
            let left = slots[right - 1], next = slots[right]
            let span = next.midX - left.midX
            let amount = span > 0 ? (centerX - left.midX) / span : 0
            width = left.width + (next.width - left.width) * amount
        } else {
            width = first.width
        }
        let lowest = row.lowerBound
        let highest = max(lowest, row.upperBound - width)
        let x = min(max(centerX - width / 2, lowest), highest)
        return CGRect(x: x, y: first.minY, width: width, height: first.height)
    }

    /// The segment a thumb let go with its middle at `centerX` lands in: the
    /// nearest one that can be picked, or nil when none can.
    public static func landing(centerX: CGFloat, slots: [CGRect], available: [Bool]? = nil) -> Int? {
        slots.indices
            .filter { index in
                guard let available, available.indices.contains(index) else { return true }
                return available[index]
            }
            .min { abs(slots[$0].midX - centerX) < abs(slots[$1].midX - centerX) }
    }
}
