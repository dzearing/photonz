import CoreGraphics
import Foundation

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
