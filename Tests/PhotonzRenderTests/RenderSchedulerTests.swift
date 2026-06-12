import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("RenderScheduler")
struct RenderSchedulerTests {

    private actor FrameCollector {
        private(set) var images: [CGImage] = []
        func add(_ image: CGImage?) {
            if let image { images.append(image) }
        }
    }

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

    @Test func deliversAFrameForASingleSubmit() async {
        let store = ImageStore()
        let base = store.register(solidImage(width: 20, height: 20, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(base)

        let collector = FrameCollector()
        let scheduler = RenderScheduler(store: store) { await collector.add($0) }

        await scheduler.submit(doc)
        await scheduler.waitUntilIdle()

        let images = await collector.images
        #expect(images.count == 1)
        if let image = images.last {
            let p = pixel(image, x: 10, y: 10)
            #expect(p.r > 240 && p.g < 16)
        }
    }

    @Test func stressMutating100xEndsWithCorrectFinalFrame() async {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 10, height: 10, r: 0, g: 0, b: 255))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 0, y: 20, width: 10, height: 10)))

        let collector = FrameCollector()
        let scheduler = RenderScheduler(store: store) { await collector.add($0) }

        // Slide the patch right 100 times in rapid succession.
        for i in 0..<100 {
            doc.layers[doc.layers.count - 1].frame.origin.x = CGFloat(i % 50)
            await scheduler.submit(doc)
        }
        await scheduler.waitUntilIdle()

        let images = await collector.images
        #expect(!images.isEmpty)
        #expect(images.count <= 100)
        if let final = images.last {
            // Final document: patch at x = 49, spanning 49...59 at y 20...30.
            let onPatch = pixel(final, x: 54, y: 25)
            let offPatch = pixel(final, x: 5, y: 25)
            #expect(onPatch.b > 240 && onPatch.r < 16, "final frame must show the patch at its last position")
            #expect(offPatch.r > 240 && offPatch.b < 16, "no ghost of earlier positions")
        }
    }

    @Test func framesArriveInSubmissionOrder() async {
        // Submit two distinguishable documents and verify the last delivered
        // frame is the last submitted one (latest wins, no stale overwrite).
        let store = ImageStore()
        let red = store.register(solidImage(width: 20, height: 20, r: 255, g: 0, b: 0))
        let green = store.register(solidImage(width: 20, height: 20, r: 0, g: 255, b: 0))

        let collector = FrameCollector()
        let scheduler = RenderScheduler(store: store) { await collector.add($0) }

        await scheduler.submit(.withBaseImage(red))
        await scheduler.submit(.withBaseImage(green))
        await scheduler.waitUntilIdle()

        let images = await collector.images
        if let last = images.last {
            let p = pixel(last, x: 10, y: 10)
            #expect(p.g > 240 && p.r < 16, "last delivered frame must be the last submitted document")
        } else {
            Issue.record("no frames delivered")
        }
    }
}
