import CoreGraphics
import Foundation

/// A corner of a rectangular surface, in reading order of preference.
public enum CanvasCorner: String, CaseIterable, Hashable, Codable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// Parks a floating panel (the measure legend, and anything like it) in a
/// corner that is actually free.
///
/// A key that sits on top of the very measurements it is explaining makes the
/// same mistake a callout covering its subject makes (UX-PATTERNS D14), so the
/// panel takes the first corner nothing is under, rather than always the same
/// one.
public enum CornerPlacement {

    /// The first corner in `order` where a `size` box, inset from the edges by
    /// `inset`, lands clear of everything in `occupied` and in `blocked`. All
    /// rects are in the surface's own top-left-origin space.
    ///
    /// The two lists differ in what gives when every corner is busy.
    /// `occupied` is content (the measurements the legend explains): a corner
    /// over one is a last resort. `blocked` is chrome drawn on top of the
    /// panel (the tool bar, the notice pill): a corner under it is never
    /// taken, since a panel behind the tool bar is simply invisible. So the
    /// walk is: a corner clear of both, else a corner clear of the chrome,
    /// else the first corner in `order`, which is where the user last saw it.
    public static func firstClear(size: CGSize, in bounds: CGSize, inset: CGFloat,
                                  avoiding occupied: [CGRect],
                                  blocked: [CGRect] = [],
                                  order: [CanvasCorner] = CanvasCorner.allCases) -> CanvasCorner {
        guard let fallback = order.first else { return .topLeading }
        let frames = order.map { ($0, frame(for: $0, size: size, in: bounds, inset: inset)) }
        let open = frames.filter { _, rect in !blocked.contains(where: { $0.intersects(rect) }) }
        if let clear = open.first(where: { _, rect in
            !occupied.contains(where: { $0.intersects(rect) }) }) { return clear.0 }
        return open.first?.0 ?? fallback
    }

    /// Where a `size` box sits when parked in `corner`.
    public static func frame(for corner: CanvasCorner, size: CGSize, in bounds: CGSize,
                             inset: CGFloat) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeading:      x = inset;                              y = inset
        case .topTrailing:     x = bounds.width - size.width - inset;  y = inset
        case .bottomLeading:   x = inset;                              y = bounds.height - size.height - inset
        case .bottomTrailing:  x = bounds.width - size.width - inset;  y = bounds.height - size.height - inset
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
