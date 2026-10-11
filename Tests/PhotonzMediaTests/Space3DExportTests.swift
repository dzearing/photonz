import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **A layer turned in space comes out of the movie where the canvas drew it**
/// (`layers-can-turn-about-x-and-y-and-move-in-depth`).
///
/// A real MP4 of a card flipping on Y is written, opened again, and three of
/// its frames are held against the canvas's own frame for the same moment,
/// pixel by pixel. The file is compressed, so a pixel may be a few levels off;
/// what must not happen is the card being anywhere else.
@Suite("2.5D: the movie matches the canvas", .serialized)
struct Space3DExportTests {

    static let canvas = CGSize(width: 320, height: 240)

    static func document() -> (PhotonzDocument, UUID) {
        func rect(_ frame: CGRect, _ hex: String) -> Layer {
            Layer(name: hex, content: .annotation(AnnotationContent(
                shape: .rectangle, strokeWidth: 0, colorHex: hex, start: .zero,
                end: CGPoint(x: frame.width, y: frame.height), fillColorHex: hex)), frame: frame)
        }
        let ground = rect(CGRect(origin: .zero, size: canvas), "#000000")
        var card = rect(CGRect(x: 80, y: 60, width: 160, height: 120), "#FF0000")
        card.time = LayerTime(inMS: 0, outMS: 2000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [ground, card])
        document.durationMS = 2000
        document.startKeying(layerID: card.id, .motion(.rotationY), atDocumentTimeMS: 0)
        document.setKeyedValue(.number(180), layerID: card.id, .motion(.rotationY), atDocumentTimeMS: 1500)
        document.startKeying(layerID: card.id, .motion(.depth), atDocumentTimeMS: 0)
        document.setKeyedValue(.number(80), layerID: card.id, .motion(.depth), atDocumentTimeMS: 1500)
        return (document, card.id)
    }

    static func rgba(_ image: CGImage, size: CGSize) -> [UInt8] {
        let w = Int(size.width), h = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    @Test("Three moments of a flip: the file's frame and the canvas's agree")
    func flipMatches() async throws {
        let (document, _) = Self.document()
        let store = ImageStore()
        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .high)
        let out = TestTone.scratch().appendingPathComponent("flip-3d.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: { ms in
                                                DocumentRenderer().render(document.drawn(atTimeMS: ms),
                                                                          store: store)
                                            })
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: out))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let canvasRenderer = DocumentRenderer()
        for ms in [400, 700, 1100] {
            let time = CMTime(value: CMTimeValue(ms), timescale: 1000)
            let (frame, actual) = try await generator.image(at: time)
            let landed = Int((actual.seconds * 1000).rounded())
            let live = try #require(canvasRenderer.renderInteractive(document.drawn(atTimeMS: landed),
                                                                     store: store))
            let a = Self.rgba(frame, size: Self.canvas)
            let b = Self.rgba(live, size: Self.canvas)
            var total = 0, far = 0
            for index in stride(from: 0, to: a.count, by: 4) {
                let d = abs(Int(a[index]) - Int(b[index]))
                total += d
                if d > 48 { far += 1 }
            }
            let pixels = a.count / 4
            let mean = Double(total) / Double(pixels)
            print(String(format: "[3d] movie vs canvas at %dms (frame %dms): mean red difference %.2f, "
                         + "%d of %d pixels more than 48 levels off", ms, landed, mean, far, pixels))
            #expect(mean < 3, "at \(ms)ms")
            // Compression softens the card's edge a pixel or so; nothing more.
            #expect(far < pixels / 100, "at \(ms)ms")
        }
    }
}
