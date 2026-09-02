import CoreGraphics
import Foundation

/// Finds the UI element under a probe point in a screenshot, for the Measure
/// tool's **Size** mode and the gap it reads in **Gap** mode (Next release).
///
/// A screenshot has no semantic UI tree, so "the element under the pointer" is
/// read from the picture. Two signals, and both are needed:
///
/// - `EdgeMap` says WHERE the boundaries are. It is block-summed, so it finds
///   them cheaply and to the pixel in the direction that matters, but it cannot
///   say how far along a boundary runs.
/// - `LumaField` says HOW FAR each one reaches (`EdgeRun`). That is what
///   separates the hairline under one settings row from the card border a few
///   pixels wider, which is exactly the difference between reading a row and
///   grabbing the whole card.
///
/// So an element is built from a PAIR of horizontal boundaries — one above the
/// pointer, one below — whose runs agree with each other. Agreement is the whole
/// trick: a button's top and bottom borders start and stop together, while a
/// glyph's baseline stops where the word does and never lines up with the
/// button's top. The agreed run gives the element's width; nearby vertical
/// boundaries sharpen its left and right, since a border reads more precisely
/// than the end of a run. Sides are placed at the OUTER boundary estimate — half
/// way between the gradient peak and the first clean background pixel outside
/// it — so a button measures the width a spec would quote, not the width of its
/// inside.
///
/// Every rung that survives is offered, innermost first, so Size mode's `[` and
/// `]` can shrink and grow the pick when the guess is not the element the person
/// meant. Nothing readable is a quiet miss (`nil`) — never a wrong box.
///
/// Both signals come from one analysis pass, so both arrive together: until the
/// screenshot has been analyzed there is no edge map and no brightness field and
/// detection is quiet, which is the same gate snapping already waits on.
public enum ElementBounds {

    /// How far from the probe (image px) each directional walk reaches before
    /// giving up.
    public static let defaultMaxRadius: Double = 600

    /// How many nested candidates the ladder is capped at. Long enough to reach
    /// a card from inside a button, short enough that `[` / `]` stays a handful
    /// of presses rather than an endless scroll.
    public static let candidateLimit = 10

    /// Two candidates this close on every side are the same element read twice,
    /// so the outer one is dropped. Sized so that every press of `]` visibly
    /// changes the pick rather than nudging it.
    private static let candidateMinGrowth: Double = 12

    /// How bold a boundary has to be, relative to the boldest one its query
    /// window offers, to be treated as a possible EDGE OF AN ELEMENT. Deliberately
    /// low: over a settings row's own label the boldest thing in the window is a
    /// glyph, and a threshold tuned to throw glyphs out throws the row out with
    /// them. What actually rules text out is geometry — a word's cap-height band
    /// is too short to be an element, and its baseline's run does not agree with
    /// the border above it.
    private static let elementFraction: Double = 0.2

    /// Two boundaries closer together than this are one boundary read twice (the
    /// two flanks of an antialiased border), so only the bolder one can define a
    /// side. Sharpening a side (below) still sees both, which is how a switch's
    /// outer edge is preferred over its knob four pixels inside it.
    private static let pairSeparation: Double = 5

    /// How far inside an element the pointer has to be for the pick to be that
    /// element. Standing within a pixel or two of a boundary is not pointing at
    /// what it encloses: it is what makes the middle of a switch read as the
    /// switch rather than as the knob whose edge happens to pass under the
    /// pointer.
    private static let probeMargin: Double = 4

    /// How much of the longer run the two runs must SHARE to be called the same
    /// element's width. A card's rounded top reads a little wider than the
    /// divider beneath it, so the test is a proportion rather than a pixel
    /// count; a glyph's baseline shares a small fraction of the border above it
    /// and is thrown out.
    private static let runAgreement: Double = 0.85

    /// How close a vertical boundary must be to the end of a run to be taken as
    /// that side's true edge.
    private static let sideSnap: Double = 12

    /// Smallest element worth offering, in IMAGE px, when the caller does not
    /// say. 20 is ten logical points on the 2x captures this tool is pointed at:
    /// small enough for a checkbox, big enough that the band between a word's
    /// cap height and its baseline — which looks exactly like a wide, short box
    /// — is not offered as something to measure.
    public static let defaultMinElement: Double = 20

    /// Half-width of the perpendicular query window centered on the probe —
    /// the same locality snapping's fallback window uses, so hover accepts the
    /// same edges a foot drag would land on.
    public static let defaultSpanRadius: Double = 32

    /// The element rect at `point`: the innermost candidate, or nil when no
    /// candidate is readable (including the not-yet-computed `EdgeMap.empty`).
    public static func detect(at point: CGPoint, in edges: EdgeMap,
                              luma: LumaField,
                              maxRadius: Double = defaultMaxRadius,
                              spanRadius: Double = defaultSpanRadius,
                              minElement: Double = defaultMinElement) -> CGRect? {
        candidates(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                   spanRadius: spanRadius, minElement: minElement, limit: 1).first
    }

    /// The nested ladder of element rects around `point`, innermost first, each
    /// containing the one before it. Empty when nothing is readable.
    public static func candidates(at point: CGPoint, in edges: EdgeMap,
                                  luma: LumaField,
                                  maxRadius: Double = defaultMaxRadius,
                                  spanRadius: Double = defaultSpanRadius,
                                  minElement: Double = defaultMinElement,
                                  limit: Int = candidateLimit) -> [CGRect] {
        guard !edges.isEmpty, !luma.isEmpty, maxRadius > 0, limit > 0 else { return [] }
        let px = Double(point.x), py = Double(point.y)
        let sides = sides(at: point, in: edges, maxRadius: maxRadius, spanRadius: spanRadius)
        let above = pairable(sides[0])
        let below = pairable(sides[1])
        guard !above.isEmpty, !below.isEmpty else { return [] }

        // Grow the pair outward one boundary at a time, so the rungs come out
        // smallest first and every rung is a real pair rather than a cross
        // product of everything in range.
        var found: [CGRect] = []
        var runs: [Int: ClosedRange<Int>?] = [:]
        var top = 0, bottom = 0
        for _ in 0...(above.count + below.count) {
            if let rect = rung(top: above[top], bottom: below[bottom], px: px, py: py,
                               left: sides[2], right: sides[3], luma: luma,
                               minElement: minElement, runs: &runs),
               grows(rect, beyond: found.last) {
                found.append(rect)
                if found.count >= limit { break }
            }
            let nextTop = top + 1 < above.count ? above[top + 1].distance : Double.infinity
            let nextBottom = bottom + 1 < below.count ? below[bottom + 1].distance : Double.infinity
            if nextTop == .infinity, nextBottom == .infinity { break }
            if nextTop <= nextBottom { top += 1 } else { bottom += 1 }
        }
        return found
    }

    /// One rung: the element bounded above by `top` and below by `bottom`, or nil
    /// when those two boundaries do not describe one.
    ///
    /// Width comes from the stretch the two boundaries BOTH cover. They have to
    /// agree at each end, which is what rules out a pairing of a border with a
    /// baseline. `runs` memoizes the walk per row, since growing the pair
    /// revisits the same boundary many times.
    private static func rung(top: Side, bottom: Side, px: Double, py: Double,
                             left: [Side], right: [Side], luma: LumaField,
                             minElement: Double,
                             runs: inout [Int: ClosedRange<Int>?]) -> CGRect? {
        guard bottom.bound - top.bound >= minElement else { return nil }

        func run(_ side: Side) -> ClosedRange<Int>? {
            let row = Int(side.peak.rounded())
            if let cached = runs[row] { return cached }
            let walked = EdgeRun.horizontal(row: row, seedX: Int(px.rounded()), in: luma)
            runs[row] = walked
            return walked
        }
        guard let topRun = run(top), let bottomRun = run(bottom) else { return nil }
        let shared = Double(min(topRun.upperBound, bottomRun.upperBound)
                            - max(topRun.lowerBound, bottomRun.lowerBound))
        let longest = Double(max(topRun.count, bottomRun.count))
        guard shared >= runAgreement * longest else { return nil }
        var lower = Double(max(topRun.lowerBound, bottomRun.lowerBound))
        // A run's last covered pixel is the element's last pixel; the boundary
        // itself is the far side of it.
        var upper = Double(min(topRun.upperBound, bottomRun.upperBound)) + 1
        lower = snapped(lower, to: left, outward: true) ?? lower
        upper = snapped(upper, to: right, outward: false) ?? upper

        guard upper - lower >= minElement,
              lower + probeMargin <= px, px <= upper - probeMargin,
              top.bound + probeMargin <= py, py <= bottom.bound - probeMargin else { return nil }
        return CGRect(x: lower, y: top.bound,
                      width: upper - lower, height: bottom.bound - top.bound)
    }

    /// The boundaries on one side that may DEFINE an element edge: bold enough
    /// to be structure, and thinned so the two flanks of one antialiased border
    /// cannot be mistaken for the top and bottom of something 3 px tall.
    private static func pairable(_ side: [Side]) -> [Side] {
        var kept: [Side] = []
        for candidate in side.filter({ $0.strength >= elementFraction })
            .sorted(by: { $0.strength > $1.strength }) {
            if kept.contains(where: { abs($0.peak - candidate.peak) < pairSeparation }) { continue }
            kept.append(candidate)
        }
        return kept.sorted { $0.distance < $1.distance }
    }

    /// A run's end refined to a real vertical boundary sitting on it.
    ///
    /// Only ever OUTWARD. The run is a floor on how far the element reaches —
    /// the boundary was still readable there — so a vertical border a few pixels
    /// further out is the element's true edge (a run stops just inside a rounded
    /// corner, and a switch's knob sits just inside the switch). One that lies
    /// INSIDE the run is something painted on the element, and pulling in to it
    /// would make the readout wobble as the pointer moved.
    private static func snapped(_ end: Double, to side: [Side], outward: Bool) -> Double? {
        let hits = side.filter { candidate in
            abs(candidate.peak - end) <= sideSnap
                && (outward ? candidate.bound <= end + 1 : candidate.bound >= end - 1)
        }
        guard !hits.isEmpty else { return nil }
        return outward ? hits.map(\.bound).min() : hits.map(\.bound).max()
    }

    /// How far past an element's edge the neighbour probe stands. Far enough
    /// to be properly inside whatever is touching it (`probeMargin` is 4), close
    /// enough that it reads the row against this one rather than something
    /// across the page.
    public static let neighborProbeReach: Double = 12

    /// What is immediately AROUND `rect`: the row under a row, the button beside
    /// a button. Size mode hands these to the readout planner, because a number
    /// parked in the next row down reads as that row's number even when the
    /// pixels underneath it happen to be blank.
    ///
    /// One probe just past the middle of each side, at each distance in
    /// `reaches`, innermost pick only. Two distances is the usual call: one
    /// close enough to find what is touching the element, one as far out as the
    /// number itself will travel, so a button 30 px away is still seen.
    /// Anything that swallows the element — its card, the window behind it — is
    /// dropped: a readout cannot steer out of a box it is standing inside, and
    /// pretending otherwise would only push the number somewhere arbitrary.
    public static func neighbors(of rect: CGRect, in edges: EdgeMap, luma: LumaField,
                                 maxRadius: Double = defaultMaxRadius,
                                 spanRadius: Double = defaultSpanRadius,
                                 minElement: Double = defaultMinElement,
                                 reaches: [Double] = [neighborProbeReach]) -> [CGRect] {
        guard !edges.isEmpty, !luma.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let slack = CGFloat(probeSlack)
        var found: [CGRect] = []
        for reach in reaches {
            probe(rect, reach: CGFloat(reach), slack: slack, into: &found, in: edges, luma: luma,
                  maxRadius: maxRadius, spanRadius: spanRadius, minElement: minElement)
        }
        return found
    }

    /// The four probes at one distance, appending whatever is new to `found`.
    private static func probe(_ rect: CGRect, reach r: CGFloat, slack: CGFloat,
                              into found: inout [CGRect], in edges: EdgeMap, luma: LumaField,
                              maxRadius: Double, spanRadius: Double, minElement: Double) {
        // Each probe carries the test for what a neighbour on THAT side looks
        // like: it has to begin where the element ends. A box that reaches back
        // across the element is a band read off the picture, not the row next
        // door, and steering a number around something invisible is worse than
        // leaving it where it belongs.
        let probes: [(point: CGPoint, beyond: (CGRect) -> Bool)] = [
            (CGPoint(x: rect.midX, y: rect.minY - r), { $0.maxY <= rect.minY + slack }),
            (CGPoint(x: rect.midX, y: rect.maxY + r), { $0.minY >= rect.maxY - slack }),
            (CGPoint(x: rect.minX - r, y: rect.midY), { $0.maxX <= rect.minX + slack }),
            (CGPoint(x: rect.maxX + r, y: rect.midY), { $0.minX >= rect.maxX - slack }),
        ]
        for probe in probes {
            guard probe.point.x >= 0, probe.point.y >= 0,
                  Double(probe.point.x) < Double(edges.width),
                  Double(probe.point.y) < Double(edges.height),
                  let hit = detect(at: probe.point, in: edges, luma: luma, maxRadius: maxRadius,
                                   spanRadius: spanRadius, minElement: minElement),
                  probe.beyond(hit),
                  !found.contains(where: { $0.insetBy(dx: -slack, dy: -slack).contains(hit) })
            else { continue }
            found.append(hit)
        }
    }

    /// How far a foot may sit from an element's painted edge and still count as
    /// standing on it. A snapped foot lands on the clean background hugging the
    /// element, which the antialiasing ramp or a drop shadow can put several
    /// pixels past the boundary detection names.
    public static let footEdgeTolerance: Double = 8

    /// What a hand-drawn caliper is ABOUT: the elements its two feet landed on.
    ///
    /// A foot carries only a point, so this reads the element back off the
    /// picture the way Size mode reads its neighbours: one probe just past the
    /// foot on each side, along the measuring axis. A hit counts only when its
    /// facing edge is at the foot (a click in the middle of a button is not a
    /// click on its edge), and a hit the caliper runs INSIDE (a card's edge to
    /// a button within it) is dropped, because a number cannot steer out of a
    /// box it is standing in. Measuring one element edge to edge by hand gives
    /// that element once, exactly what Size mode would have handed over. When
    /// two bordered elements face each other across the caliper, the strip of
    /// whitespace between them can read as a band of its own and come back too;
    /// that band is the gap being measured, and keeping the number off it is
    /// what Gap mode's head reach already does, so it is left in.
    ///
    /// Placement-time work only: two probes per foot, never per mouse move.
    public static func subjects(from start: CGPoint, to end: CGPoint, mode: MeasureMode,
                                in edges: EdgeMap, luma: LumaField,
                                maxRadius: Double = defaultMaxRadius,
                                spanRadius: Double = defaultSpanRadius,
                                minElement: Double = defaultMinElement) -> [CGRect] {
        guard !edges.isEmpty, !luma.isEmpty else { return [] }
        let horizontal = mode == .horizontal
        func along(_ p: CGPoint) -> CGFloat { horizontal ? p.x : p.y }
        func alongMin(_ r: CGRect) -> CGFloat { horizontal ? r.minX : r.minY }
        func alongMax(_ r: CGRect) -> CGFloat { horizontal ? r.maxX : r.maxY }
        let tolerance = CGFloat(footEdgeTolerance)
        let reach = CGFloat(neighborProbeReach)
        let slack = CGFloat(probeSlack)
        var found: [CGRect] = []
        for (foot, other) in [(start, end), (end, start)] {
            let a = along(foot), b = along(other)
            for sign: CGFloat in [-1, 1] {
                let probe = horizontal ? CGPoint(x: foot.x + sign * reach, y: foot.y)
                                       : CGPoint(x: foot.x, y: foot.y + sign * reach)
                guard probe.x >= 0, probe.y >= 0,
                      Double(probe.x) < Double(edges.width),
                      Double(probe.y) < Double(edges.height),
                      let hit = detect(at: probe, in: edges, luma: luma, maxRadius: maxRadius,
                                       spanRadius: spanRadius, minElement: minElement)
                else { continue }
                // The face of the hit nearest the foot has to BE the foot.
                let facing = sign < 0 ? alongMax(hit) : alongMin(hit)
                guard abs(facing - a) <= tolerance else { continue }
                // The caliper may end at the hit's far edge (its own size) but
                // not inside it: that is a container, not a subject.
                let far = sign < 0 ? alongMin(hit) : alongMax(hit)
                let runsInside = sign < 0 ? (b < a && far < b - tolerance)
                                          : (b > a && far > b + tolerance)
                guard !runsInside else { continue }
                guard !found.contains(where: { $0.insetBy(dx: -slack, dy: -slack).contains(hit) })
                else { continue }
                found.append(hit)
            }
        }
        return found
    }

    /// How far a neighbour may bleed back over the element before it stops
    /// being a neighbour. A painted border has two flanks and detection can
    /// name either, so a couple of pixels of slop is the picture, not a nest.
    private static let probeSlack: Double = 3

    /// The gap under `point`: the two facing edges of whatever sits on either
    /// side of it, across the tighter of the two axes. Nil when neither axis has
    /// a pair of edges to read.
    ///
    /// Unlike an element, a gap needs only ONE axis to work: the space between
    /// two stacked cards has a top and a bottom and no sides at all, and
    /// refusing to measure it because the sides are missing would fail the most
    /// ordinary case there is. When both axes read, the shorter span wins,
    /// because the tighter one is what a person means by "the gap". A gap is
    /// measured to the PROBE-SIDE landing of each edge — the clean background
    /// hugging each element — since what is being measured is the whitespace,
    /// not the elements.
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

    /// Whether a rung belongs on the ladder after `previous`: it has to CONTAIN
    /// what came before (a ladder that narrows on the way out is a shuffle, not
    /// a ladder) and be enough bigger on some side to be worth a keypress.
    private static func grows(_ rect: CGRect, beyond previous: CGRect?) -> Bool {
        guard let previous else { return true }
        guard rect.insetBy(dx: -1, dy: -1).contains(previous) else { return false }
        return Double(previous.minX - rect.minX) >= candidateMinGrowth
            || Double(previous.minY - rect.minY) >= candidateMinGrowth
            || Double(rect.maxX - previous.maxX) >= candidateMinGrowth
            || Double(rect.maxY - previous.maxY) >= candidateMinGrowth
    }

    /// One accepted boundary on one side of the probe.
    private struct Side {
        /// Distance from the probe to the gradient peak.
        var distance: Double
        /// The gradient peak — the middle of the transition ramp.
        var peak: Double
        /// Where the ELEMENT's edge is taken to be: the outer flank of the
        /// boundary pixel. The peak names the pixel the transition sits in, so
        /// the element's edge is half a pixel further out — but no further,
        /// because a drop shadow's clean-background landing can be six pixels
        /// out and would inflate the card by three.
        var bound: Double
        /// The clean background position on the PROBE's side — what a gap
        /// measures to.
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
    /// the probe coordinate) within `maxRadius`, nearest first. The probe sits on
    /// the element side of the boundary, so above the probe the clean background
    /// OUTSIDE the element is the before-side landing and below it the
    /// after-side.
    private static func sideLandings(_ candidates: [EdgeCandidate], probe: Double,
                                     lowerSide: Bool, maxRadius: Double) -> [Side] {
        candidates
            .filter { lowerSide ? $0.position <= probe : $0.position > probe }
            .map { candidate in
                let outer = lowerSide ? candidate.edgeBefore : candidate.edgeAfter
                let flank = min(max(outer - candidate.position, -0.5), 0.5)
                return Side(distance: abs(probe - candidate.position),
                            peak: candidate.position,
                            bound: candidate.position + flank,
                            landing: lowerSide ? candidate.edgeAfter : candidate.edgeBefore,
                            strength: candidate.strength)
            }
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
