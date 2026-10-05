import CoreGraphics
import Foundation

/// Rounding a path's sharp corners without moving its points: each corner
/// carries a radius (`PathAnchor.cornerRadius`), and the outline that is DRAWN
/// cuts the corner back along both edges and bridges the cut with an arc. The
/// same live corners Figma and Illustrator have, so a polygon drawn with the Pen
/// can be softened by pulling a knob in from its corner and sharpened again by
/// pushing it back out.
///
/// The cut is measured ALONG the two runs that meet at the corner, so a corner
/// where a curve arrives is cut into the curve itself rather than into its
/// chord. Between two straight runs the bridge is the true circular arc of the
/// radius asked for, to within the error of a four-control-point arc (a few
/// ten-thousandths of the radius).
///
/// Everything that draws a path reads `drawnOutline`: the canvas, the rings
/// round it, an area operation and SVG export (`cgPath`, `SVGExport.pathData`).
/// Everything that EDITS a path goes on reading the points.

/// What the one Corner Radius number reads over a path's corners.
public struct PathCornerRadiusReading: Hashable, Sendable {
    /// The radius every corner wears, or the roundest of them when they differ.
    public let radius: CGFloat
    /// True when the corners do not all wear the same radius.
    public let isMixed: Bool

    public init(radius: CGFloat, isMixed: Bool) {
        self.radius = radius
        self.isMixed = isMixed
    }
}

/// The small round knob just inside a sharp corner, in the layer's own
/// coordinates.
public struct PathCornerKnob: Hashable, Sendable {
    /// The anchor whose corner it rounds.
    public let index: Int
    /// Where it sits.
    public let point: CGPoint
    /// The way it travels as the corner rounds: straight into the corner's
    /// angle, along the line that halves it.
    public let direction: CGPoint
}

extension PathContent {

    /// How far in from a sharp corner its knob rests, in screen points, along
    /// the line halving the corner.
    ///
    /// Sixteen keeps the knob's six point target clear of the point's own
    /// eight, so a press aimed at the point never comes back as a rounding.
    public static let cornerKnobRest: CGFloat = 16

    /// How near a press has to land to a knob to catch it, in screen points:
    /// the slop every handle on a selection has.
    public static let cornerKnobTolerance: CGFloat = 6

    // MARK: - Which corners round

    /// The anchors that are sharp corners: a point with a run arriving and a
    /// run leaving, meant as a corner, where the line really turns. A smooth
    /// bend, a point in the middle of a straight run and the two ends of an
    /// open line have no corner to round.
    public var roundableCorners: [Int] {
        cornerGeometry().keys.sorted()
    }

    /// Whether this anchor is a corner that can be rounded.
    public func isRoundableCorner(_ index: Int) -> Bool {
        cornerGeometry()[index] != nil
    }

    /// Whether anything about this path is rounded at all.
    public var hasRoundedCorners: Bool {
        !cornerCuts().isEmpty
    }

    /// The radius this corner is actually DRAWN with: what it asked for, or as
    /// much of it as the two edges either side can hold. Nought for a point
    /// that is not a rounded corner.
    public func drawnCornerRadius(at index: Int) -> CGFloat {
        guard let corner = cornerGeometry()[index], let cut = cornerCuts()[index] else { return 0 }
        return cut / corner.tanHalfTurn
    }

    /// What the one Corner Radius number reads, or nil when the path has no
    /// corner to round.
    public var cornerRadiusReading: PathCornerRadiusReading? {
        let radii = roundableCorners.map { anchors[$0].cornerRadius }
        guard let first = radii.first else { return nil }
        let mixed = radii.contains { abs($0 - first) > 1e-9 }
        return PathCornerRadiusReading(radius: radii.max() ?? first, isMixed: mixed)
    }

    /// Rounds one corner. A point that is not a corner is left as it is.
    public mutating func setCornerRadius(_ radius: CGFloat, at index: Int) {
        guard isRoundableCorner(index) else { return }
        anchors[index].cornerRadius = max(0, radius)
    }

    /// Rounds every corner the same, which is what one number means.
    public mutating func setCornerRadius(_ radius: CGFloat) {
        for index in roundableCorners { anchors[index].cornerRadius = max(0, radius) }
    }

    /// The roundest this corner can be drawn.
    ///
    /// `allCorners` is the question a pull on the knob asks when every corner
    /// rounds together: each edge is shared by the corners at both its ends,
    /// in proportion to how sharp each is, so on a regular polygon every
    /// corner stops where the arcs meet in the middle of the edges. Alone, the
    /// corner may take whatever its neighbours have not already spent.
    public func cornerRadiusLimit(at index: Int, allCorners: Bool) -> CGFloat {
        let corners = cornerGeometry()
        guard let corner = corners[index] else { return 0 }
        let others: [Int: CGFloat]
        if allCorners {
            others = [:]
        } else {
            var alone = self
            alone.anchors[index].cornerRadius = 0
            others = alone.cornerCuts()
        }
        var limit = CGFloat.infinity
        for (length, neighbour) in [(corner.inLength, corner.previous),
                                    (corner.outLength, corner.next)] {
            if allCorners {
                let theirs = corners[neighbour].map(\.tanHalfTurn) ?? 0
                limit = min(limit, length / (corner.tanHalfTurn + theirs))
            } else {
                limit = min(limit, max(0, length - (others[neighbour] ?? 0)) / corner.tanHalfTurn)
            }
        }
        return limit.isFinite ? limit : 0
    }

    // MARK: - The knob

    /// The knob for one corner at this zoom, or nil when the point is not a
    /// corner or the corner is too small on screen to carry one: a knob that
    /// lands on top of the next point is a knob nobody can aim at.
    ///
    /// It rides the CENTRE of the corner's arc, plus its resting distance, so
    /// it travels exactly as far as the hand does (`CornerRadiusHandles`, the
    /// rectangle's own dots, make the same choice for the same reason).
    public func cornerKnob(at index: Int, zoom: CGFloat) -> PathCornerKnob? {
        guard let corner = cornerGeometry()[index] else { return nil }
        return knob(index, corner, cut: cornerCuts()[index] ?? 0, zoom: zoom)
    }

    /// Every knob showing at this zoom, in anchor order.
    public func cornerKnobs(zoom: CGFloat) -> [PathCornerKnob] {
        // The corners and the cuts are worked out once for the lot, not once
        // per knob: this runs on every pointer move over a picked path.
        let corners = cornerGeometry()
        let cuts = cornerCuts()
        return corners.keys.sorted().compactMap { index in
            corners[index].flatMap { knob(index, $0, cut: cuts[index] ?? 0, zoom: zoom) }
        }
    }

    private func knob(_ index: Int, _ corner: CornerGeometry, cut: CGFloat,
                      zoom: CGFloat) -> PathCornerKnob? {
        let z = zoom > 0 ? zoom : 1
        guard min(corner.inLength, corner.outLength) * z >= 2 * Self.cornerKnobRest else {
            return nil
        }
        let radius = cut / corner.tanHalfTurn
        let along = Self.cornerKnobRest / z + radius / corner.cosHalfTurn
        return PathCornerKnob(index: index,
                              point: CGPoint(x: corner.point.x + corner.bisector.x * along,
                                             y: corner.point.y + corner.bisector.y * along),
                              direction: corner.bisector)
    }

    /// The corner whose knob a press at `point` caught, nearest first.
    public func cornerKnobHit(at point: CGPoint, zoom: CGFloat) -> Int? {
        let z = zoom > 0 ? zoom : 1
        var best: (index: Int, distance: CGFloat)?
        for knob in cornerKnobs(zoom: zoom) {
            let d = hypot(point.x - knob.point.x, point.y - knob.point.y)
            guard d <= Self.cornerKnobTolerance / z, d < (best?.distance ?? .infinity) else { continue }
            best = (knob.index, d)
        }
        return best?.index
    }

    /// The radius a knob dragged to `point` asks its corner for: how far in
    /// along the corner's halving line the pointer is, past the knob's resting
    /// place. Pushed back out past that place the corner is sharp again.
    public func cornerRadius(draggingKnobAt index: Int, to point: CGPoint,
                             zoom: CGFloat) -> CGFloat {
        guard let corner = cornerGeometry()[index] else { return 0 }
        let z = zoom > 0 ? zoom : 1
        let along = (point.x - corner.point.x) * corner.bisector.x
            + (point.y - corner.point.y) * corner.bisector.y
        return max(0, (along - Self.cornerKnobRest / z) * corner.cosHalfTurn)
    }

    /// The radius a knob pull lands on.
    ///
    /// With the grid pulling, whole grid steps, the same steps a point drawn
    /// with the Pen lands on, so an icon on a 24 unit grid rounds by 1, 2 or
    /// 3 units. With nothing pulling (no grid, or ⌘ held, the key that frees
    /// every drag on the canvas), whole points, or half points once the canvas
    /// is zoomed in far enough for half a point to be something a hand can
    /// place.
    public static func landedCornerRadius(_ radius: CGFloat, gridSpacing: CGFloat?,
                                          zoom: CGFloat) -> CGFloat {
        let radius = max(0, radius)
        if let gridSpacing, gridSpacing.isFinite, gridSpacing > 0 {
            return (radius / gridSpacing).rounded() * gridSpacing
        }
        let step: CGFloat = zoom >= 4 ? 0.5 : 1
        return (radius / step).rounded() * step
    }

    // MARK: - The drawn outline

    /// The outline as it is drawn: every rounded corner cut back and bridged
    /// by its arc, stated as plain anchors with no radius left on them. The
    /// path itself when nothing is rounded, so a sharp path costs nothing.
    public var drawnOutline: PathContent {
        guard anchors.contains(where: { $0.cornerRadius > 0 }) else { return self }
        let cuts = cornerCuts()
        var drawn = self
        guard !cuts.isEmpty else {
            for i in drawn.anchors.indices { drawn.anchors[i].cornerRadius = 0 }
            return drawn
        }
        let corners = cornerGeometry()
        var out: [PathAnchor] = []
        var starts: [Int] = []
        for range in ringRanges {
            if !out.isEmpty { starts.append(out.count) }
            out += roundedRing(range, cuts: cuts, corners: corners)
        }
        drawn.anchors = out
        drawn.ringStarts = PathContent.tidyRingStarts(starts, count: out.count)
        return drawn
    }

    /// One ring with its corners rounded.
    private func roundedRing(_ range: Range<Int>, cuts: [Int: CGFloat],
                             corners: [Int: CornerGeometry]) -> [PathAnchor] {
        let ring = Array(anchors[range])
        let n = ring.count
        func sharp(_ anchor: PathAnchor) -> PathAnchor {
            var plain = anchor
            plain.cornerRadius = 0
            return plain
        }
        guard n >= 2 else { return ring.map(sharp) }
        let runCount = isClosed ? n : n - 1
        // Each run trimmed back from both ends by whatever the corners at its
        // ends cut out of it.
        let runs: [TrimmedRun] = (0..<runCount).map { k in
            let a = k, b = (k + 1) % n
            return TrimmedRun(PathSegment(from: ring[a], to: ring[b]),
                              startCut: cuts[range.lowerBound + a] ?? 0,
                              endCut: cuts[range.lowerBound + b] ?? 0)
        }
        var out: [PathAnchor] = []
        for i in 0..<n {
            let arriving: Int? = i > 0 ? i - 1 : (isClosed ? n - 1 : nil)
            let leaving: Int? = i < n - 1 ? i : (isClosed ? n - 1 : nil)
            let global = range.lowerBound + i
            if let cut = cuts[global], let corner = corners[global],
               let arriving, let leaving {
                let into = runs[arriving], outOf = runs[leaving]
                let radius = cut / corner.tanHalfTurn
                // The arc's two levers lie along the edges it leaves, each the
                // length a four-point arc of this turn needs.
                let lever = radius * 4 / 3 * tan(corner.turn / 4)
                let towards = into.endTangent, away = outOf.startTangent
                out.append(PathAnchor(point: into.end, handleIn: into.handleIntoEnd,
                                      handleOut: CGPoint(x: towards.x * lever, y: towards.y * lever)))
                out.append(PathAnchor(point: outOf.start,
                                      handleIn: CGPoint(x: -away.x * lever, y: -away.y * lever),
                                      handleOut: outOf.handleOutOfStart))
            } else {
                var kept = sharp(ring[i])
                if let arriving { kept.handleIn = runs[arriving].handleIntoEnd }
                if let leaving { kept.handleOut = runs[leaving].handleOutOfStart }
                out.append(kept)
            }
        }
        return Self.mergingMeetings(out, closed: isClosed)
    }

    /// Two arcs that meet in the middle of an edge leave a point at the same
    /// place twice with a run of no length between them. They are made one
    /// point, so the drawing (and the file) carries no empty step.
    private static func mergingMeetings(_ ring: [PathAnchor], closed: Bool) -> [PathAnchor] {
        guard ring.count >= 2 else { return ring }
        func meets(_ a: PathAnchor, _ b: PathAnchor) -> Bool {
            a.handleOut == nil && b.handleIn == nil
                && hypot(a.point.x - b.point.x, a.point.y - b.point.y) < 1e-6
        }
        var out: [PathAnchor] = []
        for anchor in ring {
            if let last = out.last, meets(last, anchor) {
                out[out.count - 1].handleOut = anchor.handleOut
            } else {
                out.append(anchor)
            }
        }
        if closed, out.count >= 2, let last = out.last, let first = out.first, meets(last, first) {
            out[0].handleIn = last.handleIn
            out.removeLast()
        }
        return out
    }

    // MARK: - The corners themselves

    /// What one sharp corner is like.
    struct CornerGeometry {
        let point: CGPoint
        /// The global indices of the anchors before and after it.
        let previous: Int
        let next: Int
        /// How far the line turns here, in radians, between nought (straight
        /// on) and π (doubling back).
        let turn: CGFloat
        /// Unit vector halving the angle between the two edges, pointing into
        /// it: where the arc's centre lies.
        let bisector: CGPoint
        /// How long the run arriving here and the run leaving here are.
        let inLength: CGFloat
        let outLength: CGFloat

        /// How far along each edge a radius of one cuts the corner back.
        var tanHalfTurn: CGFloat { tan(turn / 2) }
        /// A radius over this is how far the arc's centre is from the corner.
        var cosHalfTurn: CGFloat { cos(turn / 2) }
    }

    /// Every roundable corner, by global anchor index.
    func cornerGeometry() -> [Int: CornerGeometry] {
        var found: [Int: CornerGeometry] = [:]
        for range in ringRanges {
            let n = range.count
            guard n >= 3 else { continue }
            for i in 0..<n {
                guard isClosed || (i > 0 && i < n - 1) else { continue }
                let global = range.lowerBound + i
                let anchor = anchors[global]
                guard anchor.kind == .corner else { continue }
                let previous = range.lowerBound + (i + n - 1) % n
                let next = range.lowerBound + (i + 1) % n
                let into = PathSegment(from: anchors[previous], to: anchor)
                let outOf = PathSegment(from: anchor, to: anchors[next])
                let inLength = into.length, outLength = outOf.length
                guard inLength > 1e-9, outLength > 1e-9,
                      let u = into.endTangent, let v = outOf.startTangent else { continue }
                let dot = max(-1, min(1, u.x * v.x + u.y * v.y))
                let turn = acos(dot)
                // Under a degree is a point in the middle of a run; within a
                // degree of doubling back there is no corner left to fit an arc
                // in.
                let degree = CGFloat.pi / 180
                guard turn > degree, turn < .pi - degree else { continue }
                let back = CGPoint(x: v.x - u.x, y: v.y - u.y)
                let length = hypot(back.x, back.y)
                guard length > 1e-12 else { continue }
                found[global] = CornerGeometry(
                    point: anchor.point, previous: previous, next: next, turn: turn,
                    bisector: CGPoint(x: back.x / length, y: back.y / length),
                    inLength: inLength, outLength: outLength)
            }
        }
        return found
    }

    /// How far back along each edge every rounded corner is cut, by global
    /// anchor index, once each edge has been shared out between the corners at
    /// its two ends. Only corners that are actually cut appear.
    ///
    /// An edge too short for both its corners is shared in proportion to what
    /// each asked for, so neither overshoots and the two arcs meet in the
    /// middle at worst. A corner takes the smaller of what its two edges allow.
    func cornerCuts() -> [Int: CGFloat] {
        guard anchors.contains(where: { $0.cornerRadius > 0 }) else { return [:] }
        let corners = cornerGeometry()
        var wanted: [Int: CGFloat] = [:]
        for (index, corner) in corners where anchors[index].cornerRadius > 0 {
            wanted[index] = anchors[index].cornerRadius * corner.tanHalfTurn
        }
        guard !wanted.isEmpty else { return [:] }
        func allowed(_ index: Int, _ length: CGFloat, against other: Int) -> CGFloat {
            let mine = wanted[index] ?? 0
            let theirs = wanted[other] ?? 0
            guard mine + theirs > length else { return mine }
            return length * mine / (mine + theirs)
        }
        var cuts: [Int: CGFloat] = [:]
        for (index, mine) in wanted {
            guard let corner = corners[index] else { continue }
            let cut = min(mine,
                          allowed(index, corner.inLength, against: corner.previous),
                          allowed(index, corner.outLength, against: corner.next))
            if cut > 1e-9 { cuts[index] = cut }
        }
        return cuts
    }
}

// MARK: - Measuring and cutting one run

extension PathSegment {

    /// How long the run is, along the curve.
    var length: CGFloat {
        guard !isStraight else { return hypot(end.x - start.x, end.y - start.y) }
        return arcLengths().last ?? 0
    }

    /// The running length at each of `steps` even steps of `t`, from 0.
    func arcLengths(steps: Int = 64) -> [CGFloat] {
        var lengths: [CGFloat] = [0]
        var previous = start
        for i in 1...steps {
            let p = point(at: CGFloat(i) / CGFloat(steps))
            lengths.append((lengths.last ?? 0) + hypot(p.x - previous.x, p.y - previous.y))
            previous = p
        }
        return lengths
    }

    /// The `t` that lies `distance` along the curve from its start.
    func parameter(atLength distance: CGFloat) -> CGFloat {
        guard !isStraight else {
            let whole = length
            return whole > 0 ? min(max(distance / whole, 0), 1) : 0
        }
        let lengths = arcLengths()
        let steps = lengths.count - 1
        guard let total = lengths.last, total > 0 else { return 0 }
        if distance <= 0 { return 0 }
        if distance >= total { return 1 }
        var i = 1
        while i < steps && lengths[i] < distance { i += 1 }
        let span = lengths[i] - lengths[i - 1]
        let within = span > 0 ? (distance - lengths[i - 1]) / span : 0
        return (CGFloat(i - 1) + within) / CGFloat(steps)
    }

    /// The direction the run is travelling as it arrives at its end, or nil
    /// for a run of no length.
    var endTangent: CGPoint? {
        for from in [control2, control1, start]
        where hypot(end.x - from.x, end.y - from.y) > 1e-9 {
            return Self.unit(CGPoint(x: end.x - from.x, y: end.y - from.y))
        }
        return nil
    }

    /// The direction the run sets off in from its start.
    var startTangent: CGPoint? {
        for to in [control1, control2, end]
        where hypot(to.x - start.x, to.y - start.y) > 1e-9 {
            return Self.unit(CGPoint(x: to.x - start.x, y: to.y - start.y))
        }
        return nil
    }

    static func unit(_ v: CGPoint) -> CGPoint {
        let length = hypot(v.x, v.y)
        return length > 0 ? CGPoint(x: v.x / length, y: v.y / length) : .zero
    }
}

/// A run with a piece cut off one or both ends, as four control points.
private struct TrimmedRun {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
    let isStraight: Bool
    /// The directions it leaves its start and arrives at its end in, which
    /// the arc either side continues.
    let startTangent: CGPoint
    let endTangent: CGPoint

    init(_ run: PathSegment, startCut: CGFloat, endCut: CGFloat) {
        let whole = run.length
        let t0 = startCut > 0 ? run.parameter(atLength: startCut) : 0
        let t1 = endCut > 0 ? run.parameter(atLength: whole - endCut) : 1
        isStraight = run.isStraight
        if run.isStraight {
            func lerp(_ t: CGFloat) -> CGPoint {
                CGPoint(x: run.start.x + (run.end.x - run.start.x) * t,
                        y: run.start.y + (run.end.y - run.start.y) * t)
            }
            start = lerp(t0)
            end = lerp(max(t0, t1))
            control1 = start
            control2 = end
        } else {
            let piece = Self.piece(of: run, from: t0, to: max(t0, t1))
            start = piece[0]; control1 = piece[1]; control2 = piece[2]; end = piece[3]
        }
        // The cut ends keep the direction the original run had THERE, which a
        // piece of a curve says through its own control points; a piece with
        // no length left falls back on the run's own direction.
        let trimmed = PathSegment(start: start, control1: control1, control2: control2,
                                  end: end, isStraight: isStraight)
        startTangent = trimmed.startTangent ?? run.startTangent ?? .zero
        endTangent = trimmed.endTangent ?? run.endTangent ?? .zero
    }

    /// The lever this run leaves its start with, nil when it leaves straight.
    var handleOutOfStart: CGPoint? {
        guard !isStraight else { return nil }
        let lever = CGPoint(x: control1.x - start.x, y: control1.y - start.y)
        return hypot(lever.x, lever.y) > 1e-9 ? lever : nil
    }

    /// The lever it arrives at its end with, nil when it arrives straight.
    var handleIntoEnd: CGPoint? {
        guard !isStraight else { return nil }
        let lever = CGPoint(x: control2.x - end.x, y: control2.y - end.y)
        return hypot(lever.x, lever.y) > 1e-9 ? lever : nil
    }

    /// The four control points of the stretch of `run` between `t0` and `t1`.
    static func piece(of run: PathSegment, from t0: CGFloat, to t1: CGFloat) -> [CGPoint] {
        // Cut at t1 and keep the front, then cut that at the matching place
        // and keep the back.
        let front = split(run.start, run.control1, run.control2, run.end, at: t1).front
        guard t1 > 1e-12 else { return [front[0], front[0], front[0], front[0]] }
        return split(front[0], front[1], front[2], front[3], at: t0 / t1).back
    }

    static func split(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint,
                      at t: CGFloat) -> (front: [CGPoint], back: [CGPoint]) {
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let a = lerp(p0, p1), b = lerp(p1, p2), c = lerp(p2, p3)
        let d = lerp(a, b), e = lerp(b, c)
        let f = lerp(d, e)
        return ([p0, a, d, f], [f, e, c, p3])
    }
}
