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

    /// One frame of the 30 a second movie, in whole milliseconds.
    static let frameMS = 33

    /// How far the movie's red channel is from the canvas's: the mean
    /// difference, how many pixels are more than 48 levels off, and how many
    /// of those are more than `edgeBand` pixels from any edge the canvas drew.
    static func compare(_ movie: [UInt8], _ canvas: [UInt8],
                        edgeBand: Int = 2) -> (mean: Double, far: Int, farFromEdge: Int, pixels: Int) {
        let w = Int(Self.canvas.width), h = Int(Self.canvas.height)
        func red(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Int { Int(bytes[(y * w + x) * 4]) }
        var total = 0, far = 0, farFromEdge = 0
        for y in 0..<h {
            for x in 0..<w {
                let d = abs(red(movie, x, y) - red(canvas, x, y))
                total += d
                guard d > 48 else { continue }
                far += 1
                var nearEdge = false
                for dy in -edgeBand...edgeBand where !nearEdge {
                    for dx in -edgeBand...edgeBand {
                        let nx = min(max(x + dx, 0), w - 1), ny = min(max(y + dy, 0), h - 1)
                        if abs(red(canvas, nx, ny) - red(canvas, x, y)) > 48 { nearEdge = true; break }
                    }
                }
                if !nearEdge { farFromEdge += 1 }
            }
        }
        return (Double(total) / Double(w * h), far, farFromEdge, w * h)
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
        func canvas(atMS ms: Int) throws -> [UInt8] {
            Self.rgba(try #require(canvasRenderer.renderInteractive(document.drawn(atTimeMS: ms),
                                                                    store: store)),
                      size: Self.canvas)
        }
        for ms in [400, 700, 1100] {
            let time = CMTime(value: CMTimeValue(ms), timescale: 1000)
            let (frame, actual) = try await generator.image(at: time)
            let landed = Int((actual.seconds * 1000).rounded())
            let a = Self.rgba(frame, size: Self.canvas)
            let b = try canvas(atMS: landed)
            let here = Self.compare(a, b)
            // The frames either side, so a file running a frame early or late
            // against the canvas reads as exactly that.
            let early = Self.compare(a, try canvas(atMS: landed - Self.frameMS))
            let late = Self.compare(a, try canvas(atMS: landed + Self.frameMS))
            print(String(format: "[3d] movie vs canvas at %dms (frame %dms): mean red difference %.2f, "
                         + "%d of %d pixels more than 48 levels off, %d of them away from the card's edge; "
                         + "a frame early %.2f, a frame late %.2f",
                         ms, landed, here.mean, here.far, here.pixels, here.farFromEdge,
                         early.mean, late.mean))
            #expect(landed == ms, "the file has a frame starting at \(ms)ms")
            #expect(here.mean < 3, "at \(ms)ms")
            // The picture in the file is the canvas's at that moment, not the
            // one a frame before or after it.
            #expect(here.mean < early.mean, "at \(ms)ms")
            #expect(here.mean < late.mean, "at \(ms)ms")
            // Compression softens the card's edge a pixel or so, and how many
            // edge pixels that costs is the encoder's business (CI's runner
            // turned 776 of them, this Mac 287, for the same picture). Off the
            // edge, every pixel is where the canvas put it.
            #expect(here.farFromEdge < here.pixels / 1000, "at \(ms)ms")
        }
    }
}
