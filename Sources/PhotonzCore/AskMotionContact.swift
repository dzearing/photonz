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

        /// A value at `seconds`: straight between keys, standing on a Hold.
        func value(_ name: String, _ property: MotionProperty, at seconds: Double) -> AgentJSON? {
            guard let step = keyed.last(where: { one in
                (one.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) == plain(name) } ?? false
                    && one.arguments["property"]?.stringValue == property.rawValue
            }) else { return nil }
            return AskMotionCheck.value(of: step, at: seconds)
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

    /// The steps with every position key that says what it `touches` moved,
    /// straight towards that part, just far enough that the two meet at that
    /// moment, as the keys move them both; and `touches` taken off every key,
    /// moved or not. A key already touching, or naming a part the drawing
    /// does not have, keeps its value.
    public static func touchesPlaced(_ steps: [AskStep]) -> [AskStep] {
        guard steps.contains(where: { step in (step.arguments["keys"]?.arrayValue ?? []).contains { $0["touches"] != nil } }) else {
            return steps
        }
        var out = steps
        for at in out.indices where out[at].tool == "set_keys" {
            guard var object = out[at].arguments.objectValue, let keys = object["keys"]?.arrayValue,
                  keys.contains(where: { $0["touches"] != nil }) else { continue }
            let part = (object["layer"]?.stringValue).flatMap(partReference)?.part
            let isPosition = object["property"]?.stringValue == MotionProperty.position.rawValue
            var written: [AgentJSON] = []
            for key in keys {
                guard var one = key.objectValue else { written.append(key); continue }
                // Named as a layer is ("$1/lid") or as a part ("lid").
                let other = one["touches"]?.stringValue.map { partReference($0)?.part ?? $0 }
                one["touches"] = nil
                if isPosition, let part, let other, let seconds = one["seconds"]?.doubleValue,
                   let x = one["value"]?["x"]?.doubleValue, let y = one["value"]?["y"]?.doubleValue,
                   let lap = Lap(out), plain(other) != plain(part),
                   let shift = meeting(part, other, at: seconds, in: lap) {
                    one["value"] = ["x": .number(Double(rounded(CGFloat(x) + shift.dx))), "y": .number(Double(rounded(CGFloat(y) + shift.dy)))]
                }
                written.append(.object(one))
            }
            object["keys"] = .array(written)
            out[at] = AskStep(tool: out[at].tool, arguments: .object(object))
        }
        return out
    }

    /// How far `part` moves at `seconds` to just meet `other`, or nil when
    /// they meet already or either cannot be found.
    static func meeting(_ part: String, _ other: String, at seconds: Double, in lap: Lap) -> CGVector? {
        guard lap.art.parts.contains(where: { Lap.holds($0, other) }),
              let mine = lap.outline(part, at: seconds), let theirs = lap.outline(other, at: seconds),
              !meet(mine, theirs) else { return nil }
        let middle = CGPoint(x: mine.map(\.x).reduce(0, +) / CGFloat(mine.count), y: mine.map(\.y).reduce(0, +) / CGFloat(mine.count))
        let target = nearest(to: middle, on: theirs)
        let way = CGVector(dx: target.x - middle.x, dy: target.y - middle.y)
        func shifted(_ share: CGFloat) -> [CGPoint] { mine.map { CGPoint(x: $0.x + way.dx * share, y: $0.y + way.dy * share) } }
        guard meet(shifted(1), theirs) else { return nil }
        // The least share of the way that meets.
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if meet(shifted(mid), theirs) { high = mid } else { low = mid }
        }
        return CGVector(dx: way.dx * high, dy: way.dy * high)
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
