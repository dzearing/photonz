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
    static let beatsReviewAsk = """
        Before it lands, go through the beats of your design in the order the request tells them. Each beat must \
        be keyed and long enough to see (200 ms at the least, a journey 300 to 600 ms), each starting as the one \
        that causes it ends. Key any beat nothing moves for yet, or set_keys again with replace true for one too \
        quick or too small to see. If a beat cannot be shown, finish with one last line, Left out: and those beats \
        in a few words. When every beat is there, finish with: Left out: nothing.
        """

    /// Said under where the parts are.
    static let touchRule = """
        A beat where one part hits, bounces off, knocks, pushes or lands on another needs the two touching at \
        that beat's key: give that position key "touches" with the other part's id and it is placed against it. \
        What goes into something ends inside it: where this says touching nothing, move the keys until it says \
        touching that part.
        """

    /// The beats review for `steps`: the ask, and where the keys put each
    /// moving part (`whereParts`) when anything is keyed.
    static func beatsReview(for steps: [AskStep]) -> String {
        guard let parts = whereParts(steps) else { return beatsReviewAsk }
        return "\(beatsReviewAsk)\n\n\(parts)\n\(touchRule)"
    }

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
        draw it before that part in the svg, as an outline like the rest, with no fill on either. What is thrown, \
        dropped or put into another part is drawn where it is first seen, away from that part and never inside \
        it, and its keys carry it in. Parts that move together share a <g id="what-they-are">, \
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
        what stays still, the hinge or centre of any turn and which way it turns, and any extra pieces, where each \
        is first seen (what goes into something is first seen outside it) and where it goes; 3) the beats in the order the request tells them, each with its time in ms, across a lap that ends \
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
        var words = AskConversation.withoutThinking(answer)
        // A model that goes on to draw keeps the design it wrote before the
        // drawing: the user's trash of 2026-11-09 lost a whole design that way
        // and was planned with none.
        if let drawing = ["<tool_call", "```", "<svg"].compactMap({ words.range(of: $0)?.lowerBound }).min() {
            words = String(words[..<drawing])
        }
        words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
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
        up, keyed as that one group from scale 30 to 100 and opacity 100 to 0, are two calls. What breaks in two shows no line where it will part until it breaks: \
        each half is drawn as an open path, the part of the outline it carries and nothing along the break. At the \
        break the halves move apart, 1 or 2 on the grid each, as they tilt away, never still joined at a point. A part that swings on one point, seen side on (a door seen from above, an arm), \
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
        are gone before it is, never left on their own; what it leaves behind where it was (smoke, dust) grows \
        there, scale 30 to 100, as it fades over 400 to 800 ms.
        - A story of several beats plays them in the order told, one after another, each long enough to read: \
        200 ms at the least, a journey 300 to 600 ms. What a beat causes starts as that beat ends, at the key where \
        the two parts touch: that position key says "touches" with the other part's id. A beat the words count \
        (twice, three times) happens exactly that many times, each seen apart. A bounce is a hop: the part goes up \
        at least 2 on the grid and comes back down, squashing a little as it lands; a pulse in size alone reads \
        as a beat, not a bounce. The beats fill most of a 2 to 4 second lap with a short rest at its end, never a burst \
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

    // MARK: Keys written again

    /// `steps` with each value's keys as they will play: keys written again
    /// with replace true drop the ones before them for that value, and keys
    /// written again without it join them, a key at the same moment
    /// rewritten (what `set_keys` does when it runs). A hinge said before and
    /// not again stays. The checks and the room read this, never the keys a
    /// replace took away: on 2026-11-08 the trash of the user's story was sent
    /// back three times for keys it had already replaced, and its drawing was
    /// shrunk for a journey that never played.
    public static func folded(_ steps: [AskStep]) -> [AskStep] {
        fold(steps).steps
    }

    /// `folded` for the plan that lands, only when every step after a
    /// dropped one makes nothing a later step points at by number (keys and
    /// timing make nothing), so `$N` still means what it meant.
    public static func landingFolded(_ steps: [AskStep]) -> [AskStep] {
        let (out, dropped) = fold(steps)
        guard let first = dropped.min() else { return steps }
        let makesNothing: Set<String> = ["set_keys", "set_timing"]
        return steps[(first + 1)...].allSatisfy { makesNothing.contains($0.tool) } ? out : steps
    }

    private static func fold(_ steps: [AskStep]) -> (steps: [AskStep], dropped: [Int]) {
        func value(of step: AskStep) -> String? {
            guard step.tool == "set_keys" else { return nil }
            return [step.arguments["layer"]?.stringValue ?? "", step.arguments["property"]?.stringValue ?? "",
                    step.arguments["effect"]?.stringValue ?? ""].joined(separator: "\u{1F}")
        }
        var out: [AskStep?] = steps
        var dropped: [Int] = []
        var latest: [String: Int] = [:]
        for (at, step) in steps.enumerated() {
            guard let own = value(of: step) else { continue }
            defer { latest[own] = at }
            guard let before = latest[own], let earlier = out[before], var object = step.arguments.objectValue else { continue }
            if object["pivot"] == nil, let pivot = earlier.arguments["pivot"] { object["pivot"] = pivot }
            if step.arguments["replace"]?.boolValue != true {
                let near = Double(PropertyKeys.nearMS) / 1000
                let new = step.arguments["keys"]?.arrayValue ?? []
                let newTimes = new.compactMap { $0["seconds"]?.doubleValue }
                let kept = (earlier.arguments["keys"]?.arrayValue ?? []).filter { key in
                    guard let seconds = key["seconds"]?.doubleValue else { return false }
                    return !newTimes.contains { abs($0 - seconds) <= near }
                }
                object["keys"] = .array((kept + new).sorted { ($0["seconds"]?.doubleValue ?? 0) < ($1["seconds"]?.doubleValue ?? 0) })
                if let replace = earlier.arguments["replace"] { object["replace"] = replace }
            }
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
            out[before] = nil
            dropped.append(before)
        }
        return (out.compactMap { $0 }, dropped)
    }

    // MARK: Where the parts are

    /// The most moments `whereParts` lists, so a busy lap stays a short read.
    static let mostMoments = 14

    /// Where the keys put each moving part at each of their keys, on the
    /// drawing's grid, and what it touches or is inside, as lines for the
    /// model; nil when nothing is keyed. Boxes turned, grown and moved as the
    /// keys say (in a straight line between keys, a Hold standing still), a
    /// part inside a keyed group carried with it. On 2026-11-08 the look said
    /// the trash never touched the lid it should bounce off, and the model
    /// sent the same keys again: in numbers the miss is plain.
    public static func whereParts(_ planned: [AskStep]) -> String? {
        // Keys that say what they touch are shown where they will land.
        guard let lap = Lap(touchesPlaced(planned)), !lap.movers.isEmpty else { return nil }
        let keyed = lap.keyed, movers = lap.movers
        let near = Double(PropertyKeys.nearMS) / 1000
        var moments: [Double] = []
        for seconds in keyed.flatMap({ AskMotionCheck.timed($0).map(\.seconds) }).sorted() where !moments.contains(where: { abs($0 - seconds) <= near }) {
            moments.append(seconds)
        }
        func said(_ value: CGFloat) -> String {
            let tenth = (value * 10).rounded() / 10
            if tenth == 0 { return "0" }
            return tenth == tenth.rounded() ? String(Int(tenth)) : String(format: "%.1f", Double(tenth))
        }
        func time(_ seconds: Double) -> String {
            let hundredth = (seconds * 100).rounded() / 100
            return hundredth == hundredth.rounded() ? String(Int(hundredth)) : String(format: "%g", hundredth)
        }
        var lines: [String] = []
        for seconds in moments.prefix(mostMoments) {
            var said_: [String] = []
            for name in movers {
                guard let (quad, seen) = lap.placed(name, at: seconds) else { continue }
                let label = name.lowercased()
                guard seen else { said_.append("\(label) hidden"); continue }
                let xs = quad.map(\.x), ys = quad.map(\.y)
                var words = label
                let degrees = lap.value(name, .rotation, at: seconds)?.doubleValue ?? 0
                if abs(degrees) >= 1 { words += " turned \(said(CGFloat(degrees))),"}
                let grow = lap.value(name, .scale, at: seconds)?.doubleValue ?? 100
                if abs(grow - 100) >= 1 { words += " at \(said(CGFloat(grow))) percent," }
                words += " x \(said(xs.min() ?? 0)) to \(said(xs.max() ?? 0)), y \(said(ys.min() ?? 0)) to \(said(ys.max() ?? 0))"
                let others = lap.others(of: name, at: seconds)
                if let around = others.first(where: { other in quad.allSatisfy { Self.inside($0, other.quad) } }) {
                    words += ", inside \(around.name.lowercased())"
                } else {
                    let touching = others.filter { Self.meet(quad, $0.quad) }.map { $0.name.lowercased() }
                    words += touching.isEmpty ? ", touching nothing" : ", touching \(touching.joined(separator: " and "))"
                }
                said_.append(words)
            }
            lines.append("\(time(seconds)) s: \(said_.joined(separator: "; "))")
        }
        return "Where your keys put each moving part, on your drawing's grid (x across, y down), at each key:\n"
            + lines.joined(separator: "\n")
    }

    /// Whether `point` is inside the convex outline `quad`, edges included.
    static func inside(_ point: CGPoint, _ quad: [CGPoint]) -> Bool {
        var sign: CGFloat = 0
        for (a, b) in zip(quad, quad.dropFirst() + quad.prefix(1)) {
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) < 1e-6 { continue }
            if sign == 0 { sign = cross > 0 ? 1 : -1 } else if (cross > 0 ? 1 : -1) != sign { return false }
        }
        return true
    }

    /// Whether two convex outlines overlap or come within a quarter of a
    /// grid step of each other (separating axes).
    static func meet(_ a: [CGPoint], _ b: [CGPoint], within slack: CGFloat = edgeTouch) -> Bool {
        for quad in [a, b] {
            for (p, q) in zip(quad, quad.dropFirst() + quad.prefix(1)) {
                let length = hypot(q.x - p.x, q.y - p.y)
                guard length > 1e-6 else { continue }
                let axis = CGPoint(x: -(q.y - p.y) / length, y: (q.x - p.x) / length)
                let ta = a.map { $0.x * axis.x + $0.y * axis.y }, tb = b.map { $0.x * axis.x + $0.y * axis.y }
                guard let a0 = ta.min(), let a1 = ta.max(), let b0 = tb.min(), let b1 = tb.max() else { continue }
                if a1 < b0 - slack || b1 < a0 - slack { return false }
            }
        }
        return true
    }

    /// How close two parts come to count as touching, on the grid.
    static let edgeTouch: CGFloat = 0.25

    // MARK: Room for the motion

    /// The most a drawing's viewBox grows to make room. Further and the icon
    /// is too small to read, and whatever flies that far is meant to leave.
    public static let mostRoom: CGFloat = 1.4
    /// The margin an icon keeps on its grid, a share of the side: one unit
    /// of 24. A drawing whose ink at rest reaches nearer the edge than three
    /// quarters of that is cut by its frame (a paper plane's speed lines lost
    /// their ends to the left edge, the eval, 2026-11-08), so its frame grows
    /// to give it that margin, by `mostRest` at most. One drawn on the usual
    /// live area is left as it is.
    static let restMargin: CGFloat = 1.0 / 24
    static let mostRest: CGFloat = 1.2

    /// `steps` with the drawing's viewBox widened about its middle to hold
    /// everything its keys do, so nothing is cut off by the frame. A vector
    /// tool like any other: it reads boxes and keys and knows nothing of what
    /// they are. Asked to fit instead, the model shrank what it had designed:
    /// a flap's swing from 180 to 90 and a letter's rise from 3 to 1, a round of
    /// the plan each time (the eval, 2026-11-06).
    public static func fitted(_ planned: [AskStep]) -> [AskStep] {
        let (steps, view) = roomFitted(swingsFitted(foldsOpen(foldsLand(landingFolded(planned)))))
        return view.map { marksGo(comesBack(edgeHides(thrownIn(steps, view: $0), view: $0), view: $0), view: $0) } ?? steps
    }

    /// Below this opacity a part is out of sight.
    static let unseen = 5.0

    /// `steps` with every jump (a Hold into a different value) that happens
    /// while its part is seen moved to the last moment before it that the
    /// part was out of sight. The plane of 2026-11-09 was gone at 1.1 s,
    /// faded back in from 1.3 s still tipped -15 degrees and snapped level at
    /// the lap's end, "visibly snaps when the loop restarts" in four looks of
    /// four. Only a part with its own opacity keys, and only a jump it has an
    /// unseen moment before; time and values only.
    public static func jumpsUnseen(_ steps: [AskStep]) -> [AskStep] {
        func layer(_ step: AskStep) -> String? { step.arguments["layer"]?.stringValue }
        let fades = Dictionary(steps.filter { $0.tool == "set_keys" && $0.arguments["property"]?.stringValue == MotionProperty.opacity.rawValue }
            .compactMap { step in layer(step).map { ($0, step) } }, uniquingKeysWith: { _, last in last })
        return steps.map { step in
            guard step.tool == "set_keys", let name = layer(step), let fade = fades[name],
                  step.arguments["property"]?.stringValue != MotionProperty.opacity.rawValue,
                  var object = step.arguments.objectValue else { return step }
            func seen(_ at: Double) -> Bool { (AskMotionCheck.value(of: fade, at: at)?.doubleValue ?? 100) > unseen }
            var keys = AskMotionCheck.timed(step)
            guard keys.count == step.arguments["keys"]?.arrayValue?.count else { return step }
            var changed = false
            var index = 0
            while index < keys.count - 1 {
                defer { index += 1 }
                let (from, to) = (keys[index], keys[index + 1])
                guard from.curve?.caseInsensitiveCompare(AgentKeyCurve.hold) == .orderedSame, from.value != to.value,
                      seen(to.seconds) else { continue }
                // The last unseen moment between them, walking back from the jump.
                var moment = to.seconds - leavingStep
                while moment > from.seconds + 0.0005, seen(moment) { moment -= leavingStep }
                guard moment > from.seconds + 0.0005 else { continue }
                let at = Double(rounded(CGFloat(moment)))
                // Unseen until a key's width before the jump: it comes into
                // sight already there, and a key that close would be one key
                // with it, which the app refuses with the whole step (the
                // trash of 2026-11-09 never moved).
                let width = Double(PropertyKeys.nearMS) / 1000
                guard to.seconds - at > width, at - from.seconds > width else { continue }
                keys.insert((at, to.value, AgentKeyCurve.hold), at: index + 1)
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

    /// A moving icon's plan as it lands: folds timed first, since a fold's
    /// back face shows from the moment it turns edge on, read off its keys
    /// as they will play (on 2026-11-09 the back face was timed off the keys
    /// before a close was slowed, and the flap vanished while still open);
    /// then hinges shared, what comes out put behind, and room made. Before
    /// any of it, a seen hold moves and a hit starts what it hits
    /// and what travels is seen the whole way (`holdsMove`, `travelsSeen`,
    /// `hitStarts`), while the keys still say what they touch, on swings
    /// already narrowed to the room (`swingsFitted`): a lid narrowed after
    /// the trash was placed against it stood in the trash's way.
    public static func planned(_ steps: [AskStep]) -> [AskStep] {
        let timed = foldsOpen(foldsLand(touchesPlaced(hitStarts(travelsSeen(holdsMove(drawnNotFaded(swingsFitted(landingFolded(touchesKept(steps))))))))))
        let made = fitted(comesClear(hidden(hingesShared(timed))))
        // Hinges again for the room made, if any: lines and corner rounds
        // keep their size on the final grid as the drawing shrinks.
        let grow = viewBoxWidth(made).flatMap { after in viewBoxWidth(timed).map { after / $0 } } ?? 1
        guard grow > 1.001 else { return jumpsUnseen(made) }
        return jumpsUnseen(fitted(comesClear(hidden(hingesShared(timed, grow: grow)))))
    }

    /// The width of the drawing's viewBox, if it has one.
    static func viewBoxWidth(_ steps: [AskStep]) -> CGFloat? {
        guard let svg = steps.first(where: { $0.tool == "add_drawing" })?.arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return nil }
        return art.viewBox?.width
    }

    /// `fitted` before its marks go: the steps with the room made, and the
    /// frame they play in, if the drawing has one.
    static func roomFitted(_ steps: [AskStep]) -> ([AskStep], CGRect?) {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox,
              var object = steps[index].arguments.objectValue else { return (steps, nil) }
        let slack = AskMotionCheck.edgeSlack
        let reach = AskMotionCheck.reach(of: steps.filter { $0.tool == "set_keys" }, in: art)
        // At rest it keeps clear of the edge, as an icon on its grid does,
        // and so does what its keys do inside the frame (a flap folded open
        // put its tip's line on the top edge, the eval, 2026-11-09).
        var still = art.parts.map { SVGArtwork.shapeBounds($0.shape).insetBy(dx: -$0.strokeWidth / 2, dy: -$0.strokeWidth / 2) }
            .reduce(CGRect.null) { $0.union($1) }
        if !reach.isNull, view.insetBy(dx: -slack, dy: -slack).contains(reach) { still = still.union(reach) }
        let margin = restMargin * view.width
        let cut = !still.isNull && !view.insetBy(dx: margin * 0.75, dy: margin * 0.75).contains(still)
        let past = !reach.isNull && !view.insetBy(dx: -slack, dy: -slack).contains(reach)
        guard cut || past else { return (steps, view) }
        // What the frame has to hold: the ink at rest with an icon's margin,
        // and what the keys do with a little slack.
        func holding(_ reach: CGRect) -> CGRect {
            var needed = still.isNull ? CGRect.null : still.insetBy(dx: -margin, dy: -margin)
            if !reach.isNull { needed = needed.union(reach.insetBy(dx: -slack, dy: -slack)) }
            return needed
        }
        let most = view.width * (past ? mostRoom : mostRest)
        var out = steps
        var box = Self.room(holding: holding(reach), in: view, least: view.width, most: most)
        if past, !box.insetBy(dx: -slack, dy: -slack).contains(reach) {
            // Something travels past all the room there is: it is meant to
            // leave, and leaves whole rather than stopping half over the edge.
            (out, box) = leaving(steps, in: art, most: box, view: view, resting: holding(.null), mostSide: most)
        }
        guard abs(box.minX - view.minX) > 0.0005 || abs(box.minY - view.minY) > 0.0005 || abs(box.width - view.width) > 0.0005 else {
            return (out, view)
        }
        let said = [box.minX, box.minY, box.width, box.height].map { String(format: "%.3f", Double($0)) }.joined(separator: " ")
        guard let found = svg.range(of: #"viewBox="[^"]*""#, options: .regularExpression) else { return (out, view) }
        object["svg"] = .string(svg.replacingCharacters(in: found, with: "viewBox=\"\(said)\""))
        out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        return (out, box)
    }

    /// How far the room's middle may sit from the drawing's, a share of its side.
    static let offMiddle: CGFloat = 1.0 / 12

    /// The smallest square of at least `least` and at most `most` across that
    /// holds `needed`, as near the middle of `view` as that allows. Room is
    /// taken where the drawing leaves it before the drawing is made smaller:
    /// a lid that swings past the top of a can drawn low has the space below
    /// the can. When nothing has to grow it moves by whole units, so a drawing
    /// made on its grid stays on it. Geometry only, true of any drawing.
    static func room(holding needed: CGRect, in view: CGRect, least: CGFloat, most: CGFloat) -> CGRect {
        guard !needed.isNull else { return view }
        // An icon at rest sits near the middle of its frame: the room moves
        // off the middle by a twelfth at most, and grows for the rest (a
        // look at the trash of 2026-11-11 called it off centre, padded
        // unevenly, when it moved by more than two units).
        let off = offMiddle * view.width
        func span(_ low: CGFloat, _ high: CGFloat, _ middle: CGFloat) -> CGFloat {
            let centre = min(max((low + high) / 2, middle - off), middle + off)
            return 2 * max(centre - low, high - centre)
        }
        let side = min(max(least, span(needed.minX, needed.maxX, view.midX), span(needed.minY, needed.maxY, view.midY)), max(least, most))
        func along(_ low: CGFloat, _ high: CGFloat, middle: CGFloat) -> CGFloat {
            let centred = middle - side / 2
            // The frame's start that keeps `low` and `high` in, nearest the middle.
            let (first, last) = (high - side, low)
            // More than all the room there is: about the middle, and what
            // goes further is meant to leave (`leaving`).
            guard first <= last + 0.0005 else { return centred }
            var start = min(max(centred, first), last)
            if side <= view.width + 0.0005 {
                // Whole units from the grid's own frame, still holding all of it.
                let offset = start - (middle - view.width / 2)
                let whole = offset.rounded()
                let nearer = [whole, offset.rounded(.down), offset.rounded(.up)]
                    .first { (middle - view.width / 2) + $0 >= first - 0.0005 && (middle - view.width / 2) + $0 <= last + 0.0005 }
                if let nearer { start = (middle - view.width / 2) + nearer }
            }
            return start
        }
        return CGRect(x: along(needed.minX, needed.maxX, middle: view.midX), y: along(needed.minY, needed.maxY, middle: view.midY),
                      width: side, height: side)
    }

    /// A fold this far from its rest is a real opening, and its way home a
    /// landing worth seeing.
    static let foldOpen = 90.0
    /// Within this of its rest a fold is all but flat on: seen straight on,
    /// as an icon is, it is the card at 94 percent or more of itself.
    static let foldNearRest = 20.0
    /// The least a fold takes to land so the eye follows it home, and what it
    /// is given when it can borrow the stillness after it. 300 and 400 ms
    /// until 2026-11-09, when a close of 400 ms still read as "snaps shut in
    /// one frame" on a sheet of frames 160 ms apart, nine looks of nine.
    static let foldLandingLeast = 0.45
    static let foldLanding = 0.55
    /// The pace a fold of 90 degrees or more opens and lands on: even. Seen
    /// straight on, as an icon is, a fold shows the cosine of its angle, so
    /// an even turn already starts and lands softly and passes edge on
    /// quickly. Ease in out on the angle bunched every visible change into
    /// the middle of the turn: on a sheet of frames 133 ms apart the
    /// envelope of 2026-11-09 went from wide open to gone to nearly shut,
    /// "the flap vanishes, then pops back in closed instead of folding shut"
    /// in nine looks of nine.
    static let foldPace = EasingCurve.linear.title

    /// `steps` with every fold that comes home landing on its rest, seen. A
    /// flap shut in 200 ms on Ease in, then 8 degrees past flat, reached the
    /// file at full speed into its V: a shallow V one frame, the whole V the
    /// next, and the bounce past flat cannot be seen at all, since a card
    /// tipped 8 degrees either way looks the same straight on (the eval,
    /// 2026-11-08). So on the way home from an opening of 90 degrees or more,
    /// keys within 20 degrees of rest before it get there go, the run comes
    /// home at an even pace (`foldPace`), and a landing under 450 ms
    /// takes up to 550 ms from the stillness after it. Geometry and time
    /// only: nothing knows what folds.
    public static func foldsLand(_ steps: [AskStep]) -> [AskStep] {
        let folds: Set<String> = [MotionProperty.rotationX.rawValue, MotionProperty.rotationY.rawValue]
        // A lap that loops comes back to its first key, the rest: a landing
        // that is a fold's last key has the time to the lap's end after it
        // (the envelope of 2026-11-09 shut in 300 ms as its last key, "snaps
        // shut" in nine looks of nine).
        let timing = steps.last { $0.tool == "set_timing" }
        let lapEnd = timing?.arguments["loop"]?.boolValue == false ? nil : timing?.arguments["seconds"]?.doubleValue
        return steps.map { step in
            guard step.tool == "set_keys", folds.contains(step.arguments["property"]?.stringValue ?? ""),
                  var object = step.arguments.objectValue else { return step }
            var keys = (step.arguments["keys"]?.arrayValue ?? []).compactMap { key -> (seconds: Double, value: Double, json: [String: AgentJSON])? in
                guard let json = key.objectValue, let seconds = key["seconds"]?.doubleValue,
                      let value = key["value"]?.doubleValue else { return nil }
                return (seconds, value, json)
            }.sorted { $0.seconds < $1.seconds }
            guard keys.count == step.arguments["keys"]?.arrayValue?.count, let rest = keys.first?.value else { return step }
            func atRest(_ value: Double) -> Bool { abs(value - rest) < 0.5 }
            func curve(_ index: Int) -> String? { keys[index].json["curve"]?.stringValue }
            var changed = false
            var index = 0
            while index < keys.count - 1 {
                defer { index += 1 }
                guard abs(keys[index].value - rest) >= foldOpen,
                      curve(index)?.caseInsensitiveCompare(AgentKeyCurve.hold) != .orderedSame else { continue }
                // Its way home: the keys all but flat before it gets there.
                var home = index + 1
                while home < keys.count, !atRest(keys[home].value), abs(keys[home].value - rest) <= foldNearRest { home += 1 }
                guard home < keys.count, atRest(keys[home].value) else { continue }
                if home > index + 1 {
                    keys.removeSubrange((index + 1)..<home)
                    home = index + 1
                    changed = true
                }
                if curve(index)?.caseInsensitiveCompare(foldPace) != .orderedSame {
                    keys[index].json["curve"] = .string(foldPace)
                    changed = true
                }
                // Too quick to follow home: it takes its time from the
                // stillness after it, if there is any.
                let start = keys[index].seconds
                guard keys[home].seconds - start < foldLandingLeast - 0.0005 else { continue }
                if home == keys.count - 1, let lapEnd, lapEnd > keys[home].seconds + 0.0005 {
                    keys[home].seconds = Double(rounded(CGFloat(min(start + foldLanding, lapEnd))))
                    keys[home].json["seconds"] = .number(keys[home].seconds)
                    changed = true
                    continue
                }
                guard home + 1 < keys.count, atRest(keys[home + 1].value) else { continue }
                let landed = min(start + foldLanding, keys[home + 1].seconds)
                if landed >= keys[home + 1].seconds - 0.0005 {
                    keys.remove(at: home)
                } else {
                    keys[home].seconds = Double(rounded(CGFloat(landed)))
                    keys[home].json["seconds"] = .number(keys[home].seconds)
                }
                changed = true
            }
            guard changed else { return step }
            object["keys"] = .array(keys.map { .object($0.json) })
            return AskStep(tool: step.tool, arguments: .object(object))
        }
    }

    /// The least a fold takes to open so the eye sees it turn, and what it is
    /// given when it can borrow the stillness before it.
    static let foldOpeningLeast = 0.45
    static let foldOpening = 0.55

    /// `steps` with every fold that opens 90 degrees or more from rest seen
    /// doing it. The envelope of 2026-11-09 nudged its flap 10 degrees and
    /// then opened it the rest of the way in 200 ms: frames 160 ms apart showed
    /// it shut and then open, "snaps open" in nine looks of nine. So on the
    /// way out, keys within 20 degrees of rest after it leaves go (a card
    /// tipped that little looks flat straight on), an opening under 450 ms
    /// starts earlier, out of the stillness before it, to take up to 550 ms
    /// (and, short of that, ends later, out of the stillness after), and it turns at an even pace (`foldPace`). The
    /// mirror of `foldsLand`; geometry and time only.
    public static func foldsOpen(_ steps: [AskStep]) -> [AskStep] {
        let folds: Set<String> = [MotionProperty.rotationX.rawValue, MotionProperty.rotationY.rawValue]
        return steps.map { step in
            guard step.tool == "set_keys", folds.contains(step.arguments["property"]?.stringValue ?? ""),
                  var object = step.arguments.objectValue else { return step }
            var keys = (step.arguments["keys"]?.arrayValue ?? []).compactMap { key -> (seconds: Double, value: Double, json: [String: AgentJSON])? in
                guard let json = key.objectValue, let seconds = key["seconds"]?.doubleValue,
                      let value = key["value"]?.doubleValue else { return nil }
                return (seconds, value, json)
            }.sorted { $0.seconds < $1.seconds }
            guard keys.count == step.arguments["keys"]?.arrayValue?.count, let rest = keys.first?.value else { return step }
            func atRest(_ value: Double) -> Bool { abs(value - rest) < 0.5 }
            var changed = false
            var open = 1
            while open < keys.count {
                defer { open += 1 }
                guard abs(keys[open].value - rest) >= foldOpen else { continue }
                // Back to where it left rest, past any nudge too small to see.
                var start = open - 1
                while start > 0, !atRest(keys[start].value), abs(keys[start].value - rest) <= foldNearRest { start -= 1 }
                guard atRest(keys[start].value), keys[open].seconds - keys[start].seconds < foldOpeningLeast - 0.0005 else { continue }
                if open > start + 1 {
                    keys.removeSubrange((start + 1)..<open)
                    open = start + 1
                }
                let from = max(start > 0 && atRest(keys[start - 1].value) ? keys[start - 1].seconds : keys[start].seconds,
                               keys[open].seconds - foldOpening)
                if start > 0, atRest(keys[start - 1].value), from <= keys[start - 1].seconds + 0.0005 {
                    keys.remove(at: start)
                    start -= 1
                    open -= 1
                } else {
                    keys[start].seconds = Double(rounded(CGFloat(from)))
                    keys[start].json["seconds"] = .number(keys[start].seconds)
                }
                // Still too quick, it takes the rest from the stillness after it.
                if keys[open].seconds - keys[start].seconds < foldOpeningLeast - 0.0005, open + 1 < keys.count,
                   abs(keys[open + 1].value - keys[open].value) < 0.5 {
                    let opened = min(keys[start].seconds + foldOpening, keys[open + 1].seconds)
                    if opened >= keys[open + 1].seconds - 0.0005 {
                        keys.remove(at: open)
                    } else {
                        keys[open].seconds = Double(rounded(CGFloat(opened)))
                        keys[open].json["seconds"] = .number(keys[open].seconds)
                    }
                }
                keys[start].json["curve"] = .string(foldPace)
                changed = true
            }
            guard changed else { return step }
            object["keys"] = .array(keys.map { .object($0.json) })
            return AskStep(tool: step.tool, arguments: .object(object))
        }
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
    static func leaving(_ steps: [AskStep], in art: SVGArtwork, most: CGRect, view: CGRect,
                        resting: CGRect = .null, mostSide: CGFloat? = nil) -> ([AskStep], CGRect) {
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
        let needed = holding.isNull ? resting : holding.insetBy(dx: -slack, dy: -slack).union(resting)
        let room = Self.room(holding: needed, in: view, least: view.width, most: mostSide ?? most.width)
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

    /// How finely a journey is followed to find when a part has gone.
    static let leavingStep = 0.01
    /// Less than this much of a part in the frame and it reads as gone.
    static let goneShare: CGFloat = 1.0 / 3

    /// How much of `box` lies inside `view`, 0 to 1.
    static func share(of box: CGRect, in view: CGRect) -> CGFloat {
        let inside = box.intersection(view)
        guard !inside.isNull, box.width * box.height > 0 else { return 0 }
        return inside.width * inside.height / (box.width * box.height)
    }

    /// `steps` with every mark that is seen only while something moves gone
    /// by the time that thing has (all but) left the frame. A paper plane's speed lines
    /// faded in as it set off and hung on alone for half a second after it
    /// had gone (the eval, 2026-11-08), and told so in words, the model did
    /// it again. A mark here is a part hidden at the top of the lap, shown by
    /// its opacity alone, that does not travel itself; its showing is pressed
    /// into the time before the traveller is wholly out of `view`. A mark
    /// that grows on its own (its scale keyed through 10 or more) is left
    /// behind on purpose and keeps its keys: the rocket's smoke of
    /// 2026-11-09, planned from 0.55 to 1.5 s, was pressed into 0.55 to 0.9
    /// and showed in one frame. Boxes, keys and time only: nothing knows
    /// what the marks are.
    public static func marksGo(_ steps: [AskStep], view: CGRect) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return steps }
        let keyed = steps.filter { $0.tool == "set_keys" }
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        func part(_ step: AskStep) -> String? { (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part }
        func held(_ name: String) -> Set<Int> {
            let plain = plain(name)
            return Set(art.parts.indices.filter { at in
                art.parts[at].name.map { Self.plain($0) == plain } ?? false || art.parts[at].groups.contains { Self.plain($0) == plain }
            })
        }
        let moving = keyed.filter { property($0) == MotionProperty.position.rawValue }
        let grows = Set(keyed.filter { property($0) == MotionProperty.scale.rawValue }.compactMap { step -> String? in
            let values = AskMotionCheck.timed(step).compactMap { $0.value.doubleValue }
            guard let least = values.min(), let most = values.max(), most - least >= markGrowth else { return nil }
            return part(step).map { plain($0) }
        })
        // Where a part is at a moment, by its own travel.
        func offset(of name: String, at seconds: Double) -> CGVector {
            guard let step = moving.first(where: { part($0).map(plain) == plain(name) }),
                  let value = AskMotionCheck.value(of: step, at: seconds),
                  let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue else { return .zero }
            return CGVector(dx: x, dy: y)
        }
        // When each part that leaves is first all but out of the frame: the
        // eye counts it gone with a third of it still in.
        var gone: [(parts: Set<Int>, at: Double)] = []
        for step in moving {
            guard let name = part(step), let box = AskMotionCheck.box(of: name, in: art), box.width * box.height > 0,
                  let end = AskMotionCheck.timed(step).last?.seconds, end > 0 else { continue }
            var at = 0.0
            while at <= end {
                if let value = AskMotionCheck.value(of: step, at: at), let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue,
                   AskMotion.share(of: box.offsetBy(dx: x, dy: y), in: view) < goneShare {
                    gone.append((held(name), at))
                    break
                }
                at += leavingStep
            }
        }
        guard !gone.isEmpty else { return steps }
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys" && property(step) == MotionProperty.opacity.rawValue {
            guard let name = part(step), !grows.contains(plain(name)), var object = step.arguments.objectValue,
                  let box = AskMotionCheck.box(of: name, in: art) else { continue }
            let own = held(name)
            var keys = AskMotionCheck.timed(step)
            guard keys.count == step.arguments["keys"]?.arrayValue?.count,
                  let first = keys.first, first.seconds <= 0, (first.value.doubleValue ?? 100) <= 5 else { continue }
            func shown(_ key: (seconds: Double, value: AgentJSON, curve: String?)) -> Bool { (key.value.doubleValue ?? 100) > 5 }
            var changed = false
            for leaving in gone where leaving.parts.isDisjoint(with: own) {
                // A mark that has gone out of the frame itself by then is not
                // left behind.
                let there = offset(of: name, at: leaving.at)
                guard box.offsetBy(dx: there.dx, dy: there.dy).intersects(view) else { continue }
                // The stretch it is seen in that runs past the moment the
                // traveller has gone: from the last unseen key before it to
                // the first unseen key after.
                guard let after = keys.firstIndex(where: { $0.seconds > leaving.at && !shown($0) }),
                      let before = keys.lastIndex(where: { $0.seconds <= leaving.at && !shown($0) }),
                      before < after, keys[before + 1].seconds < leaving.at,
                      keys[(before + 1)..<after].contains(where: shown) else { continue }
                let from = keys[before].seconds
                let share = (leaving.at - from) / (keys[after].seconds - from)
                for key in (before + 1)...after {
                    keys[key].seconds = Double(rounded(CGFloat(from + (keys[key].seconds - from) * share)))
                }
                changed = true
            }
            guard changed else { continue }
            object["keys"] = .array(keys.map { key in
                var json: [String: AgentJSON] = ["seconds": .number(key.seconds), "value": key.value]
                if let curve = key.curve { json["curve"] = .string(curve) }
                return .object(json)
            })
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
        }
        return out
    }

    /// How much a mark's scale changes before it counts as growing on its
    /// own, as smoke or dust does where it was left.
    static let markGrowth = 10.0

    /// At or over this opacity a part is all there (at or under `unseen` it
    /// is not seen at all).
    static let seenFull = 95.0

    /// `steps` with the fade taken off a part that flies out of the frame,
    /// when every stretch it is unseen holds a moment it is gone from
    /// `view`: the frame's edge already hides it. The envelope of
    /// 2026-11-09 faded out as it flew off on Ease in and faded in on its
    /// way back, so the judge saw it gone in one frame and popping back in;
    /// the rocket of the same day faded out as it lifted off and the look
    /// saw no lift-off at all. Its keys stay where they are, every value
    /// full. A part that rests part seen keeps its look. Boxes, keys and time
    /// only.
    public static func edgeHides(_ steps: [AskStep], view: CGRect) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return steps }
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        func part(_ step: AskStep) -> String? { (step.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) } }
        let moving = steps.filter { $0.tool == "set_keys" && property($0) == MotionProperty.position.rawValue }
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys" && property(step) == MotionProperty.opacity.rawValue {
            guard let name = part(step), let travel = moving.last(where: { part($0) == name }),
                  let box = AskMotionCheck.box(of: name, in: art), box.width * box.height > 0,
                  var object = step.arguments.objectValue, let list = step.arguments["keys"]?.arrayValue else { continue }
            let keys = AskMotionCheck.timed(step)
            let values = keys.compactMap { $0.value.doubleValue }
            guard values.count == keys.count, values.count == list.count, let end = keys.last?.seconds, let full = values.max(),
                  full >= seenFull, values.allSatisfy({ $0 <= unseen || $0 >= seenFull }),
                  values.contains(where: { $0 <= unseen }) else { continue }
            func gone(_ seconds: Double) -> Bool {
                guard let value = AskMotionCheck.value(of: travel, at: seconds),
                      let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue else { return false }
                return share(of: box.offsetBy(dx: x, dy: y), in: view) < goneShare
            }
            // Each stretch it is unseen, and whether it was gone in it.
            var stretches: [Bool] = []
            var inStretch = false
            var moment = 0.0
            while moment <= end + 0.0005 {
                if (AskMotionCheck.value(of: step, at: moment)?.doubleValue ?? 100) <= unseen {
                    if !inStretch { stretches.append(false); inStretch = true }
                    if gone(moment) { stretches[stretches.count - 1] = true }
                } else {
                    inStretch = false
                }
                moment += leavingStep
            }
            guard !stretches.isEmpty, stretches.allSatisfy({ $0 }) else { continue }
            object["keys"] = .array(list.map { key in
                var json = key.objectValue ?? [:]
                json["value"] = .number(full)
                return .object(json)
            })
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
        }
        return out
    }

    /// `steps` with a line that draws itself inked from the moment it starts
    /// to draw, rather than faded in over the same beat: drawn and faded at
    /// once, the tick of 2026-11-09 read as "a small grey ghost scaling in
    /// instead of drawing in as a stroke", nine looks of nine. Only a rise in
    /// opacity that starts while nothing of the line is drawn and ends once
    /// it is is moved to the start of that rise; until then nothing shows
    /// whatever its opacity. Keys and time only.
    public static func drawnNotFaded(_ steps: [AskStep]) -> [AskStep] {
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        let trims = steps.filter { $0.tool == "set_keys" && property($0) == MotionProperty.trimEnd.rawValue }
        guard !trims.isEmpty else { return steps }
        return steps.map { step in
            guard step.tool == "set_keys", property(step) == MotionProperty.opacity.rawValue,
                  let trim = trims.last(where: { $0.arguments["layer"] == step.arguments["layer"] }),
                  var object = step.arguments.objectValue, var list = step.arguments["keys"]?.arrayValue, list.count > 1 else { return step }
            let order = list.indices.sorted { (list[$0]["seconds"]?.doubleValue ?? 0) < (list[$1]["seconds"]?.doubleValue ?? 0) }
            func seconds(_ at: Int) -> Double { list[order[at]]["seconds"]?.doubleValue ?? 0 }
            func value(_ at: Int) -> Double? { list[order[at]]["value"]?.doubleValue }
            func drawn(_ moment: Double) -> Double { AskMotionCheck.value(of: trim, at: moment)?.doubleValue ?? 100 }
            var changed = false
            for at in 0..<(order.count - 1) {
                guard let low = value(at), let high = value(at + 1), low <= unseen, high > unseen,
                      list[order[at]]["curve"]?.stringValue?.caseInsensitiveCompare(AgentKeyCurve.hold) != .orderedSame else { continue }
                let from = at > 0 ? seconds(at - 1) : seconds(at)
                let undrawn = stride(from: from, through: seconds(at), by: leavingStep).allSatisfy { drawn($0) <= unseen }
                    && drawn(seconds(at)) <= unseen
                guard undrawn, drawn(seconds(at + 1)) > unseen, var key = list[order[at]].objectValue else { continue }
                key["value"] = .number(high)
                list[order[at]] = .object(key)
                changed = true
            }
            guard changed else { return step }
            object["keys"] = .array(list)
            return AskStep(tool: step.tool, arguments: .object(object))
        }
    }

    /// The longest the frame may stand empty while what left it is away.
    static let longestGone = 0.5
    /// How soon after its last key out of sight a drawing that left comes in.
    static let returnsAfter = 0.15

    /// `steps` with a drawing that has wholly left the frame brought back in
    /// soon after, then resting at home until the lap ends, rather than
    /// waiting out of sight. A paper plane flew off and the frame stood empty
    /// for a third of the lap (the eval, 2026-11-09). Only when what leaves
    /// is everything seen at the top of the lap, so the frame really is empty,
    /// and only when its way back ends at home with nothing after but home.
    /// Its way in keeps its length; the keys out of sight before it go, its
    /// last key out holding till it jumps unseen. Boxes and time only.
    public static func comesBack(_ steps: [AskStep], view: CGRect) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return steps }
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        func part(_ step: AskStep) -> String? { (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part }
        func held(_ name: String) -> Set<Int> {
            let plain = plain(name)
            return Set(art.parts.indices.filter { at in
                art.parts[at].name.map { Self.plain($0) == plain } ?? false || art.parts[at].groups.contains { Self.plain($0) == plain }
            })
        }
        // What is seen at the top of the lap.
        var seen = Set(art.parts.indices)
        for step in steps where step.tool == "set_keys" && property(step) == MotionProperty.opacity.rawValue {
            guard let name = part(step), let first = AskMotionCheck.timed(step).first, first.seconds <= 0,
                  (first.value.doubleValue ?? 100) <= 5 else { continue }
            seen.subtract(held(name))
        }
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys" && property(step) == MotionProperty.position.rawValue {
            guard let name = part(step), seen.isSubset(of: held(name)), let box = AskMotionCheck.box(of: name, in: art),
                  var object = step.arguments.objectValue else { continue }
            let keys = AskMotionCheck.timed(step)
            guard keys.count == step.arguments["keys"]?.arrayValue?.count, let home = keys.first?.value,
                  let lapEnd = keys.last?.seconds else { continue }
            func isOut(_ value: AgentJSON?) -> Bool {
                guard let x = value?["x"]?.doubleValue, let y = value?["y"]?.doubleValue else { return false }
                return !box.offsetBy(dx: x, dy: y).intersects(view)
            }
            // How long it is away: from the moment it is out to the moment
            // it is back in sight.
            var left: Double?
            var away = 0.0
            var moment = 0.0
            while moment <= lapEnd {
                let outNow = isOut(AskMotionCheck.value(of: step, at: moment))
                if outNow, left == nil { left = moment }
                if !outNow, let since = left { away = moment - since; break }
                moment += leavingStep
            }
            guard away > longestGone,
                  let first = keys.firstIndex(where: { isOut($0.value) }),
                  let enters = keys.indices.last(where: { $0 > first && isOut(keys[$0].value) && $0 + 1 < keys.count && !isOut(keys[$0 + 1].value) }),
                  let landed = keys.indices.first(where: { $0 > enters && keys[$0].value == home }),
                  keys[landed...].allSatisfy({ $0.value == home }) else { continue }
            let starts = keys[first].seconds + returnsAfter
            let shift = keys[enters].seconds - starts
            guard shift > 0.0005 else { continue }
            var made = Array(keys[...first])
            made[first].curve = AgentKeyCurve.hold
            for key in keys[enters...landed] {
                made.append((Double(rounded(CGFloat(key.seconds - shift))), key.value, key.curve))
            }
            if let last = made.last, last.seconds < lapEnd - 0.0005 { made.append((lapEnd, home, nil)) }
            object["keys"] = .array(made.map { key in
                var json: [String: AgentJSON] = ["seconds": .number(key.seconds), "value": key.value]
                if let curve = key.curve { json["curve"] = .string(curve) }
                return .object(json)
            })
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
        }
        return out
    }

    /// A step's keys in the order they play.
    static func inTime(_ step: AskStep) -> [AgentJSON] {
        (step.arguments["keys"]?.arrayValue ?? []).enumerated().sorted {
            ($0.element["seconds"]?.doubleValue ?? 0, $0.offset) < ($1.element["seconds"]?.doubleValue ?? 0, $1.offset)
        }.map(\.element)
    }

    // MARK: A fold shares its hinge

    /// `steps` with a fold drawn a line off the edge it is hinged on moved
    /// onto that edge, and its own stroke along the hinge left out, since the
    /// outline already draws it. On 2026-11-09 the eval's envelope drew its
    /// flap's top one unit above its body's, both stroked: shut it read as
    /// "an odd thick top bar" and open as a closed triangle on a box, "a
    /// house", in nine looks of nine. Only a straight-sided outline folding
    /// over one of its own edges, within a stroke of a closed outline's same
    /// edge; a hinge said on the grid moves with it. Geometry only.
    ///
    /// `grow` is how much the drawing's frame will grow to make room: lines
    /// and corner rounds keep their size on the final grid as everything
    /// else shrinks, so a fold's ends are tucked for them that much larger
    /// (on 2026-11-09 a frame grown 1.25 times left round ends tucked for
    /// the drawn size poking out of the body's corners).
    public static func hingesShared(_ steps: [AskStep], grow: CGFloat = 1) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              var svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true),
              var object = steps[index].arguments.objectValue else { return steps }
        var out = steps
        var changed = false
        for (at, step) in steps.enumerated() where step.tool == "set_keys" {
            let property = step.arguments["property"]?.stringValue
            guard property == MotionProperty.rotationX.rawValue || property == MotionProperty.rotationY.rawValue,
                  let name = (step.arguments["layer"]?.stringValue).flatMap(partReference).map({ plain($0.part) }) else { continue }
            let level = property == MotionProperty.rotationX.rawValue
            let own = art.parts.filter { $0.name.map { plain($0) == name } ?? false || $0.groups.contains { plain($0) == name } }
            guard own.count == 1, let part = own.first, plain(part.name ?? "") == name,
                  case .path(let outline) = part.shape, outline.rings.count == 1,
                  outline.rings[0].allSatisfy({ $0.handleIn == nil && $0.handleOut == nil }),
                  let px = step.arguments["pivot"]?["x"]?.doubleValue, let py = step.arguments["pivot"]?["y"]?.doubleValue else { continue }
            let box = SVGArtwork.shapeBounds(part.shape)
            let fraction = isFraction(px, py)
            let pivot = fraction ? CGPoint(x: box.minX + box.width * px, y: box.minY + box.height * py) : CGPoint(x: px, y: py)
            // Which of its own edges it folds over, if any.
            let along = level ? pivot.y : pivot.x
            let (low, high) = level ? (box.minY, box.maxY) : (box.minX, box.maxX)
            let atLow: Bool
            if abs(along - low) <= 0.5 { atLow = true } else if abs(along - high) <= 0.5 { atLow = false } else { continue }
            let hinge = atLow ? low : high
            let (spanLow, spanHigh) = level ? (box.minX, box.maxX) : (box.minY, box.maxY)
            // The closed outline whose same edge is within a stroke of it.
            let edges: [(edge: CGFloat, round: Round?)] = art.parts.compactMap { other in
                guard other != part, !(other.name.map { plain($0) == name } ?? false), other.strokeWidth > 0 else { return nil }
                let corner: CGFloat
                switch other.shape {
                case .rect(_, let radius): corner = radius * grow
                case .path(let ring) where ring.closed: corner = 0
                default: return nil
                }
                let room = SVGArtwork.shapeBounds(other.shape)
                let slack = max(part.strokeWidth, other.strokeWidth)
                let edge = level ? (atLow ? room.minY : room.maxY) : (atLow ? room.minX : room.maxX)
                let (roomLow, roomHigh) = level ? (room.minX, room.maxX) : (room.minY, room.maxY)
                guard abs(edge - hinge) <= slack, spanLow >= roomLow - slack, spanHigh <= roomHigh + slack else { return nil }
                let half = other.strokeWidth * grow / 2
                return (edge, corner > 0 ? Round(outer: room.insetBy(dx: -half, dy: -half), radius: corner + half) : nil)
            }
            guard let nearest = edges.min(by: { abs($0.edge - hinge) < abs($1.edge - hinge) }) else { continue }
            let shift = nearest.edge - hinge
            guard let made = hingeOpened(name, level: level, atLow: atLow, box: box, shift: shift, line: part.strokeWidth * grow,
                                         round: nearest.round, in: svg) else { continue }
            svg = made
            changed = true
            if !fraction, shift != 0, var arguments = step.arguments.objectValue {
                arguments["pivot"] = .object(["x": .number(level ? px : rounded(CGFloat(px) + shift)),
                                              "y": .number(level ? rounded(CGFloat(py) + shift) : py)])
                out[at] = AskStep(tool: step.tool, arguments: .object(arguments))
            }
        }
        guard changed else { return steps }
        object["svg"] = .string(svg)
        out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        return out
    }

    /// `svg` with the path called `name`, a polygon of straight sides `size`
    /// big on the grid, opened along its edge on the hinge's side and moved
    /// `shift` across it. Nil unless its own `d` is plain absolute M and L and
    /// nothing above it scales it.
    /// The outer edge of a rounded outline's ink: its box grown by half its
    /// line, and the round of its corners there.
    struct Round: Equatable {
        var outer: CGRect
        var radius: CGFloat

        func holds(_ point: CGPoint, slack: CGFloat = 0.02) -> Bool {
            let inner = outer.insetBy(dx: radius, dy: radius)
            let nearest = CGPoint(x: min(max(point.x, inner.minX), inner.maxX), y: min(max(point.y, inner.minY), inner.maxY))
            return hypot(point.x - nearest.x, point.y - nearest.y) <= radius + slack
        }
    }

    /// How far, at most, a fold's end slides in along its hinge to clear a
    /// rounded corner, in the round's own radii: past that it is not the
    /// corner's doing.
    static let tuckMost: CGFloat = 1.5

    /// `ring`, a fold opened along its hinge with its ends on that hinge, with
    /// each end slid along the hinge toward the middle until its flat line
    /// end sits inside a rounded outline's ink both as drawn and folded over
    /// the hinge. The envelope of 2026-11-09 drew its flap's ends on the
    /// body's rounded corners, and their square ends stuck out of the round
    /// shut and open, "the flap's corners poke past the body" in seven looks
    /// of nine. Geometry only: ends, a hinge line, a round.
    ///
    /// First choice is a round end: slid in until the whole round sits inside
    /// the outline's round, a round end centred on the hinge lies within the
    /// outline's own line shut and open alike and melts into it, where a
    /// flat end meets that line at an angle and leaves a notch ("the flap's
    /// ends are clipped off at sharp angles", 2026-11-09). Only when that
    /// takes more than `tuckMost` does an end stay flat, slid as far as its
    /// corners need. `round` in the answer says which.
    static func tucked(_ ring: [CGPoint], offset: CGPoint, level: Bool, hinge: CGFloat, line: CGFloat,
                       round: Round) -> (ring: [CGPoint], round: Bool) {
        guard ring.count >= 3 else { return (ring, false) }
        let middle = level ? round.outer.midX : round.outer.midY
        let most = round.radius * tuckMost
        let ends = [0, ring.count - 1]
        // A round end: its whole disc inside the outline's round.
        let roundSlides = ends.map { end -> CGFloat? in
            let at = CGPoint(x: ring[end].x + offset.x, y: ring[end].y + offset.y)
            let inward: CGFloat = ((level ? at.x : at.y) < middle) ? 1 : -1
            // The disc is inside the round when its centre is inside the
            // round drawn half a line in all round.
            let inner = Round(outer: round.outer.insetBy(dx: line / 2, dy: line / 2), radius: max(round.radius - line / 2, 0))
            return stride(from: CGFloat(0), through: most, by: 0.05).first { slide in
                inner.holds(level ? CGPoint(x: at.x + inward * slide, y: at.y) : CGPoint(x: at.x, y: at.y + inward * slide))
            }
        }
        if roundSlides.allSatisfy({ $0 != nil }) {
            var out = ring
            for (end, slide) in zip(ends, roundSlides) {
                guard let slide, slide > 0 else { continue }
                let inward: CGFloat = ((level ? ring[end].x + offset.x : ring[end].y + offset.y) < middle) ? 1 : -1
                let amount = CGFloat(rounded(slide))
                out[end] = level ? CGPoint(x: ring[end].x + inward * amount, y: ring[end].y) : CGPoint(x: ring[end].x, y: ring[end].y + inward * amount)
            }
            return (out, true)
        }
        var out = ring
        for (end, next) in [(0, 1), (ring.count - 1, ring.count - 2)] {
            let at = CGPoint(x: ring[end].x + offset.x, y: ring[end].y + offset.y)
            let toward = CGPoint(x: ring[next].x + offset.x, y: ring[next].y + offset.y)
            let inward: CGFloat = ((level ? at.x : at.y) < middle) ? 1 : -1
            func clear(_ slide: CGFloat) -> Bool {
                let moved = level ? CGPoint(x: at.x + inward * slide, y: at.y) : CGPoint(x: at.x, y: at.y + inward * slide)
                let length = hypot(toward.x - moved.x, toward.y - moved.y)
                guard length > 0.001 else { return false }
                let across = CGPoint(x: -(toward.y - moved.y) / length * line / 2, y: (toward.x - moved.x) / length * line / 2)
                let corners = [CGPoint(x: moved.x + across.x, y: moved.y + across.y), CGPoint(x: moved.x - across.x, y: moved.y - across.y)]
                let folded = corners.map { level ? CGPoint(x: $0.x, y: 2 * hinge - $0.y) : CGPoint(x: 2 * hinge - $0.x, y: $0.y) }
                return (corners + folded).allSatisfy { round.holds($0) }
            }
            guard !clear(0) else { continue }
            guard let slide = stride(from: CGFloat(0.05), through: most, by: 0.05).first(where: clear) else { continue }
            let amount = CGFloat(rounded(slide))
            out[end] = level ? CGPoint(x: ring[end].x + inward * amount, y: ring[end].y) : CGPoint(x: ring[end].x, y: ring[end].y + inward * amount)
        }
        return (out, false)
    }

    static func hingeOpened(_ name: String, level: Bool, atLow: Bool, box: CGRect, shift: CGFloat, line: CGFloat,
                            round: Round? = nil, in svg: String) -> String? {
        let size = box.size
        guard let whole = elementRange(name, in: svg) else { return nil }
        let element = String(svg[whole])
        guard element.hasPrefix("<path"), let dRange = element.range(of: #"\sd="([^"]*)""#, options: .regularExpression) else { return nil }
        let d = String(element[dRange]).drop { $0 != "\"" }.dropFirst().dropLast()
        var points: [CGPoint] = []
        var numbers: [CGFloat] = []
        var closed = false
        var first = true
        let tokens = d.matches(of: /[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/).map { String($0.output) }
        for token in tokens {
            if let letter = token.first, letter.isLetter {
                guard numbers.isEmpty, !closed else { return nil }
                switch letter {
                case "M": guard first else { return nil }
                case "L": guard !first else { return nil }
                case "Z", "z": closed = true
                default: return nil
                }
                first = false
                continue
            }
            guard let value = Double(token) else { return nil }
            numbers.append(CGFloat(value))
            if numbers.count == 2 { points.append(CGPoint(x: numbers[0], y: numbers[1])); numbers = [] }
        }
        guard numbers.isEmpty, points.count >= 3 else { return nil }
        if let last = points.last, let start = points.first, hypot(last.x - start.x, last.y - start.y) < 0.001 { points.removeLast() }
        guard points.count >= 3 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              abs((maxX - minX) - size.width) < 0.01, abs((maxY - minY) - size.height) < 0.01 else { return nil }
        let side = level ? (atLow ? minY : maxY) : (atLow ? minX : maxX)
        func on(_ point: CGPoint) -> Bool { abs((level ? point.y : point.x) - side) < 0.01 }
        let count = points.count
        guard let cut = (0..<count).first(where: { on(points[$0]) && on(points[($0 + 1) % count]) }) else { return nil }
        var ring = (1...count).map { points[(cut + $0) % count] }
        var roundEnds = false
        if let round {
            // Where its points land in the drawing: its box, moved onto the edge.
            let offset = CGPoint(x: box.minX - minX + (level ? 0 : shift), y: box.minY - minY + (level ? shift : 0))
            let hinge = level ? side + offset.y : side + offset.x
            (ring, roundEnds) = tucked(ring, offset: offset, level: level, hinge: hinge, line: line, round: round)
        }
        func said(_ value: CGFloat) -> String {
            let number = rounded(value)
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        let opened = "M" + ring.map { "\(said($0.x)) \(said($0.y))" }.joined(separator: " L")
        // Its ends sit on the outline's line: round where they were tucked
        // inside its round, flat otherwise, since on a corner a round end
        // pokes half a line past it (the judge, 2026-11-09: "round end caps
        // poke out at the corners").
        var made = paint([("stroke-linecap", roundEnds ? "round" : "butt")], onElement: element.replacingCharacters(in: dRange, with: " d=\"\(opened)\""))
        if shift != 0 {
            let move = level ? "translate(0 \(said(shift)))" : "translate(\(said(shift)) 0)"
            if let transform = made.range(of: #"\stransform="([^"]*)""#, options: .regularExpression) {
                let existing = String(made[transform]).drop { $0 != "\"" }.dropFirst().dropLast()
                made.replaceSubrange(transform, with: " transform=\"\(move) \(existing)\"")
            } else if let space = made.firstIndex(of: " ") {
                made.insert(contentsOf: " transform=\"\(move)\"", at: space)
            }
        }
        var text = svg
        text.replaceSubrange(whole, with: made)
        return text
    }

    // MARK: What comes out of something

    /// How much of itself, at least, a part that comes out of an outline
    /// shows at its farthest out.
    static let clearShare: CGFloat = 0.7

    /// `steps` with every part that starts inside a closed outline and comes
    /// out of it brought, at its farthest out, far enough to show 70 percent
    /// of its ink past the outline's, a unit inside the frame at most. The
    /// envelope of 2026-11-09 raised its letter until 3.3 of its 7 units
    /// showed, so the letter's lines met the body's in a black band: "a
    /// stubby bar", "a solid black blob" in nine looks of nine. Every key
    /// that holds that farthest place moves with it. Boxes and keys only:
    /// nothing here knows what anything is.
    public static func comesClear(_ steps: [AskStep]) -> [AskStep] {
        guard let drawing = steps.first(where: { $0.tool == "add_drawing" }),
              let svg = drawing.arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox else { return steps }
        let margin = view.width * restMargin
        let frame = view.insetBy(dx: margin, dy: margin)
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys"
            && step.arguments["property"]?.stringValue == MotionProperty.position.rawValue {
            guard let name = (step.arguments["layer"]?.stringValue).flatMap(partReference).map({ plain($0.part) }),
                  let box = AskMotionCheck.box(of: name, in: art), var object = step.arguments.objectValue,
                  var keys = step.arguments["keys"]?.arrayValue else { continue }
            let offsets = keys.map { key -> CGPoint? in
                guard let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return nil }
                return CGPoint(x: x, y: y)
            }
            guard let first = offsets.first ?? nil, !offsets.contains(where: { $0 == nil }) else { continue }
            let rest = box.offsetBy(dx: first.x, dy: first.y)
            // The smallest closed outline, not its own, whose ink holds it at rest.
            let rooms = art.parts.compactMap { part -> CGRect? in
                guard !(part.name.map { plain($0) == name } ?? false), !part.groups.contains(where: { plain($0) == name }),
                      part.strokeWidth > 0 else { return nil }
                switch part.shape {
                case .rect, .ellipse: break
                case .path(let path) where path.closed: break
                default: return nil
                }
                let ink = Self.box(of: part)
                return ink.insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack).contains(rest) ? ink : nil
            }
            guard let room = rooms.min(by: { $0.width * $0.height < $1.width * $1.height }) else { continue }
            // Its farthest out: how far past each side of the room it shows.
            var best: (index: Int, side: Int, shown: CGFloat)?
            for (index, offset) in offsets.enumerated() {
                guard let offset else { continue }
                let placed = box.offsetBy(dx: offset.x, dy: offset.y)
                let shown = [room.minY - placed.minY, placed.maxY - room.maxY, room.minX - placed.minX, placed.maxX - room.maxX]
                for (side, past) in shown.enumerated() where past > 0 && past > (best?.shown ?? 0) {
                    best = (index, side, past)
                }
            }
            guard let best, let peak = offsets[best.index] else { continue }
            let placed = box.offsetBy(dx: peak.x, dy: peak.y)
            // Gone from the frame altogether, or already clear: as made.
            guard placed.intersects(view) else { continue }
            let extent = best.side < 2 ? placed.height : placed.width
            let wanted = clearShare * extent - best.shown
            guard wanted > 0.25 else { continue }
            let ahead = [placed.minY - frame.minY, frame.maxY - placed.maxY, placed.minX - frame.minX, frame.maxX - placed.maxX][best.side]
            let move = min(wanted, ahead)
            guard move > 0.25 else { continue }
            let delta: CGPoint = [CGPoint(x: 0, y: -move), CGPoint(x: 0, y: move), CGPoint(x: -move, y: 0), CGPoint(x: move, y: 0)][best.side]
            for (index, offset) in offsets.enumerated() where offset == peak {
                guard var json = keys[index].objectValue else { continue }
                json["value"] = .object(["x": .number(rounded(peak.x + delta.x)), "y": .number(rounded(peak.y + delta.y))])
                keys[index] = .object(json)
            }
            object["keys"] = .array(keys)
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
        }
        return out
    }

    /// `steps` with what travels out from inside a closed outline hidden at
    /// rest behind that outline, the smallest that holds it, which is filled
    /// white, so the part is behind it until it comes out. Told to do this
    /// itself, the model filled the part and the cover over it and left the
    /// outline it sat in empty, so the part showed through (the eval,
    /// 2026-11-08).
    ///
    /// An outline drawn BEFORE the part is the same picture told the other
    /// way round: the part goes to just behind the outline, but only when it
    /// really comes out of it (one that moves about inside was meant to be
    /// seen), when nothing else drawn before the outline sits inside it (the
    /// white would bury it) and when the move leaves it in the same groups.
    /// Then a part of that outline that folds and is filled white stops
    /// being filled: shut, the white outline behind it hides what is inside
    /// anyway, and folded open it would cover what came out. Three envelopes
    /// out of three did this on 2026-11-09: the outline first and empty, the
    /// part over it showing through the closed front.
    /// Order and boxes only: nothing here knows what anything is.
    public static func hidden(_ steps: [AskStep]) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              var svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true),
              var object = steps[index].arguments.objectValue else { return steps }
        func layer(_ step: AskStep) -> String? { (step.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) } }
        let keyed = steps.filter { $0.tool == "set_keys" }
        let travelling = Set(keyed.filter { $0.arguments["property"]?.stringValue == MotionProperty.position.rawValue }.compactMap(layer))
        let folding = Set(keyed.filter { [MotionProperty.rotationX.rawValue, MotionProperty.rotationY.rawValue]
            .contains($0.arguments["property"]?.stringValue ?? "") }.compactMap(layer))
        func holds(_ part: SVGArtwork.Part, _ name: String) -> Bool {
            part.name.map { plain($0) == name } ?? false || part.groups.contains { plain($0) == name }
        }
        func outline(_ part: SVGArtwork.Part) -> CGRect? {
            guard part.fill == nil, !(part.name ?? "").isEmpty else { return nil }
            if case .path(let path) = part.shape, !path.closed { return nil }
            return SVGArtwork.shapeBounds(part.shape).insetBy(dx: -part.strokeWidth / 2, dy: -part.strokeWidth / 2)
                .insetBy(dx: -AskMotionCheck.edgeSlack, dy: -AskMotionCheck.edgeSlack)
        }
        var filled: Set<String> = []
        var moved = false
        var lined: [(part: String, stroke: String, width: CGFloat)] = []
        var faced: [(part: String, room: CGRect)] = []
        // Solid ink coming out of a drawing made of lines reads as a hole,
        // not a thing (the judge, nine looks of nine on 2026-11-09: "a solid
        // black block that clashes with the outline style"). It comes out in
        // the outline's own line, white inside, when every other part is line.
        func inLine(_ name: String, from cover: SVGArtwork.Part) {
            guard let ink = cover.stroke, cover.strokeWidth > 0,
                  art.parts.allSatisfy({ holds($0, name) || $0.fill == nil || isWhite($0.fill) }) else { return }
            for part in art.parts where holds(part, name) {
                guard let own = part.name, part.fill?.lowercased() == ink.lowercased(),
                      part.stroke == nil || part.stroke?.lowercased() == ink.lowercased() else { continue }
                lined.append((plain(own), ink, cover.strokeWidth))
            }
        }
        for name in travelling.sorted() {
            let own = art.parts.indices.filter { holds(art.parts[$0], name) }
            guard let first = own.first, let last = own.last, let box = AskMotionCheck.box(of: name, in: art) else { continue }
            let after = art.parts.indices.filter { at in
                at > last && !holds(art.parts[at], name) && outline(art.parts[at]).map { $0.contains(box) } ?? false
            }
            if let smallest = after.min(by: { area(art.parts[$0]) < area(art.parts[$1]) }), let cover = art.parts[smallest].name,
               let room = outline(art.parts[smallest]) {
                filled.insert(plain(cover))
                inLine(name, from: art.parts[smallest])
                faced.append((name, room))
                continue
            }
            // Drawn before it: only what really comes out of the outline, and
            // one move a plan, since the parts' places are read from before it.
            guard !moved, let reach = AskMotionCheck.reach(of: keyed, in: art, only: name) else { continue }
            // Where it is at each of its position keys: what drops in from
            // outside the outline goes in just as what comes out of it does
            // (the eval's letter of 2026-11-09, drawn above the envelope).
            let placed = keyed.filter { layer($0) == name && $0.arguments["property"]?.stringValue == MotionProperty.position.rawValue }
                .flatMap { AskMotionCheck.timed($0) }.compactMap { key -> CGRect? in
                    guard let x = key.value["x"]?.doubleValue, let y = key.value["y"]?.doubleValue else { return nil }
                    return box.offsetBy(dx: x, dy: y)
                }
            let before = art.parts.indices.filter { at in
                guard at < first, !holds(art.parts[at], name), let room = outline(art.parts[at]) else { return false }
                return (room.contains(box) || placed.contains { room.contains($0) }) && !room.contains(reach)
            }
            guard let smallest = before.min(by: { area(art.parts[$0]) < area(art.parts[$1]) }),
                  let cover = art.parts[smallest].name,
                  let room = outline(art.parts[smallest]) else { continue }
            let buried = art.parts.indices.contains { at in
                at < smallest && !holds(art.parts[at], name) && room.intersects(Self.box(of: art.parts[at]))
            }
            guard !buried, let shifted = svgMoving(name, before: plain(cover), in: svg),
                  case .success(let after) = SVGArtwork.parse(shifted, keepingGroups: true),
                  after.parts.filter({ holds($0, name) }).map(\.groups) == own.map({ art.parts[$0].groups }) else { continue }
            svg = shifted
            moved = true
            filled.insert(plain(cover))
            inLine(name, from: art.parts[smallest])
            // A white fold of the outline, shut inside it, would cover what came out once open.
            for at in art.parts.indices where at > smallest {
                let part = art.parts[at]
                guard let fold = part.name, folding.contains(plain(fold)) || part.groups.contains(where: { folding.contains(plain($0)) }),
                      isWhite(part.fill), room.contains(Self.box(of: part)) else { continue }
                svg = fill("none", on: plain(fold), in: svg)
            }
            faced.append((name, room))
        }
        // A fold of the outline drawn over what comes out lies behind it once
        // turned past edge on.
        var added: [AskStep] = []
        for (name, room) in faced {
            for part in art.parts {
                guard let fold = part.name.map(plain), folding.contains(fold), !holds(part, name),
                      room.contains(Self.box(of: part)),
                      let at = art.parts.firstIndex(of: part), let from = art.parts.firstIndex(where: { holds($0, name) }), at > from,
                      let turn = keyed.last(where: { layer($0) == fold && [MotionProperty.rotationX.rawValue, MotionProperty.rotationY.rawValue]
                          .contains($0.arguments["property"]?.stringValue ?? "") }),
                      !keyed.contains(where: { layer($0) == fold && $0.arguments["property"]?.stringValue == MotionProperty.opacity.rawValue }),
                      let reference = (turn.arguments["layer"]?.stringValue).flatMap(partReference),
                      let faces = backFace(of: fold, behind: name, groups: part.groups, in: svg) else { continue }
                let sides = sidesShown(turn)
                guard sides.count > 1 else { continue }
                svg = faces.svg
                let back = "$\(reference.step)/\(faces.id)"
                var turned = turn.arguments.objectValue ?? [:]
                turned["layer"] = .string(back)
                added.append(AskStep(tool: "set_keys", arguments: .object(turned)))
                for (layerName, front) in [(turn.arguments["layer"]?.stringValue ?? "", true), (back, false)] {
                    let keys: [AgentJSON] = sides.enumerated().map { index, side in
                        var key: [String: AgentJSON] = ["seconds": .number(side.seconds), "value": .number(side.front == front ? 100 : 0)]
                        if index < sides.count - 1 { key["curve"] = .string(AgentKeyCurve.hold) }
                        return .object(key)
                    }
                    added.append(AskStep(tool: "set_keys", arguments: .object(["layer": .string(layerName),
                                                                               "property": .string(MotionProperty.opacity.rawValue),
                                                                               "keys": .array(keys)])))
                }
                moved = true
            }
        }
        guard !filled.isEmpty || moved else { return steps }
        for cover in filled { svg = whiteFill(on: cover, in: svg) }
        for line in lined {
            svg = paint([("fill", "#FFFFFF"), ("stroke", line.stroke), ("stroke-width", "\(rounded(line.width))"),
                         ("stroke-linejoin", "round")], on: line.part, in: svg)
        }
        object["svg"] = .string(svg)
        var out = steps
        out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        return out + added
    }

    /// `svg` with a copy of the part called `fold`, its id ending "-back",
    /// put just before the part called `name`, and that id; nil when either
    /// is not there or the copy would land in other groups than `groups`.
    static func backFace(of fold: String, behind name: String, groups: [String], in svg: String) -> (svg: String, id: String)? {
        guard let range = elementRange(fold, in: svg) else { return nil }
        let element = String(svg[range])
        guard let idRange = element.range(of: #"\bid="([^"]*)""#, options: .regularExpression) else { return nil }
        let id = String(element[idRange]).dropFirst(4).dropLast() + "-back"
        guard !svg.contains("id=\"\(id)\""), let target = elementRange(name, in: svg) else { return nil }
        var copy = element
        copy.replaceSubrange(idRange, with: "id=\"\(id)\"")
        var text = svg
        text.insert(contentsOf: copy, at: target.lowerBound)
        guard case .success(let art) = SVGArtwork.parse(text, keepingGroups: true),
              art.parts.first(where: { $0.name.map(plain) == plain(String(id)) })?.groups == groups else { return nil }
        return (text, String(id))
    }

    /// Which face of a fold shows, front or back, from its first key to its
    /// last: where it starts, then each moment it turns edge on.
    static func sidesShown(_ turn: AskStep) -> [(seconds: Double, front: Bool)] {
        let keys = AskMotionCheck.timed(turn).compactMap { key in key.value.doubleValue.map { (key.seconds, $0, key.curve) } }
        guard let first = keys.first, let last = keys.last else { return [] }
        func front(_ degrees: Double) -> Bool { cos(degrees * .pi / 180) >= 0 }
        var sides = [(seconds: rounded(CGFloat(first.0)), front: front(first.1))]
        for (one, next) in zip(keys, keys.dropFirst()) {
            let span = next.0 - one.0
            guard span > 0 else { continue }
            let hold = one.2?.caseInsensitiveCompare(AgentKeyCurve.hold) == .orderedSame
            let curve = one.2.flatMap(AgentKeyCurve.curve(named:)) ?? .linear
            func angle(_ share: Double) -> Double {
                hold ? (share < 1 ? one.1 : next.1) : one.1 + (next.1 - one.1) * curve.value(at: share)
            }
            // Walk the run finely, then close in on each turn edge on.
            let steps = 240
            var low = 0.0
            for step in 1...steps {
                let high = Double(step) / Double(steps)
                guard front(angle(high)) != front(angle(low)) else { low = high; continue }
                var (a, b) = (low, high)
                for _ in 0..<30 {
                    let mid = (a + b) / 2
                    if front(angle(mid)) == front(angle(a)) { a = mid } else { b = mid }
                }
                let at = rounded(CGFloat(one.0 + span * b))
                if let previous = sides.last, at <= previous.seconds { sides[sides.count - 1].front = front(angle(high)) } else {
                    sides.append((at, front(angle(high))))
                }
                low = high
            }
        }
        if sides.count > 1, let end = sides.last, end.seconds < rounded(CGFloat(last.0)) {
            sides.append((rounded(CGFloat(last.0)), end.front))
        }
        return sides
    }

    private static func box(of part: SVGArtwork.Part) -> CGRect {
        SVGArtwork.shapeBounds(part.shape).insetBy(dx: -part.strokeWidth / 2, dy: -part.strokeWidth / 2)
    }

    private static func isWhite(_ fill: String?) -> Bool {
        guard let fill = fill?.lowercased().trimmingCharacters(in: .whitespaces) else { return false }
        return ["#fff", "#ffffff", "white", "rgb(255,255,255)", "rgb(255, 255, 255)"].contains(fill)
    }

    /// The whole element whose id reads as `name`, children and closing tag
    /// included, in `svg`.
    static func elementRange(_ name: String, in svg: String) -> Range<String.Index>? {
        var from = svg.startIndex
        while let tag = svg.range(of: #"<([A-Za-z]+)\b[^>]*>"#, options: .regularExpression, range: from..<svg.endIndex) {
            let element = String(svg[tag])
            from = tag.upperBound
            guard let id = element.range(of: #"\bid="([^"]*)""#, options: .regularExpression),
                  plain(String(element[id]).dropFirst(4).dropLast().description) == name else { continue }
            if element.hasSuffix("/>") { return tag }
            guard let kind = element.dropFirst().split(whereSeparator: { !$0.isLetter }).first.map(String.init) else { return nil }
            // Walk to the matching close, counting the same kind opened inside.
            var depth = 1
            var at = tag.upperBound
            while depth > 0, let next = svg.range(of: "</?\(kind)\\b[^>]*>", options: .regularExpression, range: at..<svg.endIndex) {
                let found = svg[next]
                if found.hasPrefix("</") { depth -= 1 } else if !found.hasSuffix("/>") { depth += 1 }
                at = next.upperBound
                if depth == 0 { return tag.lowerBound..<next.upperBound }
            }
            return nil
        }
        return nil
    }

    /// `svg` with the element called `name` taken out and put back just
    /// before the element called `cover`, or nil when either is not there.
    static func svgMoving(_ name: String, before cover: String, in svg: String) -> String? {
        guard let part = elementRange(name, in: svg) else { return nil }
        var text = svg
        let element = String(text[part])
        text.removeSubrange(part)
        guard let target = elementRange(cover, in: text) else { return nil }
        text.insert(contentsOf: element, at: target.lowerBound)
        return text
    }

    private static func area(_ part: SVGArtwork.Part) -> CGFloat {
        let box = SVGArtwork.shapeBounds(part.shape)
        return box.width * box.height
    }

    /// `svg` with the element whose id reads as `name` filled white.
    static func whiteFill(on name: String, in svg: String) -> String { fill("#FFFFFF", on: name, in: svg) }

    /// `svg` with the element whose id reads as `name` filled with `paint`.
    static func fill(_ paint: String, on name: String, in svg: String) -> String {
        Self.paint([("fill", paint)], on: name, in: svg)
    }

    /// One element's opening tag given `attributes`, each replacing any it had.
    static func paint(_ attributes: [(String, String)], onElement element: String) -> String {
        guard let end = element.range(of: ">") else { return element }
        let tag = String(element[..<end.upperBound])
        var made = tag
        for (key, value) in attributes.reversed() {
            made = made.replacingOccurrences(of: #"\s"# + key + #"="[^"]*""#, with: "", options: .regularExpression)
            if let space = made.firstIndex(of: " ") { made.insert(contentsOf: " \(key)=\"\(value)\"", at: space) }
        }
        return made + element[end.upperBound...]
    }

    /// `svg` with the element whose id reads as `name` given `attributes`,
    /// each replacing any it had. A group is never painted: its parts are.
    static func paint(_ attributes: [(String, String)], on name: String, in svg: String) -> String {
        var text = svg
        var from = text.startIndex
        while let tag = text.range(of: #"<[A-Za-z]+\b[^>]*>"#, options: .regularExpression, range: from..<text.endIndex) {
            let element = String(text[tag])
            from = tag.upperBound
            guard let id = element.range(of: #"\bid="([^"]*)""#, options: .regularExpression),
                  plain(String(element[id]).dropFirst(4).dropLast().description) == name, !element.hasPrefix("<g") else { continue }
            var made = element
            for (key, value) in attributes.reversed() {
                made = made.replacingOccurrences(of: #"\s"# + key + #"="[^"]*""#, with: "", options: .regularExpression)
                if let space = made.firstIndex(of: " ") { made.insert(contentsOf: " \(key)=\"\(value)\"", at: space) }
            }
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
        // Keys that hold one value the whole lap move nothing, and one held
        // away from rest stands the part there all lap: the checkbox of
        // 2026-11-10 keyed every value of its tick at 100, one after another,
        // and the tick stood folded flat. A replace may put a value to rest.
        let values = (arguments["keys"]?.arrayValue ?? []).compactMap { $0["value"] }
        if arguments["replace"]?.boolValue != true, let first = values.first, values.allSatisfy({ $0 == first }) {
            let property = arguments["property"]?.stringValue ?? "that value"
            return "Not planned: every key holds \(property) at one value, so it never moves. Key only a value that changes; what stays as drawn needs no keys. Plan the next beat, or finish."
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

    /// "trash passes through lid from 0.96 s to 1.1 s", for a part a key
    /// says touches another whose ink, while both are seen, from that touch
    /// on overlaps that other's deeper than a touch (`AskMotion.passesThrough`). Only
    /// pairs the plan says touch where the one touched moves too, and not
    /// ones drawn overlapping: what is meant to slide in behind a front is
    /// never asked about.
    static func throughWhatItTouches(_ planned: [AskStep]) -> [String] {
        var pairs: [(mine: String, other: String, touch: Double)] = []
        for step in planned where step.tool == "set_keys" {
            guard let mine = (step.arguments["layer"]?.stringValue).flatMap(AskMotion.partReference)?.part else { continue }
            for key in step.arguments["keys"]?.arrayValue ?? [] {
                guard let word = key["touches"]?.stringValue, let seconds = key["seconds"]?.doubleValue else { continue }
                let other = AskMotion.partReference(word)?.part ?? word
                guard AskMotion.plain(other) != AskMotion.plain(mine) else { continue }
                if let at = pairs.firstIndex(where: { AskMotion.plain($0.mine) == AskMotion.plain(mine) && AskMotion.plain($0.other) == AskMotion.plain(other) }) {
                    pairs[at].touch = min(pairs[at].touch, seconds)
                } else {
                    pairs.append((mine, other, seconds))
                }
            }
        }
        guard !pairs.isEmpty, let lap = AskMotion.Lap(AskMotion.touchesPlaced(planned)) else { return [] }
        let end = planned.last { $0.tool == "set_timing" }?.arguments["seconds"]?.doubleValue
            ?? lap.keyed.flatMap { timed($0).map(\.seconds) }.max() ?? 0
        func seen(_ name: String, _ seconds: Double) -> Bool {
            guard lap.isMover(name) || !lap.carriers(of: name).isEmpty else { return true }
            return lap.placed(name, at: seconds)?.seen ?? true
        }
        func deep(_ a: String, _ b: String, _ seconds: Double) -> Bool {
            AskMotion.inkMeets(lap.ink(a, at: seconds), lap.ink(b, at: seconds), within: -AskMotion.passesThrough)
        }
        var said: [String] = []
        // Only what moves: going into something that stays still is going
        // in behind its front, as the rules ask.
        for (mine, other, touch) in pairs where !lap.ink(mine, at: 0).isEmpty && !lap.ink(other, at: 0).isEmpty
            && (lap.isMover(other) || !lap.carriers(of: other).isEmpty) {
            // Drawn overlapping: always "inside" it, nothing to say.
            guard !deep(mine, other, 0) || !seen(mine, 0) else { continue }
            // From the touch on: what it does after it meets the other.
            var from: Double?, to: Double?
            var seconds = touch
            while seconds <= end + 0.0005 {
                if seen(mine, seconds), seen(other, seconds), deep(mine, other, seconds) {
                    if from == nil { from = seconds }
                    to = seconds
                } else if from != nil { break }
                seconds += 0.02
            }
            // A blink of overlap (a snap home at the lap's end) is the
            // landing's to hide, not a round of the plan.
            guard let from, let to, to - from >= 0.06 - 0.0005 else { continue }
            func said2(_ value: Double) -> String { String(format: "%g", (value * 100).rounded() / 100) }
            said.append("\(AskMotion.plain(mine)) passes through \(AskMotion.plain(other)) from \(said2(from)) s to \(said2(to)) s")
        }
        return said
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

    /// `step`'s value at `seconds`: straight between keys, standing on a
    /// Hold, its first before it and its last after.
    static func value(of step: AskStep, at seconds: Double) -> AgentJSON? {
        let keys = timed(step)
        guard let first = keys.first else { return nil }
        if seconds <= first.seconds { return first.value }
        for (one, next) in zip(keys, keys.dropFirst()) where seconds < next.seconds {
            if one.curve?.caseInsensitiveCompare(AgentKeyCurve.hold) == .orderedSame { return one.value }
            let share = (seconds - one.seconds) / max(next.seconds - one.seconds, 0.001)
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * share }
            if let a = one.value.doubleValue, let b = next.value.doubleValue { return .number(mix(a, b)) }
            if let ax = one.value["x"]?.doubleValue, let ay = one.value["y"]?.doubleValue,
               let bx = next.value["x"]?.doubleValue, let by = next.value["y"]?.doubleValue {
                return ["x": .number(mix(ax, bx)), "y": .number(mix(ay, by))]
            }
            return one.value
        }
        return keys.last?.value
    }

    /// The keys of a step by time, each with its value and curve.
    static func timed(_ step: AskStep) -> [(seconds: Double, value: AgentJSON, curve: String?)] {
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
                // The widest key too: from -12 in steps of 15 a swing to 14
                // was measured at 3 (the bell of 2026-11-11, cut by the frame).
                for degrees in Array(stride(from: least, through: most, by: 15)) + [most] {
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
    public static func problems(_ planned: [AskStep]) -> [String] {
        let through = throughWhatItTouches(planned)
        let steps = AskMotion.folded(AskMotion.touchesPlaced(planned))
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
        if !through.isEmpty {
            said.append("\(through.joined(separator: "; ")): what bounces off a part comes away from it, never through it. Call set_keys again with replace true for its position, the path after the touch going back the way it came or around that part.")
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
