import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **A colour grade leaves in the file the way it plays**
/// (task `a-clip-can-be-colour-graded-from-add-effect`).
///
/// A grey picture whose Temperature is keyed from its middle to its warm end
/// over two seconds is written to a real MP4 through the ordinary renderer and
/// opened again: grey at the first key, warm at the last, and part way between
/// half way.
@Suite("A colour grade reaches the exported movie", .serialized)
struct ColorGradeExportTests {

    static let folder = TestTone.scratch()
    static let canvas = CGSize(width: 200, height: 100)

    /// Red over blue in the written file at a moment, in the middle of the
    /// picture.
    static func warmth(of url: URL, atSeconds seconds: Double) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let width = frame.width, height = frame.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw TestTone.Failure.noBuffer }
        let index = ((height / 2) * width + width / 2) * 4
        return Int(data[index]) - Int(data[index + 2])
    }

    @Test("A Temperature keyed warmer is grey at its first key, warm at its last and between half way")
    func aKeyedGradeIsInTheFile() async throws {
        let rect = CGRect(origin: .zero, size: Self.canvas)
        var picture = Layer(name: "Picture",
                            content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                   colorHex: "#808080", start: .zero,
                                                                   end: CGPoint(x: rect.width, y: rect.height),
                                                                   fillColorHex: "#808080")),
                            frame: rect)
        picture.time = LayerTime(inMS: 0, outMS: 4000)
        picture.style.effects = [.colorGrade(.neutral)]
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [picture])
        document.durationMS = 4000
        document.startKeying(layerID: picture.id, .motion(.gradeTemperature), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.number(100), layerID: picture.id, .motion(.gradeTemperature),
                               atDocumentTimeMS: 3000, ease: .linear)

        let plan = DocumentVideoExport.plan(durationMS: 4000, canvasSize: Self.canvas,
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("color-grade.mp4")
        let drawing = document
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out) { ms in
            DocumentRenderer().render(drawing.drawn(atTimeMS: ms), store: ImageStore())
        }

        let grey = try await Self.warmth(of: out, atSeconds: 0.5)
        let half = try await Self.warmth(of: out, atSeconds: 2.0)
        let warm = try await Self.warmth(of: out, atSeconds: 3.5)
        #expect(abs(grey) < 8, "grey before the grade warms: \(grey)")
        #expect(warm > 35, "warm at the last key: \(warm)")
        #expect(half > grey + 8 && half < warm - 8, "part way half way: \(grey) \(half) \(warm)")
    }
}
