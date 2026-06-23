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

    enum ExportError: Error { case noDestination, generationFailed }

    /// Re-encode the recording at `url` to an animated GIF or HEIC at `destination`.
    /// No-op-safe for `.mp4` (callers shouldn't ask, but we guard anyway).
    static func exportAnimated(from url: URL, to destination: URL,
                               format: RecordingFormat,
                               targetFPS: Double = 15, maxDimension: CGFloat = 800) async throws {
        let asset = AVURLAsset(url: url)
        let seconds = await duration(of: url)
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let naturalSize = (try? await track?.load(.naturalSize)) ?? CGSize(width: maxDimension, height: maxDimension)

        let plan = AnimatedExportPlanner.plan(duration: seconds, sourceSize: naturalSize,
                                              targetFPS: targetFPS, maxDimension: maxDimension)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = plan.size

        guard let utType = animatedUTType(for: format),
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, utType,
                                                         plan.frameCount, nil)
        else { throw ExportError.noDestination }

        // Loop forever; per-frame delay carries the timing.
        let containerProps = containerProperties(for: format)
        CGImageDestinationSetProperties(dest, containerProps as CFDictionary)

        let frameProps = frameProperties(for: format, delay: plan.frameDelay)
        var wroteAny = false
        for index in 0..<plan.frameCount {
            let time = CMTime(seconds: plan.sampleTime(index), preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
            wroteAny = true
        }
        guard wroteAny, CGImageDestinationFinalize(dest) else { throw ExportError.generationFailed }
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
