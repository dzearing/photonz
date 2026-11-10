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
}
