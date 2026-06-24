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
    var savePanelType: UTType {
        switch self {
        case .mp4: return .mpeg4Movie
        case .gif: return .gif
        case .heic: return .heic
        }
    }
}

enum VideoExporter {

    /// Recording length in seconds.
    static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite else { return 0 }
        return seconds
    }

    /// The video's natural pixel size **after** its `preferredTransform` (so a
    /// portrait recording reports portrait dimensions). Used by the in-app
    /// editor's crop overlay (phase 13.3/13.4). Falls back to `.zero` if the
    /// track can't be read.
    static func orientedNaturalSize(of url: URL) async -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return .zero }
        let oriented = natural.applying(transform)
        return CGSize(width: abs(oriented.width), height: abs(oriented.height))
    }

    /// The video's nominal frame rate (fps), for frame-accurate ←/→ stepping in
    /// the editor. Falls back to 30 if the track can't be read or reports 0.
    static func frameRate(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let fps = try? await track.load(.nominalFrameRate), fps > 0 else { return 30 }
        return Double(fps)
    }

    /// A representative frame for the history thumbnail — sampled a hair into the
    /// clip so it isn't a black first frame.
    static func posterFrame(of url: URL, maxDimension: CGFloat = 600) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let seconds = await duration(of: url)
        let at = CMTime(seconds: min(0.2, seconds / 2), preferredTimescale: 600)
        return try? await generator.image(at: at).image
    }

    enum ExportError: Error { case noDestination, generationFailed, noVideoTrack, exportFailed }

    /// Re-encode the recording at `url` to an animated GIF or HEIC at
    /// `destination`, honoring an optional `trim` window and `crop` region
    /// (phase 13.5). No-op-safe for `.mp4` (callers shouldn't ask, but we guard
    /// anyway). `crop.rect` is in oriented natural-video pixels, top-left origin
    /// — the same space `AVAssetImageGenerator` produces with
    /// `appliesPreferredTrackTransform = true`, so the crop is applied directly
    /// with `cropping(to:)` before the down-scale to `plan.size`.
    static func exportAnimated(from url: URL, to destination: URL,
                               format: RecordingFormat,
                               trim: VideoTrim? = nil, crop: VideoCrop? = nil,
                               targetFPS: Double = 15, maxDimension: CGFloat = 800) async throws {
        let asset = AVURLAsset(url: url)
        let seconds = await duration(of: url)
        let naturalSize = await orientedNaturalSize(of: url)
        let resolvedTrim = trim ?? VideoTrim(duration: seconds)

        let plan = AnimatedExportPlanner.plan(trim: resolvedTrim, crop: crop,
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
            let time = CMTime(seconds: plan.sampleTime(index), preferredTimescale: 600)
            guard var frame = try? await generator.image(at: time).image else { continue }
            if let cropRect, let cropped = frame.cropping(to: cropRect) {
                frame = scaled(cropped, to: plan.size) ?? cropped
            }
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
            wroteAny = true
        }
        guard wroteAny, CGImageDestinationFinalize(dest) else { throw ExportError.generationFailed }
    }

    /// Re-export an MP4 honoring trim + crop (phase 13.5). Inserts the trimmed
    /// time range (video AND audio, for sync) into a composition, applies a
    /// crop via an `AVMutableVideoComposition` whose `renderSize` is the crop
    /// size and whose layer-instruction transform translates the cropped origin
    /// to (0,0) — accounting for the track's `preferredTransform` and Core
    /// Video's bottom-left origin — then writes H.264/.mp4.
    static func exportMP4(from url: URL, to destination: URL,
                          trim: VideoTrim, crop: VideoCrop?) async throws {
        let asset = AVURLAsset(url: url)
        let seconds = await duration(of: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let preferred = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let natural = (try? await videoTrack.load(.naturalSize)) ?? .zero

        let (start, length) = trim.timeRange(duration: seconds)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: length, preferredTimescale: 600))

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.noVideoTrack
        }
        try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        // Audio for A/V sync, when present.
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(range, of: audioTrack, at: .zero)
        }

        // Oriented full size (after preferredTransform), and the render/crop size.
        let oriented = natural.applying(preferred)
        let orientedSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let cropRect = crop?.rect ?? CGRect(origin: .zero, size: orientedSize)
        let renderSize = CGSize(width: cropRect.width.rounded(), height: cropRect.height.rounded())

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        // Orient the source, then slide the crop's top-left to the origin. The
        // crop rect is top-left; the composition space is also top-left
        // (UIKit-style) for layer instructions, so a straight negative
        // translation of the crop origin suffices on top of preferredTransform.
        let translate = CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY)
        layer.setTransform(preferred.concatenating(translate), at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        videoComposition.renderSize = renderSize

        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed
        }
        session.videoComposition = videoComposition
        try? FileManager.default.removeItem(at: destination)
        // Modern non-deprecated async export (macOS 15+).
        try await session.export(to: destination, as: .mp4)
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
