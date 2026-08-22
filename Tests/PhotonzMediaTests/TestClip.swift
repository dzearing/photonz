import AVFoundation
import CoreGraphics
import Foundation

/// Synthesizes small, real MP4s so the media tests can assert on actual assets
/// (duration, pixel size) instead of on bookkeeping. Each clip is a solid-colour
/// gradient that shifts over time, written at 30fps by `AVAssetWriter`.
enum TestClip {

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

        let fps = 30
        let frames = max(1, Int((seconds * Double(fps)).rounded()))
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makePixelBuffer(pool: pool, size: size, index: index, of: frames) else {
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

    /// A brightness ramp, so a trimmed clip's frames are visibly distinguishable
    /// from the source's opening frames if a test ever wants to check content.
    private static func makePixelBuffer(pool: CVPixelBufferPool, size: CGSize,
                                        index: Int, of total: Int) -> CVPixelBuffer? {
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
        let level = CGFloat(index) / CGFloat(max(1, total - 1))
        ctx.setFillColor(red: level, green: 1 - level, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        return buffer
    }

    /// Seconds of the asset at `url` (0 when unreadable).
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite else { return 0 }
        return seconds
    }
}
