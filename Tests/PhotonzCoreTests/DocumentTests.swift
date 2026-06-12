import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Document")
struct DocumentTests {

    private func makeDocument() -> PhotonzDocument {
        let ref = ImageRef(pixelSize: CGSize(width: 800, height: 600))
        return PhotonzDocument.withBaseImage(ref)
    }

    @Test func baseImageBecomesBackgroundLayer() {
        let doc = makeDocument()
        #expect(doc.canvasSize == CGSize(width: 800, height: 600))
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].name == "Background")
        #expect(doc.layers[0].frame == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func addRemoveAndReorderLayers() {
        var doc = makeDocument()
        let text = Layer(name: "Title", content: .text(TextContent(string: "Hello")),
                         frame: CGRect(x: 10, y: 10, width: 200, height: 50))
        let arrow = Layer(name: "Arrow", content: .annotation(AnnotationContent(shape: .arrow)),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        doc.addLayer(text)
        doc.addLayer(arrow)
        #expect(doc.layers.map(\.name) == ["Background", "Title", "Arrow"])

        doc.moveLayer(id: arrow.id, to: 1)
        #expect(doc.layers.map(\.name) == ["Background", "Arrow", "Title"])

        doc.removeLayer(id: text.id)
        #expect(doc.layers.map(\.name) == ["Background", "Arrow"])
    }

    @Test func updateLayerMutatesInPlace() {
        var doc = makeDocument()
        let id = doc.layers[0].id
        doc.updateLayer(id: id) { $0.style.opacity = 0.5; $0.style.blurRadius = 8 }
        #expect(doc.layers[0].style.opacity == 0.5)
        #expect(doc.layers[0].style.blurRadius == 8)
    }

    @Test func promoteRegionToLayerClampsAndStacksOnTop() {
        var doc = makeDocument()
        let ref = ImageRef(pixelSize: CGSize(width: 300, height: 300))
        let layer = doc.promoteRegionToLayer(region: CGRect(x: 700, y: 500, width: 300, height: 300),
                                             rasterized: ref)
        #expect(doc.layers.last?.id == layer.id)
        // Region extends past the 800x600 canvas; frame must be clamped.
        #expect(layer.frame == CGRect(x: 700, y: 500, width: 100, height: 100))
    }

    @Test func cropRebasesLayerFramesAndDropsOutsiders() {
        var doc = makeDocument()
        let inside = Layer(name: "Inside", content: .text(TextContent(string: "a")),
                           frame: CGRect(x: 400, y: 300, width: 50, height: 50))
        let outside = Layer(name: "Outside", content: .text(TextContent(string: "b")),
                            frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        doc.addLayer(inside)
        doc.addLayer(outside)

        doc.crop(to: CGRect(x: 300, y: 200, width: 400, height: 300))

        #expect(doc.canvasSize == CGSize(width: 400, height: 300))
        #expect(doc.layers.map(\.name) == ["Background", "Inside"])
        #expect(doc.layer(id: inside.id)?.frame == CGRect(x: 100, y: 100, width: 50, height: 50))
        #expect(doc.layers[0].frame.origin == CGPoint(x: -300, y: -200))
    }

    @Test func resizeScalesAllLayerFrames() {
        var doc = makeDocument()
        doc.resize(to: CGSize(width: 400, height: 300))
        #expect(doc.canvasSize == CGSize(width: 400, height: 300))
        #expect(doc.layers[0].frame == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func documentRoundTripsThroughJSON() throws {
        var doc = makeDocument()
        doc.addLayer(Layer(name: "Note",
                           content: .text(TextContent(string: "hi", fontName: "Menlo", fontSize: 13, colorHex: "#00FF00")),
                           frame: CGRect(x: 5, y: 5, width: 80, height: 20),
                           style: LayerStyle(opacity: 0.8, blurRadius: 2, cornerRadius: 6,
                                             borderWidth: 1, borderColorHex: "#FFFFFF",
                                             shadow: ShadowStyle())))
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(decoded == doc)
    }
}
