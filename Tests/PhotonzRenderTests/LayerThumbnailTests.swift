import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Layer thumbnails")
struct LayerThumbnailTests {

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

    @Test func thumbnailShrinksToMaxDimensionPreservingAspect() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 400, height: 200, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200))
        let layer = Layer(name: "L", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        doc.addLayer(layer)

        let thumb = DocumentRenderer().thumbnail(for: layer.id, in: doc, store: store, maxDimension: 40)
        #expect(thumb != nil)
        #expect(thumb?.width == 40)
        #expect(thumb?.height == 20)
        if let thumb {
            let p = pixel(thumb, x: 20, y: 10)
            #expect(p.b > 240 && p.a > 240)
        }
    }

    @Test func smallLayersAreNotUpscaled() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 16, height: 8, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let layer = Layer(name: "Small", content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 16, height: 8))
        doc.addLayer(layer)

        let thumb = DocumentRenderer().thumbnail(for: layer.id, in: doc, store: store, maxDimension: 40)
        #expect(thumb?.width == 16)
        #expect(thumb?.height == 8)
    }

    @Test func unknownLayerReturnsNil() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        #expect(DocumentRenderer().thumbnail(for: UUID(), in: doc, store: ImageStore(),
                                             maxDimension: 40) == nil)
    }
}
