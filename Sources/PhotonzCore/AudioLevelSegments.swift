import Foundation

// A sound's volume line, segment by segment (task
// `an-audio-clip-answers-right-click-and-its-volume`, UX-PATTERNS D21).
//
// The stretch between two level points is a SEGMENT, named by the moment of
// the point it starts at, the way a key graph names a stretch by its first key
// (`KeyGraphEdits.swift`). It runs on a curve of its own from the one list
// (`EasingCurve`), Hold included, and that curve bends what the mix plays as
// well as what the lane draws, because both read `gain(atLayerMS:)` and
// `moments(fromMS:toMS:)`.

extension AudioLevel {

    // MARK: - Reading a segment

    /// The curve the segment starting at `ms` runs on, as a menu names it:
    /// its own where somebody shaped it, the Fades curve along a fade,
    /// Linear otherwise. Nil where no segment starts there.
    public func segmentCurve(startingAtMS ms: Int) -> EasingCurve? {
        guard let index = points.firstIndex(where: { $0.atMS == ms }), index + 1 < points.count else { return nil }
        if let curve = points[index].curve { return curve }
        guard stretchCurve(index) != .linear else { return .linear }
        return fadeCurve
    }

    /// The curve every one of these segments runs on, where they agree; nil
    /// where they differ or none is a segment, so a menu ticks only what is
    /// true of all of them.
    public func segmentsCurve(_ starts: Set<Int>) -> EasingCurve? {
        let curves = starts.compactMap { segmentCurve(startingAtMS: $0) }
        guard let first = curves.first, curves.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: - Shaping

    /// Every segment starting at one of `starts` runs on `curve`. False where
    /// none of them is a segment.
    @discardableResult
    public mutating func setSegmentsCurve(_ curve: EasingCurve, startingAt starts: Set<Int>) -> Bool {
        var changed = false
        for index in points.indices.dropLast() where starts.contains(points[index].atMS) {
            points[index].curve = curve
            changed = true
        }
        return changed
    }

    /// A point added on the line at `ms`, holding the level the line has
    /// there so nothing you hear changes. Part way along a curved segment the
    /// curve is cut in two exactly (`EasingCurve.split`), so the line keeps
    /// its shape. False where a point already sits there.
    @discardableResult
    public mutating func addPointOnLine(atMS ms: Int) -> Bool {
        let ms = max(0, ms)
        guard !points.contains(where: { $0.atMS == ms }) else { return false }
        var added = AudioLevelPoint(atMS: ms, gain: shape(atLayerMS: ms))
        if let next = points.firstIndex(where: { $0.atMS > ms }), next > 0,
           let curve = stretchCurve(next - 1), curve != .linear || points[next - 1].curve != nil {
            let start = points[next - 1].atMS
            let through = Double(ms - start) / Double(max(1, points[next].atMS - start))
            let (left, right) = curve.split(at: through)
            points[next - 1].curve = left
            added.curve = right
        }
        points = Self.tidied(points + [added])
        return true
    }

    /// A point carried to a new moment and level, keeping the curve of the
    /// segment it starts.
    public mutating func movePoint(fromMS: Int, toMS: Int, gain: Double) {
        let curve = points.first { $0.atMS == fromMS }?.curve
        points.removeAll { $0.atMS == fromMS }
        points = Self.tidied(points + [AudioLevelPoint(atMS: toMS, gain: gain, curve: curve)])
    }

    /// Several points taken out at once: the picked ones, in one step.
    public mutating func removePoints(_ moments: Set<Int>) {
        points.removeAll { moments.contains($0.atMS) }
    }

    // MARK: - Bending by hand

    /// The curve a segment takes when its middle is dragged to `middle` of
    /// the way from its first level to its second: an even bend either side,
    /// so the handle sits under the hand at the segment's half way moment.
    /// Half way is a straight line.
    public static func bentCurve(middle: Double) -> EasingCurve {
        let middle = min(max(middle.isFinite ? middle : 0.5, 0.05), 0.95)
        guard abs(middle - 0.5) > 0.004 else { return .linear }
        // A quadratic through (0, 0), its control at (½, q) and (1, 1) passes
        // ¼ + ½q at half way; raised to the cubic a curve list keeps.
        let q = 2 * (middle - 0.25)
        return .custom(x1: 1.0 / 3, y1: 2 * q / 3, x2: 2.0 / 3, y2: 1.0 / 3 + 2 * q / 3)
    }

    /// Where a segment's middle sits on its curve: the bend handle's height,
    /// nought at the first point's level and one at the second's.
    public static func bendMiddle(of curve: EasingCurve) -> Double {
        curve.value(at: 0.5)
    }
}

extension EasingCurve {
    /// The curve run from its end to its start: what a fade out plays, the
    /// fade in backwards, said as a curve going forwards. Exact for every
    /// curve a Bezier draws; the others are their own nearest.
    var playedBackwards: EasingCurve {
        guard self != .linear, let (x1, y1, x2, y2) = bezierControls else { return self }
        return .custom(x1: 1 - x2, y1: 1 - y2, x2: 1 - x1, y2: 1 - y1)
    }
}
