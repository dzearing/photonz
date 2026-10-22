import Foundation
@testable import PhotonzCore
import Testing

/// Ask drawing a thing (`docs/design/ask.md`, "Drawing a thing"): one
/// add_drawing call, from the built-in set or the model's own SVG, then a look
/// by a model that can see before it hands back.
@Suite("Ask draws a thing, and looks at it before handing back")
struct AskDrawingTests {

    static let circle = ##"<svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#C1694F"/></svg>"##

    static let library = DrawingLibrary(entries: [
        .init(name: "dog", words: ["pet"], svg: circle, aliases: ["puppy"]),
        .init(name: "slightly smiling face", words: ["face", "smile"], svg: circle, aliases: ["smiley", "smiley face"]),
    ])

    static func conversation(_ request: String = "draw a dog") -> AskConversation {
        AskConversation(request: request, documentRead: #"{"canvas":{"width":1440,"height":1024}}"#, drawings: library)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    static func lastTold(_ talk: AskConversation) -> String {
        talk.messages.last?["content"]?.stringValue ?? ""
    }

    // MARK: Planning a drawing

    @Test("A thing the set has is planned from its name alone")
    func builtInPlanned() {
        var talk = Self.conversation()
        _ = talk.take(Self.reply("add_drawing", ["subject": "dog"]))
        #expect(talk.steps.count == 1)
        #expect(Self.lastTold(talk).hasPrefix("Planned as step 1"))
    }

    @Test("A thing the set lacks, with no SVG, goes back to the model to draw it itself")
    func missingNeedsSVG() {
        var talk = Self.conversation("draw a bicycle")
        _ = talk.take(Self.reply("add_drawing", ["subject": "bicycle"]))
        #expect(talk.steps.isEmpty)
        #expect(Self.lastTold(talk).contains("no drawing of bicycle"))
        #expect(Self.lastTold(talk).contains("svg"))
    }

    @Test("The model's own SVG is read before it is planned, and a broken one goes back with why")
    func svgChecked() {
        var talk = Self.conversation("draw a bicycle")
        _ = talk.take(Self.reply("add_drawing", ["subject": "bicycle", "svg": "<svg><circle r=\"5\""]))
        #expect(talk.steps.isEmpty)
        #expect(Self.lastTold(talk).contains("XML"))
        _ = talk.take(Self.reply("add_drawing", ["subject": "bicycle", "svg": .string(Self.circle)]))
        #expect(talk.steps.count == 1)
    }

    @Test("The instructions send a drawing of a thing to add_drawing, with no words or components on it")
    func instructionsSayDraw() {
        let instructions = AskConversation.instructions(documentRead: "{}")
        #expect(instructions.contains("add_drawing"))
        #expect(instructions.contains("icon"))
    }

    // MARK: Looking

    @Test("The drawings a plan makes are found, with what each was asked to be")
    func drawingsInPlan() {
        let plan = AskPlan(steps: [AskStep(tool: "add_text", arguments: ["text": "Hi", "x": 0, "y": 0]),
                                   AskStep(tool: "add_drawing", arguments: ["subject": "dog"])], summary: "")
        let found = AskDrawingCheck.drawings(in: plan)
        #expect(found.count == 1)
        #expect(found.first?.step == 2 && found.first?.subject == "dog")
    }

    @Test("What the looker saw counts as the thing when it names it or a word for it",
          arguments: [("Dog.", "dog", true), ("A puppy", "dog", true), ("Smiling face.", "smiley face", true),
                      ("Sun, mountains.", "sun over mountains", true), ("Coffee Mug", "coffee cup", true)])
    func reads(seen: String, subject: String, expected: Bool) {
        #expect(AskDrawingCheck.reads(seen, as: subject, library: Self.library) == expected)
    }

    @Test("What the looker saw that shares no word with the thing is left to the model to judge",
          arguments: [("Mouse.", "dog"), ("A yellow circle", "smiley face"), ("Bear", "cat")])
    func unsure(seen: String, subject: String) {
        #expect(AskDrawingCheck.reads(seen, as: subject, library: Self.library) == nil)
    }

    @Test("The judge's yes or no is read off the start of its answer")
    func judgeAnswer() {
        #expect(AskDrawingCheck.judged("Yes, a mouse could pass") == true)
        #expect(AskDrawingCheck.judged("no.") == false)
        #expect(AskDrawingCheck.judged("Maybe") == false)
    }

    @Test("A drawing that did not read is drawn again with what was seen, the plan started afresh")
    func revise() {
        var talk = Self.conversation()
        _ = talk.take(Self.reply("add_drawing", ["subject": "dog", "builtIn": false, "svg": .string(Self.circle)]))
        #expect(talk.steps.count == 1)
        talk.revise(subject: "dog", seen: "Mouse.")
        #expect(talk.steps.isEmpty)
        #expect(talk.rounds == 0)
        let told = Self.lastTold(talk)
        #expect(told.contains("Mouse") && told.contains("dog") && told.contains("add_drawing"))
    }

    @Test("The vision request carries the picture and no hint of what was asked")
    func visionBody() {
        let body = AskDrawingCheck.visionBody(model: "llama3.2-vision:latest", png: Data([1, 2, 3]))
        let message = body["messages"]?.arrayValue?.first
        #expect(message?["images"]?.arrayValue?.first?.stringValue == Data([1, 2, 3]).base64EncodedString())
        #expect(message?["content"]?.stringValue == AskDrawingCheck.seePrompt)
        #expect(body["options"]?["num_ctx"]?.doubleValue == Double(AskDrawingCheck.visionContextWindow))
    }

    @Test("Asking the planning model to judge keeps its own window, so it is not loaded again")
    func judgeKeepsTheWindow() {
        let body = AskDrawingCheck.judgeBody(model: "qwen3:30b", subject: "dog", seen: "Mouse")
        #expect(body["options"]?["num_ctx"]?.doubleValue == Double(AskConversation.contextWindow))
    }

    @Test("A planning model that can see does its own looking; one that cannot hands it to the first on the Mac that can")
    func visionModel() {
        #expect(AskModels.eyes(planner: "qwen3.6:35b", plannerSees: true, installed: ["qwen3.6:35b", "llama3.2-vision:latest"]) == "qwen3.6:35b")
        #expect(AskModels.eyes(planner: "qwen3:30b", plannerSees: false, installed: ["qwen3:30b", "llama3.2-vision:latest"]) == "llama3.2-vision:latest")
        #expect(AskModels.eyes(planner: "qwen3:30b", plannerSees: false, installed: ["qwen3:30b"]) == nil)
    }

    @Test("The planning model looking keeps its own window and does not think, so it is not loaded again")
    func plannerLooksInItsOwnWindow() {
        let body = AskDrawingCheck.visionBody(model: "qwen3.6:35b", png: Data([1]), planner: true)
        #expect(body["options"]?["num_ctx"]?.doubleValue == Double(AskConversation.contextWindow))
        #expect(body["think"]?.boolValue == false)
        let separate = AskDrawingCheck.visionBody(model: "llama3.2-vision:latest", png: Data([1]))
        #expect(separate["think"] == nil)
    }
}
