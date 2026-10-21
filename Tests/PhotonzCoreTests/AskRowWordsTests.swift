import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Each Ask row names what the request did in the person's own terms: "Drew
/// a cat", "Made the cat's ears bigger", never "Drew a drawing" or "Changed a
/// layer" (the user, 2026-10-20). The words come from the request itself, the
/// drawing's own subject and the names of the layers it changed.
@Suite("Ask: each row says what it made")
struct AskRowWordsTests {

    static func drawing(_ subject: String, icon: Bool = false, style: String? = nil) -> AskStep {
        var args: [String: AgentJSON] = ["subject": .string(subject)]
        if icon { args["icon"] = true }
        if let style { args["style"] = .string(style) }
        return AskStep(tool: "add_drawing", arguments: .object(args))
    }

    static func set(_ layer: Layer, _ args: [String: AgentJSON]) -> AskStep {
        var all = args
        all["layer"] = .string(layer.id.uuidString)
        return AskStep(tool: "set_layer", arguments: .object(all))
    }

    static let ear = Layer(name: "Cat Ear", content: .annotation(AnnotationContent(shape: .ellipse, colorHex: "#333333")),
                           frame: CGRect(x: 10, y: 10, width: 40, height: 40))
    static let tail = Layer(name: "Tail", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#333333")),
                            frame: CGRect(x: 60, y: 10, width: 80, height: 10))
    static let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [ear, tail])

    // MARK: A drawing says what it is of

    @Test("A drawing names its subject, never the word drawing")
    func drawingNamesItsSubject() {
        #expect(AskChangeWords.sentence([Self.drawing("cat")], asked: "draw a picture of a cat") == "Drew a cat")
        #expect(AskChangeWords.sentence([Self.drawing("dog")], asked: "draw a picture of a dog.") == "Drew a dog")
        #expect(AskChangeWords.sentence([Self.drawing("sun over mountains", style: "flat")],
                                        asked: "draw an svg illustration of a sun over mountains")
                == "Drew a sun over mountains")
        #expect(AskChangeWords.sentence([Self.drawing("smiley face", icon: true)], asked: "create a smiley face icon")
                == "Drew a smiley face icon")
        #expect(AskChangeWords.sentence([Self.drawing("sun over mountains")], asked: "draw the sun over mountains")
                == "Drew the sun over mountains")
    }

    @Test("The person's own words for the subject win over the model's shorter one")
    func personsWordsWin() {
        #expect(AskChangeWords.sentence([Self.drawing("cat")], asked: "draw a picture of a fluffy orange cat")
                == "Drew a fluffy orange cat")
        #expect(AskChangeWords.sentence([Self.drawing("sun over mountains", style: "line art")],
                                        asked: "draw the sun over mountains as line art")
                == "Drew the sun over mountains as line art")
        // Too long to keep whole: cut at a natural break that still names it.
        #expect(AskChangeWords.sentence([Self.drawing("sun over mountains", style: "silhouette badge")],
                                        asked: "draw the sun over mountains as a black silhouette badge with pines")
                == "Drew the sun over mountains")
        #expect(AskChangeWords.sentence([Self.drawing("mountain")],
                                        asked: "draw the sun over mountains as a layered sunset")
                == "Drew the sun over mountains")
        // Nowhere to cut that still names it: the subject, with the article the person used.
        #expect(AskChangeWords.sentence([Self.drawing("lighthouse")],
                                        asked: "draw the tall striped lighthouse standing proudly above the sea")
                == "Drew the lighthouse")
    }

    @Test("With no request to lean on, the subject still gets a fitting article")
    func subjectAlone() {
        #expect(AskChangeWords.sentence([Self.drawing("cat")]) == "Drew a cat")
        #expect(AskChangeWords.sentence([Self.drawing("owl")]) == "Drew an owl")
        #expect(AskChangeWords.sentence([Self.drawing("mountains")]) == "Drew mountains")
        #expect(AskChangeWords.sentence([Self.drawing("a lighthouse on a cliff")]) == "Drew a lighthouse on a cliff")
        #expect(AskChangeWords.sentence([Self.drawing("rocket", icon: true)]) == "Drew a rocket icon")
    }

    @Test("Two drawings name both")
    func twoDrawings() {
        #expect(AskChangeWords.sentence([Self.drawing("cat"), Self.drawing("dog")], asked: "draw a cat and a dog")
                == "Drew a cat and a dog")
        let many = AskChangeWords.sentence(["cat", "dog", "bird", "fish", "horse", "elephant"].map { Self.drawing($0) })
        #expect(many.count <= AskChangeWords.budget)
        #expect(many.hasPrefix("Drew a cat"))
        #expect(!many.contains("drawing"))
    }

    // MARK: A change names the thing and the change

    @Test("A change to what is there is the request, said as done")
    func changeIsTheRequestDone() {
        let bigger = [Self.set(Self.ear, ["width": 60, "height": 60])]
        #expect(AskChangeWords.sentence(bigger, asked: "make the cat's ears bigger", before: Self.document)
                == "Made the cat's ears bigger")
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["fill": "#FF8800"])], asked: "recolour the sky orange",
                                        before: Self.document) == "Recoloured the sky orange")
        #expect(AskChangeWords.sentence(bigger, asked: "Can you make the title bigger?", before: Self.document)
                == "Made the title bigger")
        #expect(AskChangeWords.sentence(bigger, asked: "please make my logo red, thanks", before: Self.document)
                == "Made your logo red")
        #expect(AskChangeWords.sentence(bigger, asked: "flip it", before: Self.document) == "Flipped it")
    }

    @Test("When the request will not read as done, the row names the layer and what happened to it")
    func layerNamed() {
        let mumble = "hmm the ear is off somehow and it bugs me a lot right now"
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["fill": "#FF8800"])], asked: mumble, before: Self.document)
                == "Recoloured Cat Ear")
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["width": 60])], asked: mumble, before: Self.document)
                == "Resized Cat Ear")
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["x": 5, "y": 5])], asked: mumble, before: Self.document)
                == "Moved Cat Ear")
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["fill": "#FF8800", "width": 60])], asked: mumble,
                                        before: Self.document) == "Changed Cat Ear")
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["width": 60]), Self.set(Self.tail, ["width": 90])],
                                        asked: mumble, before: Self.document) == "Resized Cat Ear and Tail")
        #expect(AskChangeWords.sentence([Self.set(Self.ear, ["visible": false])], before: Self.document) == "Hid Cat Ear")
        // A layer the request itself made is named from the document after it.
        let made = Layer(name: "Whiskers", content: .annotation(AnnotationContent(shape: .line, colorHex: "#000000")),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        var after = Self.document
        after.addLayer(made)
        #expect(AskChangeWords.sentence([Self.set(made, ["flip": "horizontal"])], before: Self.document, after: after)
                == "Flipped Whiskers")
    }

    @Test("A request that names a thing to make keeps its noun and drops what does not fit")
    func longRequestsShorten() {
        let parts = ["place_component", "place_component", "add_text", "apply_style", "set_layout"].map {
            AskStep(tool: $0, arguments: [:])
        }
        #expect(AskChangeWords.sentence(parts, asked: "Make a pricing section on brand") == "Made a pricing section on brand")
        #expect(AskChangeWords.sentence(parts, asked: "Make a component sheet for a website's design system: buttons, text fields, cards and navigation, each labelled, with a title.")
                == "Made a component sheet")
        #expect(AskChangeWords.sentence(parts, asked: "create a table of apple like quality base components that show different states and text")
                == "Created a table")
    }

    @Test("Turning a request into done words")
    func pastTense() {
        #expect(AskChangeWords.done("draw a cat") == "Drew a cat")
        #expect(AskChangeWords.done("Move the logo left") == "Moved the logo left")
        #expect(AskChangeWords.done("shrink the title") == "Shrank the title")
        #expect(AskChangeWords.done("trim the clip to 5 seconds") == "Trimmed the clip to 5 seconds")
        #expect(AskChangeWords.done("color the background blue") == "Colored the background blue")
        #expect(AskChangeWords.done("what is this?") == nil)
        #expect(AskChangeWords.done("") == nil)
    }

    // MARK: The form every row keeps

    static let pastVerbs: Set<String> = [
        "Drew", "Made", "Added", "Created", "Placed", "Changed", "Recoloured", "Resized", "Moved", "Found",
        "Restyled", "Laid", "Ran", "Trimmed", "Saved", "Hid", "Showed", "Flipped", "Renamed",
        // A video request's own verbs: "Put my latest recording after this
        // one", "Zoomed in on the clicks", "Cut this clip where...".
        "Put", "Zoomed", "Cut",
    ]

    static func checkForm(_ row: String, _ context: String) {
        #expect(row.count <= AskChangeWords.budget, "\(context): \(row)")
        #expect(!row.contains("\u{2014}") && !row.contains("_"), "\(context): \(row)")
        let first = String(row.split(separator: " ").first ?? "")
        #expect(pastVerbs.contains(first), "\(context): \(row) starts with \(first)")
        #expect(!row.hasSuffix(" drawing") && !row.hasSuffix(" drawings"), "\(context): \(row)")
        // A number is always a number of something.
        let words = row.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() where Int(word) != nil {
            #expect(index + 1 < words.count, "\(context): \(row) ends on a count")
        }
    }

    struct Case: Decodable {
        let request: String
        let group: String
        let names: [String]?
    }

    @Test("Every eval request leaves a row in the right form, and a drawing's row names what was drawn")
    func everyEvalCase() throws {
        let cases = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/ask-eval/cases")
        let files = try FileManager.default.contentsOfDirectory(at: cases, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count >= 20)
        for file in files {
            let found = try JSONDecoder().decode(Case.self, from: Data(contentsOf: file))
            let steps: [AskStep]
            switch found.group {
            case "drawing":
                steps = [Self.drawing(found.names?.first ?? "thing", icon: found.request.contains("icon"))]
            case "redline":
                steps = Array(repeating: AskStep(tool: "add_measurement", arguments: [:]), count: 8)
            case "video":
                steps = ["cut", "set_transition", "add_title"].map { AskStep(tool: $0, arguments: [:]) }
            default:
                steps = ["place_component", "place_component", "add_text", "add_text", "add_text", "apply_style", "set_layout"]
                    .map { AskStep(tool: $0, arguments: [:]) }
            }
            let row = AskChangeWords.sentence(steps, asked: found.request)
            Self.checkForm(row, file.lastPathComponent)
            if found.group == "drawing", let names = found.names {
                #expect(names.contains { row.lowercased().contains($0) }, "\(file.lastPathComponent): \(row)")
            }
        }
    }
}
