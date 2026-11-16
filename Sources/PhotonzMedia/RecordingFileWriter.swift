import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os
import PhotonzCore
import VideoToolbox

/// Writes a screen recording's file from the stream's own frames and sound,
/// the way `RecordingPictures` says: 10-bit HEVC in Display P3 on the sRGB
/// curve, with the matrix the stream really encodes in.
///
/// macOS's own writer (`SCRecordingOutput`) takes no colour or bit rate
/// settings and tags its files 709 / 709 / 709 whatever the frames hold, so
/// every recording played lighter and greener than the screen, and banded.
/// The stream's 10-bit frames carry no colour tags at all, and its 8-bit ones
/// say the 709 curve though they hold sRGB-curve values; either way an
/// encoder told something else converts them wrongly. So every frame is told
/// what it really holds (`tag`) before it is written, and the file says the
/// same, and nothing converts on the way.
///
/// The file starts at the first frame appended. Frames and sound may arrive on
/// different queues; everything the writer touches is behind one lock.
public final class RecordingFileWriter: @unchecked Sendable {
    // @unchecked: the writer, its inputs and the counters are only touched
    // under `lock`.

    public enum WriterError: Error { case couldNotWrite }

    public let url: URL
    private let lock = OSAllocatedUnfairLock()
    private let writer: AVAssetWriter
    private let pictures: AVAssetWriterInput
    /// Frames go in as pixel buffers, never as the stream's own samples: a
    /// sample carries a description of its frame made before the frame was
    /// tagged, and the writer stops the moment one frame's description
    /// differs from the first (-16364).
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let sound: AVAssetWriterInput?
    private var started = false
    private var finishing = false
    private var firstSeconds: Double?
    private var framesWritten = 0
    private var framesMissed = 0

    /// `pixelSize` is the stream's frame size; `withSound` adds a sound track
    /// for one source (the Mac's sound or the microphone).
    public init(url: URL, pixelSize: CGSize, fps: Int, withSound: Bool,
                quality: RecordingQuality = .best) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(pixelSize.width.rounded()), height = Int(pixelSize.height.rounded())
        pictures = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: Self.colourProperties,
            AVVideoCompressionPropertiesKey: Self.compression(quality, pixelSize: pixelSize, fps: fps),
        ])
        pictures.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: pictures, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(pictures) else { throw WriterError.couldNotWrite }
        writer.add(pictures)
        if withSound {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: RecordingPictures.soundSampleRate,
                AVNumberOfChannelsKey: RecordingPictures.soundChannels,
                AVEncoderBitRateKey: RecordingPictures.soundBitsPerSecond,
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw WriterError.couldNotWrite }
            writer.add(input)
            sound = input
        } else {
            sound = nil
        }
        guard writer.startWriting() else { throw writer.error ?? WriterError.couldNotWrite }
    }

    static func compression(_ quality: RecordingQuality, pixelSize: CGSize, fps: Int) -> [String: Any] {
        var props: [String: Any] = [
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoExpectedSourceFrameRateKey: fps,
            // Two seconds between key frames, so a scrub never decodes far.
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: false,
            kVTCompressionPropertyKey_RealTime as String: true,
        ]
        switch RecordingPictures.compression(quality, pixelSize: pixelSize, fps: fps) {
        case .averageBitsPerSecond(let rate): props[AVVideoAverageBitRateKey] = rate
        case .quality(let q): props[AVVideoQualityKey] = q
        }
        return props
    }

    /// What the file says it holds.
    static let colourProperties: [String: String] = [
        AVVideoColorPrimariesKey: RecordingPictures.colourPrimaries,
        AVVideoTransferFunctionKey: RecordingPictures.transferFunction,
        AVVideoYCbCrMatrixKey: RecordingPictures.yCbCrMatrix,
    ]

    /// Tell a frame of the stream what it really holds. Idempotent; the
    /// stream never reads a frame back once it has handed it over.
    public static func tag(_ buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey,
                              RecordingPictures.colourPrimaries as CFString, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                              RecordingPictures.transferFunction as CFString, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey,
                              RecordingPictures.yCbCrMatrix as CFString, .shouldPropagate)
    }

    /// Why the file stopped being written, if it did.
    public var failure: Error? { lock.withLock { writer.status == .failed ? writer.error : nil } }

    /// The host-clock time of the first frame written, once there is one.
    public var firstFrameSeconds: Double? { lock.withLock { firstSeconds } }

    /// Frames written, and frames the encoder was not ready for.
    public var frameCounts: (written: Int, missed: Int) { lock.withLock { (framesWritten, framesMissed) } }

    /// Write one of the stream's frames. The first one starts the file.
    @discardableResult
    public func append(picture sample: CMSampleBuffer) -> Bool {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return false }
        Self.tag(buffer)
        let at = CMSampleBufferGetPresentationTimeStamp(sample)
        guard at.isValid else { return false }
        // Unchecked: the sample is handed straight to the writer under the
        // lock and never kept.
        return lock.withLockUnchecked {
            guard !finishing, writer.status == .writing else { return false }
            if !started {
                writer.startSession(atSourceTime: at)
                started = true
                firstSeconds = at.seconds
            }
            guard pictures.isReadyForMoreMediaData else {
                framesMissed += 1
                return false
            }
            let ok = adaptor.append(buffer, withPresentationTime: at)
            if ok { framesWritten += 1 }
            return ok
        }
    }

    /// Write some of the stream's sound. Sound heard before the first frame
    /// is not the recording's, and is left out.
    public func append(sound sample: CMSampleBuffer) {
        lock.withLockUnchecked {
            guard let sound, started, !finishing, writer.status == .writing,
                  sound.isReadyForMoreMediaData else { return }
            sound.append(sample)
        }
    }

    /// Close the file. True when it closed with at least one frame in it.
    public func finish() async -> Bool {
        let begun: Bool = lock.withLock {
            guard !finishing else { return false }
            finishing = true
            pictures.markAsFinished()
            sound?.markAsFinished()
            return started
        }
        guard begun else {
            writer.cancelWriting()
            return false
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        return writer.status == .completed
    }

    /// Give up on the file and remove it.
    public func abandon() {
        let wasWriting: Bool = lock.withLock {
            let was = !finishing
            finishing = true
            return was
        }
        if wasWriting { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The pixel format a movie's frames are best decoded to: 10-bit 4:2:0 for a
/// 10-bit file (decoding it to 8 bits put the bands straight back, 45 across
/// a ramp that has 70), and the usual 8-bit 4:2:0 for everything else.
public enum MovieDecodeFormat {
    public static func pixelFormat(for format: CMFormatDescription) -> OSType {
        StoredWay.bitDepth(of: format) > 8
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }
}
