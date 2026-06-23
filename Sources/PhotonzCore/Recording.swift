import CoreGraphics
import Foundation

/// What region of the screen a recording covers (phase 12.1).
public enum RecordingSource: Hashable, Codable, Sendable {
    /// The whole display.
    case fullDisplay
    /// A sub-rect of the display, in points, top-left origin in the display's
    /// own coordinate space (exactly what the region-selection overlay reports).
    case region(CGRect)

    /// The pixel/source rect to capture within the display, given the display's
    /// full size in points; `.fullDisplay` covers the entire display.
    public func sourceRect(displaySize: CGSize) -> CGRect {
        switch self {
        case .fullDisplay: return CGRect(origin: .zero, size: displaySize)
        case .region(let rect): return rect
        }
    }
}

/// Audio captured alongside the video (phase 12.2). System audio and microphone
/// are independent toggles; neither, either, or both can be on.
public struct AudioSources: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let systemAudio = AudioSources(rawValue: 1 << 0)
    public static let microphone  = AudioSources(rawValue: 1 << 1)

    public var capturesSystemAudio: Bool { contains(.systemAudio) }
    public var capturesMicrophone: Bool { contains(.microphone) }
    public var capturesAnyAudio: Bool { !isEmpty }
}

/// Output container for a recording (phase 12.5). MP4 is the native record
/// target; GIF and animated HEIC are produced by re-encoding the recorded frames
/// via ImageIO. (Animated WebP was specced but macOS's built-in encoder can't
/// write it — that would need a vendored libwebp; deferred to the backlog. HEIC
/// is the modern, system-supported small/high-quality alternative.)
public enum RecordingFormat: String, Codable, Sendable, CaseIterable {
    case mp4
    case gif
    case heic

    public var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .gif: return "gif"
        case .heic: return "heic"
        }
    }

    /// MP4 is recorded directly; GIF/HEIC are derived by re-encoding frames.
    public var isAnimatedImage: Bool { self == .gif || self == .heic }

    public var displayName: String {
        switch self {
        case .mp4: return "MP4 Video"
        case .gif: return "Animated GIF"
        case .heic: return "Animated HEIC"
        }
    }
}

/// The user's recording choices, persisted as the "last used" config (phase
/// 12.2). The selected microphone device id is opaque (an `AVCaptureDevice`
/// unique id) and only meaningful when `audio` includes `.microphone`.
public struct RecordingConfig: Codable, Sendable, Hashable {
    public var source: RecordingSource
    public var audio: AudioSources
    public var microphoneDeviceID: String?
    public var format: RecordingFormat

    public init(source: RecordingSource = .fullDisplay,
                audio: AudioSources = [],
                microphoneDeviceID: String? = nil,
                format: RecordingFormat = .mp4) {
        self.source = source
        self.audio = audio
        self.microphoneDeviceID = microphoneDeviceID
        self.format = format
    }
}

/// Elapsed-time formatting for the floating stop control (phase 12.3). Pure so
/// the HUD label stays testable.
public enum RecordingClock {
    /// `m:ss` under an hour, `h:mm:ss` at or beyond it. Negatives clamp to 0.
    public static func elapsedString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):\(pad(m)):\(pad(s))"
        }
        return "\(m):\(pad(s))"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// How many frames to emit (and at what spacing/size) when re-encoding a
/// recording to an animated GIF or HEIC (phase 12.5). Caps fps and dimensions
/// so the file stays reasonable. Pure math — the CGImageDestination plumbing is
/// app-side.
public struct AnimatedExportPlan: Hashable, Sendable {
    /// Number of frames to sample from the source.
    public let frameCount: Int
    /// Per-frame delay in seconds (1 / fps).
    public let frameDelay: TimeInterval
    /// Output frame size (downscaled, never upscaled), aspect preserved.
    public let size: CGSize
    /// Source presentation time the first frame is sampled at — the trim
    /// in-point (0 for a full clip). Subsequent frames step by `frameDelay`
    /// from here, staying within the trimmed window (phase 13.5).
    public let trimStart: TimeInterval

    public init(frameCount: Int, frameDelay: TimeInterval, size: CGSize,
                trimStart: TimeInterval = 0) {
        self.frameCount = frameCount
        self.frameDelay = frameDelay
        self.size = size
        self.trimStart = trimStart
    }

    /// The presentation time (seconds) to sample the i-th frame at: offset by
    /// the trim in-point, then spread by `frameDelay` across the trimmed window.
    public func sampleTime(_ index: Int) -> TimeInterval {
        trimStart + Double(index) * frameDelay
    }
}

/// Size/quality presets for animated/MP4 export (phase 13.5). Maps a user
/// choice to an fps + max-dimension cap. Pure so the menu and the planner agree.
public enum VideoExportQuality: String, CaseIterable, Sendable, Codable {
    case high
    case standard
    case small

    public var targetFPS: Double {
        switch self {
        case .high: return 24
        case .standard: return 15
        case .small: return 10
        }
    }

    public var maxDimension: CGFloat {
        switch self {
        case .high: return 1280
        case .standard: return 800
        case .small: return 480
        }
    }

    public var label: String {
        switch self {
        case .high: return "High (24 fps, ≤1280px)"
        case .standard: return "Standard (15 fps, ≤800px)"
        case .small: return "Small (10 fps, ≤480px)"
        }
    }
}

public enum AnimatedExportPlanner {
    /// Plan a GIF/HEIC re-encode of the full clip.
    /// - duration: source length in seconds.
    /// - sourceSize: recorded pixel size.
    /// - targetFPS: desired frame rate (clamped to ≥1).
    /// - maxDimension: longest output side (down-scale only; aspect preserved).
    public static func plan(duration: TimeInterval,
                            sourceSize: CGSize,
                            targetFPS: Double = 15,
                            maxDimension: CGFloat = 800) -> AnimatedExportPlan {
        let fps = max(1, targetFPS)
        let delay = 1.0 / fps
        // At least one frame even for a near-zero clip; otherwise one frame per
        // 1/fps step across the duration.
        let count = max(1, Int((max(0, duration) * fps).rounded()))
        let size = PinnedImageMetrics.fittedSize(imageSize: sourceSize, maxDimension: maxDimension)
        return AnimatedExportPlan(frameCount: count, frameDelay: delay, size: size)
    }

    /// Plan a GIF/HEIC re-encode honoring a trim window and optional crop
    /// (phase 13.5). The frame count comes from the trimmed duration; sample
    /// times offset from the trim in-point; the output size derives from the
    /// crop's pixel size (full frame when `crop` is nil), down-scaled to
    /// `maxDimension`.
    public static func plan(trim: VideoTrim,
                            crop: VideoCrop? = nil,
                            sourceSize: CGSize,
                            targetFPS: Double = 15,
                            maxDimension: CGFloat = 800) -> AnimatedExportPlan {
        let fps = max(1, targetFPS)
        let delay = 1.0 / fps
        let trimmed = trim.effectiveDuration
        let count = max(1, Int((max(0, trimmed) * fps).rounded()))
        let baseSize = crop?.outputSize ?? sourceSize
        let size = PinnedImageMetrics.fittedSize(imageSize: baseSize, maxDimension: maxDimension)
        return AnimatedExportPlan(frameCount: count, frameDelay: delay, size: size,
                                  trimStart: trim.inPoint)
    }

    /// Preset overload: derives fps + max-dimension from a `VideoExportQuality`.
    public static func plan(trim: VideoTrim,
                            crop: VideoCrop? = nil,
                            sourceSize: CGSize,
                            quality: VideoExportQuality) -> AnimatedExportPlan {
        plan(trim: trim, crop: crop, sourceSize: sourceSize,
             targetFPS: quality.targetFPS, maxDimension: quality.maxDimension)
    }
}
