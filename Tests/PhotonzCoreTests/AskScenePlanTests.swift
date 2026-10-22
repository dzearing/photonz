import Foundation
@testable import PhotonzCore
import Testing

/// A drawing shows what was asked, pose and all (`docs/design/ask.md`,
/// "A pose or a scene is planned, then checked"): the planning model writes
/// what has to be true of the picture (who is in it, what each is doing, the
/// view, which parts touch, what is in front), the picture model is asked to
/// paint exactly that, and the look checks each statement against the drawing
/// it made. Nothing here knows any subject: the statements are the model's.
@Suite("Ask plans a pose or a scene and checks the drawing against it")
struct AskScenePlanTests {

    static let piano: [AgentJSON] = ["the cat sits on a bench facing the piano", "its front paws rest on the keys",
                                     "the keys show"]

    static func conversation(_ request: String, paints: Bool = true) -> AskConversation {
        AskConversation(request: request, documentRead: #"{"canvas":{"width":1440,"height":1024}}"#, paints: paints)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    // MARK: The plan reaches the call

    @Test("add_drawing reads the plan's statements into the call, trimmed, empties dropped")
    func toolReadsPlan() {
        let made = AgentTools.request(tool: "add_drawing", arguments: [
            "subject": "a cat playing a piano", "plan": .array(Self.piano + ["  ", ""]),
        ])
        guard case .success(.addDrawing(_, let call)) = made else {
            Issue.record("not an add_drawing: \(made)")
            return
        }
        #expect(call.plan == Self.piano.compactMap(\.stringValue))
    }

    @Test("A plan written as one string is split into its statements")
    func planAsOneString() {
        #expect(AgentDrawingCall.statements(.string("the dog runs left; the ball is ahead of its nose\nboth on grass"))
                == ["the dog runs left", "the ball is ahead of its nose", "both on grass"])
        #expect(AgentDrawingCall.statements(nil).isEmpty)
    }

    @Test("At most six statements are kept, so the picture model's words stay about the picture")
    func planIsShort() {
        let many: AgentJSON = .array((1...9).map { .string("statement \($0)") })
        #expect(AgentDrawingCall.statements(many).count == AgentDrawingCall.mostStatements)
    }

    @Test("The plan is part of the add_drawing tool the model is given")
    func toolSchemaHasPlan() {
        let tool = AgentTools.all.first { $0.name == "add_drawing" }
        #expect(tool?.inputSchema["properties"]?["plan"] != nil)
    }

    @Test("The painting instructions ask for a plan: who, doing what, the view, what touches, what is in front")
    func instructionsAskForAPlan() {
        let painting = AskConversation.instructions(documentRead: "{}", paints: true)
        #expect(painting.contains("plan"))
        #expect(painting.contains("touch"))
        #expect(painting.contains("in front"))
    }

    @Test("A planned drawing keeps its plan in the step")
    func planSurvivesPlanning() {
        var talk = Self.conversation("draw a piano with a cartoon cat playing it")
        _ = talk.take(Self.reply("add_drawing", ["subject": "a cartoon cat playing a piano", "plan": .array(Self.piano)]))
        #expect(talk.steps.first?.arguments["plan"]?.arrayValue?.count == 3)
    }

    @Test("A second drawing on top of the first is refused: a scene is one drawing, never two stacked")
    func secondDrawingOnTopRefused() {
        var talk = Self.conversation("draw a dog chasing a ball")
        _ = talk.take(Self.reply("add_drawing", ["subject": "dog chasing a ball", "plan": ["the dog runs", "the ball is ahead of it"]]))
        _ = talk.take(Self.reply("add_drawing", ["subject": "dog chasing a ball", "plan": ["the dog runs"]]))
        #expect(talk.steps.count == 1)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("step 1") == true)
    }

    @Test("Drawings side by side, each in its own box, are both planned")
    func drawingsSideBySide() {
        var talk = Self.conversation("draw a sun icon and a moon icon side by side")
        _ = talk.take(Self.reply("add_drawing", ["subject": "sun", "frame": ["x": 100, "y": 100, "width": 400, "height": 400]]))
        _ = talk.take(Self.reply("add_drawing", ["subject": "moon", "frame": ["x": 800, "y": 100, "width": 400, "height": 400]]))
        #expect(talk.steps.count == 2)
    }

    // MARK: What the picture model is asked

    @Test("The picture model is asked for the subject, the person's words and every statement of the plan")
    func paintingRequestCarriesPlan() {
        let call = AgentDrawingCall(subject: "a cartoon cat playing a piano", asked: "draw a piano with a cartoon cat playing it",
                                    plan: ["the cat sits facing the piano", "its paws rest on the keys"])
        let asked = PictureModelRequest(call)
        #expect(asked.subject.hasPrefix("a cartoon cat playing a piano, from the request: draw a piano with a cartoon cat playing it."))
        #expect(asked.subject.contains("the cat sits facing the piano. its paws rest on the keys"))
        #expect(PictureModelRequest(AgentDrawingCall(subject: "bicycle")).subject == "bicycle")
    }

    // MARK: The look checks the plan

    @Test("The plan check shows the picture and asks yes or no for each statement, numbered")
    func planBody() throws {
        let body = AskDrawingCheck.planBody(model: "eyes", png: Data([1, 2, 3]),
                                            plan: ["the cat faces the keys", "its paws touch the keys"])
        let message = try #require(body["messages"]?.arrayValue?.first)
        let words = message["content"]?.stringValue ?? ""
        #expect(words.contains("1. the cat faces the keys"))
        #expect(words.contains("2. its paws touch the keys"))
        #expect(message["images"]?.arrayValue?.count == 1)
    }

    @Test("Statements answered no are the ones the drawing misses")
    func unmetStatements() {
        let plan = ["the cat faces away from us", "its tail curls round", "no face shows"]
        #expect(AskDrawingCheck.unmet("1 yes\n2. No\n3: no", plan: plan) == ["its tail curls round", "no face shows"])
        #expect(AskDrawingCheck.unmet("1 yes\n2 yes\n3 yes", plan: plan).isEmpty)
        #expect(AskDrawingCheck.unmet("**1** - yes\n**2** - no", plan: plan) == ["its tail curls round"])
    }

    @Test("An answer the check cannot read counts as no miss, so noise never throws a drawing away")
    func unreadableAnswer() {
        #expect(AskDrawingCheck.unmet("It looks like a cat.", plan: ["the cat sleeps"]).isEmpty)
        #expect(AskDrawingCheck.unmet("9 no", plan: ["the cat sleeps"]).isEmpty)
    }

    @Test("The plan's drawings: each with its subject and its statements")
    func drawingsCarryTheirPlan() {
        let plan = AskPlan(steps: [AskStep(tool: "add_drawing", arguments: ["subject": "a fox asleep under a tree",
                                                                             "plan": ["the fox is curled up", "its eyes are shut"]])],
                           summary: "")
        let drawings = AskDrawingCheck.drawings(in: plan)
        #expect(drawings.first?.plan == ["the fox is curled up", "its eyes are shut"])
    }

    @Test("Drawing again after a plan miss is told what the drawing did not show, and keeps the plan")
    func revisionForAPlanMiss() {
        let note = AskDrawingCheck.revisionNote(subject: "a black cat seen from behind", seen: "cat", paints: true,
                                                unmet: ["no face shows", "its back is toward us"])
        #expect(note.contains("no face shows"))
        #expect(note.contains("its back is toward us"))
        #expect(note.contains("plan"))
    }

    @Test("A drawing's layer is named with a short label, never a paragraph")
    func layerNameIsShort() {
        let long = AgentDrawingCall(subject: "a cat sitting upright on its hind legs, holding a guitar with its front paws on the neck")
        #expect(long.layerName == "A cat sitting upright on its hind legs")
        let run = AgentDrawingCall(subject: "a robot carefully pouring water from a green watering can onto a small potted plant")
        #expect(run.layerName.count <= AgentDrawingCall.longestName)
        #expect(run.layerName == "A robot carefully pouring water from a")
        #expect(AgentDrawingCall(subject: "cat playing a guitar").layerName == "Cat playing a guitar")
        #expect(AgentDrawingCall(subject: "x", name: "My own long name that the agent chose for this group").layerName
                == "My own long name that the agent chose for this group")
    }

    // MARK: The row names the scene

    @Test("The row names the whole scene, the person's own words, not just its first noun")
    func rowNamesTheScene() {
        let step = AskStep(tool: "add_drawing", arguments: ["subject": "a cartoon cat playing a piano", "plan": .array(Self.piano)])
        let said = AskChangeWords.sentence([step], asked: "draw a piano with a cartoon cat playing it")
        #expect(said.hasPrefix("Drew"))
        #expect(said.contains("cat") && said.contains("piano"), "\(said)")
        let guitar = AskStep(tool: "add_drawing", arguments: ["subject": "cat playing a guitar"])
        #expect(AskChangeWords.sentence([guitar], asked: "draw a cat playing a guitar") == "Drew a cat playing a guitar")
    }
}
