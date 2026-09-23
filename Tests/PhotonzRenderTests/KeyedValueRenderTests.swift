import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A value keyed with the diamond reaches the pixels, and moves between its
/// keys (task `every-value-in-the-panel-has-a-key-diamond`).
///
/// Keys are worked out when the document is DRAWN at a moment
/// (`PhotonzDocument.drawn(atTimeMS:)`), and nothing is ever baked in, so this
/// renders the same document at three moments and reads the ink back.
@Suite("A keyed value moves in the picture")
struct KeyedValueRenderTests {

    private func ink(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Top-left origin in the document, bottom-left in the bitmap context's
        // memory is flipped back by reading row (height - 1 - y).
        let row = height - 1 - Int(point.y)
        let index = (row * width + Int(point.x)) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// A red square keyed to slide from the left edge at 1s to the right edge
    /// at 3s, over black, in a four second document.
    private func sliding() -> (PhotonzDocument, UUID) {
        let canvas = CGSize(width: 200, height: 100)
        let ground = Layer(name: "Ground",
                           content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                  colorHex: "#000000",
                                                                  start: .zero, end: CGPoint(x: 200, y: 100),
                                                                  fillColorHex: "#000000")),
                           frame: CGRect(origin: .zero, size: canvas))
        var square = Layer(name: "Square",
                           content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                  colorHex: "#FF0000",
                                                                  start: .zero, end: CGPoint(x: 40, y: 40),
                                                                  fillColorHex: "#FF0000")),
                           frame: CGRect(x: 0, y: 30, width: 40, height: 40))
        square.time = LayerTime(inMS: 0, outMS: 4000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [ground, square])
        document.durationMS = 4000
        let id = square.id
        document.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        document.setKeyedValue(.point(CGPoint(x: 160, y: 30)), layerID: id,
                               .motion(.position), atDocumentTimeMS: 3000)
        return (document, id)
    }

    private func render(_ document: PhotonzDocument, atMS ms: Int) -> CGImage? {
        DocumentRenderer().render(document.drawn(atTimeMS: ms), store: ImageStore(), scale: 1)
    }

    @Test func theSquareIsWhereItsKeysPutIt() throws {
        let (document, _) = sliding()
        let early = try #require(render(document, atMS: 500))
        let late = try #require(render(document, atMS: 3500))
        // Before the first key it holds on the left; after the last, the right.
        #expect(ink(early, at: CGPoint(x: 20, y: 50)).r > 200)
        #expect(ink(early, at: CGPoint(x: 180, y: 50)).r < 40)
        #expect(ink(late, at: CGPoint(x: 180, y: 50)).r > 200)
        #expect(ink(late, at: CGPoint(x: 20, y: 50)).r < 40)
    }

    @Test func betweenTheKeysItIsOnItsWay() throws {
        let (document, _) = sliding()
        let middle = try #require(render(document, atMS: 2000))
        // Half way through the time, on the way and at neither end. Well past
        // half way through the distance, because a new key runs on the
        // design language's ease in out, which leaves quickly and settles
        // slowly (0.4, 0, 0.2, 1): about 78% of the way at half the time.
        #expect(ink(middle, at: CGPoint(x: 140, y: 50)).r > 200)
        #expect(ink(middle, at: CGPoint(x: 10, y: 50)).r < 40)
        #expect(ink(middle, at: CGPoint(x: 190, y: 50)).r < 40)
    }

    @Test func nothingIsBakedIn() {
        let (document, id) = sliding()
        _ = render(document, atMS: 2000)
        #expect(document.layer(id: id)?.frame.origin == CGPoint(x: 0, y: 30))
    }
}
