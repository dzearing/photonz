import CoreGraphics
import Foundation

/// The segmented control's thumb going from one option to another
/// (`docs/design/mocks/pages/comp-segmented.html`, `shared/components/segmented.js`).
///
/// The user, 2026-09-29: the thumb should "use liquid glass animation effect
/// when snapping between options". So a move is not a slide: the thumb first
/// stretches to span the slot it left and the slot it is going to, squashed a
/// little like a drop of liquid pulled along, then lets go of the far end,
/// runs a few points past its new slot and settles back.
///
/// Two rules the user added the same morning, both held here rather than in
/// the view so a test can hold them:
///
/// * **It never leaves the row, and never overshoots by more than a few
///   points**, however far it moves. The first try sprang in proportion to
///   the distance and threw the thumb out of the rail on a two-step move. The
///   settle is `min(maxSettle, 6% of the travel)`, clamped inside the row.
/// * **Position and size are one animation.** On the page the position ran on
///   one path and the width on another and they drifted apart, so the thumb
///   reached its slot still wide. Here every frame is one rect read off one
///   clock.
///
/// Interruptible: a second choice mid-flight starts a new morph from whatever
/// `frame(at:)` says right now.
public struct SegmentThumbMorph: Sendable, Equatable {
    /// The page's 420ms.
    public static let duration: TimeInterval = 0.42
    /// The furthest the thumb runs past its slot before settling.
    public static let maxSettle: CGFloat = 3
    /// How much the stretched thumb is squashed, about its middle.
    public static let squash: CGFloat = 0.88

    public var from: CGRect
    public var to: CGRect
    /// The horizontal room the thumb may use: the row of segments.
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
        let keys = keyframes
        // The page's keyframes: offsets 0, 0.4, 0.82, 1, each leg with its own curve.
        let legs: [(start: Double, end: Double, curve: (Double, Double, Double, Double))] = [
            (0, 0.4, (0.3, 0, 0.5, 1)),
            (0.4, 0.82, (0.22, 1, 0.36, 1)),
            (0.82, 1, (0.42, 0, 0.58, 1)),
        ]
        for (index, leg) in legs.enumerated() where t <= leg.end || index == legs.count - 1 {
            let local = (t - leg.start) / (leg.end - leg.start)
            let eased = CubicBezier.value(local, leg.curve.0, leg.curve.1, leg.curve.2, leg.curve.3)
            return Self.mix(keys[index], keys[index + 1], CGFloat(eased))
        }
        return to
    }

    /// The four shapes the thumb passes through: where it was, stretched over
    /// both slots, a few points past the new one, and home.
    private var keyframes: [CGRect] {
        let low = min(from.minX, to.minX)
        let high = max(from.maxX, to.maxX)
        let squashed = to.height * Self.squash
        let stretched = CGRect(x: low, y: to.midY - squashed / 2, width: high - low, height: squashed)
        let direction: CGFloat = to.minX >= from.minX ? 1 : -1
        let settle = min(Self.maxSettle, abs(to.minX - from.minX) * 0.06)
        let past = min(max(to.minX + direction * settle, row.lowerBound), max(row.lowerBound, row.upperBound - to.width))
        let beyond = CGRect(x: past, y: to.minY, width: to.width, height: to.height)
        return [from, stretched, beyond, to]
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
