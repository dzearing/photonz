import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// An animated icon told as a little story (task
/// `an-animated-icon-told-as-a-little-story-moves-th`): the user asked for a
/// lid that opens, trash thrown in that bounces off the lid and closes it, and
/// got a still, because Ask told a moving icon from a still one by an exact
/// word. Nothing here knows what any icon is of.
@Suite("An animated icon told as a story")
struct AskMotionStoryTests {

    static let svg = AskMotionTests.svg

    static func told(_ request: String, design: String? = "1) the thing 2) parts 3) beats") -> AskConversation {
        AskConversation(request: request, documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#,
                        paints: true, iconDesign: design, toldMotion: true)
    }

    // MARK: Which requests move

    @Test("A slip of the keyboard in the word for motion still asks for motion, and words that only look alike do not")
    func typos() {
        for asked in ["make an anmiated trash icon", "an animted icon of a bell", "make an aniamted svg of a kite",
                      "an animatd heart icon", "an animaton of a heart icon", "an annimated gif of a ball"] {
            #expect(AskMotion.asksToMove(asked), "\(asked)")
            #expect(AskMotion.drawsMotion(asked), "\(asked)")
        }
        for asked in ["an animal icon", "an icon of animals", "an anime icon", "an animator icon", "a cinema icon",
                      "an icon of an aminal", "a laminated card icon"] {
            #expect(!AskMotion.asksToMove(asked), "\(asked)")
        }
    }

    @Test("The model is asked whether a request moves, in one short call, and its answer is read")
    func movesQuestion() {
        let body = AskMotion.movesBody(model: "m", request: "a trash icon where the lid opens and closes")
        let asked = body["messages"]?.arrayValue?.last?["content"]?.stringValue ?? ""
        #expect(asked.hasSuffix("a trash icon where the lid opens and closes"))
        #expect(asked.contains("moves"))
        #expect(asked.contains("still"))
        #expect(body["tools"] == nil)
        #expect(body["options"]?["temperature"]?.doubleValue == 0)
        #expect(AskMotion.moves(fromAnswer: "moves"))
        #expect(AskMotion.moves(fromAnswer: "Moves."))
        #expect(AskMotion.moves(fromAnswer: "<think>\n\n</think>\n\nmoves"))
        #expect(!AskMotion.moves(fromAnswer: "still"))
        #expect(!AskMotion.moves(fromAnswer: "Still."))
        #expect(!AskMotion.moves(fromAnswer: ""))
        #expect(!AskMotion.moves(fromAnswer: "It is a still icon, it never moves."))
    }

    @Test("A story the model says moves is drawn as a moving icon, though no word asked for motion")
    func toldMoves() {
        let request = "make a trash icon where the lid opens and some trash is thrown in, bouncing off the lid and closing it"
        #expect(!AskMotion.drawsMotion(request))
        let talk = Self.told(request)
        #expect(Set(talk.doingTools) == Set(AskMotion.tools))
        let still = AskConversation(request: request, documentRead: #"{"kind":"picture","canvas":{"width":1440,"height":1024}}"#, paints: true)
        #expect(!still.doingTools.contains("set_keys"))
    }

    // MARK: Every beat

    @Test("A designed moving icon is sent back once to check its beats in order before it lands")
    func beatsReviewed() throws {
        var talk = Self.told("make an animated icon of a thing that opens and closes")
        _ = talk.take(AskMotionTests.reply("add_drawing", ["subject": "thing", "svg": .string(Self.svg)]))
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":125},{"seconds":1,"value":100}]}"#)))
        guard case .again = talk.take(AskMotionTests.said("Done.")) else { Issue.record("the beats are checked once"); return }
        let asked = talk.messages.last?["content"]?.stringValue ?? ""
        #expect(asked.contains("beat"))
        #expect(asked.contains("Left out:"))
        guard case .planned(let plan) = talk.take(AskMotionTests.said("Done.")) else { Issue.record("then it lands"); return }
        #expect(plan.unplanned == nil)
    }

    @Test("What the model says it left out is on the row, and a plan that never moved says the motion was left out")
    func leftOut() throws {
        var talk = Self.told("make an animated icon of a thing that opens, bounces and closes")
        _ = talk.take(AskMotionTests.reply("add_drawing", ["subject": "thing", "svg": .string(Self.svg)]))
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":125},{"seconds":1,"value":100}]}"#)))
        _ = talk.take(AskMotionTests.said("Done."))
        guard case .planned(let plan) = talk.take(AskMotionTests.said("It opens and closes.\nLeft out: the bounce")) else {
            Issue.record("it lands"); return
        }
        #expect(plan.unplanned?.things == ["the bounce"])
        #expect(plan.unplanned?.sentence == "Left out the bounce; it could not be planned.")
        #expect(!plan.summary.contains("Left out"))

        var still = Self.told("make an animated icon of a thing", design: nil)
        _ = still.take(AskMotionTests.reply("add_drawing", ["subject": "thing", "svg": .string(Self.svg)]))
        var outcome = still.take(AskMotionTests.said("Done."))
        while case .again = outcome { outcome = still.take(AskMotionTests.said("Done.")) }
        guard case .planned(let drawn) = outcome else { Issue.record("it lands, drawn"); return }
        #expect(drawn.unplanned?.things == ["the motion"])
    }

    @Test("Saying nothing was left out leaves nothing on the row")
    func nothingLeftOut() throws {
        var talk = Self.told("make an animated icon of a thing that opens and closes")
        _ = talk.take(AskMotionTests.reply("add_drawing", ["subject": "thing", "svg": .string(Self.svg)]))
        _ = talk.take(AskMotionTests.reply("set_keys", try AskMotionTests.args(#"{"layer":"$1/whole","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.5,"value":125},{"seconds":1,"value":100}]}"#)))
        _ = talk.take(AskMotionTests.said("Done."))
        for none in ["Left out: nothing", "Left out: none", "Left out: nothing."] {
            var copy = talk
            guard case .planned(let plan) = copy.take(AskMotionTests.said("Every beat is keyed.\n\(none)")) else { Issue.record("lands"); return }
            #expect(plan.unplanned == nil, "\(none)")
        }
    }

    @Test("The rules teach a story's beats in order, each long enough to see, and the whole object moving as one")
    func storyRules() {
        let rules = AskMotion.drawRules
        #expect(rules.contains("in the order told"))
        #expect(AskMotion.designAsk.contains("in the order the request tells them"))
    }
}

/// Checks a moving icon's keys are seen: a journey too quick to follow and a
/// motion too small to read at icon size go back, with their numbers.
@Suite("A moving icon's beats can be seen")
struct AskMotionSeenTests {

    static func step(_ json: String) throws -> AskStep { AskStep(tool: "set_keys", arguments: try AskMotionTests.args(json)) }

    @Test("A part that crosses most of the icon in a blink goes back; one seen the whole way, or unseen, does not")
    func tooQuick() throws {
        let blink = try Self.step(#"{"layer":"$1/whole","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.4,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":0,"y":-30}},{"seconds":2,"value":{"x":0,"y":0}}]}"#)
        let said = AskMotionCheck.problems([blink]).joined(separator: " ")
        #expect(said.contains("whole travels 30 on the grid in 100 ms"), "\(said)")
        let seen = try Self.step(#"{"layer":"$1/whole","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.4,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":0,"y":-30}},{"seconds":2,"value":{"x":0,"y":0}}]}"#)
        #expect(AskMotionCheck.problems([seen]).isEmpty)
        // Back from the other side on a Hold, or while it is unseen: no journey to see.
        let held = try Self.step(#"{"layer":"$1/whole","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":0,"y":-30},"curve":"Hold"},{"seconds":0.85,"value":{"x":0,"y":30}},{"seconds":2,"value":{"x":0,"y":0}}]}"#)
        #expect(AskMotionCheck.problems([held]).isEmpty)
        let jump = try Self.step(#"{"layer":"$1/whole","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.8,"value":{"x":0,"y":-30}},{"seconds":0.85,"value":{"x":0,"y":30}},{"seconds":2,"value":{"x":0,"y":0}}]}"#)
        let hidden = try Self.step(#"{"layer":"$1/whole","property":"opacity","keys":[{"seconds":0,"value":100},{"seconds":0.78,"value":100},{"seconds":0.8,"value":0},{"seconds":0.85,"value":0},{"seconds":1.2,"value":100},{"seconds":2,"value":100}]}"#)
        #expect(AskMotionCheck.problems([jump, hidden]).isEmpty)
        #expect(!AskMotionCheck.problems([jump]).isEmpty)
    }

    @Test("A shake, a nudge or a beat too small to read at icon size goes back; one big enough does not")
    func tooSmall() throws {
        let nudge = try Self.step(#"{"layer":"$1/body","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.1,"value":{"x":0.3,"y":0}},{"seconds":0.2,"value":{"x":-0.3,"y":0}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        let wobble = try Self.step(#"{"layer":"$1/body","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.1,"value":2},{"seconds":0.2,"value":-2},{"seconds":1,"value":0}]}"#)
        let beat = try Self.step(#"{"layer":"$1/body","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.2,"value":103},{"seconds":1,"value":100}]}"#)
        let said = AskMotionCheck.problems([nudge, wobble, beat]).joined(separator: " ")
        for part in ["position", "rotation", "scale"] { #expect(said.contains("body's \(part)"), "\(said)") }
        #expect(said.contains("too small to see"))
        let shake = try Self.step(#"{"layer":"$1/body","property":"rotation","keys":[{"seconds":0,"value":0},{"seconds":0.1,"value":8},{"seconds":0.2,"value":-8},{"seconds":1,"value":0}]}"#)
        let pulse = try Self.step(#"{"layer":"$1/body","property":"scale","keys":[{"seconds":0,"value":100},{"seconds":0.2,"value":115},{"seconds":1,"value":100}]}"#)
        let move = try Self.step(#"{"layer":"$1/body","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.3,"value":{"x":1.5,"y":0}},{"seconds":1,"value":{"x":0,"y":0}}]}"#)
        #expect(AskMotionCheck.problems([shake, pulse, move]).isEmpty)
    }
}

@Suite("A part that turns never swings into what stays still")
struct AskMotionSwingTests {

    static let svg = ##"""
    <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><g id="base"><path id="body" d="M5 8 L6 20 L18 20 L19 8"/><line id="rim" x1="4" y1="8" x2="20" y2="8"/></g><g id="lid"><line id="top" x1="5" y1="5" x2="19" y2="5"/></g><path id="mark" d="M21 3 L22 2"/></svg>
    """##
    static let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])
    static func turn(_ value: Int, pivotX: Int) throws -> AskStep {
        AskStep(tool: "set_keys", arguments: try AskMotionTests.args(#"{"layer":"$1/lid","property":"rotation","pivot":{"x":\#(pivotX),"y":5},"keys":[{"seconds":0,"value":0},{"seconds":0.5,"value":\#(value)},{"seconds":1,"value":0}]}"#))
    }

    @Test("Hinged at its right end, a negative turn swings the far end down into the body and goes back; the other way does not")
    func intoTheBody() throws {
        let said = AskMotionCheck.problems([Self.drawing, try Self.turn(-35, pivotX: 19)]).joined(separator: " ")
        #expect(said.contains("lid turning -35 swings into base"), "\(said)")
        #expect(said.contains("other way"))
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(35, pivotX: 19)]).isEmpty)
        #expect(AskMotionCheck.problems([Self.drawing, try Self.turn(-35, pivotX: 5)]).isEmpty)
        let said2 = AskMotionCheck.problems([Self.drawing, try Self.turn(35, pivotX: 5)]).joined(separator: " ")
        #expect(said2.contains("lid turning 35 swings into base"), "\(said2)")
    }
}

@Suite("A position is how far a part moved, not where it is")
struct AskMotionWhereTests {

    static let svg = ##"""
    <svg viewBox="0 0 24 24" fill="none" stroke="#1D1D1F" stroke-width="2"><path id="can" d="M5 8 L6 20 L18 20 L19 8"/><g id="trash"><circle id="ball" cx="12" cy="14" r="1.5"/></g></svg>
    """##
    static let drawing = AskStep(tool: "add_drawing", arguments: ["subject": "thing", "svg": .string(svg)])

    @Test("Keys that start where the part was drawn are where it is, not how far it moved: they go back")
    func whereItIs() throws {
        let absolute = AskStep(tool: "set_keys", arguments: try AskMotionTests.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":12,"y":14}},{"seconds":0.5,"value":{"x":18,"y":2}},{"seconds":1,"value":{"x":12,"y":14}}]}"#))
        let said = AskMotionCheck.problems([Self.drawing, absolute]).joined(separator: " ")
        #expect(said.contains("trash's position starts at x 12 y 14, where it was drawn"), "\(said)")
        let moved = AskStep(tool: "set_keys", arguments: try AskMotionTests.args(#"{"layer":"$1/trash","property":"position","keys":[{"seconds":0,"value":{"x":0,"y":0}},{"seconds":0.5,"value":{"x":6,"y":-12}},{"seconds":1,"value":{"x":0,"y":0}}]}"#))
        #expect(AskMotionCheck.problems([Self.drawing, moved]).isEmpty)
    }
}
