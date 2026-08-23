import CoreGraphics
import Foundation

/// Finds the UI element under a probe point in a screenshot, for the Measure
/// tool's **Size** mode and the gap it reads in **Gap** mode (Next release).
///
/// A screenshot has no semantic UI tree, so "the element under the pointer" is
/// read from the same windowed `EdgeMap` queries snapping uses: from the probe,
/// walk each of the four directions for the nearest accepted edge, querying the
/// perpendicular window centered on the probe. Each side is taken at its
/// PROBE-SIDE luma landing (the visually clean position hugging the element,
/// the exact rule `EdgeSnapping` applies), so the rect reads the number a
/// redliner would measure to. All four sides within `maxRadius` make the rect;
/// any side missing is a quiet miss (`nil`) — never a wrong box. Nested
/// elements resolve to the innermost rect because the nearest edge per
/// direction wins by construction.
///
/// A flat bitmap carries no semantic tree, so the innermost rect is a GUESS,
/// and the audit of 2026-08-23 measured how often it is the wrong one (a
/// button's glyph strokes beat its border; a settings row stops at its label).
/// `candidates` therefore returns the whole nested ladder, innermost first, so
/// Size mode can offer `[` and `]` to shrink and grow the pick instead of
/// handing over one wrong number with no recourse.
public enum ElementBounds {

    /// How far from the probe (image px) each directional walk reaches before
    /// giving up.
    public static let defaultMaxRadius: Double = 600

    /// How many nested candidates the ladder is capped at. Long enough to reach
    /// a card from inside a glyph, short enough that `[` / `]` stays a handful
    /// of presses rather than an endless scroll.
    public static let candidateLimit = 10

    /// Two candidates this close on every side are the same element read twice
    /// (an antialiased border comes back as a pair of peaks, and a bold-edge
    /// reading often lands a few pixels off a nearest-edge one), so the outer one
    /// is dropped. Sized so that every press of `]` visibly changes the pick
    /// rather than nudging it.
    private static let candidateMinGrowth: Double = 12

    /// How much bigger each rung has to be than the one before it, by area. The
    /// raw walk emits a rung per glyph stroke, which would make `]` a dozen
    /// presses to cross one word; thinning to real jumps in scale keeps the
    /// ladder to a handful of presses that each visibly change the pick.
    private static let candidateScaleStep: Double = 1.35

    /// How bold an edge has to be, as a fraction of the boldest one that
    /// direction offers, to count for the strong ladder. 0.8 was measured on a
    /// real capture: it keeps a button's border and drops the text inside it.
    private static let strongFraction: Double = 0.8

    /// Half-width of the perpendicular query window centered on the probe —
    /// the same locality snapping's fallback window uses, so hover accepts the
    /// same edges a foot drag would land on.
    public static let defaultSpanRadius: Double = 32

    /// The element rect at `point`: the innermost candidate, or nil when no
    /// candidate is readable (including the not-yet-computed `EdgeMap.empty`).
    public static func detect(at point: CGPoint, in edges: EdgeMap,
                              maxRadius: Double = defaultMaxRadius,
                              spanRadius: Double = defaultSpanRadius) -> CGRect? {
        candidates(at: point, in: edges, maxRadius: maxRadius, spanRadius: spanRadius,
                   limit: 1).first
    }

    /// The nested ladder of element rects around `point`, innermost first, each
    /// containing the one before it. Empty when nothing is readable.
    ///
    /// Built by growing outward one edge at a time: start from the nearest
    /// accepted edge on each of the four sides, then repeatedly step whichever
    /// side's next edge is closest. A rung that does not enclose the probe (the
    /// probe-side landings can invert across a glyph, which is why a button used
    /// to read nothing at all) is skipped rather than ending the walk.
    public static func candidates(at point: CGPoint, in edges: EdgeMap,
                                  maxRadius: Double = defaultMaxRadius,
                                  spanRadius: Double = defaultSpanRadius,
                                  limit: Int = candidateLimit) -> [CGRect] {
        guard !edges.isEmpty, maxRadius > 0, limit > 0 else { return [] }
        let px = Double(point.x), py = Double(point.y)
        let sides = sides(at: point, in: edges, maxRadius: maxRadius, spanRadius: spanRadius)
        guard sides.allSatisfy({ !$0.isEmpty }) else { return [] }

        // Two ladders, merged. The NEAREST ladder answers "the smallest thing
        // around the pointer", which is right for a field or a toggle and wrong
        // inside a button, where every rung is another glyph. The STRONG ladder
        // ignores everything but the boldest edges each direction offers, which
        // is what a border is, so the button appears a press or two in instead of
        // a dozen. Merged by area, the list stays a plain grow-outward ladder.
        let nearest = ladder(sides, px: px, py: py).map { (rect: $0, isStrong: false) }
        let strong = ladder(sides.map(strongest), px: px, py: py).map { (rect: $0, isStrong: true) }
        var merged: [CGRect] = []
        var lastArea: Double = 0
        for rung in (nearest + strong)
            .sorted(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) {
            let area = Double(rung.rect.width * rung.rect.height)
            guard grows(rung.rect, beyond: merged.last) else { continue }
            // Thinning keeps the ladder to a handful of presses, but a rung read
            // off bold edges is the most likely to be an actual border, so it
            // never gets thinned away by a neighbour of a similar size.
            guard rung.isStrong || merged.isEmpty || area >= lastArea * candidateScaleStep
            else { continue }
            merged.append(rung.rect)
            lastArea = area
            if merged.count >= limit { break }
        }
        return merged
    }

    /// Walks one set of side candidates outward, innermost rect first: start at
    /// the nearest accepted edge on each side, then repeatedly step whichever
    /// side's next edge is closest. A rung that does not enclose the probe (the
    /// probe-side landings can invert across a glyph, which is why a button used
    /// to read nothing at all) is skipped rather than ending the walk.
    private static func ladder(_ sides: [[Side]], px: Double, py: Double) -> [CGRect] {
        guard sides.allSatisfy({ !$0.isEmpty }) else { return [] }
        var index = [0, 0, 0, 0]
        var found: [CGRect] = []
        // One step per available edge across all four sides, so the walk always
        // terminates even if every rung is rejected.
        let budget = sides.reduce(0) { $0 + $1.count }
        for _ in 0...budget {
            let minY = sides[0][index[0]].landing, maxY = sides[1][index[1]].landing
            let minX = sides[2][index[2]].landing, maxX = sides[3][index[3]].landing
            if maxX > minX, maxY > minY, minX <= px, px <= maxX, minY <= py, py <= maxY {
                let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                if grows(rect, beyond: found.last) { found.append(rect) }
            }
            // Step the side whose next edge is nearest — the ladder grows by the
            // smallest possible amount each rung.
            var next: (side: Int, distance: Double)?
            for side in 0..<4 where index[side] + 1 < sides[side].count {
                let distance = sides[side][index[side] + 1].distance
                if distance < (next?.distance ?? .infinity) { next = (side, distance) }
            }
            guard let next else { break }
            index[next.side] += 1
        }
        return found
    }

    /// One side's candidates thinned to the boldest ones: everything within
    /// `strongFraction` of that side's strongest edge. A button's border survives
    /// this; the text inside it does not.
    private static func strongest(_ side: [Side]) -> [Side] {
        guard let peak = side.map(\.strength).max(), peak > 0 else { return side }
        return side.filter { $0.strength >= peak * strongFraction }
    }

    /// The gap under `point`: the two facing edges of whatever sits on either
    /// side of it, across the tighter of the two axes. Nil when neither axis has
    /// a pair of edges to read.
    ///
    /// Unlike an element, a gap needs only ONE axis to work: the space between
    /// two stacked cards has a top and a bottom and no sides at all, and
    /// refusing to measure it because the sides are missing would fail the most
    /// ordinary case there is. When both axes read, the shorter span wins,
    /// because the tighter one is what a person means by "the gap".
    public static func gap(at point: CGPoint, in edges: EdgeMap,
                           maxRadius: Double = defaultMaxRadius,
                           spanRadius: Double = defaultSpanRadius) -> GapMeasurement? {
        let px = Double(point.x), py = Double(point.y)
        let sides = sides(at: point, in: edges, maxRadius: maxRadius, spanRadius: spanRadius)
        var best: GapMeasurement?
        if let minY = sides[0].first?.landing, let maxY = sides[1].first?.landing,
           maxY > minY, minY <= py, py <= maxY {
            best = GapMeasurement(axis: .vertical,
                                  start: CGPoint(x: point.x, y: minY),
                                  end: CGPoint(x: point.x, y: maxY))
        }
        if let minX = sides[2].first?.landing, let maxX = sides[3].first?.landing,
           maxX > minX, minX <= px, px <= maxX {
            let horizontal = GapMeasurement(axis: .horizontal,
                                            start: CGPoint(x: minX, y: point.y),
                                            end: CGPoint(x: maxX, y: point.y))
            if best.map({ horizontal.length <= $0.length }) ?? true { best = horizontal }
        }
        return best
    }

    /// Whether a rung is far enough outside the previous one to be worth
    /// offering as a separate pick.
    private static func grows(_ rect: CGRect, beyond previous: CGRect?) -> Bool {
        guard let previous else { return true }
        return Double(previous.minX - rect.minX) >= candidateMinGrowth
            || Double(previous.minY - rect.minY) >= candidateMinGrowth
            || Double(rect.maxX - previous.maxX) >= candidateMinGrowth
            || Double(rect.maxY - previous.maxY) >= candidateMinGrowth
    }

    /// One accepted edge on one side of the probe.
    private struct Side {
        var distance: Double
        var landing: Double
        var strength: Double
    }

    /// The four sides' candidates, in the fixed order minY, maxY, minX, maxX,
    /// each nearest first.
    private static func sides(at point: CGPoint, in edges: EdgeMap,
                              maxRadius: Double, spanRadius: Double) -> [[Side]] {
        guard !edges.isEmpty, maxRadius > 0 else { return [[], [], [], []] }
        let px = Double(point.x), py = Double(point.y)
        // One query per axis serves both of that axis's directions.
        let horizontal = edges.horizontalEdges(inXRange: (px - spanRadius)...(px + spanRadius))
        let vertical = edges.verticalEdges(inYRange: (py - spanRadius)...(py + spanRadius))
        return [
            sideLandings(horizontal, probe: py, lowerSide: true, maxRadius: maxRadius),
            sideLandings(horizontal, probe: py, lowerSide: false, maxRadius: maxRadius),
            sideLandings(vertical, probe: px, lowerSide: true, maxRadius: maxRadius),
            sideLandings(vertical, probe: px, lowerSide: false, maxRadius: maxRadius),
        ]
    }

    /// Every accepted candidate on one side (`lowerSide` = positions at or below
    /// the probe coordinate) within `maxRadius`, nearest first, each read at its
    /// probe-side landing. The probe sits on the element side of the edge, so
    /// above the probe that is the after-side landing and below it the
    /// before-side.
    private static func sideLandings(_ candidates: [EdgeCandidate], probe: Double,
                                     lowerSide: Bool, maxRadius: Double) -> [Side] {
        candidates
            .filter { lowerSide ? $0.position <= probe : $0.position > probe }
            .map { Side(distance: abs(probe - $0.position),
                        landing: lowerSide ? $0.edgeAfter : $0.edgeBefore,
                        strength: $0.strength) }
            .filter { $0.distance <= maxRadius }
            .sorted { $0.distance < $1.distance }
    }
}

/// One gap reading: the two facing edges of the elements on either side of the
/// click, and the axis they face across. Rendered by the SAME caliper every
/// other mode produces — a gap has no look of its own.
public struct GapMeasurement: Equatable, Sendable {
    public var axis: MeasureMode
    public var start: CGPoint
    public var end: CGPoint

    public init(axis: MeasureMode, start: CGPoint, end: CGPoint) {
        self.axis = axis
        self.start = start
        self.end = end
    }

    /// The gap's width in document pixels.
    public var length: CGFloat {
        axis == .horizontal ? abs(end.x - start.x) : abs(end.y - start.y)
    }
}
