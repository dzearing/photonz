import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Scaled render")
struct ScaledRenderTests {

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

    @Test func scaleTwoDoublesPixelDimensions() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 64, height: 32, r: 0, g: 0, b: 255))
        let doc = PhotonzDocument.withBaseImage(ref)

        let output = DocumentRenderer().render(doc, store: store, scale: 2)
        #expect(output?.width == 128)
        #expect(output?.height == 64)
        if let output {
            let p = pixel(output, x: 64, y: 32)
            #expect(p.b > 240 && p.a > 240)
        }
    }

    @Test func scaleOneMatchesPlainRender() {
        let store = ImageStore()
        let ref = store.register(solidImage(width: 40, height: 40, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(ref)
        let output = DocumentRenderer().render(doc, store: store, scale: 1)
        #expect(output?.width == 40)
        #expect(output?.height == 40)
    }
}
