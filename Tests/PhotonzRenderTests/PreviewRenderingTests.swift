import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Drag-preview pieces: the underlay (composite minus the dragged layer) and
/// the sprite (the dragged layer rendered alone, padded for shadow/blur).
@Suite("Preview rendering")
struct PreviewRenderingTests {
    let renderer = DocumentRenderer()
    let store = ImageStore()

    private func solidImage(_ rgba: (CGFloat, CGFloat, CGFloat, CGFloat), size: CGSize) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3))
        ctx.fill(CGRect(origin: .zero, size: size))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return (data[0], data[1], data[2], data[3])
    }

    /// Blue 100×100 base + red 40×40 layer at (10,10).
    private func makeDocument() -> (PhotonzDocument, UUID) {
        let baseRef = store.register(solidImage((0, 0, 1, 1), size: CGSize(width: 100, height: 100)))
        var doc = PhotonzDocument.withBaseImage(baseRef)
        let redRef = store.register(solidImage((1, 0, 0, 1), size: CGSize(width: 40, height: 40)))
        let red = Layer(name: "red", content: .image(redRef),
                        frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        doc.addLayer(red)
        return (doc, red.id)
    }

    @Test func underlayHidesExactlyTheDraggedLayer() throws {
        let (doc, redID) = makeDocument()
        let underlay = try #require(renderer.render(doc, store: store, hiding: redID))
        // Where the red layer was, the blue base shows through.
        let p = pixel(underlay, x: 30, y: 30)
        #expect(p.r < 30 && p.b > 220)
        // The committed composite still has it.
        let full = try #require(renderer.render(doc, store: store))
        #expect(pixel(full, x: 30, y: 30).r > 220)
    }

    @Test func spriteRendersTheLayerAloneAtFrameSizePlusPadding() throws {
        let (doc, redID) = makeDocument()
        let sprite = try #require(renderer.renderSprite(for: redID, in: doc, store: store, padding: 10))
        #expect(sprite.width == 60 && sprite.height == 60) // 40 + 2×10
        // Center is the red content; the padding ring is transparent (no base layer).
        #expect(pixel(sprite, x: 30, y: 30).r > 220)
        #expect(pixel(sprite, x: 3, y: 3).a == 0)
    }

    @Test func spritePaddingKeepsTheShadowUnclipped() throws {
        var (doc, redID) = makeDocument()
        doc.updateLayer(id: redID) {
            $0.style.shadow = ShadowStyle(radius: 4, offset: CGSize(width: 6, height: 6),
                                          colorHex: "#000000", opacity: 1)
        }
        let padding = doc.layer(id: redID)!.style.previewPadding
        #expect(padding >= 18) // 4×3 + 6
        let sprite = try #require(renderer.renderSprite(for: redID, in: doc, store: store, padding: padding))
        // Just outside the bottom-right of the content, inside the padding:
        // the shadow lands there (non-zero alpha).
        let contentMax = Int(padding) + 40
        let p = pixel(sprite, x: contentMax + 3, y: contentMax + 3)
        #expect(p.a > 20)
    }

    @Test func previewPaddingIsZeroForPlainLayers() {
        #expect(LayerStyle().previewPadding == 0)
    }

    @Test func previewPaddingCoversBlur() {
        let style = LayerStyle(blurRadius: 5)
        #expect(style.previewPadding >= 15)
    }
}
