import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Skew & distort draws the picture on its reshaped corners, non-destructively,
/// and the flat turn acts on the reshaped picture (`LayerReshape.swift`).
@Suite("Reshape rendering")
struct ReshapeRenderingTests {

    private func solid(_ width: Int, _ height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let o = (y * w + x) * 4
        return (data[o], data[o + 1], data[o + 2])
    }

    /// A blue 40 by 40 patch at (30, 30) on a red 100 by 100 base.
    private func render(reshape: LayerReshape?, transform: LayerTransform = .identity) -> CGImage {
        let store = ImageStore()
        let base = store.register(solid(100, 100, r: 255, g: 0, b: 0))
        let patch = store.register(solid(40, 40, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        var layer = Layer(name: "Patch", content: .image(patch),
                          frame: CGRect(x: 30, y: 30, width: 40, height: 40), transform: transform)
        layer.reshape = reshape
        doc.addLayer(layer)
        return DocumentRenderer().render(doc, store: store)!
    }

    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 }
    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.b < 60 }

    @Test("A corner pulled out draws the picture out to it")
    func distortReachesTheCorner() {
        // The bottom right corner pulled 20 right and 20 down: (90, 90).
        let out = render(reshape: LayerReshape(offsets: [.zero, .zero, CGPoint(x: 0.5, y: 0.5), .zero]))
        #expect(isBlue(pixel(out, 84, 84)), "the pulled corner is covered")
        #expect(isBlue(pixel(out, 35, 35)), "the corner left alone stays")
        // Outside the new edge from the top right (70, 30) to (90, 90).
        #expect(isRed(pixel(out, 85, 40)))
        // The unreshaped layer leaves (84, 84) red.
        #expect(isRed(pixel(render(reshape: nil), 84, 84)))
    }

    @Test("A skew slides the top edge along itself and leaves the bottom")
    func skewSlidesTheTop() {
        // The top edge slid 20 right: (50, 30) to (90, 30), bottom stays (30..70, 70).
        let out = render(reshape: LayerReshape(offsets: [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 0), .zero, .zero]))
        #expect(isBlue(pixel(out, 85, 33)), "the top now reaches past the box")
        #expect(isRed(pixel(out, 33, 33)), "the top left of the box is left bare")
        #expect(isBlue(pixel(out, 33, 67)), "the bottom left stays")
    }

    @Test("The flat turn acts on the reshaped picture, about the box's middle")
    func turnActsOnTheReshape() {
        // Bottom right pulled to (90, 90), then a half turn about (50, 50) puts
        // it at (10, 10).
        let out = render(reshape: LayerReshape(offsets: [.zero, .zero, CGPoint(x: 0.5, y: 0.5), .zero]),
                         transform: LayerTransform(rotation: .pi))
        #expect(isBlue(pixel(out, 16, 16)))
        #expect(isRed(pixel(out, 84, 84)))
    }
}
