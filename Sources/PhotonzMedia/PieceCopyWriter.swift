import AVFoundation
import CoreMedia
import Foundation
import PhotonzCore
import VideoToolbox

// Writing an edit that is nothing but cuts by COPYING what it keeps
// (`CutCopy.swift` says when that is, and which frames go across untouched).
//
// The document writer photographs every moment and encodes every photograph
// again: about seventy five seconds for a three minute Retina recording with a
// few pieces cut out (measured 2026-10-07). Copying the stretches it keeps, and
// encoding again only the handful of frames between a cut and the next key
// frame, wrote the same edit in about a second.
//
// Three things it is careful about, each measured on a real recording:
//
// - **The clock.** A recording's frames are stamped a couple of frames late in
//   the file and an edit list pulls them back; the timeline, the canvas and
//   every decoded frame are on the pulled-back clock. The cut points are moved
//   onto the file's clock before anything is planned, so a cut at 4.20s keeps
//   the frame the timeline shows at 4.20s, not the one two frames before it.
// - **Colour.** Copied frames keep the recording's own colour tags, and the
//   frames made again are told the same ones, so a join is never a step in
//   brightness.
// - **The sound** is not copied: it is the document's mix, written by exactly
//   the code the full path uses (`AudioMixdown`) and laid beside the pictures
//   by the same join, so it is the same sound either way.
public enum PieceCopyWriter {

    /// What a copy did: how many frames went across untouched and how many
    /// were made again.
    public struct Outcome: Sendable, Hashable {
        public let copiedFrames: Int
        public let renderedFrames: Int
    }

    public enum CopyError: Error {
        /// The file is not one this can copy from (an unusual codec, an edit
        /// list it does not follow, groups of frames that lean on each other).
        /// The caller writes the edit the ordinary way instead.
        case notCopyable(String)
        /// Something went wrong part way.
        case failed(String)
    }

    /// Write `ranges` of the recording at `source` (each a stretch of its
    /// timeline clock, in milliseconds, in play order) back to back as an MP4,
    /// with `mix` under it.
    ///
    /// Throws `CopyError.notCopyable` before anything is written when the file
    /// cannot be copied from; the caller then takes the ordinary path.
    /// Cancelling the task stops it and removes what was written.
    @discardableResult
    public static func write(source: URL, ranges: [Range<Int>],
                             mix: [AudioMixSegment], soundURLs: [UUID: URL],
                             to destination: URL,
                             onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> Outcome {
        let recording = try await Recording.load(source)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-copy-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try? FileManager.default.removeItem(at: destination)

        let silent = scratch.appendingPathComponent("picture.mp4")
        let pictureShare = mix.isEmpty ? 1.0 : 0.6
        let stop = StopFlag()
        do {
            let outcome = try await withTaskCancellationHandler {
                try await OffThePool.run {
                    try writePictures(of: recording, ranges: ranges, to: silent, stop: stop) { done in
                        onProgress?(done * pictureShare)
                    }
                }
            } onCancel: { stop.raise() }
            try Task.checkCancellation()
            guard !mix.isEmpty else {
                try FileManager.default.moveItem(at: silent, to: destination)
                onProgress?(1)
                return outcome
            }
            let sound = scratch.appendingPathComponent("sound.m4a")
            try await AudioMixdown.write(mix, urls: soundURLs, to: sound)
            try Task.checkCancellation()
            onProgress?(0.9)
            try await DocumentMovieWriter.join(picture: silent, sound: sound, to: destination)
            onProgress?(1)
            return outcome
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: - The recording, read before anything is written

    /// Everything known about the source before a frame is written.
    struct Recording: @unchecked Sendable {
        // `AVAssetTrack` and the format description are not marked Sendable;
        // this is handed whole to the one queue that writes, and nothing else
        // touches it after (the same promise `HandedTrack` makes).
        let asset: AVURLAsset
        let track: AVAssetTrack
        let format: CMFormatDescription
        let transform: CGAffineTransform
        /// The clock every time here is counted on: one both a millisecond and
        /// a tick of the file divide exactly.
        let clock: CMTimeScale
        /// How far the file's own clock runs ahead of the timeline's, in ticks.
        let editOffset: Int64
        /// Every frame, in decode order, on the file's own clock.
        let frames: [CutCopyPlan.StoredFrame]
        let dataRate: Float

        static func load(_ url: URL) async throws -> Recording {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw CopyError.notCopyable("it has no picture")
            }
            let formats = try await track.load(.formatDescriptions)
            guard formats.count == 1, let format = formats.first else {
                throw CopyError.notCopyable("its pictures are stored more than one way")
            }
            let codec = CMFormatDescriptionGetMediaSubType(format)
            guard codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC else {
                throw CopyError.notCopyable("its pictures are not H.264 or HEVC")
            }
            // One stretch of the file played straight through, which is what
            // a recording is. Anything else is an edit this does not follow.
            let segments = try await track.load(.segments)
            guard segments.count == 1, let segment = segments.first, !segment.isEmpty,
                  CMTimeCompare(segment.timeMapping.source.duration,
                                segment.timeMapping.target.duration) == 0
            else { throw CopyError.notCopyable("its picture is itself an edit") }
            let natural = Int64(try await track.load(.naturalTimeScale))
            guard natural > 0 else { throw CopyError.notCopyable("it has no clock") }
            let common = natural / greatestDivisor(natural, 1000) * 1000
            guard common <= Int64(Int32.max) else { throw CopyError.notCopyable("its clock is too fine") }
            let clock = CMTimeScale(common)
            guard let offset = ticks(CMTimeSubtract(segment.timeMapping.source.start,
                                                    segment.timeMapping.target.start), on: clock)
            else { throw CopyError.notCopyable("its edit list has no offset") }
            guard let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else {
                throw CopyError.notCopyable("its frames cannot be listed")
            }
            var frames: [CutCopyPlan.StoredFrame] = []
            repeat {
                guard let shows = ticks(cursor.presentationTimeStamp, on: clock),
                      let decodes = ticks(cursor.decodeTimeStamp, on: clock)
                else { throw CopyError.notCopyable("a frame has no time") }
                frames.append(CutCopyPlan.StoredFrame(
                    showsAt: shows, decodesAt: decodes,
                    isKey: cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue))
            } while cursor.stepInDecodeOrder(byCount: 1) == 1
            return Recording(asset: asset, track: track, format: format,
                             transform: try await track.load(.preferredTransform),
                             clock: clock, editOffset: offset, frames: frames,
                             dataRate: try await track.load(.estimatedDataRate))
        }

        /// The timeline's clock (what a reader's range and a decoded frame
        /// are on) for a moment of the file's own.
        func timelineTime(_ fileTicks: Int64) -> CMTime {
            CMTime(value: fileTicks - editOffset, timescale: clock)
        }
    }

    static func ticks(_ time: CMTime, on clock: CMTimeScale) -> Int64? {
        guard time.isNumeric else { return nil }
        return CMTimeConvertScale(time, timescale: clock, method: .roundHalfAwayFromZero).value
    }

    private static func greatestDivisor(_ a: Int64, _ b: Int64) -> Int64 {
        b == 0 ? a : greatestDivisor(b, a % b)
    }

    // MARK: - Writing the pictures

    /// The plan for `ranges` of the recording, or `notCopyable`.
    static func plan(for recording: Recording, ranges: [Range<Int>]) throws -> CutCopyPlan {
        let perMS = Int64(recording.clock) / 1000
        let pieces = ranges.map {
            (Int64($0.lowerBound) * perMS + recording.editOffset)
                ..< (Int64($0.upperBound) * perMS + recording.editOffset)
        }
        guard let plan = CutCopyPlan.make(frames: recording.frames, pieces: pieces) else {
            throw CopyError.notCopyable("its frames cannot be cut without drawing them")
        }
        return plan
    }

    /// The kept frames into a silent MP4. Blocks: run it off the shared pool.
    static func writePictures(of recording: Recording, ranges: [Range<Int>], to destination: URL,
                              stop: StopFlag,
                              onProgress: ((Double) -> Void)?) throws -> Outcome {
        let plan = try plan(for: recording, ranges: ranges)
        let clock = recording.clock
        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                       sourceFormatHint: recording.format)
        input.expectsMediaDataInRealTime = false
        input.transform = recording.transform
        input.mediaTimeScale = clock
        guard writer.canAdd(input) else { throw CopyError.failed("the file will not take the pictures") }
        writer.add(input)
        guard writer.startWriting() else {
            throw CopyError.failed(writer.error.map(String.init(describing:)) ?? "it would not start")
        }
        writer.startSession(atSourceTime: .zero)

        let total = Double(max(1, plan.placed.count))
        var written = 0
        // Said in two hundredths: a copy writes thousands of frames a second,
        // and a bar cannot show a finer step than that, so nothing downstream
        // is asked to redraw for each one.
        var said = -1
        func append(_ sample: CMSampleBuffer, as placed: CutCopyPlan.Placed) throws {
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: placed.lastsFor, timescale: clock),
                presentationTimeStamp: CMTime(value: placed.showsAt, timescale: clock),
                decodeTimeStamp: CMTime(value: placed.decodesAt, timescale: clock))
            var retimed: CMSampleBuffer?
            guard CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample,
                                                        sampleTimingEntryCount: 1,
                                                        sampleTimingArray: &timing,
                                                        sampleBufferOut: &retimed) == noErr,
                  let retimed else { throw CopyError.failed("a frame could not be moved") }
            while !input.isReadyForMoreMediaData {
                if stop.isRaised { throw CancellationError() }
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard input.append(retimed) else {
                throw CopyError.failed(writer.error.map(String.init(describing:)) ?? "a frame was refused")
            }
            written += 1
            let step = Int(Double(written) / total * 200)
            if step != said {
                said = step
                onProgress?(Double(written) / total)
            }
        }

        do {
            var reader: CompressedFrames?
            for run in plan.runs {
                if stop.isRaised { throw CancellationError() }
                switch run {
                case .copy(let frames):
                    guard let first = frames.first?.index else { continue }
                    if reader?.canReach(first) != true {
                        reader = try CompressedFrames(recording, from: first)
                    }
                    for placed in frames {
                        guard let sample = try reader?.sample(at: placed.index) else { continue }
                        try append(sample, as: placed)
                    }
                case .render(let group, let frames):
                    let made = try render(recording, group: group, frames: frames)
                    for (sample, placed) in zip(made, frames) { try append(sample, as: placed) }
                }
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: plan.durationTicks, timescale: clock))
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw CopyError.failed(writer.error.map(String.init(describing:)) ?? "it did not finish")
        }
        return Outcome(copiedFrames: plan.copiedFrames, renderedFrames: plan.renderedFrames)
    }

    /// One group of frames decoded, and the ones listed encoded afresh in the
    /// order they show, opening on a key frame of their own, without
    /// reordering and with the recording's own colour tags.
    ///
    /// The bit rate is twice the recording's average, with a floor: these are
    /// a second of frames at most, so it costs nothing worth weighing, and a
    /// join is never a visible step down in sharpness.
    private static func render(_ recording: Recording, group: Range<Int>,
                               frames: [CutCopyPlan.Placed]) throws -> [CMSampleBuffer] {
        let wanted = Set(frames.map { recording.frames[$0.index].showsAt })
        let shows = group.map { recording.frames[$0].showsAt }
        guard let from = shows.min(), let last = shows.max(), !wanted.isEmpty else { return [] }
        let reader = try AVAssetReader(asset: recording.asset)
        reader.timeRange = CMTimeRange(start: recording.timelineTime(from),
                                       end: recording.timelineTime(last + 1))
        let output = AVAssetReaderTrackOutput(track: recording.track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw CopyError.failed("its frames could not be decoded") }
        reader.add(output)
        guard reader.startReading() else { throw CopyError.failed("its frames could not be decoded") }
        defer { reader.cancelReading() }

        let size = CMVideoFormatDescriptionGetDimensions(recording.format)
        let codec = CMFormatDescriptionGetMediaSubType(recording.format)
        var made: VTCompressionSession?
        guard VTCompressionSessionCreate(allocator: nil, width: size.width, height: size.height,
                                         codecType: codec, encoderSpecification: nil,
                                         imageBufferAttributes: nil, compressedDataAllocator: nil,
                                         outputCallback: nil, refcon: nil,
                                         compressionSessionOut: &made) == noErr,
              let session = made
        else { throw CopyError.failed("no encoder for its frames") }
        defer { VTCompressionSessionInvalidate(session) }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: 100_000 as CFNumber)
        if codec == kCMVideoCodecType_H264 {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                                 value: kVTProfileLevel_H264_High_AutoLevel)
        }
        let rate = max(Double(recording.dataRate) * 2, 4_000_000)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: rate as CFNumber)
        let tags = CMFormatDescriptionGetExtensions(recording.format) as? [CFString: Any] ?? [:]
        for (tag, property) in [
            (kCMFormatDescriptionExtension_ColorPrimaries, kVTCompressionPropertyKey_ColorPrimaries),
            (kCMFormatDescriptionExtension_TransferFunction, kVTCompressionPropertyKey_TransferFunction),
            (kCMFormatDescriptionExtension_YCbCrMatrix, kVTCompressionPropertyKey_YCbCrMatrix),
        ] {
            if let value = tags[tag] { VTSessionSetProperty(session, key: property, value: value as CFTypeRef) }
        }
        VTCompressionSessionPrepareToEncodeFrames(session)

        let encoded = EncodedFrames()
        var fed = 0
        while fed < wanted.count, let sample = output.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            let at = CMSampleBufferGetPresentationTimeStamp(sample)
            guard let fileTicks = ticks(at, on: recording.clock).map({ $0 + recording.editOffset }),
                  wanted.contains(fileTicks) else { continue }
            let options = fed == 0
                ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
            let status = VTCompressionSessionEncodeFrame(
                session, imageBuffer: image, presentationTimeStamp: at, duration: .invalid,
                frameProperties: options, infoFlagsOut: nil) { status, _, buffer in
                    encoded.add(status: status, buffer)
                }
            guard status == noErr else { throw CopyError.failed("a frame could not be encoded (\(status))") }
            fed += 1
        }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        let samples = try encoded.inShowingOrder()
        guard samples.count == wanted.count else {
            throw CopyError.failed("\(samples.count) of \(wanted.count) frames came out of the encoder")
        }
        return samples
    }
}

/// The recording's compressed frames, read front to back from a key frame and
/// handed over by their place in decode order.
private final class CompressedFrames {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let indexOfDecode: [Int64: Int]
    private let clock: CMTimeScale
    private var position: Int

    init(_ recording: PieceCopyWriter.Recording, from index: Int) throws {
        reader = try AVAssetReader(asset: recording.asset)
        reader.timeRange = CMTimeRange(start: recording.timelineTime(recording.frames[index].showsAt),
                                       duration: .positiveInfinity)
        output = AVAssetReaderTrackOutput(track: recording.track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw PieceCopyWriter.CopyError.failed("its frames could not be read") }
        reader.add(output)
        guard reader.startReading() else { throw PieceCopyWriter.CopyError.failed("its frames could not be read") }
        var map: [Int64: Int] = [:]
        for (i, frame) in recording.frames.enumerated() { map[frame.decodesAt] = i }
        indexOfDecode = map
        clock = recording.clock
        position = index
    }

    /// Whether a frame is still ahead of this reader.
    func canReach(_ index: Int) -> Bool { index >= position }

    func sample(at index: Int) throws -> CMSampleBuffer {
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0,
                  let decodes = PieceCopyWriter.ticks(CMSampleBufferGetDecodeTimeStamp(sample), on: clock),
                  let at = indexOfDecode[decodes] else { continue }
            position = at + 1
            if at == index { return sample }
            if at > index { break }
        }
        throw PieceCopyWriter.CopyError.failed("frame \(index) of the recording never came")
    }

    deinit { reader.cancelReading() }
}

/// What the encoder hands back, from its own thread.
private final class EncodedFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [CMSampleBuffer] = []
    private var failure: OSStatus = noErr

    func add(status: OSStatus, _ buffer: CMSampleBuffer?) {
        lock.lock(); defer { lock.unlock() }
        if status != noErr { failure = status }
        if let buffer { frames.append(buffer) }
    }

    func inShowingOrder() throws -> [CMSampleBuffer] {
        lock.lock(); defer { lock.unlock() }
        guard failure == noErr else { throw PieceCopyWriter.CopyError.failed("the encoder failed (\(failure))") }
        return frames.sorted {
            CMTimeCompare(CMSampleBufferGetPresentationTimeStamp($0),
                          CMSampleBufferGetPresentationTimeStamp($1)) < 0
        }
    }
}

/// Raised when the task writing is cancelled, read by the queue doing the
/// writing between frames.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return raised }
    func raise() { lock.lock(); raised = true; lock.unlock() }
}
