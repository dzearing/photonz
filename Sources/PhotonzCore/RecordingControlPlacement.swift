import CoreGraphics

/// Where the person left the floating recording control (timer and Stop),
/// kept as a distance from the nearest corner of the screen's visible area so
/// it lands in the same corner on a screen of another size.
public struct RecordingControlSpot: Codable, Sendable, Hashable {
    public enum Corner: String, Codable, Sendable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
    }

    public var corner: Corner
    /// Points from the corner's left or right edge to the control's window.
    public var fromSide: Double
    /// Points from the corner's top or bottom edge to the control's window.
    public var fromEnd: Double

    public init(corner: Corner, fromSide: Double, fromEnd: Double) {
        self.corner = corner
        self.fromSide = fromSide
        self.fromEnd = fromEnd
    }
}

/// Lays out the recording control's window. Everything is in screen points
/// with y going up, AppKit's screen space; `visible` is the screen's area
/// clear of the menu bar and the Dock.
public enum RecordingControlPlacement {
    /// The control's window, clear padding included.
    public static let size = CGSize(width: 232, height: 52)
    /// The clear padding between the window's edge and the glass a person sees.
    public static let glassInset: CGFloat = 6
    /// How far in from the screen's edges the glass sits when it has never been moved.
    public static let margin: CGFloat = 16
    /// How far outside a recorded region the control is put when it would cover it.
    public static let regionGap: CGFloat = 12

    /// Bottom left, the glass 16 pt in from both edges.
    public static var defaultSpot: RecordingControlSpot {
        let gap = Double(margin - glassInset)
        return RecordingControlSpot(corner: .bottomLeft, fromSide: gap, fromEnd: gap)
    }

    /// The control's frame for `spot` (the default when nil), pulled inside
    /// `visible`, and moved outside `region` when it would sit over it.
    public static func frame(spot: RecordingControlSpot?, visible: CGRect, region: CGRect? = nil) -> CGRect {
        let spot = spot ?? defaultSpot
        let x = spot.corner.isLeft ? visible.minX + spot.fromSide : visible.maxX - spot.fromSide - size.width
        let y = spot.corner.isTop ? visible.maxY - spot.fromEnd - size.height : visible.minY + spot.fromEnd
        let placed = clamped(CGRect(origin: CGPoint(x: x, y: y), size: size), into: visible)
        guard let region else { return placed }
        return clear(of: region, placed, visible: visible)
    }

    /// The spot a control let go at `frame` is remembered as: measured from
    /// whichever corner of `visible` its middle is nearest.
    public static func spot(for frame: CGRect, visible: CGRect) -> RecordingControlSpot {
        let left = frame.midX < visible.midX
        let top = frame.midY > visible.midY
        let corner: RecordingControlSpot.Corner = top ? (left ? .topLeft : .topRight)
                                                       : (left ? .bottomLeft : .bottomRight)
        let fromSide = left ? frame.minX - visible.minX : visible.maxX - frame.maxX
        let fromEnd = top ? visible.maxY - frame.maxY : frame.minY - visible.minY
        return RecordingControlSpot(corner: corner, fromSide: Double(fromSide), fromEnd: Double(fromEnd))
    }

    /// `frame` moved the least it takes to sit wholly inside `visible`.
    public static func clamped(_ frame: CGRect, into visible: CGRect) -> CGRect {
        let x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return CGRect(origin: CGPoint(x: max(x, visible.minX), y: max(y, visible.minY)), size: frame.size)
    }

    /// `frame` moved straight out of `region` the shortest way that still
    /// fits inside `visible`: over the region's left, right, top or bottom
    /// edge, `regionGap` clear of it. Left where it is when it does not touch
    /// the region, or when no way out fits (a region filling the screen).
    public static func clear(of region: CGRect, _ frame: CGRect, visible: CGRect) -> CGRect {
        guard frame.intersects(region) else { return frame }
        let candidates = [
            CGPoint(x: region.minX - regionGap - frame.width, y: frame.minY),
            CGPoint(x: region.maxX + regionGap, y: frame.minY),
            CGPoint(x: frame.minX, y: region.minY - regionGap - frame.height),
            CGPoint(x: frame.minX, y: region.maxY + regionGap),
        ].map { CGRect(origin: $0, size: frame.size) }
        let fitting = candidates.filter { visible.contains($0) }
        let nearest = fitting.min {
            hypot($0.minX - frame.minX, $0.minY - frame.minY) < hypot($1.minX - frame.minX, $1.minY - frame.minY)
        }
        return nearest ?? frame
    }

    /// A region as the region overlay reports it (points from the display's
    /// top left) in screen points with y going up.
    public static func screenRect(ofRegion region: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + region.minX, y: screenFrame.maxY - region.maxY,
               width: region.width, height: region.height)
    }
}
