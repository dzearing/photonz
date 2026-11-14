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

        /// Whether all of `name`'s ink lies inside the outline of a closed
        /// shape `other` draws (a rectangle, a circle, a closed path), as the
        /// keys have both at `seconds`: it has gone in, not through. On
        /// 2026-11-12 the eval's letter, keyed down into the envelope and said
        /// to touch it, was pushed out of the top because the envelope flies
        /// off later in the lap. Geometry only.
        func within(_ name: String, closedOf other: String, at seconds: Double) -> Bool {
            let mine = ink(name, at: seconds).flatMap { $0 }
            guard !mine.isEmpty else { return false }
            return art.parts.filter { Self.holds($0, other) }.contains { part in
                switch part.shape {
                case .path(let outline) where !outline.closed: return false
                default: break
                }
                let chain = ([part.name].compactMap { $0 } + part.groups.reversed()).compactMap { group in
                    movers.first { plain($0) == plain(group) }
                }
                var points = Self.inkPoints(part)
                for mover in chain { points = moved(points, by: mover, at: seconds) }
                let outline = AskMotion.hull(points)
                return outline.count > 2 && mine.allSatisfy { AskMotion.inside($0, outline) }
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

    /// `touchesPlaced` with the hits placed, bounced off and waited for on
    /// the drawing as it will be drawn in a frame grown from `from` to
    /// `viewBox` across: an icon's lines keep their weight on the final
    /// grid as everything else shrinks, so parts placed to meet at the
    /// written width end deep in each other (the eval's trash of 2026-11-14,
    /// 0.84 into the lid's bar at the hit). Only the keys change: the
    /// drawing comes back as written.
    public static func touchesPlaced(_ steps: [AskStep], drawn: (viewBox: CGFloat, from: CGFloat)?) -> [AskStep] {
        guard let drawn, let index = steps.firstIndex(where: { $0.tool == "add_drawing" }) else { return touchesPlaced(steps) }
        var placed = touchesPlaced(linesAsDrawn(steps, on: drawn.viewBox, from: drawn.from))
        guard placed.indices.contains(index), placed[index].tool == "add_drawing" else { return touchesPlaced(steps) }
        placed[index] = steps[index]
        return placed
    }

    /// The steps with every position key that says what it `touches` moved,
    /// straight towards that part, just far enough that the two meet at that
    /// moment, as the keys move them both; and `touches` taken off every key,
    /// moved or not. A key already touching, or naming a part the drawing
    /// does not have, keeps its value.
    ///
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
            // Or, with none, the key it is heading for as it goes out of sight.
            let landing = (contacts[bounce.step] ?? []).filter { $0 > bounce.seconds + 0.0005 }.min()
                ?? hitter(bounce.step).flatMap { goneAt($0, keys: AskMotionCheck.timed(out[bounce.step]), in: out) }
                    .flatMap { $0 > bounce.seconds + 0.0005 ? $0 : nil }
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
        for end in ends { out = carriesOn(out, step: end.step, hit: end.seconds) }
        return out
    }

    /// The most two legs either side of a key may turn, as a cosine, and
    /// still be one fall: 45 degrees.
    static let carriesOnTurn: CGFloat = 0.7

    /// `steps` with the key after a hit, where the part goes on the same
    /// way it came off (turning less than 45 degrees), passed through at
    /// speed: the hit's key and that key run evenly (Linear), instead of
    /// slowing to a stop between them. A stop is right at the top of a
    /// bounce that comes back down, never in the middle of a fall: on
    /// 2026-11-12 the user's trash came off the lid, slowed to a stop in mid
    /// air over the can's mouth and then dropped in. Keys and time only.
    static func carriesOn(_ steps: [AskStep], step index: Int, hit seconds: Double) -> [AskStep] {
        func point(_ value: AgentJSON?) -> CGPoint? {
            guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let keys = AskMotionCheck.timed(steps[index])
        guard let k = keys.firstIndex(where: { abs($0.seconds - seconds) <= 0.0005 }), k + 2 < keys.count,
              let a = point(keys[k].value), let b = point(keys[k + 1].value), let c = point(keys[k + 2].value),
              var object = steps[index].arguments.objectValue, var list = object["keys"]?.arrayValue else { return steps }
        let first = CGVector(dx: b.x - a.x, dy: b.y - a.y), second = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let lengths = hypot(first.dx, first.dy) * hypot(second.dx, second.dy)
        guard lengths > 1e-6, (first.dx * second.dx + first.dy * second.dy) / lengths >= carriesOnTurn else { return steps }
        for moment in [keys[k].seconds, keys[k + 1].seconds] {
            guard let slot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - moment) <= 0.0005 }),
                  var key = list[slot].objectValue else { return steps }
            key["curve"] = .string(EasingCurve.linear.title)
            list[slot] = .object(key)
        }
        object["keys"] = .array(list)
        var out = steps
        out[index] = AskStep(tool: out[index].tool, arguments: .object(object))
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
        func through(_ trial: [AskStep], walled: Bool = false) -> Bool {
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
    /// The most a bounce's way out may go along its way in, as the cosine of
    /// the angle between them: 0 is a right angle or more.
    static let bounceTurns: CGFloat = 0

    /// Every stroke of what `name` draws on its own, as ink: a line as thick
    /// as its stroke, segment by segment, so an open outline (a can's U)
    /// is its walls and not the space they hold. Where it rests; still parts only.
    static func lines(of name: String, in lap: Lap) -> [[CGPoint]] {
        lap.art.parts.filter { Lap.holds($0, name) }.flatMap(lines(of:))
    }

    /// The lines of the still parts `names` that something moving can run
    /// into, stroke by stroke (`lines`), leaving out a part drawn wholly
    /// inside another one's outline: a rib on a can's front, a stripe on a
    /// box. That is detail on a face, which a part going in passes in front
    /// of or behind; counted as a wall, nothing could ever fall into the
    /// can (2026-11-12). Points only, any subject.
    static func walls(of names: [String], in lap: Lap) -> [[CGPoint]] {
        let parts = lap.art.parts.filter { part in names.contains { Lap.holds(part, $0) } }
        func points(_ part: SVGArtwork.Part) -> [CGPoint] {
            guard case .path(let outline) = part.shape else { return Lap.inkPoints(part) }
            return outline.rings.flatMap { $0.map(\.point) }
        }
        let outlines = parts.indices.map { hull(points(parts[$0])) }
        return parts.indices.filter { index in
            let mine = points(parts[index])
            return !outlines.indices.contains { other in
                other != index && outlines[other].count >= 3 && !mine.isEmpty
                    && mine.allSatisfy { inside($0, outlines[other]) }
            }
        }.flatMap { lines(of: parts[$0]) }
    }

    /// Every stroke of `part` on its own, as ink (see `lines(of:in:)`).
    static func lines(of part: SVGArtwork.Part) -> [[CGPoint]] {
        [part].flatMap { part -> [[CGPoint]] in
            guard case .path(let outline) = part.shape else { return [hull(Lap.inkPoints(part))] }
            let half = max(part.strokeWidth / 2, 0.01)
            return outline.rings.flatMap { ring -> [[CGPoint]] in
                let points = ring.map(\.point) + (outline.closed && ring.count > 2 ? [ring[0].point] : [])
                return zip(points, points.dropFirst()).map { a, b in
                    hull([a, b].flatMap { point in
                        (0..<8).map { step in
                            let angle = Double(step) * .pi / 4
                            return CGPoint(x: point.x + half * cos(angle), y: point.y + half * sin(angle))
                        }
                    })
                }
            }
        }
    }

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
        // The lines of what stays still, each stroke on its own: a bounce
        // goes through none of them (an open can's wall, 2026-11-11).
        // ...on the way off it and the first of the way to where it goes
        // next: the last of that is going in, past the rim, where a part that
        // only just fits brushes the walls whatever the bounce did.
        let wallsUntil = k + 2 < keys.count && !keepingNext ? after + (keys[k + 2].seconds - after) * 0.5 : after
        let walls = walls(of: lap.still.map(\.name).filter { plain($0) != plain(other) && plain($0) != plain(part) }, in: lap)
            .filter { !inkMeets(lap.ink(part, at: seconds), [$0], within: -passesThrough) }
        func through(_ trial: [AskStep], walled: Bool = false) -> Bool {
            guard let lap = Lap(trial) else { return false }
            func seen(_ name: String, _ moment: Double) -> Bool {
                guard lap.isMover(name) || !lap.carriers(of: name).isEmpty else { return true }
                return lap.placed(name, at: moment)?.seen ?? true
            }
            var moment = seconds + 0.02
            while moment <= wallsUntil + 0.0005 || moment <= until + 0.0005 {
                if seen(part, moment) {
                    let mine = lap.ink(part, at: moment)
                    if moment <= until + 0.0005, seen(other, moment), inkMeets(mine, lap.ink(other, at: moment), within: -passesThrough) { return true }
                    if walled, moment <= wallsUntil + 0.0005, inkMeets(mine, walls, within: -passesThrough) { return true }
                }
                moment += 0.02
            }
            return false
        }
        // Seen apart from what it hit by the key after: a gap at icon size.
        func apart(_ trial: [AskStep]) -> Bool {
            guard let lap = Lap(trial) else { return true }
            return !inkMeets(lap.ink(part, at: after), lap.ink(other, at: after), within: bounceGap * (lap.art.viewBox?.width ?? 24))
        }
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
        // Back off it the way it came, or between that and the face.
        if let back = unit(CGVector(dx: -way.dx, dy: -way.dy)) {
            ways += [unit(CGVector(dx: back.dx + face.dx, dy: back.dy + face.dy)) ?? back, back]
        }
        guard var object = steps[index].arguments.objectValue, let list = object["keys"]?.arrayValue,
              let slot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - keys[k + 1].seconds) <= 0.0005 }),
              var key = keepingNext ? ["seconds": .number(middle)] : list[slot].objectValue else { return steps }
        func nearer(_ at: CGPoint) -> Bool {
            guard let goal else { return true }
            return hypot(at.x - goal.x, at.y - goal.y) <= hypot(hitAt.x - goal.x, hitAt.y - goal.y) + 0.0005
        }
        // A bounce turns: it leaves at `bounceTurns` or more to the way it
        // came, or the eye reads a part going on past what it grazed. On
        // 2026-11-11 the user's trash met the open lid's underside at a slant,
        // its mirror went on down the lid, and every look and judge read it
        // as sliding off, "no visible bounce".
        func turns(_ direction: CGVector) -> Bool {
            let length = hypot(direction.dx, direction.dy) * hypot(way.dx, way.dy)
            return length > 1e-6 && (direction.dx * way.dx + direction.dy * way.dy) / length <= bounceTurns
        }
        let leaves = CGVector(dx: (point(AskMotionCheck.value(of: steps[index], at: after))?.x ?? nextAt.x) - hitAt.x,
                              dy: (point(AskMotionCheck.value(of: steps[index], at: after))?.y ?? nextAt.y) - hitAt.y)
        let clean = !through(steps) && apart(steps)
        guard !clean || !turns(leaves) else { return steps }
        // A turn clear of the walls first; where there is none (a part that
        // only just fits the mouth it goes into: the trash 6 across with its
        // line in a mouth 6 across, 2026-11-11), as before: towards where it
        // lands, clear of what it hit. A turn into a wall reads as stuck in it.
        let passes: [(walled: Bool, towardsOnly: Bool, turnedOnly: Bool)] =
            [(true, true, true), (true, false, true), (false, true, false), (false, false, false)]
        for (walled, towardsOnly, turnedOnly) in passes {
            // No turn clear of the walls from where it hit: met further along
            // the face, where its own mirror turns (`aimedHit`).
            if walled, !towardsOnly, !clean, let goal,
               let trial = aimedHit(steps, at: index, key: k, hit: seconds, off: other, face: face, goal: goal,
                                    least: least, bounceAt: after, keepingNext: keepingNext,
                                    clear: { !through($0, walled: true) && apart($0) }) { return trial }
            if !towardsOnly, goal == nil, walled { continue }
            // Already clear and apart, only not turning: a turn clear of the
            // walls, or the model's own way off.
            if clean, !walled { break }
            for share: CGFloat in [1, 1.5, 2, 2.5, 3] {
                for direction in ways {
                    let at = CGPoint(x: hitAt.x + direction.dx * least * share, y: hitAt.y + direction.dy * least * share)
                    guard !towardsOnly || nearer(at), !turnedOnly || turns(direction) else { continue }
                    key["value"] = ["x": .number(Double(rounded(at.x))), "y": .number(Double(rounded(at.y)))]
                    var changed = list
                    if keepingNext { changed.insert(.object(key), at: slot) } else { changed[slot] = .object(key) }
                    object["keys"] = .array(changed)
                    var trial = steps
                    trial[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
                    if !through(trial, walled: walled), apart(trial) { return trial }
                }
            }
        }
        return steps
    }

    /// How far along the face it struck a hit may be moved to bounce clear,
    /// as a share of the drawing.
    static let aimedReach: CGFloat = 0.25

    /// The most a bounce met where its mirror turns (`aimedHit`) may go
    /// along its way in, as a cosine: 60 degrees of turn or more. Its own
    /// mirror, at speed and off a face it leaves, reads as a ricochet; a
    /// right angle (`bounceTurns`) cannot be had off a lid open 40 degrees
    /// without running into the can's wall.
    static let aimedTurn: CGFloat = 0.5

    /// `steps` with the hit at key `key` of step `index` met where it was
    /// planned or further along the face of `other` it struck, where the way
    /// in from the key before meets that face steeply enough that its mirror
    /// off it turns `aimedTurn` or more, goes towards `goal` (where it lands), and passes
    /// through nothing (`clear`), with the bounce a key of its own at
    /// `bounceAt`: a ball coming off a wall the way a ball does. The nearest
    /// such place along the face wins; nil when there is none within
    /// `aimedReach`, or the way in to it passes through anything.
    ///
    /// On 2026-11-12 the user's trash met the underside of a lid open 40
    /// degrees on a way in nearly along it, about 25 degrees: every bounce
    /// that turned ran into the can's wall, so it went back the way it came,
    /// stopped in mid-air over the right wall and dropped across it, and no
    /// look saw a bounce. Its own mirror off the lid, 66 degrees, drops it
    /// straight into the can's mouth. Ink, keys and time only, any subject.
    static func aimedHit(_ steps: [AskStep], at index: Int, key k: Int, hit seconds: Double, off other: String,
                         face planned: CGVector, goal: CGPoint, least: CGFloat, bounceAt: Double, keepingNext: Bool,
                         clear: ([AskStep]) -> Bool) -> [AskStep]? {
        guard k > 0, let part = (steps[index].arguments["layer"]?.stringValue).flatMap(partReference)?.part,
              var object = steps[index].arguments.objectValue, let list = object["keys"]?.arrayValue,
              let lap = Lap(steps) else { return nil }
        func point(_ value: AgentJSON?) -> CGPoint? {
            guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        let keys = AskMotionCheck.timed(steps[index])
        guard k + 1 < keys.count, let from = point(keys[k - 1].value), let hitAt = point(keys[k].value),
              let hitSlot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - seconds) <= 0.0005 }),
              let nextSlot = list.firstIndex(where: { abs(($0["seconds"]?.doubleValue ?? -1) - keys[k + 1].seconds) <= 0.0005 }),
              var hitKey = list[hitSlot].objectValue else { return nil }
        let setOff = keys[k - 1].seconds
        let side = lap.art.viewBox?.width ?? 24
        func unit(_ v: CGVector) -> CGVector? {
            let length = hypot(v.dx, v.dy)
            return length > 1e-6 ? CGVector(dx: v.dx / length, dy: v.dy / length) : nil
        }
        func value(_ at: CGPoint) -> AgentJSON { ["x": .number(Double(rounded(at.x))), "y": .number(Double(rounded(at.y)))] }
        func with(hit at: CGPoint, bounce: CGPoint? = nil) -> [AskStep] {
            var changed = list
            hitKey["value"] = value(at)
            changed[hitSlot] = .object(hitKey)
            if let bounce {
                if keepingNext {
                    changed.insert(.object(["seconds": .number(bounceAt), "value": value(bounce)]), at: nextSlot)
                } else if var next = list[nextSlot].objectValue {
                    next["value"] = value(bounce)
                    changed[nextSlot] = .object(next)
                }
            }
            var trial = steps
            var arguments = object
            arguments["keys"] = .array(changed)
            trial[index] = AskStep(tool: steps[index].tool, arguments: .object(arguments))
            return trial
        }
        // Just touching what it hits, moved along `planned` (out of it) or
        // straight to it.
        func touching(_ at: CGPoint) -> CGPoint? {
            var at = at
            for _ in 0..<24 {
                guard let lap = Lap(with(hit: at)), inkMeets(lap.ink(part, at: seconds), lap.ink(other, at: seconds), within: 0) else { break }
                at = CGPoint(x: at.x + planned.dx * 0.25, y: at.y + planned.dy * 0.25)
            }
            guard let lap = Lap(with(hit: at)) else { return nil }
            if let move = meeting(part, other, at: seconds, in: lap) { at = CGPoint(x: at.x + move.dx, y: at.y + move.dy) }
            return inkMeets(lap.ink(part, at: seconds), lap.ink(other, at: seconds)) || meeting(part, other, at: seconds, in: lap) != nil ? at : nil
        }
        // What stays still, stroke by stroke, that it does not already meet as it sets off.
        let walls = walls(of: lap.still.map(\.name).filter { plain($0) != plain(other) && plain($0) != plain(part) }, in: lap)
            .filter { !inkMeets(lap.ink(part, at: setOff), [$0], within: -passesThrough) }
        let tangent = CGVector(dx: -planned.dy, dy: planned.dx)
        let offsets: [CGFloat] = [0] + stride(from: CGFloat(0.5), through: aimedReach * side, by: 0.5).flatMap { [$0, -$0] }
        for offset in offsets {
            guard let at = touching(CGPoint(x: hitAt.x + tangent.dx * offset, y: hitAt.y + tangent.dy * offset)),
                  let met = Lap(with(hit: at)) else { continue }
            // The face where it meets it now, and the way it comes in.
            let mine = met.ink(part, at: seconds).flatMap { $0 }, theirs = met.ink(other, at: seconds)
            guard !mine.isEmpty else { continue }
            let centre = CGPoint(x: mine.map(\.x).reduce(0, +) / CGFloat(mine.count), y: mine.map(\.y).reduce(0, +) / CGFloat(mine.count))
            guard let struck = theirs.map({ nearest(to: centre, on: $0) })
                    .min(by: { hypot($0.x - centre.x, $0.y - centre.y) < hypot($1.x - centre.x, $1.y - centre.y) }),
                  let face = unit(CGVector(dx: centre.x - struck.x, dy: centre.y - struck.y)) else { continue }
            let way = CGVector(dx: at.x - from.x, dy: at.y - from.y)
            let dot = way.dx * face.dx + way.dy * face.dy
            guard dot < 0, let mirror = unit(CGVector(dx: way.dx - 2 * dot * face.dx, dy: way.dy - 2 * dot * face.dy)),
                  mirror.dx * way.dx + mirror.dy * way.dy <= aimedTurn * hypot(way.dx, way.dy) else { continue }
            // The way in passes through nothing seen.
            var moment = setOff + 0.02, blocked = false
            while moment < seconds - 0.01, !blocked {
                if met.placed(part, at: moment)?.seen ?? true {
                    let ink = met.ink(part, at: moment)
                    blocked = inkMeets(ink, walls, within: -passesThrough)
                        || inkMeets(ink, met.ink(other, at: moment), within: -passesThrough)
                }
                moment += 0.02
            }
            guard !blocked else { continue }
            for share: CGFloat in [1, 1.5, 2, 2.5, 3] {
                let bounce = CGPoint(x: at.x + mirror.dx * least * share, y: at.y + mirror.dy * least * share)
                guard hypot(bounce.x - goal.x, bounce.y - goal.y) <= hypot(at.x - goal.x, at.y - goal.y) + 0.0005 else { continue }
                let trial = with(hit: at, bounce: bounce)
                if clear(trial) { return trial }
            }
        }
        return nil
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
        guard !mine.isEmpty, !theirs.isEmpty, inkMeets(mine, theirs, within: -passesThrough),
              !lap.within(part, closedOf: other, at: seconds) else { return nil }
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
