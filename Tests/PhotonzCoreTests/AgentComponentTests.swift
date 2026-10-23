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
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": 300, "height": 44, "fill": "#FFFFFF"},
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
        #expect(name.frame.midY.rounded() == boxes[0].midY.rounded(), "the name sits level with the row")
        #expect(Set(words.compactMap { $0.text?.fontSize }).count == 1, "one size for every label")
        // A second set asked onto the same spot goes under it, words and all.
        let again = try document.agentAddComponent(try Self.spec(json), measure: Self.measure).get()
        let secondName = try #require(again.labels.first.flatMap { document.layer(id: $0) })
        let lowest = made.looks.compactMap { document.canvasBounds(of: $0.layer)?.maxY }.max() ?? 0
        let secondTop = again.looks.compactMap { document.canvasBounds(of: $0.layer)?.minY }.min() ?? 0
        #expect(secondTop == lowest + AgentNewComponent.rowGap)
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
        func card(_ words: String, width: Int) -> String {
            ##"""
            {"name": "Card", "x": 0, "y": 0, "labels": false, "firstLook": "Default",
             "parts": [{"name": "Background", "shape": "rectangle", "x": 0, "y": 0, "width": 200, "height": 120},
                       {"name": "Body", "shape": "text", "text": "\##(words)", "fontSize": 15, "x": 16, "y": 40, "width": \##(width), "height": 24}],
             "looks": [{"name": "Hover", "changes": [{"part": "Background", "fill": "#F2F2F7"}]}]}
            """##
        }
        guard case .failure(let long) = try Self.request(card("Card body text goes here with description.", width: 168)) else {
            Issue.record("accepted words longer than their box"); return
        }
        #expect(long.message.contains("Body"), "\(long.message)")
        #expect(throws: Never.self) { _ = try Self.request(card("Card body text", width: 168)).get() }
        // A box of no width is no box: the words sit from its left edge.
        #expect(throws: Never.self) { _ = try Self.request(card("Card body text goes here with description.", width: 0)).get() }
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

