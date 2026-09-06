import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A frame draws as a screen: it paints its surface, everything inside lands on
/// it, and what hangs off the edge is cut away. A document with no frames in it
/// draws exactly as it always did.
@Suite("Frame rendering")
struct FrameRenderingTests {

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

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private let canvas = CGSize(width: 200, height: 200)

    /// A grey 200×200 base, so a frame's white surface reads against it.
    private func document(_ store: ImageStore, _ layers: [Layer]) -> PhotonzDocument {
        let base = store.register(solidImage(width: 200, height: 200, r: 100, g: 100, b: 100))
        var doc = PhotonzDocument(canvasSize: canvas, layers: [
            Layer(name: "Base", content: .image(base),
                  frame: CGRect(origin: .zero, size: canvas), isLocked: true)
        ])
        for layer in layers { doc.addLayer(layer) }
        return doc
    }

    private func patch(_ store: ImageStore, _ name: String, _ frame: CGRect,
                       r: UInt8, g: UInt8, b: UInt8) -> Layer {
        let ref = store.register(solidImage(width: Int(frame.width), height: Int(frame.height),
                                            r: r, g: g, b: b))
        return Layer(name: name, content: .image(ref), frame: frame)
    }

    @Test func aFramePaintsItsSurface() {
        let store = ImageStore()
        let doc = document(store, [
            Layer.frameLayer(name: "Home", origin: CGPoint(x: 50, y: 50),
                             size: CGSize(width: 100, height: 100))
        ])
        let image = DocumentRenderer().render(doc, store: store)!
        // Inside the frame: white. Outside it: the grey canvas.
        #expect(pixel(image, x: 100, y: 100).r == 255)
        #expect(pixel(image, x: 20, y: 20).r == 100)
    }

    @Test func aFrameWithNoSurfaceLetsTheCanvasThrough() {
        let store = ImageStore()
        let doc = document(store, [
            Layer.frameLayer(name: "Home", origin: CGPoint(x: 50, y: 50),
                             size: CGSize(width: 100, height: 100), backgroundHex: nil)
        ])
        let image = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(image, x: 100, y: 100).r == 100)
    }

    @Test func whatHangsOffTheEdgeIsCutAway() {
        let store = ImageStore()
        let overhang = patch(store, "Overhang", CGRect(x: 80, y: 20, width: 60, height: 20),
                             r: 255, g: 0, b: 0)
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 50, y: 50),
                                     size: CGSize(width: 100, height: 100),
                                     children: [overhang])
        var doc = document(store, [frame])
        let clipped = DocumentRenderer().render(doc, store: store)!
        // (140, 75) is inside the frame and red; (160, 75) is past its edge.
        #expect(pixel(clipped, x: 140, y: 75).r > 200)
        #expect(pixel(clipped, x: 160, y: 75).r == 100)

        doc.setClipsContents(id: doc.frames[0].id, false)
        let open = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(open, x: 160, y: 75).r > 200)
        #expect(pixel(open, x: 160, y: 75).g < 60)
    }

    @Test func aFrameExportsItsContentsAndNothingElse() {
        let store = ImageStore()
        let inside = patch(store, "Button", CGRect(x: 10, y: 10, width: 20, height: 20),
                           r: 0, g: 0, b: 255)
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 50, y: 50),
                                     size: CGSize(width: 100, height: 100), children: [inside])
        let doc = document(store, [
            frame,
            patch(store, "Outside", CGRect(x: 0, y: 0, width: 40, height: 40), r: 255, g: 0, b: 0)
        ])
        let export = doc.frameDocument(id: doc.frames[0].id)!
        let image = DocumentRenderer().render(export, store: store)!
        #expect(image.width == 100)
        #expect(image.height == 100)
        // The frame's own surface and its button, no canvas and no red layer.
        #expect(pixel(image, x: 60, y: 60).r == 255)
        #expect(pixel(image, x: 20, y: 20).b > 200)
        #expect(pixel(image, x: 20, y: 20).r < 60)
    }

    @Test func framesSideBySideEachKeepTheirOwnContents() {
        let store = ImageStore()
        let red = patch(store, "Red", CGRect(x: 5, y: 5, width: 20, height: 20), r: 255, g: 0, b: 0)
        let blue = patch(store, "Blue", CGRect(x: 5, y: 5, width: 20, height: 20), r: 0, g: 0, b: 255)
        let doc = document(store, [
            Layer.frameLayer(name: "One", origin: CGPoint(x: 10, y: 10),
                             size: CGSize(width: 60, height: 60), children: [red]),
            Layer.frameLayer(name: "Two", origin: CGPoint(x: 110, y: 10),
                             size: CGSize(width: 60, height: 60), children: [blue]),
        ])
        let image = DocumentRenderer().render(doc, store: store)!
        #expect(pixel(image, x: 20, y: 20).r > 200)
        #expect(pixel(image, x: 120, y: 20).b > 200)
        // The gap between them is still the canvas.
        #expect(pixel(image, x: 90, y: 20).r == 100)
    }

    @Test func aFrameHasARoundedCornerWhenItIsGivenOne() {
        let store = ImageStore()
        var style = LayerStyle()
        style.cornerRadius = 20
        var frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 50, y: 50),
                                     size: CGSize(width: 100, height: 100))
        frame.style = style
        let doc = document(store, [frame])
        let image = DocumentRenderer().render(doc, store: store)!
        // The very corner is cut away; the middle of the edge is not.
        #expect(pixel(image, x: 52, y: 52).r == 100)
        #expect(pixel(image, x: 100, y: 52).r == 255)
    }
}
