import CoreGraphics
import Foundation

extension AskMotionCheck {

    // MARK: A mark shows clear of what moves

    /// "ring right is drawn over bell from 0.6 s to 0.78 s", for a mark (a
    /// part hidden at the top of the lap and shown by its opacity) whose lines
    /// cross the lines of a part that moves while the mark is seen, deeper
    /// than the two sat at rest. The bell of 2026-11-11 (run 20261111-200328)
    /// flashed a ring mark beside its rim just as it swung that way, and nine
    /// looks of nine saw a filled blob run into the bell's outline. The lines
    /// themselves are read (curves walked, each line as thick as its stroke),
    /// not boxes: a mark drawn a hair from the rim is fine until the rim comes
    /// to it. Lines, keys and time only: nothing knows what the parts are.
    /// The furthest a mark moves and is still a mark, in grid units.
    static let markNudge: CGFloat = 3

    static func marksOver(_ planned: [AskStep]) -> [String] {
        guard let lap = AskMotion.Lap(AskMotion.touchesPlaced(planned)) else { return [] }
        let end = planned.last { $0.tool == "set_timing" }?.arguments["seconds"]?.doubleValue
            ?? lap.keyed.flatMap { timed($0).map(\.seconds) }.max() ?? 0
        guard end > 0 else { return [] }
        func keyed(_ name: String, _ property: MotionProperty) -> AskStep? {
            lap.keyed.last { one in
                (one.arguments["layer"]?.stringValue).flatMap(AskMotion.partReference).map { AskMotion.plain($0.part) == AskMotion.plain(name) } ?? false
                    && one.arguments["property"]?.stringValue == property.rawValue
            }
        }
        let marks = lap.movers.filter { name in
            guard let fade = keyed(name, .opacity), let first = timed(fade).first?.value.doubleValue,
                  first <= AskMotion.unseen else { return false }
            // A mark does not travel: what is thrown and hidden at rest (the
            // trash) meets what it hits on purpose. A nudge of a few units
            // out of the way is still a mark.
            guard let move = keyed(name, .position) else { return true }
            let far = timed(move).compactMap { key -> CGFloat? in
                guard let x = key.value["x"]?.doubleValue, let y = key.value["y"]?.doubleValue else { return nil }
                return hypot(CGFloat(x), CGFloat(y))
            }.max() ?? 0
            return far <= Self.markNudge
        }
        let movers = lap.movers.filter { name in
            !marks.contains { AskMotion.plain($0) == AskMotion.plain(name) }
                && [MotionProperty.rotation, .position, .scale].contains { keyed(name, $0) != nil }
        }
        guard !marks.isEmpty, !movers.isEmpty else { return [] }
        func seen(_ name: String, _ seconds: Double) -> Bool {
            (lap.value(name, .opacity, at: seconds)?.doubleValue ?? 100) >= 10
        }
        var said: [String] = []
        for mark in marks {
            for mover in movers where lap.carriers(of: mark).allSatisfy({ AskMotion.plain($0) != AskMotion.plain(mover) }) {
                let rest = gap(lap.lines(mark, at: 0), lap.lines(mover, at: 0))
                // Over it: its lines cross the other's by a quarter unit
                // more than at rest, and cross them at all.
                let deepest = min(rest, 0) - 0.25
                var from: Double?, to: Double?
                var seconds = 0.0
                while seconds <= end + 0.0005 {
                    if seen(mark, seconds), gap(lap.lines(mark, at: seconds), lap.lines(mover, at: seconds)) < deepest {
                        if from == nil { from = seconds }
                        to = seconds
                    } else if from != nil { break }
                    seconds += 0.02
                }
                guard let from, let to, to - from >= 0.06 - 0.0005 else { continue }
                func time(_ value: Double) -> String { String(format: "%g", (value * 100).rounded() / 100) }
                said.append("\(AskMotion.plain(mark)) is drawn over \(AskMotion.plain(mover)) from \(time(from)) s to \(time(to)) s")
            }
        }
        return said
    }

    /// The narrowest gap between two sets of lines, strokes taken off: below
    /// zero where they overlap.
    static func gap(_ a: [(points: [CGPoint], half: CGFloat)], _ b: [(points: [CGPoint], half: CGFloat)]) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for one in a {
            for other in b {
                best = min(best, distance(one.points, other.points) - one.half - other.half)
            }
        }
        return best
    }

    /// The least distance between two polylines (a single point is a line of no length).
    static func distance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        func toSegment(_ p: CGPoint, _ s: CGPoint, _ e: CGPoint) -> CGFloat {
            let (dx, dy) = (e.x - s.x, e.y - s.y)
            let length = dx * dx + dy * dy
            let t = length > 1e-9 ? max(0, min(1, ((p.x - s.x) * dx + (p.y - s.y) * dy) / length)) : 0
            return hypot(s.x + dx * t - p.x, s.y + dy * t - p.y)
        }
        func segments(_ line: [CGPoint]) -> [(CGPoint, CGPoint)] {
            line.count < 2 ? line.map { ($0, $0) } : Array(zip(line, line.dropFirst()))
        }
        var best = CGFloat.greatestFiniteMagnitude
        for point in a { for (s, e) in segments(b) { best = min(best, toSegment(point, s, e)) } }
        for point in b { for (s, e) in segments(a) { best = min(best, toSegment(point, s, e)) } }
        return best
    }
}

extension AskMotion.Lap {
    /// The lines of every drawn part `name` holds, curves walked in short
    /// steps, each with half its stroke, carried by its keys and every keyed
    /// group it sits in to where they have it at `seconds`. A closed shape's
    /// ring is closed.
    func lines(_ name: String, at seconds: Double) -> [(points: [CGPoint], half: CGFloat)] {
        art.parts.filter { Self.holds($0, name) }.flatMap { part -> [(points: [CGPoint], half: CGFloat)] in
            let chain = ([part.name].compactMap { $0 } + part.groups.reversed()).compactMap { group in
                movers.first { AskMotion.plain($0) == AskMotion.plain(group) }
            }
            let half = part.stroke == nil ? 0 : part.strokeWidth / 2
            let closed: Bool
            switch part.shape {
            case .path(let outline): closed = outline.closed
            default: closed = true
            }
            return BrushSketch.outline(part.shape).map { ring in
                var points = closed && ring.count > 2 ? ring + [ring[0]] : ring
                for mover in chain { points = moved(points, by: mover, at: seconds) }
                return (points, half)
            }
        }
    }
}
