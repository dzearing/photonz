import CoreGraphics

/// The mark a point wears on the canvas, which says what KIND of point it is.
///
/// A smooth bend is round and a hard corner is square, so what a point IS can
/// be read off the canvas rather than remembered. A point curved on ONE side is
/// drawn half way between the two, which is what it is. Without a third mark it
/// would wear the hard corner's square — it IS a corner by kind, since its two
/// sides are not tied together — and a rounded corner in an icon would look
/// exactly like a sharp one until you dragged something.
///
/// The mark says WHETHER, not WHICH SIDE: the outline itself already shows
/// which run is straight, and a glyph turned to face the straight side read as
/// a diamond at eight points across rather than as anything anybody could name.
///
/// One answer for both places a point is drawn — the Pen as it places them and
/// reshaping once they are picked up — so a shape does not change its look the
/// moment you stop drawing it.
public enum PathAnchorMark: String, CaseIterable, Hashable, Sendable {
    case square
    case round
    case roundedSquare

    public init(_ anchor: PathAnchor) {
        if anchor.kind == .smooth {
            self = .round
        } else if anchor.isHalfSmooth {
            self = .roundedSquare
        } else {
            self = .square
        }
    }

    /// The mark as a shape filling the square `radius` either side of
    /// `centre`, in whatever space the caller draws in.
    public func path(centredOn centre: CGPoint, radius r: CGFloat) -> CGPath {
        let box = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        switch self {
        case .square:
            return CGPath(rect: box, transform: nil)
        case .round:
            return CGPath(ellipseIn: box, transform: nil)
        case .roundedSquare:
            // Rounded a little over half way to a circle: far enough that it
            // is not a square at eight points across, not so far that it is a
            // circle.
            return CGPath(roundedRect: box, cornerWidth: r * 0.6,
                          cornerHeight: r * 0.6, transform: nil)
        }
    }
}
