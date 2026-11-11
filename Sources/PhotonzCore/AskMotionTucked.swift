import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: What goes in under a closing part goes in past it

    /// The gap, as a share of the drawing's width, a part going out of sight
    /// keeps from the line a closing part shuts onto.
    static let tuckGap: CGFloat = 0.03
    /// The furthest, as a share of the drawing's width, a landing is pushed in.
    static let mostTuck: CGFloat = 0.25
    /// Each try at pushing it in goes this much further, as a share of the width.
    static let tuckStep: CGFloat = 0.01

    /// `steps` with a part that goes out of sight where another part comes to
    /// rest over it (a lid shutting on what went in, a flap on a letter)
    /// landing past that part's resting line first: its landing key, and the
    /// keys holding it there, pushed the way the closing part sweeps onto
    /// it, just far enough to keep `tuckGap` from where that part rests and
    /// never to pass through it while seen. On 2026-11-11 the user's trash
    /// dropped to the can's mouth and faded there, across the line the lid
    /// shuts onto: the agent's own look called it "vanishes in place", and
    /// the reel showed a grey ghost of it on the shut lid. Pushed in, it is
    /// seen going into the can as it fades and the lid shuts over nothing.
    /// The push starts the way the closer sweeps and turns from it as far as
    /// a right angle, shortest first, until the part's middle is half its
    /// size inside what it landed in (later that day the model moved the
    /// landing onto the can's rim, and the sweep alone, down and out with the
    /// lid's end, sent the trash down the outside of the wall).
    /// Only the latest keys of each value are read and changed (as they
    /// will play), and a landing no push within `mostTuck` clears keeps
    /// its keys. Ink, keys and time only, any subject.
    static func tuckedIn(_ steps: [AskStep]) -> [AskStep] {
        guard let lap = Lap(steps), let width = lap.art.viewBox?.width ?? Optional(lap.art.bounds.width), width > 0 else { return steps }
        let keyedEnds = steps.filter { $0.tool == "set_keys" }.flatMap { AskMotionCheck.timed($0).map(\.seconds) }
        guard let lapEnd = steps.last(where: { $0.tool == "set_timing" })?.arguments["seconds"]?.doubleValue ?? keyedEnds.max() else { return steps }
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        func isPosition(_ step: AskStep) -> Bool {
            step.tool == "set_keys" && step.arguments["property"]?.stringValue == MotionProperty.position.rawValue
        }
        var out = steps
        for index in out.indices where isPosition(out[index]) {
            // Only the keys that play: the last written for this value.
            guard let name = layer(out[index]), let part = partReference(name)?.part, lap.isMover(part),
                  !out[(index + 1)...].contains(where: { isPosition($0) && layer($0) == name }),
                  let current = Lap(out) else { continue }
            let keys = AskMotionCheck.timed(out[index])
            guard keys.count >= 2 else { continue }
            func seen(_ at: Double, in lap: Lap) -> Bool { lap.placed(part, at: at)?.seen ?? true }
            // Where it goes out of sight, after being seen.
            var gone: Double?
            var moment = 0.01
            while moment < lapEnd - 0.0005 {
                if seen(moment - 0.01, in: current), !seen(moment, in: current) { gone = moment }
                moment += 0.01
            }
            // The key it is heading for as it goes, or holding at.
            guard let gone, let before = keys.lastIndex(where: { $0.seconds <= gone + 0.0005 }) else { continue }
            let landing = before + 1 < keys.count && keys[before + 1].value != keys[before].value ? before + 1 : before
            guard landing > 0 else { continue }
            let from = keys[landing - 1].seconds, landed = keys[landing].seconds
            // The keys holding it where it landed go with it.
            var moved = [landing]
            for later in keys.indices where later > landing {
                guard keys[later].value == keys[landing].value else { break }
                moved.append(later)
            }
            let family = Set([plain(part)] + current.carriers(of: part).map(plain))
            let closers = current.movers.filter { other in
                !family.contains(plain(other)) && !current.carriers(of: other).contains { plain($0) == plain(part) }
            }
            for closer in closers {
                let rest = current.ink(closer, at: lapEnd)
                // It lands where the closer comes to rest, and the closer
                // gets there after it set off for the landing.
                guard inkMeets(current.ink(part, at: landed), rest, within: tuckGap * width),
                      let sweep = sweep(of: closer, onto: current.ink(part, at: landed), from: from, to: lapEnd, in: current) else { continue }
                func trial(_ way: CGVector) -> [AskStep]? {
                    guard var object = out[index].arguments.objectValue, var list = object["keys"]?.arrayValue else { return nil }
                    for slot in list.indices {
                        guard let at = list[slot]["seconds"]?.doubleValue,
                              moved.contains(where: { abs(keys[$0].seconds - at) <= 0.0005 }),
                              var one = list[slot].objectValue,
                              let x = one["value"]?["x"]?.doubleValue, let y = one["value"]?["y"]?.doubleValue else { continue }
                        one["value"] = ["x": .number(rounded(CGFloat(x) + way.dx)), "y": .number(rounded(CGFloat(y) + way.dy))]
                        list[slot] = .object(one)
                    }
                    object["keys"] = .array(list)
                    var made = out
                    made[index] = AskStep(tool: made[index].tool, arguments: .object(object))
                    return made
                }
                func clear(_ made: [AskStep]) -> Bool {
                    guard let lap = Lap(made) else { return false }
                    if inkMeets(lap.ink(part, at: landed), rest, within: tuckGap * width) { return false }
                    // Never through the closer on the way in, until it is
                    // gone (coming back unseen for the next lap is not part of it).
                    var at = from + 0.01
                    while at < lapEnd - 0.0005, seen(at, in: lap) {
                        if inkMeets(lap.ink(part, at: at), lap.ink(closer, at: at), within: -passesThrough) { return false }
                        at += 0.01
                    }
                    return true
                }
                // What it lands in: the still parts it meets as it lands. Its
                // middle ends at least half its own size inside their outline,
                // or as deep as any push gets it, so it goes into the can, not
                // down the outside of its wall.
                let landedInk = current.ink(part, at: landed)
                let points = landedInk.flatMap { $0 }
                guard !points.isEmpty else { break }
                let middle = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
                let size = min((points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0), (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0))
                let into = hull(current.still.map(\.name).flatMap { name -> [CGPoint] in
                    let ink = current.ink(name, at: landed)
                    return inkMeets(landedInk, ink, within: tuckGap * width) ? ink.flatMap { $0 } : []
                })
                // The sweep first, then turned a little more each way.
                let turns: [Double] = into.count >= 3 ? [0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90] : [0]
                var tries: [(length: CGFloat, turn: Double, way: CGVector)] = []
                var length = tuckStep * width
                while length <= mostTuck * width + 0.0005 {
                    for turn in turns {
                        let angle = turn * .pi / 180
                        let way = CGVector(dx: (sweep.dx * cos(angle) - sweep.dy * sin(angle)) * length,
                                           dy: (sweep.dx * sin(angle) + sweep.dy * cos(angle)) * length)
                        tries.append((length, turn, way))
                    }
                    length += tuckStep * width
                }
                func depth(_ way: CGVector) -> CGFloat {
                    into.count >= 3 ? AskMotion.depth(of: CGPoint(x: middle.x + way.dx, y: middle.y + way.dy), in: into) : 0
                }
                let deepest = tries.map { depth($0.way) }.max() ?? 0
                let need = min(size / 2, deepest)
                for one in tries where depth(one.way) >= need - 0.0005 {
                    // Cheap first: clear of where the closer rests.
                    let shifted = landedInk.map { $0.map { CGPoint(x: $0.x + one.way.dx, y: $0.y + one.way.dy) } }
                    guard !inkMeets(shifted, rest, within: tuckGap * width), let made = trial(one.way), clear(made) else { continue }
                    out = made
                    break
                }
                break
            }
        }
        return out
    }

    /// How far `point` is inside the convex outline `hull`: the distance to
    /// its nearest edge, less than nothing outside it.
    static func depth(of point: CGPoint, in hull: [CGPoint]) -> CGFloat {
        guard hull.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for (a, b) in zip(hull, hull.dropFirst() + [hull[0]]) { area += a.x * b.y - b.x * a.y }
        let turn: CGFloat = area >= 0 ? 1 : -1
        var nearest = CGFloat.greatestFiniteMagnitude
        for (a, b) in zip(hull, hull.dropFirst() + [hull[0]]) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { continue }
            let side = turn * ((b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)) / length
            nearest = min(nearest, side)
        }
        return nearest
    }

    /// The way `closer` sweeps onto what lies at `onto`: the point of it that
    /// rests nearest, from where it was at `from` to where it rests at `to`,
    /// as a unit vector; nil when it does not move there.
    static func sweep(of closer: String, onto: [[CGPoint]], from: Double, to: Double, in lap: Lap) -> CGVector? {
        let target = onto.flatMap { $0 }
        guard !target.isEmpty else { return nil }
        let middle = CGPoint(x: target.map(\.x).reduce(0, +) / CGFloat(target.count), y: target.map(\.y).reduce(0, +) / CGFloat(target.count))
        var best: (distance: CGFloat, way: CGVector)?
        for drawn in lap.art.parts where Lap.holds(drawn, closer) || drawn.groups.contains(where: { plain($0) == plain(closer) }) {
            let chain = ([drawn.name].compactMap { $0 } + drawn.groups.reversed()).compactMap { group in
                lap.movers.first { plain($0) == plain(group) }
            }
            var then = Lap.inkPoints(drawn), now = then
            for mover in chain {
                then = lap.moved(then, by: mover, at: from)
                now = lap.moved(now, by: mover, at: to)
            }
            for (a, b) in zip(then, now) {
                let distance = hypot(b.x - middle.x, b.y - middle.y)
                let way = CGVector(dx: b.x - a.x, dy: b.y - a.y)
                if best.map({ distance < $0.distance }) ?? true { best = (distance, way) }
            }
        }
        guard let way = best?.way else { return nil }
        let length = hypot(way.dx, way.dy)
        guard length > 0.05 else { return nil }
        return CGVector(dx: way.dx / length, dy: way.dy / length)
    }
}
