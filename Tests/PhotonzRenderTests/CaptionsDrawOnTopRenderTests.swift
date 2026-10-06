import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Captions are drawn over everything, wherever their row is listed, in the
/// one composite the canvas, a written frame and an exported film all come out
/// of (`CaptionsDrawOnTop.swift`).
@Suite("Captions draw on top")
struct CaptionsDrawOnTopRenderTests {

    private func solidImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// How many pixels are anything other than the red cover.
    private func notRed(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4)
        where data[i] < 200 || data[i + 1] > 60 || data[i + 2] > 60 { count += 1 }
        return count
    }

    /// Captions, then an opaque red picture over the whole canvas laid on top
    /// of them in the stack, the way a title typed after the captions is.
    private func coveredCaptions(captionsLook: Bool) throws -> CGImage {
        let size = CGSize(width: 640, height: 360)
        let store = ImageStore()
        var doc = PhotonzDocument(canvasSize: size)
        let landed = doc.landCaptions(CaptionCues.cues(from: [
            TranscribedWord("Capture", startMS: 0, endMS: 500, confidence: 0.9),
            TranscribedWord("it.", startMS: 500, endMS: 900, confidence: 0.9),
        ]))
        let captions = try #require(landed)
        if !captionsLook { doc.updateLayer(id: captions) { $0.captionsLook = nil } }
        let red = store.register(solidImage(width: 640, height: 360))
        doc.addLayer(Layer(name: "Cover", content: .image(red), frame: CGRect(origin: .zero, size: size)))
        #expect(doc.layers.last?.name == "Cover", "the cover is on top of the stack")
        return try #require(DocumentRenderer().render(doc, store: store))
    }

    @Test("A Captions layer under something in the stack is still drawn over it")
    func captionsOverWhatIsAboveThem() throws {
        #expect(notRed(try coveredCaptions(captionsLook: true)) > 200)
    }

    @Test("An ordinary group in the same place is drawn under it, as the stack says")
    func anOrdinaryGroupStaysUnder() throws {
        #expect(notRed(try coveredCaptions(captionsLook: false)) == 0)
    }
}
