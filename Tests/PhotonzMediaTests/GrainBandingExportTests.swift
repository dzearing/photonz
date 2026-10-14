import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **Grain stops a dark gradient banding in the exported movie**
/// (task `title-backgrounds-move-gradients-grain-and-the-r`).
///
/// A movie encoder squeezes a smooth dark gradient into flat steps you can see
/// on a big screen. A dark title backdrop is written to a real MP4 twice,
/// once plain and once with Grain at its default amount, the files are opened
/// again, and the bands are MEASURED: how many rows in a row a column of the
/// picture stays exactly one value. Plain, the steps are tens of rows tall;
/// with grain they break up into the noise.
///
/// Measured on 2026-10-10, 1080p at the app's own bitrate: plain 48 rows. One
/// pixel grain at 12% made no difference (41 to 48 rows: the encoder wipes it
/// out); two pixel grain at 25% halved it (24 rows), at 30% 21 rows.
///
/// Every frame of the file is read and the middle one counts. Grain is new
/// noise each frame, so one frame of the grainy file reads anywhere from 11 to
/// 32 rows (2026-10-14), and reading only the frame at 0.3s failed about one
/// full test run in three: with other suites encoding at the same moment the
/// plain file comes out of the encoder differently (4 KB alone, 86 KB beside
/// them, 44 rows instead of 48) and the 0.3s read landed on a 31 row frame.
/// The middle frame read 24 rows grainy in every run, alone or not.
@Suite("Grain stops banding in the exported movie", .serialized)
struct GrainBandingExportTests {

    static let folder = TestTone.scratch()
    static let canvas = CGSize(width: 1920, height: 1080)

    /// Midnight's own backdrop: a long, dark ramp, the worst case for bands.
    static func backdrop(grain: Bool) -> PhotonzDocument {
        let paint = Paint(hex: "#0B1426", kind: .linear,
                          stops: [GradientStop(hex: "#0B1426", position: 0),
                                  GradientStop(hex: "#1F3B73", position: 1)],
                          angle: 180)
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: paint.hex,
                                        start: .zero, end: CGPoint(x: canvas.width, y: canvas.height))
        content.fill = paint
        var layer = Layer(name: "Background", content: .annotation(content),
                          frame: CGRect(origin: .zero, size: canvas))
        if grain { layer.style.effects = [.grain(GrainEffect())] }
        layer.time = LayerTime(inMS: 0, outMS: 600, sourceInMS: 0)
        var document = PhotonzDocument(canvasSize: canvas, layers: [layer])
        document.durationMS = 600
        return document
    }

    /// The blue channel of the written file at a moment, rows top first.
    static func blue(of url: URL, atSeconds seconds: Double) async throws -> (data: [UInt8], width: Int, height: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let width = frame.width, height = frame.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { bytes in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw TestTone.Failure.noBuffer }
        // Every fourth byte from the third: a plain loop, since a debug build
        // takes most of a second per frame to filter eight megabytes lazily.
        var blue = [UInt8](repeating: 0, count: width * height)
        data.withUnsafeBufferPointer { rgba in
            blue.withUnsafeMutableBufferPointer { out in
                for pixel in 0..<out.count { out[pixel] = rgba[pixel * 4 + 2] }
            }
        }
        return (blue, width, height)
    }

    /// The tallest run of one exact value down each of `columns` columns, the
    /// median of them: how tall a band reads, in rows.
    static func bandHeight(_ picture: (data: [UInt8], width: Int, height: Int), columns: Int = 40) -> Int {
        var runs: [Int] = []
        for step in 0..<columns {
            let x = picture.width / 4 + step * (picture.width / 2) / columns
            var longest = 0, current = 0
            var last: UInt8?
            for y in 40..<(picture.height - 40) {
                let value = picture.data[y * picture.width + x]
                current = value == last ? current + 1 : 1
                last = value
                longest = max(longest, current)
            }
            runs.append(longest)
        }
        return runs.sorted()[runs.count / 2]
    }

    /// The middle band height over every frame of the file.
    static func typicalBandHeight(of url: URL, durationMS: Int, fps: Double) async throws -> (median: Int, frames: [Int]) {
        var heights: [Int] = []
        let frames = Int((Double(durationMS) / 1000 * fps).rounded(.down))
        for frame in 0..<frames {
            // The middle of each frame's time on screen, never its edge.
            let seconds = (Double(frame) + 0.5) / fps
            heights.append(bandHeight(try await blue(of: url, atSeconds: seconds)))
        }
        return (heights.sorted()[heights.count / 2], heights)
    }

    @Test("A dark gradient written plain bands in tall steps; with Grain the steps break up")
    func grainBreaksUpBands() async throws {
        var heights: [Bool: Int] = [:]
        for grain in [false, true] {
            let drawing = Self.backdrop(grain: grain)
            // The 1080p file the Export sheet writes, drawn at the file's
            // size as the app draws it (`EditorState.writeVideo`).
            let plan = DocumentVideoExport.plan(durationMS: 600, canvasSize: Self.canvas,
                                                format: .mp4, quality: .high, size: .p1080)
            let out = Self.folder.appendingPathComponent(grain ? "banding-grain.mp4" : "banding-plain.mp4")
            try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out) { ms in
                DocumentRenderer().render(drawing.drawn(atTimeMS: ms), store: ImageStore())
            }
            let read = try await Self.typicalBandHeight(of: out, durationMS: 600, fps: plan.fps)
            heights[grain] = read.median
            print("[banding] \(grain ? "with grain" : "plain"), frame by frame: \(read.frames)")
        }
        let plain = heights[false] ?? 0, grainy = heights[true] ?? 0
        print("[banding] 1920x1080 MP4, Midnight's ramp, tallest run of one blue value (median of 40 columns, "
              + "middle frame): plain \(plain) rows, with grain \(grainy) rows")
        #expect(plain >= 30, "plain ramp band height \(plain)")
        // Grain has to take a quarter off the bands. Measured 2026-10-14, the
        // middle frame against plain: the default amount 0.50 on a quiet
        // encoder and 0.68 with other suites encoding beside it (the encoder
        // writes a different file then, its first frames 30 to 32 rows);
        // amount 20 0.56; amount 16 0.83 and amount 12 1.0, grain the encoder
        // has all but wiped out. The line used to be two thirds, which the
        // busy encoder crossed about one full test run in three.
        #expect(grainy * 4 <= plain * 3, "grain left bands \(grainy) rows tall against \(plain)")
    }
}
