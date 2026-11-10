import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: A seen hold moves

    /// What a part does between keys that is a move, not a look: a hold that
    /// jumps while seen is a snap.
    static let moveProperties: Set<String> = [MotionProperty.position.rawValue, MotionProperty.rotation.rawValue,
                                              MotionProperty.scale.rawValue]

    /// `steps` with every Hold that stays where the part already was, and
    /// then jumps to a new value while the part is seen at both ends, run on
    /// the next key's curve instead (Ease in out when it has none); the first
    /// key's Hold too, which holds nothing. The model writes a key's curve as
    /// how the part ARRIVES there, a Hold on the key it stays until and the
    /// overshoot on the key it lands at, while a curve is the run LEAVING its
    /// key: 81 such keys in the eval's plans by 2026-11-09, and the trash's lid
    /// stood open and snapped shut in one frame in every look. A jump out of
    /// sight (off the frame, or faded out) is meant and keeps its Hold, and so
    /// does a Hold reached by moving, which steps on. Keys and time only.
    public static func holdsMove(_ steps: [AskStep]) -> [AskStep] {
        guard let lap = Lap(steps) else { return steps }
        let view = lap.art.viewBox
        func seen(_ name: String, at seconds: Double) -> Bool {
            guard let there = lap.placed(name, at: seconds), there.seen else { return false }
            guard let view else { return true }
            let xs = there.quad.map(\.x), ys = there.quad.map(\.y)
            guard let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() else { return false }
            return CGRect(x: left, y: top, width: right - left, height: bottom - top).intersects(view)
        }
        return steps.map { step in
            guard step.tool == "set_keys", let property = step.arguments["property"]?.stringValue, moveProperties.contains(property),
                  let name = (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part,
                  var object = step.arguments.objectValue, var list = step.arguments["keys"]?.arrayValue, list.count > 1 else { return step }
            let order = list.indices.sorted { (list[$0]["seconds"]?.doubleValue ?? 0, $0) < (list[$1]["seconds"]?.doubleValue ?? 0, $1) }
            var changed = false
            for at in 0..<(order.count - 1) {
                let key = list[order[at]], next = list[order[at + 1]]
                guard key["curve"]?.stringValue?.caseInsensitiveCompare(AgentKeyCurve.hold) == .orderedSame,
                      let value = key["value"], let after = next["value"], value != after,
                      let from = key["seconds"]?.doubleValue, let to = next["seconds"]?.doubleValue else { continue }
                // Already there: the first key, or the key before it holds the same value.
                guard at == 0 || list[order[at - 1]]["value"] == value else { continue }
                guard seen(name, at: from), seen(name, at: to), seen(name, at: (from + to) / 2) else { continue }
                let curve = next["curve"]?.stringValue.flatMap { $0.caseInsensitiveCompare(AgentKeyCurve.hold) == .orderedSame ? nil : $0 }
                guard var one = key.objectValue else { continue }
                one["curve"] = .string(curve ?? AgentKeyCurve.easeInOut)
                list[order[at]] = .object(one)
                changed = true
            }
            guard changed else { return step }
            object["keys"] = .array(list)
            return AskStep(tool: step.tool, arguments: .object(object))
        }
    }

    // MARK: A hit starts what it hits

    /// The longest a part that is hit may stand still before it moves and
    /// still be moved by the hit: the trash's lid waited 0.3 s.
    static let hitStartsWithin = 0.5

    /// `steps` with a part that a key `touches`, standing still at that
    /// moment and keyed to start moving soon after, starting that move the
    /// moment it is hit: what follows comes earlier by the wait, and the lap
    /// still ends where it did. On 2026-11-09 the trash met the lid at 0.6 s
    /// and the lid shut at 0.9 s, read as "the lid shuts on its own" in every
    /// look though the request said the hit closes it. Only moves (position,
    /// turn, size) of the part hit or a group carrying it; a part that is
    /// moving anyway, or waits longer than `hitStartsWithin`, keeps its keys.
    ///
    /// It starts as soon after the hit as it can without passing through the
    /// part that hit it, tried every `hitStartStep`: on 2026-11-10 the trash's
    /// lid, started at the very moment of the hit, swept down through the
    /// ball as it dropped in. When every start would pass through, the keys
    /// stay as planned.
    public static func hitStarts(_ steps: [AskStep]) -> [AskStep] {
        var hits: [(seconds: Double, part: String, by: String?)] = []
        for step in steps where step.tool == "set_keys" && step.arguments["property"]?.stringValue == MotionProperty.position.rawValue {
            let mine = (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part
            for key in step.arguments["keys"]?.arrayValue ?? [] {
                guard let word = key["touches"]?.stringValue, let seconds = key["seconds"]?.doubleValue else { continue }
                let other = partReference(word)?.part ?? word
                if let mine, plain(mine) == plain(other) { continue }
                hits.append((seconds, other, mine))
            }
        }
        guard !hits.isEmpty, let lap = Lap(steps) else { return steps }
        let lapEnd = steps.last { $0.tool == "set_timing" }?.arguments["seconds"]?.doubleValue
        let near = Double(PropertyKeys.nearMS) / 1000
        var out = steps
        for hit in hits {
            let struck = Set(([hit.part] + lap.carriers(of: hit.part)).map(plain))
            for at in out.indices where out[at].tool == "set_keys" {
                guard let property = out[at].arguments["property"]?.stringValue, moveProperties.contains(property),
                      let name = (out[at].arguments["layer"]?.stringValue).flatMap(partReference)?.part,
                      struck.contains(plain(name)), let object = out[at].arguments.objectValue else { continue }
                let keys = AskMotionCheck.timed(out[at])
                guard keys.count == out[at].arguments["keys"]?.arrayValue?.count, let still = AskMotionCheck.value(of: out[at], at: hit.seconds),
                      AskMotionCheck.value(of: out[at], at: hit.seconds + near) == still,
                      let first = keys.firstIndex(where: { $0.seconds > hit.seconds + 0.0005 }) else { continue }
                // The last key still there, then the move.
                var starts = first
                while starts + 1 < keys.count, keys[starts].value == still, keys[starts + 1].value == still { starts += 1 }
                guard keys[starts].value == still, starts + 1 < keys.count else { continue }
                let wait = keys[starts].seconds - hit.seconds
                guard wait > near, wait <= hitStartsWithin else { continue }
                let lastSeconds = keys[keys.count - 1].seconds
                let endsLap = lapEnd.map { lastSeconds >= $0 - 0.0005 } ?? true
                let planned = keys
                func started(after shift: Double) -> AskStep {
                    var made = Array(planned[..<first]).filter { $0.seconds < hit.seconds - near }
                    for key in planned[starts...] { made.append((Double(rounded(CGFloat(key.seconds - wait + shift))), key.value, key.curve)) }
                    if endsLap, let last = made.last, last.seconds < lastSeconds - near { made.append((lastSeconds, last.value, nil)) }
                    var changed = object
                    changed["keys"] = .array(made.map { key in
                        var json: [String: AgentJSON] = ["seconds": .number(key.seconds), "value": key.value]
                        if let curve = key.curve { json["curve"] = .string(curve) }
                        return .object(json)
                    })
                    return AskStep(tool: out[at].tool, arguments: .object(changed))
                }
                // How long the move it starts lasts, to watch it through.
                let moveLasts = (planned.last { $0.value != still }.map(\.seconds) ?? planned[starts + 1].seconds) - planned[starts].seconds
                var shift = 0.0
                while shift < wait - near {
                    let tried = started(after: shift)
                    var trial = out
                    trial[at] = tried
                    if let by = hit.by, crosses(name, by, from: hit.seconds + shift, lasting: moveLasts + hitStartStep, in: trial) {
                        shift += hitStartStep
                        continue
                    }
                    out[at] = tried
                    break
                }
            }
        }
        return out
    }
    /// How much later each try at starting what was hit comes.
    static let hitStartStep = 0.05
    /// How deep two parts' ink may overlap and still read as touching, not
    /// one passing through the other.
    static let passesThrough: CGFloat = 0.3

    /// Whether `moving`, as `steps` key it with each hit placed, passes
    /// through `other` at any moment from `from` for `lasting` seconds.
    static func crosses(_ moving: String, _ other: String, from: Double, lasting: Double, in steps: [AskStep]) -> Bool {
        guard let lap = Lap(touchesPlaced(steps)) else { return false }
        var seconds = from + 0.02
        while seconds <= from + lasting {
            if inkMeets(lap.ink(moving, at: seconds), lap.ink(other, at: seconds), within: -passesThrough) { return true }
            seconds += 0.02
        }
        return false
    }

    // MARK: Seen the whole way

    /// How long what arrived takes to fade where it arrived.
    static let fadesWhereItArrives = 0.1

    /// `steps` with a part that fades out while it travels a long way (at
    /// least `longJourney` on the grid between the fade's two keys) kept
    /// seen the whole way, and faded over `fadesWhereItArrives` once it has
    /// arrived. On 2026-11-09 the trash was faded out over its whole throw,
    /// so it "fades out in mid-air" and "is never thrown in", in every look.
    /// A short drift that fades is a puff and a part that grows as it goes is
    /// a mark left behind: both keep their fade. Keys and time only.
    public static func travelsSeen(_ steps: [AskStep]) -> [AskStep] {
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        let near = Double(PropertyKeys.nearMS) / 1000
        return steps.map { step in
            guard step.tool == "set_keys", property(step) == MotionProperty.opacity.rawValue, let name = layer(step),
                  let travel = steps.last(where: { $0.tool == "set_keys" && layer($0) == name && property($0) == MotionProperty.position.rawValue }),
                  var object = step.arguments.objectValue else { return step }
            if let grow = steps.last(where: { $0.tool == "set_keys" && layer($0) == name && property($0) == MotionProperty.scale.rawValue }),
               Set(AskMotionCheck.timed(grow).compactMap { $0.value.doubleValue }).count > 1 { return step }
            var keys = AskMotionCheck.timed(step)
            guard keys.count == step.arguments["keys"]?.arrayValue?.count else { return step }
            let moves = AskMotionCheck.timed(travel)
            func at(_ seconds: Double) -> CGPoint? {
                let value = AskMotionCheck.value(of: travel, at: seconds)
                guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
                return CGPoint(x: x, y: y)
            }
            var changed = false
            var index = 0
            while index + 1 < keys.count {
                defer { index += 1 }
                let (from, to) = (keys[index], keys[index + 1])
                guard (from.value.doubleValue ?? 0) >= 50, (to.value.doubleValue ?? 100) <= unseen,
                      from.curve?.caseInsensitiveCompare(AgentKeyCurve.hold) != .orderedSame else { continue }
                // How far it goes while it fades.
                var far: CGFloat = 0
                var moment = from.seconds
                while moment < to.seconds - 0.0005 {
                    let next = min(moment + leavingStep, to.seconds)
                    if let a = at(moment), let b = at(next) { far += hypot(b.x - a.x, b.y - a.y) }
                    moment = next
                }
                guard far >= AskMotionCheck.longJourney else { continue }
                // Where it arrives: the first key after the fade starts that the next one does not move from.
                guard let landing = moves.indices.first(where: { at in
                    moves[at].seconds > from.seconds + 0.0005 && (at + 1 == moves.count || moves[at + 1].value == moves[at].value)
                }) else { continue }
                var arrives = moves[landing].seconds
                if index + 2 < keys.count { arrives = min(arrives, keys[index + 2].seconds - near) }
                guard arrives > to.seconds + near else { continue }
                let starts = max(to.seconds, arrives - fadesWhereItArrives)
                keys[index + 1] = (Double(rounded(CGFloat(starts))), from.value, to.curve)
                keys.insert((Double(rounded(CGFloat(arrives))), to.value, nil), at: index + 2)
                changed = true
                index += 1
            }
            guard changed else { return step }
            object["keys"] = .array(keys.map { key in
                var json: [String: AgentJSON] = ["seconds": .number(key.seconds), "value": key.value]
                if let curve = key.curve { json["curve"] = .string(curve) }
                return .object(json)
            })
            return AskStep(tool: step.tool, arguments: .object(object))
        }
    }
}
