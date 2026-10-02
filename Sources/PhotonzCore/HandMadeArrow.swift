import CoreGraphics
import Foundation

// How the hand-made arrow styles are drawn (`ArrowStyle.swift`).
//
// Three rules hold every style together:
//
// * **It never wobbles between renders.** All of the irregularity comes from a
//   seed stored on the arrow (`AnnotationContent.styleSeed`), so the canvas,
//   a reopened document and an export at any scale draw the same hand.
// * **Detail scales with the line.** Every wobble, gap and swell is stated in
//   the arrow's own thickness or length, so a thick arrow is the thin one
//   drawn bigger rather than the thin one's tremor on a fat line.
// * **It follows the spine.** Each style is laid along an `ArrowSpine`, a
//   curve from the tail to the tip, so a bent arrow's style bends with it
//   (`ArrowBend.swift`).
//
// What comes out is a list of `ArrowInk`: lines to stroke and shapes to fill,
// each marked as shaft or head so the head keeps its own colour. The
// rasterizer, the canvas's live preview and the SVG export all draw from the
// same list (`HandMadeArrow.outlines(for:)`), so they cannot disagree.

// MARK: - The spine

/// The curve an arrow is drawn along, tail to tip: a quadratic whose control
/// point sits on the straight line for an arrow that does not bend.
public struct ArrowSpine: Hashable, Sendable {
    public var start: CGPoint
    public var control: CGPoint
    public var end: CGPoint

    /// A straight spine.
    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
        control = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    public init(start: CGPoint, control: CGPoint, end: CGPoint) {
        self.start = start
        self.control = control
        self.end = end
    }

    public func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }

    /// The direction the curve is heading at `t`, as a unit vector.
    public func direction(at t: CGFloat) -> CGVector {
        let u = 1 - t
        let dx = 2 * u * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * u * (control.y - start.y) + 2 * t * (end.y - control.y)
        let length = hypot(dx, dy)
        if length > 1e-9 { return CGVector(dx: dx / length, dy: dy / length) }
        let chord = hypot(end.x - start.x, end.y - start.y)
        guard chord > 1e-9 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: (end.x - start.x) / chord, dy: (end.y - start.y) / chord)
    }

    /// One place along the spine: where it is, which way it is heading, and
    /// how far along the curve that is.
    public struct Station: Hashable, Sendable {
        public var point: CGPoint
        public var direction: CGVector
        public var distance: CGFloat
    }

    private static let tableSteps = 128

    /// Cumulative length at `t = i / tableSteps`.
    private func lengthTable() -> [CGFloat] {
        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(Self.tableSteps + 1)
        var previous = start
        var total: CGFloat = 0
        for i in 1...Self.tableSteps {
            let next = point(at: CGFloat(i) / CGFloat(Self.tableSteps))
            total += hypot(next.x - previous.x, next.y - previous.y)
            lengths.append(total)
            previous = next
        }
        return lengths
    }

    /// How long the curve is.
    public var length: CGFloat { lengthTable().last ?? 0 }

    /// `count` stations spread EVENLY ALONG THE CURVE, the first on the tail
    /// and the last on the tip, so a wobble or a taper stated per unit of
    /// length looks the same on the tight part of a bend as on the loose one.
    public func stations(count: Int) -> [Station] {
        let n = max(count, 2)
        let lengths = lengthTable()
        let total = lengths.last ?? 0
        return (0..<n).map { i in
            let distance = total * CGFloat(i) / CGFloat(n - 1)
            let t = parameter(atDistance: distance, lengths: lengths)
            return Station(point: point(at: t), direction: direction(at: t), distance: distance)
        }
    }

    /// The curve's parameter `distance` along it from the start.
    func parameter(atDistance distance: CGFloat) -> CGFloat {
        parameter(atDistance: distance, lengths: lengthTable())
    }

    private func parameter(atDistance distance: CGFloat, lengths: [CGFloat]) -> CGFloat {
        let steps = lengths.count - 1
        guard steps > 0, let total = lengths.last, total > 0 else { return distance > 0 ? 1 : 0 }
        if distance <= 0 { return 0 }
        if distance >= total { return 1 }
        var lo = 0
        var hi = steps
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if lengths[mid] < distance { lo = mid } else { hi = mid }
        }
        let span = lengths[hi] - lengths[lo]
        let fraction = span > 0 ? (distance - lengths[lo]) / span : 0
        return (CGFloat(lo) + fraction) / CGFloat(steps)
    }
}

// MARK: - What gets drawn

/// One piece of a hand-made arrow: a line to stroke or a shape to fill.
public struct ArrowInk: Hashable, Sendable {
    /// Which part of the arrow this is, so the head can wear its own colour.
    public enum Part: Hashable, Sendable { case shaft, head }
    public enum Kind: Hashable, Sendable {
        /// `points` is a line, stroked `width` wide with round ends.
        case stroke
        /// `points` is the outline of a shape, filled.
        case fill
    }

    public var part: Part
    public var kind: Kind
    public var points: [CGPoint]
    /// How wide a stroke is drawn; zero for a fill.
    public var width: CGFloat

    public init(part: Part, kind: Kind, points: [CGPoint], width: CGFloat) {
        self.part = part
        self.kind = kind
        self.points = points
        self.width = width
    }
}

// MARK: - A seeded hand

/// The arrow's own source of irregularity: the same seed gives the same
/// numbers in the same order, on every machine, forever (SplitMix64).
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt32, salt: UInt64) {
        state = (UInt64(seed) &* 0x9E37_79B9_7F4A_7C15) ^ (salt &* 0xD1B5_4A32_D192_ED03)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }

    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * unit() }

    mutating func sign() -> CGFloat { next() & 1 == 0 ? 1 : -1 }
}

// MARK: - The styles

public enum HandMadeArrow {

    /// The seed the next arrow is drawn with, given the last one: never zero
    /// (the seed every arrow from before styles carries) and never the same
    /// twice in a row.
    public static func seed(after seed: UInt32) -> UInt32 {
        var random = SeededRandom(seed: seed, salt: 0x5EED)
        var next = UInt32(truncatingIfNeeded: random.next())
        while next == 0 || next == seed { next = UInt32(truncatingIfNeeded: random.next()) }
        return next
    }

    /// The pieces `content` is drawn in, along its own spine: the straight
    /// line between its ends, or the curve it has been bent into. Empty for a
    /// clean arrow, which the rasterizer draws as it always has, and for
    /// anything that is not an arrow.
    public static func inks(for content: AnnotationContent) -> [ArrowInk] {
        inks(for: content, along: content.spine)
    }

    /// The same, along any spine.
    public static func inks(for content: AnnotationContent, along spine: ArrowSpine) -> [ArrowInk] {
        guard content.shape == .arrow, content.arrowStyle.isHandMade,
              let hand = Hand(content, spine: spine) else { return [] }
        switch content.arrowStyle {
        case .clean: return []
        case .handDrawn: return hand.pen()
        case .marker: return hand.marker()
        case .brush: return hand.brush()
        case .sketch: return hand.sketch()
        }
    }

    /// The box every piece of ink covers, with room for the smoothing between
    /// points, in the arrow's own coordinates. `.null` when nothing is drawn.
    public static func inkBounds(for content: AnnotationContent) -> CGRect {
        var box = CGRect.null
        let slack = max(1.5, content.strokeWidth * 0.35)
        for ink in inks(for: content) {
            guard var minX = ink.points.first?.x, var minY = ink.points.first?.y else { continue }
            var maxX = minX
            var maxY = minY
            for p in ink.points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let reach = (ink.kind == .stroke ? ink.width / 2 : 0) + slack
            box = box.union(CGRect(x: minX - reach, y: minY - reach,
                                   width: maxX - minX + 2 * reach, height: maxY - minY + 2 * reach))
        }
        return box
    }

    /// Whether `point` (in the arrow's own coordinates) lands on any of its
    /// ink, or within `slop` of it.
    public static func ink(of content: AnnotationContent, reaches point: CGPoint,
                           within slop: CGFloat) -> Bool {
        for ink in inks(for: content) {
            switch ink.kind {
            case .stroke:
                let reach = ink.width / 2 + max(slop, 0)
                for (a, b) in zip(ink.points, ink.points.dropFirst())
                    where Geometry.distance(from: point, toSegmentFrom: a, to: b) <= reach {
                    return true
                }
            case .fill:
                if ink.outline.contains(point) { return true }
                let reach = max(slop, 0)
                for (a, b) in zip(ink.points, ink.points.dropFirst())
                    where Geometry.distance(from: point, toSegmentFrom: a, to: b) <= reach {
                    return true
                }
            }
        }
        return false
    }

    /// How far a brush stroke reaches either side of its spine at each
    /// fraction of the way from tail (0) to tip (1).
    public static func brushHalfWidths(for content: AnnotationContent, at fractions: [CGFloat]) -> [CGFloat] {
        fractions.map { Hand.brushHalfWidth(at: $0, peak: Hand.brushPeak(width: content.strokeWidth)) }
    }

    /// The arrow as two shapes to fill, shaft and head, each the union of its
    /// pieces (filled with the non-zero rule, which is what makes overlapping
    /// pieces one patch of ink rather than a darker spot where they cross).
    public static func outlines(for content: AnnotationContent) -> (shaft: CGPath, head: CGPath) {
        outlines(of: inks(for: content))
    }

    public static func outlines(of inks: [ArrowInk]) -> (shaft: CGPath, head: CGPath) {
        let shaft = CGMutablePath()
        let head = CGMutablePath()
        for ink in inks {
            let outline = ink.outline
            if ink.part == .shaft { shaft.addPath(outline) } else { head.addPath(outline) }
        }
        return (shaft, head)
    }
}

extension ArrowInk {
    /// The piece as a shape to fill: a stroke turned into its own outline, or
    /// the fill's outline turned to wind the same way a stroke's does, so any
    /// mix of the two fills as one.
    public var outline: CGPath {
        switch kind {
        case .stroke:
            return Self.smoothPath(points, closed: false)
                .copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        case .fill:
            let area = Self.signedArea(points)
            let oriented = (area >= 0) == Self.strokeWindingIsPositive ? points : points.reversed()
            return Self.smoothPath(oriented, closed: true)
        }
    }

    /// The line or outline through the points, smoothed into curves
    /// (Catmull-Rom) so it stays a curve however far the canvas is zoomed in.
    public static func smoothPath(_ points: [CGPoint], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        let n = points.count
        if n < 3 {
            for p in points.dropFirst() { path.addLine(to: p) }
            if closed { path.closeSubpath() }
            return path
        }
        func at(_ i: Int) -> CGPoint {
            if closed { return points[((i % n) + n) % n] }
            return points[min(max(i, 0), n - 1)]
        }
        let segments = closed ? n : n - 1
        for i in 0..<segments {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }

    static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst() + [points[0]]) {
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Which way Core Graphics winds the outline of a stroke. Asked of Core
    /// Graphics itself rather than assumed, so a filled piece is always turned
    /// to match it and never punches a hole where it overlaps a stroked one.
    static let strokeWindingIsPositive: Bool = {
        let line = CGMutablePath()
        line.move(to: .zero)
        line.addLine(to: CGPoint(x: 100, y: 0))
        let outline = line.copy(strokingWithWidth: 10, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        var corners: [CGPoint] = []
        outline.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                corners.append(element.pointee.points[0])
            case .addQuadCurveToPoint:
                corners.append(element.pointee.points[1])
            case .addCurveToPoint:
                corners.append(element.pointee.points[2])
            default:
                break
            }
        }
        return signedArea(corners) >= 0
    }()
}

// MARK: - Drawing them

/// Everything one arrow's hand needs: the spine, how long and thick it is, and
/// how big its head is.
private struct Hand {
    let content: AnnotationContent
    let spine: ArrowSpine
    let length: CGFloat
    let width: CGFloat
    let headHalfWidth: CGFloat
    let headLength: CGFloat
    /// How many stations the shaft is drawn through: one for about every
    /// width and a quarter of length, so it is the same drawing at any size.
    let count: Int

    init?(_ content: AnnotationContent, spine: ArrowSpine) {
        let width = content.strokeWidth
        let length = spine.length
        guard width > 0, length > 0, length.isFinite else { return nil }
        self.content = content
        self.spine = spine
        self.length = length
        self.width = width
        headHalfWidth = Geometry.arrowheadHalfWidth(strokeWidth: width, scale: content.arrowheadScale)
        headLength = Geometry.arrowheadLength(strokeWidth: width, scale: content.arrowheadScale,
                                              length: length)
        count = min(max(Int((length / width * 0.8).rounded(.up)) + 1, 12), 240)
    }

    func random(_ salt: UInt64) -> SeededRandom { SeededRandom(seed: content.styleSeed, salt: salt) }

    /// The spine pushed sideways by `offset(u)` at each fraction `u` of the
    /// way along it.
    func track(_ offset: (CGFloat) -> CGFloat) -> Track {
        Track(spine.stations(count: count), offset: offset)
    }

    /// The angle a head's wing makes with the shaft.
    var wingAngle: CGFloat { atan2(headHalfWidth, max(headLength, 0.001)) }

    // MARK: Hand-drawn (ref 25)

    /// A pen line: thin, a little unsteady, bowed the way a hand sweeps, with
    /// an open head whose two strokes hook outwards.
    func pen() -> [ArrowInk] {
        var r = random(1)
        let bow = length * r.range(0.012, 0.03) * r.sign()
        let cycles1 = length / (width * r.range(30, 50))
        let amp1 = width * r.range(0.05, 0.1)
        let phase1 = r.range(0, 2 * .pi)
        let cycles2 = cycles1 * 2.7
        let amp2 = amp1 * 0.5
        let phase2 = r.range(0, 2 * .pi)
        let track = track { u in
            let envelope = sin(.pi * u)
            return bow * envelope + sqrt(max(envelope, 0)) * (amp1 * sin(2 * .pi * cycles1 * u + phase1)
                                                               + amp2 * sin(2 * .pi * cycles2 * u + phase2))
        }
        var inks = [ArrowInk(part: .shaft, kind: .stroke, points: track.points, width: width)]
        let tip = track.tip
        let back = track.backAtTip(reach: headLength * 0.5)
        for side in [CGFloat(1), -1] {
            let reach = headLength * r.range(0.82, 1.02)
            let angle = wingAngle * r.range(0.85, 1.12)
            let direction = back.rotated(by: side * angle)
            let wingEnd = tip + direction * reach
            let outward = back.rotated(by: side * .pi / 2)
            let control = midpoint(tip, wingEnd) + outward * (reach * r.range(0.03, 0.09))
            inks.append(ArrowInk(part: .head, kind: .stroke,
                                 points: quadratic(tip, control, wingEnd, count: 8), width: width))
        }
        return inks
    }

    // MARK: Marker (ref 27)

    /// A bold rounded marker stroke, smooth and slightly bowed, with a loose
    /// head of two separate strokes that do not quite meet at the tip.
    func marker() -> [ArrowInk] {
        var r = random(2)
        let bold = width * 1.6
        let bow = length * r.range(0.015, 0.035) * r.sign()
        let cycles = length / (width * r.range(40, 60))
        let amp = width * r.range(0.08, 0.15)
        let phase = r.range(0, 2 * .pi)
        let track = track { u in
            let envelope = sin(.pi * u)
            return bow * envelope + envelope * amp * sin(2 * .pi * cycles * u + phase)
        }
        var inks = [ArrowInk(part: .shaft, kind: .stroke, points: track.points, width: bold)]
        let tip = track.tip
        let back = track.backAtTip(reach: headLength * 0.5)
        // A head drawn with a fat marker needs strokes long enough to read as
        // a head rather than a blob, whatever the Head Size floor would allow.
        let markerReach = max(headLength, min(bold * 3.2, length * 0.45))
        for side in [CGFloat(1), -1] {
            let reach = markerReach * r.range(0.8, 1.0)
            let angle = wingAngle * r.range(0.9, 1.18)
            let direction = back.rotated(by: side * angle)
            let outward = back.rotated(by: side * .pi / 2)
            // Loose: each stroke starts a little off the tip, one of them
            // usually running past it, the way two quick marker strokes land.
            let from = tip + back * (bold * r.range(-0.5, 0.2)) + outward * (bold * r.range(-0.25, 0.25))
            let wingEnd = tip + direction * reach
            let control = midpoint(from, wingEnd) + outward * (reach * r.range(-0.02, 0.08))
            inks.append(ArrowInk(part: .head, kind: .stroke,
                                 points: quadratic(from, control, wingEnd, count: 8), width: bold))
        }
        return inks
    }

    // MARK: Brush (ref 28)

    static func brushPeak(width: CGFloat) -> CGFloat { width * 1.3 }

    /// Half the brush body's width at `u` of the way from tail to tip: a point
    /// at the tail, swelling to its fullest a little past the middle, then
    /// narrowing into the head.
    static func brushHalfWidth(at u: CGFloat, peak: CGFloat) -> CGFloat {
        let fullest: CGFloat = 0.62
        let u = min(max(u, 0), 1)
        if u <= fullest {
            return peak * pow(max(sin(u / fullest * .pi / 2), 0), 0.9)
        }
        let v = (u - fullest) / (1 - fullest)
        return peak * (1 - 0.6 * v * v * (3 - 2 * v))
    }

    /// A filled brush stroke and two swept calligraphic wings.
    func brush() -> [ArrowInk] {
        var r = random(3)
        let bow = length * r.range(0.01, 0.025) * r.sign()
        let track = track { u in bow * sin(.pi * u) }
        let peak = Self.brushPeak(width: width)
        let halfWidths = track.fractions.map { Self.brushHalfWidth(at: $0, peak: peak) }
        var inks = [ArrowInk(part: .shaft, kind: .fill,
                             points: ribbon(track.points, halfWidths: halfWidths,
                                            startCap: false, endCap: true),
                             width: 0)]
        let tip = track.tip
        let back = track.backAtTip(reach: headLength * 0.5)
        let wing = peak * 0.95
        let brushReach = min(max(headLength * 1.6, peak * 7), length * 0.45)
        for side in [CGFloat(1), -1] {
            let reach = brushReach * r.range(0.9, 1.08)
            let angle = wingAngle * r.range(0.85, 1.1)
            let direction = back.rotated(by: side * angle)
            let outward = back.rotated(by: side * .pi / 2)
            let wingEnd = tip + direction * reach
            // Swept: the wing bows in towards the shaft, the way a brush
            // flicked back from the tip curves.
            let control = midpoint(tip, wingEnd) - outward * (reach * r.range(0.03, 0.08))
            let spine = quadratic(tip, control, wingEnd, count: 14)
            let widths = spine.indices.map { i -> CGFloat in
                let v = CGFloat(i) / CGFloat(spine.count - 1)
                if v < 0.3 { return wing * (0.55 + 0.45 * sin(v / 0.3 * .pi / 2)) }
                return wing * (1 - 0.75 * pow((v - 0.3) / 0.7, 1.3))
            }
            inks.append(ArrowInk(part: .head, kind: .fill,
                                 points: ribbon(spine, halfWidths: widths, startCap: true, endCap: true),
                                 width: 0))
        }
        return inks
    }

    // MARK: Sketch (ref 26)

    /// An outline arrow, a wide body and a big barbed head, sketched twice
    /// over with a dry marker: each side its own rough stroke running a
    /// little past the corners, broken where the ink skipped, with flecks of
    /// ink beside the line.
    func sketch() -> [ArrowInk] {
        var r = random(4)
        let head = max(headHalfWidth * 2, width * 5)
        let headReach = min(max(headLength * 1.4, head * 1.4), length * 0.55)
        let body = head * 0.4
        let tailBody = body * 0.75
        let bow = length * r.range(0.015, 0.04) * r.sign()
        let track = track { u in bow * sin(.pi * u) }
        let baseU = max(1 - headReach / length, 0.05)

        let sideCount = max(4, Int((CGFloat(count) * baseU).rounded()))
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0..<sideCount {
            let u = baseU * CGFloat(i) / CGFloat(sideCount - 1)
            let at = track.sample(u)
            let s = u / baseU
            let half = tailBody + (body - tailBody) * s * s * (3 - 2 * s)
            left.append(at.point + at.normal * half)
            right.append(at.point - at.normal * half)
        }
        let base = track.sample(baseU)
        let baseLeft = base.point + base.normal * body
        let baseRight = base.point - base.normal * body
        let barb = base.tangent * (headReach * 0.15)
        let wingLeft = base.point - barb + base.normal * head
        let wingRight = base.point - barb - base.normal * head
        let tip = track.tip

        let segments: [(points: [CGPoint], part: ArrowInk.Part)] = [
            (left, .shaft),
            ([baseLeft, wingLeft], .head),
            ([wingLeft, tip], .head),
            ([tip, wingRight], .head),
            ([wingRight, baseRight], .head),
            (Array(right.reversed()), .shaft),
        ]

        var inks: [ArrowInk] = []
        for pass in 0..<2 {
            let stroke = width * (pass == 0 ? 0.85 : 0.5)
            let shift = pass == 0 ? 0 : width * r.range(0.6, 1.0)
            for segment in segments {
                let line = roughLine(segment.points, shift: shift, random: &r)
                for dash in dashes(line, pass: pass, random: &r) {
                    inks.append(ArrowInk(part: segment.part, kind: .stroke, points: dash, width: stroke))
                }
            }
        }
        // Flecks: the specks a dry marker leaves beside its line.
        let perimeter = segments.reduce(CGFloat(0)) { $0 + polylineLength($1.points) }
        let flecks = min(40, Int(perimeter / (width * 7)))
        for _ in 0..<flecks {
            let which = min(Int(r.unit() * CGFloat(segments.count)), segments.count - 1)
            let segment = segments[which]
            let at = pointAlong(segment.points, fraction: r.unit())
            let off = width * r.range(-1.3, 1.3)
            let start = at.point + at.normal * off
            let direction = at.tangent.rotated(by: r.range(-0.5, 0.5))
            let end = start + direction * (width * r.range(0.4, 1.2))
            inks.append(ArrowInk(part: segment.part, kind: .stroke, points: [start, end],
                                 width: width * r.range(0.25, 0.45)))
        }
        return inks
    }

    /// One side of the sketch drawn by hand: run a little past both corners,
    /// bowed slightly, trembling along its length, and on the second pass
    /// set off to one side so the two passes read as a double line.
    private func roughLine(_ points: [CGPoint], shift: CGFloat,
                           random r: inout SeededRandom) -> [CGPoint] {
        let total = polylineLength(points)
        guard total > 0 else { return points }
        let spacing = width * 1.5
        let n = max(3, Int((total / spacing).rounded(.up)) + 1)
        let overshootStart = width * r.range(0, 1.1)
        let overshootEnd = width * r.range(0, 1.1)
        let bow = total * r.range(-0.015, 0.015)
        // A slow drift, so a second pass wanders across the first rather than
        // running beside it like a railway line, and a fine tremor on top.
        let drift = r.range(0.6, 1.6)
        let driftPhase = r.range(0, 2 * .pi)
        let amp = width * r.range(0.04, 0.09)
        let cycles = total / (width * r.range(3, 5))
        let phase = r.range(0, 2 * .pi)
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let v = CGFloat(i) / CGFloat(n - 1)
            let reach = -overshootStart + v * (total + overshootStart + overshootEnd)
            let at = pointAlong(points, distance: reach, total: total)
            let offset = shift * sin(.pi * drift * v + driftPhase) + bow * sin(.pi * v)
                + amp * sin(2 * .pi * cycles * v + phase)
            out.append(at.point + at.normal * offset)
        }
        return out
    }

    /// The line broken where the ink skipped. The first pass skips now and
    /// then; the lighter second pass skips more.
    private func dashes(_ line: [CGPoint], pass: Int, random r: inout SeededRandom) -> [[CGPoint]] {
        var pieces: [[CGPoint]] = []
        var current: [CGPoint] = []
        var dashLeft = width * (pass == 0 ? r.range(6, 18) : r.range(3, 10))
        guard let first = line.first else { return [] }
        current.append(first)
        var previous = first
        var gapLeft: CGFloat = 0
        for p in line.dropFirst() {
            var step = hypot(p.x - previous.x, p.y - previous.y)
            var from = previous
            while step > 0 {
                if gapLeft > 0 {
                    let used = min(gapLeft, step)
                    gapLeft -= used
                    from = from + (p - from).normalized * used
                    step -= used
                    if gapLeft <= 0 { current = [from] }
                    continue
                }
                if step < dashLeft {
                    dashLeft -= step
                    current.append(p)
                    from = p
                    step = 0
                } else {
                    let cut = from + (p - from).normalized * dashLeft
                    current.append(cut)
                    step -= dashLeft
                    from = cut
                    let skips = r.unit() < (pass == 0 ? 0.5 : 0.75)
                    dashLeft = width * (pass == 0 ? r.range(6, 18) : r.range(3, 10))
                    if skips {
                        if current.count >= 2 { pieces.append(current) }
                        current = []
                        gapLeft = width * r.range(0.3, 0.9)
                    }
                }
            }
            previous = p
        }
        if current.count >= 2 { pieces.append(current) }
        return pieces
    }

    // MARK: Shapes

    /// A filled band along `points`, `halfWidths[i]` either side of each, with
    /// a round end where asked.
    private func ribbon(_ points: [CGPoint], halfWidths: [CGFloat],
                        startCap: Bool, endCap: Bool) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let tangents = Track.tangents(of: points)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for (i, p) in points.enumerated() {
            let normal = tangents[i].perpendicular
            let half = halfWidths[min(i, halfWidths.count - 1)]
            left.append(p + normal * half)
            right.append(p - normal * half)
        }
        var outline: [CGPoint] = []
        if startCap, let first = points.first, let half = halfWidths.first, half > 0 {
            outline.append(contentsOf: cap(around: first, facing: tangents[0] * -1,
                                           radius: half, from: right[0], clockwiseTo: left[0]))
        }
        outline.append(contentsOf: left)
        if endCap, let last = points.last, let half = halfWidths.last, half > 0,
           let tangent = tangents.last, let leftEnd = left.last, let rightEnd = right.last {
            outline.append(contentsOf: cap(around: last, facing: tangent, radius: half,
                                           from: leftEnd, clockwiseTo: rightEnd))
        }
        // A side that ends in a point has the same point on both sides; it is
        // said once.
        var back = Array(right.reversed())
        if let a = outline.last, let b = back.first, hypot(a.x - b.x, a.y - b.y) < 1e-6 { back.removeFirst() }
        if let a = outline.first, let b = back.last, hypot(a.x - b.x, a.y - b.y) < 1e-6 { back.removeLast() }
        outline.append(contentsOf: back)
        return outline
    }

    /// The points of a half circle round `center`, bulging towards `facing`,
    /// between two points already on the outline (which are left out).
    private func cap(around center: CGPoint, facing: CGVector, radius: CGFloat,
                     from: CGPoint, clockwiseTo to: CGPoint) -> [CGPoint] {
        let a0 = atan2(from.y - center.y, from.x - center.x)
        let a1 = atan2(to.y - center.y, to.x - center.x)
        let mid = atan2(facing.dy, facing.dx)
        // Go round whichever way passes through the direction it faces.
        var sweep = a1 - a0
        while sweep > .pi { sweep -= 2 * .pi }
        while sweep < -.pi { sweep += 2 * .pi }
        var probe = mid - a0
        while probe > .pi { probe -= 2 * .pi }
        while probe < -.pi { probe += 2 * .pi }
        if (sweep > 0) != (probe > 0) { sweep += sweep > 0 ? -2 * .pi : 2 * .pi }
        let steps = 6
        return (1..<steps).map { i in
            let angle = a0 + sweep * CGFloat(i) / CGFloat(steps)
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    private func quadratic(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, count: Int) -> [CGPoint] {
        ArrowSpine(start: a, control: c, end: b).stations(count: count).map(\.point)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func polylineLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    private func pointAlong(_ points: [CGPoint], fraction: CGFloat)
        -> (point: CGPoint, tangent: CGVector, normal: CGVector) {
        let total = polylineLength(points)
        return pointAlong(points, distance: total * fraction, total: total)
    }

    /// The point `distance` along a polyline, carried on straight past either
    /// end so a stroke can overshoot its corner.
    private func pointAlong(_ points: [CGPoint], distance: CGFloat, total: CGFloat)
        -> (point: CGPoint, tangent: CGVector, normal: CGVector) {
        guard points.count >= 2, let first = points.first, let last = points.last else {
            let p = points.first ?? .zero
            return (p, CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1))
        }
        if distance <= 0 {
            let t = (points[1] - first).normalized
            return (first + t * distance, t, t.perpendicular)
        }
        var walked: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            let step = hypot(b.x - a.x, b.y - a.y)
            if walked + step >= distance, step > 0 {
                let t = (b - a).normalized
                return (a + t * (distance - walked), t, t.perpendicular)
            }
            walked += step
        }
        let t = (last - points[points.count - 2]).normalized
        return (last + t * (distance - total), t, t.perpendicular)
    }
}

/// The spine pushed sideways: the line a hand actually drew.
private struct Track {
    let points: [CGPoint]
    let tangents: [CGVector]
    let fractions: [CGFloat]

    init(_ stations: [ArrowSpine.Station], offset: (CGFloat) -> CGFloat) {
        let total = stations.last?.distance ?? 0
        var points: [CGPoint] = []
        var fractions: [CGFloat] = []
        for station in stations {
            let u = total > 0 ? station.distance / total : 0
            points.append(station.point + station.direction.perpendicular * offset(u))
            fractions.append(u)
        }
        self.points = points
        self.fractions = fractions
        tangents = Self.tangents(of: points)
    }

    static func tangents(of points: [CGPoint]) -> [CGVector] {
        points.indices.map { i in
            let a = points[max(i - 1, 0)]
            let b = points[min(i + 1, points.count - 1)]
            let d = b - a
            return hypot(d.dx, d.dy) > 1e-9 ? d.normalized : CGVector(dx: 1, dy: 0)
        }
    }

    var tip: CGPoint { points.last ?? .zero }

    /// The way back from the tip along the drawn line, read over `reach` so a
    /// tremor right at the end does not swing the head.
    func backAtTip(reach: CGFloat) -> CGVector {
        let tip = self.tip
        for p in points.reversed() where hypot(p.x - tip.x, p.y - tip.y) >= reach {
            return (p - tip).normalized
        }
        guard let first = points.first, hypot(first.x - tip.x, first.y - tip.y) > 1e-9 else {
            return CGVector(dx: -1, dy: 0)
        }
        return (first - tip).normalized
    }

    /// The point, direction and left-hand normal `u` of the way along.
    func sample(_ u: CGFloat) -> (point: CGPoint, tangent: CGVector, normal: CGVector) {
        guard points.count >= 2 else {
            return (points.first ?? .zero, CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1))
        }
        let scaled = min(max(u, 0), 1) * CGFloat(points.count - 1)
        let i = min(Int(scaled), points.count - 2)
        let f = scaled - CGFloat(i)
        let a = points[i], b = points[i + 1]
        let point = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        let t = (tangents[i] * (1 - f) + tangents[i + 1] * f).normalized
        return (point, t, t.perpendicular)
    }
}

// MARK: - Vector arithmetic

private extension CGVector {
    var normalized: CGVector {
        let length = hypot(dx, dy)
        return length > 1e-12 ? CGVector(dx: dx / length, dy: dy / length) : CGVector(dx: 1, dy: 0)
    }
    /// A quarter turn: the left-hand side of the direction in screen space.
    var perpendicular: CGVector { CGVector(dx: -dy, dy: dx) }
    func rotated(by angle: CGFloat) -> CGVector {
        CGVector(dx: dx * cos(angle) - dy * sin(angle), dy: dx * sin(angle) + dy * cos(angle))
    }
    static func * (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
}

private extension CGPoint {
    static func + (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x + v.dx, y: p.y + v.dy) }
    static func - (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x - v.dx, y: p.y - v.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}
