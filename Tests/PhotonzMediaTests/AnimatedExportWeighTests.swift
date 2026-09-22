import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **The Export sheet weighs a GIF by writing one, so the number it shows has
/// to be the number that lands.**
///
/// A video's weight is arithmetic. An animated picture has none: sampling eight
/// frames from across a recording, encoding just those and multiplying came out
/// between 100 and 400 per cent over on every clip measured, because ImageIO
/// spends a fraction as much on a frame that follows a frame like it and a
/// sample of frames from far apart has no such frames in it. Taking runs of
/// consecutive frames instead swung from 76 per cent under to 120 per cent
/// over, depending on the material and the format. There is no formula here.
///
/// So the sheet writes a scratch copy while it is open, says what that weighed,
/// and hands the very same file to Export. That is only honest if writing the
/// same recording twice gives a file of the same size, which is what this
/// measures. It does, for both formats and every preset: a GIF is identical to
/// the byte, and a HEIC is identical in size with one byte of the video
/// encoder's own state moving inside it. An MP4 is neither, which is why a
/// video is weighed from its budget instead (`VideoExportBudgetTests`).
@Suite("An animated export weighs the same twice", .serialized)
struct AnimatedExportWeighTests {

    static let folder = TestTone.scratch()

    static func bytes(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// A screen-like recording: fine still detail like a window full of words,
    /// with one block moving over it, and for `stillAfter` seconds onwards
    /// nothing moving at all. Both halves matter — a still stretch is where
    /// every sampling shortcut went wrong.
    static func screenSource(seconds: Int, size: CGSize, stillAfter: Double) async throws -> URL {
        let url = folder.appendingPathComponent("screen-\(seconds)s-\(Int(size.width)).mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let plan = DocumentVideoExport.plan(durationMS: seconds * 1000, canvasSize: size,
                                            format: .mp4, quality: .high)
        let width = Int(plan.size.width), height = Int(plan.size.height)
        let frames: DocumentMovieWriter.FrameSource = { ms in
            guard let ctx = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let t = min(Double(ms) / 1000, stillAfter)
            ctx.setFillColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1)
            for row in 0..<20 {
                let y = Double(row) * Double(height) / 22 + 4
                var x = 12.0
                var word = 0
                while x < Double(width) - 30 {
                    let w = Double(18 + (row * 7 + word * 13) % 60)
                    ctx.fill(CGRect(x: x, y: y, width: w, height: 4))
                    x += w + 8
                    word += 1
                }
            }
            let travel = max(40, Double(width) - 120)
            let shift = (t * 90).truncatingRemainder(dividingBy: travel)
            ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
            ctx.fill(CGRect(x: shift, y: Double(height) / 3, width: 100, height: 70))
            return ctx.makeImage()
        }
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: url,
                                            frames: frames)
        return url
    }

    /// Every preset, on a short recording and on a longer one that is still for
    /// half its length, written twice: the same size both times.
    ///
    /// This is the promise the sheet makes when it drops the word "about" for a
    /// GIF. It also checks the presets really are three different sizes, since
    /// a number that never moved with the choice would be no use on the row.
    @Test("written twice, an animated export lands at the same size")
    func theSameFileTwice() async throws {
        for (label, seconds, size, stillAfter) in [
            ("short", 2, CGSize(width: 640, height: 400), 99.0),
            ("longer", 6, CGSize(width: 960, height: 600), 3.0),
        ] {
            let source = try await Self.screenSource(seconds: seconds, size: size,
                                                     stillAfter: stillAfter)
            let trim = VideoTrim(duration: await VideoExporter.duration(of: source))
            for format in [RecordingFormat.gif, .heic] {
                var landed: [VideoExportQuality: Int] = [:]
                for quality in VideoExportQuality.allCases {
                    var written: [Data] = []
                    for pass in 0..<2 {
                        let out = Self.folder.appendingPathComponent(
                            "\(label)-\(format.rawValue)-\(quality.rawValue)-\(pass)."
                                + format.fileExtension)
                        try await VideoExporter.exportAnimated(
                            from: source, to: out, format: format, trim: trim, crop: nil,
                            targetFPS: quality.targetFPS, maxDimension: quality.maxDimension)
                        written.append(try Data(contentsOf: out))
                    }
                    let drift = "\(label) \(format.rawValue) at \(quality.rawValue) came out "
                        + "\(written[0].count) bytes and then \(written[1].count): "
                        + "the sheet cannot promise a size it cannot reproduce"
                    #expect(written[0].count == written[1].count, "\(drift)")
                    // A GIF is the same file down to the byte. A HEIC is the
                    // same SIZE and moves a single byte inside the first frame
                    // — measured at offset 1123 of a 295,520 byte file, 0x76
                    // one time and 0x80 the next — which is the video encoder's
                    // own state and not anything about the picture. The size is
                    // what the sheet promises, so the size is what is claimed
                    // here for both, and the stronger claim is made where it
                    // holds.
                    if format == .gif {
                        #expect(written[0] == written[1], "\(drift)")
                    }
                    landed[quality] = written[0].count
                }
                let high = try #require(landed[.high])
                let standard = try #require(landed[.standard])
                let small = try #require(landed[.small])
                let row = "\(label) \(format.rawValue) came out \(high)/\(standard)/\(small) "
                    + "bytes at High/Standard/Small, so the preset row does not move the size"
                #expect(small < standard && standard < high, "\(row)")
            }
        }
    }

    /// The document's own writer, which is what the editor window's sheet
    /// weighs with: the same promise, from frames drawn rather than read off a
    /// file.
    @Test("a document written twice as a GIF is byte for byte the same file")
    func thedocumentWriterTwice() async throws {
        let plan = DocumentVideoExport.plan(durationMS: 1500,
                                            canvasSize: CGSize(width: 480, height: 300),
                                            format: .gif, quality: .standard)
        let frames: DocumentMovieWriter.FrameSource = { ms in
            guard let ctx = CGContext(data: nil, width: Int(plan.size.width),
                                      height: Int(plan.size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: plan.size))
            ctx.setFillColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
            let x = Double(ms) / 1500 * (Double(plan.size.width) - 80)
            ctx.fill(CGRect(x: x, y: 40, width: 80, height: 60))
            return ctx.makeImage()
        }
        var written: [Data] = []
        for pass in 0..<2 {
            let out = Self.folder.appendingPathComponent("doc-\(pass).gif")
            try await DocumentMovieWriter.writeAnimated(plan: plan, format: .gif, to: out,
                                                        frames: frames)
            written.append(try Data(contentsOf: out))
        }
        #expect(written[0] == written[1],
                "the document came out \(written[0].count) bytes and then \(written[1].count)")
    }

    /// Weighing has to be stoppable, because it runs while somebody is looking
    /// at a sheet they can close at any moment. Stopping takes the scratch file
    /// with it, so a cancelled weigh leaves nothing behind to be found later
    /// and mistaken for an export.
    @Test("a weigh that is stopped leaves no file behind")
    func stoppingLeavesNothing() async throws {
        let source = try await Self.screenSource(seconds: 6, size: CGSize(width: 960, height: 600),
                                                 stillAfter: 3)
        let trim = VideoTrim(duration: await VideoExporter.duration(of: source))
        let out = Self.folder.appendingPathComponent("stopped.gif")
        let job = Task {
            try await VideoExporter.exportAnimated(from: source, to: out, format: .gif,
                                                   trim: trim, crop: nil,
                                                   targetFPS: VideoExportQuality.high.targetFPS,
                                                   maxDimension: VideoExportQuality.high.maxDimension)
        }
        try await Task.sleep(for: .milliseconds(200))
        job.cancel()
        _ = try? await job.value
        #expect(!FileManager.default.fileExists(atPath: out.path),
                "a stopped weigh left \(Self.bytes(of: out)) bytes at \(out.lastPathComponent)")
    }
}
