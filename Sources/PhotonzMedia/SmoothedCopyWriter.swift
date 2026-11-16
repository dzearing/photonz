import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import PhotonzCore
import Synchronization
import VideoToolbox

/// Writing a recording (or the stretches an edit of cuts keeps) back out as
/// the SAME kind of file, with every frame passed through a picture filter on
/// the way: what a top quality export of a recording does when the recording's
/// soft gradients are drawn in steps (`RecordingSmoothing`, which the app hands
/// in as `filter`).
///
/// A copy of the file (`PieceCopyWriter`, or the whole file copied) keeps the
/// steps the Mac drew, so QuickTime and Safari show bands Photonz does not.
/// This decodes at the recording's own depth, runs the filter on the GPU, and
/// encodes again at the same depth, codec, colours and data rate:
///
/// - **Depth.** A 10-bit recording is read and written at 10 bits, so a smooth
///   ramp between two 8-bit shades needs no grain to survive: four 10-bit codes
///   sit between every pair of 8-bit shades. Grain does not survive the
///   encoder, so none is added: the file holds the ramp in steps of one code.
/// - **Codec and colours.** HEVC Main 10 for a 10-bit recording, the
///   recording's own colour tags, so the file plays in the same colours as the
///   copy it replaces.
/// - **Size.** Asked for by quality, not rate (`quality` says why): the user's
///   recording came out a quarter of the size of the copy.
///
/// The sound is the document's mix, written and joined exactly as the copy
/// writes it (`PieceCopyWriter`).
public enum SmoothedCopyWriter {

    /// A frame's picture in, the picture to write out. Called off the main
    /// thread, one frame at a time.
    public typealias Filter = @Sendable (CIImage) -> CIImage

    public enum WriteError: Error {
        /// The recording is not one this writes (no picture, an unusual codec).
        /// The caller takes another route.
        case notWritable(String)
        /// Something went wrong part way.
        case failed(String)
        /// No picture came out of the recording for `readStallLimit`, twice.
        case readerStalled
    }

    /// Whether the recording at `url` stores its picture deeper than 8 bits:
    /// the only kind worth writing out smoothed, since an 8-bit file rounds a
    /// grain-free ramp straight back into the steps it had.
    public static func isDeep(_ url: URL) async -> Bool {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let format = try? await track.load(.formatDescriptions).first else { return false }
        return StoredWay.bitDepth(of: format) > 8
    }

    /// Write `ranges` of the recording at `source` (each a stretch of its
    /// timeline clock in milliseconds, in play order; nil for all of it) as an
    /// MP4 at `destination`, every frame through `filter`, with `mix` under it.
    /// Returns how many frames were written. Cancelling stops it and removes
    /// what was written.
    @discardableResult
    public static func write(source: URL, ranges: [Range<Int>]?,
                             mix: [AudioMixSegment], soundURLs: [UUID: URL],
                             filter: @escaping Filter,
                             to destination: URL,
                             onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> Int {
        let recording = try await Recording.load(source, ranges: ranges)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-smoothed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try? FileManager.default.removeItem(at: destination)

        let silent = scratch.appendingPathComponent("picture.mp4")
        let pictureShare = mix.isEmpty ? 1.0 : 0.9
        // The bar never runs backwards when a stalled pass goes again.
        let furthest = Mutex<Double>(-1)
        let forward: @Sendable (Double) -> Void = { done in
            let moved = furthest.withLock { far in
                guard done > far else { return false }
                far = done
                return true
            }
            if moved { onProgress?(done * pictureShare) }
        }
        do {
            // One re-encode at a time across the app (`ExportQueue`).
            await ExportQueue.shared.enter()
            let frames: Int
            do {
                // A stalled read gets one more go with a fresh reader, and so
                // a fresh decoder session (`readStallLimit`).
                do {
                    frames = try await writePictures(of: recording, filter: filter, to: silent,
                                                     onProgress: forward)
                } catch WriteError.readerStalled {
                    try Task.checkCancellation()
                    frames = try await writePictures(of: recording, filter: filter, to: silent,
                                                     onProgress: forward)
                }
            } catch {
                await ExportQueue.shared.leave()
                throw error
            }
            await ExportQueue.shared.leave()
            try Task.checkCancellation()
            guard !mix.isEmpty else {
                try FileManager.default.moveItem(at: silent, to: destination)
                onProgress?(1)
                return frames
            }
            let sound = scratch.appendingPathComponent("sound.m4a")
            try await AudioMixdown.write(mix, urls: soundURLs, to: sound)
            try Task.checkCancellation()
            try await DocumentMovieWriter.join(picture: silent, sound: sound, to: destination)
            onProgress?(1)
            return frames
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// What the encoder is asked for: a QUALITY, not a rate, with spatial
    /// adaptive quantisation off. Measured 2026-11-16 on the user's 9.3 s
    /// Retina recording (104 Mbps, 121 MB), the hardware HEVC encoder:
    ///
    /// - asked for the recording's own 104 Mbps, wrote about 9 Mbps, and the
    ///   terminal text came back up to 19 ten-bit codes off (99th percentile);
    /// - asked for a quality, ignored it whenever a rate limit was also set;
    /// - with its adaptive quantisation on, flattened a slow ramp to one value
    ///   per 32 px block with jumps of two and three codes, and kept or lost
    ///   added grain by chance (21 px flat at half a shade, 70 at a whole one);
    ///   off, it holds the ramp as steps of one code, a quarter of the shade
    ///   the Mac drew.
    ///
    /// At 0.9: 32 MB, text 9 codes off at the 99th percentile, the same as a
    /// plain re-encode with nothing smoothed and invisible at three times the
    /// size; 0.95 gave 8 codes at 75 MB, 0.8 gave 11 at 10 MB.
    static let quality = 0.9

    static func videoSettings(codec: CMVideoCodecType, tenBit: Bool, width: Int, height: Int,
                              fps: Double, colours: [String: String]) -> [String: Any] {
        let hevc = codec == kCMVideoCodecType_HEVC
        var compression: [String: Any] = [
            AVVideoQualityKey: quality,
            // A key frame every two seconds, so the file scrubs.
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoAllowFrameReorderingKey: true,
            kVTCompressionPropertyKey_SpatialAdaptiveQPLevel as String: kVTQPModulationLevel_Disable,
        ]
        if fps > 0 { compression[AVVideoExpectedSourceFrameRateKey] = Int(fps.rounded()) }
        if hevc {
            compression[AVVideoProfileLevelKey] = tenBit
                ? kVTProfileLevel_HEVC_Main10_AutoLevel as String
                : kVTProfileLevel_HEVC_Main_AutoLevel as String
        } else {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        var settings: [String: Any] = [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        if !colours.isEmpty { settings[AVVideoColorPropertiesKey] = colours }
        return settings
    }

    // MARK: - The recording

    struct Recording: @unchecked Sendable {
        // `AVAsset` and the format description are not marked Sendable; this
        // is handed whole to the one queue that writes, and nothing else
        // touches it after (the same promise `PieceCopyWriter.Recording` makes).
        let reading: AVAsset
        let track: AVAssetTrack
        let format: CMFormatDescription
        let transform: CGAffineTransform
        let duration: CMTime
        let fps: Float

        static func load(_ url: URL, ranges: [Range<Int>]?) async throws -> Recording {
            let asset = AVURLAsset(url: url)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw WriteError.notWritable("it has no picture")
            }
            let formats = try await sourceTrack.load(.formatDescriptions)
            guard let format = formats.first else { throw WriteError.notWritable("its picture has no format") }
            let codec = CMFormatDescriptionGetMediaSubType(format)
            guard codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC else {
                throw WriteError.notWritable("its pictures are not H.264 or HEVC")
            }
            let transform = try await sourceTrack.load(.preferredTransform)
                let fps = try await sourceTrack.load(.nominalFrameRate)
            guard let ranges else {
                return Recording(reading: asset, track: sourceTrack, format: format, transform: transform,
                                 duration: try await asset.load(.duration), fps: fps)
            }
            // The kept stretches back to back, on the timeline's clock (the
            // asset's, edit list applied), which is the clock every range here
            // is counted on.
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw WriteError.failed("no room for its picture") }
            var cursor = CMTime.zero
            for range in ranges where !range.isEmpty {
                let time = CMTimeRange(start: CMTime(value: CMTimeValue(range.lowerBound), timescale: 1000),
                                       end: CMTime(value: CMTimeValue(range.upperBound), timescale: 1000))
                try track.insertTimeRange(time, of: sourceTrack, at: cursor)
                cursor = CMTimeAdd(cursor, time.duration)
            }
            guard cursor.seconds > 0 else { throw WriteError.notWritable("it keeps nothing") }
            return Recording(reading: composition, track: track, format: format, transform: transform,
                             duration: cursor, fps: fps)
        }
    }

    /// One CIContext for every write: compiling its pipeline is the slow part
    /// of the first frame.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    private static func writePictures(of recording: Recording, filter: @escaping Filter,
                                      to destination: URL,
                                      onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        let format = recording.format
        let pixelFormat = MovieDecodeFormat.pixelFormat(for: format)
        let tenBit = StoredWay.bitDepth(of: format) > 8
        let size = CMVideoFormatDescriptionGetDimensions(format)
        let codec = CMFormatDescriptionGetMediaSubType(format)
        let tags = CMFormatDescriptionGetExtensions(format) as? [CFString: Any] ?? [:]
        var colours: [String: String] = [:]
        for (tag, key) in [
            (kCMFormatDescriptionExtension_ColorPrimaries, AVVideoColorPrimariesKey),
            (kCMFormatDescriptionExtension_TransferFunction, AVVideoTransferFunctionKey),
            (kCMFormatDescriptionExtension_YCbCrMatrix, AVVideoYCbCrMatrixKey),
        ] {
            if let value = tags[tag] as? String { colours[key] = value }
        }
        // All three or none: the writer refuses a partial set.
        if colours.count != 3 { colours = [:] }
        let settings = videoSettings(codec: codec, tenBit: tenBit,
                                     width: Int(size.width), height: Int(size.height),
                                     fps: Double(recording.fps), colours: colours)

        let (writer, (input, adaptor)) = try await HardwareEncoder.start(
            at: destination, wouldNotStart: { error in
                WriteError.failed(error.map(String.init(describing:)) ?? "the encoder would not start")
            }
        ) { hardware in
            let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
            var settings = settings
            if hardware { settings[AVVideoEncoderSpecificationKey] = HardwareEncoder.required }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            input.transform = recording.transform
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                    kCVPixelBufferWidthKey as String: Int(size.width),
                    kCVPixelBufferHeightKey as String: Int(size.height),
                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                ])
            guard writer.canAdd(input) else { throw WriteError.failed("the encoder would not take it") }
            writer.add(input)
            return (writer, (input, adaptor))
        }
        return try await pump(recording, pixelFormat: pixelFormat,
                              handed: Handed(writer: writer, input: input, adaptor: adaptor),
                              filter: filter, onProgress: onProgress)
    }

    /// The writer and its inputs, and the reader feeding them. None of them
    /// is marked Sendable; each read happens on the guard's one serial queue
    /// while this waits, and clean-up is queued behind it (`GuardedReads`).
    private struct Handed: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    private struct HandedReader: @unchecked Sendable {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
    }

    private struct HandedSample: @unchecked Sendable {
        let sample: CMSampleBuffer?
    }

    /// A read that has not answered for this long has stalled: the same
    /// limit, and the same one retry with a fresh reader, as the recording's
    /// own export (`VideoExporter.retryingAStalledRead`). A full test run on
    /// 2026-11-16 caught this writer's read sitting for good under load.
    static let readStallLimit = VideoExporter.readStallLimit

    private static func pump(_ recording: Recording, pixelFormat: OSType, handed: Handed,
                             filter: Filter,
                             onProgress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        let writer = handed.writer, input = handed.input, adaptor = handed.adaptor
        let reader = try AVAssetReader(asset: recording.reading)
        let output = AVAssetReaderTrackOutput(track: recording.track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { writer.cancelWriting(); throw WriteError.failed("its frames could not be decoded") }
        reader.add(output)
        guard reader.startReading() else { writer.cancelWriting(); throw WriteError.failed("its frames could not be decoded") }
        writer.startSession(atSourceTime: .zero)

        let reads = GuardedReads(label: "photonz.smoothed-copy.pictures", limit: readStallLimit)
        let handedReader = HandedReader(reader: reader, output: output)
        func giveUp() {
            // Stopping a reader that is stuck is stuck too: queued behind the read.
            reads.afterwards {
                handedReader.reader.cancelReading()
                handed.writer.cancelWriting()
            }
        }
        let total = max(0.001, recording.duration.seconds)
        var written = 0
        while true {
            let next: HandedSample
            do {
                next = try await reads.run { HandedSample(sample: handedReader.output.copyNextSampleBuffer()) }
            } catch {
                giveUp()
                if error is GuardedReads.Stalled { throw WriteError.readerStalled }
                throw error
            }
            guard let sample = next.sample else { break }
            if Task.isCancelled { giveUp(); throw CancellationError() }
            guard let decoded = CMSampleBufferGetImageBuffer(sample) else { continue }
            let at = CMSampleBufferGetPresentationTimeStamp(sample)
            // Wait for the encoder to be hungry, without ever waiting for good.
            let giveUpAt = Date().addingTimeInterval(90)
            while !input.isReadyForMoreMediaData {
                if Task.isCancelled { giveUp(); throw CancellationError() }
                guard writer.status == .writing, Date() < giveUpAt else {
                    giveUp()
                    throw WriteError.failed(writer.error.map(String.init(describing:))
                                            ?? "the encoder stopped taking pictures")
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { giveUp(); throw WriteError.failed("no room for a frame") }
            var made: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess,
                  let ours = made else { giveUp(); throw WriteError.failed("no room for a frame") }
            render(decoded, through: filter, into: ours)
            guard adaptor.append(ours, withPresentationTime: at) else {
                giveUp()
                throw WriteError.failed(writer.error.map(String.init(describing:)) ?? "a frame was refused")
            }
            written += 1
            onProgress(min(0.99, at.seconds / total))
        }
        if reader.status == .failed {
            giveUp()
            throw WriteError.failed(reader.error.map(String.init(describing:)) ?? "the recording stopped reading")
        }
        guard written > 0 else { giveUp(); throw WriteError.failed("no frame came out of it") }
        input.markAsFinished()
        writer.endSession(atSourceTime: recording.duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw WriteError.failed(writer.error.map(String.init(describing:)) ?? "it did not finish")
        }
        return written
    }

    /// One decoded frame through `filter` into `destination`, which takes the
    /// frame's own colour tags first so the conversion back to YCbCr is the
    /// exact reverse of the one in.
    static func render(_ decoded: CVPixelBuffer, through filter: Filter, into destination: CVPixelBuffer) {
        if let tags = CVBufferCopyAttachments(decoded, .shouldPropagate) {
            CVBufferSetAttachments(destination, tags, .shouldPropagate)
        }
        let colours = CVImageBufferCreateColorSpaceFromAttachments(
            CVBufferCopyAttachments(decoded, .shouldPropagate) ?? [:] as CFDictionary)?.takeRetainedValue()
        let image = CIImage(cvPixelBuffer: decoded)
        let extent = image.extent
        let filtered = filter(image).cropped(to: extent)
        context.render(filtered, to: destination, bounds: extent,
                       colorSpace: colours ?? CGColorSpace(name: CGColorSpace.displayP3))
    }
}
