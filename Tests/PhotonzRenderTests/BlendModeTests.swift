import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Blend modes")
struct BlendModeTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Reads the RGBA value at (x, y) in top-left coordinates.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    /// Gray-on-gray 20x20 doc: base value `base`, full-cover layer value `layer`.
    private func renderBlend(_ mode: BlendMode, base: UInt8, layer: UInt8) -> CGImage {
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 20, height: 20, r: base, g: base, b: base))
        let topRef = store.register(solidImage(width: 20, height: 20, r: layer, g: layer, b: layer))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        doc.addLayer(Layer(name: "Top", content: .image(topRef),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(blendMode: mode)))
        return DocumentRenderer().render(doc, store: store)!
    }

    @Test func defaultBlendModeIsNormal() {
        #expect(LayerStyle().blendMode == .normal)
    }

    @Test func blendModeRoundTripsThroughCodable() throws {
        let style = LayerStyle(blendMode: .screen)
        let data = try JSONEncoder().encode(style)
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back.blendMode == .screen)
    }

    @Test func normalBlendCoversBackdrop() {
        let p = pixel(renderBlend(.normal, base: 64, layer: 128), x: 10, y: 10)
        #expect(p.r > 115 && p.r < 145, "opaque normal blend should read the layer value, got \(p.r)")
    }

    @Test func multiplyBlendDarkens() {
        let p = pixel(renderBlend(.multiply, base: 128, layer: 128), x: 10, y: 10)
        #expect(p.r > 45 && p.r < 85, "mid-gray multiplied by mid-gray should darken, got \(p.r)")
    }

    @Test func screenBlendLightens() {
        let p = pixel(renderBlend(.screen, base: 128, layer: 128), x: 10, y: 10)
        #expect(p.r > 150 && p.r < 215, "mid-gray screened with mid-gray should lighten, got \(p.r)")
        #expect(p.r < 250, "screen of mid-grays is not white")
    }

    @Test func blendOnlyAffectsLayerExtent() {
        // A half-canvas multiply layer leaves the uncovered half untouched.
        let store = ImageStore()
        let baseRef = store.register(solidImage(width: 40, height: 20, r: 128, g: 128, b: 128))
        let topRef = store.register(solidImage(width: 20, height: 20, r: 128, g: 128, b: 128))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        doc.addLayer(Layer(name: "Half", content: .image(topRef),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(blendMode: .multiply)))
        let output = DocumentRenderer().render(doc, store: store)!
        let covered = pixel(output, x: 10, y: 10)
        let uncovered = pixel(output, x: 30, y: 10)
        #expect(covered.r < 90, "covered half darkens")
        #expect(uncovered.r > 115 && uncovered.r < 145, "uncovered half keeps the base value")
    }
}
