import AVFoundation
import CoreGraphics
import ImageIO
import PhotonzCore
import UniformTypeIdentifiers

/// Reads frames out of a recorded MP4 to produce: a poster thumbnail for the
/// history bin (phase 12.4), and animated GIF / HEIC re-encodes (phase 12.5).
/// The *how many frames, what size, what delay* decision is the tested
/// `AnimatedExportPlanner` (PhotonzCore); this is the AVFoundation / ImageIO shell.
extension RecordingFormat {
    /// The save-panel content type for this output format.
    public var savePanelType: UTType {
        switch self {
        case .mp4: return .mpeg4Movie
        case .gif: return .gif
        case .heic: return .heic
        }
    }
}

/// One video re-encode at a time, for the whole app.
///
/// Encoding is one piece of hardware however many windows ask for it, so a
/// second export started while the first is running gains nothing and costs
/// something real: the two compete for decoders and buffer pools, and the
/// symptom is not slowness but an export that stops moving. Whoever is second
/// waits here, and their bar sits at nought until their turn, which is the
/// honest picture of what is happening.
actor ExportQueue {
    static let shared = ExportQueue()

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard busy else { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        guard !waiting.isEmpty else { busy = false; return }
        waiting.removeFirst().resume()
    }
}

public enum VideoExporter {

    /// Recording length in seconds.
    public static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite else { return 0 }
        return seconds
    }

    /// The video's natural pixel size **after** its `preferredTransform` (so a
    /// portrait recording reports portrait dimensions). Used by the in-app
    /// editor's crop overlay (phase 13.3/13.4). Falls back to `.zero` if the
    /// track can't be read.
    public static func orientedNaturalSize(of url: URL) async -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return .zero }
        let oriented = natural.applying(transform)
        return CGSize(width: abs(oriented.width), height: abs(oriented.height))
    }

    /// The video's nominal frame rate (fps), for frame-accurate ←/→ stepping in
    /// the editor. Falls back to 30 if the track can't be read or reports 0.
    public static func frameRate(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let fps = try? await track.load(.nominalFrameRate), fps > 0 else { return 30 }
        return Double(fps)
    }

    /// Whether the recording carries any sound at all, which is the difference
    /// between a budget for pictures and a budget for both.
    public static func hasAudio(of url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false
    }

    /// A representative frame for the history thumbnail — sampled a hair into
    /// the clip so it isn't a black first frame. The stored file is the truth
    /// (phase 19): a saved trim/crop is already baked in, so there is nothing to
    /// re-apply here.
    public static func posterFrame(of url: URL, maxDimension: CGFloat = 600) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let seconds = await duration(of: url)
        let at = CMTime(seconds: min(0.2, seconds / 2), preferredTimescale: 600)
        return try? await generator.image(at: at).image
    }

    public enum ExportError: Error {
        case noDestination, generationFailed, noVideoTrack, exportFailed
        /// AVFoundation stopped taking media part way through, and what it said
        /// about why.
        case writerGaveUp(String)
        /// The file was written but AVFoundation would not finish it.
        case didNotFinish(String)
    }

    /// Re-encode the recording at `url` to an animated GIF or HEIC at
    /// `destination`, honoring an optional `trim` window and `crop` region
    /// (phase 13.5). No-op-safe for `.mp4` (callers shouldn't ask, but we guard
    /// anyway). `crop.rect` is in oriented natural-video pixels, top-left origin
    /// — the same space `AVAssetImageGenerator` produces with
    /// `appliesPreferredTrackTransform = true`, so the crop is applied directly
    /// with `cropping(to:)` before the down-scale to `plan.size`.
    /// `onProgress(completedFrames, totalFrames)` fires after each frame is
    /// appended, so a caller can surface GIF-prep progress. It's invoked off the
    /// main actor (this whole function runs off-main) — hop before touching UI.
    public static func exportAnimated(from url: URL, to destination: URL,
                               format: RecordingFormat,
                               trim: VideoTrim? = nil, crop: VideoCrop? = nil,
                               cuts: VideoCutList? = nil,
                               targetFPS: Double = 15, maxDimension: CGFloat = 800,
                               onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: url)
        let seconds = await duration(of: url)
        let naturalSize = await orientedNaturalSize(of: url)
        let resolvedTrim = trim ?? VideoTrim(duration: seconds)

        // Cuts win when present: they can say everything a trim can, and a trim
        // cannot say "drop the middle".
        let plan = cuts.map {
            AnimatedExportPlanner.plan(cuts: $0, crop: crop, sourceSize: naturalSize,
                                       targetFPS: targetFPS, maxDimension: maxDimension)
        } ?? AnimatedExportPlanner.plan(trim: resolvedTrim, crop: crop,
                                        sourceSize: naturalSize,
                                        targetFPS: targetFPS, maxDimension: maxDimension)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // With a crop we must keep full resolution until after cropping; without
        // one, let the generator down-scale straight to the output size.
        if crop == nil { generator.maximumSize = plan.size }

        guard let utType = animatedUTType(for: format),
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, utType,
                                                         plan.frameCount, nil)
        else { throw ExportError.noDestination }

        // Loop forever; per-frame delay carries the timing.
        let containerProps = containerProperties(for: format)
        CGImageDestinationSetProperties(dest, containerProps as CFDictionary)

        let frameProps = frameProperties(for: format, delay: plan.frameDelay)
        let cropRect = crop.map { Geometry.pixelAligned($0.rect) }
        var wroteAny = false
        for index in 0..<plan.frameCount {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
            let time = CMTime(seconds: plan.sampleTime(index), preferredTimescale: 600)
            guard var frame = try? await generator.image(at: time).image else { continue }
            if let cropRect, let cropped = frame.cropping(to: cropRect) {
                frame = scaled(cropped, to: plan.size) ?? cropped
            }
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
            wroteAny = true
            onProgress?(index + 1, plan.frameCount)
        }
        guard wroteAny, CGImageDestinationFinalize(dest) else { throw ExportError.generationFailed }
    }

    /// Re-export an MP4 honoring trim + crop (phase 13.5).
    public static func exportMP4(from url: URL, to destination: URL,
                          trim: VideoTrim, crop: VideoCrop?,
                          recipe: VideoExportRecipe? = nil) async throws {
        let seconds = await duration(of: url)
        let (start, length) = trim.timeRange(duration: seconds)
        let cuts = VideoCutList(pieces: [VideoPiece(start: start, end: start + length)],
                                sourceDuration: seconds)
        try await exportMP4(from: url, to: destination, cuts: cuts, crop: crop, recipe: recipe)
    }

    /// Re-export an MP4 of a recording that has been cut into pieces: every kept
    /// stretch is inserted into one composition, in order, so the exported file
    /// plays exactly what the editor plays — the dropped pieces simply are not
    /// in it, and the joins are ordinary frame boundaries.
    ///
    /// **What it spends is asked for rather than left to AVFoundation.** This
    /// used to run at `AVAssetExportPresetHighestQuality`, which is an opaque
    /// target: the app could not say what would come out, so the Export sheet
    /// could only offer a ratio and hope. Handed a `recipe` it encodes at that
    /// pixel size, that frame rate and that number of bits per second, which is
    /// what lets the sheet promise a size before anybody commits to it, and
    /// what makes Standard and Small mean something on a video
    /// (`VideoExportRecipe`). With no recipe it keeps the recording's own size
    /// and frame rate at the top budget.
    ///
    /// `onProgress` is called with how far through it is, nought to one, off
    /// the main actor. Cancelling the task stops the encode and takes the
    /// half-written file with it.
    public static func exportMP4(from url: URL, to destination: URL,
                          cuts: VideoCutList, crop: VideoCrop?,
                          recipe: VideoExportRecipe? = nil,
                          onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let preferred = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let natural = (try? await videoTrack.load(.naturalSize)) ?? .zero

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.noVideoTrack
        }
        // Audio for A/V sync, when present — cut at the same points as the
        // picture, so sound never drifts off what is on screen.
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        let compAudio = audioTrack == nil ? nil : composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for piece in cuts.sourceRanges {
            let range = CMTimeRange(start: CMTime(seconds: piece.start, preferredTimescale: 600),
                                    duration: CMTime(seconds: piece.length, preferredTimescale: 600))
            guard range.duration.seconds > 0 else { continue }
            try compVideo.insertTimeRange(range, of: videoTrack, at: cursor)
            if let audioTrack, let compAudio {
                try? compAudio.insertTimeRange(range, of: audioTrack, at: cursor)
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }
        guard cursor.seconds > 0 else { throw ExportError.exportFailed }

        // Oriented full size (after preferredTransform), and the crop within it.
        let oriented = natural.applying(preferred)
        let orientedSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let cropRect = crop?.rect ?? CGRect(origin: .zero, size: orientedSize)
        let sourceFPS = (try? await videoTrack.load(.nominalFrameRate)).map(Double.init) ?? 30
        let plan = recipe ?? VideoExportQuality.high.recipe(
            format: .mp4, sourceSize: cropRect.size, sourceFPS: sourceFPS)
        let renderSize = CGSize(width: max(2, plan.size.width.rounded()),
                                height: max(2, plan.size.height.rounded()))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        // Orient the source, slide the crop's top-left to the origin, then
        // shrink the whole thing onto the render size the choice asked for. The
        // crop rect is top-left; the composition space is also top-left
        // (UIKit-style) for layer instructions, so a straight negative
        // translation of the crop origin suffices on top of preferredTransform.
        let translate = CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY)
        let shrink = cropRect.width > 0 && cropRect.height > 0
            ? CGAffineTransform(scaleX: renderSize.width / cropRect.width,
                                y: renderSize.height / cropRect.height)
            : .identity
        layer.setTransform(preferred.concatenating(translate).concatenating(shrink), at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 100,
                                                timescale: CMTimeScale((plan.fps * 100).rounded()))
        videoComposition.renderSize = renderSize

        try? FileManager.default.removeItem(at: destination)
        // One re-encode at a time across the whole app. Two at once do not
        // finish any sooner, because they share one hardware encoder, and they
        // do take each other's decoders and buffer pools: several at once is
        // how an export stops moving.
        await ExportQueue.shared.enter()
        do {
            try await encode(composition: composition, videoComposition: videoComposition,
                             hasAudio: compAudio != nil, plan: plan, to: destination,
                             onProgress: onProgress)
        } catch {
            await ExportQueue.shared.leave()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        await ExportQueue.shared.leave()
        onProgress?(1)
    }

    /// Read the composition back through the encoder, spending exactly what the
    /// recipe allows.
    ///
    /// **The pictures and the sound are written separately and then laid side
    /// by side**, which is the same shape `DocumentMovieWriter` settled on and
    /// for the same reason. Feeding both into one `AVAssetWriter` looks like
    /// one pass fewer and deadlocks: the writer stops asking for pictures part
    /// way through and never asks again, whoever is ahead. On the eight second
    /// sample it stopped at 45 to 65 frames every time, with the sound input
    /// still hungry and the sound already further along than the picture. The
    /// join is a straight passthrough copy, so nothing is compressed twice.
    private static func encode(composition: AVComposition,
                               videoComposition: AVVideoComposition,
                               hasAudio: Bool,
                               plan: VideoExportRecipe,
                               to destination: URL,
                               onProgress: (@Sendable (Double) -> Void)?) async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-recording-export-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // The pictures are nearly all of the work, so they are nearly all of
        // the bar. What is left covers the sound and the join.
        let pictureShare = hasAudio ? 0.9 : 1.0
        let silent = scratch.appendingPathComponent("picture.mp4")
        try await writePictures(composition: composition, videoComposition: videoComposition,
                                plan: plan, to: silent) { done in
            onProgress?(done * pictureShare)
        }
        try Task.checkCancellation()
        guard hasAudio else {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: silent, to: destination)
            return
        }
        let sound = scratch.appendingPathComponent("sound.m4a")
        try await writeSound(composition: composition, to: sound)
        try Task.checkCancellation()
        try await join(picture: silent, sound: sound, to: destination)
    }

    /// The composition photographed frame by frame into a silent movie, inside
    /// the budget the choice allows.
    private static func writePictures(composition: AVComposition,
                                      videoComposition: AVVideoComposition,
                                      plan: VideoExportRecipe, to destination: URL,
                                      onProgress: (@Sendable (Double) -> Void)?) async throws {
        let reader = try AVAssetReader(asset: composition)
        let videoOut = AVAssetReaderVideoCompositionOutput(
            videoTracks: composition.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_32BGRA])
        videoOut.videoComposition = videoComposition
        // The reader hands its own buffers straight over rather than copying
        // each one; every frame is copied into the writer's pool below, and
        // then let go, which is the promise that makes that safe.
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else { throw ExportError.exportFailed }
        reader.add(videoOut)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: movieSettings(plan))
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(plan.size.width.rounded()),
                kCVPixelBufferHeightKey as String: Int(plan.size.height.rounded()),
            ])
        guard writer.canAdd(input) else { throw ExportError.exportFailed }
        writer.add(input)
        guard writer.startWriting(), reader.startReading() else {
            throw ExportError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)

        let total = max(0.001, composition.duration.seconds)
        var wroteAny = false
        while let sample = videoOut.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                throw CancellationError()
            }
            try await waitFor(input, writer: writer)
            guard let rendered = CMSampleBufferGetImageBuffer(sample),
                  let pool = adaptor.pixelBufferPool,
                  let ours = copy(rendered, into: pool) else { break }
            let at = CMSampleBufferGetPresentationTimeStamp(sample)
            guard adaptor.append(ours, withPresentationTime: at) else { break }
            wroteAny = true
            onProgress?(min(0.99, at.seconds / total))
        }
        input.markAsFinished()
        guard wroteAny else {
            reader.cancelReading()
            writer.cancelWriting()
            throw ExportError.exportFailed
        }
        writer.endSession(atSourceTime: composition.duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ExportError.didNotFinish(
                writer.error.map(String.init(describing:)) ?? "it did not finish")
        }
    }

    /// The composition's sound, cut at the same points as the picture, as one
    /// m4a. Written on its own so the two never wait on each other.
    private static func writeSound(composition: AVComposition, to destination: URL) async throws {
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetAppleM4A)
        else { throw ExportError.exportFailed }
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .m4a)
    }

    /// The picture and the sound in one file, neither of them re-encoded.
    private static func join(picture: URL, sound: URL, to destination: URL) async throws {
        let composition = AVMutableComposition()
        let pictureAsset = AVURLAsset(url: picture)
        guard let source = try? await pictureAsset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noVideoTrack }
        let length = try await pictureAsset.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: .zero)

        let soundAsset = AVURLAsset(url: sound)
        if let heard = try? await soundAsset.loadTracks(withMediaType: .audio).first,
           let lane = composition.addMutableTrack(withMediaType: .audio,
                                                  preferredTrackID: kCMPersistentTrackID_Invalid) {
            let heardLength = (try? await soundAsset.load(.duration)) ?? length
            // Never longer than the picture: sound running past the last frame
            // would leave the file playing a black nothing.
            let kept = CMTimeMinimum(heardLength, length)
            try? lane.insertTimeRange(CMTimeRange(start: .zero, duration: kept), of: heard, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetPassthrough)
        else { throw ExportError.exportFailed }
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .mp4)
    }

    /// One frame, copied out of whatever rendered it and into the writer's own
    /// pool, so the thing that rendered it can have it back at once.
    private static func copy(_ source: CVPixelBuffer, into pool: CVPixelBufferPool)
        -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess,
              let ours = made else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(ours, [])
        defer {
            CVPixelBufferUnlockBaseAddress(ours, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let from = CVPixelBufferGetBaseAddress(source),
              let to = CVPixelBufferGetBaseAddress(ours) else { return nil }
        let fromStride = CVPixelBufferGetBytesPerRow(source)
        let toStride = CVPixelBufferGetBytesPerRow(ours)
        let rows = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(ours))
        let run = min(fromStride, toStride)
        for row in 0..<rows {
            memcpy(to.advanced(by: row * toStride), from.advanced(by: row * fromStride), run)
        }
        return ours
    }

    /// Wait for the writer to be hungry again, without blocking a thread.
    ///
    /// A writer that has given up never becomes hungry again, and one that is
    /// neither finished nor failed nor hungry is stuck. Waiting on either
    /// forever is an export that never ends with a bar that never moves, so
    /// both of them say so instead.
    private static func waitFor(_ input: AVAssetWriterInput,
                                writer: AVAssetWriter) async throws {
        let giveUpAt = Date().addingTimeInterval(stallLimit)
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else {
                throw ExportError.writerGaveUp(
                    writer.error.map(String.init(describing:)) ?? "it stopped taking media")
            }
            guard Date() < giveUpAt else {
                throw ExportError.writerGaveUp(
                    "it stopped asking for pictures and never started again")
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// How long an export waits on a writer that has gone quiet before calling
    /// it stuck. Long enough that a machine under real load is never accused,
    /// short enough that nobody watches a dead bar for a coffee break.
    private static let stallLimit: TimeInterval = 90

    /// What the encoder is asked for: the size, the frame rate and the budget.
    private static func movieSettings(_ plan: VideoExportRecipe) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(plan.size.width.rounded()),
            AVVideoHeightKey: Int(plan.size.height.rounded()),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: plan.videoBitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: Int(plan.fps.rounded()),
                // A key frame every two seconds, so scrubbing and the preview a
                // chat app builds both land quickly.
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // Frame reordering stays ON, and it was worth measuring
                // rather than assuming. Turning it off makes a short export
                // reproducible to the byte, which the Export sheet would like
                // to be able to promise; it also more than DOUBLED the file on
                // a three second clip with real movement in it, 130,349 bytes
                // to 278,280. Doubling the file to buy reproducibility is
                // exactly the wrong trade for a feature whose whole point is a
                // file small enough to send, and it did not even buy it on a
                // longer clip, where the system encoder still wandered by ten
                // bytes and rewrote nearly every one of them. So: smallest
                // file, and the sheet says "about".
                AVVideoAllowFrameReorderingKey: true,
            ] as [String: Any],
        ]
    }

    /// Down-scale a CGImage to `size` (bitmap context). Used to fit a cropped
    /// frame into the planned output size for animated exports.
    private static func scaled(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0,
              let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - ImageIO property maps

    private static func animatedUTType(for format: RecordingFormat) -> CFString? {
        switch format {
        case .gif: return UTType.gif.identifier as CFString
        // Animated HEIC uses the image-sequence container type, not still .heic.
        case .heic: return "public.heics" as CFString
        case .mp4: return nil
        }
    }

    private static func containerProperties(for format: RecordingFormat) -> [CFString: Any] {
        switch format {
        case .gif:
            return [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        case .heic:
            return [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSLoopCount: 0]]
        case .mp4:
            return [:]
        }
    }

    private static func frameProperties(for format: RecordingFormat, delay: TimeInterval) -> [CFString: Any] {
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
