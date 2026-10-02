import CoreGraphics

/// What a press takes hold of while a picked zoom's box is up on the picture.
///
/// One answer for both the press and the pointer, so the cursor resting on a
/// spot can never promise a different grab from the one the press makes. The
/// box keeps the frame's shape, so it resizes only from a corner: an edge is
/// part of the body.
public enum ZoomBoxHit: Hashable, Sendable {
    /// A corner handle: the box is drawn again from the opposite corner.
    case corner(ResizeHandle)
    /// Inside the box: carry it.
    case body
    /// On the clip, off the box: a drag draws a new box from here, a click
    /// lets the zoom go.
    case beside

    /// What a press at `p` takes, all in document points. `reach` is how near
    /// a corner counts as on it; nil when the press is off the clip and so
    /// not the box's at all.
    public static func at(_ p: CGPoint, box: CGRect, clip: CGRect, reach: CGFloat) -> ZoomBoxHit? {
        let box = box.standardized
        guard clip.standardized.insetBy(dx: -reach, dy: -reach).contains(p) else { return nil }
        let corners: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: box.minX, y: box.minY)),
            (.topRight, CGPoint(x: box.maxX, y: box.minY)),
            (.bottomRight, CGPoint(x: box.maxX, y: box.maxY)),
            (.bottomLeft, CGPoint(x: box.minX, y: box.maxY)),
        ]
        let nearest = corners
            .map { (handle: $0.0, distance: hypot($0.1.x - p.x, $0.1.y - p.y)) }
            .min { $0.distance < $1.distance }
        if let nearest, nearest.distance <= reach { return .corner(nearest.handle) }
        return box.contains(p) ? .body : .beside
    }

    /// The corner that stays put while this corner is pulled; nil for
    /// anything that is not a corner.
    public func anchor(of box: CGRect) -> CGPoint? {
        guard case .corner(let handle) = self else { return nil }
        let box = box.standardized
        switch handle {
        case .topLeft: return CGPoint(x: box.maxX, y: box.maxY)
        case .topRight: return CGPoint(x: box.minX, y: box.maxY)
        case .bottomRight: return CGPoint(x: box.minX, y: box.minY)
        case .bottomLeft: return CGPoint(x: box.maxX, y: box.minY)
        default: return nil
        }
    }

    /// The pointer that says so: the resize arrows on a corner, the open hand
    /// on the body. Nil beside the box, where the canvas shows a crosshair
    /// because a drag there draws.
    public var cue: CanvasPointerCue? {
        switch self {
        case .corner(let handle): .resize(handle)
        case .body: .grab
        case .beside: nil
        }
    }
}
