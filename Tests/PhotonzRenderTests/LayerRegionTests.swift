import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The picked layer's pixels inside a marquee — the one piece of picture that
/// both ⌘C ("copy takes the layer you picked") and ⌘J ("New Layer via Copy")
/// hand back, so the same marquee gives the same pixels whichever way you
/// take them.
@Suite("Layer region")
struct LayerRegionTests {

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

    /// A red 100×100 background with a blue 30×30 patch at (10, 10).
    private func twoLayerDocument() -> (doc: PhotonzDocument, store: ImageStore, patch: UUID) {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patchRef = store.register(solidImage(width: 30, height: 30, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        let patch = Layer(name: "Patch", content: .image(patchRef),
                          frame: CGRect(x: 10, y: 10, width: 30, height: 30))
        doc.addLayer(patch)
        return (doc, store, patch.id)
    }

    @Test func takesOnlyThePickedLayersPixelsInsideTheMarquee() {
        let (doc, store, patch) = twoLayerDocument()
        // A marquee across the patch AND the background around it.
        let marquee = CGPath(rect: CGRect(x: 0, y: 0, width: 60, height: 60), transform: nil)
        guard let piece = DocumentRenderer().layerRegion(of: patch, in: doc, store: store,
                                                         path: marquee) else {
            Issue.record("no piece came back")
            return
        }
        // Trimmed to the patch, so the frame is the patch itself and not the
        // marquee's big transparent box.
        #expect(piece.frame == CGRect(x: 10, y: 10, width: 30, height: 30))
        #expect(piece.image.width == 30 && piece.image.height == 30)
        let inside = pixel(piece.image, x: 15, y: 15)
        #expect(inside.b > 240 && inside.a > 240, "patch pixels — got \(inside)")
    }

    @Test func cropsToThePartOfTheLayerTheMarqueeCovers() {
        let (doc, store, patch) = twoLayerDocument()
        // The right half of the patch only.
        let marquee = CGPath(rect: CGRect(x: 25, y: 0, width: 40, height: 100), transform: nil)
        guard let piece = DocumentRenderer().layerRegion(of: patch, in: doc, store: store,
                                                         path: marquee) else {
            Issue.record("no piece came back")
            return
        }
        #expect(piece.frame == CGRect(x: 25, y: 10, width: 15, height: 30))
        #expect(piece.image.width == 15 && piece.image.height == 30)
    }

    @Test func aMarqueeThatMissesTheLayerHandsBackNothing() {
        let (doc, store, patch) = twoLayerDocument()
        // Squarely on the background, nowhere near the patch.
        let marquee = CGPath(rect: CGRect(x: 60, y: 60, width: 20, height: 20), transform: nil)
        #expect(DocumentRenderer().layerRegion(of: patch, in: doc, store: store, path: marquee) == nil)
    }

    @Test func aMarqueeOffTheCanvasHandsBackNothing() {
        let (doc, store, patch) = twoLayerDocument()
        let marquee = CGPath(rect: CGRect(x: 200, y: 200, width: 20, height: 20), transform: nil)
        #expect(DocumentRenderer().layerRegion(of: patch, in: doc, store: store, path: marquee) == nil)
    }

    @Test func anUnknownLayerHandsBackNothing() {
        let (doc, store, _) = twoLayerDocument()
        let marquee = CGPath(rect: CGRect(x: 0, y: 0, width: 60, height: 60), transform: nil)
        #expect(DocumentRenderer().layerRegion(of: UUID(), in: doc, store: store, path: marquee) == nil)
    }

    /// A wand blob or an ellipse comes out with the shape it was drawn in: the
    /// corners the path does not cover stay clear.
    @Test func clipsToTheShapeTheMarqueeWasDrawnIn() {
        let (doc, store, patch) = twoLayerDocument()
        let marquee = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 30, height: 30), transform: nil)
        guard let piece = DocumentRenderer().layerRegion(of: patch, in: doc, store: store,
                                                         path: marquee) else {
            Issue.record("no piece came back")
            return
        }
        let corner = pixel(piece.image, x: 0, y: 0)
        #expect(corner.a == 0, "outside the ellipse — got \(corner)")
        let middle = pixel(piece.image, x: 15, y: 15)
        #expect(middle.b > 240 && middle.a > 240, "inside the ellipse — got \(middle)")
    }
}
