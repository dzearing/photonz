import CoreGraphics
import Foundation

// Ask animates what it makes (`docs/design/ask.md`, "A moving icon"). The model
// draws every part a motion needs and keys them in the same plan, so one
// request is one undo step. A plan runs only once it is complete, so nothing it
// draws has a layer id yet, and the model knows its own drawing as ids on a 24
// grid, not as boxes in points. So it says `$1/lid` and how far on that grid,
// and this turns that into the keys a person sets, as the step runs.
//
// Everything here is about keys. The sense of motion is the model's own, taught
// by general principles: nothing knows what any icon is of, and nothing holds a
// motion for a subject.

public enum AskMotion {

    /// The words for a file that moves, which has no other word for an icon in it.
    static let fileWords: Set<String> = ["svg", "svgs"]
    /// The words that ask for something drawn to move. Narrower than what
    /// reaches the key tools: "a motion sensor icon" is a still of a sensor.
    static let drawingWords: Set<String> = ["animate", "animated", "animating", "animation", "looping"]

    /// Whether `request` asks for a moving icon to be drawn: a request about
    /// motion that names an icon or an SVG. "Animate the icon" is about the one
    /// here, which `AskConversation.takesIconRoute` settles.
    public static func drawsMotion(_ request: String) -> Bool {
        let words = AgentDrawingWords.words(request)
        return !drawingWords.isDisjoint(with: words) && (AskIcon.asked(in: request) || !fileWords.isDisjoint(with: words))
            && !AskIcon.meansTheOneHere(request)
    }

    /// All a moving icon needs. The rest of Ask's tools are 13,000 tokens read
    /// before every plan, about 100 of a request's 190 seconds (the eval,
    /// 2026-11-06), and one balloon ran out of its five minutes.
    public static let tools = ["add_drawing", "set_timing", "set_keys"]

    // MARK: What the model is told

    /// In place of the icon rule that shows an action by breaking the outline:
    /// a moving icon shows it happening.
    static let drawRules = """
        - This icon moves. Plan it in this order: add_drawing once, set_timing once, then set_keys once for each \
        value of each part that moves.
        - Draw the object whole and at rest, as its first moment shows it, and every part the motion needs: \
        anything that only appears part way through (pieces, marks, waves) is drawn too, where it starts. Never \
        opacity="0" in the svg: a key at 0 seconds hides it. Parts that move together share a <g id="what-they-are">, \
        with everything attached to them and nothing drawn twice; a part that moves alone has an id of its own.
        - Name a part as layer "$1/its-id". position is how far it has moved from where you drew it, x and y on the 24 \
        grid: x 0 y 0 is where it was drawn, y grows downward. scale is a percent of its size, about its own middle. \
        rotation is degrees clockwise, about pivot: x and y on the 24 grid, the hinge, the mount or the centre of \
        the circle it turns on. opacity is 0 to 100. trimEnd is how much of a line is drawn, 0 to 100, for a line \
        drawing itself. color is #RRGGBB.
        \(principles)
        """

    /// The most a design may write.
    public static let mostDesignTokens = 500

    /// What the model is asked before it draws. Straight off, it drew what it
    /// knew at rest and then found it could not move it: a flap with its hinge
    /// at the point, a swap of two pictures for a pop (the eval, 2026-11-06).
    static let designAsk = """
        Before drawing, design this moving icon in words, under 120 words, no SVG and no numbers for its shape yet: you \
        will draw the object the way you know it. Say: 1) what the eye must see for this to read as that action and \
        not a plain pulse or swap; 2) the parts: which move, everything attached to a moving part that goes with it, \
        what stays still, the hinge or centre of any turn and which way it turns, and any extra pieces and where they \
        go; 3) the beats, each with its time in ms, across a lap that ends back at rest.
        """

    /// What follows the design in the talk.
    public static let drawTheDesign = """
        Draw exactly that design, every part it names, then call set_timing and set_keys for its beats. \
        \(AskIcon.smallParts)
        """

    /// The body of the one call that designs the motion: no tools, no document.
    public static func designBody(model: String, request: String) -> AgentJSON {
        let rules = AskConversation.iconRules.replacingOccurrences(of: AskConversation.iconActionRule, with: "")
        return ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
                "messages": [["role": "system", "content": .string("You design moving icons.\n\(rules)\n\(drawRules)")],
                             ["role": "user", "content": .string("\(request)\n\n\(designAsk)")]],
                "options": ["temperature": 0, "num_predict": .number(Double(mostDesignTokens))]]
    }

    /// The design in `answer`, or nil when it holds none, which only costs
    /// the motion its head start.
    public static func design(fromAnswer answer: String) -> String? {
        let words = AskConversation.withoutThinking(answer).trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty || words.contains("<svg") ? nil : words
    }

    /// How a thing moves well, true of anything.
    static let principles = """
        - Decide the beats first, then time them in milliseconds. Before a big move, a small anticipation the other \
        way. A quick event is quick: a snap or a burst takes 60 to 150 ms, a settle 200 to 400 ms. Afterwards, \
        follow-through: loose parts lag, overshoot and settle, each a little less. Let parts start a little apart, \
        never all at once. A key's curve is how it LEAVES that key: Ease in leaves rest, Ease out arrives, Ease out \
        back overshoots, Linear is a steady spin. Hold stays exactly at that key's value until the next key and \
        then jumps, so a change you want to see never leaves a Hold.
        - A change of state is a movement, never one picture fading into another. What breaks or bursts swells a \
        little, is gone within 100 ms, and at that moment separate small pieces fly out from where it was, slowing \
        and fading out within 400 ms: pieces never stand still. Three to six pieces in one <g>, drawn where they end \
        up, keyed as that one group from scale 30 to 100 and opacity 100 to 0, are two calls. A part that lifts on a hinge is hinged at its left end, on the object's real edge, and lifting it is a negative \
        rotation, no more than it could swing. What moves never crosses what stays still: it stops short of it.
        - A lap is 1 to 3 seconds and loops unless the words say once. It must loop cleanly: set_timing seconds is \
        the lap, and every value's last key sits at the end of the lap with its first value, or a turn ends on a \
        whole 360. What vanishes comes back before the lap ends. Leave a beat at rest so the eye can read it. \
        An object that grows, swings or sheds pieces is drawn about 16 across, with room around it for the motion.
        """

    /// On a picture with layers already there.
    static let keyRules = """
        - To animate what is here, call set_keys once for each value of each layer that moves, layer being its id \
        from the document above, and set_timing once for the lap. position is the top left of its box, in the points \
        of what holds it. scale is a percent, opacity 0 to 100, rotation degrees clockwise about pivot, which is x and \
        y as fractions of the layer's own box (0.5, 0 is the middle of its top edge). trimEnd is how much of a line is \
        drawn, 0 to 100.
        \(principles)
        """

    /// On a picture that already moves.
    static let tweakRules = """
        - This picture already moves: its keys are in the document above under keyed, and lap is how long it plays. \
        A change to the motion keeps that motion and changes its keys in place. Faster, slower, further, less, more \
        bounce, the other way: call change_keys once with speed, amount or both, and layers when the words name only \
        some parts: their ids, every part the words mean. A pause when it loops: set_timing with seconds longer than \
        lap. Anything else about one value: set_keys with replace true and all of that value's keys, in the points \
        the document shows. Never draw it again, and never change what the words did not name.
        """

    // MARK: Room for the motion

    /// The most a drawing's viewBox grows to make room. Further and the icon
    /// is too small to read, and whatever flies that far is meant to leave.
    public static let mostRoom: CGFloat = 1.4

    /// `steps` with the drawing's viewBox widened about its middle to hold
    /// everything its keys do, so nothing is cut off by the frame. A vector
    /// tool like any other: it reads boxes and keys and knows nothing of what
    /// they are. Asked to fit instead, the model shrank what it had designed:
    /// a flap's swing from 180 to 90 and a letter's rise from 3 to 1, a round of
    /// the plan each time (the eval, 2026-11-06).
    public static func fitted(_ steps: [AskStep]) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox,
              var object = steps[index].arguments.objectValue else { return steps }
        let reach = AskMotionCheck.reach(of: steps.filter { $0.tool == "set_keys" }, in: art)
        guard !reach.isNull, !view.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack).contains(reach) else { return steps }
        let needed = [view.midX - reach.minX, reach.maxX - view.midX, view.midY - reach.minY, reach.maxY - view.midY].max() ?? 0
        let side = min((needed + 2 * AskMotionCheck.edgeSlack) * 2, view.width * mostRoom)
        guard side > view.width else { return steps }
        let box = CGRect(x: view.midX - side / 2, y: view.midY - side / 2, width: side, height: side)
        let said = [box.minX, box.minY, box.width, box.height].map { String(format: "%.3f", Double($0)) }.joined(separator: " ")
        guard let found = svg.range(of: #"viewBox="[^"]*""#, options: .regularExpression) else { return steps }
        object["svg"] = .string(svg.replacingCharacters(in: found, with: "viewBox=\"\(said)\""))
        var out = steps
        out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        return out
    }

    // MARK: A part of a planned drawing

    /// `$N/part`: a part of what step N draws.
    public struct PartReference: Hashable, Sendable {
        public let step: Int
        public let part: String
    }

    public static func partReference(_ word: String) -> PartReference? {
        guard word.hasPrefix("$"), let slash = word.firstIndex(of: "/"),
              let step = Int(word[word.index(after: word.startIndex)..<slash]) else { return nil }
        let part = String(word[word.index(after: slash)...])
        return part.isEmpty ? nil : PartReference(step: step, part: part)
    }

    /// A name with everything that does not tell two parts apart taken out.
    static func plain(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Every id in the drawing a key can name: its parts and its groups.
    static func partNames(in art: SVGArtwork) -> [String] {
        var names: [String] = []
        for part in art.parts {
            for name in part.groups + [part.name].compactMap({ $0 }) where !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Why this value cannot stand on `property`, or nil where it can: said
    /// while the model can mend it, since a key refused as the plan runs is lost.
    static func valueProblem(_ value: AgentJSON, property: String?) -> String? {
        switch MotionProperty(rawValue: property ?? "") {
        case .position?:
            return value["x"]?.doubleValue != nil && value["y"]?.doubleValue != nil ? nil
                : "Not planned: a position key's value is x and y, such as {\"x\": 3, \"y\": -2}."
        case .color?:
            return value.stringValue?.hasPrefix("#") == true ? nil : "Not planned: a color key's value is #RRGGBB."
        case .opacity?, .trimStart?, .trimEnd?:
            guard let number = value.doubleValue else { return "Not planned: \(property ?? "that")'s value is a number." }
            return (0...100).contains(number) ? nil : "Not planned: \(property ?? "that") runs 0 to 100."
        case nil:
            return nil
        default:
            return value.doubleValue != nil ? nil : "Not planned: \(property ?? "that")'s value is a number."
        }
    }

    /// Why this step cannot key what it names, or nil where it can.
    static func refusal(_ arguments: AgentJSON, steps: [AskStep]) -> String? {
        for key in arguments["keys"]?.arrayValue ?? [] {
            if let value = key["value"], let problem = valueProblem(value, property: arguments["property"]?.stringValue) { return problem }
        }
        if let word = arguments["layer"]?.stringValue, let number = AskStep.stepNamed(word),
           steps.indices.contains(number - 1), steps[number - 1].tool == "add_drawing" {
            return "Not planned: key the parts, not the whole drawing: layer is $\(number)/its-id. To move all of it, give each part the same keys."
        }
        guard let reference = (arguments["layer"]?.stringValue).flatMap(partReference) else { return nil }
        guard steps.indices.contains(reference.step - 1), steps[reference.step - 1].tool == "add_drawing",
              case .success(let art)? = steps[reference.step - 1].arguments["svg"]?.stringValue.map({ SVGArtwork.parse($0, keepingGroups: true) }) else {
            return "Not planned: step \(reference.step) draws no parts to key. Draw the icon first, then key its parts as $N/its-id."
        }
        let names = partNames(in: art)
        guard names.contains(where: { plain($0) == plain(reference.part) }) else {
            return "Not planned: the drawing has no part called \(reference.part). Its parts are \(names.joined(separator: ", "))."
        }
        return nil
    }

    /// Why this drawing cannot be keyed as it is, or nil.
    static func drawingProblem(_ svg: String) -> String? {
        // Dashes do not reach the layers, so a ring with a dashed gap landed
        // whole, and a whole ring spinning looks still (the eval, 2026-11-06).
        guard !svg.contains("stroke-dash") else {
            return "Not planned: no stroke-dasharray in the svg. A gap is drawn: an open path or an arc that stops short. Call add_drawing once more with the whole svg."
        }
        guard case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return nil }
        let hidden = svg.range(of: #"(?<![a-z-])opacity="0(\.0*)?""#, options: .regularExpression) != nil
        guard hidden || art.parts.contains(where: { $0.opacity <= 0.001 }) else { return nil }
        return "Not planned: every part is drawn visible: no opacity=\"0\" in the svg. A key at 0 seconds with opacity 0 hides it. Call add_drawing once more with the whole svg."
    }

    /// A key's arguments as far as planning can tidy them: a pivot only ever
    /// means something to a turn, and the model adds one to a scale.
    static func tidied(_ arguments: AgentJSON) -> AgentJSON {
        guard var object = arguments.objectValue, arguments["property"]?.stringValue != MotionProperty.rotation.rawValue else { return arguments }
        object["pivot"] = nil
        return .object(object)
    }

    // MARK: Landing

    /// Whether a pivot was written as fractions of the part, the way the tool
    /// says on a layer that is there, and not as a place on the grid: nothing
    /// that turns has its hinge in the top left corner of the grid, and a gear
    /// turned about 0.5, 0.5 flew off the canvas (the eval, 2026-11-06).
    static func isFraction(_ x: Double, _ y: Double) -> Bool { (0...1).contains(x) && (0...1).contains(y) }

    /// How the drawing's grid stands on the canvas.
    private struct Grid {
        let origin: CGPoint
        let drawn: CGPoint
        let scale: CGFloat
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + (point.x - drawn.x) * scale, y: origin.y + (point.y - drawn.y) * scale)
        }
    }

    private static func grid(of art: SVGArtwork, landedAs id: UUID, in document: PhotonzDocument) -> Grid? {
        guard let layer = document.layer(id: id), let box = document.canvasBounds(of: id) else { return nil }
        // A frame stands on the viewBox. A drawing fitted into a box of its
        // own (an icon given a place in somebody's picture) is what was drawn.
        let from = (layer.isFrame ? art.viewBox : nil) ?? art.bounds
        guard from.width > 0, from.height > 0 else { return nil }
        return Grid(origin: box.origin, drawn: from.origin, scale: min(box.width / from.width, box.height / from.height))
    }

    private static func layer(named part: String, under layer: Layer) -> Layer? {
        for child in layer.children {
            if plain(child.name) == plain(part) { return child }
            if let found = Self.layer(named: part, under: child) { return found }
        }
        return nil
    }

    /// `step` as it runs now that what it names has landed: a part becomes its
    /// layer, a place on the grid becomes the point keys hold, a pivot on the
    /// grid a spot on the layer's box. Any other step goes through as it was.
    public static func landing(_ step: AskStep, in document: PhotonzDocument, plan: [AskStep],
                               made: [Int: String]) -> Result<AskStep, AgentToolError> {
        guard let reference = (step.arguments["layer"]?.stringValue).flatMap(partReference) else { return .success(step) }
        func fail(_ words: String) -> Result<AskStep, AgentToolError> { .failure(AgentToolError("\(step.tool): \(words)")) }
        guard plan.indices.contains(reference.step - 1), let id = made[reference.step].flatMap(UUID.init(uuidString:)),
              let top = document.layer(id: id), let svg = plan[reference.step - 1].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let grid = grid(of: art, landedAs: id, in: document) else {
            return fail("step \(reference.step) did not land.")
        }
        guard let part = layer(named: reference.part, under: top), let box = document.canvasBounds(of: part.id) else {
            return fail("\(reference.part) is not in the drawing.")
        }
        guard var object = step.arguments.objectValue else { return .success(step) }
        object["layer"] = .string(part.id.uuidString)
        if step.arguments["property"]?.stringValue == MotionProperty.position.rawValue,
           case .point(let still)? = part.keyStill(.position) {
            object["keys"] = .array((step.arguments["keys"]?.arrayValue ?? []).map { key in
                guard var moved = key.objectValue, let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return key }
                moved["value"] = ["x": .number(Double(still.x + CGFloat(x) * grid.scale)), "y": .number(Double(still.y + CGFloat(y) * grid.scale))]
                return .object(moved)
            })
        }
        if let x = step.arguments["pivot"]?["x"]?.doubleValue, let y = step.arguments["pivot"]?["y"]?.doubleValue,
           !isFraction(x, y) {
            let spot = MotionPivot(at: grid.place(CGPoint(x: x, y: y)), in: box).unit
            object["pivot"] = ["x": .number(Double(spot.x)), "y": .number(Double(spot.y))]
        }
        return .success(AskStep(tool: step.tool, arguments: .object(object)))
    }
}

/// Whether a planned motion can play: rules true of any subject, sent back to
/// the model once while it can still do something about them.
public enum AskMotionCheck {

    /// After this many goes it lands as it is: a rough motion beats none.
    public static let mostSendBacks = 2

    private static func values(_ step: AskStep) -> [AgentJSON] {
        (step.arguments["keys"]?.arrayValue ?? []).sorted {
            ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0)
        }.compactMap { $0["value"] }
    }

    private static func sameAtTheLoop(_ first: AgentJSON, _ last: AgentJSON, property: String?) -> Bool {
        if let a = first.doubleValue, let b = last.doubleValue {
            if property == MotionProperty.rotation.rawValue { return (a - b).truncatingRemainder(dividingBy: 360) == 0 }
            return abs(a - b) < 0.5
        }
        if let ax = first["x"]?.doubleValue, let ay = first["y"]?.doubleValue,
           let bx = last["x"]?.doubleValue, let by = last["y"]?.doubleValue {
            return abs(ax - bx) < 0.05 && abs(ay - by) < 0.05
        }
        return first == last
    }

    private static func name(of step: AskStep) -> String {
        let layer = step.arguments["layer"]?.stringValue ?? "a part"
        return AskMotion.partReference(layer)?.part ?? layer
    }

    /// A Hold on the last key but one, with a different value after it: the
    /// value stands still and jumps as the lap ends, and the move is never seen.
    private static func holdsBeforeTheEnd(_ step: AskStep) -> Bool {
        let keys = (step.arguments["keys"]?.arrayValue ?? []).sorted { ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0) }
        guard keys.count >= 2, let last = keys.last?["value"], let before = keys.dropLast().last,
              before["curve"]?.stringValue?.caseInsensitiveCompare(AgentKeyCurve.hold) == .orderedSame else { return false }
        return before["value"] != last
    }

    /// The box of a part on its drawing's grid, stroke included.
    private static func box(of part: String, in art: SVGArtwork) -> CGRect? {
        let plain = AskMotion.plain(part)
        let held = art.parts.filter { one in
            one.name.map { AskMotion.plain($0) == plain } ?? false || one.groups.contains { AskMotion.plain($0) == plain }
        }
        let boxes = held.map { SVGArtwork.shapeBounds($0.shape).insetBy(dx: -$0.strokeWidth / 2, dy: -$0.strokeWidth / 2) }
        return boxes.reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// The furthest this step takes `box`, at any of its keys.
    private static func reach(of step: AskStep, box: CGRect) -> CGRect {
        var far = box
        var pivot = CGPoint(x: box.midX, y: box.midY)
        if let x = step.arguments["pivot"]?["x"]?.doubleValue, let y = step.arguments["pivot"]?["y"]?.doubleValue {
            pivot = AskMotion.isFraction(x, y) ? CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y) : CGPoint(x: x, y: y)
        }
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
        let keys = step.arguments["keys"]?.arrayValue ?? []
        for key in keys {
            guard let value = key["value"] else { continue }
            switch MotionProperty(rawValue: step.arguments["property"]?.stringValue ?? "") {
            case .position?:
                far = far.union(box.offsetBy(dx: value["x"]?.doubleValue ?? 0, dy: value["y"]?.doubleValue ?? 0))
            case .scale?:
                let grow = (value.doubleValue ?? 100) / 100
                far = far.union(CGRect(x: box.midX - box.width * grow / 2, y: box.midY - box.height * grow / 2, width: box.width * grow, height: box.height * grow))
            default:
                break
            }
        }
        // A turn passes through everything between its keys. Spinning about
        // its own middle a part stays where it is: its box's corners swinging
        // out are not the part, and made room shrank a ring for nothing.
        if step.arguments["property"]?.stringValue == MotionProperty.rotation.rawValue,
           hypot(pivot.x - box.midX, pivot.y - box.midY) >= 1 {
            let angles = keys.compactMap { $0["value"]?.doubleValue }
            if let least = angles.min(), let most = angles.max() {
                for degrees in stride(from: least, through: most, by: 15) {
                    let turn = degrees * .pi / 180
                    for corner in corners {
                        let (x, y) = (corner.x - pivot.x, corner.y - pivot.y)
                        far = far.union(CGRect(x: pivot.x + x * cos(turn) - y * sin(turn), y: pivot.y + x * sin(turn) + y * cos(turn), width: 0, height: 0))
                    }
                }
            }
        }
        return far
    }

    /// The furthest `keyed` takes everything it names, on the drawing's grid:
    /// each part's turns and growth first, then its travel on top of them,
    /// since a part that does both does them at once.
    static func reach(of keyed: [AskStep], in art: SVGArtwork) -> CGRect {
        var parts: [String: [AskStep]] = [:]
        for step in keyed {
            guard let reference = (step.arguments["layer"]?.stringValue).flatMap(AskMotion.partReference) else { continue }
            parts[AskMotion.plain(reference.part), default: []].append(step)
        }
        var whole = CGRect.null
        for (part, steps) in parts {
            guard let box = box(of: part, in: art) else { continue }
            let moves = steps.filter { $0.arguments["property"]?.stringValue == MotionProperty.position.rawValue }
            var far = steps.filter { !moves.contains($0) }.reduce(box) { $0.union(reach(of: $1, box: box)) }
            let inPlace = far
            for step in moves { far = far.union(reach(of: step, box: inPlace)) }
            whole = whole.union(far)
        }
        return whole
    }

    /// How far past the edge a part may stand before it is cut off for the eye.
    static let edgeSlack: CGFloat = 0.25

    /// What is wrong with `steps` as a moving icon, in words for the model.
    public static func problems(_ steps: [AskStep]) -> [String] {
        let keyed = steps.filter { $0.tool == "set_keys" }
        guard !keyed.isEmpty else {
            return ["Nothing moves yet. Call set_keys for each value of each part that moves, then finish."]
        }
        var said: [String] = []
        let flat = keyed.filter { step in
            let list = values(step)
            return list.count > 1 && list.allSatisfy { $0 == list[0] }
        }.map(name(of:))
        if !flat.isEmpty {
            said.append("\(flat.joined(separator: ", ")): its keys never change, so it does not move. Call set_keys again with replace true and all of its keys.")
        }
        let held = keyed.filter(holdsBeforeTheEnd).map(name(of:))
        if !held.isEmpty {
            said.append("\(held.joined(separator: ", ")) \(held.count == 1 ? "stands" : "stand") on a Hold until the last key and then jumps, so that move is never seen. Call set_keys again with replace true and all of its keys, the move starting at an earlier key with a curve that moves.")
        }
        guard steps.last(where: { $0.tool == "set_timing" })?.arguments["loop"]?.boolValue != false else { return said }
        // A line that draws itself and starts over is a loop: the file goes
        // back to nothing as the next lap draws it again.
        let drawing: Set<String> = [MotionProperty.trimStart.rawValue, MotionProperty.trimEnd.rawValue]
        let jumps = keyed.compactMap { step -> String? in
            let list = values(step)
            guard !drawing.contains(step.arguments["property"]?.stringValue ?? ""), list.count > 1, let first = list.first, let last = list.last,
                  !sameAtTheLoop(first, last, property: step.arguments["property"]?.stringValue) else { return nil }
            return "\(name(of: step))'s \(step.arguments["property"]?.stringValue ?? "value")"
        }
        guard !jumps.isEmpty else { return said }
        return said + ["It jumps when the lap starts again: \(jumps.joined(separator: ", ")) \(jumps.count == 1 ? "ends" : "end") away from where \(jumps.count == 1 ? "it starts" : "they start"). Call set_keys again for each with replace true and all of its keys, the motion intact and a last key back at the first value at the end of the lap, then finish."]
    }
}
