import CoreGraphics
import Foundation

/// The eight resize handles around a selected layer's frame.
public enum ResizeHandle: String, CaseIterable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    public var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    public var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    public var movesMinY: Bool { self == .topLeft || self == .top || self == .topRight }
    public var movesMaxY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    public var isCorner: Bool {
        (movesMinX || movesMaxX) && (movesMinY || movesMaxY)
    }

    /// The handle diagonally/axis opposite this one — the anchor that should stay
    /// put during a resize.
    public var opposite: ResizeHandle {
        switch self {
        case .topLeft: .bottomRight
        case .top: .bottom
        case .topRight: .bottomLeft
        case .left: .right
        case .right: .left
        case .bottomLeft: .topRight
        case .bottom: .top
        case .bottomRight: .topLeft
        }
    }
}

/// Handle placement, hit-testing, and resize math — all in document
/// coordinates, with hit tolerance expressed in screen points so handles feel
/// the same size at any zoom.
public enum Handles {
    /// Where a handle sits on the frame (corners and edge midpoints).
    public static func point(for handle: ResizeHandle, in frame: CGRect) -> CGPoint {
        let x = handle.movesMinX ? frame.minX : (handle.movesMaxX ? frame.maxX : frame.midX)
        let y = handle.movesMinY ? frame.minY : (handle.movesMaxY ? frame.maxY : frame.midY)
        return CGPoint(x: x, y: y)
    }

    /// The handle under a document-space point, if any. Nearest wins.
    public static func hit(at p: CGPoint, frame: CGRect, zoom: CGFloat,
                           screenTolerance: CGFloat = 6) -> ResizeHandle? {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        var best: (handle: ResizeHandle, distance: CGFloat)?
        for handle in ResizeHandle.allCases {
            let hp = point(for: handle, in: frame)
            let distance = hypot(p.x - hp.x, p.y - hp.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (handle, distance)
            }
        }
        return best?.handle
    }

    /// The frame after dragging `handle` to `p`. The opposite edge/corner stays
    /// anchored; the rect never inverts (clamped at `minSize`). With
    /// `preserveAspect` (⇧), corners scale uniformly by the dominant axis and
    /// edges scale the cross axis around its center.
    public static func resize(_ frame: CGRect, dragging handle: ResizeHandle, to p: CGPoint,
                              preserveAspect: Bool, minSize: CGFloat = 1) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if handle.movesMinX { minX = min(p.x, maxX - minSize) }
        if handle.movesMaxX { maxX = max(p.x, minX + minSize) }
        if handle.movesMinY { minY = min(p.y, maxY - minSize) }
        if handle.movesMaxY { maxY = max(p.y, minY + minSize) }
        var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        guard preserveAspect, frame.width > 0, frame.height > 0 else { return r }
        if handle.isCorner {
            let scale = max(r.width / frame.width, r.height / frame.height)
            let w = max(frame.width * scale, minSize)
            let h = max(frame.height * scale, minSize)
            r = CGRect(x: handle.movesMinX ? frame.maxX - w : frame.minX,
                       y: handle.movesMinY ? frame.maxY - h : frame.minY,
                       width: w, height: h)
        } else if handle.movesMinX || handle.movesMaxX {
            let h = max(frame.height * (r.width / frame.width), minSize)
            r.origin.y = frame.midY - h / 2
            r.size.height = h
        } else {
            let w = max(frame.width * (r.height / frame.height), minSize)
            r.origin.x = frame.midX - w / 2
            r.size.width = w
        }
        return r
    }

    /// Shift `newFrame` so the corner/edge opposite `handle` stays fixed in
    /// **screen** space under `transform`. Frame resize anchors the opposite
    /// corner in untransformed space, but a rotated/skewed layer is drawn around
    /// its frame *center* — which moves when the frame resizes — so without this
    /// the anchored corner swings on screen (the "resize after rotate is broken"
    /// bug). Identity transforms are returned unchanged. Works for any `newFrame`
    /// (including one whose height was re-derived, e.g. text re-wrap), since it
    /// only adds a translation.
    public static func anchoredFrame(start: CGRect, proposed newFrame: CGRect,
                                     handle: ResizeHandle, transform: LayerTransform) -> CGRect {
        guard !transform.isIdentity else { return newFrame }
        let anchor = handle.opposite
        let oldCenter = CGPoint(x: start.midX, y: start.midY)
        let newCenter = CGPoint(x: newFrame.midX, y: newFrame.midY)
        let screenOld = point(for: anchor, in: start)
            .applying(transform.affineTransform(around: oldCenter))
        let screenNew = point(for: anchor, in: newFrame)
            .applying(transform.affineTransform(around: newCenter))
        return newFrame.offsetBy(dx: screenOld.x - screenNew.x, dy: screenOld.y - screenNew.y)
    }
}
