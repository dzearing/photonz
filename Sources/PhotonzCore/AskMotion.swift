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
    static let fileWords: Set<String> = ["svg", "svgs", "gif", "gifs"]
    /// A GIF is a picture that moves: the word asks for motion on its own.
    static let gifWords: Set<String> = ["gif", "gifs"]
    /// The words that ask for something drawn to move. Narrower than what
    /// reaches the key tools: "a motion sensor icon" is a still of a sensor.
    static let drawingWords: Set<String> = ["animate", "animated", "animating", "animation", "animations", "looping"]

    /// Whether `request` asks for what is drawn to move: "animated", "a
    /// looping", "a gif of". Whatever it is of.
    public static func asksToMove(_ request: String) -> Bool {
        AgentDrawingWords.words(request).contains { word in
            drawingWords.contains(word) || gifWords.contains(word) || slipOfAnimate(word)
        }
    }

    /// The long words for motion, which a slip of the keyboard does not turn
    /// into another word: one letter left out, added, changed or two swapped
    /// ("anmiated", "animted") still asks for motion. "animal", "anime" and
    /// "animator" are two or more slips away from every one of them.
    static let slippable = ["animate", "animated", "animating", "animation", "animations"]

    static func slipOfAnimate(_ word: String) -> Bool {
        guard word.count >= 6, word.first == "a" else { return false }
        return slippable.contains { oneSlip(word, $0) }
    }

    /// Whether `a` is `b` with at most one letter left out, added, changed, or
    /// two neighbours swapped.
    static func oneSlip(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard abs(x.count - y.count) <= 1 else { return false }
        if x == y { return true }
        var i = 0
        while i < min(x.count, y.count), x[i] == y[i] { i += 1 }
        if x.count == y.count {
            if Array(x[(i + 1)...]) == Array(y[(i + 1)...]) { return true }
            return i + 1 < x.count && x[i] == y[i + 1] && x[i + 1] == y[i] && Array(x[(i + 2)...]) == Array(y[(i + 2)...])
        }
        return x.count > y.count ? Array(x[(i + 1)...]) == Array(y[i...]) : Array(x[i...]) == Array(y[(i + 1)...])
    }

    // MARK: When the words do not say

    /// Asked of an icon whose words name no motion, before it is drawn still:
    /// on 2026-11-07 the user told a trash can's whole story (the lid opens,
    /// trash is thrown in, bounces off the lid and closes it) in words the
    /// motion check did not know, and got a still can. The model reads the
    /// request; nothing here knows any subject. One action is still a still
    /// (a balloon popping, a bell ringing): asked of qwen3.8-27b on 2026-11-08,
    /// this wording read 17 stills and 9 stories right, where asking only
    /// whether it moves turned five one-action stills into moving icons.
    static let movesQuestion = """
        An icon was asked for. Reply moves only if the words ask for it to move (animated, moving, playing, \
        looping), or tell two or more things that happen one after another (this happens, then that). One thing \
        doing one action (popping, opening, ringing, flying, taking off) is a still icon showing that action. Reply \
        only: moves, or: still.

        The request:
        """

    /// The body of the one call that asks: no tools, no document.
    public static func movesBody(model: String, request: String) -> AgentJSON {
        ["model": .string(model), "stream": false, "think": false, "keep_alive": "30m",
         "messages": [["role": "user", "content": .string("\(movesQuestion) \(request)")]],
         "options": ["temperature": 0, "num_predict": 8]]
    }

    /// Whether the answer says it moves. Anything else draws it still, as before.
    public static func moves(fromAnswer answer: String) -> Bool {
        let said = AskConversation.withoutThinking(answer).trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters).lowercased()
        return said == "moves" || said == "move"
    }

    // MARK: Every beat

    /// Said once, when a designed moving icon says it is finished: the beats
    /// it designed, in order, each keyed and seen, or named as left out.
    static let beatsReview = """
        Before it lands, go through the beats of your design in the order the request tells them. Each beat must \
        be keyed and long enough to see (200 ms at the least, a journey 300 to 600 ms), each starting as the one \
        that causes it ends. Key any beat nothing moves for yet, or set_keys again with replace true for one too \
        quick or too small to see. If a beat cannot be shown, finish with one last line, Left out: and those beats \
        in a few words. When every beat is there, finish with: Left out: nothing.
        """

    /// The beats the model's last words say it left out, and those words
    /// without that line.
    static func leftOut(in said: String) -> (beats: [String], rest: String) {
        var beats: [String] = []
        var kept: [Substring] = []
        for line in said.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("left out:") else { kept.append(line); continue }
            let named = trimmed.dropFirst("left out:".count).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".")).trimmingCharacters(in: .whitespaces)
            if ["", "nothing", "none", "no beats", "no beat"].contains(named.lowercased()) { continue }
            beats.append(named)
        }
        return (beats, kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whether `request` asks for a moving icon to be drawn: a request about
    /// motion that names an icon, an SVG or a GIF, or any request about motion
    /// on a `blankIcon`, a picture made as an icon with nothing drawn on it yet
    /// (the Icon size, or the New window asked for something animated). "Animate
    /// the icon" is about the one here, which `AskConversation.takesIconRoute`
    /// settles.
    public static func drawsMotion(_ request: String, blankIcon: Bool = false) -> Bool {
        let words = AgentDrawingWords.words(request)
        return asksToMove(request) && (blankIcon || AskIcon.asked(in: request) || !fileWords.isDisjoint(with: words))
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
        opacity="0" in the svg: a key at 0 seconds hides it. What comes out of another part starts hidden inside it: \
        draw it before that part in the svg, as an outline like the rest, with no fill on either. Parts that move together share a <g id="what-they-are">, \
        with everything attached to them and nothing drawn twice; a part that moves alone has an id of its own.
        - Name a part as layer "$1/its-id". position is how far it has moved from where you drew it, x and y on the 24 \
        grid: x 0 y 0 is where it was drawn, y grows downward. scale is a percent of its size, about its own middle. \
        rotation is degrees clockwise, about pivot: x and y on the 24 grid, the hinge, the mount or the centre of \
        the circle it turns on. rotationX folds a part over a level hinge, rotationY over an upright one: degrees, \
        about pivot on that edge, 180 laying it flat the other side of it. opacity is 0 to 100. trimEnd is how much \
        of a line is drawn, 0 to 100, for a line drawing itself. color is #RRGGBB.
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
        go; 3) the beats in the order the request tells them, each with its time in ms, across a lap that ends \
        back at rest.
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
        up, keyed as that one group from scale 30 to 100 and opacity 100 to 0, are two calls. A part that swings on one point, seen side on (a door seen from above, an arm), \
        turns with rotation, hinged at its end on the object's real edge, no more than it could swing. Lifting is a \
        negative rotation when the hinge is at its left end and a positive one when the hinge is at its right end. A part hinged along a whole edge facing you (a cover, a page, a door seen from the front) folds over that \
        edge: rotationX for a top or bottom edge, rotationY for a side, pivot the middle of that edge, 180 to lie \
        open; it never turns flat. What moves never crosses what stays still: it stops short of it.
        - A line that draws itself is keyed on trimEnd alone, never trimStart too: trimEnd 0 at 0 seconds, so the \
        lap starts with it undrawn, then up to 100 in its own beat, several lines one after another a little apart, \
        and it holds drawn. To start over it fades to opacity 0, then trimEnd goes back to 0 while it is unseen, \
        then opacity back to 100 at the end of the lap.
        - What leaves (flies off, is thrown, is sent) goes all the way out of the frame, never stopping half over \
        its edge, seen the whole way: Ease in, speeding up over 300 to 500 ms. Then it comes back in from the other \
        side, or fades in where it rests. Marks that show a part moving (lines behind it, a trail) go with it or \
        are gone before it is, never left on their own.
        - A story of several beats plays them in the order told, one after another, each long enough to read: \
        200 ms at the least, a journey 300 to 600 ms. What a beat causes starts as that beat ends, at the key where \
        the two parts touch. The beats fill most of a 2 to 4 second lap with a short rest at its end, never a burst \
        at the start and a long still wait.
        - Nothing appears out of nowhere. What is thrown, dropped or put in starts away from where it lands (in \
        view, or outside the frame) and travels the whole way there, x and y keyed together along an arc; what goes \
        into something passes behind its front and is gone inside it.
        - When the whole object moves (flies off, lifts off, swings, shakes), draw all of it inside one <g> and key \
        that <g>, so no part is left behind; a part that also moves on its own is a <g> inside it. A shake is quick \
        turns of 5 to 10 degrees, or moves of 1 on the grid, three or four times. A thing hanging from a point swings \
        with rotation about that point, never rotationX or rotationY, which only fold a flat cover over an edge.
        - A lap is 1 to 3 seconds, a story 2 to 4, and loops unless the words say once. It must loop cleanly: set_timing seconds is \
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
    public static func fitted(_ planned: [AskStep]) -> [AskStep] {
        let steps = swingsFitted(planned)
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox,
              var object = steps[index].arguments.objectValue else { return steps }
        let slack = AskMotionCheck.edgeSlack
        let reach = AskMotionCheck.reach(of: steps.filter { $0.tool == "set_keys" }, in: art)
        guard !reach.isNull, !view.insetBy(dx: -slack, dy: -slack).contains(reach) else { return steps }
        func room(holding reach: CGRect) -> CGRect {
            let needed = [view.midX - reach.minX, reach.maxX - view.midX, view.midY - reach.minY, reach.maxY - view.midY].max() ?? 0
            let side = max(view.width, min((needed + 2 * slack) * 2, view.width * mostRoom))
            return CGRect(x: view.midX - side / 2, y: view.midY - side / 2, width: side, height: side)
        }
        var out = steps
        var box = room(holding: reach)
        if !box.insetBy(dx: -slack, dy: -slack).contains(reach) {
            // Something travels past all the room there is: it is meant to
            // leave, and leaves whole rather than stopping half over the edge.
            (out, box) = leaving(steps, in: art, most: box, view: view)
        }
        if box.width > view.width {
            let said = [box.minX, box.minY, box.width, box.height].map { String(format: "%.3f", Double($0)) }.joined(separator: " ")
            guard let found = svg.range(of: #"viewBox="[^"]*""#, options: .regularExpression) else { return out }
            object["svg"] = .string(svg.replacingCharacters(in: found, with: "viewBox=\"\(said)\""))
            out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        }
        return out
    }

    /// `steps` with every swing that would reach past all the room there is
    /// eased down, all its keys by one share, until it fits: a plane tipped
    /// 35 degrees about its tail had its nose cut flat by the frame while it
    /// stood still (the eval, 2026-11-08). Only a swing, under half a turn
    /// either way: a turn all the way round has to end where it began.
    static func swingsFitted(_ steps: [AskStep]) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox else { return steps }
        let side = view.width * mostRoom
        let room = CGRect(x: view.midX - side / 2, y: view.midY - side / 2, width: side, height: side)
            .insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack)
        func scaled(_ step: AskStep, by share: Double) -> AskStep {
            guard var object = step.arguments.objectValue else { return step }
            object["keys"] = .array((step.arguments["keys"]?.arrayValue ?? []).map { key in
                guard var moved = key.objectValue, let degrees = key["value"]?.doubleValue else { return key }
                moved["value"] = .number(rounded(CGFloat(degrees * share)))
                return .object(moved)
            })
            return AskStep(tool: step.tool, arguments: .object(object))
        }
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys" && turns.contains(step.arguments["property"]?.stringValue ?? "") {
            let angles = (step.arguments["keys"]?.arrayValue ?? []).compactMap { $0["value"]?.doubleValue }
            guard let widest = angles.map(abs).max(), widest > 0, widest < 180,
                  !room.contains(AskMotionCheck.reach(of: [step], in: art)) else { continue }
            // The largest share that fits, found by halving: the reach of a
            // turn grows with its angle, but not in a straight line.
            var (low, high) = (0.0, 1.0)
            for _ in 0..<12 {
                let middle = (low + high) / 2
                if room.contains(AskMotionCheck.reach(of: [scaled(step, by: middle)], in: art)) { low = middle } else { high = middle }
            }
            // Swung less than half as far it no longer says what it did.
            if low >= 0.4 { out[at] = scaled(step, by: low) }
        }
        return out
    }

    /// `steps` with every place a part travels to either inside the room or
    /// wholly out of the frame, and the room that holds what stays. A part
    /// keyed half over the edge is cut off for as long as it stands there (a
    /// plane taking off stalled with its nose sliced flat, the eval,
    /// 2026-11-08), so each such place goes to whichever is nearer: a little
    /// further in, or far enough on to clear the frame. Geometry only, about
    /// boxes and keys, true of anything that travels.
    static func leaving(_ steps: [AskStep], in art: SVGArtwork, most: CGRect, view: CGRect) -> ([AskStep], CGRect) {
        let slack = AskMotionCheck.edgeSlack
        let keyed = steps.filter { $0.tool == "set_keys" }
        let isMove = { (step: AskStep) in step.arguments["property"]?.stringValue == MotionProperty.position.rawValue }
        let still = keyed.filter { !isMove($0) }
        var holding = AskMotionCheck.reach(of: still, in: art)
        let inside = most.insetBy(dx: -slack, dy: -slack)
        enum Place {
            case kept, moved(CGFloat), out
            /// Whether a key here brings a part that left back into sight.
            var returns: Bool { if case .out = self { false } else { true } }
        }
        var plans: [Int: (box: CGRect, places: [Place])] = [:]
        for (index, step) in steps.enumerated() where step.tool == "set_keys" && isMove(step) {
            guard let part = (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part,
                  let box = AskMotionCheck.reach(of: still, in: art, only: part) else { continue }
            let places = Self.inTime(step).map { key -> Place in
                guard let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return .kept }
                let travel = CGVector(dx: x, dy: y)
                let there = box.offsetBy(dx: travel.dx, dy: travel.dy)
                if inside.contains(there) || travel == .zero {
                    holding = holding.union(there)
                    return .kept
                }
                let back = Self.share(of: travel, keeping: box, inside: inside.insetBy(dx: 0.01, dy: 0.01))
                let on = Self.share(of: travel, clearing: box, of: most.insetBy(dx: -slack, dy: -slack))
                // Nearer as a ratio: pulled to 80% is as far as pushed to 125%.
                guard back > 0, 1 / back <= on else { return .out }
                holding = holding.union(box.offsetBy(dx: travel.dx * back, dy: travel.dy * back))
                return .moved(back)
            }
            plans[index] = (box, places)
        }
        let needed = [view.midX - holding.minX, holding.maxX - view.midX, view.midY - holding.minY, holding.maxY - view.midY].max() ?? 0
        let side = holding.isNull ? view.width : max(view.width, min((needed + 2 * slack) * 2, most.width))
        let room = CGRect(x: view.midX - side / 2, y: view.midY - side / 2, width: side, height: side)
        var out = steps
        for (index, plan) in plans {
            guard var object = steps[index].arguments.objectValue else { continue }
            let keys = Self.inTime(steps[index])
            let clear = room.insetBy(dx: -slack, dy: -slack)
            var landed: [AgentJSON] = []
            for (number, (key, place)) in zip(keys, plan.places).enumerated() {
                guard var moved = key.objectValue, let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else {
                    landed.append(key)
                    continue
                }
                let travel = CGVector(dx: x, dy: y)
                switch place {
                case .kept:
                    landed.append(key)
                    continue
                case .moved(let back):
                    moved["value"] = ["x": .number(Self.rounded(x * back)), "y": .number(Self.rounded(y * back))]
                    landed.append(.object(moved))
                    continue
                case .out:
                    let on = Self.share(of: travel, clearing: plan.box, of: clear)
                    moved["value"] = ["x": .number(Self.rounded(x * on)), "y": .number(Self.rounded(y * on))]
                }
                // Gone, and the next key brings it back: it comes in from the
                // other side, carrying on the way it went, rather than backing
                // down the way it left. It waits out of sight on a Hold, then
                // stands as far off the other side.
                let gap = 2 * Double(PropertyKeys.nearMS) / 1000
                guard number + 1 < keys.count, plan.places[number + 1].returns,
                      let from = key["seconds"]?.doubleValue, let to = keys[number + 1]["seconds"]?.doubleValue,
                      to - from > 2 * gap else {
                    landed.append(.object(moved))
                    continue
                }
                let curve = moved["curve"]
                moved["curve"] = .string(AgentKeyCurve.hold)
                landed.append(.object(moved))
                let away = CGVector(dx: -travel.dx, dy: -travel.dy)
                let far = Self.share(of: away, clearing: plan.box, of: clear)
                var enters: [String: AgentJSON] = ["seconds": .number(Self.rounded(CGFloat(from + gap))),
                                                   "value": ["x": .number(Self.rounded(away.dx * far)), "y": .number(Self.rounded(away.dy * far))]]
                if let curve { enters["curve"] = curve }
                landed.append(.object(enters))
            }
            object["keys"] = .array(landed)
            out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        }
        return (out, room)
    }

    /// A step's keys in the order they play.
    static func inTime(_ step: AskStep) -> [AgentJSON] {
        (step.arguments["keys"]?.arrayValue ?? []).enumerated().sorted {
            ($0.element["seconds"]?.doubleValue ?? 0, $0.offset) < ($1.element["seconds"]?.doubleValue ?? 0, $1.offset)
        }.map(\.element)
    }

    // MARK: What comes out of something

    /// `steps` with what travels out from inside a closed outline drawn
    /// after it hidden at rest: that outline, the smallest that holds it, is
    /// filled white, so the part is behind it until it comes out. Told to do
    /// this itself, the model filled the part and the cover over it and left
    /// the outline it sat in empty, so the part showed through (the eval,
    /// 2026-11-08). Order and boxes only: a part drawn in front of the
    /// outline, or one that never travels, was meant to be seen.
    public static func hidden(_ steps: [AskStep]) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              var svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true),
              var object = steps[index].arguments.objectValue else { return steps }
        let travelling = Set(steps.filter { $0.tool == "set_keys" && $0.arguments["property"]?.stringValue == MotionProperty.position.rawValue }
            .compactMap { ($0.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) } })
        func holds(_ part: SVGArtwork.Part, _ name: String) -> Bool {
            part.name.map { plain($0) == name } ?? false || part.groups.contains { plain($0) == name }
        }
        var filled: Set<String> = []
        for name in travelling {
            let own = art.parts.indices.filter { holds(art.parts[$0], name) }
            guard let last = own.last, let box = AskMotionCheck.box(of: name, in: art) else { continue }
            let covers = art.parts.indices.filter { at in
                let part = art.parts[at]
                guard at > last, part.fill == nil, let cover = part.name, !holds(part, name) else { return false }
                if case .path(let outline) = part.shape, !outline.closed { return false }
                return SVGArtwork.shapeBounds(part.shape).insetBy(dx: -part.strokeWidth / 2, dy: -part.strokeWidth / 2)
                    .insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack).contains(box) && !cover.isEmpty
            }
            let smallest = covers.min { area(art.parts[$0]) < area(art.parts[$1]) }
            if let smallest, let cover = art.parts[smallest].name { filled.insert(plain(cover)) }
        }
        guard !filled.isEmpty else { return steps }
        for cover in filled { svg = whiteFill(on: cover, in: svg) }
        object["svg"] = .string(svg)
        var out = steps
        out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        return out
    }

    private static func area(_ part: SVGArtwork.Part) -> CGFloat {
        let box = SVGArtwork.shapeBounds(part.shape)
        return box.width * box.height
    }

    /// `svg` with the element whose id reads as `name` filled white.
    static func whiteFill(on name: String, in svg: String) -> String {
        var text = svg
        var from = text.startIndex
        while let tag = text.range(of: #"<[A-Za-z]+\b[^>]*>"#, options: .regularExpression, range: from..<text.endIndex) {
            let element = String(text[tag])
            from = tag.upperBound
            guard let id = element.range(of: #"\bid="([^"]*)""#, options: .regularExpression),
                  plain(String(element[id]).dropFirst(4).dropLast().description) == name, !element.hasPrefix("<g") else { continue }
            var made = element.replacingOccurrences(of: #"\sfill="[^"]*""#, with: "", options: .regularExpression)
            if let space = made.firstIndex(of: " ") { made.insert(contentsOf: " fill=\"#FFFFFF\"", at: space) }
            text.replaceSubrange(tag, with: made)
            return text
        }
        return text
    }

    /// The most of `travel`, from none to all of it, that keeps `box` inside `room`.
    static func share(of travel: CGVector, keeping box: CGRect, inside room: CGRect) -> CGFloat {
        var most: CGFloat = 1
        if travel.dx > 0 { most = min(most, (room.maxX - box.maxX) / travel.dx) }
        if travel.dx < 0 { most = min(most, (room.minX - box.minX) / travel.dx) }
        if travel.dy > 0 { most = min(most, (room.maxY - box.maxY) / travel.dy) }
        if travel.dy < 0 { most = min(most, (room.minY - box.minY) / travel.dy) }
        return max(0, most)
    }

    /// The least of `travel`, at least all of it, that takes `box` wholly off `room`.
    static func share(of travel: CGVector, clearing box: CGRect, of room: CGRect) -> CGFloat {
        var least = CGFloat.infinity
        if travel.dx > 0 { least = min(least, (room.maxX - box.minX) / travel.dx) }
        if travel.dx < 0 { least = min(least, (room.minX - box.maxX) / travel.dx) }
        if travel.dy > 0 { least = min(least, (room.maxY - box.minY) / travel.dy) }
        if travel.dy < 0 { least = min(least, (room.minY - box.maxY) / travel.dy) }
        return least.isFinite ? max(1, least) : 1
    }

    /// A place on the grid as a person would write it.
    static func rounded(_ value: CGFloat) -> Double { (Double(value) * 1000).rounded() / 1000 }

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
        // The file draws a line from one end (`MotionSVG`), and a line keyed
        // on its start un-draws from the start: wifi's waves went away one by
        // one and came back together (the eval, 2026-11-08).
        if arguments["property"]?.stringValue == MotionProperty.trimStart.rawValue {
            return "Not planned: a line drawing itself is keyed on trimEnd alone: 0 is none of it drawn, 100 all of it."
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

    /// The values that turn about a pivot: a flat turn and the two folds.
    static let turns: Set<String> = [MotionProperty.rotation.rawValue, MotionProperty.rotationX.rawValue, MotionProperty.rotationY.rawValue]

    /// A key's arguments as far as planning can tidy them: a pivot only ever
    /// means something to a turn, and the model adds one to a scale.
    static func tidied(_ arguments: AgentJSON) -> AgentJSON {
        guard var object = arguments.objectValue, !turns.contains(arguments["property"]?.stringValue ?? "") else { return arguments }
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
            if AskMotion.turns.contains(property ?? "") { return (a - b).truncatingRemainder(dividingBy: 360) == 0 }
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

    /// "trash's position starts at x 12 y 14, where it was drawn", for keys
    /// written as where the part is on the grid rather than how far it moved:
    /// the part lands that far again from where it was drawn, often off the
    /// icon (2026-11-08, the trash of the user's story keyed at x 12 y 14).
    private static func placedWhereDrawn(_ steps: [AskStep]) -> [String] {
        guard let svg = steps.first(where: { $0.tool == "add_drawing" })?.arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return [] }
        return steps.compactMap { step -> String? in
            guard step.tool == "set_keys", step.arguments["property"]?.stringValue == MotionProperty.position.rawValue,
                  let own = box(of: name(of: step), in: art), let start = timed(step).first.flatMap({ point($0.value) }) else { return nil }
            let middle = CGPoint(x: own.midX, y: own.midY)
            guard hypot(middle.x, middle.y) > 4, hypot(start.x - middle.x, start.y - middle.y) <= 1.5 else { return nil }
            func said(_ value: CGFloat) -> String { value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value) }
            return "\(name(of: step))'s position starts at x \(said(start.x)) y \(said(start.y)), where it was drawn"
        }
    }

    /// A still thing smaller than this across or down is a mark, not
    /// something a turning part could fall into.
    static let solidSide: CGFloat = 4

    /// "lid turning -35 swings into base", for a part keyed on rotation whose
    /// corners, turned to its furthest key about its pivot, land inside
    /// something that stays still and were not inside it at rest: a lid hinged
    /// at its right end and lifted the left end's way drops into the can.
    private static func swingsInto(_ steps: [AskStep]) -> [String] {
        guard let svg = steps.first(where: { $0.tool == "add_drawing" })?.arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return [] }
        var said: [String] = []
        for step in steps where step.tool == "set_keys" && step.arguments["property"]?.stringValue == MotionProperty.rotation.rawValue {
            let moving = AskMotion.plain(name(of: step))
            guard let own = box(of: name(of: step), in: art),
                  let furthest = timed(step).compactMap({ $0.value.doubleValue }).max(by: { abs($0) < abs($1) }), abs(furthest) >= 10,
                  let x = step.arguments["pivot"]?["x"]?.doubleValue, let y = step.arguments["pivot"]?["y"]?.doubleValue else { continue }
            let pivot = AskMotion.isFraction(x, y) ? CGPoint(x: own.minX + own.width * x, y: own.minY + own.height * y) : CGPoint(x: x, y: y)
            let angle = furthest * .pi / 180
            let corners = [CGPoint(x: own.minX, y: own.minY), CGPoint(x: own.maxX, y: own.minY),
                           CGPoint(x: own.minX, y: own.maxY), CGPoint(x: own.maxX, y: own.maxY)]
            let turned = corners.map { corner -> CGPoint in
                let dx = corner.x - pivot.x, dy = corner.y - pivot.y
                return CGPoint(x: pivot.x + dx * cos(angle) - dy * sin(angle), y: pivot.y + dx * sin(angle) + dy * cos(angle))
            }
            // What stays still, as the largest named thing not holding the turning part.
            var still: [String] = []
            for part in art.parts {
                let names = part.groups + [part.name].compactMap { $0 }
                guard !names.contains(where: { AskMotion.plain($0) == moving }) else { continue }
                let holding = Set(art.parts.filter { one in (one.groups + [one.name].compactMap { $0 }).contains { AskMotion.plain($0) == moving } }
                    .flatMap { $0.groups }.map(AskMotion.plain))
                if let unit = names.first(where: { !holding.contains(AskMotion.plain($0)) }), !still.contains(unit) { still.append(unit) }
            }
            for unit in still {
                guard let solid = box(of: unit, in: art), solid.width >= solidSide, solid.height >= solidSide else { continue }
                let inside = solid.insetBy(dx: 1, dy: 1)
                if turned.contains(where: inside.contains), !corners.contains(where: inside.contains) {
                    said.append("\(name(of: step)) turning \(Int(furthest.rounded())) swings into \(unit.lowercased())")
                    break
                }
            }
        }
        return said
    }

    /// The keys of a step by time, each with its value and curve.
    private static func timed(_ step: AskStep) -> [(seconds: Double, value: AgentJSON, curve: String?)] {
        (step.arguments["keys"]?.arrayValue ?? []).compactMap { key in
            guard let seconds = key["seconds"]?.doubleValue, let value = key["value"] else { return nil }
            return (seconds, value, key["curve"]?.stringValue)
        }.sorted { $0.seconds < $1.seconds }
    }

    private static func point(_ value: AgentJSON) -> CGPoint? {
        guard let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// The farthest a journey may go between two keys in less than
    /// `quickest` seconds: past it, the part is there and then gone.
    static let longJourney: CGFloat = 6
    static let quickest = 0.25

    /// "lid travels 9 on the grid in 100 ms", for a part that crosses a long
    /// way between two keys too close together, while it can be seen and not
    /// on a Hold (a jump back to the other side is meant).
    private static func tooQuick(_ step: AskStep, among keyed: [AskStep]) -> String? {
        guard step.arguments["property"]?.stringValue == MotionProperty.position.rawValue else { return nil }
        let keys = timed(step)
        let layer = step.arguments["layer"]?.stringValue
        let fades = keyed.first { $0.arguments["layer"]?.stringValue == layer && $0.arguments["property"]?.stringValue == MotionProperty.opacity.rawValue }
        for (from, to) in zip(keys, keys.dropFirst()) {
            let gap = to.seconds - from.seconds
            guard gap > 0, gap < quickest, from.curve?.caseInsensitiveCompare(AgentKeyCurve.hold) != .orderedSame,
                  let a = point(from.value), let b = point(to.value) else { continue }
            let far = hypot(b.x - a.x, b.y - a.y)
            guard far >= longJourney else { continue }
            if let fades, opacity(fades, at: from.seconds) < 10, opacity(fades, at: to.seconds) < 10 { continue }
            return "\(name(of: step)) travels \(Int(far.rounded())) on the grid in \(Int((gap * 1000).rounded())) ms"
        }
        return nil
    }

    /// An opacity at `seconds`, straight between its keys.
    private static func opacity(_ step: AskStep, at seconds: Double) -> Double {
        let keys = timed(step).compactMap { key in key.value.doubleValue.map { (key.seconds, $0) } }
        guard let first = keys.first else { return 100 }
        if seconds <= first.0 { return first.1 }
        for (a, b) in zip(keys, keys.dropFirst()) where seconds <= b.0 {
            return b.0 - a.0 <= 0 ? b.1 : a.1 + (b.1 - a.1) * (seconds - a.0) / (b.0 - a.0)
        }
        return keys.last?.1 ?? 100
    }

    /// "body's rotation changes by only 2", for a motion that moves but by
    /// less than an icon shows: a shake of a third of a grid unit reads as still.
    private static func tooSmall(_ step: AskStep) -> String? {
        let property = step.arguments["property"]?.stringValue ?? ""
        let keys = timed(step)
        guard let first = keys.first?.value, keys.count > 1 else { return nil }
        let reach: Double
        let least: Double
        switch MotionProperty(rawValue: property) {
        case .position?:
            guard let start = point(first) else { return nil }
            reach = keys.compactMap { point($0.value) }.map { Double(hypot($0.x - start.x, $0.y - start.y)) }.max() ?? 0
            least = 0.75
        case .rotation?:
            guard let start = first.doubleValue else { return nil }
            reach = keys.compactMap { $0.value.doubleValue }.map { abs($0 - start) }.max() ?? 0
            least = 4
        case .scale?:
            guard let start = first.doubleValue else { return nil }
            reach = keys.compactMap { $0.value.doubleValue }.map { abs($0 - start) }.max() ?? 0
            least = 6
        default:
            return nil
        }
        guard reach > 0, reach < least else { return nil }
        let said = reach < 1 ? String(format: "%.1f", reach) : String(Int(reach.rounded()))
        return "\(name(of: step))'s \(property) changes by only \(said)"
    }

    /// The box of a part on its drawing's grid, stroke included.
    static func box(of part: String, in art: SVGArtwork) -> CGRect? {
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
        // A fold squeezes the part toward its hinge and, past edge on, lays
        // it out the other side, as far as it reached on this one.
        let folds = [MotionProperty.rotationX.rawValue: true, MotionProperty.rotationY.rawValue: false]
        if let level = folds[step.arguments["property"]?.stringValue ?? ""] {
            let angles = keys.compactMap { $0["value"]?.doubleValue }
            if let least = angles.min(), let most = angles.max() {
                for degrees in Array(stride(from: least, through: most, by: 15)) + [most] {
                    let share = cos(degrees * .pi / 180)
                    for corner in corners {
                        let folded = level ? CGPoint(x: corner.x, y: pivot.y + (corner.y - pivot.y) * share)
                            : CGPoint(x: pivot.x + (corner.x - pivot.x) * share, y: corner.y)
                        far = far.union(CGRect(origin: folded, size: .zero))
                    }
                }
            }
        }
        return far
    }

    /// The furthest `keyed` takes `part` alone, at rest where it travels from:
    /// its box and what its keys in `keyed` do to it. Nil when no part is called that.
    static func reach(of keyed: [AskStep], in art: SVGArtwork, only part: String) -> CGRect? {
        let plain = AskMotion.plain(part)
        guard let box = box(of: part, in: art) else { return nil }
        return keyed.filter { step in
            (step.arguments["layer"]?.stringValue).flatMap(AskMotion.partReference).map { AskMotion.plain($0.part) == plain } ?? false
        }.reduce(box) { $0.union(reach(of: $1, box: box)) }
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
        let placed = placedWhereDrawn(steps)
        if !placed.isEmpty {
            said.append("\(placed.joined(separator: "; ")): position is how far it has moved from where it was drawn, so where it was drawn is x 0 y 0. Call set_keys again with replace true, each value less where it was drawn.")
        }
        let into = swingsInto(steps)
        if !into.isEmpty {
            said.append("\(into.joined(separator: "; ")): turned that way it falls into what stays still. Turn it the other way: set_keys again with replace true, every rotation value with the opposite sign.")
        }
        let quick = keyed.compactMap { tooQuick($0, among: keyed) }
        if !quick.isEmpty {
            said.append("\(quick.joined(separator: "; ")): too quick to see, it is there and then gone. Call set_keys again with replace true for it, that journey over 300 to 500 ms.")
        }
        let small = keyed.compactMap(tooSmall)
        if !small.isEmpty {
            said.append("\(small.joined(separator: "; ")): too small to see at icon size. A shake or a nudge is at least 1 on the grid or 6 degrees, a beat or a squash at least 10 percent. Call set_keys again with replace true for it.")
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
