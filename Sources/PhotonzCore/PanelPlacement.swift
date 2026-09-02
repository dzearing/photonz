import CoreGraphics
import Foundation

/// Where a floating panel can park on a rectangular surface, in order of
/// preference: the four corners first, since a corner is where a key
/// conventionally lives, then the middle of the leading edge and of the
/// trailing edge as the places it steps to when every corner is taken.
public enum PanelAnchor: String, CaseIterable, Hashable, Codable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case leading
    case trailing
}

/// Parks a floating panel (the measure legend, and anything like it) in a
/// slot that is actually free.
///
/// A key that sits on top of the very measurements it is explaining makes the
/// same mistake a callout covering its subject makes (UX-PATTERNS D14), so the
/// panel takes the first slot nothing is under, rather than always the same
/// one. The slots are a fixed handful (`PanelAnchor`) rather than a position
/// slid to wherever there happens to be room: a panel that followed the gaps
/// would creep along after every measurement dragged near it.
public enum PanelPlacement {

    /// The first anchor in `order` where a `size` box, inset from the edges by
    /// `inset`, lands clear of everything in `occupied` and in `blocked`. All
    /// rects are in the surface's own top-left-origin space.
    ///
    /// The two lists differ in what gives when every slot is busy.
    /// `occupied` is content (the measurements the legend explains): a slot
    /// over one is a last resort. `blocked` is chrome drawn on top of the
    /// panel (the tool bar, the notice pill): a slot under it is never
    /// taken, since a panel behind the tool bar is simply invisible. So the
    /// walk is: a slot clear of both, else a slot clear of the chrome, else
    /// the first anchor in `order`, which is where the user last saw it.
    public static func firstClear(size: CGSize, in bounds: CGSize, inset: CGFloat,
                                  avoiding occupied: [CGRect],
                                  blocked: [CGRect] = [],
                                  order: [PanelAnchor] = PanelAnchor.allCases) -> PanelAnchor {
        guard let fallback = order.first else { return .topLeading }
        let frames = order.map { ($0, frame(for: $0, size: size, in: bounds, inset: inset)) }
        let open = frames.filter { _, rect in !blocked.contains(where: { $0.intersects(rect) }) }
        if let clear = open.first(where: { _, rect in
            !occupied.contains(where: { $0.intersects(rect) }) }) { return clear.0 }
        return open.first?.0 ?? fallback
    }

    /// Where a `size` box sits when parked at `anchor`. Corners sit `inset`
    /// off both of their edges; the edge slots sit `inset` off their edge,
    /// centred along it.
    public static func frame(for anchor: PanelAnchor, size: CGSize, in bounds: CGSize,
                             inset: CGFloat) -> CGRect {
        let leadingX = inset
        let trailingX = bounds.width - size.width - inset
        let middleY = (bounds.height - size.height) / 2
        let x: CGFloat
        let y: CGFloat
        switch anchor {
        case .topLeading:      x = leadingX;   y = inset
        case .topTrailing:     x = trailingX;  y = inset
        case .bottomLeading:   x = leadingX;   y = bounds.height - size.height - inset
        case .bottomTrailing:  x = trailingX;  y = bounds.height - size.height - inset
        case .leading:         x = leadingX;   y = middleY
        case .trailing:        x = trailingX;  y = middleY
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
