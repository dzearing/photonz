import Foundation

/// Which clips a busy lane paints as one layer instead of building a view for
/// each (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
///
/// A clip's bar is a big view: pieces, grips, a level line you can drag, fade
/// diamonds, popover anchors, a right-click menu. On the 60 minute reference
/// edit about 800 of them are in sight near the whole-hour view, and every
/// frame of a zoom built each one again, about 570 ms a frame against 8 ms
/// (2026-11-14). With the bars taken out the same zoom ran at 24 ms.
///
/// So a lane with many clips in sight paints the plain ones (the same fill,
/// edge, name, waveform, level line, fade diamonds and picture fades the bar
/// draws, and the cuts between them) and builds a full bar only for a clip
/// somebody is working on: picked, in a hand, trimmed, renamed or under the
/// pointer. Anything the painting does not draw (pieces, a still, a speed
/// badge, keys, points on the level line, pictures along the clip) keeps the
/// clip a view, so what the timeline shows never changes. A lane with few clips builds them all,
/// as it always has.
public enum TimelinePaint {
    /// A lane with fewer clips than this in sight builds every one as a view.
    public static let busyLane = 24

    public static func lanePaints(clipsInSight: Int) -> Bool {
        clipsInSight >= busyLane
    }

    /// What decides whether one clip's bar can be painted.
    public struct Clip: Hashable, Sendable {
        /// Picked, in a hand, being trimmed or renamed, or under the pointer.
        public var isKept = false
        /// A picture or its own sound: the kinds the painting draws.
        public var isPlainKind = true
        public var pieceCount = 1
        /// A held frame: drawn as a still.
        public var isHeld = false
        public var pictureHidden = false
        /// A speed or hold badge in its corner.
        public var hasBadge = false
        public var hasKeys = false
        /// Out of step with the picture after a hold elsewhere.
        public var hasDrift = false
        /// Pinned points on its sound's level line, each a dot to drag.
        public var levelHasPoints = false
        /// A gain, a cleaned sound or a cleaning in progress, as a badge.
        public var soundHasBadge = false
        /// Zoomed in far enough for pictures along the clip.
        public var showsPictures = false
        /// Its sound's shape is not read yet: the bar asks for it.
        public var waveformMissing = false

        public init() {}
    }

    public static func paints(_ clip: Clip) -> Bool {
        !clip.isKept && clip.isPlainKind && clip.pieceCount == 1 && !clip.isHeld && !clip.pictureHidden
            && !clip.hasBadge && !clip.hasKeys && !clip.hasDrift
            && !clip.levelHasPoints && !clip.soundHasBadge && !clip.showsPictures && !clip.waveformMissing
    }
}
