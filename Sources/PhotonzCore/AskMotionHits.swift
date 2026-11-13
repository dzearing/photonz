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
                // Going home: it arrived as the fade began and turns back
                // for where the lap starts, getting there at the lap's end.
                // That trip is the next lap's, unseen (`staysTillGone` holds
                // it where it landed until it is gone). On 2026-11-12 it was
                // read as a journey to be seen: the fade moved to its end and
                // the trash rose out of the can over the shut lid.
                if goesHome(moves, fadeFrom: from.seconds) { continue }
                // Where it arrives: a key of its journey at the very moment
                // it is gone (pass twelve's walk: gone at 1.1 s in the can,
                // then back to the start unseen by the lap's end), else the
                // first key after the fade starts that the next one does not
                // move from.
                let goneThere = moves.contains { abs($0.seconds - to.seconds) <= near }
                guard let landing = moves.indices.first(where: { at in
                    moves[at].seconds > from.seconds + 0.0005 && (at + 1 == moves.count || moves[at + 1].value == moves[at].value)
                }) else { continue }
                var arrives = goneThere ? to.seconds : moves[landing].seconds
                if index + 2 < keys.count { arrives = min(arrives, keys[index + 2].seconds - 2 * near) }
                // Faded out by the very moment it lands (run 20261111-103646:
                // the trash faded over its whole throw into the can): seen
                // the whole way, faded over the last of it.
                if abs(arrives - to.seconds) <= near {
                    let starts = to.seconds - fadesWhereItArrives
                    guard starts > from.seconds + near else { continue }
                    keys.insert((Double(rounded(CGFloat(starts))), from.value, from.curve), at: index + 1)
                    changed = true
                    index += 1
                    continue
                }
                guard arrives > to.seconds + near else { continue }
                // Its fade's last key has to stand apart from the key after,
                // or the app reads the two as one and refuses the fade.
                if index + 2 < keys.count, keys[index + 2].seconds - arrives <= near { continue }
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

    /// Whether the position keys `moves` arrive somewhere as a fade starting
    /// at `fadeFrom` begins, and then turn back (more than a right angle) on
    /// one leg to the lap's last key, which is where the lap's first key
    /// has it: the way home for the next lap.
    static func goesHome(_ moves: [(seconds: Double, value: AgentJSON, curve: String?)], fadeFrom: Double) -> Bool {
        func point(_ value: AgentJSON) -> CGPoint? {
            guard let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let near = Double(PropertyKeys.nearMS) / 1000
        guard moves.count >= 3, let first = moves.first, let last = moves.last, first.value == last.value,
              let k = moves.indices.last(where: { $0 > 0 && $0 + 1 < moves.count && abs(moves[$0].seconds - fadeFrom) <= near }),
              k + 2 == moves.count,
              let before = point(moves[k - 1].value), let here = point(moves[k].value), let next = point(last.value) else { return false }
        let came = CGVector(dx: here.x - before.x, dy: here.y - before.y), goes = CGVector(dx: next.x - here.x, dy: next.y - here.y)
        let lengths = hypot(came.dx, came.dy) * hypot(goes.dx, goes.dy)
        return lengths > 1e-6 && (came.dx * goes.dx + came.dy * goes.dy) / lengths < 0
    }

    // MARK: Gone where it landed

    /// `steps` with a part that is still fading out when it sets off back the
    /// way it came (its next key turns it round, more than a right angle)
    /// held where it arrived until it is out of sight: a position key at the
    /// moment its fade ends, the arrival's value. Coming back is for the next
    /// lap, unseen. On 2026-11-11 the model faded the trash from 1.1 to
    /// 1.2 s and sent it home from 1.1 s: a grey ghost of it rose out of the
    /// can over the shutting lid. Keys and time only.
    static func staysTillGone(_ steps: [AskStep]) -> [AskStep] {
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        func point(_ value: AgentJSON) -> CGPoint? {
            guard let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let near = Double(PropertyKeys.nearMS) / 1000
        var out = steps
        for index in out.indices where out[index].tool == "set_keys" && property(out[index]) == MotionProperty.position.rawValue {
            guard let name = layer(out[index]),
                  !out[(index + 1)...].contains(where: { $0.tool == "set_keys" && layer($0) == name && property($0) == MotionProperty.position.rawValue }),
                  let fade = out.last(where: { $0.tool == "set_keys" && layer($0) == name && property($0) == MotionProperty.opacity.rawValue }),
                  var object = out[index].arguments.objectValue, var list = object["keys"]?.arrayValue else { continue }
            let keys = AskMotionCheck.timed(out[index])
            guard keys.count == list.count else { continue }
            let fades = AskMotionCheck.timed(fade)
            // Each fade out: from seen to out of sight.
            for (from, to) in zip(fades, fades.dropFirst()) where (from.value.doubleValue ?? 0) >= 50 && (to.value.doubleValue ?? 100) <= unseen {
                // The key it arrived at as the fade began, or during it.
                guard let k = keys.indices.last(where: { $0 > 0 && keys[$0].seconds <= to.seconds - near && keys[$0].seconds >= from.seconds - near }),
                      k + 1 < keys.count, keys[k + 1].seconds > to.seconds + near,
                      let before = point(keys[k - 1].value), let here = point(keys[k].value), let next = point(keys[k + 1].value) else { continue }
                let came = CGVector(dx: here.x - before.x, dy: here.y - before.y), goes = CGVector(dx: next.x - here.x, dy: next.y - here.y)
                let lengths = hypot(came.dx, came.dy) * hypot(goes.dx, goes.dy)
                guard lengths > 1e-6, (came.dx * goes.dx + came.dy * goes.dy) / lengths < 0 else { continue }
                var hold: [String: AgentJSON] = ["seconds": .number(rounded(CGFloat(to.seconds))), "value": keys[k].value]
                if let curve = keys[k].curve { hold["curve"] = .string(curve) }
                // The way home keeps the curve it had; the arrival stands still.
                if let slot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - keys[k].seconds) <= 0.0005 }),
                   var arrival = list[slot].objectValue {
                    arrival["curve"] = .string(AgentKeyCurve.hold)
                    list[slot] = .object(arrival)
                }
                list.append(.object(hold))
                list.sort { ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0) }
                object["keys"] = .array(list)
                out[index] = AskStep(tool: out[index].tool, arguments: .object(object))
                break
            }
        }
        return out
    }

    // MARK: Keys the app takes

    /// The least gap `keysApart` leaves between two keys it moves apart.
    static let keyGap = 0.03

    /// `steps` with no two keys of one set_keys closer than the app takes
    /// (`PropertyKeys.nearMS`): the inner key of a pair too close moves away
    /// from its neighbour by `keyGap` where there is room, and goes where
    /// there is not. The app refuses the whole call for one such pair, and
    /// on 2026-11-11 a fade the landing had moved to 20 ms before the lap's
    /// last key was refused whole: the trash sat in view all lap and the row
    /// said "Left out a layer: it could not be done". Time only.
    public static func keysApart(_ steps: [AskStep]) -> [AskStep] {
        func seconds(_ key: AgentJSON) -> Double { key["seconds"]?.doubleValue ?? 0 }
        func at(_ key: AgentJSON, _ moment: Double) -> AgentJSON {
            guard var object = key.objectValue else { return key }
            object["seconds"] = .number(rounded(CGFloat(moment)))
            return .object(object)
        }
        return steps.map { step in
            guard step.tool == "set_keys", var object = step.arguments.objectValue,
                  var keys = object["keys"]?.arrayValue, keys.count > 1 else { return step }
            keys.sort { seconds($0) < seconds($1) }
            func tooClose(_ a: Double, _ b: Double) -> Bool { ((b - a) * 1000).rounded() <= Double(PropertyKeys.nearMS) }
            var changed = false
            var index = 0
            while index + 1 < keys.count {
                let (a, b) = (seconds(keys[index]), seconds(keys[index + 1]))
                guard tooClose(a, b) else { index += 1; continue }
                changed = true
                let last = index + 1 == keys.count - 1
                if !last, !tooClose(a + keyGap, seconds(keys[index + 2])) {
                    keys[index + 1] = at(keys[index + 1], a + keyGap)
                } else if index > 0, !tooClose(seconds(keys[index - 1]), b - keyGap) {
                    keys[index] = at(keys[index], b - keyGap)
                } else if last, index == 0 {
                    keys.remove(at: index + 1)
                } else {
                    keys.remove(at: last ? index : index + 1)
                }
            }
            guard changed else { return step }
            object["keys"] = .array(keys)
            return AskStep(tool: step.tool, arguments: .object(object))
        }
    }
}
