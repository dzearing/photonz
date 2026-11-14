import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: What goes in under a closing part is in before it shuts

    /// The shortest the way in from where the part was as the closer began
    /// to shut may take, in seconds.
    static let shortestWayIn = 0.08
    /// How long after the closer sets off the part may still be touching it
    /// at the hit, in seconds.
    static let hitGrace = 0.05

    /// `steps` with a part that goes out of sight where it lands, and passes
    /// through another moving part (a closer: a lid, a flap, a door) while
    /// seen, landed before that part shuts: from the moment the closer sets
    /// off on its last move to rest, the part's keys that take it further
    /// from where it lands than it was then are left out (a hop up over what
    /// is shutting), and its landing comes at the latest moment, no later
    /// than the closer shuts, at which it passes through nothing it is meant
    /// to go in under, pushed in past the closer's resting line as little
    /// as that takes (`tuckStep`, up to `mostTuck`). The keys between keep their order, closer in time.
    /// A landing no moment clears keeps its keys.
    ///
    /// On 2026-11-12 the user's trash met the lid as it began to snap shut
    /// at 0.8 s; the model then had it ride the lid down, hop up off the shut
    /// lid at 1.1 s and drop into the can at 1.2 s, straight through the
    /// closed lid. Landed by 0.93 s it comes off the lid down into the can
    /// as the lid slams over it: thrown in, off the lid, and shut, in order.
    /// Ink, keys and time only, any subject.
    static func inBeforeShut(_ steps: [AskStep]) -> [AskStep] {
        guard let lap = Lap(steps) else { return steps }
        let keyedEnds = steps.filter { $0.tool == "set_keys" }.flatMap { AskMotionCheck.timed($0).map(\.seconds) }
        guard let lapEnd = steps.last(where: { $0.tool == "set_timing" })?.arguments["seconds"]?.doubleValue ?? keyedEnds.max() else { return steps }
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        func isPosition(_ step: AskStep) -> Bool {
            step.tool == "set_keys" && step.arguments["property"]?.stringValue == MotionProperty.position.rawValue
        }
        func point(_ value: AgentJSON?) -> CGPoint? {
            guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let tick = 0.01
        var out = steps
        for index in out.indices where isPosition(out[index]) {
            guard let name = layer(out[index]), let part = partReference(name)?.part, lap.isMover(part),
                  !out[(index + 1)...].contains(where: { isPosition($0) && layer($0) == name }),
                  let current = Lap(out) else { continue }
            let keys = AskMotionCheck.timed(out[index])
            guard keys.count >= 3, let landedAt = goneAt(part, keys: keys, in: out),
                  let landing = keys.firstIndex(where: { abs($0.seconds - landedAt) <= 0.0005 }), landing > 0,
                  let goal = point(keys[landing].value) else { continue }
            let family = Set([plain(part)] + current.carriers(of: part).map(plain))
            let closers = current.movers.filter { other in
                !family.contains(plain(other)) && !current.carriers(of: other).contains { plain($0) == plain(part) }
            }
            for closer in closers {
                // When it shuts (at rest from then to the lap's end) and when
                // it set off on that last move.
                let rest = current.ink(closer, at: lapEnd)
                func same(_ a: [[CGPoint]], _ b: [[CGPoint]]) -> Bool {
                    a.count == b.count && zip(a, b).allSatisfy { one, two in
                        one.count == two.count && zip(one, two).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 0.02 }
                    }
                }
                var shut = lapEnd
                while shut - tick > 0, same(current.ink(closer, at: shut - tick), rest) { shut -= tick }
                var setsOff = shut
                while setsOff - tick > 0, !same(current.ink(closer, at: setsOff - tick), current.ink(closer, at: setsOff)) { setsOff -= tick }
                guard shut < lapEnd - tick, setsOff < shut - tick, landedAt > shut + 0.0005, setsOff < landedAt,
                      let from = point(AskMotionCheck.value(of: out[index], at: setsOff)) else { continue }
                // Through the closer while seen. Meeting it as the closer sets
                // off is the hit itself (placed touching it), for `hitGrace`
                // at most: meeting it again once the two have come apart, or
                // staying in it longer (a lid slamming down through what hit
                // it, the eval of 2026-11-13), counts.
                func through(_ made: [AskStep]) -> Bool {
                    guard let lap = Lap(made) else { return true }
                    var moment = setsOff + tick
                    var hitting = true
                    while moment < lapEnd - 0.0005 {
                        guard lap.placed(part, at: moment)?.seen ?? true else { return hitting }
                        let meets = inkMeets(lap.ink(part, at: moment), lap.ink(closer, at: moment), within: -passesThrough)
                        if meets, !hitting || moment > setsOff + hitGrace + 0.0005 { return true }
                        if !meets { hitting = false }
                        moment += tick
                    }
                    return hitting
                }
                guard through(out), var object = out[index].arguments.objectValue, let list = object["keys"]?.arrayValue else { continue }
                // Further from the landing than it was as the closer set off: left out.
                let far = hypot(goal.x - from.x, goal.y - from.y) + 0.0005
                let kept = list.filter { key in
                    guard let at = key["seconds"]?.doubleValue, at > setsOff + 0.0005, at < landedAt - 0.0005,
                          let here = point(key["value"]) else { return true }
                    return hypot(goal.x - here.x, goal.y - here.y) <= far
                }
                let between = kept.compactMap { $0["seconds"]?.doubleValue }.filter { $0 > setsOff + 0.0005 && $0 < landedAt - 0.0005 }
                // Where it lands, and the keys holding it there, may also go
                // a little further in, straight away from where the closer
                // rests: a landing just under the shut lid's line is still in
                // its stroke (the walk of 2026-11-13).
                let width = current.art.viewBox?.width ?? current.art.bounds.width
                let landedInk = current.ink(part, at: landedAt).flatMap { $0 }
                guard !landedInk.isEmpty else { break }
                let middle = CGPoint(x: landedInk.map(\.x).reduce(0, +) / CGFloat(landedInk.count),
                                     y: landedInk.map(\.y).reduce(0, +) / CGFloat(landedInk.count))
                let touch = rest.map { nearest(to: middle, on: $0) }
                    .min { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }
                var away = CGVector.zero
                if let touch, hypot(middle.x - touch.x, middle.y - touch.y) > 1e-6 {
                    let length = hypot(middle.x - touch.x, middle.y - touch.y)
                    away = CGVector(dx: (middle.x - touch.x) / length, dy: (middle.y - touch.y) / length)
                }
                let holds = keys.indices.filter { $0 >= landing && keys[$0].value == keys[landing].value }.map { keys[$0].seconds }
                let near = Double(PropertyKeys.nearMS) / 1000
                var pushes: [CGFloat] = [0]
                if away != .zero {
                    var push = tuckStep * width
                    while push <= mostTuck * width + 0.0005 { pushes.append(push); push += tuckStep * width }
                }
                var found = false
                for push in pushes {
                    var lands = shut
                    while lands >= setsOff + shortestWayIn - 0.0005 {
                        let share = (lands - setsOff) / (landedAt - setsOff)
                        var moved: [AgentJSON] = kept.map { key in
                            guard var one = key.objectValue, let at = one["seconds"]?.doubleValue else { return key }
                            if push > 0, holds.contains(where: { abs($0 - at) <= 0.0005 }),
                               let x = one["value"]?["x"]?.doubleValue, let y = one["value"]?["y"]?.doubleValue {
                                one["value"] = ["x": .number(Double(rounded(CGFloat(x) + away.dx * push))),
                                                "y": .number(Double(rounded(CGFloat(y) + away.dy * push)))]
                            }
                            if at > setsOff + 0.0005, at <= landedAt + 0.0005 {
                                one["seconds"] = .number(Double(rounded(CGFloat(setsOff + (at - setsOff) * share))))
                            }
                            return .object(one)
                        }
                        // Landed sooner, it waits there until the moment it
                        // landed before: what it does after (home, unseen)
                        // keeps its time.
                        if lands < landedAt - near,
                           let slot = moved.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - Double(rounded(CGFloat(lands)))) <= 0.0005 }),
                           var arrival = moved[slot].objectValue {
                            var stays = arrival
                            stays["seconds"] = .number(landedAt)
                            arrival["curve"] = .string(AgentKeyCurve.hold)
                            moved[slot] = .object(arrival)
                            if !moved.contains(where: { abs(($0["seconds"]?.doubleValue ?? -1) - landedAt) <= 0.0005 }) { moved.append(.object(stays)) }
                            moved.sort { ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0) }
                        }
                        let times = moved.compactMap { $0["seconds"]?.doubleValue }.sorted()
                        if between.isEmpty || zip(times, times.dropFirst()).allSatisfy({ $1 - $0 > near }) {
                            object["keys"] = .array(moved)
                            var made = out
                            made[index] = AskStep(tool: made[index].tool, arguments: .object(object))
                            // Off what it met at speed, as a hit is left
                            // (`curved`): a slow start there is caught by the
                            // closer coming down.
                            made = curved(made, step: index, leaving: setsOff, arriving: false)
                            if !through(made) { out = made; found = true; break }
                        }
                        lands -= tick
                    }
                    if found { break }
                }
                break
            }
        }
        return out
    }
}
