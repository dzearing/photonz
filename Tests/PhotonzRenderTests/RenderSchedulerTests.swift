import CoreGraphics
import Foundation
import Synchronization
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

        scheduler.submit(doc)
        await scheduler.waitUntilIdle()

        let images = await collector.images
        #expect(images.count == 1)
        if let image = images.last {
            let p = pixel(image, x: 10, y: 10)
            #expect(p.r > 240 && p.g < 16)
        }
    }

    /// What the canvas is told about a picture it did not draw itself: a
    /// speed walk counts a scrubbed picture as caught up only when it was
    /// drawn from the frames under the hand, and the tag is how that fact
    /// rides along with the picture it is about.
    @Test("A picture comes back with the tag it was asked for with")
    func tagRidesAlong() async {
        let store = ImageStore()
        let base = store.register(solidImage(width: 8, height: 8, r: 255, g: 0, b: 0))
        let doc = PhotonzDocument.withBaseImage(base)
        actor Tags { var seen: [Int] = []; func add(_ tag: Int) { seen.append(tag) } }
        let tags = Tags()
        let scheduler = RenderScheduler(store: store, onDelivery: { await tags.add($0.tag) })
        scheduler.submit(doc, stamp: 5, tag: 1)
        await scheduler.waitUntilIdle()
        scheduler.submit(doc, stamp: 6)
        await scheduler.waitUntilIdle()
        #expect(await tags.seen == [1, 0])
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
            scheduler.submit(doc)
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

        scheduler.submit(.withBaseImage(red))
        scheduler.submit(.withBaseImage(green))
        await scheduler.waitUntilIdle()

        let images = await collector.images
        if let last = images.last {
            let p = pixel(last, x: 10, y: 10)
            #expect(p.g > 240 && p.r < 16, "last delivered frame must be the last submitted document")
        } else {
            Issue.record("no frames delivered")
        }
    }

    @Test func writesTheFrameInTheColourSpaceItWasAskedFor() async throws {
        let store = ImageStore()
        let base = store.register(solidImage(width: 20, height: 20, r: 255, g: 0, b: 0))
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let collector = FrameCollector()
        let scheduler = RenderScheduler(store: store) { await collector.add($0) }

        scheduler.submit(.withBaseImage(base), colorSpace: p3)
        await scheduler.waitUntilIdle()

        let image = try #require(await collector.images.last)
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        let p = pixel(image, x: 10, y: 10)
        #expect(p.r > 240 && p.g < 16, "still red, read back in sRGB")
    }

    /// A picture is asked for straight from the main actor, with no task in
    /// between: a task started there first waits its turn on the main actor,
    /// and while a hand dragged the playhead of the 6 minute reference edit
    /// that turn cost 0.8 ms in the middle and 3.5 at the slow end, enough to
    /// put the picture a refresh behind the hand
    /// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 17).
    @MainActor
    @Test("A picture asked for while the main actor stays busy is drawn and delivered all the same")
    func drawsWhileTheMainActorIsBusy() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 20, height: 20, r: 255, g: 0, b: 0))
        let arrived = Mutex(false)
        let scheduler = RenderScheduler(store: store) { image in
            if image != nil { arrived.withLock { $0 = true } }
        }
        scheduler.submit(.withBaseImage(base))
        // Hold the main actor, never giving it up, until the picture comes.
        let deadline = Date().addingTimeInterval(5)
        while !arrived.withLock({ $0 }), Date() < deadline {}
        #expect(arrived.withLock { $0 })
    }

    @Test("Pictures asked for in a row are drawn in that order, the newest last")
    func askedInARowDrawnInOrder() async {
        let store = ImageStore()
        let ids = (0..<30).map { i in store.register(solidImage(width: 4, height: 4, r: UInt8(i * 8), g: 0, b: 0)) }
        actor Stamps { var seen: [Int] = []; func add(_ stamp: Int) { seen.append(stamp) } }
        let stamps = Stamps()
        let scheduler = RenderScheduler(store: store, onDelivery: { await stamps.add($0.stamp) })
        for (i, id) in ids.enumerated() { scheduler.submit(.withBaseImage(id), stamp: i) }
        await scheduler.waitUntilIdle()
        let seen = await stamps.seen
        #expect(seen == seen.sorted())
        #expect(seen.last == 29)
    }
}
