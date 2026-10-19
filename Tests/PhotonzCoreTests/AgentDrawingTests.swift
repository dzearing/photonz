import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The third slice of the agent tools (`docs/design/agent-mcp.md`): an agent
/// draws with the same layers a person draws, so each call is checked here and
/// each becomes the layer the matching tool would have made.
@Suite("Agent drawing: shapes, paths, text, layers and measurements")
struct AgentDrawingTests {

    static func args(_ json: String) throws -> AgentJSON {
        try AgentJSON.parse(Data(json.utf8))
    }

    static func request(_ tool: String, _ json: String) throws -> Result<AgentRequest, AgentToolError> {
        AgentTools.request(tool: tool, arguments: try args(json))
    }

    // MARK: The calls

    @Test("The picture slice's tools are offered after the first two slices'")
    func theToolsAreOffered() {
        let names = AgentTools.all.map(\.name)
        for name in ["new_picture", "add_shape", "add_path", "add_text", "set_layer", "find_elements",
                     "add_measurement", "list_components", "place_component", "export"] {
            #expect(names.contains(name), "\(name) is missing")
        }
    }

    @Test("A rectangle call carries its frame and its paint")
    func rectangleCall() throws {
        let request = try Self.request("add_shape", #"""
            {"shape": "rectangle", "frame": {"x": 10, "y": 20, "width": 100, "height": 50},
             "fill": "#ff0000", "stroke": "#00FF0080", "strokeWidth": 3, "cornerRadius": 8, "name": "Box"}
            """#).get()
        guard case .addShape(nil, let shape) = request else { Issue.record("\(request)"); return }
        #expect(shape.kind == .rectangle)
        #expect(shape.frame == CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(shape.look.fill == .hex("#FF0000"))
        #expect(shape.look.stroke == .hex("#00FF0080"))
        #expect(shape.look.strokeWidth == 3)
        #expect(shape.name == "Box")
    }

    @Test("A shape call missing the geometry its kind needs is refused in words")
    func shapeNeedsItsGeometry() throws {
        guard case .failure(let noFrame) = try Self.request("add_shape", #"{"shape": "ellipse"}"#)
        else { Issue.record("an ellipse with no frame was accepted"); return }
        #expect(noFrame.message.contains("needs a frame"))
        guard case .failure(let noEnds) = try Self.request("add_shape", #"{"shape": "arrow", "from": {"x": 1, "y": 1}}"#)
        else { Issue.record("an arrow with one end was accepted"); return }
        #expect(noEnds.message.contains("from and to"))
        guard case .failure(let badInk) = try Self.request(
            "add_shape", #"{"shape": "rectangle", "frame": {"x": 0, "y": 0, "width": 9, "height": 9}, "fill": "red"}"#)
        else { Issue.record("a colour name was accepted"); return }
        #expect(badInk.message.contains("#RRGGBB"))
    }

    @Test("A path call needs two points, and three to close")
    func pathCall() throws {
        let request = try Self.request("add_path", #"""
            {"points": [{"x": 0, "y": 0}, {"x": 10, "y": 0, "smooth": true}, {"x": 10, "y": 10}], "closed": true}
            """#).get()
        guard case .addPath(nil, let path) = request else { Issue.record("\(request)"); return }
        #expect(path.closed)
        #expect(path.points.map(\.smooth) == [false, true, false])
        guard case .failure = try Self.request("add_path", #"{"points": [{"x": 0, "y": 0}]}"#)
        else { Issue.record("a one point path was accepted"); return }
        guard case .failure = try Self.request("add_path", #"{"points": [{"x": 0, "y": 0}, {"x": 5, "y": 5}], "closed": true}"#)
        else { Issue.record("a closed two point path was accepted"); return }
    }

    @Test("A text call carries its words, place and type")
    func textCall() throws {
        let request = try Self.request("add_text", #"""
            {"text": "Hello", "x": 5, "y": 6, "fontSize": 40, "weight": "bold", "color": "#112233", "alignment": "center"}
            """#).get()
        guard case .addText(nil, let text) = request else { Issue.record("\(request)"); return }
        #expect(text.origin == CGPoint(x: 5, y: 6))
        #expect(text.content.string == "Hello")
        #expect(text.content.fontSize == 40)
        #expect(text.content.weight == .bold)
        #expect(text.content.colorHex == "#112233")
        #expect(text.content.alignment == .center)
        #expect(text.shadow, "words keep the Text tool's legibility shadow unless told")
        let plain = try Self.request("add_text", #"{"text": "Hi", "x": 0, "y": 0, "shadow": false}"#).get()
        guard case .addText(nil, let bare) = plain else { Issue.record("\(plain)"); return }
        #expect(!bare.shadow)
        guard case .failure = try Self.request("add_text", #"{"text": "  ", "x": 0, "y": 0}"#)
        else { Issue.record("empty words were accepted"); return }
    }

    @Test("set_layer needs something to change, and removeShadow means none")
    func setLayerCall() throws {
        guard case .failure(let nothing) = try Self.request("set_layer", #"{"layer": "x"}"#)
        else { Issue.record("a change of nothing was accepted"); return }
        #expect(nothing.message.contains("say what to change"))
        let request = try Self.request("set_layer", #"{"layer": "x", "removeShadow": true, "opacity": 0.5}"#).get()
        guard case .setLayer(nil, "x", let change) = request else { Issue.record("\(request)"); return }
        #expect(change.look.shadow == AgentShadow.none)
        #expect(change.look.opacity == 0.5)
    }

    @Test("A measurement call says which kind and what it measures")
    func measurementCall() throws {
        let size = try Self.request("add_measurement", #"{"kind": "size", "box": {"x": 1, "y": 2, "width": 3, "height": 4}}"#).get()
        #expect(size == .addMeasurement(document: nil, measurement: .size(CGRect(x: 1, y: 2, width: 3, height: 4))))
        let click = try Self.request("add_measurement", #"{"kind": "size", "at": {"x": 7, "y": 8}, "level": 1}"#).get()
        #expect(click == .addMeasurement(document: nil, measurement: .sizeAt(CGPoint(x: 7, y: 8), level: 1)))
        let distance = try Self.request("add_measurement", #"{"kind": "distance", "from": {"x": 0, "y": 0}, "to": {"x": 3, "y": 40}}"#).get()
        #expect(distance == .addMeasurement(document: nil, measurement: .distance(
            from: .zero, to: CGPoint(x: 3, y: 40), axis: .vertical)))
        guard case .failure = try Self.request("add_measurement", #"{"kind": "gap", "boxes": [{"x": 0, "y": 0, "width": 1, "height": 1}]}"#)
        else { Issue.record("a gap of one box was accepted"); return }
    }

    @Test("export needs an absolute path that ends in its format")
    func exportCall() throws {
        let request = try Self.request("export", #"{"format": "svg", "path": "/tmp/icon.svg"}"#).get()
        #expect(request == .export(document: nil, format: .svg, path: "/tmp/icon.svg", scale: 1, background: true))
        guard case .failure = try Self.request("export", #"{"format": "svg", "path": "icon.svg"}"#)
        else { Issue.record("a relative path was accepted"); return }
        guard case .failure = try Self.request("export", #"{"format": "png", "path": "/tmp/icon.svg"}"#)
        else { Issue.record("a PNG to a .svg was accepted"); return }
    }

    // MARK: The layers they become

    @Test("A rectangle becomes the shape tool's box, filled, in exactly the frame asked for")
    func rectangleLayer() {
        let layer = AgentDrawing.layer(for: AgentShape(
            kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 100, height: 50),
            look: AgentLook(fill: .hex("#FF0000"), cornerRadius: 8)))
        #expect(layer.frame == CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(layer.annotation?.shape == .rectangle)
        #expect(layer.annotation?.fill?.hex == "#FF0000")
        #expect(layer.annotation?.cornerRadii == CornerRadii(8))
        #expect(layer.style.borderWidth == 0, "a box with only a fill has no edge")
    }

    @Test("A box given a line wears it as a Border, as one drawn by hand does")
    func rectangleEdge() {
        let layer = AgentDrawing.layer(for: AgentShape(
            kind: .ellipse, frame: CGRect(x: 0, y: 0, width: 40, height: 40),
            look: AgentLook(stroke: .hex("#00FF00"), strokeWidth: 3)))
        #expect(layer.style.borderWidth == 3)
        #expect(layer.style.borderColorHex.uppercased().hasPrefix("#00FF00"))
        #expect(layer.annotation?.fill == nil, "an outline asked for is not filled")
    }

    @Test("An arrow runs from its tail to its head")
    func arrowLayer() {
        let layer = AgentDrawing.layer(for: AgentShape(kind: .arrow, from: CGPoint(x: 10, y: 10),
                                                       to: CGPoint(x: 110, y: 60)))
        guard let arrow = layer.annotation else { Issue.record("not an arrow"); return }
        let tail = CGPoint(x: layer.frame.minX + arrow.start.x, y: layer.frame.minY + arrow.start.y)
        let head = CGPoint(x: layer.frame.minX + arrow.end.x, y: layer.frame.minY + arrow.end.y)
        #expect(tail == CGPoint(x: 10, y: 10))
        #expect(head == CGPoint(x: 110, y: 60))
    }

    @Test("A path is boxed round its points, and a smooth point gets handles along its neighbours")
    func pathLayer() {
        let path = AgentPath(points: [AgentPathPoint(CGPoint(x: 10, y: 50)),
                                      AgentPathPoint(CGPoint(x: 60, y: 10), smooth: true),
                                      AgentPathPoint(CGPoint(x: 110, y: 50))],
                             closed: true, look: AgentLook(fill: .hex("#336699")))
        let anchors = AgentDrawing.anchors(for: path)
        #expect(anchors[0].handleOut == nil)
        #expect(anchors[1].kind == .smooth)
        #expect(anchors[1].handleOut == CGPoint(x: 100.0 / 6, y: 0))
        #expect(anchors[1].handleIn == CGPoint(x: -100.0 / 6, y: 0))
        let layer = AgentDrawing.layer(for: path)
        #expect(layer.path?.isClosed == true)
        #expect(layer.path?.fill?.hex == "#336699")
        #expect(layer.path?.strokeWidth == 0)
        #expect(layer.frame.minX == 10)
        #expect(layer.frame.maxX == 110)
        #expect(layer.frame.maxY == 50)
    }

    @Test("set_layer moves a layer without resizing it, and resizes when told a size")
    func setLayerFrame() throws {
        let box = AgentDrawing.layer(for: AgentShape(kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 40, height: 20)))
        let moved = try AgentDrawing.applying(AgentLayerChange(x: 100), to: box, canvas: nil).get()
        #expect(moved.frame == CGRect(x: 100, y: 10, width: 40, height: 20))
        let sized = try AgentDrawing.applying(AgentLayerChange(width: 80, height: 60), to: box, canvas: nil).get()
        #expect(sized.frame == CGRect(x: 10, y: 10, width: 80, height: 60))
    }

    @Test("set_layer paints a box's inside and edge, and takes a shadow off")
    func setLayerLook() throws {
        var box = AgentDrawing.layer(for: AgentShape(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 40, height: 20)))
        box.style.shadow = ShadowStyle()
        let changed = try AgentDrawing.applying(
            AgentLayerChange(look: AgentLook(fill: .hex("#123456"), stroke: .hex("#FFFFFF"), strokeWidth: 2,
                                             opacity: 0.5, shadow: AgentShadow.none)),
            to: box, canvas: nil).get()
        #expect(changed.annotation?.fill?.hex == "#123456")
        #expect(changed.style.borderWidth == 2)
        #expect(changed.style.opacity == 0.5)
        #expect(changed.style.shadows.isEmpty)
        let noFill = try AgentDrawing.applying(AgentLayerChange(look: AgentLook(fill: AgentInk.none)), to: changed, canvas: nil).get()
        #expect(noFill.annotation?.fill == nil)
    }

    @Test("set_layer refuses what the layer cannot take, in words")
    func setLayerRefuses() {
        let line = AgentDrawing.layer(for: AgentShape(kind: .line, from: .zero, to: CGPoint(x: 10, y: 0)))
        guard case .failure(let error) = AgentDrawing.applying(AgentLayerChange(look: AgentLook(fill: .hex("#000000"))),
                                                               to: line, canvas: nil)
        else { Issue.record("a line took a fill"); return }
        #expect(error.message.contains("no inside"))
        guard case .failure = AgentDrawing.applying(AgentLayerChange(text: "hi"), to: line, canvas: nil)
        else { Issue.record("a line took words"); return }
    }

    // MARK: Measuring

    @Test("The gap between two boxes is measured across where they face")
    func gapBetweenBoxes() {
        let side = AgentMeasurePlan.gap(between: CGRect(x: 0, y: 0, width: 50, height: 40),
                                        and: CGRect(x: 70, y: 10, width: 50, height: 40))
        #expect(side == GapMeasurement(axis: .horizontal, start: CGPoint(x: 50, y: 25), end: CGPoint(x: 70, y: 25)))
        let stacked = AgentMeasurePlan.gap(between: CGRect(x: 0, y: 100, width: 50, height: 40),
                                           and: CGRect(x: 0, y: 0, width: 50, height: 80))
        #expect(stacked == GapMeasurement(axis: .vertical, start: CGPoint(x: 25, y: 80), end: CGPoint(x: 25, y: 100)))
        #expect(AgentMeasurePlan.gap(between: CGRect(x: 0, y: 0, width: 50, height: 50),
                                     and: CGRect(x: 20, y: 20, width: 50, height: 50)) == nil, "overlapping")
        #expect(AgentMeasurePlan.gap(between: CGRect(x: 0, y: 0, width: 10, height: 10),
                                     and: CGRect(x: 50, y: 50, width: 10, height: 10)) == nil, "corner to corner")
    }

    @Test("A box on a painted button lands all four sides on its edges; one off to the side lands none")
    func sidesOnEdges() {
        var scene = PaintedCapture(w: 400, h: 300)
        scene.box(CGRect(x: 100, y: 100, width: 120, height: 60), border: 60)
        let edges = scene.map
        #expect(AgentMeasurePlan.sidesOnEdges(CGRect(x: 100, y: 100, width: 120, height: 60), in: edges) == 4)
        #expect(AgentMeasurePlan.sidesOnEdges(CGRect(x: 130, y: 115, width: 60, height: 20), in: edges) == 0)
        #expect(AgentMeasurePlan.feetOnEdges(from: CGPoint(x: 100, y: 130), to: CGPoint(x: 220, y: 130),
                                             axis: .horizontal, in: edges) == 2)
    }

    @Test("A Size placed by an agent steers round the same neighbours a click's does: the picture's and the drawn ones")
    func sizeNeighbours() {
        // Settings rows stacked in a card, as in ElementBoundsTests, and a
        // box drawn beside the card.
        var scene = PaintedCapture(w: 800, h: 400)
        scene.box(CGRect(x: 40, y: 40, width: 620, height: 264), border: 200, width: 1)
        scene.rule(y: 128, x0: 70, x1: 630, tone: 220)
        scene.rule(y: 216, x0: 70, x1: 630, tone: 220)
        let drawn = AgentDrawing.layer(for: AgentShape(kind: .rectangle, frame: CGRect(x: 680, y: 140, width: 60, height: 60)))
        let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 400), layers: [drawn])
        let found = AgentMeasurePlan.sizeNeighbors(of: CGRect(x: 70, y: 128, width: 560, height: 88),
                                                   style: MeasureContent(), edges: scene.map, luma: scene.luma,
                                                   document: document)
        #expect(found.contains { abs($0.minY - 216) <= 4 }, "the row below: \(found)")
        #expect(found.contains(CGRect(x: 680, y: 140, width: 60, height: 60)), "the drawn box beside: \(found)")
    }

    @Test("find_elements reads both buttons out of a painted card")
    func findsElements() {
        var scene = PaintedCapture(w: 600, h: 400)
        scene.box(CGRect(x: 20, y: 20, width: 560, height: 360), border: 120)
        scene.box(CGRect(x: 100, y: 150, width: 120, height: 60), border: 60)
        scene.box(CGRect(x: 300, y: 150, width: 120, height: 60), border: 60)
        let document = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400), layers: [])
        let found = AgentElementScan.elements(in: document, edges: scene.map, luma: scene.luma, across: 8)
        for button in [CGRect(x: 100, y: 150, width: 120, height: 60), CGRect(x: 300, y: 150, width: 120, height: 60)] {
            #expect(found.contains { abs($0.minX - button.minX) <= 3 && abs($0.minY - button.minY) <= 3
                && abs($0.width - button.width) <= 6 && abs($0.height - button.height) <= 6 },
                    "missed \(button) in \(found)")
        }
        let areas = found.map { $0.width * $0.height }
        #expect(areas == areas.sorted(by: >), "largest first")
    }

    @Test("find_elements lists the boxes a blank canvas has drawn on it")
    func findsDrawnLayers() {
        let box = AgentDrawing.layer(for: AgentShape(kind: .rectangle, frame: CGRect(x: 40, y: 40, width: 100, height: 80)))
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [box])
        let found = AgentElementScan.elements(in: document, edges: .empty, luma: .empty)
        #expect(found == [CGRect(x: 40, y: 40, width: 100, height: 80)])
    }
}
