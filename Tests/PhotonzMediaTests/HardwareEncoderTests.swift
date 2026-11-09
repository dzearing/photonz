import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing
import VideoToolbox

/// **An MP4 is written on the Mac's hardware encoder, or waits for it.**
///
/// The hardware H.264 encoder takes 32 sessions at once across the whole Mac
/// (measured 2026-11-09: one process holding 24 left a second process 8). A
/// writer started past that is handed the software encoder without a word,
/// and the software encoder does not keep to a budget (`MovieCompression`), so
/// the file lands far heavier than the Export sheet said. That is what made
/// the size checks in `BusyVideoSizeTests` fail only inside a full test run,
/// where the parallel video suites hold more than 32 sessions between them.
@Suite("An MP4 waits for the hardware encoder rather than going without it", .serialized)
struct HardwareEncoderTests {

    /// Every hardware session still free on the Mac, taken until one comes
    /// back as software. Let go when the value is dropped.
    final class HeldEncoders: @unchecked Sendable {
        private(set) var sessions: [VTCompressionSession] = []

        init() {
            for _ in 0..<64 {
                guard let session = Self.open() else { break }
                guard Self.onHardware(session) else {
                    VTCompressionSessionInvalidate(session)
                    break
                }
                sessions.append(session)
            }
        }

        func release() {
            for session in sessions { VTCompressionSessionInvalidate(session) }
            sessions = []
        }

        deinit { release() }

        private static func open() -> VTCompressionSession? {
            var made: VTCompressionSession?
            guard VTCompressionSessionCreate(
                allocator: nil, width: 640, height: 400, codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil, imageBufferAttributes: nil,
                compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                compressionSessionOut: &made) == noErr, let session = made else { return nil }
            // A session settles on its encoder once it has a frame to encode.
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 640, 400, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
            if let buffer {
                VTCompressionSessionEncodeFrame(session, imageBuffer: buffer,
                                                presentationTimeStamp: .zero, duration: .invalid,
                                                frameProperties: nil, infoFlagsOut: nil) { _, _, _ in }
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            }
            return session
        }

        private static func onHardware(_ session: VTCompressionSession) -> Bool {
            var value: CFTypeRef?
            VTSessionCopyProperty(session,
                                  key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                                  allocator: nil, valueOut: &value)
            return (value as? Bool) == true
        }
    }

    static let size = CGSize(width: 640, height: 400)

    /// Fast fine text at Small: the hardware encoder lands it near the budget,
    /// the software one at several times it.
    static func frames(_ plan: VideoFramePlan) -> DocumentMovieWriter.FrameSource {
        VideoExportBudgetTests.scrollingFrames(size: plan.size, pixelsPerSecond: 900)
    }

    @Test("A write started while every hardware session is taken lands what a quiet Mac writes")
    func aWriteWaitsForTheHardwareEncoder() async throws {
        let folder = VideoExportBudgetTests.folder
        let plan = DocumentVideoExport.plan(durationMS: 2000, canvasSize: Self.size,
                                            format: .mp4, quality: .small)
        let quiet = folder.appendingPathComponent("quiet-\(UUID().uuidString).mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: quiet,
                                            frames: Self.frames(plan))
        let source = folder.appendingPathComponent("source-\(UUID().uuidString).mp4")
        try await DocumentMovieWriter.write(
            plan: DocumentVideoExport.plan(durationMS: 2000, canvasSize: Self.size,
                                           format: .mp4, quality: .high),
            mix: [], soundURLs: [:], to: source, frames: Self.frames(plan))
        let recipe = VideoExportQuality.small.recipe(format: .mp4, sourceSize: Self.size,
                                                     sourceFPS: 30)
        let cuts = VideoExportBudgetTests.wholeOf(source, seconds: 2)
        let exportedQuietly = folder.appendingPathComponent("exported-quiet-\(UUID().uuidString).mp4")
        try await VideoExporter.exportMP4(from: source, to: exportedQuietly, cuts: cuts, crop: nil,
                                          recipe: recipe)

        let held = HeldEncoders()
        try #require(!held.sessions.isEmpty, "no hardware encoder session could be taken")
        let busy = folder.appendingPathComponent("busy-\(UUID().uuidString).mp4")
        let exportedBusy = folder.appendingPathComponent("exported-busy-\(UUID().uuidString).mp4")
        let documentWrite = Task {
            try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: busy,
                                                frames: Self.frames(plan))
        }
        let recordingWrite = Task {
            try await VideoExporter.exportMP4(from: source, to: exportedBusy, cuts: cuts, crop: nil,
                                              recipe: recipe)
        }
        try await Task.sleep(for: .milliseconds(1500))
        held.release()
        try await documentWrite.value
        try await recordingWrite.value

        let quietBytes = VideoExportBudgetTests.bytes(of: quiet)
        let busyBytes = VideoExportBudgetTests.bytes(of: busy)
        #expect(BusyVideoSizeTests.near(busyBytes, quietBytes),
                "a document written while the encoder was taken landed \(busyBytes), quietly \(quietBytes)")
        let quietExport = VideoExportBudgetTests.bytes(of: exportedQuietly)
        let busyExport = VideoExportBudgetTests.bytes(of: exportedBusy)
        #expect(BusyVideoSizeTests.near(busyExport, quietExport),
                "a recording exported while the encoder was taken landed \(busyExport), quietly \(quietExport)")
    }

    @Test("Only a busy encoder is waited for: the error a full hardware encoder gives is told apart")
    func busyIsToldApart() {
        let busy = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -12903),
        ])
        #expect(HardwareEncoder.isBusy(busy))
        let full = NSError(domain: NSOSStatusErrorDomain, code: -12915)
        #expect(HardwareEncoder.isBusy(full))
        let diskFull = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28),
        ])
        #expect(!HardwareEncoder.isBusy(diskFull))
        #expect(!HardwareEncoder.isBusy(nil))
    }
}
