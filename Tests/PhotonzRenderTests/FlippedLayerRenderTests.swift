import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// A flipped layer is drawn as its mirror image on the canvas, and the
/// exported SVG draws exactly what the canvas does (`LayerFlip.swift`).
@Suite("A flipped layer draws mirrored everywhere")
struct FlippedLayerRenderTests {

    static let canvas = CGSize(width: 120, height: 80)

    /// Red on the left third, blue on the rest: a picture whose left and
    /// right cannot be confused.
    static func lopsided(_ width: Int, _ height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context?.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        // Bottom-left in CG is the TOP-left of the picture: a corner, so a
        // flip either way moves it.
        context?.fill(CGRect(x: 0, y: height / 2, width: width / 3, height: height / 2))
        return context?.makeImage()
    }

    static func document(store: ImageStore) throws -> (PhotonzDocument, UUID) {
        let image = try #require(lopsided(Int(canvas.width), Int(canvas.height)))
        let layer = Layer(name: "Photo", content: .image(store.register(image)),
                          frame: CGRect(origin: .zero, size: canvas))
        return (PhotonzDocument(canvasSize: canvas, layers: [layer]), layer.id)
    }

    /// Straight RGBA bytes of a render, top row first.
    static func bytes(_ image: CGImage) -> [UInt8] {
        SVGExportRenderTests.pixels(of: image, size: canvas)
    }

    static func mirrored(_ bytes: [UInt8], _ axis: FlipAxis) -> [UInt8] {
        let width = Int(canvas.width), height = Int(canvas.height)
        var out = bytes
        for y in 0..<height {
            for x in 0..<width {
                let from = axis == .horizontal ? (y * width + (width - 1 - x)) : ((height - 1 - y) * width + x)
                for c in 0..<4 { out[(y * width + x) * 4 + c] = bytes[from * 4 + c] }
            }
        }
        return out
    }

    @Test(arguments: FlipAxis.allCases)
    func theCanvasDrawsTheMirrorImage(axis: FlipAxis) throws {
        let store = ImageStore()
        var (document, id) = try Self.document(store: store)
        let renderer = DocumentRenderer()
        let before = try #require(renderer.render(document, store: store))
        document.flip(ids: [id], axis)
        let after = try #require(renderer.render(document, store: store))
        let difference = SVGExportRenderTests.meanDifference(
            between: Self.mirrored(Self.bytes(before), axis), and: Self.bytes(after))
        #expect(difference < 1, "the flipped render is \(difference) off the mirrored one")
        // And it really changed: the picture is not its own mirror.
        let unchanged = SVGExportRenderTests.meanDifference(between: Self.bytes(before), and: Self.bytes(after))
        #expect(unchanged > 20)
    }

    @Test func theExportedSVGDrawsWhatTheCanvasDraws() throws {
        let store = ImageStore()
        var (document, id) = try Self.document(store: store)
        document.flip(ids: [id], .horizontal)
        document.flip(ids: [id], .vertical)
        try SVGExportRenderTests.expectTheSamePicture(of: document, name: "flipped-photo", store: store)
    }

    @Test func flippedWordsAndAnArrowComeBackTheSameInTheSVG() throws {
        let arrow = AnnotationContent(shape: .arrow, strokeWidth: 5, colorHex: "#FF3B30")
        var words = TextContent(string: "Flip")
        words.fontSize = 28
        words.colorHex = "#102030"
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            AnnotationBuilder.layer(content: arrow, from: CGPoint(x: 10, y: 70), to: CGPoint(x: 100, y: 15)),
            Layer(name: "Words", content: .text(words), frame: CGRect(x: 20, y: 20, width: 70, height: 36)),
        ])
        let ids = Set(document.layers.map(\.id))
        document.flip(ids: ids, .horizontal)
        try SVGExportRenderTests.expectTheSamePicture(of: document, name: "flipped-arrow")
    }
}
