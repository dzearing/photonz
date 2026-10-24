import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// add_component (`docs/design/agent-mcp.md`, "Making a component"): an agent
/// describes the pieces of a component's first look and how each further look
/// (a state: hover, pressed, disabled, on) differs, and Photonz builds one
/// component in the Library holding every look as a named version. Nothing
/// about which components exist or how they look is stored: the call says it.
@Suite("Agent add_component: a component with its states")
struct AgentComponentTests {

    static func request(_ json: String) throws -> Result<AgentRequest, AgentToolError> {
        AgentTools.request(tool: "add_component", arguments: try AgentJSON.parse(Data(json.utf8)))
    }

    static func spec(_ json: String) throws -> AgentNewComponent {
        let request = try request(json).get()
        guard case .addComponent(nil, let spec) = request else {
            throw AgentToolError("not an add_component request: \(request)")
        }
        return spec
    }

    /// Every word is 8 points wide and 20 tall, so boxes are easy to check.
    static func measure(_ content: TextContent, _ width: CGFloat?) -> CGSize {
        CGSize(width: width ?? CGFloat(content.string.count * 8), height: 20)
    }

    static let toggle = ##"""
        {"name": "Toggle", "x": 100, "y": 200, "labels": false, "property": "State",
         "parts": [
           {"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 51, "height": 31, "cornerRadius": 15.5, "fill": "#E9E9EA"},
           {"name": "Knob", "shape": "ellipse", "x": 2, "y": 2, "width": 27, "height": 27, "fill": "#FFFFFF"}
         ],
         "firstLook": "Off", "looks": [{"name": "On", "changes": [{"part": "Track", "fill": "#34C759"}, {"part": "Knob", "x": 22}]},
           {"name": "Disabled", "changes": [{"part": "Track", "opacity": 0.4}]}
         ]}
        """##

    static let button = ##"""
        {"name": "Button", "x": 40, "y": 40, "labels": false, "step": 160,
         "parts": [
           {"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 40, "cornerRadius": 10, "fill": "#007AFF"},
           {"name": "Label", "shape": "text", "x": 0, "y": 0, "width": 0, "height": 0, "text": "Continue", "fontSize": 15, "weight": "semibold", "color": "#FFFFFF", "centerIn": "Background"}
         ],
         "firstLook": "Default", "looks": [{"name": "Pressed", "changes": [{"part": "Background", "fill": "#0062CC"}]},
           {"name": "Busy", "changes": [{"part": "Label", "text": "Saving now"}]}
         ]}
        """##

    static func built(_ json: String) throws -> (PhotonzDocument, AgentMadeComponent) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        let made = try document.agentAddComponent(try spec(json), measure: measure).get()
        return (document, made)
    }

    static func piece(_ name: String, of look: String, in document: PhotonzDocument,
                      _ made: AgentMadeComponent) -> Layer? {
        guard let id = made.looks.first(where: { $0.name == look })?.layer,
              let main = document.layer(id: id) else { return nil }
        return main.group?.children.first { $0.name == name }
    }

    // MARK: The call

    @Test("add_component is offered to agents and to Ask, with an object schema")
    func offered() {
        #expect(AgentTools.tool(named: "add_component")?.inputSchema["type"]?.stringValue == "object")
        #expect(AskTools.doing.contains("add_component"))
    }

    @Test("A call carries its name, place, question, parts and looks")
    func parsed() throws {
        let spec = try Self.spec(Self.toggle)
        #expect(spec.name == "Toggle")
        #expect(spec.origin == CGPoint(x: 100, y: 200))
        #expect(spec.property == "State")
        #expect(spec.parts.map(\.name) == ["Track", "Knob"])
        #expect(spec.parts[0].kind == .shape(.rectangle))
        #expect(spec.parts[0].frame == CGRect(x: 0, y: 0, width: 51, height: 31))
        #expect(spec.parts[0].look.cornerRadius == 15.5)
        #expect(spec.looks.map(\.name) == ["Off", "On", "Disabled"])
        #expect(spec.looks[1].changes.map(\.part) == ["Track", "Knob"])
        #expect(spec.looks[1].changes[1].change.x == 22)
    }

    @Test("Words carry their size, weight, colour and the part they sit centred in")
    func parsedWords() throws {
        let label = try Self.spec(Self.button).parts[1]
        #expect(label.kind == .text)
        #expect(label.text == "Continue")
        #expect(label.fontSize == 15)
        #expect(label.weight == .semibold)
        #expect(label.colorHex == "#FFFFFF")
        #expect(label.centerIn == "Background")
    }

    @Test("A call that cannot be built is refused with a sentence saying why")
    func refusals() throws {
        let cases: [(String, String)] = [
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [], "firstLook": "D", "looks": [{"name": "E", "changes": [{"part": "A", "visible": true}]}]}"##, "part"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "rectangle", "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "D"}"##, "looks"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "rectangle", "x": 0, "y": 0, "width": 10, "height": 10}, {"name": "A", "shape": "ellipse", "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "D", "looks": [{"name": "E", "changes": [{"part": "A", "visible": true}]}]}"##, "A"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "text", "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "D", "looks": [{"name": "E", "changes": [{"part": "A", "visible": true}]}]}"##, "text"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "rectangle", "x": 0, "y": 0, "width": 0, "height": 10}], "firstLook": "D", "looks": [{"name": "E", "changes": [{"part": "A", "visible": true}]}]}"##, "width"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "rectangle", "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "D", "looks": [{"name": "On", "changes": [{"part": "B", "fill": "#000000"}]}]}"##, "B"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "rectangle", "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "On", "looks": [{"name": "On", "changes": [{"part": "A", "visible": true}]}]}"##, "On"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "text", "text": "Hi", "centerIn": "Nope", "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "D", "looks": [{"name": "E", "changes": [{"part": "A", "visible": true}]}]}"##, "Nope"),
            (##"{"name": "X", "x": 0, "y": 0, "labels": false, "parts": [{"name": "A", "shape": "path", "points": [{"x": 1, "y": 1}], "x": 0, "y": 0, "width": 10, "height": 10}], "firstLook": "D", "looks": [{"name": "E", "changes": [{"part": "A", "visible": true}]}]}"##, "points"),
        ]
        for (json, word) in cases {
            guard case .failure(let error) = try Self.request(json) else {
                Issue.record("accepted: \(json)"); continue
            }
            #expect(error.message.hasPrefix("add_component:"), "\(error.message)")
            #expect(error.message.contains(word), "\(error.message) should say \(word)")
        }
    }

    // MARK: Building it

    @Test("It is one component in the Library holding each look as a named version")
    func oneComponentWithItsLooks() throws {
        let (document, made) = try Self.built(Self.toggle)
        #expect(document.componentLibraryEntries.count == 1)
        let versions = document.componentVersions(of: made.componentID)
        #expect(versions.map(\.name) == ["Off", "On", "Disabled"])
        #expect(document.componentVariantName(of: made.componentID) == "State")
        #expect(document.mainComponent(componentID: made.componentID)?.name == "Toggle")
        #expect(made.looks.map(\.name) == ["Off", "On", "Disabled"])
    }

    @Test("Each look differs only where its changes say")
    func looksDiffer() throws {
        let (document, made) = try Self.built(Self.toggle)
        let offTrack = Self.piece("Track", of: "Off", in: document, made)
        let onTrack = Self.piece("Track", of: "On", in: document, made)
        #expect(offTrack?.annotation?.fill?.hex == "#E9E9EA")
        #expect(onTrack?.annotation?.fill?.hex == "#34C759")
        #expect(Self.piece("Knob", of: "Off", in: document, made)?.frame.minX == 2)
        #expect(Self.piece("Knob", of: "On", in: document, made)?.frame.minX == 22)
        #expect(Self.piece("Knob", of: "On", in: document, made)?.frame.width == 27)
        #expect(Self.piece("Track", of: "Disabled", in: document, made)?.style.opacity == 0.4)
        #expect(Self.piece("Track", of: "Disabled", in: document, made)?.annotation?.fill?.hex == "#E9E9EA")
        #expect(offTrack?.annotation?.cornerRadii == CornerRadii(15.5))
    }

    @Test("The looks sit in one row, a step apart, starting where the call said")
    func looksInARow() throws {
        let (document, made) = try Self.built(Self.toggle)
        let boxes = made.looks.compactMap { document.canvasBounds(of: $0.layer) }
        #expect(boxes.map(\.minX) == [100, 175, 250], "51 wide plus 24 between, when no step is given")
        #expect(boxes.allSatisfy { $0.minY == 200 })
        let (buttons, madeButtons) = try Self.built(Self.button)
        #expect(madeButtons.looks.compactMap { buttons.canvasBounds(of: $0.layer)?.minX } == [40, 200, 360])
    }

    @Test("Words are set centred in the part they name, with no legibility shadow")
    func wordsCentred() throws {
        let (document, made) = try Self.built(Self.button)
        let label = try #require(Self.piece("Label", of: "Default", in: document, made))
        #expect(label.text?.string == "Continue")
        #expect(label.frame == CGRect(x: 28, y: 10, width: 64, height: 20))
        #expect(label.style.shadows.isEmpty)
        #expect(label.text?.weight == .semibold)
        #expect(label.text?.colorHex == "#FFFFFF")
    }

    @Test("New words are measured again and stay centred")
    func rewordedStaysCentred() throws {
        let (document, made) = try Self.built(Self.button)
        let label = try #require(Self.piece("Label", of: "Busy", in: document, made))
        #expect(label.text?.string == "Saving now")
        #expect(label.frame == CGRect(x: 20, y: 10, width: 80, height: 20))
        #expect(Self.piece("Label", of: "Default", in: document, made)?.text?.string == "Continue")
    }

    @Test("Words given a box sit centred in it unless told to sit left or right")
    func wordsInABox() throws {
        let json = ##"""
            {"name": "Row", "x": 0, "y": 0, "labels": false,
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 300, "height": 44, "fill": "#F2F2F7"},
                       {"name": "Title", "shape": "text", "text": "Wi-Fi", "x": 16, "y": 0, "width": 200, "height": 44, "alignment": "left"},
                       {"name": "Value", "shape": "text", "text": "Home", "x": 200, "y": 0, "width": 84, "height": 44, "alignment": "right"},
                       {"name": "Badge", "shape": "text", "text": "New", "x": 100, "y": 0, "width": 100, "height": 44}],
             "firstLook": "Default", "looks": [{"name": "Long", "changes": [{"part": "Value", "text": "Office Network"}]}]}
            """##
        let (document, made) = try Self.built(json)
        #expect(Self.piece("Title", of: "Default", in: document, made)?.frame == CGRect(x: 16, y: 12, width: 40, height: 20))
        #expect(Self.piece("Value", of: "Default", in: document, made)?.frame == CGRect(x: 252, y: 12, width: 32, height: 20))
        #expect(Self.piece("Badge", of: "Default", in: document, made)?.frame == CGRect(x: 138, y: 12, width: 24, height: 20))
        #expect(Self.piece("Value", of: "Long", in: document, made)?.frame == CGRect(x: 172, y: 12, width: 112, height: 20),
                "new words keep to the right edge of their box")
    }

    @Test("The model is sent add_component's keys in the order a person writes them; other tools stay sorted")
    func keysInWritingOrder() throws {
        let body: AgentJSON = ["tools": .array(AskTools.modelTools)]
        let wire = String(decoding: AskTools.wireEncoded(body), as: UTF8.self)
        let tool = try #require(wire.range(of: #"{"name":"add_component""#))
        let part = try #require(wire.range(of: #""items":{"#, range: tool.upperBound..<wire.endIndex))
        let rest = String(wire[part.upperBound...])
        func at(_ key: String) -> Int {
            rest.range(of: "\"\(key)\":").map { rest.distance(from: rest.startIndex, to: $0.lowerBound) } ?? Int.max
        }
        #expect(at("name") < at("shape") && at("shape") < at("x") && at("x") < at("y")
                && at("y") < at("width") && at("width") < at("height") && at("height") < at("text")
                && at("text") < at("fill"), "\(rest.prefix(600))")
        let top = String(wire[tool.lowerBound...])
        let parts = try #require(top.range(of: #""parts":{"#))
        let looks = try #require(top.range(of: #""looks":{"#))
        #expect(parts.lowerBound < looks.lowerBound, "the parts come before the looks that change them")
        // Everything else goes out exactly as before.
        let plain: AgentJSON = ["tools": .array(AskTools.modelTools.filter { $0["function"]?["name"]?.stringValue != "add_component" })]
        #expect(AskTools.wireEncoded(plain) == plain.encoded())
    }

    @Test("A component asked onto a row that is taken goes to the next free row, at the same x")
    func neverOnTopOfAnother() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        let first = try document.agentAddComponent(try Self.spec(Self.toggle), measure: Self.measure).get()
        let second = try document.agentAddComponent(try Self.spec(Self.toggle), measure: Self.measure).get()
        let firstBoxes = first.looks.compactMap { document.canvasBounds(of: $0.layer) }
        let secondBoxes = second.looks.compactMap { document.canvasBounds(of: $0.layer) }
        #expect(secondBoxes.map(\.minX) == firstBoxes.map(\.minX))
        #expect(secondBoxes.allSatisfy { $0.minY == 200 + 31 + 24 }, "\(secondBoxes)")
        // Somewhere free is left where it was asked.
        let json = Self.toggle.replacingOccurrences(of: #""x": 100, "y": 200"#, with: #""x": 100, "y": 600"#)
        let third = try document.agentAddComponent(try Self.spec(json), measure: Self.measure).get()
        #expect(third.looks.compactMap { document.canvasBounds(of: $0.layer)?.minY } == [600, 600, 600])
    }

    @Test("A look after the first that changes nothing is refused, saying what to give")
    func aLookThatChangesNothing() throws {
        guard case .failure(let schema) = try Self.request(##"""
            {"name": "Chip", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 60, "height": 24}],
             "looks": [{"name": "Hover", "changes": []}]}
            """##) else { Issue.record("accepted"); return }
        #expect(schema.message.contains("changes"), "\(schema.message)")
        let spec = AgentNewComponent(name: "Chip", origin: .zero,
                                     parts: [AgentComponentPart(name: "Back", kind: .shape(.rectangle),
                                                                frame: CGRect(x: 0, y: 0, width: 60, height: 24))],
                                     looks: [AgentComponentLook(name: "Default"), AgentComponentLook(name: "Hover")])
        #expect(spec.problem?.contains("Hover") == true)
        #expect(spec.problem?.contains("changes") == true)
    }

    @Test("A look only a shade off the first is refused, saying which change is too small to see")
    func aLookTooCloseToTell() throws {
        func badge(_ hover: String) -> String {
            ##"""
            {"name": "Badge", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 40, "height": 20, "cornerRadius": 10, "fill": "#FF3B30"},
                       {"name": "Count", "shape": "text", "text": "3", "fontSize": 13, "color": "#FFFFFF", "x": 0, "y": 0, "width": 0, "height": 0, "centerIn": "Back"}],
             "looks": [{"name": "Hover", "changes": [\##(hover)]}]}
            """##
        }
        guard case .failure(let shade) = try Self.request(badge(##"{"part": "Back", "fill": "#FF453A"}"##)) else {
            Issue.record("accepted a look a shade off the first"); return
        }
        #expect(shade.message.contains("Hover"), "\(shade.message)")
        #expect(shade.message.contains("#FF453A"), "\(shade.message)")
        // Words a shade off, an opacity barely changed, both together: still one look.
        for small in [##"{"part": "Count", "color": "#F4F4F4"}"##, ##"{"part": "Back", "opacity": 0.92}"##,
                      ##"{"part": "Back", "fill": "#FF453A"}, {"part": "Count", "color": "#FAFAFA"}"##] {
            guard case .failure = try Self.request(badge(small)) else { Issue.record("accepted \(small)"); continue }
        }
        // A change the eye sees passes, alone or beside a small one.
        for plain in [##"{"part": "Back", "fill": "#D70015"}"##, ##"{"part": "Back", "opacity": 0.4}"##,
                      ##"{"part": "Count", "visible": false}"##, ##"{"part": "Count", "text": "4"}"##,
                      ##"{"part": "Back", "y": 2}"##, ##"{"part": "Back", "stroke": "#000000", "strokeWidth": 2}"##,
                      ##"{"part": "Back", "fill": "#FF453A"}, {"part": "Count", "color": "#000000"}"##] {
            #expect(throws: Never.self, "\(plain)") { _ = try Self.request(badge(plain)).get() }
        }
        #expect(throws: Never.self) { _ = try Self.request(Self.toggle).get() }
        #expect(throws: Never.self) { _ = try Self.request(Self.button).get() }
        // Judged by how much lighter or darker, or by a new hue: a hover a step darker is plain.
        #expect(AgentNewComponent.plainlyApart("#2563EB", "#1D4ED8") == true)
        #expect(AgentNewComponent.plainlyApart("#F2F2F7", "#D1D1D6") == true)
        #expect(AgentNewComponent.plainlyApart("#FF3B30", "#FF453A") == false)
        #expect(AgentNewComponent.plainlyApart("#0A84FF", "#007AFF") == false)
        for (was, asked) in [("#FF3B30", "#FF453A"), ("#007AFF", "#0A84FF"), ("#FFFFFF", "#FAFAFA"), ("#000000", "#050505")] {
            #expect(AgentNewComponent.plainlyApart(AgentNewComponent.widened(asked, from: was), was) == true, "\(was) \(asked)")
        }
    }

    @Test("A surface the canvas's own white, with no edge or shadow, is refused: nobody could see it")
    func anUnseenSurface() throws {
        func card(_ background: String) -> String {
            ##"""
            {"name": "Card", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 240, "height": 120, "cornerRadius": 12, \##(background)},
                       {"name": "Title", "shape": "text", "text": "Title", "fontSize": 17, "x": 16, "y": 16, "width": 0, "height": 0}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#D1D1D6"}]}]}
            """##
        }
        guard case .failure(let unseen) = try Self.request(card(##""fill": "#FFFFFF""##)) else {
            Issue.record("accepted a white surface with no edge on a white canvas"); return
        }
        #expect(unseen.message.contains("Background"), "\(unseen.message)")
        guard case .failure = try Self.request(card(##""fill": "#FDFDFD", "stroke": "none""##)) else {
            Issue.record("accepted a near-white surface with its edge taken off"); return
        }
        for seen in [##""fill": "#F2F2F7""##, ##""fill": "#FFFFFF", "stroke": "#E5E5EA", "strokeWidth": 1"##,
                     ##""fill": "#FFFFFF", "shadow": {"opacity": 0.12, "radius": 8, "y": 2}"##] {
            #expect(throws: Never.self, "\(seen)") { _ = try Self.request(card(seen)).get() }
        }
        // White on top of another part is seen against that part: a toggle's knob.
        #expect(throws: Never.self) { _ = try Self.request(Self.toggle).get() }
    }

    @Test("Two components drawn alike are told apart from two kinds that only share a size")
    func drawnAlike() throws {
        let toggle = try Self.spec(Self.toggle)
        var renamed = toggle
        renamed.name = "Switch"
        renamed.origin = CGPoint(x: 600, y: 900)
        #expect(renamed.drawnLike(toggle))
        #expect(!(try Self.spec(Self.button)).drawnLike(toggle))
        var recoloured = toggle
        recoloured.parts[0].look.fill = AgentInk("#5856D6")
        #expect(!recoloured.drawnLike(toggle), "a different colour is a different look")
        var resized = toggle
        resized.parts[0].frame.size.width = 80
        #expect(!resized.drawnLike(toggle))
    }

    @Test("A shadow nobody could see is no shadow")
    func invisibleShadow() throws {
        let json = ##"""
            {"name": "Chip", "x": 0, "y": 0, "labels": false,
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 60, "height": 24, "shadow": {"opacity": 0, "radius": 0}}],
             "firstLook": "Default", "looks": [{"name": "Off", "changes": [{"part": "Back", "opacity": 0.5}]}]}
            """##
        let (document, made) = try Self.built(json)
        #expect(Self.piece("Back", of: "Default", in: document, made)?.style.shadows.isEmpty == true)
    }

    @Test("labels names the row on its left and its states once above them, and a second set goes under it")
    func labelled() throws {
        let json = Self.toggle.replacingOccurrences(of: #""labels": false,"#, with: #""labels": true,"#)
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        let made = try document.agentAddComponent(try Self.spec(json), measure: Self.measure).get()
        let boxes = made.looks.compactMap { document.canvasBounds(of: $0.layer) }
        let words = document.layers.filter { $0.text != nil }
        #expect(Set(words.compactMap(\.text?.string)) == ["Toggle", "Off", "On", "Disabled"])
        #expect(made.labels.compactMap { document.layer(id: $0)?.text?.string } == ["Toggle"],
                "every state is its column's, so none is named under its look")
        let name = try #require(made.labels.first.flatMap { document.layer(id: $0) })
        #expect(name.frame.minX == 100)
        #expect(name.frame.maxX <= boxes[0].minX)
        #expect(abs(name.frame.midY - boxes[0].midY) <= 1, "the name sits level with the row")
        #expect(Set(words.compactMap { $0.text?.fontSize }).count == 1, "one size for every label")
        // A second set asked onto the same spot goes under it, words and all.
        let again = try document.agentAddComponent(try Self.spec(json), measure: Self.measure).get()
        let secondName = try #require(again.labels.first.flatMap { document.layer(id: $0) })
        let first = try #require(made.looks.first.flatMap { document.canvasBounds(of: $0.layer) })
        let second = try #require(again.looks.first.flatMap { document.canvasBounds(of: $0.layer) })
        let band = max(first.height, AgentNewComponent.rowHeight)
        #expect(abs(second.midY - first.midY - (band + AgentNewComponent.rowGap)) <= 1)
        #expect(secondName.frame.minX == 100)
    }

    @Test("Words set on top of other words are refused, naming both, so the component is drawn again")
    func wordsOverWords() throws {
        func card(_ title: String, _ body: String) -> String {
            ##"""
            {"name": "Card", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 120},
                       {"name": "Title", "shape": "text", "text": "Card Title", "fontSize": 17, \##(title)},
                       {"name": "Body", "shape": "text", "text": "Card content goes here", "fontSize": 15, \##(body)}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#F2F2F7"}]}]}
            """##
        }
        // Both centred in the card: one line on the other.
        guard case .failure(let stacked) = try Self.request(card(
            #""centerIn": "Background", "x": 0, "y": 0, "width": 0, "height": 0"#,
            #""centerIn": "Background", "x": 0, "y": 0, "width": 0, "height": 0"#)) else {
            Issue.record("accepted words over words"); return
        }
        #expect(stacked.message.contains("Title") && stacked.message.contains("Body"), "\(stacked.message)")
        // Boxes that share a middle put the words on one another too.
        guard case .failure = try Self.request(card(#""x": 16, "y": 40, "width": 168, "height": 20"#,
                                                    #""x": 16, "y": 30, "width": 168, "height": 40"#)) else {
            Issue.record("accepted boxes sharing a middle"); return
        }
        // One under the other is a card.
        #expect(throws: Never.self) {
            _ = try Self.request(card(#""x": 16, "y": 16, "width": 168, "height": 24"#,
                                      #""x": 16, "y": 48, "width": 168, "height": 24"#)).get()
        }
        // Side by side in their own boxes is a segmented control.
        let segments = ##"""
            {"name": "Segments", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 180, "height": 28},
                       {"name": "One", "shape": "text", "text": "One", "x": 0, "y": 0, "width": 60, "height": 28},
                       {"name": "Two", "shape": "text", "text": "Two", "x": 60, "y": 0, "width": 60, "height": 28},
                       {"name": "Three", "shape": "text", "text": "Three", "x": 120, "y": 0, "width": 60, "height": 28}],
             "looks": [{"name": "Hover", "changes": [{"part": "Track", "fill": "#E5E5EA"}]}]}
            """##
        #expect(throws: Never.self) { _ = try Self.request(segments).get() }
    }

    @Test("Words longer than the box they sit in are refused, so they never run past the component's edge")
    func wordsPastTheirBox() throws {
        func card(_ words: String, width: Int, height: Int = 24) -> String {
            ##"""
            {"name": "Card", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 120},
                       {"name": "Body", "shape": "text", "text": "\##(words)", "fontSize": 15, "x": 16, "y": 40, "width": \##(width), "height": \##(height)}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#F2F2F7"}]}]}
            """##
        }
        guard case .failure(let long) = try Self.request(card("Card body text goes here with description.", width: 168)) else {
            Issue.record("accepted words longer than their box"); return
        }
        #expect(long.message.contains("Body"), "\(long.message)")
        #expect(throws: Never.self) { _ = try Self.request(card("Card body text", width: 168)).get() }
        // A box tall enough for three lines wraps the words onto them (the
        // eval, 2026-10-24: a card's body in a 64 point box refused twelve
        // times as one line, and the sheet lost its card).
        #expect(throws: Never.self) {
            _ = try Self.request(card("Card body text goes here with description.", width: 168, height: 64)).get()
        }
        // A box of no width is no box: the words sit from its left edge, and
        // these run on past the card's.
        guard case .failure(let past) = try Self.request(card("Card body text goes here with description.", width: 0)) else {
            Issue.record("accepted words running past the card"); return
        }
        #expect(past.message.contains("Body") && past.message.contains("Background"), "\(past.message)")
    }

    @Test("Words half on a box are refused, naming both: wholly inside it or wholly off it")
    func wordsHalfOnABox() throws {
        func tab(iconY: Int, labelX: Int = 0) -> String {
            ##"""
            {"name": "Tab", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Bar", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 49, "fill": "#F2F2F7"},
                       {"name": "Icon", "shape": "rectangle", "x": 48, "y": \##(iconY), "width": 24, "height": 24, "cornerRadius": 6, "fill": "#007AFF"},
                       {"name": "Name", "shape": "text", "text": "Search", "fontSize": 10, "x": \##(labelX), "y": 32, "width": 120, "height": 12}],
             "looks": [{"name": "Selected", "changes": [{"part": "Icon", "fill": "#8E8E93"}]}]}
            """##
        }
        guard case .failure(let onIcon) = try Self.request(tab(iconY: 22)) else { Issue.record("accepted words on an icon"); return }
        #expect(onIcon.message.contains("Name") && onIcon.message.contains("Icon"), "\(onIcon.message)")
        guard case .failure(let pastBar) = try Self.request(tab(iconY: 4, labelX: 60)) else { Issue.record("accepted words past the bar"); return }
        #expect(pastBar.message.contains("Bar"), "\(pastBar.message)")
        #expect(throws: Never.self) { _ = try Self.request(tab(iconY: 4)).get() }
        // Words centred in their control, and words beside a box rather than on it, are fine.
        #expect(throws: Never.self) { _ = try Self.request(Self.button).get() }
        #expect(throws: Never.self) { _ = try Self.request(##"""
            {"name": "Check", "x": 0, "y": 0, "labels": false, "firstLook": "Off",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 20, "height": 20, "stroke": "#8E8E93", "strokeWidth": 1.5},
                       {"name": "Label", "shape": "text", "text": "Remember me", "fontSize": 15, "x": 28, "y": 0, "width": 0, "height": 20}],
             "looks": [{"name": "On", "changes": [{"part": "Box", "fill": "#007AFF"}]}]}
            """##).get() }
    }

    @Test("A part can start hidden and show in a later look: a check mark only On shows")
    func aPartHiddenInTheFirstLook() throws {
        func checkbox(_ check: String) -> String {
            ##"""
            {"name": "Checkbox", "x": 0, "y": 0, "labels": false, "firstLook": "Off",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 22, "height": 22, "cornerRadius": 6, "stroke": "#8E8E93", "strokeWidth": 1.5},
                       {"name": "Check", "shape": "path", "x": 5, "y": 6, "width": 12, "height": 10, "stroke": "#FFFFFF", "strokeWidth": 2,
                        "points": [{"x": 0, "y": 5}, {"x": 4, "y": 9}, {"x": 12, "y": 0}]\##(check)}],
             "looks": [{"name": "On", "changes": [{"part": "Box", "fill": "#007AFF", "stroke": "#007AFF"}, {"part": "Check", "visible": true}]},
                       {"name": "Disabled", "changes": [{"part": "Box", "opacity": 0.4}]}]}
            """##
        }
        for said in [#", "visible": false"#, ""] {
            let (document, made) = try Self.built(checkbox(said))
            #expect(Self.piece("Check", of: "Off", in: document, made)?.isVisible == false, "said: \(said)")
            #expect(Self.piece("Check", of: "On", in: document, made)?.isVisible == true, "said: \(said)")
            #expect(Self.piece("Check", of: "Disabled", in: document, made)?.isVisible == false, "said: \(said)")
        }
        // A look that only shows a hidden part is a change a person sees.
        let spec = try Self.spec(checkbox(""))
        #expect(spec.tooSmallToSee(spec.looks[1]) == nil)
    }

    @Test("Words nobody could read against what is behind them are refused: the canvas, or the box they sit on")
    func unreadableWords() throws {
        func row(_ label: String, back: String = "#E5E5EA") -> String {
            ##"""
            {"name": "Row", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 32, "cornerRadius": 8, "fill": "\##(back)"},
                       {"name": "Inside", "shape": "text", "text": "One", "fontSize": 13, "x": 0, "y": 0, "width": 0, "height": 0, "centerIn": "Box", "color": "\##(label)"},
                       {"name": "Beside", "shape": "text", "text": "Option", "fontSize": 15, "x": 132, "y": 6, "width": 0, "height": 0, "color": "\##(label)"}],
             "looks": [{"name": "Disabled", "changes": [{"part": "Box", "opacity": 0.4}]}]}
            """##
        }
        guard case .failure(let onCanvas) = try Self.request(row("#F2F2F7", back: "#007AFF")) else { Issue.record("accepted white words on the white canvas"); return }
        #expect(onCanvas.message.contains("Beside") && onCanvas.message.contains("canvas"), "\(onCanvas.message)")
        guard case .failure(let onBox) = try Self.request(row("#1C1C1E", back: "#2C2C2E")) else { Issue.record("accepted dark words on a dark box"); return }
        #expect(onBox.message.contains("Inside") && onBox.message.contains("Box"), "\(onBox.message)")
        #expect(throws: Never.self) { _ = try Self.request(row("#1C1C1E")).get() }
        #expect(throws: Never.self) { _ = try Self.request(row("#8E8E93")).get() }
        #expect(throws: Never.self) { _ = try Self.request(Self.button).get() }
        // Blue words on a darker blue box (the eval, 2026-10-24: a pressed
        // secondary button) are as hard to read as their ratio of 1.64 hides;
        // the faint grey Apple sets a disabled label in still reads.
        guard case .failure(let blue) = try Self.request(row("#007AFF", back: "#0056CC")) else { Issue.record("accepted blue words on a blue box"); return }
        #expect(blue.message.contains("Inside"), "\(blue.message)")
        #expect(throws: Never.self) { _ = try Self.request(row("#AEAEB2")).get() }
        #expect(throws: Never.self) { _ = try Self.request(row("#FFFFFF", back: "#34C759").replacingOccurrences(of: ##""color": "#FFFFFF"}],"##, with: ##""color": "#000000"}],"##)).get() }
        // Ask's planner sets them in the colour that reads instead of refusing.
        let plain = AgentNewComponent.madePlain(try AgentJSON.parse(Data(row("#F2F2F7").utf8)))
        guard case .success(.addComponent(_, let spec)) = AgentTools.request(tool: "add_component", arguments: plain) else {
            Issue.record("the plain call is still refused"); return
        }
        #expect(spec.problem == nil)
    }

    @Test("Words that land on words in a later look are refused too, naming the look")
    func wordsOverWordsInALaterLook() throws {
        func segmented(_ second: String) -> String {
            ##"""
            {"name": "Segmented", "x": 0, "y": 0, "labels": false, "firstLook": "First",
             "parts": [{"name": "Track", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 32, "cornerRadius": 8, "fill": "#E5E5EA"},
                       {"name": "Pill", "shape": "rectangle", "x": 2, "y": 2, "width": 98, "height": 28, "cornerRadius": 7, "fill": "#FFFFFF"},
                       {"name": "Daily", "shape": "text", "text": "Daily", "fontSize": 13, "x": 2, "y": 2, "width": 98, "height": 28},
                       {"name": "Weekly", "shape": "text", "text": "Weekly", "fontSize": 13, "x": 100, "y": 2, "width": 98, "height": 28}],
             "looks": [{"name": "Second", "changes": [{"part": "Pill", "x": 100}, \##(second)]}]}
            """##
        }
        guard case .failure(let stacked) = try Self.request(segmented(##"{"part": "Daily", "x": 100}"##)) else {
            Issue.record("accepted words moved onto words"); return
        }
        #expect(stacked.message.contains("Second") && stacked.message.contains("Daily") && stacked.message.contains("Weekly"), "\(stacked.message)")
        #expect(throws: Never.self) { _ = try Self.request(segmented(##"{"part": "Weekly", "color": "#000000"}"##)).get() }
    }

    @Test("Words a later look leaves unreadable are refused, and Ask's planner recolours them to the nearest shade that reads")
    func unreadableInALaterLook() throws {
        let json = ##"""
            {"name": "Secondary", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 120, "height": 40, "cornerRadius": 10, "fill": "#007AFF"},
                       {"name": "Label", "shape": "text", "text": "Cancel", "fontSize": 15, "x": 0, "y": 0, "width": 0, "height": 0, "centerIn": "Back", "color": "#FFFFFF"}],
             "looks": [{"name": "Hover", "changes": [{"part": "Back", "fill": "#F2F2F7"}]}]}
            """##
        guard case .failure(let lost) = try Self.request(json) else { Issue.record("accepted white words on a white hover"); return }
        #expect(lost.message.contains("Hover") && lost.message.contains("Label"), "\(lost.message)")
        let plain = AgentNewComponent.madePlain(try AgentJSON.parse(Data(json.utf8)))
        guard case .success(.addComponent(_, let spec)) = AgentTools.request(tool: "add_component", arguments: plain) else {
            Issue.record("the plain call is still refused"); return
        }
        #expect(spec.problem == nil)
        #expect(spec.inLook(spec.looks[1]).parts[1].colorHex != "#FFFFFF")
        #expect(spec.parts[1].colorHex == "#FFFFFF", "the first look keeps the words it could read")
    }

    @Test("A text colour change lands on the words")
    func wordColour() throws {
        let json = ##"""
            {"name": "Link", "x": 0, "y": 0, "labels": false,
             "parts": [{"name": "Label", "shape": "text", "x": 0, "y": 0, "width": 0, "height": 0, "text": "More", "color": "#007AFF"}],
             "firstLook": "Default", "looks": [{"name": "Disabled", "changes": [{"part": "Label", "color": "#AEAEB2"}]}]}
            """##
        let (document, made) = try Self.built(json)
        #expect(Self.piece("Label", of: "Disabled", in: document, made)?.text?.colorHex == "#AEAEB2")
        #expect(Self.piece("Label", of: "Default", in: document, made)?.text?.colorHex == "#007AFF")
    }

    @Test("A path part is drawn where its points say, inside the component")
    func pathPart() throws {
        let json = ##"""
            {"name": "Checkbox", "x": 10, "y": 10, "labels": false,
             "parts": [{"name": "Box", "shape": "rectangle", "x": 0, "y": 0, "width": 22, "height": 22, "cornerRadius": 6, "fill": "#007AFF"},
                       {"name": "Check", "shape": "path", "x": 0, "y": 0, "width": 22, "height": 22, "points": [{"x": 6, "y": 11}, {"x": 10, "y": 15}, {"x": 16, "y": 7}], "stroke": "#FFFFFF", "strokeWidth": 2}],
             "firstLook": "Checked", "looks": [{"name": "Unchecked", "changes": [{"part": "Check", "visible": false}, {"part": "Box", "fill": "#FFFFFF", "stroke": "#C7C7CC", "strokeWidth": 1}]}]}
            """##
        let (document, made) = try Self.built(json)
        let check = try #require(Self.piece("Check", of: "Checked", in: document, made))
        #expect(check.path != nil)
        #expect(check.frame.minX == 6 && check.frame.minY == 7)
        #expect(Self.piece("Check", of: "Unchecked", in: document, made)?.isVisible == false)
        #expect(Self.piece("Box", of: "Unchecked", in: document, made)?.style.borderColorHex == "#C7C7CC")
    }

    @Test("A text change on a shape is refused, naming the part")
    func changeThatCannotLand() throws {
        let json = ##"""
            {"name": "Chip", "x": 0, "y": 0, "labels": false,
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 60, "height": 24}],
             "firstLook": "A", "looks": [{"name": "B", "changes": [{"part": "Back", "text": "Hi"}]}]}
            """##
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [])
        guard case .failure(let error) = document.agentAddComponent(try Self.spec(json), measure: Self.measure) else {
            Issue.record("words landed on a box"); return
        }
        #expect(error.message.contains("Back"))
        #expect(document.layers.isEmpty, "nothing is left half built")
    }
}

