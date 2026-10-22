import Foundation
@testable import PhotonzCore
import Testing

/// Ask drawing with a picture model on this Mac (`docs/design/ask.md`,
/// "Painting a drawing"): with "Ask paints its drawings" on and the picture
/// model answering, every add_drawing is painted from the person's words and
/// traced into layers, so nothing is looked up and no svg is asked for.
@Suite("Ask paints its drawings with a local picture model")
struct AskPaintsTests {

    static let circle = ##"<svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#C1694F"/></svg>"##

    static func conversation(_ request: String, paints: Bool = true) -> AskConversation {
        AskConversation(request: request, documentRead: #"{"canvas":{"width":1440,"height":1024}}"#,
                        paints: paints)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    @Test("Any subject is planned with no svg: a thing, a pose, a scene")
    func anySubjectPlanned() {
        for subject in ["bicycle", "a cat curled up asleep", "a lighthouse on a cliff at dusk"] {
            var talk = Self.conversation("draw \(subject)")
            _ = talk.take(Self.reply("add_drawing", ["subject": .string(subject)]))
            #expect(talk.steps.count == 1, "\(subject)")
        }
    }

    @Test("The planned drawing carries the person's own words, so a shortened subject keeps its pose")
    func carriesTheRequest() {
        var talk = Self.conversation("draw a cat curled up sleeping")
        _ = talk.take(Self.reply("add_drawing", ["subject": "cat"]))
        #expect(talk.steps.first?.arguments["asked"]?.stringValue == "draw a cat curled up sleeping")
    }

    @Test("Without painting, a drawing needs the model's own svg")
    func offIsUnchanged() {
        var talk = Self.conversation("draw a bicycle", paints: false)
        _ = talk.take(Self.reply("add_drawing", ["subject": "bicycle"]))
        #expect(talk.steps.isEmpty)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("svg") == true)
    }

    @Test("The instructions ask for the whole description and no svg when painting")
    func instructionsWhenPainting() {
        let painting = AskConversation.instructions(documentRead: "{}", paints: true)
        #expect(painting.contains("what it is doing"))
        #expect(!painting.contains("your own drawing as one complete SVG"))
        let drawing = AskConversation.instructions(documentRead: "{}", paints: false)
        #expect(drawing.contains("your own drawing as one complete SVG"))
    }

    @Test("add_drawing reads the person's words into the call")
    func toolReadsAsked() throws {
        let made = AgentTools.request(tool: "add_drawing", arguments: [
            "document": "d1", "subject": "cat", "asked": "draw a cat at a piano",
        ])
        guard case .success(.addDrawing(_, let call)) = made else {
            Issue.record("not an add_drawing: \(made)")
            return
        }
        #expect(call.asked == "draw a cat at a piano")
    }

    @Test("What the picture model is asked: the subject, the person's words when they say more, and the look")
    func paintingRequest() {
        let call = AgentDrawingCall(subject: "cat", style: "watercolor", asked: "draw a cat curled up sleeping")
        let asked = PictureModelRequest(call)
        #expect(asked.subject == "cat, from the request: draw a cat curled up sleeping")
        #expect(asked.style == "watercolor")
        let plain = PictureModelRequest(AgentDrawingCall(subject: "a red bicycle", asked: "a red bicycle"))
        #expect(plain.subject == "a red bicycle")
    }

    @Test("A scene is painted edge to edge: when the planning model says so, or the words name a scene or a time of day")
    func scenes() {
        #expect(PictureModelRequest(AgentDrawingCall(subject: "a lighthouse on a cliff", scene: true)).scene)
        #expect(PictureModelRequest(AgentDrawingCall(subject: "a forest", asked: "draw a forest at dusk")).scene)
        #expect(PictureModelRequest(AgentDrawingCall(subject: "a city skyline", scene: true)).scene)
        #expect(PictureModelRequest(AgentDrawingCall(subject: "a mountain landscape")).scene)
        #expect(!PictureModelRequest(AgentDrawingCall(subject: "a cat", asked: "draw a cat curled up asleep")).scene)
    }

    @Test("add_drawing reads scene into the call")
    func toolReadsScene() {
        let made = AgentTools.request(tool: "add_drawing", arguments: ["document": "d1", "subject": "a harbour", "scene": true])
        guard case .success(.addDrawing(_, let call)) = made else {
            Issue.record("not an add_drawing: \(made)")
            return
        }
        #expect(call.scene)
    }

    @Test("A painted drawing counts as drawn for the request, never looked up")
    func paintedIsDrawn() {
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"painted: z-image-turbo"}"#) == .drawn)
    }

    @Test("The switch is on in Next, since painting beat the old way on the held-out set, and absent from Current")
    func switchIsOnInNext() {
        let flag = FeatureCatalog.flags(for: .next).first { $0.name == FeatureCatalog.askPaintsFlag }
        #expect(flag?.isEnabled == true)
        #expect(FeatureCatalog.flags(for: .current).first { $0.name == FeatureCatalog.askPaintsFlag } == nil)
    }
}
