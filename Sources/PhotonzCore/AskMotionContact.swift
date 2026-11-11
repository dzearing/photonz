import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: Where the parts are at a moment

    /// A planned drawing's parts as its keys move them: where each is at any
    /// moment, on the drawing's grid. Boxes turned, grown and moved as the
    /// keys say (in a straight line between keys, a Hold standing still), a
    /// part inside a keyed group carried with it. What `whereParts` says and
    /// what `touchesPlaced` measures.
    struct Lap {
        let art: SVGArtwork
        let keyed: [AskStep]
        /// The keyed parts, in the order first keyed.
        let movers: [String]
        /// What stays still, each as its outermost named thing.
        let still: [(name: String, box: CGRect)]

        /// nil when the plan has no drawing whose parts can be read.
        init?(_ planned: [AskStep]) {
            let steps = AskMotion.folded(planned)
            guard let svg = steps.first(where: { $0.tool == "add_drawing" })?.arguments["svg"]?.stringValue,
                  case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return nil }
            let keyed = steps.filter { $0.tool == "set_keys" }
            var movers: [String] = []
            for step in keyed {
                guard let part = (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part,
                      AskMotionCheck.box(of: part, in: art) != nil, !movers.contains(where: { plain($0) == plain(part) }) else { continue }
                movers.append(part)
            }
            var still: [(name: String, box: CGRect)] = []
            for part in art.parts where !movers.contains(where: { Self.holds(part, $0) }) {
                guard let unit = part.groups.first ?? part.name else { continue }
                let own = SVGArtwork.shapeBounds(part.shape).insetBy(dx: -part.strokeWidth / 2, dy: -part.strokeWidth / 2)
                if let at = still.firstIndex(where: { plain($0.name) == plain(unit) }) {
                    still[at].box = still[at].box.union(own)
                } else {
                    still.append((unit, own))
                }
            }
            self.art = art
            self.keyed = keyed
            self.movers = movers
            self.still = still
        }

        static func holds(_ part: SVGArtwork.Part, _ name: String) -> Bool {
            part.name.map { plain($0) == plain(name) } ?? false || part.groups.contains { plain($0) == plain(name) }
        }

        /// The keyed groups `name` sits inside, innermost first.
        func carriers(of name: String) -> [String] {
            guard let first = art.parts.first(where: { Self.holds($0, name) }) else { return [] }
            let outer = first.groups.firstIndex { plain($0) == plain(name) }.map { Array(first.groups[..<$0]) } ?? first.groups
            return outer.reversed().compactMap { group in movers.first { plain($0) == plain(group) } }
        }

        func isMover(_ name: String) -> Bool { movers.contains { plain($0) == plain(name) } }

        /// A value at `seconds` as the icon plays it, on each key's curve
        /// (`AskMotionCheck.played`).
        func value(_ name: String, _ property: MotionProperty, at seconds: Double) -> AgentJSON? {
            guard let step = keyed.last(where: { one in
                (one.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) == plain(name) } ?? false
                    && one.arguments["property"]?.stringValue == property.rawValue
            }) else { return nil }
            return AskMotionCheck.played(of: step, at: seconds)
        }

        func pivot(of name: String) -> CGPoint? {
            guard let step = keyed.last(where: { one in
                (one.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) == plain(name) } ?? false
                    && one.arguments["property"]?.stringValue == MotionProperty.rotation.rawValue
            }), let own = AskMotionCheck.box(of: name, in: art) else { return nil }
            guard let x = step.arguments["pivot"]?["x"]?.doubleValue, let y = step.arguments["pivot"]?["y"]?.doubleValue else {
                return CGPoint(x: own.midX, y: own.midY)
            }
            return isFraction(x, y) ? CGPoint(x: own.minX + own.width * x, y: own.minY + own.height * y) : CGPoint(x: x, y: y)
        }

        /// `points` as `name`'s own keys move them at `seconds`.
        func moved(_ points: [CGPoint], by name: String, at seconds: Double) -> [CGPoint] {
            guard let own = AskMotionCheck.box(of: name, in: art) else { return points }
            let middle = CGPoint(x: own.midX, y: own.midY)
            let grow = (value(name, .scale, at: seconds)?.doubleValue ?? 100) / 100
            let degrees = value(name, .rotation, at: seconds)?.doubleValue ?? 0
            let pivot = pivot(of: name) ?? middle
            let shift = value(name, .position, at: seconds)
            let (dx, dy) = (shift?["x"]?.doubleValue ?? 0, shift?["y"]?.doubleValue ?? 0)
            let angle = degrees * .pi / 180
            return points.map { point in
                let grown = CGPoint(x: middle.x + (point.x - middle.x) * grow, y: middle.y + (point.y - middle.y) * grow)
                let (x, y) = (grown.x - pivot.x, grown.y - pivot.y)
                return CGPoint(x: pivot.x + x * cos(angle) - y * sin(angle) + dx, y: pivot.y + x * sin(angle) + y * cos(angle) + dy)
            }
        }

        static func corners(_ box: CGRect) -> [CGPoint] {
            [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
             CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        }

        /// Where a keyed part is at `seconds`, and whether it can be seen.
        func placed(_ name: String, at seconds: Double) -> (quad: [CGPoint], seen: Bool)? {
            guard let own = AskMotionCheck.box(of: name, in: art) else { return nil }
            var quad = moved(Self.corners(own), by: name, at: seconds)
            var seen = (value(name, .opacity, at: seconds)?.doubleValue ?? 100) >= 10
            for carrier in carriers(of: name) {
                quad = moved(quad, by: carrier, at: seconds)
                seen = seen && (value(carrier, .opacity, at: seconds)?.doubleValue ?? 100) >= 10
            }
            return (quad, seen)
        }

        /// Where any named part is at `seconds`: keyed, carried by a keyed
        /// group, or still.
        func outline(_ name: String, at seconds: Double) -> [CGPoint]? {
            if isMover(name) || !carriers(of: name).isEmpty { return placed(name, at: seconds)?.quad }
            return AskMotionCheck.box(of: name, in: art).map(Self.corners)
        }

        /// The ink of every drawn part `name` holds, each as the convex
        /// outline of what it draws (a circle as drawn, a line as thick as
        /// its stroke, a curve within its handles), carried by every keyed
        /// group it sits in, to where the keys have it at `seconds`. What
        /// touching is read off: boxes overlap where the ink does not (a
        /// ball under a tilted bar, 2026-11-10).
        func ink(_ name: String, at seconds: Double) -> [[CGPoint]] {
            art.parts.filter { Self.holds($0, name) }.map { part in
                // Innermost first: the part's own keys, then each group out.
                let chain = ([part.name].compactMap { $0 } + part.groups.reversed()).compactMap { group in
                    movers.first { plain($0) == plain(group) }
                }
                var points = Self.inkPoints(part)
                for mover in chain { points = moved(points, by: mover, at: seconds) }
                return AskMotion.hull(points)
            }
        }

        static func inkPoints(_ part: SVGArtwork.Part) -> [CGPoint] {
            let half = part.stroke == nil ? 0 : part.strokeWidth / 2
            switch part.shape {
            case .ellipse(let box):
                return (0..<24).map { step in
                    let angle = Double(step) * .pi / 12
                    return CGPoint(x: box.midX + (box.width / 2 + half) * cos(angle), y: box.midY + (box.height / 2 + half) * sin(angle))
                }
            case .rect(let box, _):
                return corners(box.insetBy(dx: -half, dy: -half))
            case .path(let outline):
                let points = outline.rings.flatMap { ring in
                    ring.flatMap { anchor in
                        [anchor.point] + [anchor.handleIn, anchor.handleOut].compactMap { handle in
                            handle.map { CGPoint(x: anchor.point.x + $0.x, y: anchor.point.y + $0.y) }
                        }
                    }
                }
                guard half > 0 else { return points }
                return points.flatMap { point in
                    (0..<8).map { step in
                        let angle = Double(step) * .pi / 4
                        return CGPoint(x: point.x + half * cos(angle), y: point.y + half * sin(angle))
                    }
                }
            }
        }

        /// What `name` might touch at `seconds`: what stays, and what moves
        /// and is seen then, never what carries it or what it carries.
        func others(of name: String, at seconds: Double) -> [(name: String, quad: [CGPoint])] {
            let family = Set(carriers(of: name).map(plain) + [plain(name)])
                .union(movers.filter { carriers(of: $0).contains { plain($0) == plain(name) } }.map(plain))
            var others: [(name: String, quad: [CGPoint])] = still
                .filter { unit in !family.contains(plain(unit.name)) && !art.parts.contains { Self.holds($0, name) && $0.groups.contains { plain($0) == plain(unit.name) } } }
                .map { ($0.name, Self.corners($0.box)) }
            for other in movers where !family.contains(plain(other)) {
                if let there = placed(other, at: seconds), there.seen { others.append((other, there.quad)) }
            }
            return others
        }
    }

    // MARK: A key that touches

    /// What the moving icon's model is offered: Ask's tools for a picture,
    /// with a key of set_keys able to say which part it touches.
    public static let modelTools: [AgentJSON] = tools.compactMap { name in
        let tool = (AskTools.pictureKeyModelTools + AskTools.modelTools).first { $0["function"]?["name"]?.stringValue == name }
        guard name == "set_keys", var whole = tool?.objectValue, var function = whole["function"]?.objectValue,
              var parameters = function["parameters"]?.objectValue, var properties = parameters["properties"]?.objectValue,
              var keys = properties["keys"]?.objectValue, var items = keys["items"]?.objectValue,
              var itemProperties = items["properties"]?.objectValue else { return tool }
        itemProperties["touches"] = ["type": "string", "description": .string(touchesWords)]
        items["properties"] = .object(itemProperties)
        keys["items"] = .object(items)
        properties["keys"] = .object(keys)
        parameters["properties"] = .object(properties)
        function["parameters"] = .object(parameters)
        whole["function"] = .object(function)
        return .object(whole)
    }

    static let touchesWords = "On a position key: the id of the part this one hits, lands on or bounces off at this moment. The key is moved so the two just meet."

    /// set_keys arguments with no key saying what it touches: what the tool
    /// itself takes.
    static func withoutTouches(_ arguments: AgentJSON) -> AgentJSON {
        guard var object = arguments.objectValue, let keys = object["keys"]?.arrayValue,
              keys.contains(where: { $0["touches"] != nil }) else { return arguments }
        object["keys"] = .array(keys.map { key in
            guard var one = key.objectValue else { return key }
            one["touches"] = nil
            return .object(one)
        })
        return .object(object)
    }

    /// The steps with every key written again for the same value, at the same
    /// moment as an earlier key that said what it `touches`, saying it too
    /// when it says nothing itself. A model mending its keys writes them out
    /// again and leaves the extra word off: on 2026-11-09 the trash of the
    /// user's story lost its hit on the lid that way, and with it the bounce
    /// and the lid shutting because of it.
    public static func touchesKept(_ steps: [AskStep]) -> [AskStep] {
        func value(of step: AskStep) -> String? {
            guard step.tool == "set_keys", let layer = step.arguments["layer"]?.stringValue else { return nil }
            return [layer, step.arguments["property"]?.stringValue ?? "", step.arguments["effect"]?.stringValue ?? ""]
                .joined(separator: "\u{1F}")
        }
        let near = Double(PropertyKeys.nearMS) / 1000
        var said: [String: [(seconds: Double, value: AgentJSON?, other: AgentJSON)]] = [:]
        // The one key of `keys` that arrives at `value` (the key before it
        // somewhere else), when exactly one does: the hit written again at
        // another moment, the way a mend that slows the lap writes it.
        func arriving(at value: AgentJSON?, in keys: [AgentJSON]) -> Double? {
            guard let value else { return nil }
            let timed = keys.compactMap { key in key["seconds"]?.doubleValue.map { ($0, key["value"]) } }
                .sorted { $0.0 < $1.0 }
            let arrivals = timed.indices.filter { at in timed[at].1 == value && (at == 0 || timed[at - 1].1 != value) }
            return arrivals.count == 1 ? timed[arrivals[0]].0 : nil
        }
        var out = steps
        for at in out.indices {
            guard let own = value(of: out[at]), var object = out[at].arguments.objectValue,
                  let keys = object["keys"]?.arrayValue else { continue }
            let before = said[own] ?? []
            var changed = false
            let written: [AgentJSON] = keys.map { key in
                guard var one = key.objectValue, one["touches"] == nil, let seconds = one["seconds"]?.doubleValue,
                      let earlier = before.last(where: { abs($0.seconds - seconds) <= near })
                        ?? before.last(where: { said in arriving(at: said.value, in: keys).map { abs($0 - seconds) <= near } ?? false })
                else { return key }
                one["touches"] = earlier.other
                changed = true
                return .object(one)
            }
            if changed {
                object["keys"] = .array(written)
                out[at] = AskStep(tool: out[at].tool, arguments: .object(object))
            }
            for key in written {
                if let seconds = key["seconds"]?.doubleValue, let other = key["touches"] { said[own, default: []].append((seconds, key["value"], other)) }
            }
        }
        return out
    }

    /// The steps with every position key that says what it `touches` moved,
    /// straight towards that part, just far enough that the two meet at that
    /// moment, as the keys move them both; and `touches` taken off every key,
    /// moved or not. A key already touching, or naming a part the drawing
    /// does not have, keeps its value.
    public static func touchesPlaced(_ steps: [AskStep]) -> [AskStep] {
        guard steps.contains(where: { step in (step.arguments["keys"]?.arrayValue ?? []).contains { $0["touches"] != nil } }) else {
            return steps
        }
        // A key written again at a moment one said it touches says it too.
        var out = touchesKept(steps)
        var bounces: [(step: Int, seconds: Double, off: String)] = []
        // The moments each step's keys said they touch something: a contact
        // planned after a hit is kept, and the bounce goes between.
        var contacts: [Int: [Double]] = [:]
        for at in out.indices where out[at].tool == "set_keys" {
            guard var object = out[at].arguments.objectValue, let keys = object["keys"]?.arrayValue,
                  keys.contains(where: { $0["touches"] != nil }) else { continue }
            let part = (object["layer"]?.stringValue).flatMap(partReference)?.part
            let isPosition = object["property"]?.stringValue == MotionProperty.position.rawValue
            var written: [AgentJSON] = []
            var moved: [(seconds: Double, was: AgentJSON, now: AgentJSON)] = []
            for key in keys {
                guard var one = key.objectValue else { written.append(key); continue }
                // Named as a layer is ("$1/lid") or as a part ("lid").
                let other = one["touches"]?.stringValue.map { partReference($0)?.part ?? $0 }
                one["touches"] = nil
                if isPosition, let part, let other, let seconds = one["seconds"]?.doubleValue,
                   let x = one["value"]?["x"]?.doubleValue, let y = one["value"]?["y"]?.doubleValue,
                   let lap = Lap(out), plain(other) != plain(part),
                   let shift = meeting(part, other, at: seconds, in: lap) ?? pushedOut(part, other, at: seconds, in: lap) {
                    let now: AgentJSON = ["x": .number(Double(rounded(CGFloat(x) + shift.dx))), "y": .number(Double(rounded(CGFloat(y) + shift.dy)))]
                    if let was = one["value"] { moved.append((seconds, was, now)) }
                    one["value"] = now
                }
                if isPosition, let part, let other, plain(other) != plain(part), let seconds = one["seconds"]?.doubleValue {
                    bounces.append((at, seconds, other))
                    contacts[at, default: []].append(seconds)
                }
                written.append(.object(one))
            }
            // What stays where it hit stays with it: the keys straight after
            // a hit at the same place go where the hit went.
            let order = written.indices.sorted { (written[$0]["seconds"]?.doubleValue ?? 0) < (written[$1]["seconds"]?.doubleValue ?? 0) }
            for move in moved {
                guard let from = order.firstIndex(where: { abs((written[$0]["seconds"]?.doubleValue ?? -1) - move.seconds) <= 0.0005 }) else { continue }
                for slot in order[(from + 1)...] {
                    guard written[slot]["value"] == move.was, keys[slot]["touches"] == nil, var one = written[slot].objectValue else { break }
                    one["value"] = move.now
                    written[slot] = .object(one)
                }
            }
            object["keys"] = .array(written)
            out[at] = AskStep(tool: out[at].tool, arguments: .object(object))
        }
        // Every hit placed first: what comes away is read against where the
        // others really are.
        // A run of keys touching the same part is one contact (it slides or
        // rests along it): it comes away after the last of them, and only then.
        let ends = bounces.filter { bounce in !bounces.contains(where: { later in
            later.step == bounce.step && plain(later.off) == plain(bounce.off) && later.seconds > bounce.seconds + 0.0005
                && AskMotionCheck.timed(out[bounce.step]).first(where: { $0.seconds > bounce.seconds + 0.0005 }).map { abs($0.seconds - later.seconds) <= 0.0005 } == true
        }) }
        func hitter(_ step: Int) -> String? { (out[step].arguments["layer"]?.stringValue).flatMap(partReference)?.part }
        // What was hit waits for what hit it to get clear, before the bounce
        // is aimed (it is aimed against where the struck part really goes)
        // and again after it (the bounce's own path is waited for too).
        for end in ends { if let part = hitter(end.step) { out = struckWaits(out, part: part, hit: end.seconds, off: end.off) } }
        for bounce in ends {
            let next = AskMotionCheck.timed(out[bounce.step]).first { $0.seconds > bounce.seconds + 0.0005 }?.seconds
            let planned = next.map { next in (contacts[bounce.step] ?? []).contains { abs($0 - next) <= 0.0005 } } ?? false
            // The next contact the model planned for it after this one, if any: where it lands.
            let landing = (contacts[bounce.step] ?? []).filter { $0 > bounce.seconds + 0.0005 }.min()
            out = bouncedAway(out, at: bounce.step, hit: bounce.seconds, off: bounce.off, keepingNext: planned, landing: landing)
        }
        for end in ends { if let part = hitter(end.step) { out = struckWaits(out, part: part, hit: end.seconds, off: end.off) } }
        // Met at speed and left at speed: a contact's first key is arrived
        // at accelerating, its last left decelerating.
        let starts = bounces.filter { bounce in !bounces.contains(where: { earlier in
            earlier.step == bounce.step && plain(earlier.off) == plain(bounce.off) && earlier.seconds < bounce.seconds - 0.0005
                && AskMotionCheck.timed(out[bounce.step]).last(where: { $0.seconds < bounce.seconds - 0.0005 }).map { abs($0.seconds - earlier.seconds) <= 0.0005 } == true
        }) }
        for start in starts { out = curved(out, step: start.step, leaving: AskMotionCheck.timed(out[start.step]).last { $0.seconds < start.seconds - 0.0005 }?.seconds, arriving: true) }
        for end in ends { out = curved(out, step: end.step, leaving: end.seconds, arriving: false) }
        return out
    }

    /// The least speed, as a share of a leg's mean, a hit is met or left at.
    static let hitSpeed = 0.5

    /// `steps` with the curve of the leg leaving the key at `seconds` in
    /// `step` made to arrive at speed (`arriving`, into a hit: Ease in) or
    /// leave at speed (out of a hit: Ease out), when the curve it has (none
    /// is Ease in out) is slower than `hitSpeed` of the leg's mean there.
    /// A curve that already meets it, Linear or the model's own Ease in, is
    /// kept. On 2026-11-11 the user's trash, keyed with no curves, stopped
    /// dead against the lid and set off again slowly: a touch and a slide,
    /// never seen as a bounce.
    static func curved(_ steps: [AskStep], step index: Int, leaving seconds: Double?, arriving: Bool) -> [AskStep] {
        guard let seconds, var object = steps[index].arguments.objectValue, var list = object["keys"]?.arrayValue,
              let slot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - seconds) <= 0.0005 }),
              var key = list[slot].objectValue else { return steps }
        let word = key["curve"]?.stringValue ?? AgentKeyCurve.easeInOut
        guard let curve = AgentKeyCurve.curve(named: word), curve != .steps(1) else { return steps }
        let edge = 0.02
        let speed = arriving ? (1 - curve.value(at: 1 - edge)) / edge : curve.value(at: edge) / edge
        guard speed < hitSpeed else { return steps }
        key["curve"] = .string(arriving ? EasingCurve.easeIn.title : EasingCurve.easeOut.title)
        list[slot] = .object(key)
        object["keys"] = .array(list)
        var out = steps
        out[index] = AskStep(tool: out[index].tool, arguments: .object(object))
        return out
    }

    // MARK: What is hit waits for what hit it

    /// The longest what was hit waits, and the least share of the time left
    /// in the lap its moves after the hit keep.
    static let longestWait = 0.5
    static let leastKeptShare = 0.5

    /// `steps` with the MOVING part `other`, hit by `part` at `seconds` (the
    /// last key of a contact), made to wait before its moves after the hit
    /// until `part`, seen, no longer passes through it for the rest of the
    /// lap, or until it goes out of sight: it stands where it was at the hit for the wait, and its moves
    /// after run in the time left before the lap ends (the lap's last key
    /// stays put). Tried every `hitStartStep`, the least wait that clears;
    /// none clears and the keys stay as planned. On 2026-11-11 the user's
    /// trash bounced off the lid and dropped into the can while the lid,
    /// closing on Ease out back from the hit, swept down through it: every
    /// look of the judge read "falls straight through the lid". A lid stays
    /// open until the trash is in, a door until whoever walked in is
    /// through. Keys and time only, any subject.
    static func struckWaits(_ steps: [AskStep], part: String, hit seconds: Double, off other: String) -> [AskStep] {
        guard let lap = Lap(steps), lap.isMover(other) || !lap.carriers(of: other).isEmpty, plain(part) != plain(other) else { return steps }
        let keyedEnds = steps.filter { $0.tool == "set_keys" }.flatMap { AskMotionCheck.timed($0).map(\.seconds) }
        guard let lapEnd = steps.last(where: { $0.tool == "set_timing" })?.arguments["seconds"]?.doubleValue ?? keyedEnds.max(),
              lapEnd - seconds > 0.1 else { return steps }
        // Its journey from the hit ends where it goes out of sight: coming
        // back unseen for the next lap is not part of it.
        var until = lapEnd
        var look = seconds + 0.02
        while look < lapEnd - 0.0005 {
            if lap.placed(part, at: look)?.seen == false { until = look; break }
            look += 0.02
        }
        func through(_ trial: [AskStep]) -> Bool {
            guard let lap = Lap(trial) else { return false }
            var moment = seconds + 0.02
            while moment < until - 0.0005 {
                if lap.placed(part, at: moment)?.seen ?? true, (lap.placed(other, at: moment)?.seen ?? true),
                   inkMeets(lap.ink(part, at: moment), lap.ink(other, at: moment), within: -passesThrough) { return true }
                moment += 0.02
            }
            return false
        }
        guard through(steps) else { return steps }
        let struck = Set(([other] + lap.carriers(of: other)).map(plain))
        let near = Double(PropertyKeys.nearMS) / 1000
        let room = lapEnd - seconds
        func waited(_ wait: Double) -> [AskStep]? {
            var trial = steps
            var changedAny = false
            for at in trial.indices where trial[at].tool == "set_keys" {
                guard let property = trial[at].arguments["property"]?.stringValue, moveProperties.contains(property),
                      let name = (trial[at].arguments["layer"]?.stringValue).flatMap(partReference)?.part, struck.contains(plain(name)),
                      var object = trial[at].arguments.objectValue, let list = object["keys"]?.arrayValue else { continue }
                let keys = AskMotionCheck.timed(trial[at])
                // Only what moves after the hit waits.
                guard let still = AskMotionCheck.played(of: trial[at], at: seconds),
                      keys.contains(where: { $0.seconds > seconds + 0.0005 && $0.seconds < lapEnd - 0.0005 && $0.value != still })
                        || (keys.last.map { $0.seconds > seconds + 0.0005 && $0.value != still } ?? false) else { continue }
                let share = (room - wait) / room
                var made: [AgentJSON] = []
                var standsAt: AgentJSON?
                for key in list {
                    guard var one = key.objectValue, let at = one["seconds"]?.doubleValue else { made.append(key); continue }
                    if abs(at - seconds) <= 0.0005 {
                        // The key at the hit: it stands for the wait, and its run starts after.
                        standsAt = key
                        var stand = one
                        stand["curve"] = nil
                        made.append(.object(stand))
                        continue
                    }
                    if at > seconds + 0.0005, at < lapEnd - 0.0005 {
                        one["seconds"] = .number(rounded(CGFloat(seconds + wait + (at - seconds) * share)))
                    }
                    made.append(.object(one))
                }
                // Where it stood at the hit, keyed when no key was there, and
                // again at the end of the wait with the run's own curve.
                var resume: [String: AgentJSON]
                if let standsAt, let object = standsAt.objectValue {
                    resume = object
                } else if keys.first(where: { $0.seconds > seconds + 0.0005 })?.value == still {
                    // Standing already at the hit: its next keys coming later is the wait.
                    made.sort { ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0) }
                    let times = made.compactMap { $0["seconds"]?.doubleValue }
                    guard zip(times, times.dropFirst()).allSatisfy({ $1 - $0 > near }) else { return nil }
                    object["keys"] = .array(made)
                    trial[at] = AskStep(tool: trial[at].tool, arguments: .object(object))
                    changedAny = true
                    continue
                } else {
                    let running = keys.last { $0.seconds < seconds }
                    made.append(.object(["seconds": .number(seconds), "value": still]))
                    resume = ["value": still]
                    if let curve = running?.curve { resume["curve"] = .string(curve) }
                }
                resume["seconds"] = .number(rounded(CGFloat(seconds + wait)))
                resume["touches"] = nil
                made.append(.object(resume))
                made.sort { ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0) }
                let times = made.compactMap { $0["seconds"]?.doubleValue }
                guard zip(times, times.dropFirst()).allSatisfy({ $1 - $0 > near }) else { return nil }
                object["keys"] = .array(made)
                trial[at] = AskStep(tool: trial[at].tool, arguments: .object(object))
                changedAny = true
            }
            return changedAny ? trial : nil
        }
        var wait = hitStartStep
        while wait <= min(longestWait, room * (1 - leastKeptShare)) + 0.0005 {
            if let trial = waited(wait), !through(trial) { return trial }
            wait += hitStartStep
        }
        return steps
    }

    // MARK: What bounces comes away

    /// The least a part goes coming away from what it hit, as a share of the
    /// drawing's width: less is not seen as a bounce at icon size.
    static let leastBounce: CGFloat = 0.125
    /// The gap, as a share of the drawing's width, a part that bounced has
    /// opened from what it hit by its next key. Touching ink, black on
    /// black, reads as one shape: on 2026-11-10 the trash came off the lid a
    /// little while the lid dipped after it, and nine looks of nine saw it
    /// stuck to the lid, never bouncing.
    static let bounceGap: CGFloat = 0.06

    /// `steps`, with the hit at `seconds` already placed, and the key after
    /// it moved when the part, from the hit on to the key after that, passes
    /// through the moving part it hit, or ends it still touching it
    /// (`bounceGap`): sent the way a ball comes off a wall,
    /// its way in mirrored about the face it struck, at least `leastBounce`
    /// of the drawing, and further, or nearer straight off that face, until
    /// nothing passes through. On 2026-11-10 the user's trash met the open
    /// lid from below and then moved back up into it as the lid dipped, so
    /// "bounces off the lid" read as sinking through it in every run; sent
    /// back with when, the model moved the key by one unit and no more.
    /// A part hit that stays still is left alone (going in behind its front
    /// is meant), and so is a part that comes away already, or stays where it
    /// hit, or a hit no try keeps clear of. Keys and time only, any subject.
    ///
    /// `landing`, the moment of the next contact the model planned after the
    /// hit, is where the part goes next: a bounce goes no further from there
    /// than the hit left it, when any way does (on 2026-11-11 the mirror off
    /// the lid sent the user's trash through the can's wall, and it hung
    /// outside the can before dropping in), trying straight towards it too.
    /// `keepingNext` is a key after the hit that says it touches something
    /// itself (the trash at the can's mouth after the lid): it is where the
    /// model sent the part next, so it stays, and the bounce is a key of its
    /// own halfway between. On 2026-11-11 re-aiming that key threw the
    /// user's trash down the outside of the can.
    static func bouncedAway(_ steps: [AskStep], at index: Int, hit seconds: Double, off other: String,
                            keepingNext: Bool = false, landing: Double? = nil) -> [AskStep] {
        guard steps.indices.contains(index), let part = (steps[index].arguments["layer"]?.stringValue).flatMap(partReference)?.part,
              let lap = Lap(steps), lap.isMover(other) || !lap.carriers(of: other).isEmpty else { return steps }
        func point(_ value: AgentJSON?) -> CGPoint? {
            guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let keys = AskMotionCheck.timed(steps[index])
        guard let k = keys.firstIndex(where: { abs($0.seconds - seconds) <= 0.0005 }), k + 1 < keys.count,
              let hitAt = point(keys[k].value), let nextAt = point(keys[k + 1].value), nextAt != hitAt else { return steps }
        // Kept, the next key is where the part goes after the bounce: halfway
        // there it comes off what it hit, on a key of its own.
        let width = PropertyKeys.nearMS
        let middle = Double(rounded(CGFloat((seconds + keys[k + 1].seconds) / 2)))
        if keepingNext, (middle - seconds) * 1000 <= Double(width) || (keys[k + 1].seconds - middle) * 1000 <= Double(width) { return steps }
        let after = keepingNext ? middle : keys[k + 1].seconds
        // With a landing planned, the bounce is judged on its own leg: what
        // comes after is the landing's (`tuckedIn`, `struckWaits`).
        let until = keepingNext ? keys[k + 1].seconds : landing != nil ? keys[k + 1].seconds
            : k + 2 < keys.count ? keys[k + 2].seconds : keys[k + 1].seconds
        func through(_ trial: [AskStep]) -> Bool {
            guard let lap = Lap(trial) else { return false }
            func seen(_ name: String, _ moment: Double) -> Bool {
                guard lap.isMover(name) || !lap.carriers(of: name).isEmpty else { return true }
                return lap.placed(name, at: moment)?.seen ?? true
            }
            var moment = seconds + 0.02
            while moment <= until + 0.0005 {
                if seen(part, moment), seen(other, moment),
                   inkMeets(lap.ink(part, at: moment), lap.ink(other, at: moment), within: -passesThrough) { return true }
                moment += 0.02
            }
            return false
        }
        // Seen apart from what it hit by the key after: a gap at icon size.
        func apart(_ trial: [AskStep]) -> Bool {
            guard let lap = Lap(trial) else { return true }
            return !inkMeets(lap.ink(part, at: after), lap.ink(other, at: after), within: bounceGap * (lap.art.viewBox?.width ?? 24))
        }
        guard through(steps) || !apart(steps) else { return steps }
        // The way in: from just before the hit, or from the key before.
        var before = point(AskMotionCheck.value(of: steps[index], at: seconds - 0.05)) ?? hitAt
        if before == hitAt, k > 0, let earlier = point(keys[k - 1].value) { before = earlier }
        let way = CGVector(dx: hitAt.x - before.x, dy: hitAt.y - before.y)
        // The face struck: from the nearest ink of what was hit to the middle of the part.
        let mine = lap.ink(part, at: seconds).flatMap { $0 }, theirs = lap.ink(other, at: seconds)
        guard !mine.isEmpty, !theirs.isEmpty else { return steps }
        let centre = CGPoint(x: mine.map(\.x).reduce(0, +) / CGFloat(mine.count), y: mine.map(\.y).reduce(0, +) / CGFloat(mine.count))
        guard let struck = theirs.map({ nearest(to: centre, on: $0) })
                .min(by: { hypot($0.x - centre.x, $0.y - centre.y) < hypot($1.x - centre.x, $1.y - centre.y) }) else { return steps }
        func unit(_ v: CGVector) -> CGVector? {
            let length = hypot(v.dx, v.dy)
            return length > 1e-6 ? CGVector(dx: v.dx / length, dy: v.dy / length) : nil
        }
        guard let face = unit(CGVector(dx: centre.x - struck.x, dy: centre.y - struck.y)) ?? unit(CGVector(dx: -way.dx, dy: -way.dy)) else { return steps }
        let dot = way.dx * face.dx + way.dy * face.dy
        let mirrored = dot < 0 ? unit(CGVector(dx: way.dx - 2 * dot * face.dx, dy: way.dy - 2 * dot * face.dy)) ?? face : face
        let side = lap.art.viewBox?.width ?? 24
        let least = keepingNext ? leastBounce * side : max(hypot(nextAt.x - hitAt.x, nextAt.y - hitAt.y), leastBounce * side)
        // Where it goes after the bounce: a bounce never takes it further
        // from there than the hit left it. On 2026-11-11 the mirror off the
        // lid sent the user's trash through the can's wall, and it hung
        // outside the can before dropping in.
        let goal = keepingNext ? nextAt : landing.flatMap { at in keys.first { abs($0.seconds - at) <= 0.0005 } }.flatMap { point($0.value) }
        var ways = [mirrored, unit(CGVector(dx: mirrored.dx + face.dx, dy: mirrored.dy + face.dy)) ?? face, face]
        if let goal, let towards = unit(CGVector(dx: goal.x - hitAt.x, dy: goal.y - hitAt.y)) {
            ways += [unit(CGVector(dx: face.dx + towards.dx, dy: face.dy + towards.dy)) ?? towards, towards]
        }
        guard var object = steps[index].arguments.objectValue, let list = object["keys"]?.arrayValue,
              let slot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - keys[k + 1].seconds) <= 0.0005 }),
              var key = keepingNext ? ["seconds": .number(middle)] : list[slot].objectValue else { return steps }
        func nearer(_ at: CGPoint) -> Bool {
            guard let goal else { return true }
            return hypot(at.x - goal.x, at.y - goal.y) <= hypot(hitAt.x - goal.x, hitAt.y - goal.y) + 0.0005
        }
        for towardsOnly in [true, false] {
            for share: CGFloat in [1, 1.5, 2, 2.5, 3] {
                for direction in ways {
                    let at = CGPoint(x: hitAt.x + direction.dx * least * share, y: hitAt.y + direction.dy * least * share)
                    guard !towardsOnly || nearer(at) else { continue }
                    key["value"] = ["x": .number(Double(rounded(at.x))), "y": .number(Double(rounded(at.y)))]
                    var changed = list
                    if keepingNext { changed.insert(.object(key), at: slot) } else { changed[slot] = .object(key) }
                    object["keys"] = .array(changed)
                    var trial = steps
                    trial[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
                    if !through(trial), apart(trial) { return trial }
                }
            }
            if goal == nil { break }
        }
        return steps
    }

    /// How far `part` moves at `seconds` to just meet `other`, or nil when
    /// they meet already or either cannot be found.
    /// Read off the ink of both (`Lap.ink`), never their boxes.
    static func meeting(_ part: String, _ other: String, at seconds: Double, in lap: Lap) -> CGVector? {
        let mine = lap.ink(part, at: seconds), theirs = lap.ink(other, at: seconds)
        guard !mine.isEmpty, !theirs.isEmpty, !inkMeets(mine, theirs) else { return nil }
        let all = mine.flatMap { $0 }
        let middle = CGPoint(x: all.map(\.x).reduce(0, +) / CGFloat(all.count), y: all.map(\.y).reduce(0, +) / CGFloat(all.count))
        guard let target = theirs.map({ nearest(to: middle, on: $0) })
                .min(by: { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }) else { return nil }
        let way = CGVector(dx: target.x - middle.x, dy: target.y - middle.y)
        func shifted(_ share: CGFloat) -> [[CGPoint]] {
            mine.map { hull in hull.map { CGPoint(x: $0.x + way.dx * share, y: $0.y + way.dy * share) } }
        }
        guard inkMeets(shifted(1), theirs, within: 0) else { return nil }
        // The least share of the way at which the ink really meets, so the
        // hit reads as one however the numbers round.
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if inkMeets(shifted(mid), theirs, within: 0) { high = mid } else { low = mid }
        }
        return CGVector(dx: way.dx * high, dy: way.dy * high)
    }

    /// How far `part` moves at `seconds` to come out of a MOVING `other` it
    /// is buried in until the two just meet, the shortest way out across one
    /// of `other`'s faces; nil when it is not in deeper than a touch, when
    /// `other` stays still (going in behind its front is meant), or when no
    /// way out is found. On 2026-11-10 the model keyed the trash at 0.95 s
    /// as touching the lid, two units inside it, and the trash was drawn
    /// through the lid from 0.84 to 1.06 s: placing only ever pulled a part
    /// towards what it touches.
    static func pushedOut(_ part: String, _ other: String, at seconds: Double, in lap: Lap) -> CGVector? {
        guard lap.isMover(other) || !lap.carriers(of: other).isEmpty else { return nil }
        let mine = lap.ink(part, at: seconds), theirs = lap.ink(other, at: seconds)
        guard !mine.isEmpty, !theirs.isEmpty, inkMeets(mine, theirs, within: -passesThrough) else { return nil }
        func deep(_ way: CGVector, _ share: CGFloat) -> Bool {
            inkMeets(mine.map { hull in hull.map { CGPoint(x: $0.x + way.dx * share, y: $0.y + way.dy * share) } }, theirs, within: -0.05)
        }
        let reach = (lap.art.viewBox?.width ?? 24) / 2
        var best: CGVector?
        for hull in theirs {
            for (a, b) in zip(hull, hull.dropFirst() + hull.prefix(1)) {
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 1e-6 else { continue }
                for sign: CGFloat in [1, -1] {
                    let way = CGVector(dx: sign * (b.y - a.y) / length, dy: sign * -(b.x - a.x) / length)
                    guard !deep(way, reach) else { continue }
                    var low: CGFloat = 0, high = reach
                    for _ in 0..<24 {
                        let mid = (low + high) / 2
                        if deep(way, mid) { low = mid } else { high = mid }
                    }
                    if best.map({ hypot($0.dx, $0.dy) > high }) ?? true { best = CGVector(dx: way.dx * high, dy: way.dy * high) }
                }
            }
        }
        return best
    }

    /// Whether any piece of ink of one meets any of the other's.
    static func inkMeets(_ a: [[CGPoint]], _ b: [[CGPoint]], within slack: CGFloat = edgeTouch) -> Bool {
        a.contains { one in b.contains { meet(one, $0, within: slack) } }
    }

    /// The convex hull of `points`, going round one way (monotone chain).
    static func hull(_ points: [CGPoint]) -> [CGPoint] {
        func snapped(_ point: CGPoint) -> CGPoint {
            let x: CGFloat = (point.x * 1000).rounded() / 1000
            let y: CGFloat = (point.y * 1000).rounded() / 1000
            return CGPoint(x: x, y: y)
        }
        func before(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x != b.x ? a.x < b.x : a.y < b.y }
        var sorted: [CGPoint] = []
        for point in points.map(snapped).sorted(by: before) where sorted.last != point { sorted.append(point) }
        guard sorted.count > 2 else { return sorted }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        for point in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// The point of the convex outline `quad` nearest `point`, edges included.
    static func nearest(to point: CGPoint, on quad: [CGPoint]) -> CGPoint {
        if inside(point, quad) { return point }
        var best = quad.first ?? point
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (a, b) in zip(quad, quad.dropFirst() + quad.prefix(1)) {
            let (dx, dy) = (b.x - a.x, b.y - a.y)
            let length = dx * dx + dy * dy
            let t = length > 1e-9 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
            let on = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            let distance = hypot(on.x - point.x, on.y - point.y)
            if distance < bestDistance { bestDistance = distance; best = on }
        }
        return best
    }
}
