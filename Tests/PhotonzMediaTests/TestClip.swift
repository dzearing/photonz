import AVFoundation
import CoreGraphics
import Foundation

/// Synthesizes small, real MP4s so the media tests can assert on actual assets
/// (duration, pixel size) instead of on bookkeeping. Written at 30fps by
/// `AVAssetWriter`.
///
/// Every frame carries its own frame number, painted as a row of black and
/// white stripes: stripe *n* is white when bit *n* of the frame number is set.
/// Read the stripes back and you know exactly which moment of the SOURCE a
/// frame came from, which is how the cut tests prove a dropped piece is really
/// gone instead of only proving the file came out the right length.
///
/// It used to be a colour ramp read back as a brightness value, and that is a
/// measurement of the colour pipeline, not of the cut: an H.264 round trip
/// moves a saturated colour by as much as 0.26 out of 1 depending on how the
/// file happens to be colour-tagged, and on 2026-09-15 that put the build
/// machine's runs permanently red while the same code passed here. Black and
/// white survive any of it: whatever a machine does with colour matrices,
/// ranges and gamma, black stays near 0 and white stays near 1.
enum TestClip {

    /// Frames a second. Every clip is written at this rate, so a frame number
    /// converts straight to a moment of the recording.
    static let fps = 30

    /// How many stripes carry the frame number. Ten bits counts to 1023, about
    /// 34 seconds at 30fps, which is far longer than any clip written here.
    static let codeBits = 10

    /// A scratch folder unique to the calling test, removed by `cleanUp`.
    static func makeScratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotonzMediaTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Write an H.264 MP4 of `seconds` at `size`, 30fps.
    static func write(to url: URL, seconds: Double, size: CGSize = CGSize(width: 160, height: 120)) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frames = max(1, Int((seconds * Double(fps)).rounded()))
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makePixelBuffer(pool: pool, size: size, index: index) else {
                continue
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index),
                                                               timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        // The clip's duration is the last frame's presentation time plus one
        // frame, so end the session explicitly rather than trusting the default.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))
        await writer.finishWriting()
        if writer.status == .failed, let error = writer.error { throw error }
    }

    /// One frame: its number written across the picture in black and white
    /// stripes, low bit on the left.
    private static func makePixelBuffer(pool: CVPixelBufferPool, size: CGSize,
                                        index: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: base,
                                  width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        let stripe = size.width / CGFloat(codeBits)
        for bit in 0..<codeBits where (index >> bit) & 1 == 1 {
            ctx.fill(CGRect(x: CGFloat(bit) * stripe, y: 0, width: stripe, height: size.height))
        }
        return buffer
    }

    /// A frame number read back out of a picture of a frame.
    struct FrameCode: Sendable {
        /// The frame's number in the SOURCE recording it was written into.
        let index: Int
        /// The moment of that recording, in seconds.
        let seconds: Double
        /// How far the least convincing stripe sat from the black/white
        /// midpoint, 0...0.5. A clean read is near 0.5; a small number means
        /// the picture no longer carries a legible code and the reading should
        /// not be trusted.
        let margin: Double
    }

    /// Which frame of the source the picture shown at `seconds` of `url` is.
    /// Nil when there is no frame there at all.
    static func frameCode(at seconds: Double, in url: URL) async -> FrameCode? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let image = try? await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return nil }
        return frameCode(of: image)
    }

    /// The stripe code painted into one frame.
    static func frameCode(of image: CGImage) -> FrameCode? {
        let width = image.width
        guard width >= codeBits * 2 else { return nil }
        var row = [UInt8](repeating: 0, count: width * 4)
        let drew = row.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: width, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Squash the frame to a single row: each stripe runs the full
            // height, so nothing is lost and encoder noise averages out.
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: 1))
            return true
        }
        guard drew else { return nil }

        var index = 0
        var margin = 0.5
        for bit in 0..<codeBits {
            // The middle of the stripe, so a blurred edge between two stripes
            // never decides a bit.
            let x = Int((Double(bit) + 0.5) * Double(width) / Double(codeBits))
            let level = Double(row[x * 4]) / 255.0
            if level > 0.5 { index |= 1 << bit }
            margin = min(margin, abs(level - 0.5))
        }
        return FrameCode(index: index, seconds: Double(index) / Double(fps), margin: margin)
    }

    /// Seconds of the asset at `url` (0 when unreadable).
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite else { return 0 }
        return seconds
    }
}
