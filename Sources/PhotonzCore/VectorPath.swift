import CoreGraphics
import Foundation

/// A shape that is any outline you like: as many anchors as you want, each one
/// a corner or a smooth bend, so a single shape can have straight edges and
/// curves in it. The foundation for drawing icons
/// (`docs/design/vector-paths.md`).
///
/// Everything here is geometry and nothing here draws: `PathRasterizer` in
/// PhotonzRender is the only thing that turns one of these into pixels.

// MARK: - An anchor

/// Which side of an anchor a handle is on.
public enum PathHandleSide: String, CaseIterable, Hashable, Codable, Sendable {
    /// The handle that shapes the run ARRIVING at this anchor.
    case handleIn
    /// The handle that shapes the run LEAVING it.
    case handleOut
}

/// What somebody meant an anchor to be, which is not the same question as what
/// its handles happen to be right now.
///
/// `corner` is two independent sides: drag one handle and the other holds
/// still, so a hard turn stays hard. `smooth` is the promise that the two stay
/// in line with each other, so the curve runs through the anchor without a
/// kink. Only the editing tools keep that promise — everything that DRAWS a
/// path reads the handles and never this — which is what lets a smooth anchor
/// carry unequal handle lengths, exactly as it does in every drawing app.
public enum PathAnchorKind: String, CaseIterable, Hashable, Codable, Sendable {
    case corner
    case smooth

    /// What the inspector calls it.
    public var title: String {
        switch self {
        case .corner: return "Corner"
        case .smooth: return "Smooth"
        }
    }
}

/// One point on a path, with up to two handles.
///
/// **Handles are stored RELATIVE to the anchor**, as an offset from `point`.
/// That is the decision the whole model turns on: moving an anchor then drags
/// its curve with it for free, mirroring one handle onto the other is a
/// negation rather than a reflection about a moving origin, and scaling a path
/// scales points and handles by exactly the same numbers.
///
/// **Either handle may be absent**, and that is what makes a HALF-SMOOTH anchor
/// expressible: `handleIn` nil with `handleOut` set is a point a straight edge
/// arrives at and a curve leaves from, which is the commonest thing in a real
/// icon. Both absent is a plain corner between two straight runs.
public struct PathAnchor: Hashable, Codable, Sendable {
    /// Where the anchor sits, in the layer's own top-left coordinates.
    public var point: CGPoint
    /// The handle shaping the run ARRIVING here, as an offset from `point`.
    /// Nil means that run arrives straight.
    public var handleIn: CGPoint?
    /// The handle shaping the run LEAVING here, as an offset from `point`.
    /// Nil means that run leaves straight.
    public var handleOut: CGPoint?
    /// Whether the two sides are meant to stay in line. See `PathAnchorKind`.
    public var kind: PathAnchorKind

    public init(point: CGPoint,
                handleIn: CGPoint? = nil,
                handleOut: CGPoint? = nil,
                kind: PathAnchorKind = .corner) {
        self.point = point
        self.handleIn = handleIn
        self.handleOut = handleOut
        self.kind = kind
    }

    /// The control point for the run arriving here, in layer coordinates.
    /// The anchor itself when that run arrives straight.
    public var controlIn: CGPoint {
        guard let handleIn else { return point }
        return CGPoint(x: point.x + handleIn.x, y: point.y + handleIn.y)
    }

    /// The control point for the run leaving here, in layer coordinates.
    public var controlOut: CGPoint {
        guard let handleOut else { return point }
        return CGPoint(x: point.x + handleOut.x, y: point.y + handleOut.y)
    }

    /// Curved on one side and straight on the other.
    public var isHalfSmooth: Bool { (handleIn == nil) != (handleOut == nil) }

    /// The handle on a side.
    public func handle(_ side: PathHandleSide) -> CGPoint? {
        side == .handleIn ? handleIn : handleOut
    }

    /// Puts the other handle back in line with the one named, keeping its own
    /// length — the mirrored-angle rule every drawing app uses, so a smooth
    /// anchor can be gentle on one side and sharp on the other.
    ///
    /// Does nothing on a corner (its two sides are independent by definition),
    /// and nothing where there is no other handle to align: a half-smooth
    /// anchor stays half-smooth rather than sprouting a handle nobody dragged.
    public mutating func alignHandles(keeping side: PathHandleSide) {
        guard kind == .smooth, let led = handle(side) else { return }
        let other: PathHandleSide = side == .handleIn ? .handleOut : .handleIn
        guard let follower = handle(other) else { return }
        let ledLength = hypot(led.x, led.y)
        guard ledLength > 0 else { return }
        let length = hypot(follower.x, follower.y)
        let aligned = CGPoint(x: -led.x / ledLength * length,
                              y: -led.y / ledLength * length)
        if other == .handleIn { handleIn = aligned } else { handleOut = aligned }
    }

    /// The same anchor with every number multiplied, which is what a resize
    /// does: the point moves and its handles grow with it, so the curve keeps
    /// its shape instead of flattening.
    func scaled(x: CGFloat, y: CGFloat) -> PathAnchor {
        func scale(_ handle: CGPoint?) -> CGPoint? {
            handle.map { CGPoint(x: $0.x * x, y: $0.y * y) }
        }
        return PathAnchor(point: CGPoint(x: point.x * x, y: point.y * y),
                          handleIn: scale(handleIn), handleOut: scale(handleOut),
                          kind: kind)
    }

    /// The same anchor shifted. Handles are offsets, so they do not move.
    func offsetBy(dx: CGFloat, dy: CGFloat) -> PathAnchor {
        var moved = self
        moved.point = CGPoint(x: point.x + dx, y: point.y + dy)
        return moved
    }
}

// MARK: - One run between two anchors

/// The stretch of outline between two anchors, always stated as a cubic. A run
/// with no handle on either end IS a straight line, and says so, so a straight
/// edge can be drawn straight rather than as a curve that happens to look flat.
public struct PathSegment: Hashable, Sendable {
    public let start: CGPoint
    public let control1: CGPoint
    public let control2: CGPoint
    public let end: CGPoint
    /// True when neither end has a handle: the run is a plain line.
    public let isStraight: Bool

    init(from: PathAnchor, to: PathAnchor) {
        start = from.point
        control1 = from.controlOut
        control2 = to.controlIn
        end = to.point
        isStraight = from.handleOut == nil && to.handleIn == nil
    }

    /// The tight box this run covers: where the curve actually goes, not where
    /// its control points sit.
    public var bounds: CGRect {
        guard !isStraight else {
            return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        }
        let x = Bezier.extent(start.x, control1.x, control2.x, end.x)
        let y = Bezier.extent(start.y, control1.y, control2.y, end.y)
        return CGRect(x: x.low, y: y.low, width: x.high - x.low, height: y.high - y.low)
    }
}

/// The cubic maths a path's bounds are worked out with, on one axis at a time.
enum Bezier {

    /// Where a cubic actually reaches on one axis, between its two ends and
    /// wherever it turns round in between.
    ///
    /// The turning points are the roots of the derivative, which is a
    /// quadratic; anything outside 0...1 is off the end of this run and does
    /// not count. Doing it this way rather than taking the control points'
    /// box matters: a handle 40 long only bulges 30, so a box drawn round the
    /// control points would put the selection outline well clear of the ink.
    static func extent(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat,
                       _ p3: CGFloat) -> (low: CGFloat, high: CGFloat) {
        var low = min(p0, p3), high = max(p0, p3)
        for t in turningPoints(p0, p1, p2, p3) {
            let v = value(p0, p1, p2, p3, at: t)
            low = min(low, v)
            high = max(high, v)
        }
        return (low, high)
    }

    /// How much area one run sweeps out about the origin: ∮(x dy − y dx)
    /// along it. Halve the sum over a closed outline and you have its area.
    ///
    /// Worked out exactly rather than by chopping the curve into little
    /// straight pieces. Both coordinates are cubic polynomials in t, so the
    /// integrand is a polynomial too and every term integrates to a fraction:
    /// a run that doubles back along itself cancels to a clean zero instead of
    /// to sampling noise, which is the one answer this has to get right.
    static func sweep(of run: PathSegment) -> CGFloat {
        let x = powers(run.start.x, run.control1.x, run.control2.x, run.end.x)
        let y = powers(run.start.y, run.control1.y, run.control2.y, run.end.y)
        // ∫₀¹ (x y′ − y x′) dt, pair of powers by pair of powers. The two
        // halves of a pair share a denominator, which is what collapses the
        // sixteen terms to six.
        var total: CGFloat = 0
        for i in 0..<4 {
            for j in (i + 1)..<4 {
                total += (x[i] * y[j] - x[j] * y[i]) * CGFloat(j - i) / CGFloat(i + j)
            }
        }
        return total
    }

    /// The same cubic written as plain powers of t, lowest first, rather than
    /// as four control points.
    static func powers(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat,
                       _ p3: CGFloat) -> [CGFloat] {
        [p0,
         3 * (p1 - p0),
         3 * (p0 - 2 * p1 + p2),
         -p0 + 3 * p1 - 3 * p2 + p3]
    }

    /// The cubic's value at `t`.
    static func value(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat,
                      at t: CGFloat) -> CGFloat {
        let u = 1 - t
        return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }

    /// The `t`s strictly inside the run where the curve stops going one way and
    /// starts going the other.
    static func turningPoints(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat,
                              _ p3: CGFloat) -> [CGFloat] {
        // B'(t)/3 = a t² + b t + c, with a, b, c off the three handle spans.
        let d1 = p1 - p0, d2 = p2 - p1, d3 = p3 - p2
        let a = d1 - 2 * d2 + d3
        let b = 2 * (d2 - d1)
        let c = d1
        func inside(_ t: CGFloat) -> Bool { t > 0 && t < 1 && t.isFinite }
        if abs(a) < 1e-12 {
            guard abs(b) > 1e-12 else { return [] }
            let t = -c / b
            return inside(t) ? [t] : []
        }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        let root = discriminant.squareRoot()
        return [(-b + root) / (2 * a), (-b - root) / (2 * a)].filter(inside)
    }
}

// MARK: - The shape itself

/// How a path decides what is inside it when its outline crosses itself, which
/// is how an icon gets a hole in it.
public enum PathFillRule: String, CaseIterable, Hashable, Codable, Sendable {
    /// Crossings counted with direction: a hole needs its ring drawn the other
    /// way round. What every drawing app starts with.
    case nonZero
    /// Crossings counted plainly: any ring inside another one is a hole,
    /// whichever way it is drawn.
    case evenOdd

    public var title: String {
        switch self {
        case .nonZero: return "Non-zero"
        case .evenOdd: return "Even-odd"
        }
    }
}

/// A path: the anchors, whether it closes, and the two paints it wears.
///
/// It is a kind of layer CONTENT in its own right and not a sixth
/// `AnnotationShape`, because an annotation is a two-point mark built from a
/// start and an end and a path has as many points as it likes.
public struct PathContent: Hashable, Codable, Sendable {
    /// The anchors in the order the outline runs through them, in the layer's
    /// own top-left coordinates.
    public var anchors: [PathAnchor]
    /// Whether the last anchor joins back to the first. A closed path is
    /// something you can paint inside; an open one is a line.
    public var isClosed: Bool
    /// Where each ring AFTER the first begins in `anchors`. Empty for the
    /// single-ring outline almost every path is.
    ///
    /// A ring is one closed loop of the outline. Most shapes are one ring, but
    /// the two things an area operation hands back are not: a circle with a
    /// circle cut out of it is a rim and a hole, and two shapes that do not
    /// touch, joined, are two separate pieces. Both are ONE shape wearing one
    /// fill, so both have to live in one path.
    ///
    /// They live in one FLAT anchor list, with this saying where each new loop
    /// starts, rather than in a list of lists. That is the whole reason for the
    /// shape of it: an anchor is still found by one number, so picking a point
    /// up, dragging it, nudging it, selecting several and reading a press off
    /// the outline all go on working on the hole exactly as they work on the
    /// rim, with no second index to thread through every one of them.
    ///
    /// Strictly increasing, every entry between 1 and `anchors.count - 1`,
    /// kept that way by `init` and by every edit.
    public var ringStarts: [Int]
    /// What the OUTLINE is drawn in. Flat by default, a gradient once one is
    /// chosen, exactly like every other shape's paint.
    public var paint: Paint
    /// How thick that outline is, in document points. Zero is a shape with no
    /// line round it, which is a perfectly ordinary filled icon.
    public var strokeWidth: CGFloat
    /// Which side of the outline the line sits on. Centred by default, which
    /// is what every vector tool draws and the only one of the three that
    /// means anything on an OPEN path (a line has no inside to be within).
    public var strokePosition: BorderPosition
    /// What the inside is painted with. Nil is a shape with no fill. Ignored
    /// while the path is open: there is no inside to paint.
    public var fill: Paint?
    /// How the inside is decided where the outline crosses itself.
    public var fillRule: PathFillRule
    /// What the ends of the line look like: the two ends of an open path, and
    /// the ends of every dash on a dashed one (`PathLineStyle.swift`).
    public var lineEnd: PathLineEnd
    /// How the line turns where two runs meet at an angle.
    public var lineCorner: PathLineCorner
    /// Whether the line is unbroken, dashed or dotted.
    public var linePattern: PathLinePattern

    public init(anchors: [PathAnchor],
                isClosed: Bool = false,
                ringStarts: [Int] = [],
                paint: Paint = Paint(hex: PathContent.defaultColorHex),
                strokeWidth: CGFloat = PathContent.defaultStrokeWidth,
                strokePosition: BorderPosition = .center,
                fill: Paint? = Paint(hex: PathContent.defaultColorHex),
                fillRule: PathFillRule = .nonZero,
                lineEnd: PathLineEnd = .round,
                lineCorner: PathLineCorner = .sharp,
                linePattern: PathLinePattern = .solid) {
        self.anchors = anchors
        self.isClosed = isClosed
        self.ringStarts = PathContent.tidyRingStarts(ringStarts, count: anchors.count)
        self.paint = paint
        self.strokeWidth = strokeWidth
        self.strokePosition = strokePosition
        self.fill = fill
        self.fillRule = fillRule
        self.lineEnd = lineEnd
        self.lineCorner = lineCorner
        self.linePattern = linePattern
    }

    /// What a freshly drawn path wears, which is what a freshly drawn box
    /// wears: the redline red, filled and outlined in it, 4pt of line
    /// (`AnnotationStyles.standard`). One shape vocabulary, one set of
    /// defaults.
    public static let defaultColorHex = "#FF3B30"
    public static let defaultStrokeWidth: CGFloat = 4

    /// The outline's flat colour. Everything that can only draw one colour
    /// reads this; setting it makes the outline flat, which is what painting a
    /// shape a colour means.
    public var colorHex: String {
        get { paint.hex }
        set { paint.hex = newValue; paint.kind = .solid }
    }

    /// The fill's flat colour, nil where there is no fill.
    public var fillColorHex: String? {
        get { fill?.hex }
        set { fill = newValue.map { Paint(hex: $0) } }
    }

    /// Whether this path actually paints an inside: it has to be closed AND
    /// have a fill. An open path is a line whatever colour is stored on it.
    public var paintsAnInside: Bool { isClosed && fill != nil }

    /// The stretch of `anchors` each ring covers, in order, the first one
    /// always starting at zero. One range for the single-ring outline almost
    /// every path is.
    public var ringRanges: [Range<Int>] {
        guard !anchors.isEmpty else { return [] }
        guard !ringStarts.isEmpty else { return [0..<anchors.count] }
        var ranges: [Range<Int>] = []
        var from = 0
        for start in ringStarts {
            ranges.append(from..<start)
            from = start
        }
        ranges.append(from..<anchors.count)
        return ranges
    }

    /// How many separate loops the outline is made of. One for an ordinary
    /// shape; two for a ring; more for a result in several pieces.
    public var ringCount: Int { anchors.isEmpty ? 0 : ringStarts.count + 1 }

    /// Whether this outline is more than one loop, which is what a hole or a
    /// result in unconnected pieces is.
    public var hasSeveralRings: Bool { ringCount > 1 }

    /// Which ring an anchor belongs to, and the stretch that ring covers.
    /// Nil for an index that is not an anchor.
    public func ring(containing index: Int) -> (ring: Int, range: Range<Int>)? {
        for (number, range) in ringRanges.enumerated() where range.contains(index) {
            return (number, range)
        }
        return nil
    }

    /// The only ring list that means anything: strictly increasing, inside the
    /// anchors, and with no empty ring in it.
    static func tidyRingStarts(_ starts: [Int], count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var tidy: [Int] = []
        for start in starts.sorted() where start >= 1 && start < count {
            if tidy.last != start { tidy.append(start) }
        }
        return tidy
    }

    /// The runs between the anchors, ring by ring, each ring's closing run
    /// included when the path is closed. A run NEVER crosses from one ring to
    /// the next: the last anchor of the rim joins back to the rim's own first
    /// anchor and not to the first anchor of the hole.
    ///
    /// Empty for a path of one anchor or none, which has no outline yet.
    public var segments: [PathSegment] {
        guard anchors.count >= 2 else { return [] }
        var runs: [PathSegment] = []
        for range in ringRanges {
            let ring = anchors[range]
            guard ring.count >= 2 else { continue }
            runs += zip(ring, ring.dropFirst()).map { PathSegment(from: $0, to: $1) }
            if isClosed, let first = ring.first, let last = ring.last {
                runs.append(PathSegment(from: last, to: first))
            }
        }
        return runs
    }

    /// How much area the outline encloses, signed: positive one way round the
    /// shape, negative the other. Zero for an outline with no inside at all.
    ///
    /// Zero is the interesting answer. An outline that doubles back along its
    /// own line sweeps nothing: two points joined by two straight runs, three
    /// points in a row, a closed path whose every anchor sits on one line.
    /// Those are the shapes the Pen must refuse to close, because closing them
    /// would drop a layer on the canvas that paints no pixels and can only be
    /// found by hunting for it in the layer list.
    ///
    /// An OPEN path answers zero whatever shape it is, because a line has no
    /// inside. Ask a copy with `isClosed` set to see what closing it would give.
    public var enclosedArea: CGFloat {
        guard isClosed else { return 0 }
        return segments.reduce(0) { $0 + Bezier.sweep(of: $1) } / 2
    }

    /// Whether the outline really has an inside, which is what makes it a
    /// shape rather than a line that happens to end where it started.
    ///
    /// The threshold is there for floating point dust, not for taste: a flat
    /// outline works out to zero on paper and to about a billionth of a point
    /// in practice, while the smallest shape anyone would draw on a 24 point
    /// icon grid covers whole square points.
    public var enclosesAnArea: Bool { abs(enclosedArea) > 1e-6 }

    /// The tight box the OUTLINE covers, curve bulge and all, in the layer's
    /// own coordinates. It knows nothing about the line's thickness: that is
    /// `strokeOutset`, and the two are added where a selection box is worked
    /// out.
    public var bounds: CGRect {
        guard let first = anchors.first else { return .zero }
        guard anchors.count >= 2 else {
            return CGRect(origin: first.point, size: .zero)
        }
        return segments.dropFirst().reduce(segments[0].bounds) { $0.union($1.bounds) }
    }

    /// How far this shape's own line reaches past its outline, in document
    /// points. Zero for an inside line, which stays within the shape.
    ///
    /// An OPEN path has no inside, so an inside line has nowhere to be: it is
    /// read as centred, which is what it is drawn as.
    ///
    /// Rounded UP to a whole point, the same way a line's own overhang is
    /// (`AnnotationContent.renderPadding`). This is what keeps the shape on the
    /// pixel grid: the bitmap it is drawn into is this much bigger on every
    /// side and is then laid on the canvas that much back from the frame, so a
    /// reach of half a point would put every path with an odd stroke width on
    /// half a pixel and let the compositor resample a hard edge into a soft
    /// one. A rounded-up reach costs half a point of clear margin and nothing
    /// else: the ink lands in exactly the same place either way.
    public var strokeOutset: CGFloat {
        guard strokeWidth > 0 else { return 0 }
        let reach = effectiveStrokePosition.outset(width: strokeWidth)
        // A SQUARE end reaches further than the half width every other end
        // does: its far corner sits width/√2 from the last point rather
        // than width/2, so without this the corners of a square-ended line
        // would be sliced off by the edge of its own bitmap
        // (`PathLineStyle.swift`).
        guard showsLineEnds, lineEnd == .square else { return reach.rounded(.up) }
        return max(reach, strokeWidth * lineEnd.reach).rounded(.up)
    }

    /// The position the line is actually drawn in, once an open path's missing
    /// inside is taken into account.
    public var effectiveStrokePosition: BorderPosition {
        isClosed ? strokePosition : .center
    }

    /// The same shape with every number multiplied about the layer's own
    /// origin. Handles scale with their anchors, which is what keeps a curve a
    /// curve instead of flattening it; the LINE WIDTH is left alone, because
    /// what is measured in points holds still when a box is dragged
    /// (`docs/design/ui-building.md`, "Resizing places the pieces").
    public func scaled(x: CGFloat, y: CGFloat) -> PathContent {
        var scaled = self
        scaled.anchors = anchors.map { $0.scaled(x: x, y: y) }
        return scaled
    }

    /// The same shape shifted in its own space.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> PathContent {
        var moved = self
        moved.anchors = anchors.map { $0.offsetBy(dx: dx, dy: dy) }
        return moved
    }

    /// The same shape with an affine transform applied to it: the anchors
    /// move, and the handles turn with them.
    ///
    /// Handles are stored as OFFSETS from their anchor, so only the rotating
    /// and scaling part of the transform touches them and the shifting part
    /// must not: applying the full transform to an offset would move every
    /// curve by the whole translation on top of its anchor.
    ///
    /// This is what bakes a layer's rotation into its outline, so a turned
    /// shape can take part in an area operation as the shape you can see
    /// rather than as the unturned one its numbers still describe.
    public func transformed(by transform: CGAffineTransform) -> PathContent {
        let linear = CGAffineTransform(a: transform.a, b: transform.b,
                                       c: transform.c, d: transform.d, tx: 0, ty: 0)
        var moved = self
        moved.anchors = anchors.map { anchor in
            var turned = anchor
            turned.point = anchor.point.applying(transform)
            turned.handleIn = anchor.handleIn?.applying(linear)
            turned.handleOut = anchor.handleOut?.applying(linear)
            return turned
        }
        return moved
    }

    /// The same shape re-stated against its own top-left corner, so its
    /// bounds start at zero and the layer's frame is the box it fills.
    public func normalized() -> PathContent {
        let box = bounds
        guard box.origin != .zero else { return self }
        return offsetBy(dx: -box.origin.x, dy: -box.origin.y)
    }

    // MARK: On disk

    private enum CodingKeys: String, CodingKey {
        case anchors, closed, ringStarts, paint, strokeWidth, strokePosition, fill, fillRule
        case lineEnd, lineCorner, linePattern
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anchors = try c.decodeIfPresent([PathAnchor].self, forKey: .anchors) ?? []
        isClosed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        // A file written before a path could hold more than one ring has none
        // of these, and comes back as the single-ring outline it always was.
        ringStarts = PathContent.tidyRingStarts(
            try c.decodeIfPresent([Int].self, forKey: .ringStarts) ?? [], count: anchors.count)
        paint = try c.decodeIfPresent(Paint.self, forKey: .paint)
            ?? Paint(hex: PathContent.defaultColorHex)
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth)
            ?? PathContent.defaultStrokeWidth
        strokePosition = try c.decodeIfPresent(BorderPosition.self, forKey: .strokePosition) ?? .center
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill)
        fillRule = try c.decodeIfPresent(PathFillRule.self, forKey: .fillRule) ?? .nonZero
        // A file written before a path could say any of this comes back
        // wearing exactly the look it had: round ends, sharp corners, a solid
        // line, which is what the rasterizer always drew.
        lineEnd = try c.decodeIfPresent(PathLineEnd.self, forKey: .lineEnd) ?? .round
        lineCorner = try c.decodeIfPresent(PathLineCorner.self, forKey: .lineCorner) ?? .sharp
        linePattern = try c.decodeIfPresent(PathLinePattern.self, forKey: .linePattern) ?? .solid
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(anchors, forKey: .anchors)
        try c.encode(isClosed, forKey: .closed)
        // Left out of an ordinary one-ring path, so nothing already on disk
        // changes shape the next time it is saved.
        if !ringStarts.isEmpty { try c.encode(ringStarts, forKey: .ringStarts) }
        try c.encode(paint, forKey: .paint)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokePosition, forKey: .strokePosition)
        try c.encodeIfPresent(fill, forKey: .fill)
        try c.encode(fillRule, forKey: .fillRule)
        try c.encode(lineEnd, forKey: .lineEnd)
        try c.encode(lineCorner, forKey: .lineCorner)
        try c.encode(linePattern, forKey: .linePattern)
    }
}

// MARK: - A layer made of one

extension Layer {

    /// The layer's path content, nil for every other kind.
    public var path: PathContent? {
        if case .path(let p) = content { return p }
        return nil
    }
}

/// Making and re-fitting a path layer, the same way `AnnotationBuilder` makes
/// and re-fits a mark.
public enum PathBuilder {

    /// What a path layer is called before anybody renames it.
    public static let defaultName = "Path"

    /// A layer wrapping `content`, boxed round the shape it actually covers and
    /// placed with that box's top-left corner at `origin`.
    ///
    /// The anchors are re-stated against the box on the way in, so a path's
    /// numbers are always its own layer's numbers and moving the layer never
    /// touches them.
    public static func layer(_ content: PathContent, at origin: CGPoint,
                             name: String = PathBuilder.defaultName) -> Layer {
        let normalized = content.normalized()
        let box = normalized.bounds
        return Layer(name: name, content: .path(normalized),
                     frame: CGRect(origin: origin, size: box.size))
    }

    /// The layer re-fitted so its box becomes `frame`: the shape scales into
    /// the new box, curves and all.
    ///
    /// An axis with nothing in it is left alone rather than divided by, the
    /// same rule a group's resize follows: a perfectly flat path dragged taller
    /// has no height to scale from.
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        guard let content = layer.path else { return layer }
        let box = frame.standardized
        let was = layer.frame.standardized
        let sx = was.width > 0 ? box.width / was.width : 1
        let sy = was.height > 0 ? box.height / was.height : 1
        var resized = layer
        resized.content = .path(content.scaled(x: sx, y: sy))
        resized.frame = box
        return resized
    }
}

// MARK: - Where the shape actually is

extension PathSegment {

    /// The run as a short chain of straight steps, the first point left out so
    /// chaining runs together never repeats a point.
    ///
    /// A fixed number of steps rather than an adaptive flattening: this is for
    /// answering "did the click land on it", where being a fraction of a point
    /// out is beneath notice and being fast matters, since every layer in the
    /// document is asked on every click.
    func flattened(steps: Int = 16) -> [CGPoint] {
        guard !isStraight else { return [end] }
        return (1...max(1, steps)).map { i in
            let t = CGFloat(i) / CGFloat(max(1, steps))
            return CGPoint(x: Bezier.value(start.x, control1.x, control2.x, end.x, at: t),
                           y: Bezier.value(start.y, control1.y, control2.y, end.y, at: t))
        }
    }
}

extension PathContent {

    /// Every ring of the outline as its own chain of straight steps, in the
    /// layer's own coordinates. A closed ring comes back with its closing run
    /// included, so its last point is its first one again.
    ///
    /// One chain per ring rather than one long one, because the gap between
    /// the rim and the hole is not part of the outline: chaining them would
    /// invent a straight run across the middle of the shape, and everything
    /// that measures a distance to the outline or counts crossings through it
    /// would read that invented run as real.
    public func flattenedRings(steps: Int = 16) -> [[CGPoint]] {
        guard anchors.count >= 2 else { return anchors.isEmpty ? [] : [anchors.map(\.point)] }
        var rings: [[CGPoint]] = []
        var runs = segments[...]
        for range in ringRanges {
            let ring = anchors[range]
            guard ring.count >= 2, let first = ring.first else { continue }
            let count = ring.count - 1 + (isClosed ? 1 : 0)
            var points = [first.point]
            for run in runs.prefix(count) { points += run.flattened(steps: steps) }
            runs = runs.dropFirst(count)
            rings.append(points)
        }
        return rings
    }

    /// The FIRST ring as a chain of straight steps, which for the single-ring
    /// outline almost every path is is the whole outline.
    public func flattened(steps: Int = 16) -> [CGPoint] {
        flattenedRings(steps: steps).first ?? anchors.map(\.point)
    }

    /// Whether a point in the layer's own coordinates is INSIDE the shape.
    ///
    /// Only means anything on a closed path: an open one has no inside, and
    /// says so rather than pretending its two ends are joined.
    public func containsInside(_ point: CGPoint) -> Bool {
        guard isClosed else { return false }
        let rings = flattenedRings()
        guard rings.contains(where: { $0.count >= 3 }) else { return false }
        var crossings = 0
        var winding = 0
        // Every ring is counted into the SAME tally, which is what makes a
        // hole a hole: the rim is wound one way and the hole the other, so a
        // point inside both cancels to nothing and is outside the shape.
        for outline in rings where outline.count >= 3 {
            for (a, b) in zip(outline, outline.dropFirst()) {
                guard (a.y > point.y) != (b.y > point.y) else { continue }
                let span = b.y - a.y
                guard span != 0 else { continue }
                let x = a.x + (point.y - a.y) / span * (b.x - a.x)
                guard x > point.x else { continue }
                crossings += 1
                winding += b.y > a.y ? 1 : -1
            }
        }
        return fillRule == .evenOdd ? crossings % 2 == 1 : winding != 0
    }

    /// How far a point in the layer's own coordinates is from the OUTLINE.
    public func distanceToOutline(from point: CGPoint) -> CGFloat {
        // Every ring counts: the edge of a hole is as much the shape's outline
        // as its rim is, and a press on it has to catch the shape.
        var best = CGFloat.infinity
        for outline in flattenedRings() {
            guard outline.count >= 2 else {
                if let only = outline.first {
                    best = min(best, hypot(point.x - only.x, point.y - only.y))
                }
                continue
            }
            for (a, b) in zip(outline, outline.dropFirst()) {
                best = min(best, Geometry.distance(from: point, toSegmentFrom: a, to: b))
            }
        }
        return best
    }

    /// Whether a click at `point`, in the layer's own coordinates, lands on
    /// this shape.
    ///
    /// A filled shape takes a click anywhere inside it. A shape with no fill —
    /// and every open path, which has no inside at all — is its LINE, so it
    /// takes a click near that line and nowhere else. `slop` is the extra
    /// forgiveness a thin line gets, so a one point stroke is not a one pixel
    /// target (the same six screen points a thin arrow is given).
    public func isHit(at point: CGPoint, slop: CGFloat = 6) -> Bool {
        if paintsAnInside, containsInside(point) { return true }
        guard strokeWidth > 0 || !paintsAnInside else { return false }
        return distanceToOutline(from: point) <= strokeWidth / 2 + slop
    }
}
