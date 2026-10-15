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
/// Since `icon-snapping-reaches-what-the-icon-mock-draws` the shapes already
/// drawn offer more than their points: their CENTRES pull like a point, and
/// their EDGES pull each axis like a keyline, so a second shape lines up with
/// the first or starts dead in its middle (the icon mock's step 6). And each of
/// the three pulls, whole units, keylines and geometry, can be turned off on
/// its own (`IconSnapChoices`, View ▸ Snap in Icons).
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
    /// The middles of the shapes already on the frame, on whole units only.
    /// They pull exactly as a point does.
    public let centers: [CGPoint]
    /// Whether a point nothing else caught rounds to a whole unit. Off, it
    /// stays exactly where it was put.
    public let grid: Bool

    /// - Parameters:
    ///   - keylines: whether the frame's keylines pull (only while shown).
    ///   - anchors: the points of the shapes already drawn.
    ///   - shapes: the boxes of the shapes already drawn: their edges and
    ///     middle lines pull each axis, their centres pull both.
    ///   - grid: whether everything else lands on a whole unit.
    public init(frame: CGRect, keylines: Bool = true, anchors: [CGPoint] = [],
                shapes: [CGRect] = [], grid: Bool = true) {
        self.frame = frame
        self.grid = grid
        let origin = frame.origin
        func whole(_ value: CGFloat, from start: CGFloat) -> Bool {
            let offset = value - start
            return offset.isFinite && abs(offset - offset.rounded()) < 1e-6
        }
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []
        if keylines, let guides = IconKeylines.guides(in: frame) {
            xs += [frame.minX, frame.maxX, guides.liveArea.minX, guides.liveArea.maxX,
                      guides.centerX]
            ys += [frame.minY, frame.maxY, guides.liveArea.minY, guides.liveArea.maxY,
                      guides.centerY]
            if let square = guides.squareKeyline {
                xs += [square.minX, square.maxX]
                ys += [square.minY, square.maxY]
            }
        }
        var middles: [CGPoint] = []
        for box in shapes where !box.isNull && box.minX.isFinite && box.minY.isFinite {
            xs += [box.minX, box.midX, box.maxX]
            ys += [box.minY, box.midY, box.maxY]
            middles.append(CGPoint(x: box.midX, y: box.midY))
        }
        xLines = Array(Set(xs.filter { whole($0, from: origin.x) })).sorted()
        yLines = Array(Set(ys.filter { whole($0, from: origin.y) })).sorted()
        func onUnits(_ point: CGPoint) -> Bool {
            whole(point.x, from: origin.x) && whole(point.y, from: origin.y)
        }
        self.anchors = anchors.filter(onUnits)
        var seen = Set<String>()
        self.centers = middles.filter(onUnits).filter { seen.insert("\($0.x),\($0.y)").inserted }
    }

    /// How far a magnet reaches at this zoom, in document points.
    func reach(zoom: CGFloat) -> CGFloat {
        let scale = zoom.isFinite && zoom > 0 ? zoom : 1
        return min(Self.pullRadius / scale, Self.largestPull)
    }

    /// Where a point put down at `point` lands: on another shape's point or
    /// centre when it is within reach of one, otherwise each axis on the
    /// nearest keyline or edge within reach, otherwise on the nearest whole
    /// unit (with the grid on) or exactly where it was put (with it off).
    public func point(nearest point: CGPoint, zoom: CGFloat) -> CGPoint {
        landing(nearest: point, zoom: zoom).point
    }

    /// Where a point lands, and whether anything put it there: a target, a
    /// line, or the units. A point nothing placed lands under the pointer, and
    /// a mark saying "here" would be news about nothing.
    public func landing(nearest point: CGPoint, zoom: CGFloat) -> (point: CGPoint, placed: Bool) {
        guard point.x.isFinite, point.y.isFinite else { return (point, false) }
        let reach = reach(zoom: zoom)
        var best: (point: CGPoint, distance: CGFloat)?
        for target in anchors + centers {
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (target, distance)
            }
        }
        if let best { return (best.point, true) }
        let x = axis(point.x, lines: xLines, from: frame.minX, reach: reach)
        let y = axis(point.y, lines: yLines, from: frame.minY, reach: reach)
        return (CGPoint(x: x.value, y: y.value), grid || x.caught || y.caught)
    }

    private func axis(_ value: CGFloat, lines: [CGFloat], from start: CGFloat,
                      reach: CGFloat) -> (value: CGFloat, caught: Bool) {
        let nearest = lines.min { abs($0 - value) < abs($1 - value) }
        if let nearest, abs(nearest - value) <= reach { return (nearest, true) }
        return (grid ? start + (value - start).rounded() : value, false)
    }

    /// The place a point is at, in the icon's own units counted from its
    /// corner, the way the readout beside the pointer says it: "15, 13".
    /// Whole units print whole; a point nothing rounded prints to two places.
    public func readout(for point: CGPoint) -> String {
        func unit(_ value: CGFloat) -> String {
            let hundredths = (value * 100).rounded() / 100
            if hundredths == hundredths.rounded() { return String(Int(hundredths)) }
            var text = String(format: "%.2f", Double(hundredths))
            while text.hasSuffix("0") { text.removeLast() }
            return text
        }
        return "\(unit(point.x - frame.minX)), \(unit(point.y - frame.minY))"
    }

    /// A handle pulled out of a point, as an offset from it, ending on a whole
    /// unit. One held at 45 degrees stays at 45: both sides round to the same
    /// length, so the angle ⇧ is holding survives. With the grid off a handle
    /// ends where it was pulled.
    public func offset(_ offset: CGPoint) -> CGPoint {
        guard grid, offset.x.isFinite, offset.y.isFinite else { return offset }
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
    /// now; `choices` is which of the three pulls are on. The targets offered
    /// are those of every unturned path and shape on the frame: a path's
    /// points, a box's corners, an oval's four quarter points, a line's ends,
    /// and the box round each for its edges and centre. A shape that has been
    /// rotated, skewed or flipped draws itself somewhere its numbers do not
    /// say, so it offers none. `excluding` is the layer being reshaped, which
    /// should not pull towards where it already is.
    public func iconSnap(at point: CGPoint, keylines: Bool,
                         choices: IconSnapChoices = .all,
                         excluding: UUID? = nil) -> IconSnap? {
        guard let id = iconFrameID(under: point), let box = canvasFrame(of: id),
              let frame = layer(id: id) else { return nil }
        var anchors: [CGPoint] = []
        var shapes: [CGRect] = []
        func gather(_ children: [Layer], at origin: CGPoint) {
            for child in children where child.isVisible && child.id != excluding {
                let placed = CGPoint(x: origin.x + child.frame.origin.x,
                                     y: origin.y + child.frame.origin.y)
                func at(_ local: CGPoint) -> CGPoint {
                    CGPoint(x: placed.x + local.x, y: placed.y + local.y)
                }
                if child.isGroup {
                    gather(child.children, at: placed)
                } else if !child.transform.isIdentity {
                    continue
                } else if let path = child.path {
                    let points = path.anchors.map { at($0.point) }
                    anchors += points
                    if let bounds = Self.bounds(of: points) { shapes.append(bounds) }
                } else if let annotation = child.annotation {
                    let start = at(annotation.start)
                    let end = at(annotation.end)
                    let bounds = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                        width: abs(end.x - start.x),
                                        height: abs(end.y - start.y))
                    switch annotation.shape {
                    case .rectangle, .highlight:
                        anchors += [CGPoint(x: bounds.minX, y: bounds.minY),
                                    CGPoint(x: bounds.maxX, y: bounds.minY),
                                    CGPoint(x: bounds.minX, y: bounds.maxY),
                                    CGPoint(x: bounds.maxX, y: bounds.maxY)]
                    case .ellipse:
                        anchors += [CGPoint(x: bounds.midX, y: bounds.minY),
                                    CGPoint(x: bounds.maxX, y: bounds.midY),
                                    CGPoint(x: bounds.midX, y: bounds.maxY),
                                    CGPoint(x: bounds.minX, y: bounds.midY)]
                    default:
                        anchors += [start, end]
                    }
                    shapes.append(bounds)
                }
            }
        }
        if choices.geometry { gather(frame.children, at: box.origin) }
        return IconSnap(frame: box, keylines: keylines && choices.keylines,
                        anchors: anchors, shapes: shapes, grid: choices.grid)
    }

    private static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var box = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { box = box.union(CGRect(origin: point, size: .zero)) }
        return box
    }
}

/// Which pulls snapping has inside an icon frame: whole units ("Grid"), the
/// frame's keylines, and the shapes already drawn ("Geometry"), the three
/// choices under Snap to in the icon mock. All on until somebody turns one off;
/// the app keeps the choice as a preference, true of every icon at once.
public struct IconSnapChoices: Equatable, Hashable, Sendable, Codable {
    public var grid: Bool
    public var keylines: Bool
    public var geometry: Bool

    public init(grid: Bool = true, keylines: Bool = true, geometry: Bool = true) {
        self.grid = grid
        self.keylines = keylines
        self.geometry = geometry
    }

    public static let all = IconSnapChoices()
}
