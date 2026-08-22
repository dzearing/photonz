import CoreGraphics
import Foundation

/// Trim window for a recording (phase 13.3). Holds the in/out points in
/// seconds; the clip plays (and exports) only within `[inPoint, outPoint]`, and
/// saving commits that window into the stored file (phase 18). Pure value type
/// — the `AVPlayer`/export plumbing lives app-side.
///
/// Editing rules: both points clamp to `[0, duration]`, a minimum window is
/// enforced, and moving one handle past the other **pushes** the other instead
/// of inverting (set-in pushes out forward; set-out pushes in backward). When a
/// push would run off the end of the clip, the moved handle is pulled back so
/// the minimum window still fits.
public struct VideoTrim: Codable, Sendable, Hashable {
    /// Trim start, seconds. Always `<= outPoint - minDuration`.
    public private(set) var inPoint: TimeInterval
    /// Trim end, seconds. Always `>= inPoint + minDuration`.
    public private(set) var outPoint: TimeInterval
    /// The clip length this trim was made against, in seconds. Stored so
    /// `isTrimmed`/`effectiveDuration` need no external duration and the value
    /// survives Codable round-trips.
    public private(set) var clipDuration: TimeInterval

    /// The default minimum kept window, in seconds, so a clip can never trim to
    /// nothing.
    public static let defaultMinDuration: TimeInterval = 0.1

    /// A full-clip trim for a recording of `duration` seconds.
    public init(duration: TimeInterval) {
        let d = max(0, duration)
        self.inPoint = 0
        self.outPoint = d
        self.clipDuration = d
    }

    /// A trim with explicit points, clamped into `[0, duration]` and ordered.
    public init(inPoint: TimeInterval, outPoint: TimeInterval, duration: TimeInterval,
                minDuration: TimeInterval = VideoTrim.defaultMinDuration) {
        let d = max(0, duration)
        let lo = min(max(0, inPoint), d)
        let hi = min(max(0, outPoint), d)
        self.inPoint = min(lo, hi)
        self.outPoint = max(lo, hi)
        self.clipDuration = d
        enforceMinDuration(minDuration: max(0, minDuration), prefer: .keepIn)
    }

    /// True when the window is anything narrower than the whole clip.
    public var isTrimmed: Bool {
        inPoint > 1e-6 || outPoint < clipDuration - 1e-6
    }

    /// Kept length in seconds.
    public var effectiveDuration: TimeInterval { max(0, outPoint - inPoint) }

    /// The kept window as `(start, length)` for `AVAssetExportSession` /
    /// composition insertion. `duration` lets the out-point re-clamp if the
    /// underlying clip length changed since this trim was made.
    public func timeRange(duration: TimeInterval) -> (start: TimeInterval, length: TimeInterval) {
        let d = max(0, duration)
        let start = min(max(0, inPoint), d)
        let end = min(max(start, outPoint), d)
        return (start, end - start)
    }

    /// Move the in-point to `seconds`, clamped and min-window-enforced. Pushes
    /// the out-point forward if needed (never inverts).
    public mutating func setIn(_ seconds: TimeInterval, duration: TimeInterval,
                               minDuration: TimeInterval = VideoTrim.defaultMinDuration) {
        clipDuration = max(0, duration)
        let m = max(0, minDuration)
        inPoint = min(max(0, seconds), clipDuration)
        if outPoint < inPoint + m {
            outPoint = inPoint + m
            if outPoint > clipDuration {
                outPoint = clipDuration
                inPoint = max(0, clipDuration - m)
            }
        }
    }

    /// Move the out-point to `seconds`, clamped and min-window-enforced. Pushes
    /// the in-point backward if needed (never inverts).
    public mutating func setOut(_ seconds: TimeInterval, duration: TimeInterval,
                                minDuration: TimeInterval = VideoTrim.defaultMinDuration) {
        clipDuration = max(0, duration)
        let m = max(0, minDuration)
        outPoint = min(max(0, seconds), clipDuration)
        if inPoint > outPoint - m {
            inPoint = outPoint - m
            if inPoint < 0 {
                inPoint = 0
                outPoint = min(clipDuration, m)
            }
        }
    }

    private enum Bias { case keepIn, keepOut }

    private mutating func enforceMinDuration(minDuration: TimeInterval, prefer: Bias) {
        guard outPoint - inPoint < minDuration else { return }
        switch prefer {
        case .keepIn:
            outPoint = inPoint + minDuration
            if outPoint > clipDuration {
                outPoint = clipDuration
                inPoint = max(0, clipDuration - minDuration)
            }
        case .keepOut:
            inPoint = outPoint - minDuration
            if inPoint < 0 {
                inPoint = 0
                outPoint = min(clipDuration, minDuration)
            }
        }
    }
}

/// The edits that produced a recording's current media file: the trim window
/// and crop region, in **preserved-original** seconds/pixels, stored in a
/// `.photonzedits` sidecar next to the media (the video sibling of the image
/// editor's layered `.photonz` sidecar).
///
/// Since phase 18 the stored file is the truth: saving bakes these in, so no
/// consumer re-applies them. What the sidecar buys is reversibility — the
/// editor reopens against `VideoOriginals.editSource` and this record puts the
/// trim handles back where they were, so the edit can be widened, tightened, or
/// cleared away entirely.
public struct VideoEdits: Codable, Sendable, Hashable {
    /// Kept window in source-file seconds; nil = whole clip.
    public var trim: VideoTrim?
    /// Kept region in natural-video pixels; nil = full frame.
    public var crop: VideoCrop?

    public init(trim: VideoTrim? = nil, crop: VideoCrop? = nil) {
        self.trim = trim
        self.crop = crop
    }

    /// True when there is nothing to apply at export.
    public var isEmpty: Bool { trim == nil && crop == nil }

    /// Drops a full-clip trim and a full-frame crop, so only *real* edits
    /// persist (an empty result means the sidecar can be deleted). A zero
    /// `videoSize` (metadata not loaded) leaves the crop untouched.
    public func normalized(videoSize: CGSize) -> VideoEdits {
        var edits = self
        if let trim, !trim.isTrimmed { edits.trim = nil }
        if let crop, videoSize != .zero, !crop.isCropped(videoSize: videoSize) { edits.crop = nil }
        return edits
    }
}

/// Sidecar IO for `VideoEdits`: same folder, same basename as the recording,
/// `.photonzedits` extension (deliberately not a media extension, so the
/// capture-folder scan never lists it as history). Best-effort like the image
/// sidecar — a failed write loses the record of how the file was derived, never
/// the media itself. Written only by a save (`VideoAssetCommit`), so it always
/// describes what the stored file actually has baked in.
public enum VideoEditsSidecar {
    public static func url(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension("photonzedits")
    }

    public static func load(for mediaURL: URL) -> VideoEdits? {
        guard let data = try? Data(contentsOf: url(for: mediaURL)) else { return nil }
        return try? JSONDecoder().decode(VideoEdits.self, from: data)
    }

    /// Writes the sidecar; empty edits remove it instead, so a cleared trim
    /// doesn't leave a stale file behind.
    public static func save(_ edits: VideoEdits, for mediaURL: URL) {
        let sidecar = url(for: mediaURL)
        if edits.isEmpty {
            try? FileManager.default.removeItem(at: sidecar)
        } else if let data = try? JSONEncoder().encode(edits) {
            try? data.write(to: sidecar, options: .atomic)
        }
    }
}

/// Crop region for a recording (phase 13.4), applied to the stored file when the
/// recording is saved (phase 18). Stores a `CGRect` in **natural-video-pixel
/// space, top-left origin** (the same convention the
/// document model uses), plus an optional aspect lock. All editing reuses the
/// image editor's `Crop`/`CropAspect`/`Geometry.clampCrop` geometry verbatim —
/// only the storage and the clamp-to-video-size wrapper are new. The bottom-left
/// flip and `preferredTransform` handling are re-done at export time, never here.
public struct VideoCrop: Codable, Sendable, Hashable {
    /// The kept region in natural-video pixels (top-left origin), always inside
    /// `[0, videoSize]`.
    public private(set) var rect: CGRect
    /// Aspect lock the rect honors; `.free` = unconstrained.
    public private(set) var aspect: CropAspect

    /// A crop clamped to `videoSize`. A null/empty intersection falls back to a
    /// minimal in-bounds rect (matching `Geometry.clampCrop`).
    public init(rect: CGRect, videoSize: CGSize, aspect: CropAspect = .free) {
        self.rect = Geometry.clampCrop(rect, toCanvas: videoSize)
        self.aspect = aspect
    }

    /// The full-frame default (whole video). With an aspect lock, the largest
    /// rect of that ratio, centered.
    public init(fullFrame videoSize: CGSize, aspect: CropAspect = .free) {
        let full = CGRect(origin: .zero, size: videoSize)
        self.rect = Crop.fitted(full, to: aspect)
        self.aspect = aspect
    }

    /// The exported pixel size — the crop rect's size (whole pixels).
    public var outputSize: CGSize {
        CGSize(width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// True when the region is anything narrower than the whole video.
    public func isCropped(videoSize: CGSize) -> Bool {
        rect.standardized != CGRect(origin: .zero, size: videoSize)
    }

    /// Resize by dragging a handle, ratio-locked and clamped to the video — a
    /// thin wrapper over `Crop.resize`.
    public mutating func resize(dragging handle: ResizeHandle, to point: CGPoint, videoSize: CGSize) {
        rect = Crop.resize(rect, dragging: handle, to: point, aspect: aspect, canvas: videoSize)
    }

    /// Translate the region, clamped to the video — wraps `Crop.moved`.
    public mutating func move(by delta: CGPoint, videoSize: CGSize) {
        rect = Crop.moved(rect, by: delta, in: videoSize)
    }

    /// A fresh region dragged from `anchor` to `current`, ratio-locked and
    /// clamped — wraps `Crop.dragRect` (no-op when the drag is still empty).
    public mutating func drag(anchor: CGPoint, current: CGPoint, videoSize: CGSize) {
        if let r = Crop.dragRect(anchor: anchor, current: current, aspect: aspect, canvas: videoSize) {
            rect = r
        }
    }

    /// Change the aspect lock, re-fitting the current rect to it.
    public mutating func setAspect(_ aspect: CropAspect, videoSize: CGSize) {
        self.aspect = aspect
        rect = Geometry.clampCrop(Crop.fitted(rect, to: aspect), toCanvas: videoSize)
    }
}
