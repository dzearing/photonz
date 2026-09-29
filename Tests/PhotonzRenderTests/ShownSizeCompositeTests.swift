import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A recording composited at the size it is shown still draws everything on it
/// (`a-title-with-a-fade-in-and-a-fade-out-shows-duri`).
///
/// The canvas composites a big recording at the size the window shows it
/// (`CompositeScale`): the document is magnified by a half or less and handed
/// to the renderer. Until 2026-09-28 the renderer was never told, so a title's
/// words were laid out at their full 223pt inside a box shrunk to a half, and
/// came out as nothing: a title on a full-screen Retina recording never showed,
/// stopped or playing, whatever its fades said.
@Suite("A recording composited at its shown size draws what is on it")
struct ShownSizeCompositeTests {

    static let canvas = CGSize(width: 3456, height: 2234)

    /// A dark frame of a screen recording with a white title over it, the way
    /// the text tool makes one on a recording.
    static func titled() -> (PhotonzDocument, Layer) {
        var document = PhotonzDocument(canvasSize: canvas)
        let styles = TitleLook.styles(in: canvas)
        var title = Layer(name: "Ship it faster",
                          content: .text(styles.content(string: "Ship it faster")),
                          frame: CGRect(x: 1200, y: 900, width: 1474, height: 258))
        title.style.shadows = TitleLook.shadows(forColorHex: styles.colorHex, fontSize: styles.fontSize)
        document.layers = [title]
        return (document, title)
    }

    static func shown(_ document: PhotonzDocument, at scale: CGFloat) -> PhotonzDocument {
        var shown = document.magnified(by: scale)
        shown.canvasSize = CGSize(width: (canvas.width * scale).rounded(),
                                  height: (canvas.height * scale).rounded())
        return shown
    }

    /// How many pixels inside `box` are close to white.
    static func whitePixels(_ image: CGImage, in box: CGRect) -> Int {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var count = 0
        let rows = max(0, Int(box.minY))..<min(h, Int(box.maxY))
        let columns = max(0, Int(box.minX))..<min(w, Int(box.maxX))
        for y in rows {
            for x in columns {
                let i = (y * w + x) * 4
                if data[i] > 230, data[i + 1] > 230, data[i + 2] > 230 { count += 1 }
            }
        }
        return count
    }

    @Test("A title on a big recording shows at every size it is composited at",
          arguments: [0.75, 0.5, 0.375, 0.25] as [CGFloat])
    func titleShowsAtShownSize(scale: CGFloat) throws {
        let (document, title) = Self.titled()
        let store = ImageStore()
        let full = try #require(DocumentRenderer().render(document, store: store))
        let fullInk = Self.whitePixels(full, in: title.frame)
        #expect(fullInk > 20_000, "the full-size render draws the words (\(fullInk) white pixels)")

        let shown = Self.shown(document, at: scale)
        let picture = try #require(DocumentRenderer().renderInteractive(shown, store: store,
                                                                         contentScale: scale))
        let box = title.frame.magnified(by: scale)
        let ink = Self.whitePixels(picture, in: box)
        // The same words at a smaller size: about scale squared of the ink.
        let expected = Double(fullInk) * Double(scale * scale)
        #expect(Double(ink) > expected * 0.6,
                "at \(scale) the words drew \(ink) white pixels, expected about \(Int(expected))")
    }

    @Test("The render scheduler composites at the scale it is told")
    func schedulerPassesTheScale() async throws {
        let (document, title) = Self.titled()
        let scale: CGFloat = 0.5
        let store = ImageStore()
        let delivered = Delivered()
        let scheduler = RenderScheduler(store: store, onDelivery: { await delivered.set($0.image) })
        await scheduler.submit(Self.shown(document, at: scale), contentScale: scale)
        await scheduler.waitUntilIdle()
        let picture = try #require(await delivered.image)
        #expect(Self.whitePixels(picture, in: title.frame.magnified(by: scale)) > 5000)
    }

    actor Delivered {
        var image: CGImage?
        func set(_ image: CGImage?) { self.image = image }
    }
}
