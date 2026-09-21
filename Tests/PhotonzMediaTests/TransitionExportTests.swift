import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **What plays is what exports**, for a cut with a transition on it
/// (`docs/design/video-transitions.md`).
///
/// This is the one claim that cannot be checked by reading code: the writer is
/// handed the same `drawn(atTimeMS:)` picture the canvas is, so a dissolve and
/// a dip have to come out of the FILE. Each test here writes a real movie and
/// then opens it again and looks at the frame on the cut.
@Suite("A transition survives the export", .serialized)
struct TransitionExportTests {

    static let folder = TestTone.scratch()
    static let canvas = CGSize(width: 160, height: 120)

    /// A two piece clip: the first piece red, the second blue, with a gap in
    /// the recording between them so the two sides are really different.
    static func document() throws -> (document: PhotonzDocument, store: ImageStore) {
        let store = ImageStore()
        let movie = MovieRef(pixelSize: canvas, durationMS: 8000)
        var clip = Layer(name: "Recording",
                         content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 8000)
        clip.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 2000),
                                               ClipPiece(sourceInMS: 5000, lengthMS: 2000)],
                                      sourceLengthMS: 8000))
        var document = PhotonzDocument(canvasSize: canvas, layers: [clip])
        document.durationMS = 4000
        return (document, store)
    }

    static func solid(_ hex: String) throws -> CGImage {
        try #require(SolidImage.make(size: canvas, hex: hex))
    }

    /// The frames the app's own fetcher would have filed, filed here instead:
    /// everything before the middle of the recording red, everything after it
    /// blue.
    static func fillFrames(_ document: PhotonzDocument, store: ImageStore, atMS ms: Int) throws {
        for request in document.movieFrames(atTimeMS: ms) {
            store.register(try solid(request.sourceMS >= 4000 ? "#0000FF" : "#FF0000"),
                           as: request.ref)
        }
    }

    /// The export's own frame source: exactly what the app hands the writer —
    /// the document drawn at a moment, through the ordinary renderer.
    static func frames(_ document: PhotonzDocument,
                       store: ImageStore) -> @Sendable (Int) async -> CGImage? {
        { ms in
            try? fillFrames(document, store: store, atMS: ms)
            return DocumentRenderer().render(document.drawn(atTimeMS: ms), store: store)
        }
    }

    static func colour(of url: URL, atSeconds seconds: Double) async throws -> (r: Int, g: Int, b: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = pixel.withUnsafeMutableBytes({ bytes in
            CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { throw TestTone.Failure.noBuffer }
        context.interpolationQuality = .low
        context.draw(frame, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    static func write(_ document: PhotonzDocument, store: ImageStore,
                      named name: String) async throws -> URL {
        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .standard)
        let out = folder.appendingPathComponent(name)
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: frames(document, store: store))
        return out
    }

    @Test("A hard cut comes out as a hard cut: one shot, then the other")
    func aHardCutIsHard() async throws {
        let (document, store) = try Self.document()
        let out = try await Self.write(document, store: store, named: "hard-cut.mp4")
        let before = try await Self.colour(of: out, atSeconds: 1.5)
        #expect(before.r > 180 && before.b < 70)
        let after = try await Self.colour(of: out, atSeconds: 2.5)
        #expect(after.b > 180 && after.r < 70)
    }

    @Test("A dip to black is black in the FILE, on the frame the cut is on")
    func aDipIsBlackInTheFile() async throws {
        let (base, store) = try Self.document()
        var document = base
        let put = document.setClipTransition(try #require(document.layers.first).id, atCut: 1,
                                             to: ClipTransition(kind: .dipToBlack, lengthMS: 600))
        #expect(put)
        let out = try await Self.write(document, store: store, named: "dip-to-black.mp4")
        // Nearly black rather than exactly black, and the number is worth
        // knowing: the export photographs on a 33ms grid, so the frame nearest
        // the cut is about twenty milliseconds off the bottom of the dip, and
        // the few per cent of light still getting through reads as about 70 out
        // of 255 once it is written back as sRGB. Beside shots that read over
        // 180, that is the picture going through black.
        let onTheCut = try await Self.colour(of: out, atSeconds: 2.0)
        #expect(onTheCut.r < 110 && onTheCut.g < 60 && onTheCut.b < 60)
        // ...and clear of it, the shots are their own colours, so the dip did
        // not simply darken the whole film.
        let before = try await Self.colour(of: out, atSeconds: 1.0)
        #expect(before.r > 180)
        let after = try await Self.colour(of: out, atSeconds: 3.0)
        #expect(after.b > 180)
    }

    @Test("A cross dissolve is both shots at once in the FILE")
    func aDissolveIsBothInTheFile() async throws {
        let (base, store) = try Self.document()
        var document = base
        let put = document.setClipTransition(try #require(document.layers.first).id, atCut: 1,
                                             to: ClipTransition(kind: .dissolve, lengthMS: 600))
        #expect(put)
        let out = try await Self.write(document, store: store, named: "dissolve.mp4")
        // On the cut, neither shot alone: some of each. (The numbers are not
        // half of 255: the composite happens in linear light.)
        let onTheCut = try await Self.colour(of: out, atSeconds: 2.0)
        #expect(onTheCut.r > 60 && onTheCut.b > 60)
        #expect(onTheCut.r < 240 && onTheCut.b < 240)
    }
}
