import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import PhotonzMedia

/// The writers' picture buffers come from a pool the writer owns, never from
/// the adaptor's own pool read frame by frame.
///
/// The adaptor swaps its pool for a new one a few frames into every write, and
/// the encoder frees the old one on its own thread while the swap is under way.
/// A frame asked of the adaptor's pool in that moment is drawn from a pool that
/// is being torn down, and the process dies (`EXC_BAD_ACCESS` at 0x0 inside
/// `CVPixelBufferPool::createPixelBuffer`). A full test run died that way on
/// 2026-11-22, and asking the adaptor for its pool from a second thread during
/// the first ten frames of eight writes at once killed the test helper in the
/// first round every time it was tried.
@Suite struct WriterFramePoolTests {

    private static func writer(size: CGSize, attributes: [String: Any])
        throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-frame-pool-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: attributes)
        writer.add(input)
        return (writer, input, adaptor, url)
    }

    @Test("a frame from the writer's own pool is the adaptor's format and size, on a surface")
    func framesMatchTheAdaptor() throws {
        let size = CGSize(width: 320, height: 200)
        let (_, _, adaptor, _) = try Self.writer(size: size, attributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        let pool = try #require(WriterFramePool.make(for: adaptor))
        let frame = try #require(WriterFramePool.frame(from: pool))
        #expect(CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32ARGB)
        #expect(CVPixelBufferGetWidth(frame) == 320)
        #expect(CVPixelBufferGetHeight(frame) == 200)
        #expect(CVPixelBufferGetIOSurface(frame) != nil, "the encoder takes a surface without a copy")
    }

    @Test("an adaptor that names no format gets no pool")
    func noFormatNoPool() throws {
        let (_, _, adaptor, _) = try Self.writer(size: CGSize(width: 64, height: 64), attributes: [:])
        #expect(WriterFramePool.make(for: adaptor) == nil)
    }

    @Test("one pool fills a whole write, every frame there")
    func oneFillsAWholeWrite() async throws {
        let size = CGSize(width: 320, height: 200)
        let (writer, input, adaptor, url) = try Self.writer(size: size, attributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let pool = try #require(WriterFramePool.make(for: adaptor))
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let frame = try #require(WriterFramePool.frame(from: pool))
            #expect(adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 30, timescale: 30))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        #expect(abs(await TestClip.duration(of: url) - 1.0) < 0.01)
    }
}
