import CoreGraphics
import Foundation

/// Where a point put down inside an icon frame really lands
/// (`pen-points-in-an-icon-frame-land-on-whole-units`).
///
/// An icon grid IS pixels: a point half way across one is the smear the frame
/// exists to help somebody avoid, and an SVG that says 3.3 where the drawing
/// meant 3 is not a clean file. So inside an icon frame every point the Pen
/// puts down lands on a WHOLE UNIT, counted from the frame's own corner, with
/// no setting to find first. The canvas grid does not get a say in there: four
/// points apart, it could only ever reach one unit in four.
///
/// Two things pull harder than plain rounding, because they are what a person
/// drawing an icon is actually aiming at:
///
/// - **another shape's point**, so a second shape meets the first exactly;
/// - **a keyline** (the frame's edges, the live area, the square, the centre
///   lines), each axis on its own, so an edge sits ON the margin rather than a
///   unit beside it. Only while the keylines are showing: a pull towards a line
///   nobody can see is what made snapping feel broken elsewhere in the app.
///
/// Both pull from a few points on SCREEN, never more than one unit, so zoomed
/// out they catch a point the hand cannot place precisely, and zoomed in, where
/// a unit is a big target, rounding alone decides. A target that is not itself
/// on a whole unit (the centre of an odd sized frame, a point somebody dragged
/// with ⌘ held) is never offered, which is what keeps the promise whole.
///
/// ⌘ still means "exactly where I put it", here as everywhere on the canvas;
/// that is the Pen's to honour (`PenSession.free`).
public struct IconSnap: Equatable, Sendable {

    /// How far a keyline or a point reaches out to catch the pointer, ON
    /// SCREEN. The forgiveness the rest of the canvas's magnets give.
    public static let pullRadius: CGFloat = 6

    /// The most a magnet ever reaches, in units, however far out the view is.
    /// A unit further would make the units next to a keyline unreachable.
    public static let largestPull: CGFloat = 1

    /// The icon frame, in canvas coordinates. Units count from its corner.
    public let frame: CGRect
    /// The keylines running down the frame (their x) and across it (their y),
    /// on whole units only. Empty when the guides are switched off.
    public let xLines: [CGFloat]
    public let yLines: [CGFloat]
    /// The points of the shapes already on the frame, on whole units only.
    public let anchors: [CGPoint]

    public init(frame: CGRect, keylines: Bool = true, anchors: [CGPoint] = []) {
        self.frame = frame
        let origin = frame.origin
        func whole(_ value: CGFloat, from start: CGFloat) -> Bool {
            let offset = value - start
            return offset.isFinite && abs(offset - offset.rounded()) < 1e-6
        }
        if keylines, let guides = IconKeylines.guides(in: frame) {
            var xs = [frame.minX, frame.maxX, guides.liveArea.minX, guides.liveArea.maxX,
                      guides.centerX]
            var ys = [frame.minY, frame.maxY, guides.liveArea.minY, guides.liveArea.maxY,
                      guides.centerY]
            if let square = guides.squareKeyline {
                xs += [square.minX, square.maxX]
                ys += [square.minY, square.maxY]
            }
            xLines = Array(Set(xs.filter { whole($0, from: origin.x) })).sorted()
            yLines = Array(Set(ys.filter { whole($0, from: origin.y) })).sorted()
        } else {
            xLines = []
            yLines = []
        }
        self.anchors = anchors.filter { whole($0.x, from: origin.x) && whole($0.y, from: origin.y) }
    }

    /// How far a magnet reaches at this zoom, in document points.
    func reach(zoom: CGFloat) -> CGFloat {
        let scale = zoom.isFinite && zoom > 0 ? zoom : 1
        return min(Self.pullRadius / scale, Self.largestPull)
    }

    /// Where a point put down at `point` lands: on another shape's point when
    /// it is within reach of one, otherwise each axis on the nearest keyline
    /// within reach, otherwise on the nearest whole unit.
    public func point(nearest point: CGPoint, zoom: CGFloat) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else { return point }
        let reach = reach(zoom: zoom)
        var best: (point: CGPoint, distance: CGFloat)?
        for anchor in anchors {
            let distance = hypot(anchor.x - point.x, anchor.y - point.y)
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (anchor, distance)
            }
        }
        if let best { return best.point }
        return CGPoint(x: axis(point.x, lines: xLines, from: frame.minX, reach: reach),
                       y: axis(point.y, lines: yLines, from: frame.minY, reach: reach))
    }

    private func axis(_ value: CGFloat, lines: [CGFloat], from start: CGFloat,
                      reach: CGFloat) -> CGFloat {
        let nearest = lines.min { abs($0 - value) < abs($1 - value) }
        if let nearest, abs(nearest - value) <= reach { return nearest }
        return start + (value - start).rounded()
    }

    /// A handle pulled out of a point, as an offset from it, ending on a whole
    /// unit. One held at 45 degrees stays at 45: both sides round to the same
    /// length, so the angle ⇧ is holding survives.
    public func offset(_ offset: CGPoint) -> CGPoint {
        guard offset.x.isFinite, offset.y.isFinite else { return offset }
        if offset.x != 0, offset.y != 0, abs(abs(offset.x) - abs(offset.y)) < 1e-6 {
            let side = abs(offset.x).rounded()
            return CGPoint(x: offset.x < 0 ? -side : side, y: offset.y < 0 ? -side : side)
        }
        return CGPoint(x: offset.x.rounded(), y: offset.y.rounded())
    }
}

extension PhotonzDocument {

    /// What a Pen point at `point` lands on, or nil when the point is not
    /// inside an icon frame (a screen, bare canvas, a document of
    /// screenshots), where the Pen behaves exactly as it always has.
    ///
    /// `keylines` is whether the canvas is drawing the frame's guides right
    /// now. The points offered are those of every unturned path on the frame;
    /// a shape that has been rotated, skewed or flipped draws its points
    /// somewhere its numbers do not say, so it offers none.
    public func iconSnap(at point: CGPoint, keylines: Bool) -> IconSnap? {
        guard let id = iconFrameID(under: point), let box = canvasFrame(of: id),
              let frame = layer(id: id) else { return nil }
        var anchors: [CGPoint] = []
        func gather(_ children: [Layer], at origin: CGPoint) {
            for child in children where child.isVisible {
                let placed = CGPoint(x: origin.x + child.frame.origin.x,
                                     y: origin.y + child.frame.origin.y)
                if child.isGroup {
                    gather(child.children, at: placed)
                } else if let path = child.path, child.transform.isIdentity {
                    anchors += path.anchors.map {
                        CGPoint(x: placed.x + $0.point.x, y: placed.y + $0.point.y)
                    }
                }
            }
        }
        gather(frame.children, at: box.origin)
        return IconSnap(frame: box, keylines: keylines, anchors: anchors)
    }
}
