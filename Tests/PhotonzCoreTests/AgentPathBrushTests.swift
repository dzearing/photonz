import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A path's brushed line through the agent channel: add_path and set_layer
/// take a `brush`, checked against the medium's settings, and a brush on a
/// group restyles every path in it (`docs/design/brushes.md`, decision 9).
@Suite("The agent brushes a path's line")
struct AgentPathBrushTests {

    private static func args(_ json: String) throws -> AgentJSON { try AgentJSON.parse(Data(json.utf8)) }

    private func path(_ json: String) throws -> Layer {
        let request = try AgentTools.request(tool: "add_path", arguments: Self.args(json)).get()
        guard case .addPath(_, let path) = request else { throw AgentToolError("not add_path") }
        return AgentDrawing.layer(for: path)
    }

    @Test("add_path takes a medium by name and paints the line with it")
    func byName() throws {
        let layer = try path(#"{"points": [{"x": 10, "y": 10}, {"x": 200, "y": 80}], "brush": "charcoal", "strokeWidth": 14}"#)
        let content = try #require(layer.path)
        #expect(content.brush?.medium == .charcoal)
        #expect(content.strokeWidth == 14)
        #expect(content.brushStrokes.count == 1)
    }

    @Test("A brush with settings is checked against the medium, and its size is the line's thickness")
    func withSettings() throws {
        let layer = try path(#"{"points": [{"x": 0, "y": 0}, {"x": 90, "y": 40}], "brush": {"medium": "marker", "settings": {"flow": 30, "tip": "Chisel", "size": 22}}}"#)
        let content = try #require(layer.path)
        #expect(content.brush?.settings.value("flow") == 30)
        #expect(content.strokeWidth == 22)

        let refused = AgentTools.request(tool: "add_path", arguments: try Self.args(
            #"{"points": [{"x": 0, "y": 0}, {"x": 9, "y": 9}], "brush": {"medium": "marker", "settings": {"wetness": 40}}}"#))
        #expect(refused.failure?.message == "add_path: Marker has no setting called wetness; its settings are size, opacity, tip, flow.")
        let unknown = AgentTools.request(tool: "add_path", arguments: try Self.args(
            #"{"points": [{"x": 0, "y": 0}, {"x": 9, "y": 9}], "brush": "crayola"}"#))
        #expect(unknown.failure?.message.contains("brush should be plain or pencil") == true)
    }

    @Test("A closed path given only a brush gets a line to paint")
    func closedGetsALine() throws {
        let layer = try path(#"{"points": [{"x": 0, "y": 0}, {"x": 90, "y": 0}, {"x": 45, "y": 60}], "closed": true, "brush": "crayon"}"#)
        let content = try #require(layer.path)
        #expect(content.strokeWidth > 0)
        #expect(content.fill != nil)
        #expect(content.brush?.medium == .crayon)
    }

    @Test("set_layer swaps the brush on a group, every path in it, and plain takes it off")
    func groupSwap() throws {
        let a = PathBuilder.layer(PathContent(anchors: [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 40, y: 0))]), at: .zero)
        let b = PathBuilder.layer(PathContent(anchors: [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 0, y: 40))]), at: .zero)
        let group = Layer(name: "Drawing", content: .group(GroupContent(children: [a, b])), frame: .zero)
        func set(_ json: String, on layer: Layer) throws -> Layer {
            let request = try AgentTools.request(tool: "set_layer", arguments: Self.args(json)).get()
            guard case .setLayer(_, _, let change) = request else { throw AgentToolError("not set_layer") }
            return try AgentDrawing.applying(change, to: layer, canvas: nil).get()
        }
        let watercolour = try set(#"{"layer": "x", "brush": "watercolour"}"#, on: group)
        #expect(watercolour.group?.children.allSatisfy { $0.path?.brush?.medium == .watercolour } == true)
        let plain = try set(#"{"layer": "x", "brush": "plain"}"#, on: watercolour)
        #expect(plain.group?.children.allSatisfy { $0.path?.brush == nil } == true)

        let text = Layer(name: "Words", content: .text(TextContent(string: "Hi")), frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        let request = try AgentTools.request(tool: "set_layer", arguments: Self.args(#"{"layer": "x", "brush": "oil"}"#)).get()
        guard case .setLayer(_, _, let change) = request else { return }
        #expect(AgentDrawing.applying(change, to: text, canvas: nil).failure?.message.contains("not a path") == true)
    }

    @Test("read_document says which medium a brushed line is painted in")
    func reads() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 300, height: 200))
        document.layers.append(try path(#"{"points": [{"x": 10, "y": 10}, {"x": 200, "y": 80}], "brush": "pencil"}"#))
        let read = AgentDocumentRead.make(document, context: AgentDocumentRead.Context(
            id: "d1", title: "T", file: nil, playheadMS: 0, canUndo: false, canRedo: false))
        #expect(read.layers.first?.path?.brush == "pencil")
    }
}
