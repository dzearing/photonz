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

/// Where a frame's handles go, once the frame's size has had its say.
///
/// Eight handles round a comfortable box are eight separate targets. Round a
/// two letter label they are one solid mass covering the label, so there is
/// nowhere left to grab it and drag it. The answer, and it is the one every
/// design tool settles on: when a box is cramped, its handles stop sitting on
/// it and step outside, and the four edge midpoints — the ones that crowd the
/// corners — drop away, leaving corners only.
///
/// Cramped is measured in SCREEN points, because a handle is a screen-sized
/// thing: the same layer is roomy zoomed in and cramped zoomed out, and the
/// handles follow.
public struct HandleLayout: Equatable, Sendable {
    /// The frame the handles belong to, in document coordinates.
    public let frame: CGRect
    /// The handles this frame actually offers, in `ResizeHandle.allCases` order.
    public let handles: [ResizeHandle]
    /// How far each axis pushes its handles out past the outline, in document
    /// units. Zero on an axis with room to spare.
    public let outset: CGSize

    public init(frame: CGRect, handles: [ResizeHandle], outset: CGSize) {
        self.frame = frame
        self.handles = handles
        self.outset = outset
    }

    /// Whether this frame offers `handle` at all.
    public func offers(_ handle: ResizeHandle) -> Bool { handles.contains(handle) }

    /// Where `handle` sits: on the frame, nudged outward on any cramped axis.
    /// A midpoint has no outward direction on its own axis, so it stays put
    /// there and only moves on the axis it straddles.
    public func point(for handle: ResizeHandle) -> CGPoint {
        let base = Handles.point(for: handle, in: frame)
        let dx = handle.movesMinX ? -outset.width : (handle.movesMaxX ? outset.width : 0)
        let dy = handle.movesMinY ? -outset.height : (handle.movesMaxY ? outset.height : 0)
        return CGPoint(x: base.x + dx, y: base.y + dy)
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

    /// A frame is CRAMPED on an axis once it spans fewer than this many screen
    /// points.
    ///
    /// Forty is where an edge midpoint earns its place. A handle is an eight
    /// point square, so three of them along a forty point edge leave twelve
    /// points of air either side of the middle one: three separate targets you
    /// can tell apart and aim at. Any tighter and they read as one solid bar
    /// laid over the object, which is the complaint this whole rule exists to
    /// answer — a two letter label wearing a lattice is no better than a two
    /// letter label wearing eight squares.
    public static let crampedSpan: CGFloat = 40

    /// How far outside the outline a cramped axis pushes its handles, in
    /// screen points — half a handle plus the outline, so the square clears
    /// the edge it belongs to instead of sitting on top of the object.
    public static let crampedOutset: CGFloat = 5

    /// How the handles arrange themselves round `frame` at this zoom.
    ///
    /// Drawing and hit-testing both read this, so a handle is a target exactly
    /// where it is a picture.
    public static func layout(in frame: CGRect, zoom: CGFloat) -> HandleLayout {
        let z = zoom > 0 ? zoom : 1
        let crampedX = frame.width * z < crampedSpan
        let crampedY = frame.height * z < crampedSpan
        return HandleLayout(
            frame: frame,
            // Edge midpoints sit BETWEEN the corners, so they are the ones a
            // cramped axis crowds — on either axis, since a midpoint on the
            // long side is just as close to the corners of the short one.
            handles: crampedX || crampedY
                ? ResizeHandle.allCases.filter(\.isCorner)
                : ResizeHandle.allCases,
            outset: CGSize(width: crampedX ? crampedOutset / z : 0,
                           height: crampedY ? crampedOutset / z : 0))
    }

    /// The clear strip that has to survive down the middle of a box once both
    /// its edges on that axis have taken their grab band, in screen points.
    ///
    /// A picked object is picked UP by pressing its middle, so an edge may
    /// only claim a band while there is still a middle left to press. Twenty
    /// is a handle and its air. On a one line label, twenty nine points tall,
    /// it is what keeps the top and bottom edges off the words while the left
    /// and right edges — the two that set where the words wrap, and the whole
    /// reason a label gets resized — stay live down their whole run.
    public static let edgeGrabInterior: CGFloat = 20

    /// The shortest stretch of an edge, clear of its own two corners, that is
    /// worth aiming at, in screen points. Below this the corners have the edge
    /// between them and there is nothing left in the middle to aim for.
    public static let edgeGrabRun: CGFloat = 8

    /// The stretch of `edge` that answers to a press: the edge's own line,
    /// shortened at both ends by whatever its corner squares already claim.
    /// Nil when this edge offers no band — the box is too narrow across to
    /// spare the room, or its corners have the whole edge between them.
    ///
    /// This is the one handle that is not a square. A square in the middle of
    /// an edge needs a long edge to sit on, and a one line label does not have
    /// one: its two corners claim the entire side, so the width the words wrap
    /// at had nothing to take hold of and pulling the side slid the label
    /// across the canvas. Every drawing tool answers this the same way, by
    /// making the OUTLINE itself the handle, and the outline is drawn at every
    /// size — with the pointer turning into resize arrows over it, which is
    /// the invitation a square would have been.
    public static func grabRun(for edge: ResizeHandle, in frame: CGRect, zoom: CGFloat,
                               screenTolerance: CGFloat = 6) -> (from: CGPoint, to: CGPoint)? {
        guard !edge.isCorner else { return nil }
        let z = zoom > 0 ? zoom : 1
        let tolerance = screenTolerance / z
        let outset = layout(in: frame, zoom: zoom).outset
        let vertical = edge.movesMinX || edge.movesMaxX
        // A corner sits `across` the edge's line and `along` past its end, so
        // this is how far up the edge the corner's tolerance still reaches.
        let across = vertical ? outset.width : outset.height
        let along = vertical ? outset.height : outset.width
        let reach = max(0, max(0, tolerance * tolerance - across * across).squareRoot() - along)
        let run = (vertical ? frame.height : frame.width) - reach * 2
        let interior = vertical ? frame.width : frame.height
        guard run * z >= edgeGrabRun,
              interior * z >= screenTolerance * 2 + edgeGrabInterior else { return nil }
        if vertical {
            let x = edge.movesMinX ? frame.minX : frame.maxX
            return (CGPoint(x: x, y: frame.minY + reach), CGPoint(x: x, y: frame.maxY - reach))
        }
        let y = edge.movesMinY ? frame.minY : frame.maxY
        return (CGPoint(x: frame.minX + reach, y: y), CGPoint(x: frame.maxX - reach, y: y))
    }

    /// The handle under a document-space point, if any. Nearest wins. Only the
    /// handles the layout actually offers can be hit: an edge handle a cramped
    /// frame does not draw is not a press either.
    ///
    /// With `edgeGrab`, a press that found no square falls back to the four
    /// edges, each live down its whole run (`grabRun`). The squares are still
    /// read first, so a corner always beats the edge it ends.
    public static func hit(at p: CGPoint, frame: CGRect, zoom: CGFloat,
                           screenTolerance: CGFloat = 6,
                           edgeGrab: Bool = false) -> ResizeHandle? {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        let arrangement = layout(in: frame, zoom: zoom)
        var best: (handle: ResizeHandle, distance: CGFloat)?
        for handle in arrangement.handles {
            let hp = arrangement.point(for: handle)
            let distance = hypot(p.x - hp.x, p.y - hp.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (handle, distance)
            }
        }
        if let best { return best.handle }
        guard edgeGrab else { return nil }
        var bestEdge: (handle: ResizeHandle, distance: CGFloat)?
        for edge in ResizeHandle.allCases where !edge.isCorner {
            guard let run = grabRun(for: edge, in: frame, zoom: zoom,
                                    screenTolerance: screenTolerance) else { continue }
            let distance = distance(from: p, toRunFrom: run.from, to: run.to)
            if distance <= tolerance, distance < (bestEdge?.distance ?? .infinity) {
                bestEdge = (edge, distance)
            }
        }
        return bestEdge?.handle
    }

    /// Distance from `p` to an axis-aligned segment, clamped to its ends.
    private static func distance(from p: CGPoint, toRunFrom a: CGPoint,
                                 to b: CGPoint) -> CGFloat {
        let x = min(max(p.x, min(a.x, b.x)), max(a.x, b.x))
        let y = min(max(p.y, min(a.y, b.y)), max(a.y, b.y))
        return hypot(p.x - x, p.y - y)
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
