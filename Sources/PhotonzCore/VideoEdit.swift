import CoreGraphics
import Foundation

/// Non-destructive trim window for a recording (phase 13.3). Holds the in/out
/// points in seconds; the clip plays (and exports) only within `[inPoint,
/// outPoint]`. Pure value type — the `AVPlayer`/export plumbing lives app-side.
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

/// Non-destructive crop region for a recording (phase 13.4). Stores a `CGRect`
/// in **natural-video-pixel space, top-left origin** (the same convention the
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
