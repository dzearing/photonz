import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing
import VideoToolbox

/// A recording written back out with its soft gradients smoothed
/// (`SmoothedCopyWriter` with `RecordingSmoothing` as its filter): what a top
/// quality export of a banded recording now is, so QuickTime and Safari play
/// the ramp Photonz shows instead of the Mac's 8-bit steps.
@Suite("Writing a recording out smoothed")
struct SmoothedCopyWriterTests {

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Scripts/playtest/fixtures")

    /// 1280 x 800, two seconds of a dark gradient drawn in 8-bit steps, stored
    /// the way the Mac stores a recording now: HEVC Main 10.
    static let banded = fixtures.appendingPathComponent("Banded dark gradient recording 1280x800.mp4")

    /// What the app hands the writer: the pass, no grain (the encoder drops it).
    static let filter: SmoothedCopyWriter.Filter = { image in
        RecordingSmoothing.smoothed(image, reach: RecordingSmoothing.reachInRecordingPixels, grain: false)
    }

    /// The gradient's column in the fixture, above and below its one-pixel
    /// line at y 500.
    static func gradient(of url: URL, at seconds: Double) async throws -> [Double] {
        try await column(of: url, at: seconds, x: 640, rows: 0..<492)
            + column(of: url, at: seconds, x: 640, rows: 509..<800)
    }

    /// The green channel down column `x` of the frame at `seconds`, decoded
    /// deep, as fractions of full scale.
    static func column(of url: URL, at seconds: Double, x: Int,
                       rows: Range<Int>? = nil) async throws -> [Double] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        return try greens(of: image, x: x, rows: rows)
    }

    static func greens(of image: CGImage, x: Int, rows: Range<Int>?) throws -> [Double] {
        let w = image.width, h = image.height
        var pixels = [UInt16](repeating: 0, count: w * h * 4)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 16,
                                      bytesPerRow: w * 8, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder16Little.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        try #require(drawn)
        let span = rows ?? 0..<h
        return span.map { y in Double(pixels[(y * w + x) * 4 + 1]) / 65535 }
    }

    /// Each flat run as "start:length@code", for a failure to show where.
    static func runs(_ values: [Double], from first: Int) -> String {
        let codes = BandingReading.codes(values, bits: 10)
        var runs: [String] = [], start = 0
        for i in 1...codes.count where i == codes.count || codes[i] != codes[start] {
            runs.append("\(start + first):\(i - start)@\(codes[start])"); start = i
        }
        return runs.joined(separator: " ")
    }

    /// Every channel of `rect` of the frame at `seconds`, in 10-bit codes.
    static func codes(of url: URL, at seconds: Double, rect: CGRect) async throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let crop = try #require(image.cropping(to: rect))
        let w = crop.width, h = crop.height
        var pixels = [UInt16](repeating: 0, count: w * h * 4)
        let space = try #require(image.colorSpace)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 16,
                                bytesPerRow: w * 8, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                  | CGBitmapInfo.byteOrder16Little.rawValue)
            ctx?.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return pixels.enumerated().filter { $0.offset % 4 != 3 }
            .map { Int((Double($0.element) / 65535 * 1023).rounded()) }
    }

    /// The 99th percentile and the share over one code of |a - b|.
    static func difference(_ a: [Int], _ b: [Int]) -> (p99: Int, overOne: Double, mean: Double) {
        let d = zip(a, b).map { abs($0 - $1) }.sorted()
        guard !d.isEmpty else { return (0, 0, 0) }
        let over = Double(d.filter { $0 > 1 }.count) / Double(d.count)
        let mean = Double(zip(a, b).map { $0 - $1 }.reduce(0, +)) / Double(d.count)
        return (d[Int(Double(d.count - 1) * 0.99)], over, mean)
    }

    static func tenBit(_ values: [Double]) -> BandingReading {
        BandingReading(levels: BandingReading.codes(values, bits: 10))
    }

    /// Only a recording deeper than 8 bits is worth writing out smoothed: an
    /// 8-bit file rounds a grain-free ramp straight back into the same steps.
    @Test("a 10-bit recording is deep, an 8-bit one is not")
    func depth() async throws {
        #expect(await SmoothedCopyWriter.isDeep(Self.banded))
        let scratch = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(scratch) }
        let eightBit = scratch.appendingPathComponent("eight.mp4")
        try await TestClip.write(to: eightBit, seconds: 0.5, size: CGSize(width: 320, height: 200))
        #expect(await SmoothedCopyWriter.isDeep(eightBit) == false)
    }

    @Test("the fixture is banded to begin with")
    func fixtureIsBanded() async throws {
        let reading = Self.tenBit(try await Self.gradient(of: Self.banded, at: 1))
        #expect(reading.longestFlatRun >= 40, "\(reading)")
    }

    @Test("a banded 10-bit recording comes out smooth, 10-bit HEVC, every frame there")
    func smoothsTheFile() async throws {
        try #require(RecordingSmoothing.isAvailable)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoothed-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        let frames = try await SmoothedCopyWriter.write(source: Self.banded, ranges: nil, mix: [], soundURLs: [:],
                                                        filter: Self.filter, to: out)
        #expect(frames == 60)

        // Before: ten flat runs of 80 px, a whole shade (4 codes) apart. After:
        // a ramp in steps of a code or two, none flat for 40 px away from the
        // frame's top and bottom edge, where a ramp has nothing past the edge
        // to lean on (measured 2026-11-16: 12 to 38 px inside, 45 at the ends).
        let column = try await Self.gradient(of: out, at: 1)
        let inside = Self.tenBit(Array(column[60..<(column.count - 60)]))
        #expect(inside.longestFlatRun < 40, "\(inside) \(Self.runs(column, from: 0))")
        #expect(Self.tenBit(column).largestStep <= 2, "\(Self.runs(column, from: 0))")

        let asset = AVURLAsset(url: out)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC)
        #expect(StoredWay.bitDepth(of: format) == 10)
        let size = CMVideoFormatDescriptionGetDimensions(format)
        #expect(size.width == 1280 && size.height == 800)
        let seconds = try await asset.load(.duration).seconds
        #expect(abs(seconds - 2) < 0.05)
    }

    /// The controlled case the task sets the bar on: a full-frame dark grey
    /// gradient of ten 8-bit shades over 1300 px, 130 px a band, stored as
    /// HEVC Main 10 the way the Mac stores a recording now.
    static func staircase(to url: URL, width: Int = 640, height: Int = 1300) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoAverageBitRateKey: 20_000_000,
            ],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let pool = try #require(adaptor.pixelBufferPool)
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            let buffer = try #require(made)
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                let shade = UInt8(40 + min(9, y / (height / 10)))
                let row = base.advanced(by: y * stride)
                for x in 0..<width {
                    row[x * 4] = shade; row[x * 4 + 1] = shade; row[x * 4 + 2] = shade; row[x * 4 + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }

    /// Ten shades over 1300 px is 36 ten-bit codes, 33 px a code on a perfect
    /// ramp; the encoder lays the ramp on its 32 px blocks, so a step lands
    /// 32 to 45 px from the last (measured 2026-11-16). Under 40 px flat
    /// everywhere would take grain, and the encoder drops grain (see
    /// `SmoothedCopyWriter.quality`), so the bar here is the ramp itself: no
    /// step bigger than half a shade and no flat run over 50 px, against
    /// 130 px flat and whole-shade steps before.
    @Test("ten shades over 1300 px come out as a ramp of one-code steps")
    func controlledStaircase() async throws {
        try #require(RecordingSmoothing.isAvailable)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("staircase-\(UUID().uuidString).mp4")
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("staircase-smoothed-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: out)
        }
        try await Self.staircase(to: source)
        // A band in from each end: a ramp has nothing past the frame's edge to
        // lean on, so its first and last half band stay as flat as the shade
        // they are.
        let before = Self.tenBit(try await Self.column(of: source, at: 0.5, x: 320, rows: 130..<1170))
        #expect(before.longestFlatRun >= 100, "\(before)")
        try await SmoothedCopyWriter.write(source: source, ranges: nil, mix: [], soundURLs: [:],
                                           filter: Self.filter, to: out)
        let afterColumn = try await Self.column(of: out, at: 0.5, x: 320, rows: 130..<1170)
        let after = Self.tenBit(afterColumn)
        let runs = Self.runs(afterColumn, from: 130)
        #expect(after.longestFlatRun < 50, "\(after) \(runs)")
        #expect(after.largestStep <= 2, "\(after) \(runs)")
        #expect(after.distinctLevels >= 28, "\(after) \(runs)")
    }

    @Test("a filter that changes nothing changes nothing, line and box included")
    func identityIsFaithful() async throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("identity-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        try await SmoothedCopyWriter.write(source: Self.banded, ranges: nil, mix: [], soundURLs: [:],
                                           filter: { $0 }, to: out)
        let before = BandingReading.codes(try await Self.column(of: Self.banded, at: 1, x: 640), bits: 10)
        let after = BandingReading.codes(try await Self.column(of: out, at: 1, x: 640), bits: 10)
        let difference = Self.difference(before, after)
        #expect(difference.p99 <= 1 && difference.overOne < 0.01, "\(difference)")
    }

    @Test("the stretches an edit keeps, back to back")
    func keepsOnlyTheRanges() async throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ranges-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        try await SmoothedCopyWriter.write(source: Self.banded, ranges: [0..<500, 1000..<1500],
                                           mix: [], soundURLs: [:], filter: Self.filter, to: out)
        let seconds = try await AVURLAsset(url: out).load(.duration).seconds
        #expect(abs(seconds - 1) < 0.05, "\(seconds)")
    }

    /// The user's own recording, when it is on this Mac: what the audit
    /// quotes. Opt in with PHOTONZ_USER_RECORDING=<path to the .mp4>.
    @Test("the user's recording, measured",
          .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_USER_RECORDING"] != nil))
    func usersRecording() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTONZ_USER_RECORDING"])
        let source = URL(fileURLWithPath: path)
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_SMOOTHED_OUT"]
                      ?? NSTemporaryDirectory() + "user-smoothed.mp4")
        let started = Date()
        let frames = try await SmoothedCopyWriter.write(source: source, ranges: nil, mix: [], soundURLs: [:],
                                                        filter: Self.filter, to: out)
        let took = Date().timeIntervalSince(started)
        let before = Self.tenBit(try await Self.column(of: source, at: 3, x: 261, rows: 740..<2040))
        let afterColumn = try await Self.column(of: out, at: 3, x: 261, rows: 740..<2040)
        let after = Self.tenBit(afterColumn)
        print("USER-RUNS \(Self.runs(afterColumn, from: 740))")
        let inBytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let outBytes = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // The filter on the decoded frame itself, before any encoder.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600)).image
        let space = try #require(frame.colorSpace)
        let deep = try #require(CIContext().createCGImage(
            Self.filter(CIImage(cgImage: frame)), from: CGRect(x: 0, y: 0, width: frame.width, height: frame.height),
            format: .RGBA16, colorSpace: space))
        let filtered = Self.tenBit(try Self.greens(of: deep, x: 261, rows: 740..<2040))
        print("USER-RECORDING filtered before encoding \(filtered); frame bits \(frame.bitsPerComponent)")
        let text = CGRect(x: 560, y: 520, width: 1000, height: 580)
        let plain = URL(fileURLWithPath: NSTemporaryDirectory() + "user-plain.mp4")
        let plainStarted = Date()
        try await SmoothedCopyWriter.write(source: source, ranges: nil, mix: [], soundURLs: [:],
                                           filter: { $0 }, to: plain)
        let plainTook = Date().timeIntervalSince(plainStarted)
        let sourceText = try await Self.codes(of: source, at: 3, rect: text)
        let plainText = try await Self.codes(of: plain, at: 3, rect: text)
        let smoothText = try await Self.codes(of: out, at: 3, rect: text)
        print("USER-TEXT source vs smoothed \(Self.difference(sourceText, smoothText)); "
              + "source vs plain re-encode \(Self.difference(sourceText, plainText)); "
              + "plain vs smoothed \(Self.difference(plainText, smoothText)); plain took \(plainTook) s")
        print("USER-RECORDING frames \(frames) took \(String(format: "%.2f", took)) s; "
              + "before \(before); after \(after); bytes \(inBytes) -> \(outBytes)")
    }
}
