import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A closed window's pictures and frames are given back. On 2026-10-23 five
/// opens and closes of a 12-megapixel picture left the probe at 1.9 GB:
/// every closed editor still held its store and its frame buffer. The app
/// now empties both when the window goes (`EditorState.letGoOnClose`); these
/// pin the two calls it makes.
@Suite("Letting go of pictures and frames")
struct LettingGoTests {

    private func solid(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func aStoreSaysHowManyBytesOfPictureItHolds() {
        let store = ImageStore()
        #expect(store.pixelBytes == 0)
        store.register(solid(width: 100, height: 50))
        store.register(solid(width: 10, height: 10))
        #expect(store.pixelBytes == 100 * 50 * 4 + 10 * 10 * 4)
    }

    @Test func anEmptiedStoreHoldsNothing() {
        let store = ImageStore()
        let ref = store.register(solid(width: 64, height: 64))
        store.removeAll()
        #expect(store.image(for: ref) == nil)
        #expect(store.pixelBytes == 0)
        #expect(store.count == 0)
    }

    @Test func aRendererThatLetGoHoldsNoFrameAndNoCachesAndStillDraws() throws {
        let store = ImageStore()
        var document = PhotonzDocument.withBaseImage(store.register(solid(width: 400, height: 300)))
        document.addLayer(Layer(name: "Text",
                                content: .text(TextContent(string: "Hi", fontSize: 40, colorHex: "#112233")),
                                frame: CGRect(x: 10, y: 10, width: 120, height: 60)))
        let renderer = DocumentRenderer()
        let before = try #require(renderer.renderInteractive(document, store: store))
        #expect(renderer.frameBufferBytes >= 400 * 300 * 4)
        #expect(renderer.contentCacheCount > 0)

        renderer.letGo()
        #expect(renderer.frameBufferBytes == 0)
        #expect(renderer.contentCacheCount == 0)

        let after = try #require(renderer.renderInteractive(document, store: store))
        #expect(after.width == before.width && after.height == before.height)
    }
}
