import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: What goes in under a closing part is in before it shuts

    /// The shortest the way in from where the part was as the closer began
    /// to shut may take, in seconds.
    static let shortestWayIn = 0.08

    /// `steps` with a part that goes out of sight where it lands, and passes
    /// through another moving part (a closer: a lid, a flap, a door) while
    /// seen, landed before that part shuts: from the moment the closer sets
    /// off on its last move to rest, the part's keys that take it further
    /// from where it lands than it was then are left out (a hop up over what
    /// is shutting), and its landing comes at the latest moment, no later
    /// than the closer shuts, at which it passes through nothing it is meant
    /// to go in under. The keys between keep their order, closer in time.
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
                func through(_ made: [AskStep]) -> Bool {
                    guard let lap = Lap(made) else { return true }
                    var moment = setsOff + tick
                    while moment < lapEnd - 0.0005 {
                        guard lap.placed(part, at: moment)?.seen ?? true else { break }
                        if inkMeets(lap.ink(part, at: moment), lap.ink(closer, at: moment), within: -passesThrough) { return true }
                        moment += tick
                    }
                    return false
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
                var lands = shut
                while lands >= setsOff + shortestWayIn - 0.0005 {
                    let share = (lands - setsOff) / (landedAt - setsOff)
                    let moved: [AgentJSON] = kept.map { key in
                        guard var one = key.objectValue, let at = one["seconds"]?.doubleValue,
                              at > setsOff + 0.0005, at <= landedAt + 0.0005 else { return key }
                        one["seconds"] = .number(Double(rounded(CGFloat(setsOff + (at - setsOff) * share))))
                        return .object(one)
                    }
                    let times = moved.compactMap { $0["seconds"]?.doubleValue }.sorted()
                    let near = Double(PropertyKeys.nearMS) / 1000
                    if between.isEmpty || zip(times, times.dropFirst()).allSatisfy({ $1 - $0 > near }) {
                        object["keys"] = .array(moved)
                        var made = out
                        made[index] = AskStep(tool: made[index].tool, arguments: .object(object))
                        if !through(made) { out = made; break }
                    }
                    lands -= tick
                }
                break
            }
        }
        return out
    }
}
