import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The design-system tools of the agent channel (`docs/design/agent-mcp.md`,
/// "Design systems"): colours and type saved under a name on the Library's
/// Styles shelf, put on layers by name, and the spacing a group keeps (a stack
/// or grid with its gap and padding), so an agent can build a website's design
/// system as the Library a person would build.
@Suite("Agent design system: styles and layout")
struct AgentDesignTests {

    static func request(_ tool: String, _ json: String) throws -> Result<AgentRequest, AgentToolError> {
        AgentTools.request(tool: tool, arguments: try AgentJSON.parse(Data(json.utf8)))
    }

    @Test("The design tools are offered, each with an object schema")
    func offered() {
        for name in ["list_styles", "add_style", "apply_style", "set_layout"] {
            let tool = AgentTools.tool(named: name)
            #expect(tool != nil, "\(name) is missing")
            #expect(tool?.inputSchema["type"]?.stringValue == "object")
        }
    }

    // MARK: add_style

    @Test("A colour style carries its name and colour")
    func colourStyleCall() throws {
        let request = try Self.request("add_style", ##"{"kind": "color", "name": "Brand", "color": "#5e6ad2"}"##).get()
        guard case .addStyle(nil, let style) = request else { Issue.record("\(request)"); return }
        #expect(style == .color(name: "Brand", hex: "#5E6AD2"))
    }

    @Test("A text style carries its font, size, weight and colour, with the Text tool's defaults")
    func textStyleCall() throws {
        let request = try Self.request("add_style", ##"""
            {"kind": "text", "name": "Heading", "size": 32, "weight": "semibold", "color": "#111111"}
            """##).get()
        guard case .addStyle(nil, let style) = request else { Issue.record("\(request)"); return }
        #expect(style == .text(name: "Heading", treatment: TextTreatment(fontName: "SF Pro", fontSize: 32,
                                                                          weight: .semibold, colorHex: "#111111")))
    }

    @Test("A colour style needs a colour, and words that are not a colour are refused")
    func colourStyleNeedsAColour() throws {
        guard case .failure(let none) = try Self.request("add_style", ##"{"kind": "color", "name": "Brand"}"##)
        else { Issue.record("a colour style with no colour was accepted"); return }
        #expect(none.message.contains("color"))
        guard case .failure(let bad) = try Self.request("add_style", ##"{"kind": "color", "name": "B", "color": "blue"}"##)
        else { Issue.record("a colour name was accepted"); return }
        #expect(bad.message.contains("#RRGGBB"))
        guard case .failure(let textOnly) = try Self.request(
            "add_style", ##"{"kind": "color", "name": "B", "color": "#000000", "size": 12}"##)
        else { Issue.record("a colour style with a size was accepted"); return }
        #expect(textOnly.message.contains("text style"))
    }

    // MARK: apply_style

    @Test("apply_style names a style and the layers, and the part for a colour")
    func applyCall() throws {
        let request = try Self.request("apply_style", ##"{"style": "Brand", "layers": ["A", "B"], "part": "stroke"}"##).get()
        guard case .applyStyle(nil, let style, let layers, let part) = request else { Issue.record("\(request)"); return }
        #expect(style == "Brand")
        #expect(layers == ["A", "B"])
        #expect(part == .stroke)
        guard case .failure = try Self.request("apply_style", ##"{"style": "Brand", "layers": []}"##)
        else { Issue.record("no layers was accepted"); return }
    }

    @Test("The parts a colour goes on are the app's own colour parts")
    func partsAreSlots() {
        #expect(AgentStylePart.fill.slot == .fill)
        #expect(AgentStylePart.stroke.slot == .stroke)
        #expect(AgentStylePart.text.slot == .text)
    }

    @Test("A colour style is put on the part a layer has: a fill on a box, the ink on words")
    func defaultPart() {
        #expect(AgentStylePart.defaultSlot(for: [.fill, .stroke]) == .fill)
        #expect(AgentStylePart.defaultSlot(for: [.text]) == .text)
        #expect(AgentStylePart.defaultSlot(for: [.stroke, .arrowHead]) == .stroke)
        #expect(AgentStylePart.defaultSlot(for: []) == nil)
    }

    // MARK: Finding a style

    @Test("A style is found by id or by its name in any case, colours and type alike")
    func findStyle() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let brand = document.addColorStyle(name: "Brand", colorHex: "#5E6AD2")
        let heading = document.addTextStyle(name: "Heading", treatment: TextTreatment(
            fontName: "SF Pro", fontSize: 32, weight: .bold, colorHex: "#111111"))
        #expect(document.agentStyle(named: "brand") == .color(brand))
        #expect(document.agentStyle(named: brand.uuidString) == .color(brand))
        #expect(document.agentStyle(named: " Heading ") == .text(heading))
        #expect(document.agentStyle(named: "Body") == nil)
    }

    @Test("list_styles lists colours and type with what each holds")
    func listing() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        document.addColorStyle(name: "Brand", colorHex: "#5E6AD2")
        document.addTextStyle(name: "Body", treatment: TextTreatment(
            fontName: "Inter", fontSize: 16, weight: .regular, colorHex: "#333333"))
        let listing = AgentStyleListing.make(document)
        #expect(listing.colors.contains { $0.name == "Brand" && $0.color == "#5E6AD2" })
        #expect(listing.text == [AgentStyleListing.Text(id: listing.text[0].id, name: "Body", font: "Inter",
                                                        size: 16, weight: "regular", color: "#333333")])
    }

    // MARK: set_layout

    @Test("set_layout carries a stack's direction, gap and padding")
    func layoutCall() throws {
        let request = try Self.request("set_layout", ##"""
            {"layer": "G", "arrange": "stack", "direction": "row", "gap": 16, "padding": 24, "width": 320}
            """##).get()
        guard case .setLayout(nil, "G", let change) = request else { Issue.record("\(request)"); return }
        #expect(change.arrange == .stack)
        #expect(change.direction == .row)
        #expect(change.gap == 16)
        #expect(change.padding == GroupPadding(24))
        #expect(change.width == .fixed(320))
    }

    @Test("Padding can be one number or each side, and a size can hug")
    func paddingSidesAndHug() throws {
        let request = try Self.request("set_layout", ##"""
            {"layer": "G", "padding": {"top": 8, "bottom": 8, "left": 16, "right": 16}, "height": "hug"}
            """##).get()
        guard case .setLayout(_, _, let change) = request else { Issue.record("\(request)"); return }
        #expect(change.padding == GroupPadding(top: 8, right: 16, bottom: 8, left: 16))
        #expect(change.height == .hug)
        guard case .failure(let nothing) = try Self.request("set_layout", ##"{"layer": "G"}"##)
        else { Issue.record("a call that changes nothing was accepted"); return }
        #expect(nothing.message.contains("nothing"))
        guard case .failure(let badSize) = try Self.request("set_layout", ##"{"layer": "G", "width": "wide"}"##)
        else { Issue.record("a word for a width was accepted"); return }
        #expect(badSize.message.contains("hug"))
    }

    @Test("The numbers land on the group's layout and leave the rest as it was")
    func applyingTheNumbers() {
        var layout = GroupLayout.free(padding: .none)
        layout.kind = .stack
        layout.gap = 12
        layout.columns = 3
        var change = AgentLayoutChange()
        change.direction = .row
        change.gap = 20
        change.padding = GroupPadding(10)
        change.width = .fixed(400)
        change.height = .hug
        change.spread = true
        change.applied(to: &layout)
        #expect(layout.direction == .row)
        #expect(layout.gap == 20)
        #expect(layout.padding == GroupPadding(10))
        #expect(layout.width == 400)
        #expect(layout.height == nil)
        #expect(layout.spreadsGap)
        #expect(layout.columns == 3)
    }

    @Test("A group made into a stack by set_layout lays its contents out with the gap asked for")
    func stackLaysOut() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let a = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")), frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        let b = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")), frame: CGRect(x: 0, y: 100, width: 50, height: 20))
        document.layers = [a, b]
        let made = document.groupLayers(ids: [a.id, b.id], name: "Card")
        let group = try #require(made)
        var change = AgentLayoutChange()
        change.arrange = .stack
        change.direction = .column
        change.gap = 8
        document.agentSetLayout(id: group.id, change)
        document.reflowLayouts()
        let children = try #require(document.layer(id: group.id)?.children)
        let tops = children.map(\.frame.minY).sorted()
        let bottoms = children.map(\.frame.maxY).sorted()
        #expect(tops[1] - bottoms[0] == 8)
    }

    @Test("read_document shows the spacing a group keeps")
    func readShowsLayout() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let a = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")), frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        let b = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")), frame: CGRect(x: 0, y: 40, width: 50, height: 20))
        document.layers = [a, b]
        let made = document.groupLayers(ids: [a.id, b.id], name: "Card")
        let group = try #require(made)
        var change = AgentLayoutChange()
        change.arrange = .stack
        change.gap = 12
        change.padding = GroupPadding(16)
        document.agentSetLayout(id: group.id, change)
        let read = AgentDocumentRead.make(document, context: .init(id: "d1", title: "t", file: nil, playheadMS: 0, canUndo: false, canRedo: false))
        let layout = try #require(read.layers.first?.layout)
        #expect(layout.arrange == "stack")
        #expect(layout.gap == 12)
        #expect(layout.padding == 16)
    }

    // MARK: Where a group is

    private func groupAt100() throws -> (PhotonzDocument, UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let a = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")), frame: CGRect(x: 100, y: 100, width: 50, height: 20))
        let b = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")), frame: CGRect(x: 100, y: 140, width: 50, height: 20))
        document.layers = [a, b]
        let made = document.groupLayers(ids: [a.id, b.id], name: "Pair")
        return (document, try #require(made).id)
    }

    @Test("read_document gives a group the box it covers on the canvas, not its stored size")
    func readGivesAGroupItsBox() throws {
        let (document, id) = try groupAt100()
        let read = AgentDocumentRead.make(document, context: .init(id: "d1", title: "t", file: nil, playheadMS: 0, canUndo: false, canRedo: false))
        let group = try #require(read.layers.first { $0.id == id.uuidString })
        #expect(group.frame == AgentDocumentRead.Rect(x: 100, y: 100, width: 50, height: 60))
    }

    @Test("set_layer moves a group to the point asked, once, not twice its position")
    func setLayerMovesAGroupOnce() throws {
        let (document, id) = try groupAt100()
        let group = try #require(document.layer(id: id))
        let moved = try AgentDrawing.applying(AgentLayerChange(x: 10, y: 30), to: group, canvas: document.canvasSize).get()
        #expect(moved.localBounds.origin == CGPoint(x: 10, y: 30))
        #expect(AgentDrawing.box(of: moved) == CGRect(x: 10, y: 30, width: 50, height: 60))
    }

    // MARK: Words inside a copy

    /// A component "Row" of a box and a "Title" saying "Story", placed twice.
    private func rowPlacedTwice() throws -> (PhotonzDocument, title: UUID, first: UUID, second: UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [
            Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
                  frame: CGRect(x: 10, y: 10, width: 300, height: 40)),
            Layer(name: "Title", content: .text(TextContent(string: "Story")), frame: CGRect(x: 20, y: 20, width: 80, height: 20)),
        ])
        let title = document.layers[1].id
        let made = document.groupLayers(ids: [document.layers[0].id, title], name: "Row")
        let groupID = try #require(made).id
        let madeComponent = document.makeComponent(id: groupID)
        let componentID = try #require(madeComponent)
        let placedFirst = document.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 100))
        let placedSecond = document.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))
        let first = try #require(placedFirst)
        let second = try #require(placedSecond)
        return (document, title, first, second)
    }

    private func words(_ document: PhotonzDocument, copy: UUID, source: UUID) -> String? {
        document.layer(id: ComponentIdentity.derived(instance: copy, source: source))?.text?.string
    }

    @Test("Words typed over a piece of a copy land on that copy alone, and stay after the copies are put back in step")
    func wordsLandOnTheCopy() throws {
        var (document, title, first, second) = try rowPlacedTwice()
        let piece = ComponentIdentity.derived(instance: first, source: title)
        let answer = document.agentWordCopyPiece(piece, to: "Wine ported to OpenBSD")
        #expect(answer == .landed(madeAdjustable: true))
        document.syncComponentInstances()
        #expect(words(document, copy: first, source: title) == "Wine ported to OpenBSD")
        #expect(words(document, copy: second, source: title) == "Story")
        // The second time, the knob is already there.
        let again = document.agentWordCopyPiece(ComponentIdentity.derived(instance: second, source: title), to: "Two")
        #expect(again == .landed(madeAdjustable: false))
        document.syncComponentInstances()
        #expect(words(document, copy: second, source: title) == "Two")
    }

    @Test("A layer that is not inside a copy is left to set_layer's ordinary edit")
    func ordinaryLayerIsNotAPiece() throws {
        var (document, title, _, _) = try rowPlacedTwice()
        #expect(document.agentWordCopyPiece(title, to: "x") == .notAPiece)
    }

    @Test("A locked copy refuses in words that say how to go on")
    func lockedCopyRefuses() throws {
        var (document, title, first, _) = try rowPlacedTwice()
        document.updateLayer(id: first) { $0.isLocked = true }
        guard case .refused(let why) = document.agentWordCopyPiece(ComponentIdentity.derived(instance: first, source: title), to: "x")
        else { Issue.record("a locked copy took the words"); return }
        #expect(why.contains("lock"))
    }

    // MARK: Reading one layer

    @Test("read_document with a layer lists that layer and everything inside it, however full the document")
    func readOneLayer() throws {
        var (document, id) = try groupAt100()
        // More layers above it than a whole read lists.
        document.layers += (0..<AgentDocumentRead.mostLayersListed).map { index in
            Layer(name: "Dot \(index)", content: .annotation(AnnotationContent(shape: .ellipse, colorHex: "#000000")),
                  frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let context = AgentDocumentRead.Context(id: "d1", title: "t", file: nil, playheadMS: 0, canUndo: false, canRedo: false)
        let whole = AgentDocumentRead.make(document, context: context)
        #expect(!whole.layers.contains { $0.id == id.uuidString }, "the group is past the whole read's budget")
        let one = AgentDocumentRead.make(document, context: context, only: id)
        #expect(one.layers.map(\.id) == [id.uuidString])
        #expect(one.layers.first?.children?.count == 2)
        #expect(try AgentTools.request(tool: "read_document", arguments: .object(["layer": "X"])).get()
                == .readDocument(document: nil, layer: "X"))
    }
}
