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

    // MARK: A plan the model left out is asked for

    @Test("A drawing sent with no plan is listed for one to be asked for; one with a plan is not")
    func unplannedDrawingsAreFound() {
        let plan = AskPlan(steps: [
            AskStep(tool: "add_drawing", arguments: ["subject": "robot watering a plant"]),
            AskStep(tool: "add_text", arguments: ["text": "Hello"]),
            AskStep(tool: "add_drawing", arguments: ["subject": "a cat playing a piano", "plan": .array(Self.piano)]),
        ], summary: "")
        let missing = AskDrawingCheck.unplanned(in: plan)
        #expect(missing.map(\.step) == [1])
        #expect(missing.map(\.subject) == ["robot watering a plant"])
    }

    @Test("The question for a plan carries the subject and the rules for statements, and does not think")
    func planQuestion() {
        let body = AskDrawingCheck.planningBody(model: "m", subject: "robot watering a plant")
        let asked = body["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        #expect(asked.contains("robot watering a plant"))
        #expect(asked.contains("yes or no"))
        #expect(asked.contains("none"))
        #expect(body["think"] == false)
        #expect(body["stream"] == false)
    }

    @Test("The answer's statements are read one per line, numbering and bullets taken off, at most four")
    func planAnswerRead() {
        let answer = """
        1. The robot holds a watering can by its handle.
        - Water pours from the can's spout onto the plant
        * the plant sits in a pot

        4) the robot faces the plant
        5. one too many
        """
        #expect(AskDrawingCheck.statements(fromAnswer: answer) == [
            "The robot holds a watering can by its handle", "Water pours from the can's spout onto the plant",
            "the plant sits in a pot", "the robot faces the plant",
        ])
    }

    @Test("A plain thing's answer is no plan at all")
    func plainThingHasNoPlan() {
        #expect(AskDrawingCheck.statements(fromAnswer: "none").isEmpty)
        #expect(AskDrawingCheck.statements(fromAnswer: "None.").isEmpty)
        #expect(AskDrawingCheck.statements(fromAnswer: "<think>a dog is plain</think>\nnone").isEmpty)
        #expect(AskDrawingCheck.statements(fromAnswer: "").isEmpty)
    }

    @Test("The plan asked for is written into its step, the rest of the plan untouched")
    func planWrittenIntoStep() {
        let plan = AskPlan(steps: [
            AskStep(tool: "add_drawing", arguments: ["subject": "robot watering a plant", "scene": true]),
            AskStep(tool: "add_text", arguments: ["text": "Hello"]),
        ], summary: "Drew it", names: ["a": "b"])
        let filled = plan.settingDrawingPlan(step: 1, to: ["the robot holds a watering can"])
        #expect(filled.steps[0].arguments["plan"] == .array(["the robot holds a watering can"]))
        #expect(filled.steps[0].arguments["subject"] == "robot watering a plant")
        #expect(filled.steps[0].arguments["scene"] == true)
        #expect(filled.steps[1] == plan.steps[1])
        #expect(filled.summary == "Drew it" && filled.names == ["a": "b"])
        #expect(AskDrawingCheck.drawings(in: filled).first?.plan == ["the robot holds a watering can"])
        #expect(plan.settingDrawingPlan(step: 1, to: []) == plan)
    }

    // MARK: A drawing drawn again keeps its plan, and the closest try stays

    static func drawing(_ subject: String, _ plan: [AgentJSON]? = nil) -> AskStep {
        AskStep(tool: "add_drawing", arguments: plan.map { ["subject": .string(subject), "plan": .array($0)] }
                ?? ["subject": .string(subject)])
    }

    @Test("A drawing drawn again is checked against the plan the first one was, not a new plan of its reworded subject")
    func revisionCarriesThePlan() {
        let first = AskPlan(steps: [Self.drawing("a cat playing a piano", Self.piano)], summary: "")
        let carried = AskDrawingCheck.drawings(in: first).map(\.plan)
        // The model rewords the subject and leaves the plan out.
        let again = AskPlan(steps: [Self.drawing("a cartoon cat seated on a bench, both front paws pressing the keys")],
                            summary: "Drew it")
        let carrying = AskDrawingCheck.carryingPlans(carried, into: again)
        #expect(carrying?.steps[0].arguments["plan"] == .array(Self.piano))
        #expect(carrying?.steps[0].arguments["subject"] == "a cartoon cat seated on a bench, both front paws pressing the keys")
        #expect(carrying.map { AskDrawingCheck.unplanned(in: $0) }?.isEmpty == true)
        // A plan the model reworded is replaced by the one the request was checked against.
        let reworded = AskPlan(steps: [Self.drawing("a cat at a piano", ["a cat", "a piano"])], summary: "")
        #expect(AskDrawingCheck.carryingPlans(carried, into: reworded)?.steps[0].arguments["plan"] == .array(Self.piano))
    }

    @Test("A plain thing drawn again stays a plain thing; a different number of drawings asks afresh")
    func revisionCarriesNothingForAPlainThing() {
        let carried: [[String]] = [[]]
        let again = AskPlan(steps: [Self.drawing("a dog, side view, four legs, wagging tail")], summary: "")
        let carrying = AskDrawingCheck.carryingPlans(carried, into: again)
        #expect(carrying == again)
        let two = AskPlan(steps: [Self.drawing("a dog"), Self.drawing("a ball")], summary: "")
        #expect(AskDrawingCheck.carryingPlans(carried, into: two) == nil)
        let text = AskPlan(steps: [AskStep(tool: "add_text", arguments: ["text": "Hi"]), Self.drawing("a dog")], summary: "")
        #expect(AskDrawingCheck.carryingPlans([["it sits"]], into: text)?.steps[1].arguments["plan"] == .array(["it sits"]))
    }

    @Test("The closest try is kept: one that reads beats one that does not, fewer statements missed beats more, a tie goes to the later")
    func closestTryKept() {
        typealias Try = AskDrawingCheck.Attempt
        #expect(AskDrawingCheck.isCloser(Try(reads: true, missed: 2), than: nil))
        #expect(!AskDrawingCheck.isCloser(Try(reads: false, missed: 0), than: nil))
        #expect(AskDrawingCheck.isCloser(Try(reads: true, missed: 1), than: Try(reads: true, missed: 2)))
        #expect(!AskDrawingCheck.isCloser(Try(reads: true, missed: 2), than: Try(reads: true, missed: 1)))
        #expect(AskDrawingCheck.isCloser(Try(reads: true, missed: 1), than: Try(reads: true, missed: 1)))
        #expect(!AskDrawingCheck.isCloser(Try(reads: false, missed: 0), than: Try(reads: true, missed: 3)))
        #expect(AskDrawingCheck.isCloser(Try(reads: true, missed: 3), than: Try(reads: false, missed: 0)))
    }

    // MARK: A plan keeps only what the words ask for

    @Test("The question whether the words ask for each statement carries the request and the numbered statements, and does not think")
    func groundingQuestion() {
        let body = AskDrawingCheck.groundingBody(model: "m", request: "draw a robot watering a plant",
                                                 plan: ["the robot holds a watering can", "the plant is in front of the robot"])
        let asked = body["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        #expect(asked.contains("draw a robot watering a plant"))
        #expect(asked.contains("1. the robot holds a watering can"))
        #expect(asked.contains("2. the plant is in front of the robot"))
        #expect(asked.contains("1 yes"))
        #expect(body["think"] == false)
        #expect(body["stream"] == false)
    }

    @Test("Statements the words do not ask for are dropped; a line it cannot read keeps its statement")
    func groundingKeepsWhatWasAsked() {
        let plan = ["its eyebrows angle down", "its body is round and red", "it has a black beak", "it frowns"]
        #expect(AskDrawingCheck.grounded(plan, answer: "1 yes\n2 no\n3. No\n4 yes") == ["its eyebrows angle down", "it frowns"])
        #expect(AskDrawingCheck.grounded(plan, answer: "1 yes\n2 no") == ["its eyebrows angle down", "it has a black beak", "it frowns"])
        #expect(AskDrawingCheck.grounded(plan, answer: "I am not sure") == plan)
        #expect(AskDrawingCheck.grounded(plan, answer: "1 no\n2 no\n3 no\n4 no").isEmpty)
    }

    @Test("A plan cut down is written back into its step, and a plan cut to nothing is taken off")
    func groundedPlanWrittenBack() {
        let plan = AskPlan(steps: [Self.drawing("angry bird", ["its eyebrows angle down", "it has a black beak"])], summary: "")
        let cut = plan.replacingDrawingPlan(step: 1, with: ["its eyebrows angle down"])
        #expect(AskDrawingCheck.drawings(in: cut).first?.plan == ["its eyebrows angle down"])
        let none = plan.replacingDrawingPlan(step: 1, with: [])
        #expect(none.steps[0].arguments["plan"] == nil)
        #expect(none.steps[0].arguments["subject"] == "angry bird")
        #expect(AskDrawingCheck.drawings(in: none).first?.plan == [])
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
