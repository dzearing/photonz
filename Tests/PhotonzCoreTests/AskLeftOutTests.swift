import Foundation
@testable import PhotonzCore
import Testing

/// A change that stops short says so. On 2026-10-23 a model sent one refused
/// add_shape back three times and Ask offered the title, the subtitle and one
/// empty card as a finished pricing section, and a plan with one step that
/// failed as it ran threw every other step away.
@Suite("Ask: what a change left out")
struct AskLeftOutTests {

    static func reply(_ calls: [(String, String)], content: String = "") throws -> AgentJSON {
        try AskPlanningTests.reply(calls, content: content)
    }

    static let title = ("add_text", #"{"text":"Pricing","x":8,"y":8}"#)
    /// A rectangle with no frame, the call of the 2026-10-23 trace.
    static let noFrame = ("add_shape", ##"{"shape":"rectangle","stroke":"#D2D2D7","strokeWidth":1}"##)
    static let namedNoFrame = ("add_shape", #"{"shape":"rectangle","name":"Badge"}"#)
    static let framed = ("add_shape", #"{"shape":"rectangle","frame":{"x":20,"y":20,"width":100,"height":80}}"#)

    static func talk() throws -> AskConversation {
        var talk = AskPlanningTests.conversation("make a pricing section")
        _ = talk.take(try reply([title]))
        return talk
    }

    static func userTurns(_ talk: AskConversation) -> [String] {
        talk.messages.filter { $0["role"]?.stringValue == "user" }.compactMap { $0["content"]?.stringValue }
    }

    // MARK: While it plans

    @Test("A refused call sent back unchanged is taken out of the talk and the model asked to go on, for any tool")
    func repeatIsTakenOut() throws {
        var talk = try Self.talk()
        #expect(talk.take(try Self.reply([Self.noFrame])) == .again(looks: []))
        let refused = talk.messages.count
        #expect(talk.take(try Self.reply([Self.noFrame])) == .again(looks: []))
        #expect(talk.messages.count == refused + 1, "the repeat and its answer are gone, one line asking to go on is added")
        let asked = talk.messages.last
        #expect(asked?["role"]?.stringValue == "user")
        #expect(asked?["content"]?.stringValue?.contains("add_shape") == true)
        #expect(asked?["content"]?.stringValue?.contains("or finish") == true)
    }

    @Test("A model that goes on after a repeat finishes with the rest of the plan, and nothing extra is said")
    func goingOnFinishes() throws {
        var talk = try Self.talk()
        _ = talk.take(try Self.reply([Self.noFrame]))
        _ = talk.take(try Self.reply([Self.noFrame]))
        #expect(talk.take(try Self.reply([Self.framed])) == .again(looks: []))
        guard case .planned(let plan) = talk.take(try Self.reply([], content: "Done.")) else {
            Issue.record("the model finished"); return
        }
        #expect(plan.steps.map(\.tool) == ["add_text", "add_shape"])
        #expect(plan.unplanned == nil, "the shape it could not plan came right on the next try")
    }

    @Test("A named thing that was left out and never came back is said, even when the model finished")
    func leftOutAndFinished() throws {
        var talk = try Self.talk()
        _ = talk.take(try Self.reply([Self.namedNoFrame]))
        _ = talk.take(try Self.reply([Self.namedNoFrame]))
        _ = talk.take(try Self.reply([Self.framed]))
        guard case .planned(let plan) = talk.take(try Self.reply([], content: "Done.")) else {
            Issue.record("the model finished"); return
        }
        #expect(plan.unplanned?.sentence == "Left out Badge; it could not be planned.")
    }

    @Test("A model that sends it back even after being told to leave it out stops, and the plan says where")
    func stopShortCarriesTheSentence() throws {
        var talk = try Self.talk()
        _ = talk.take(try Self.reply([Self.noFrame]))
        _ = talk.take(try Self.reply([Self.noFrame]))
        guard case .planned(let plan) = talk.take(try Self.reply([Self.noFrame])) else {
            Issue.record("still asking after being told to leave it out"); return
        }
        #expect(plan.steps.map(\.tool) == ["add_text"])
        #expect(plan.unplanned?.sentence == "Stopped after \u{201C}Pricing\u{201D}; the rest could not be planned.")
    }

    @Test("A repeat of something the plan already holds stops nothing short: nothing was lost")
    func repeatOfAPlannedStepLosesNothing() throws {
        var talk = try Self.talk()
        for _ in 0..<2 { _ = talk.take(try Self.reply([Self.title])) }
        guard case .planned(let plan) = talk.take(try Self.reply([Self.title])) else {
            Issue.record("still asking after three repeats"); return
        }
        #expect(plan.steps.count == 1)
        #expect(plan.unplanned == nil)
    }

    @Test("A turn that also planned something is left in the talk: the model is getting somewhere")
    func aMixedTurnStays() throws {
        var talk = try Self.talk()
        _ = talk.take(try Self.reply([Self.noFrame]))
        let before = talk.messages.count
        #expect(talk.take(try Self.reply([Self.noFrame, Self.framed])) == .again(looks: []))
        #expect(talk.messages.count == before + 3, "its turn and both answers stay")
        #expect(talk.steps.count == 2)
    }

    @Test("A call repeated with another between them is still a repeat")
    func interleavedRepeat() throws {
        var talk = try Self.talk()
        let other = ("add_shape", #"{"shape":"ellipse"}"#)
        _ = talk.take(try Self.reply([Self.noFrame]))
        _ = talk.take(try Self.reply([other]))
        _ = talk.take(try Self.reply([Self.noFrame]))
        #expect(Self.userTurns(talk).last?.hasPrefix("Leave") == true)
    }

    @Test("Running out of rounds or a reply that cannot be read carries the same sentence; a finished plan says nothing")
    func otherStops() throws {
        let talk = try Self.talk()
        #expect(talk.plan(summary: "", stoppedShort: true).unplanned?.sentence
                == "Stopped after \u{201C}Pricing\u{201D}; the rest could not be planned.")
        #expect(talk.plan(summary: "Done.").unplanned == nil)
    }

    @Test("What the plan could not make survives a drawing's plan being set")
    func carriedThroughTheDrawingPlan() throws {
        let plan = try Self.talk().plan(summary: "", stoppedShort: true)
        #expect(plan.settingDrawingPlan(step: 1, to: ["a"]).unplanned == plan.unplanned)
        #expect(plan.replacingDrawingPlan(step: 1, with: []).unplanned == plan.unplanned)
    }

    @Test("Many things left out stay one short line")
    func manyThings() {
        let two = AskUnplanned(things: ["Badge", "Footer"], stoppedAfter: nil)
        #expect(two.sentence == "Left out Badge and Footer; they could not be planned.")
        let four = AskUnplanned(things: ["Badge", "Footer", "Note", "Tabs"], stoppedAfter: nil)
        #expect(four.sentence == "Left out Badge and 3 more; they could not be planned.")
    }

    // MARK: As it runs

    static let gone = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"

    static func step(_ tool: String, _ arguments: AgentJSON) -> AskStep { AskStep(tool: tool, arguments: arguments) }

    /// Runs a plan the way the app does, a step at a time, with `answer`
    /// standing in for the document: nil lands the step, words refuse it.
    static func run(_ plan: AskPlan, answer: (Int, AskStep) -> String? = { _, _ in nil }) -> AskPlanRun {
        var run = AskPlanRun(plan: plan)
        for (index, step) in plan.steps.enumerated() {
            let number = index + 1
            if run.passOver(number) { continue }
            if let refusal = answer(number, step) {
                run.leaveOut(number, because: refusal)
            } else {
                run.land(number, id: "layer-\(number)")
            }
        }
        return run
    }

    /// A step naming a layer the document does not have fails, as it does in
    /// the app (`AgentWork`).
    static func noSuchLayer(_ number: Int, _ step: AskStep) -> String? {
        step.arguments["layer"]?.stringValue == gone ? "set_layer: there is no layer \(gone)." : nil
    }

    @Test("One step that fails as it runs leaves every other step made, and the line says which and why")
    func oneFailedStep() {
        let plan = AskPlan(steps: [
            Self.step("add_text", ["text": "Pricing"]),
            Self.step("set_layer", ["layer": .string(Self.gone), "name": "Card Pro"]),
            Self.step("add_text", ["text": "Per month"]),
        ], summary: "")
        let run = Self.run(plan) { number, step in
            number == 2 ? "set_layer: Card is locked." : Self.noSuchLayer(number, step)
        }
        #expect(run.landed.count == 2)
        #expect(run.leftOut.map(\.number) == [2])
        #expect(run.sentence == "Left out Card Pro: Card is locked.")
    }

    @Test("A step counting on a failed step is left out too, along with what counts on it, and the line says so")
    func dependentsGoToo() {
        let plan = AskPlan(steps: [
            Self.step("add_shape", ["name": "Card", "shape": "rectangle"]),
            Self.step("set_layer", ["layer": "$1", "fill": "#FFFFFF"]),
            Self.step("set_layer", ["layer": "$2", "x": 4]),
            Self.step("add_text", ["text": "Unrelated"]),
        ], summary: "")
        let run = Self.run(plan) { number, _ in number == 1 ? "add_shape: a rectangle needs a frame." : nil }
        #expect(run.landed.map(\.tool) == ["add_text"])
        #expect(run.leftOut.map(\.number) == [1, 2, 3])
        #expect(run.leftOut.map(\.needed) == [nil, 1, 2])
        #expect(run.sentence == "Left out Card and 2 steps that needed it: a rectangle needs a frame.")
    }

    @Test("A $ in a person's words is not a step counting on another")
    func priceIsNotAStep() {
        let plan = AskPlan(steps: [
            Self.step("add_shape", ["name": "Card", "shape": "rectangle"]),
            Self.step("add_text", ["text": "$1"]),
        ], summary: "")
        let run = Self.run(plan) { number, _ in number == 1 ? "Card is locked." : nil }
        #expect(run.landed.map(\.tool) == ["add_text"])
    }

    @Test("What a later step reads of an earlier one is what that step made")
    func madeIsKept() {
        let plan = AskPlan(steps: [Self.step("add_text", ["text": "A"])], summary: "")
        #expect(Self.run(plan).made == [1: "layer-1"])
    }

    @Test("Several failed steps stay one line, a reason in code words is never shown, and a clean run says nothing")
    func theLine() {
        let plan = AskPlan(steps: [
            Self.step("set_layer", ["layer": .string(Self.gone), "name": "One"]),
            Self.step("set_layer", ["layer": .string(Self.gone), "name": "Two"]),
            Self.step("add_text", ["text": "Kept"]),
        ], summary: "")
        let run = Self.run(plan, answer: Self.noSuchLayer)
        #expect(run.sentence == "Left out One and 1 more: that layer is not there.")
        #expect(Self.run(AskPlan(steps: [Self.step("add_text", ["text": "A"])], summary: "")).sentence == nil)
    }

    @Test("A reason is shown only as a person can read it")
    func reasons() {
        #expect(AskLeftOutWords.reason("set_layer: Card is locked.") == "Card is locked")
        #expect(AskLeftOutWords.reason("There is no layer \(Self.gone) in this document. read_document lists the layer ids.")
                == "that layer is not there")
        #expect(AskLeftOutWords.reason("change_part: there is no layer $4. read_document lists the layers.") == "that layer is not there")
        #expect(AskLeftOutWords.reason("Layer \(Self.gone) moved.") == AskLeftOutWords.noReason)
        #expect(AskLeftOutWords.reason("use read_document first") == AskLeftOutWords.noReason)
        #expect(AskLeftOutWords.reason(String(repeating: "long ", count: 30)) == AskLeftOutWords.noReason)
        #expect(AskLeftOutWords.reason("") == AskLeftOutWords.noReason)
    }

    @Test("What a step is called in the line: its name, its words, or the kind of thing")
    func things() {
        #expect(AskLeftOutWords.thing(Self.step("add_shape", ["name": "Card", "shape": "rectangle"])) == "Card")
        #expect(AskLeftOutWords.thing(Self.step("add_text", ["text": "Get started"])) == "\u{201C}Get started\u{201D}")
        #expect(AskLeftOutWords.thing(Self.step("add_shape", ["shape": "rectangle"])) == "a shape")
        #expect(AskLeftOutWords.thing(Self.step("no_such_tool", [:])) == "a step")
    }

    @Test("A plan's own shortfall and a run's are said together")
    func bothTogether() throws {
        let plan = AskPlan(steps: [
            Self.step("add_text", ["text": "A"]), Self.step("add_text", ["text": "B"]),
        ], summary: "", unplanned: AskUnplanned(things: [], stoppedAfter: "\u{201C}B\u{201D}"))
        let run = Self.run(plan) { number, _ in number == 1 ? "A is locked." : nil }
        #expect(run.sentence == "Stopped after \u{201C}B\u{201D}; the rest could not be planned. Left out \u{201C}A\u{201D}: A is locked.")
    }

    // MARK: A walk's stand-in for the model

    @Test("A walk's setup can answer for the model, one reply a turn, and anything else is an error")
    func walkReplies() throws {
        let said = try PlaytestScript.decode(Data(#"{"out":"/tmp/x","setup":{"askReplies":[{"message":{"content":"Done."}}]},"steps":[]}"#.utf8))
        #expect(said.setup.askReplies.count == 1)
        #expect(!said.setup.isEmpty)
        let reply = try AgentJSON.parse(Data(said.setup.askReplies[0].utf8))
        #expect(reply["message"]?["content"]?.stringValue == "Done.")
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(Data(#"{"out":"/tmp/x","setup":{"askReplies":["Done."]},"steps":[]}"#.utf8))
        }
    }

    // MARK: The row

    @Test("The row keeps what was left out, and a change that made it all has nothing there")
    func rowKeepsIt() throws {
        let before = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10), layers: [])
        let after = PhotonzDocument(canvasSize: CGSize(width: 20, height: 10), layers: [])
        var list = AskChangeList()
        let short = list.record(asked: "x", sentence: "Added text", before: before, after: after, leftOut: "Left out Card.")
        let whole = list.record(asked: "y", sentence: "Added text", before: before, after: after)
        #expect(list.row(try #require(short))?.leftOut == "Left out Card.")
        #expect(list.row(try #require(whole))?.leftOut == nil)
    }

    @Test("A row for a change that stopped short says what landed, never the request as if it were done")
    func rowDoesNotClaimTheRequest() {
        let steps = [Self.step("add_text", ["text": "Pricing"]), Self.step("add_shape", ["shape": "rectangle"])]
        #expect(AskChangeWords.sentence(steps, asked: "make a pricing section") == "Made a pricing section")
        let partly = AskChangeWords.sentence(steps, asked: "make a pricing section", madeAll: false)
        
        #expect(partly == "Added the text \u{201C}Pricing\u{201D} and 1 more")
    }
}
