import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: What is thrown comes in from outside

    /// `steps` with a part that comes into sight inside `view` as it sets off
    /// on a journey that ends against another part (a hit, a landing) starting
    /// that journey off the frame instead, on the same line, so it is seen
    /// thrown in rather than appearing in mid-air. On 2026-11-10 the user's
    /// trash faded in beside the open lid, a hand's width from where it hit,
    /// in every run, read as "appears out of nothing, never thrown in";
    /// the rules ask for the start outside and the model drew it in view.
    /// Only a part with its own fade, out of sight just before the journey
    /// sets off and seen when it arrives, whose way back to the frame's edge
    /// crosses nothing else. The way in keeps its time and its curve, so it
    /// arrives as planned, faster. Boxes, ink, keys and time only.
    static func thrownIn(_ steps: [AskStep], view: CGRect) -> [AskStep] {
        guard let lap = Lap(steps) else { return steps }
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        func point(_ value: AgentJSON) -> CGPoint? {
            guard let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let fades = Dictionary(steps.filter { $0.tool == "set_keys" && $0.arguments["property"]?.stringValue == MotionProperty.opacity.rawValue }
            .compactMap { step in layer(step).map { ($0, step) } }, uniquingKeysWith: { _, last in last })
        var out = steps
        for index in out.indices where out[index].tool == "set_keys" && out[index].arguments["property"]?.stringValue == MotionProperty.position.rawValue {
            guard let name = layer(out[index]), let fade = fades[name], let part = partReference(name)?.part,
                  lap.isMover(part), var object = out[index].arguments.objectValue, let list = object["keys"]?.arrayValue else { continue }
            func seen(_ at: Double) -> Bool { (AskMotionCheck.value(of: fade, at: at)?.doubleValue ?? 100) > unseen }
            let keys = AskMotionCheck.timed(out[index])
            guard keys.count == list.count else { continue }
            // What it could arrive against: everything else drawn, never what carries it or what it carries.
            let family = Set([plain(part)] + lap.carriers(of: part).map(plain))
            let others = (lap.still.map(\.name) + lap.movers).filter { !family.contains(plain($0)) && !lap.carriers(of: $0).contains { plain($0) == plain(part) } }
            func against(_ at: Double) -> Bool {
                let mine = lap.ink(part, at: at)
                return others.contains { inkMeets(mine, lap.ink($0, at: at)) }
            }
            for start in keys.indices.dropLast() {
                let from = keys[start].seconds
                // Out of sight as it sets off, and set off at once.
                guard !seen(from - 0.01) || !seen(from), let here = point(keys[start].value),
                      let next = point(keys[start + 1].value), next != here else { continue }
                // Moving and seen the whole way to where it arrives against something.
                guard let arrives = keys.indices.first(where: { $0 > start && against(keys[$0].seconds) }),
                      seen(keys[arrives].seconds),
                      (start + 1...arrives).allSatisfy({ point(keys[$0].value) != point(keys[$0 - 1].value) }) else { continue }
                // Comes into sight in the frame.
                guard let quad = lap.placed(part, at: from)?.quad else { continue }
                let xs = quad.map(\.x), ys = quad.map(\.y)
                guard let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() else { continue }
                let box = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                guard share(of: box, in: view) > 0 else { continue }
                let back = CGVector(dx: here.x - next.x, dy: here.y - next.y)
                let far = share(of: back, clearing: box, of: view)
                let outside = CGPoint(x: here.x + back.dx * far, y: here.y + back.dy * far)
                guard var key = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - from) <= 0.0005 }).flatMap({ list[$0].objectValue }),
                      let slot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - from) <= 0.0005 }) else { continue }
                key["value"] = ["x": .number(rounded(outside.x)), "y": .number(rounded(outside.y))]
                var changed = list
                changed[slot] = .object(key)
                object["keys"] = .array(changed)
                var trial = out
                trial[index] = AskStep(tool: out[index].tool, arguments: .object(object))
                // Its way in from the edge crosses nothing seen.
                guard let after = Lap(trial) else { continue }
                let reaches = keys[start + 1].seconds
                var moment = from, crosses = false
                while moment < reaches, !crosses {
                    let mine = after.ink(part, at: moment)
                    crosses = seen(moment) && others.contains { inkMeets(mine, after.ink($0, at: moment), within: -passesThrough) }
                    moment += 0.02
                }
                guard !crosses else { object["keys"] = .array(list); continue }
                out = trial
                break
            }
        }
        return out
    }

    // MARK: What the story uses up is not seen waiting

    /// `steps` with a part the story uses up (seen at the lap's start, it
    /// stands still, sets off, meets another part while seen, and ends out of
    /// sight before the lap is over) kept out of sight until it sets off and
    /// after it is gone, to the lap's end: what is thrown, posted or dropped
    /// in is not seen waiting beside where it goes, and `thrownIn` then brings
    /// it in from off the frame. On 2026-11-11 the user's trash stood in view
    /// beside the can for half the lap before it was thrown, and every look of
    /// the judge read "the trash just hangs beside the can". A part that stays
    /// in sight, or meets nothing on its way, keeps its fade. Keys and time
    /// only, any subject.
    static func usedUpUnseen(_ steps: [AskStep]) -> [AskStep] {
        guard let lap = Lap(steps),
              let lapEnd = steps.last(where: { $0.tool == "set_timing" })?.arguments["seconds"]?.doubleValue else { return steps }
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        let near = Double(PropertyKeys.nearMS) / 1000
        var out = steps
        for index in out.indices where out[index].tool == "set_keys" && property(out[index]) == MotionProperty.position.rawValue {
            guard let name = layer(out[index]), let part = partReference(name)?.part, lap.isMover(part),
                  let fadeAt = out.lastIndex(where: { $0.tool == "set_keys" && layer($0) == name && property($0) == MotionProperty.opacity.rawValue }),
                  var object = out[fadeAt].arguments.objectValue, let list = object["keys"]?.arrayValue else { continue }
            let fade = out[fadeAt]
            func seen(_ at: Double) -> Bool { (AskMotionCheck.value(of: fade, at: at)?.doubleValue ?? 100) > unseen }
            let keys = AskMotionCheck.timed(out[index])
            guard let first = keys.first, first.seconds <= near, seen(0) else { continue }
            // Stands still from the lap's start, then sets off.
            guard let setsOff = keys.indices.dropLast().first(where: { keys[$0 + 1].value != first.value }),
                  keys[...setsOff].allSatisfy({ $0.value == first.value }) else { continue }
            let from = keys[setsOff].seconds
            guard from > 0.05 else { continue }
            // Meets something else drawn while seen.
            let family = Set([plain(part)] + lap.carriers(of: part).map(plain))
            let others = (lap.still.map(\.name) + lap.movers).filter { !family.contains(plain($0)) && !lap.carriers(of: $0).contains { plain($0) == plain(part) } }
            guard let arrives = keys.indices.first(where: { at in
                at > setsOff && seen(keys[at].seconds) && others.contains { inkMeets(lap.ink(part, at: keys[at].seconds), lap.ink($0, at: keys[at].seconds)) }
            }) else { continue }
            // Then goes out of sight before the lap is over.
            let fades = AskMotionCheck.timed(fade)
            guard fades.count == list.count,
                  let gone = fades.first(where: { $0.seconds > keys[arrives].seconds + 0.0005 && ($0.value.doubleValue ?? 100) <= unseen })?.seconds,
                  gone < lapEnd - near else { continue }
            let appears = from + 0.05
            var made: [AgentJSON] = [["seconds": .number(0), "value": .number(0)], ["seconds": .number(from), "value": .number(0)],
                                     ["seconds": .number(rounded(CGFloat(appears))), "value": AskMotionCheck.value(of: fade, at: appears) ?? .number(100)]]
            made += list.filter { key in
                guard let at = key["seconds"]?.doubleValue else { return false }
                return at > appears + near && at <= gone + 0.0005
            }
            made.append(["seconds": .number(lapEnd), "value": .number(0)])
            let times = made.compactMap { $0["seconds"]?.doubleValue }
            guard zip(times, times.dropFirst()).allSatisfy({ $1 - $0 > near }) else { continue }
            object["keys"] = .array(made)
            out[fadeAt] = AskStep(tool: fade.tool, arguments: .object(object))
        }
        return out
    }
}
