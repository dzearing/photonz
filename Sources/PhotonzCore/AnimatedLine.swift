import CoreGraphics
import Foundation

// One rule for every animated line on the timeline: a value graph, a key
// lane's line and a sound's volume line (the user, 2026-10-13: "I don't want
// to add dots by default. I want to select things. I want to add dots by cmd
// clicking on the line").
//
// - A click on a dot picks it; a click on the line between two dots picks
//   that SEGMENT. A plain click never adds a dot.
// - A Command-click on the line adds a dot there. A Command-click on a dot
//   adds it to the pick instead, so it never lands a second dot on the first.
// - Shift adds to the pick, or takes out what was in it.
// - The line running on before the first dot and after the last is not a
//   segment: a click there is a click on the lane.
//
// Written once here, in the line's own drawn space (points, as the view lays
// it out), so each surface only says where its dots and lines are drawn.

/// What sits under the pointer on an animated line.
public enum AnimatedLineHit: Hashable, Sendable {
    /// Dot `index`, first to last.
    case dot(Int)
    /// The stretch of line from dot `index` to dot `index + 1`.
    case segment(Int)
    /// The line before the first dot or after the last.
    case beyond
}

/// What a click on an animated line does.
public enum AnimatedLineAction: Hashable, Sendable {
    case pickDot(Int, extending: Bool)
    case pickSegment(Int, extending: Bool)
    /// A dot added where the click landed on the line.
    case addDot
    /// Nothing of the line: the lane's own click.
    case clear
}

/// An animated line as it is drawn: its dots, the line between each pair, and
/// the line running on either side.
public struct AnimatedLine: Hashable, Sendable {
    public var dots: [CGPoint]
    /// `segments[i]` runs from `dots[i]` to `dots[i + 1]`, as drawn.
    public var segments: [[CGPoint]]
    public var before: [CGPoint]
    public var after: [CGPoint]

    /// How near a dot a press has to land to take it: a diamond's half width
    /// and a little more, so the hand need not be exact.
    public static let dotReach: CGFloat = 7
    /// How near the line a press has to land to be on it.
    public static let lineReach: CGFloat = 6

    public init(dots: [CGPoint], segments: [[CGPoint]], before: [CGPoint] = [], after: [CGPoint] = []) {
        self.dots = dots
        self.segments = segments
        self.before = before
        self.after = after
    }

    /// A key lane drawn shut: its keys along a flat line at `y`, a straight
    /// segment between each pair and no line either side, so a click off the
    /// keys is the lane's own.
    public init(flatThrough xs: [CGFloat], atY y: CGFloat) {
        let dots = xs.sorted().map { CGPoint(x: $0, y: y) }
        self.init(dots: dots, segments: zip(dots, dots.dropFirst()).map { [$0, $1] })
    }

    /// What is under `point`: the nearest dot within reach first, so a dot is
    /// never lost under the line it sits on, then the nearest stretch of line.
    public func hit(_ point: CGPoint) -> AnimatedLineHit? {
        let nearestDot = dots.indices.min { Self.distance(dots[$0], point) < Self.distance(dots[$1], point) }
        if let index = nearestDot, Self.distance(dots[index], point) <= Self.dotReach { return .dot(index) }
        var best: (hit: AnimatedLineHit, distance: CGFloat)?
        func consider(_ line: [CGPoint], _ hit: AnimatedLineHit) {
            let distance = Self.nearest(on: line, to: point).distance
            guard distance <= Self.lineReach, distance < (best?.distance ?? .infinity) else { return }
            best = (hit, distance)
        }
        for index in segments.indices { consider(segments[index], .segment(index)) }
        consider(before, .beyond)
        consider(after, .beyond)
        return best?.hit
    }

    /// The point on the line nearest `point`: where a dot added there sits.
    public func nearestPoint(to point: CGPoint) -> CGPoint {
        let lines = segments + [before, after]
        return lines.map { Self.nearest(on: $0, to: point) }
            .min { $0.distance < $1.distance }?.point ?? point
    }

    /// What a click does to what it landed on.
    public static func action(for hit: AnimatedLineHit?, command: Bool, shift: Bool) -> AnimatedLineAction {
        switch hit {
        case let .dot(index): return .pickDot(index, extending: shift || command)
        case let .segment(index): return command ? .addDot : .pickSegment(index, extending: shift)
        case .beyond: return command ? .addDot : .clear
        case nil: return .clear
        }
    }

    // MARK: - Distances

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func nearest(on line: [CGPoint], to point: CGPoint) -> (point: CGPoint, distance: CGFloat) {
        guard let first = line.first else { return (point, .infinity) }
        var best = (point: first, distance: distance(first, point))
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let u = length > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / length, 0), 1) : 0
            let on = CGPoint(x: a.x + u * dx, y: a.y + u * dy)
            let gap = distance(on, point)
            if gap < best.distance { best = (on, gap) }
        }
        return best
    }
}

/// What is picked on an animated line: dots and segments, a segment named by
/// the dot it starts at.
public struct AnimatedLinePick<ID: Hashable & Sendable>: Hashable, Sendable {
    public var dots: Set<ID>
    public var segments: Set<ID>

    public init(dots: Set<ID> = [], segments: Set<ID> = []) {
        self.dots = dots
        self.segments = segments
    }

    public var isEmpty: Bool { dots.isEmpty && segments.isEmpty }

    /// A click on a dot: it alone is picked, or with Shift it joins the pick
    /// or leaves it.
    public mutating func pick(dot id: ID, extending: Bool) {
        guard extending else {
            self = AnimatedLinePick(dots: [id])
            return
        }
        if dots.contains(id) { dots.remove(id) } else { dots.insert(id) }
    }

    /// A click on a segment, the same way.
    public mutating func pick(segment id: ID, extending: Bool) {
        guard extending else {
            self = AnimatedLinePick(segments: [id])
            return
        }
        if segments.contains(id) { segments.remove(id) } else { segments.insert(id) }
    }
}
