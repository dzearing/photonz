import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Layer clipboard")
struct ClipboardTests {

    @Test func transferRoundTripsThroughJSON() throws {
        var layer = Layer(name: "Note", content: .text(TextContent(string: "hi")),
                          frame: CGRect(x: 5, y: 5, width: 80, height: 20))
        layer.style.shadow = ShadowStyle()
        let transfer = LayerTransfer(layer: layer, imageData: Data([1, 2, 3]))
        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(LayerTransfer.self, from: data)
        #expect(decoded.layer == layer)
        #expect(decoded.imageData == Data([1, 2, 3]))
    }

    @Test func smallPastedImageLandsCenteredAtFullSize() {
        let frame = PastePlacement.frame(forImageOf: CGSize(width: 200, height: 100),
                                         canvas: CGSize(width: 800, height: 600))
        #expect(frame == CGRect(x: 300, y: 250, width: 200, height: 100))
    }

    @Test func oversizedPastedImageAspectFitsTheCanvas() {
        let frame = PastePlacement.frame(forImageOf: CGSize(width: 1600, height: 600),
                                         canvas: CGSize(width: 800, height: 600))
        // Scale 0.5 → 800×300, centered vertically.
        #expect(frame == CGRect(x: 0, y: 150, width: 800, height: 300))
    }

    @Test func degenerateImageSizeFallsBackToCanvasCenter() {
        let frame = PastePlacement.frame(forImageOf: .zero,
                                         canvas: CGSize(width: 800, height: 600))
        #expect(frame.isEmpty)
        #expect(frame.origin == CGPoint(x: 400, y: 300))
    }
}
