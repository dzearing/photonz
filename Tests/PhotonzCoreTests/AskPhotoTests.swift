import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask picks how to make a picture from what the person says
/// (`docs/design/ask.md`, "A photo, a drawing or a painting"): photo words
/// make a photographic picture layer painted by the picture model and kept as
/// pixels, drawing, vector and icon words make editable vector layers, and
/// paint words wait for the brushes, making the nearest kind meanwhile.
@Suite("Ask makes a photo, a vector drawing or a painting, from the words")
struct AskPhotoTests {

    static func conversation(_ request: String, paints: Bool = true) -> AskConversation {
        AskConversation(request: request, documentRead: #"{"canvas":{"width":1440,"height":900}}"#, paints: paints)
    }

    static func reply(_ name: String, _ args: AgentJSON) -> AgentJSON {
        ["message": ["role": "assistant", "content": "", "tool_calls": .array([["function": ["name": .string(name), "arguments": args]]])]]
    }

    // MARK: Reading the words

    @Test("Photo words ask for a photo, in any of the ways people say it")
    func photoWords() {
        for asked in ["make a photorealistic image of a dog on a beach", "a photo of a kitten walking in the snow",
                      "generate a photo of a kitten walking in the snow", "a realistic picture of a red barn",
                      "photograph of a lighthouse at dusk", "Make it as a photo", "a lifelike image of an owl",
                      "draw a photorealistic apple"] {
            #expect(AgentPictureKind.asked(in: asked) == .photo, "\(asked)")
        }
    }

    @Test("Drawing, vector and icon words ask for vector layers")
    func vectorWords() {
        for asked in ["make vector art of a fox", "draw a cat", "create an icon of a camera", "a flat illustration of a tree",
                      "a smiley face icon", "line art of a bicycle", "a logo for a coffee shop", "as vector art",
                      "paint an icon of a rocket", "a realistic drawing of a horse"] {
            #expect(AgentPictureKind.asked(in: asked) == .vector, "\(asked)")
        }
    }

    @Test("Paint words ask for a painting")
    func paintWords() {
        for asked in ["paint a picture of a sunset", "a painting of a harbour", "paint a vase of flowers with brushes",
                      "Paint me a forest", "a realistic painting of a horse"] {
            #expect(AgentPictureKind.asked(in: asked) == .paint, "\(asked)")
        }
    }

    @Test("A request that names no kind leaves the choice to the planning model")
    func neither() {
        for asked in ["a dog on a beach", "make a cat", "a picture of a mountain", "make the cat bigger", "a photonic crystal"] {
            #expect(AgentPictureKind.asked(in: asked) == nil, "\(asked)")
        }
    }

    // MARK: Again, the other way

    @Test("\"As a photo\" after a drawing makes the same thing again as a photo")
    func remake() {
        #expect(AgentPictureKind.remade("as a photo", after: "draw a dog on a beach")
                == "draw a dog on a beach, as a photo")
        #expect(AgentPictureKind.remade("now make it as vector art", after: "a photo of a lighthouse")
                == "a photo of a lighthouse, as vector art")
        #expect(AgentPictureKind.remade("Try it as a painting instead", after: "a fox") == "a fox, as a painting")
        // A request with a subject of its own is its own request.
        #expect(AgentPictureKind.remade("a photo of a cat", after: "draw a dog") == nil)
        #expect(AgentPictureKind.remade("as a photo", after: nil) == nil)
        #expect(AgentPictureKind.remade("make it bigger", after: "draw a dog") == nil)
    }

    @Test("Made again the other way, the new kind wins over the old request's words")
    func remakeWins() throws {
        let words = try #require(AgentPictureKind.remade("as a photo", after: "draw a dog on a beach"))
        #expect(AgentPictureKind.asked(in: words) == .photo)
        let back = try #require(AgentPictureKind.remade("as vector art", after: "a photo of a dog"))
        #expect(AgentPictureKind.asked(in: back) == .vector)
    }

    // MARK: The tool

    @Test("add_photo is offered to agents and to Ask, beside add_drawing")
    func offered() {
        #expect(AgentTools.all.contains { $0.name == "add_photo" })
        #expect(AskTools.doing.contains("add_photo"))
        let tool = AgentTools.all.first { $0.name == "add_photo" }
        #expect(tool?.description.contains("photo") == true)
    }

    @Test("add_photo reads its subject, the person's words, a frame and a name")
    func toolReads() throws {
        let made = AgentTools.request(tool: "add_photo", arguments: [
            "document": "d1", "subject": "a dog on a beach", "asked": "a photo of a dog on a beach",
            "frame": ["x": 10, "y": 20, "width": 400, "height": 300], "name": "Beach dog",
        ])
        guard case .success(.addPhoto(let document, let call)) = made else {
            Issue.record("not an add_photo: \(made)")
            return
        }
        #expect(document == "d1")
        #expect(call.subject == "a dog on a beach")
        #expect(call.asked == "a photo of a dog on a beach")
        #expect(call.frame == CGRect(x: 10, y: 20, width: 400, height: 300))
        #expect(call.layerName == "Beach dog")
        #expect(call.look == .photo)
        guard case .failure = AgentTools.request(tool: "add_photo", arguments: ["subject": " "]) else {
            Issue.record("an empty subject was accepted")
            return
        }
    }

    @Test("A photo layer is named for its subject, a label not a paragraph")
    func layerName() {
        #expect(AgentPhotoCall(subject: "a dog on a beach").layerName == "A dog on a beach")
        #expect(AgentPhotoCall(subject: "a kitten walking in the snow, soft morning light, shallow focus").layerName
                == "A kitten walking in the snow")
    }

    // MARK: What the picture model is asked

    @Test("A photo is asked for as a real photograph, with none of the flat look a traced drawing needs")
    func photoPrompt() {
        let prompt = PictureModelPhotoRequest(AgentPhotoCall(subject: "a dog on a beach"),
                                              box: CGSize(width: 1440, height: 900)).prompt
        #expect(prompt.hasPrefix("a dog on a beach"))
        #expect(prompt.contains("photograph"))
        for flat in ["flat", "vector", "illustration", "few colours", "no shading", "no gradients", "plain white"] {
            #expect(!prompt.lowercased().contains(flat), "\(flat)")
        }
    }

    @Test("The person's words reach the photo when they say more than the subject")
    func promptCarriesTheRequest() {
        let prompt = PictureModelPhotoRequest(AgentPhotoCall(subject: "kitten", asked: "a photo of a kitten walking in the snow"),
                                              box: CGSize(width: 1024, height: 1024)).prompt
        #expect(prompt.contains("kitten, from the request: a photo of a kitten walking in the snow"))
    }

    @Test("Made again as a photo, the earlier request's drawing words stay out of the photo's prompt")
    func remadePromptDropsTheOtherKind() {
        let prompt = PictureModelPhotoRequest(AgentPhotoCall(subject: "a fox", asked: "make vector art of a fox, as a photo"),
                                              box: CGSize(width: 1440, height: 900)).prompt.lowercased()
        for drawn in ["vector", " art ", "draw", "illustration"] {
            #expect(!prompt.contains(drawn), "\(drawn) in \(prompt)")
        }
        #expect(prompt.contains("fox"))
        let painted = PictureModelPhotoRequest(AgentPhotoCall(subject: "a harbour", asked: "draw a cartoon harbour, as a painting",
                                                              look: .painting),
                                               box: CGSize(width: 1200, height: 900)).prompt.lowercased()
        #expect(!painted.contains("cartoon") && !painted.contains("draw"), "\(painted)")
    }

    @Test("A painting asked for before the brushes are ready is painted as one picture, in a painted look")
    func paintingPrompt() {
        let prompt = PictureModelPhotoRequest(AgentPhotoCall(subject: "a harbour", look: .painting),
                                              box: CGSize(width: 1200, height: 900)).prompt
        #expect(prompt.contains("painting"))
        #expect(!prompt.contains("photograph"))
    }

    @Test("Painted at the box's aspect, about a million pixels, every side a multiple of 16")
    func size() {
        func painted(_ w: CGFloat, _ h: CGFloat) -> (Int, Int) {
            let asked = PictureModelPhotoRequest(AgentPhotoCall(subject: "x"), box: CGSize(width: w, height: h))
            return (asked.width, asked.height)
        }
        for (w, h) in [(1440, 900), (1024, 1024), (3024, 1964), (800, 600), (1080, 1920)] as [(CGFloat, CGFloat)] {
            let (pw, ph) = painted(w, h)
            #expect(pw % 16 == 0 && ph % 16 == 0, "\(w)x\(h)")
            let pixels = Double(pw * ph)
            #expect(pixels > 800_000 && pixels <= 1_100_000, "\(w)x\(h) -> \(pw)x\(ph)")
            #expect(abs(Double(pw) / Double(ph) - Double(w / h)) < 0.04, "\(w)x\(h) -> \(pw)x\(ph)")
        }
        // A strip is kept to the shapes the model paints well.
        let (sw, sh) = painted(4000, 200)
        #expect(Double(sw) / Double(sh) <= 3.01)
        // A small box is never painted bigger than it needs at 2x.
        let (tw, th) = painted(200, 150)
        #expect(tw <= 400 + 16 && th <= 300 + 16 && th >= 256)
    }

    @Test("A photo fills the box asked for, kept on the canvas, or the whole canvas")
    func placement() {
        let canvas = CGSize(width: 1440, height: 900)
        #expect(AgentPhotoPlacement.box(nil, on: canvas) == CGRect(origin: .zero, size: canvas))
        #expect(AgentPhotoPlacement.box(CGRect(x: 100, y: 100, width: 400, height: 300), on: canvas)
                == CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(AgentPhotoPlacement.box(CGRect(x: 1300, y: 800, width: 400, height: 300), on: canvas)
                == CGRect(x: 1300, y: 800, width: 140, height: 100))
        #expect(AgentPhotoPlacement.box(CGRect(x: 5000, y: 5000, width: 40, height: 30), on: canvas)
                == CGRect(origin: .zero, size: canvas))
    }

    // MARK: Ask routes by the words

    @Test("Asked for a photo, a drawing the model planned is made as a photo")
    func photoWordsWin() {
        var talk = Self.conversation("make a photorealistic image of a dog on a beach")
        _ = talk.take(Self.reply("add_drawing", ["subject": "dog on a beach", "scene": true]))
        #expect(talk.steps.count == 1)
        #expect(talk.steps.first?.tool == "add_photo")
        #expect(talk.steps.first?.arguments["subject"]?.stringValue == "dog on a beach")
        #expect(talk.steps.first?.arguments["asked"]?.stringValue == "make a photorealistic image of a dog on a beach")
        #expect(talk.note == nil)
    }

    @Test("Asked for vector art or an icon, a photo the model planned is drawn as layers")
    func vectorWordsWin() {
        var talk = Self.conversation("make vector art of a fox")
        _ = talk.take(Self.reply("add_photo", ["subject": "fox"]))
        #expect(talk.steps.first?.tool == "add_drawing")
        #expect(talk.steps.first?.arguments["subject"]?.stringValue == "fox")
        var icon = Self.conversation("a photo icon of a camera")
        _ = icon.take(Self.reply("add_drawing", ["subject": "camera", "icon": true]))
        #expect(icon.steps.first?.tool == "add_drawing")
    }

    @Test("Saying neither, what the model picked is kept")
    func neitherKeepsTheModelsChoice() {
        var photo = Self.conversation("a dog on a beach")
        _ = photo.take(Self.reply("add_photo", ["subject": "dog on a beach"]))
        #expect(photo.steps.first?.tool == "add_photo")
        var drawing = Self.conversation("a dog on a beach")
        _ = drawing.take(Self.reply("add_drawing", ["subject": "dog on a beach"]))
        #expect(drawing.steps.first?.tool == "add_drawing")
    }

    @Test("Asked to paint before the brushes are ready, Ask paints one picture and says so in a line")
    func paintFallsBack() {
        var talk = Self.conversation("paint a picture of a sunset over the sea")
        _ = talk.take(Self.reply("add_drawing", ["subject": "sunset over the sea", "scene": true]))
        #expect(talk.steps.first?.tool == "add_photo")
        #expect(talk.steps.first?.arguments["look"]?.stringValue == "painting")
        #expect(talk.note == AskConversation.brushesNotReady)
        #expect(AskConversation.brushesNotReady.contains("brushes"))
        #expect(!AskConversation.brushesNotReady.contains("—"))
        // A panel line: 40 characters at most (UX-PATTERNS §4).
        #expect(AskConversation.brushesNotReady.count <= 40 && AskConversation.brushesNotReadyDrawn.count <= 40)
    }

    @Test("With no picture model on this Mac a photo is refused with what to do, and a drawing still needs its svg")
    func noPictureModel() {
        var talk = Self.conversation("a photo of a dog", paints: false)
        _ = talk.take(Self.reply("add_photo", ["subject": "dog"]))
        #expect(talk.steps.isEmpty)
        #expect(talk.messages.last?["content"]?.stringValue?.contains("Settings") == true)
    }

    @Test("The instructions say which tool each kind of request takes")
    func instructions() {
        let painting = AskConversation.instructions(documentRead: "{}", paints: true)
        #expect(painting.contains("add_photo"))
        #expect(painting.contains("photo"))
    }

    // MARK: What the row says

    @Test("The row says it made a photo, so the person knows which kind they got")
    func rowSaysPhoto() {
        let step = AskStep(tool: "add_photo", arguments: ["subject": "a dog on a beach"])
        #expect(AskChangeWords.sentence([step], asked: "a dog on a beach") == "Made a photo of a dog on a beach")
        let painted = AskStep(tool: "add_photo", arguments: ["subject": "a harbour", "look": "painting"])
        #expect(AskChangeWords.sentence([painted], asked: "paint a harbour") == "Painted a harbour")
        let drawn = AskStep(tool: "add_drawing", arguments: ["subject": "a dog"])
        #expect(AskChangeWords.sentence([drawn], asked: "a dog").hasPrefix("Drew"))
    }

    @Test("A photo counts as made for the request, never looked up")
    func photoIsDrawn() {
        #expect(AskDrawingSource.of(tool: "add_photo", answer: #"{"from":"painted: Z-Image Turbo"}"#) == .drawn)
    }
}
