import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// One layer drawn alone but in place — the picture "copy the layer you
/// picked" crops.
@Suite("Isolated layer render")
struct IsolatedLayerRenderTests {

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

    @Test func drawsOnlyTheAskedForLayerAndLeavesTheRestTransparent() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 30, height: 30, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        let layer = Layer(name: "Patch", content: .image(patch),
                          frame: CGRect(x: 10, y: 10, width: 30, height: 30))
        doc.addLayer(layer)

        let output = DocumentRenderer().render(doc, store: store, only: layer.id)
        #expect(output?.width == 100)
        #expect(output?.height == 100)
        if let output {
            // The patch is there, in the place it occupies on the canvas.
            let inPatch = pixel(output, x: 20, y: 20)
            #expect(inPatch.b > 240 && inPatch.a > 240, "patch pixels — got \(inPatch)")
            // The red background it was sitting on is not.
            let outside = pixel(output, x: 70, y: 70)
            #expect(outside.a == 0, "outside the layer should be clear — got \(outside)")
        }
    }

    @Test func theBackgroundLayerCanBeIsolatedToo() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 60, height: 60, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 20, height: 20, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 0, y: 0, width: 20, height: 20)))
        let backgroundID = doc.layers[0].id

        let output = DocumentRenderer().render(doc, store: store, only: backgroundID)
        if let output {
            // Where the blue patch covers the background, the background alone
            // is still red: the layer above it is not in this picture.
            let underPatch = pixel(output, x: 10, y: 10)
            #expect(underPatch.r > 240 && underPatch.b < 16, "background pixels — got \(underPatch)")
        } else {
            Issue.record("expected a render")
        }
    }

    @Test func aLayerInsideAGroupIsDrawnWhereTheCanvasShowsIt() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 20, height: 20, r: 0, g: 255, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        let child = Layer(name: "Child", content: .image(patch),
                          frame: CGRect(x: 5, y: 5, width: 20, height: 20))
        doc.addLayer(Layer(name: "Group", content: .group(GroupContent(children: [child])),
                           frame: CGRect(x: 40, y: 40, width: 0, height: 0)))

        let output = DocumentRenderer().render(doc, store: store, only: child.id)
        if let output {
            // The child's frame is inside its group, so on the canvas it sits
            // at (45, 45) — that is where an isolated render must put it.
            let inChild = pixel(output, x: 50, y: 50)
            #expect(inChild.g > 240 && inChild.a > 240, "child pixels — got \(inChild)")
            let elsewhere = pixel(output, x: 10, y: 10)
            #expect(elsewhere.a == 0, "outside the child should be clear — got \(elsewhere)")
        } else {
            Issue.record("expected a render")
        }
    }

    @Test func anUnknownLayerRendersNothing() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 40, height: 40, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(base)
        #expect(DocumentRenderer().render(doc, store: store, only: UUID()) == nil)
    }
}
