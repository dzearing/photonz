import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("DocumentRenderer")
struct DocumentRendererTests {

    /// Builds a solid-color CGImage for pixel assertions.
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

    @Test func rendersBaseImageAtCanvasSize() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 64, height: 32, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(ref)
        let renderer = DocumentRenderer()

        let output = renderer.render(doc, store: store)
        #expect(output != nil)
        #expect(output?.width == 64)
        #expect(output?.height == 32)
        if let output {
            let p = pixel(output, x: 32, y: 16)
            #expect(p.r > 240 && p.g < 16 && p.b < 16 && p.a > 240)
        }
    }

    @Test func compositesTopLayerOverBase() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 50, height: 50, r: 0, g: 0, b: 255))

        var doc = PhotonzDocument.withBaseImage(base)
        // Blue patch in the top-left quadrant (model coords are top-left origin).
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 0, y: 0, width: 50, height: 50)))

        let output = DocumentRenderer().render(doc, store: store)!
        let topLeft = pixel(output, x: 10, y: 10)
        let bottomRight = pixel(output, x: 90, y: 90)
        #expect(topLeft.b > 240 && topLeft.r < 16)
        #expect(bottomRight.r > 240 && bottomRight.b < 16)
    }

    @Test func hiddenLayersAreSkipped() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 20, height: 20, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 20, height: 20, r: 0, g: 255, b: 0))

        var doc = PhotonzDocument.withBaseImage(base)
        var layer = Layer(name: "Hidden", content: .image(patch),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        layer.isVisible = false
        doc.addLayer(layer)

        let output = DocumentRenderer().render(doc, store: store)!
        let p = pixel(output, x: 10, y: 10)
        #expect(p.r > 240 && p.g < 16)
    }

    @Test func opacityBlendsLayerWithBackdrop() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 20, height: 20, r: 0, g: 0, b: 0))
        let patch = store.register(solidImage(width: 20, height: 20, r: 255, g: 255, b: 255))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Half", content: .image(patch),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                           style: LayerStyle(opacity: 0.5)))

        let output = DocumentRenderer().render(doc, store: store)!
        let p = pixel(output, x: 10, y: 10)
        // 50% white over black: mid-gray within sRGB blending tolerance.
        #expect(p.r > 100 && p.r < 200)
    }

    @Test func scalesLayerContentIntoFrame() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 10, height: 10, r: 0, g: 0, b: 255))

        var doc = PhotonzDocument.withBaseImage(base)
        // 10x10 content stretched to cover the whole canvas.
        doc.addLayer(Layer(name: "Stretched", content: .image(patch),
                           frame: CGRect(x: 0, y: 0, width: 100, height: 100)))

        let output = DocumentRenderer().render(doc, store: store)!
        let p = pixel(output, x: 95, y: 95)
        #expect(p.b > 240)
    }

    @Test func emptyDocumentRendersNil() {
        let renderer = DocumentRenderer()
        let doc = PhotonzDocument(canvasSize: .zero)
        #expect(renderer.render(doc, store: ImageStore()) == nil)
    }

    /// Two-tone CGImage: left half red, right half blue.
    private func twoToneImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    @Test func cropContentKeepsPixelsInPlaceOnCanvas() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 0, g: 255, b: 0))
        // Left half red, right half blue, placed 1:1 at (10, 10).
        let patch = store.register(twoToneImage(width: 40, height: 40))

        var doc = PhotonzDocument.withBaseImage(base)
        var layer = Layer(name: "Patch", content: .image(patch),
                          frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        // Keep only the blue right half.
        layer.cropContent(to: CGRect(x: 30, y: 10, width: 20, height: 40))
        doc.addLayer(layer)

        let output = DocumentRenderer().render(doc, store: store)!
        let kept = pixel(output, x: 40, y: 30)
        #expect(kept.b > 240, "kept pixels render where they were — got \(kept)")
        let dropped = pixel(output, x: 20, y: 30)
        #expect(dropped.g > 240 && dropped.r < 16,
                "cropped-away region shows the backdrop — got \(dropped)")
    }
}
