import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **A flipped layer is flipped in the exported movie**, not only on the
/// canvas: a real MP4 is written from the same `drawn(atTimeMS:)` picture
/// the canvas plays, opened again and read on its left and right.
@Suite("A flipped layer survives the export", .serialized)
struct FlippedLayerExportTests {

    static let canvas = CGSize(width: 160, height: 120)

    /// A picture red on its left half and blue on its right, on the timeline.
    static func document(store: ImageStore) throws -> (PhotonzDocument, UUID) {
        let width = Int(canvas.width), height = Int(canvas.height)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)
                                                 ?? CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let image = try #require(context.makeImage())
        var layer = Layer(name: "Half and half", content: .image(store.register(image)),
                          frame: CGRect(origin: .zero, size: canvas))
        layer.time = LayerTime(inMS: 0, outMS: 2000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [layer])
        document.durationMS = 2000
        return (document, layer.id)
    }

    /// The average colour of the left and right halves of a frame.
    static func halves(of url: URL, atSeconds seconds: Double) async throws
        -> (left: (r: Int, b: Int), right: (r: Int, b: Int)) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixels = [UInt8](repeating: 0, count: 8)
        guard let context = pixels.withUnsafeMutableBytes({ bytes in
            CGContext(data: bytes.baseAddress, width: 2, height: 1, bitsPerComponent: 8,
                      bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { throw TestTone.Failure.noBuffer }
        context.interpolationQuality = .medium
        context.draw(frame, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        return ((Int(pixels[0]), Int(pixels[2])), (Int(pixels[4]), Int(pixels[6])))
    }

    @Test("Flipped left to right, the movie is blue on the left and red on the right")
    func theMovieIsMirrored() async throws {
        let store = ImageStore()
        var (document, id) = try Self.document(store: store)
        let flipped = document.flip(ids: [id], .horizontal)
        #expect(flipped)
        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .standard)
        let out = TestTone.scratch().appendingPathComponent("flipped-layer.mp4")
        let shown = document
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: { ms in
                                                DocumentRenderer().render(shown.drawn(atTimeMS: ms), store: store)
                                            })
        let read = try await Self.halves(of: out, atSeconds: 1)
        #expect(read.left.b > 180 && read.left.r < 60, "left half reads \(read.left)")
        #expect(read.right.r > 180 && read.right.b < 60, "right half reads \(read.right)")
    }
}
