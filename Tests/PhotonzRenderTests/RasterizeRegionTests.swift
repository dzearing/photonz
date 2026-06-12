import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Rasterize region")
struct RasterizeRegionTests {

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

    @Test func rasterizesTheRequestedRegionOfTheComposite() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 30, height: 30, r: 0, g: 0, b: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        // Blue patch at (10, 10)–(40, 40) in top-left model coords.
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 10, y: 10, width: 30, height: 30)))

        // Region covering the patch plus a red margin on the right.
        let region = CGRect(x: 10, y: 10, width: 60, height: 30)
        let output = DocumentRenderer().rasterize(region: region, of: doc, store: store)
        #expect(output != nil)
        #expect(output?.width == 60)
        #expect(output?.height == 30)
        if let output {
            let inPatch = pixel(output, x: 5, y: 15)
            #expect(inPatch.b > 240 && inPatch.r < 16, "patch pixels — got \(inPatch)")
            let inBase = pixel(output, x: 50, y: 15)
            #expect(inBase.r > 240 && inBase.b < 16, "base pixels — got \(inBase)")
        }
    }

    @Test func regionIsClampedToTheCanvas() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 50, height: 50, r: 0, g: 255, b: 0))
        let doc = PhotonzDocument.withBaseImage(base)

        let region = CGRect(x: 30, y: 30, width: 100, height: 100)
        let output = DocumentRenderer().rasterize(region: region, of: doc, store: store)
        #expect(output?.width == 20)
        #expect(output?.height == 20)
    }

    @Test func degenerateRegionReturnsNil() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 50, height: 50, r: 0, g: 255, b: 0))
        let doc = PhotonzDocument.withBaseImage(base)
        let output = DocumentRenderer().rasterize(region: CGRect(x: -100, y: -100, width: 10, height: 10),
                                                  of: doc, store: store)
        #expect(output == nil)
    }
}
