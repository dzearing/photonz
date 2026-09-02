import CoreGraphics
import Foundation

/// Where a measurement's readout sits relative to the measurement itself
/// (UX-PATTERNS D14: a callout never covers what it is talking about).
///
/// The case is stored, the pixels are not: the actual displacement is derived
/// from the chip's current size, so growing the label, switching units or
/// gaining a digit can never leave a stale offset behind.
///
/// "Positive" is the direction coordinates grow in: right for a horizontal
/// measurement's along-axis, down for its cross-axis, and the transpose for a
/// vertical one.
public enum MeasureLabelPlacement: String, CaseIterable, Hashable, Codable, Sendable {
    /// Centred on the measurement's own line, which splits around it. The
    /// classic look, and still the best one whenever the line is clear there.
    case onLine
    /// Just past the low end of the line, along its axis (left, or above).
    case beforeStart
    /// Just past the high end of the line, along its axis (right, or below).
    case afterEnd
    /// Pushed perpendicular, clear of everything the measurement describes, on
    /// the growing side (below a horizontal measure, right of a vertical one).
    case clearPositive
    /// The same push, on the other side.
    case clearNegative
}

extension MeasureContent {

    /// Unit step along the measuring line.
    var alongUnit: CGPoint { mode == .horizontal ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1) }
    /// Unit step perpendicular to it — the direction `headOffset` counts in.
    var crossUnit: CGPoint { mode == .horizontal ? CGPoint(x: 0, y: 1) : CGPoint(x: 1, y: 0) }

    /// The chip's half-extent across the measuring line.
    func chipCrossHalfExtent(chipSize: CGSize) -> CGFloat {
        (mode == .horizontal ? chipSize.height : chipSize.width) / 2
    }

    /// The cross-axis coordinate of the measuring line itself.
    public var lineCross: CGFloat { mode == .horizontal ? start.y : start.x }

    /// How far off the measuring line the thing being described actually
    /// reaches. A caliper describes the line itself; an alignment check also
    /// covers each element's tick and, for the outlier, its real edge — which
    /// can sit well off the guide.
    public var subjectCrossReach: CGFloat {
        let stroke = strokeWidth / 2
        guard let check = alignment, !check.items.isEmpty else { return stroke }
        let worst = check.items.map { abs($0.edge - lineCross) }.max() ?? 0
        return worst + MeasureBuilder.alignmentTickHalf + stroke
    }

    /// The rects a callout must stay off: what this measurement is describing.
    /// A caliper protects the span between its feet; an alignment check
    /// protects each element run it crossed, out to that element's real edge.
    public var subjectRects: [CGRect] {
        let stroke = strokeWidth / 2
        func rect(cross: ClosedRange<CGFloat>, along: ClosedRange<CGFloat>) -> CGRect {
            let c = CGRect(x: cross.lowerBound, y: along.lowerBound,
                           width: max(cross.upperBound - cross.lowerBound, 0.5),
                           height: max(along.upperBound - along.lowerBound, 0.5))
            return mode == .vertical ? c : CGRect(x: c.minY, y: c.minX,
                                                  width: c.height, height: c.width)
        }
        guard let check = alignment, !check.items.isEmpty else {
            let a = min(alongCoordinate(start), alongCoordinate(end))
            let b = max(alongCoordinate(start), alongCoordinate(end))
            return [rect(cross: (lineCross - stroke)...(lineCross + stroke), along: a...b)]
        }
        let tick = MeasureBuilder.alignmentTickHalf
        return check.items.map { item in
            let lo = min(lineCross, item.edge) - tick - stroke
            let hi = max(lineCross, item.edge) + tick + stroke
            return rect(cross: lo...hi,
                        along: min(item.spanStart, item.spanEnd)...max(item.spanStart, item.spanEnd))
        }
    }

    private func alongCoordinate(_ p: CGPoint) -> CGFloat { mode == .horizontal ? p.x : p.y }

    /// Takes on a planner's answer in one step, so no caller can carry the
    /// placement without the reach that goes with it.
    public mutating func apply(_ plan: MeasureLabelPlanner.Plan) {
        labelPlacement = plan.placement
        labelNudge = plan.nudge
        labelCrossReach = plan.crossReach
    }

    /// The displacement the current placement asks for, from `labelAnchor`.
    /// Only the readout moves: the feet, the head, the ticks and the connector
    /// stay exactly where the measurement is (D14 rule 5).
    public func labelOffset(chipSize: CGSize) -> CGPoint {
        let gap = MeasureContent.chipLineGap
        let halfAlong = chipAxisHalfExtent(chipSize: chipSize)
        let halfCross = chipCrossHalfExtent(chipSize: chipSize)
        var along = labelNudge
        var cross: CGFloat = 0
        switch labelPlacement {
        case .onLine:
            break
        case .afterEnd:
            along += rawDistance / 2 + halfAlong + gap
            cross = labelCrossReach
        case .beforeStart:
            along -= rawDistance / 2 + halfAlong + gap
            cross = labelCrossReach
        case .clearPositive:
            cross = max(0, max(subjectCrossReach, labelCrossReach) + gap + halfCross - headOffset)
        case .clearNegative:
            cross = min(0, -(max(subjectCrossReach, labelCrossReach) + gap + halfCross) - headOffset)
        }
        return CGPoint(x: alongUnit.x * along + crossUnit.x * cross,
                       y: alongUnit.y * along + crossUnit.y * cross)
    }

    /// Where the readout centres, once the placement is applied.
    public func labelPosition(chipSize: CGSize) -> CGPoint {
        let anchor = labelAnchor
        let offset = labelOffset(chipSize: chipSize)
        return CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
    }

    /// The readout's footprint, in the same space as the feet.
    public func labelRect(chipSize: CGSize) -> CGRect {
        let p = labelPosition(chipSize: chipSize)
        return CGRect(x: p.x - chipSize.width / 2, y: p.y - chipSize.height / 2,
                      width: chipSize.width, height: chipSize.height)
    }

    /// The signed slide across the line that brings `rect` back onto
    /// `bounds` on the cross axis, or nil when it already is, or when no slide
    /// can (a chip wider than the picture). The slide is the least that
    /// works, so the chip's edge sits on the picture's edge.
    func edgeSlide(for rect: CGRect, within bounds: CGRect) -> CGFloat? {
        let lo = mode == .horizontal ? rect.minY : rect.minX
        let hi = mode == .horizontal ? rect.maxY : rect.maxX
        let boundLo = mode == .horizontal ? bounds.minY : bounds.minX
        let boundHi = mode == .horizontal ? bounds.maxY : bounds.maxX
        guard hi - lo <= boundHi - boundLo else { return nil }
        if lo < boundLo { return boundLo - lo }
        if hi > boundHi { return boundHi - hi }
        return nil
    }

    /// True while the readout still rides its own line, which is the only time
    /// the line needs splitting around it.
    public func labelRidesTheLine(chipSize: CGSize) -> Bool {
        let offset = labelOffset(chipSize: chipSize)
        return abs(mode == .horizontal ? offset.y : offset.x) < 0.5
    }

    /// True while the readout sits on top of the head handle, which it does
    /// whenever it rides the line unnudged: the handle is drawn at the head
    /// midpoint and the chip centres on the same point. A dot drawn there
    /// lands on the digits ("121 px" reads "12 px"), so while this holds the
    /// chip itself is the thing to grab and the dot stays hidden.
    public func labelCoversHeadHandle(chipSize: CGSize) -> Bool {
        showLabel && labelRect(chipSize: chipSize).contains(headHandle)
    }
}

/// Picks where a measurement's readout should sit, once, when the measurement
/// lands or its endpoints move.
///
/// It scores candidate placements against three things: the rects the
/// measurement is describing (which it must never cover), the canvas edges
/// (a readout half off the image is not a readout), and the readouts already on
/// the canvas (two stacked numbers are worse than one). The classic
/// on-the-line placement is ranked first, so nothing moves that was never in
/// the way.
public enum MeasureLabelPlanner {

    /// Running off the picture is the worst thing a readout can do: a number
    /// you cannot read is not a measurement at all, so this outranks even
    /// covering the subject — the same order `clearingHeadOffset` already uses
    /// when it turns a head round rather than hang the chip off the edge.
    private static let offCanvasPenalty: CGFloat = 500
    /// A readout that covers what it is describing is disqualifying, and
    /// covering two subjects is no worse than covering one: when every spot is
    /// on something, the number stays where you always look for it instead of
    /// jumping to whichever spot happens to cover the least.
    private static let subjectPenalty: CGFloat = 400
    /// Covering another readout, or a neighbouring element, is bad, but not as
    /// bad as covering the subject.
    private static let overlapPenalty: CGFloat = 120
    /// Each step down the preference order.
    private static let rankPenalty: CGFloat = 4
    /// Each nudge step away from centre.
    private static let nudgePenalty: CGFloat = 1
    /// A gentle pull back toward the measurement, so of two clear placements
    /// the closer one wins.
    private static let travelPenalty: CGFloat = 0.02

    /// `crossReach` is how far off the line a sideways placement pushes to
    /// clear the described subjects; zero unless that placement won.
    public typealias Plan = (placement: MeasureLabelPlacement, nudge: CGFloat,
                             crossReach: CGFloat)

    /// How far past its own line a readout will step sideways to find
    /// whitespace: three of its own heights. Further than that the number
    /// stops being the caliper's and the classic spot on the line, even on
    /// top of something, is the easier read.
    public static func maxCrossReach(for content: MeasureContent, chip: CGSize) -> CGFloat {
        3 * (content.mode == .horizontal ? chip.height : chip.width)
    }

    /// The pushes a sideways placement may try: none, and then the far side
    /// of each subject on that side, nearest first, as far as `maxCrossReach`
    /// allows. Each subject's edge is its own candidate because clearing the
    /// near one is often enough: the far one may not reach the chip at all
    /// once a nudge slides it along.
    ///
    /// The other placements keep the chip centred on the line, with one
    /// exception: when centring a past-the-end chip hangs it off the picture
    /// (a wide chip on a guide near the edge), it may slide across the line
    /// by exactly the overhang. That slide is found per candidate in `plan`,
    /// since it depends on where the chip landed.
    private static func crossReaches(for placement: MeasureLabelPlacement,
                                     content: MeasureContent, subjects: [CGRect],
                                     chip: CGSize) -> [CGFloat] {
        guard placement == .clearPositive || placement == .clearNegative,
              !subjects.isEmpty else { return [0] }
        let line = content.lineCross
        let horizontal = content.mode == .horizontal
        let limit = maxCrossReach(for: content, chip: chip)
        let extents = subjects.map { rect -> CGFloat in
            let lo = horizontal ? rect.minY : rect.minX
            let hi = horizontal ? rect.maxY : rect.maxX
            return placement == .clearPositive ? hi - line : line - lo
        }
        let usable = Set(extents.filter { $0 > content.subjectCrossReach && $0 <= limit })
        return [0] + usable.sorted()
    }

    /// The placement for `content`, whose feet, alignment items and `others`
    /// must all be in the same coordinate space (document space at placement
    /// time). `canvas` is that space's bounds; pass nil to skip the edge check.
    ///
    /// `describing` is what this measurement is ABOUT, when the caller knows
    /// more than the geometry does. A caliper on its own only knows its thin
    /// measuring line, so Size mode hands it the element it just measured and
    /// the readout treats that whole box the way it treats the line: never sit
    /// on it. `avoiding` is the softer list — other readouts, neighbouring
    /// elements — steered around when there is room and tolerated when there
    /// is not.
    public static func plan(for content: MeasureContent, canvas: CGSize? = nil,
                            avoiding others: [CGRect] = [],
                            describing extraSubjects: [CGRect] = []) -> Plan {
        let chip = content.estimatedLabelSize
        guard content.showLabel else { return (.onLine, 0, 0) }
        let subjects = content.subjectRects + extraSubjects
        let bounds = canvas.map { CGRect(origin: .zero, size: $0) }
        let step = content.chipAxisHalfExtent(chipSize: chip) + MeasureContent.chipLineGap

        var best: Plan = (.onLine, 0, 0)
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (rank, placement) in order(for: content).enumerated() {
            let reaches = crossReaches(for: placement, content: content, subjects: extraSubjects,
                                       chip: chip)
            for reach in reaches {
                for multiple in [0, 1, -1, 2, -2] {
                    var probe = content
                    probe.labelPlacement = placement
                    probe.labelNudge = step * CGFloat(multiple)
                    probe.labelCrossReach = reach
                    // A centred chip that hangs off the picture may slide
                    // across the line by the overhang; the slide is the
                    // candidate's cross reach, so it draws from the plan alone.
                    // On-line chips stay centred: the line splits around them,
                    // and a slid pill would show the dashes through its fill.
                    let pastEnd = placement == .afterEnd || placement == .beforeStart
                    if pastEnd, let bounds,
                       let slide = probe.edgeSlide(for: probe.labelRect(chipSize: chip),
                                                   within: bounds) {
                        probe.labelCrossReach = slide
                    }
                    let rect = probe.labelRect(chipSize: chip)
                    var score = CGFloat(rank) * rankPenalty
                    score += CGFloat(abs(multiple)) * nudgePenalty
                    if subjects.contains(where: { $0.intersects(rect) }) { score += subjectPenalty }
                    score += overlapPenalty * CGFloat(others.filter { $0.intersects(rect) }.count)
                    if let bounds, !bounds.contains(rect) { score += offCanvasPenalty }
                    let offset = probe.labelOffset(chipSize: chip)
                    score += hypot(offset.x, offset.y) * travelPenalty
                    if score < bestScore {
                        bestScore = score
                        best = (placement, probe.labelNudge, probe.labelCrossReach)
                    }
                }
            }
        }
        return best
    }

    /// Preference order.
    ///
    /// An alignment guide runs THROUGH the elements it is judging, so anywhere
    /// along it is on top of the evidence — even a gap between two rows is a
    /// squeeze. Its verdict goes past the end of the guide, and only falls back
    /// to the line when the picture leaves it nowhere else. Predictable beats
    /// clever here: you always know where to look for the verdict.
    ///
    /// Sideways is the LAST resort, not the second: a guide checking left edges
    /// has all of its elements off to one side, and which side that is cannot be
    /// read from the edges alone — so a sideways push is a coin flip on covering
    /// a row. A gap between two checked runs is known-empty, so it comes first.
    ///
    /// A caliper is the opposite: its head line is space the caliper itself
    /// claimed, off the thing being measured, so the readout stays there and
    /// only steps further out when the head is too shallow to be clear.
    private static func order(for content: MeasureContent) -> [MeasureLabelPlacement] {
        if content.alignment != nil {
            return [.afterEnd, .beforeStart, .onLine, .clearPositive, .clearNegative]
        }
        let outward: MeasureLabelPlacement = content.headOffset < 0 ? .clearNegative : .clearPositive
        let inward: MeasureLabelPlacement = outward == .clearPositive ? .clearNegative : .clearPositive
        return [.onLine, outward, .afterEnd, .beforeStart, inward]
    }
}
