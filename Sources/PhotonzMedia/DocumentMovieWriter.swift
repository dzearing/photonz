import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import UniformTypeIdentifiers

// Writing a DOCUMENT out as a video (`docs/design/video.md` §8).
//
// `VideoExporter` writes a recording out: one source file, a cut list and a
// crop, re-timed by AVFoundation. It cannot say a piece carried into a
// different order, a held frame, a piece at double speed, a second sound layer
// with a level line on it or an arrow drawn over the picture, because none of
// those are things one source file can be asked for. This writes the other
// kind of file: **a photograph of the document at every moment, in order.**
//
// The split that makes it small:
//
// - *What the picture at a moment looks like* is not this file's business. The
//   caller hands in a closure that answers it, and in the app that closure is
//   the very renderer the canvas draws with, handed
//   `PhotonzDocument.drawn(atTimeMS:)`. So the exported frame and the frame on
//   screen cannot be two different pictures.
// - *What it sounds like* is not this file's business either. `AudioMixdown`
//   already turns `PhotonzDocument.audioMix()` into a mix with the volume ramps
//   on it, and its own comment said video export would take that unchanged when
//   it arrived. It does: the very function Export Sound calls writes the mix,
//   and this lays it beside the pictures. So a mix that sounds right on its own
//   sounds right in the video, because it IS the same file.
// - *Which moments and how big* is `DocumentVideoExport.plan`, which is pure
//   and tested without writing a file at all.
//
// The last step is a PASSTHROUGH copy of both tracks into one container, so the
// pictures are never compressed twice and the sound is byte for byte the mix.
// (Feeding both into one `AVAssetWriter` would be one pass fewer, and it
// deadlocks: a writer holds one input back until the other catches up, and the
// pictures cannot be interleaved with a mix that is not made yet.)
public enum DocumentMovieWriter {

    /// What a moment of the document looks like. Nil means the frame could not
    /// be made, and the one before it stands in rather than a hole appearing.
    public typealias FrameSource = @Sendable (Int) async -> CGImage?

    public enum WriteError: Error {
        /// A plan with nothing in it: a document with no time.
        case nothingToWrite
        /// AVFoundation would not take the file.
        case writerFailed(String)
        /// Not one frame could be made, so there is no video to write.
        case noFrames
    }

    /// Write the document out as an MP4.
    ///
    /// `onProgress` is called with how much of it is done, nought to one, off
    /// the main actor. Cancelling the task stops the write and takes the
    /// half-written file with it, so a cancelled export leaves the disk as it
    /// found it.
    ///
    /// Three steps, in this order: photograph the document into a silent movie,
    /// write the mix out as one sound file, and lay the two beside each other
    /// in one container without touching either. The last step is a passthrough
    /// copy, so the pictures are never compressed twice and the mix in the file
    /// is byte for byte the mix Export Sound would have written.
    public static func write(plan: VideoFramePlan, mix: [AudioMixSegment],
                             soundURLs: [UUID: URL], to destination: URL,
                             frames: FrameSource,
                             onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !plan.isEmpty else { throw WriteError.nothingToWrite }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try? FileManager.default.removeItem(at: destination)

        let silent = scratch.appendingPathComponent("picture.mp4")
        // The pictures are nearly all of the work, so they are nearly all of
        // the bar. What is left covers the sound and the join.
        let pictureShare = mix.isEmpty ? 1.0 : 0.9
        do {
            try await writeSilentMovie(plan: plan, to: silent, frames: frames) { done in
                onProgress?(done * pictureShare)
            }
            try Task.checkCancellation()
            guard !mix.isEmpty else {
                try FileManager.default.moveItem(at: silent, to: destination)
                onProgress?(1)
                return
            }
            let sound = scratch.appendingPathComponent("sound.m4a")
            try await AudioMixdown.write(mix, urls: soundURLs, to: sound)
            try Task.checkCancellation()
            try await join(picture: silent, sound: sound, to: destination)
            onProgress?(1)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// The document photographed at every moment of the plan, with no sound on
    /// it yet.
    private static func writeSilentMovie(plan: VideoFramePlan, to destination: URL,
                                         frames: FrameSource,
                                         onProgress: (@Sendable (Double) -> Void)?) async throws {
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video,
                                       outputSettings: videoSettings(plan: plan))
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(plan.size.width),
                kCVPixelBufferHeightKey as String: Int(plan.size.height),
            ])
        guard writer.canAdd(input) else {
            throw WriteError.writerFailed("the file will not take a picture track")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw WriteError.writerFailed(
                writer.error.map(String.init(describing:)) ?? "it would not start")
        }
        writer.startSession(atSourceTime: .zero)
        do {
            try await writePictures(plan: plan, frames: frames, writer: writer, input: input,
                                    adaptor: adaptor, onProgress: onProgress)
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        // The last picture stays up until the document ends, so the file runs
        // as long as the document rather than stopping a frame early.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(plan.durationMS),
                                               timescale: 1000))
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw WriteError.writerFailed(
                writer.error.map(String.init(describing:)) ?? "it did not finish")
        }
    }

    /// The picture and the sound in one file, neither of them re-encoded.
    private static func join(picture: URL, sound: URL, to destination: URL) async throws {
        let composition = AVMutableComposition()
        let pictureAsset = AVURLAsset(url: picture)
        guard let source = try? await pictureAsset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw WriteError.writerFailed("the pictures could not be read back") }
        let length = try await pictureAsset.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: length),
                                  of: source, at: .zero)

        let soundAsset = AVURLAsset(url: sound)
        if let heard = try? await soundAsset.loadTracks(withMediaType: .audio).first,
           let lane = composition.addMutableTrack(withMediaType: .audio,
                                                  preferredTrackID: kCMPersistentTrackID_Invalid) {
            let heardLength = (try? await soundAsset.load(.duration)) ?? length
            // Never longer than the picture: a mix that runs past the last
            // frame would leave the file playing a black nothing.
            let kept = CMTimeMinimum(heardLength, length)
            try? lane.insertTimeRange(CMTimeRange(start: .zero, duration: kept),
                                      of: heard, at: .zero)
        }

        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetPassthrough)
        else { throw WriteError.writerFailed("the two could not be put in one file") }
        try await session.export(to: destination, as: .mp4)
    }

    /// Write the same frames out as an animated GIF or HEIC.
    ///
    /// The picture half of the recording export's animated path, aimed at a
    /// document: same planner, same containers, same loop-forever behaviour,
    /// and no sound because neither format can hold any.
    public static func writeAnimated(plan: VideoFramePlan, format: RecordingFormat,
                                     to destination: URL, frames: FrameSource,
                                     onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !plan.isEmpty else { throw WriteError.nothingToWrite }
        guard let utType = animatedUTType(for: format) else {
            throw WriteError.writerFailed("\(format.rawValue) is not an animated picture")
        }
        try? FileManager.default.removeItem(at: destination)
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, utType,
                                                         plan.frameCount, nil) else {
            throw WriteError.writerFailed("the file could not be opened for writing")
        }
        CGImageDestinationSetProperties(dest, containerProperties(for: format) as CFDictionary)
        let frameProps = frameProperties(for: format, delay: plan.frameDelay)

        var wroteAny = false
        for index in 0..<plan.frameCount {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
            guard let picture = await frames(plan.timeMS(at: index)) else { continue }
            CGImageDestinationAddImage(dest, fitted(picture, to: plan.size), frameProps as CFDictionary)
            wroteAny = true
            onProgress?(Double(index + 1) / Double(plan.frameCount))
        }
        guard wroteAny, CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: destination)
            throw WriteError.noFrames
        }
    }

    // MARK: - The picture

    private static func writePictures(plan: VideoFramePlan, frames: FrameSource,
                                      writer: AVAssetWriter,
                                      input: AVAssetWriterInput,
                                      adaptor: AVAssetWriterInputPixelBufferAdaptor,
                                      onProgress: (@Sendable (Double) -> Void)?) async throws {
        let width = Int(plan.size.width), height = Int(plan.size.height)
        var wroteAny = false
        var last: CGImage?
        for index in 0..<plan.frameCount {
            try Task.checkCancellation()
            let picture = await frames(plan.timeMS(at: index)) ?? last
            guard let picture else { continue }
            last = picture
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                // A writer that has given up never becomes hungry again, so
                // without this the export waits for it forever with nothing on
                // screen moving. Say what it said instead.
                guard writer.status == .writing else {
                    throw WriteError.writerFailed(
                        writer.error.map(String.init(describing:))
                            ?? "it stopped taking pictures")
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: picture, pool: pool, width: width, height: height)
            else { continue }
            // Where the picture sits on the file's own clock. Milliseconds,
            // because the document's clock is milliseconds and rounding it into
            // a frame-rate timebase is how a long export drifts.
            let at = CMTime(value: CMTimeValue(plan.timeMS(at: index)), timescale: 1000)
            adaptor.append(buffer, withPresentationTime: at)
            wroteAny = true
            onProgress?(Double(index + 1) / Double(plan.frameCount))
        }
        guard wroteAny else { throw WriteError.noFrames }
        // The last picture is on screen until the document ends, so the file
        // runs as long as the document rather than stopping a frame early.
        input.markAsFinished()
    }

    /// What the encoder is asked for. The budget comes from the plan rather
    /// than being left to AVFoundation, so the Export sheet can say what the
    /// file will weigh before anybody commits to it (`VideoExportRecipe`).
    private static func videoSettings(plan: VideoFramePlan) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(plan.size.width),
            AVVideoHeightKey: Int(plan.size.height),
        ]
        guard plan.videoBitsPerSecond > 0 else { return settings }
        settings[AVVideoCompressionPropertiesKey] = [
            AVVideoAverageBitRateKey: plan.videoBitsPerSecond,
            AVVideoExpectedSourceFrameRateKey: Int(plan.fps.rounded()),
            // A key frame every two seconds, so scrubbing and the preview a
            // chat app builds both land quickly.
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: true,
        ] as [String: Any]
        return settings
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool,
                                    width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // **Clear it first.** Buffers come out of a pool, so the one handed
        // over still holds whatever frame used it last, and a picture is drawn
        // OVER what is there rather than replacing it. Without this, a frame
        // with nothing on it — a document whose music runs past its last clip —
        // comes out as the previous picture, which reads as a freeze frame
        // nobody asked for. A movie has no transparency to keep, so what shows
        // through an empty frame is black.
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(whole)
        // A frame that is not exactly the file's size is drawn to fit it rather
        // than refused: the canvas is the truth about what the picture is, and
        // a rounded-to-even movie size is a pixel off it at most.
        context.interpolationQuality = .high
        context.draw(image, in: whole)
        return buffer
    }

    /// The picture at the size the file wants, where it is not already.
    private static func fitted(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0, image.width != width || image.height != height else { return image }
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: - ImageIO property maps

    private static func animatedUTType(for format: RecordingFormat) -> CFString? {
        switch format {
        case .gif: return UTType.gif.identifier as CFString
        case .heic: return "public.heics" as CFString
        case .mp4: return nil
        }
    }

    private static func containerProperties(for format: RecordingFormat) -> [CFString: Any] {
        switch format {
        case .gif: return [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        case .heic: return [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSLoopCount: 0]]
        case .mp4: return [:]
        }
    }

    private static func frameProperties(for format: RecordingFormat,
                                        delay: TimeInterval) -> [CFString: Any] {
        switch format {
        case .gif:
            return [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]]
        case .heic:
            return [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSUnclampedDelayTime: delay]]
        case .mp4:
            return [:]
        }
    }
}
