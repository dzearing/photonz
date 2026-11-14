import Foundation

/// The stretch of time the timeline builds views for: the window on screen and
/// half a window each side of it
/// (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
///
/// A lane used to build a view for every clip, sound, gap, edit point and
/// click tick on its track, wherever it was. Each of them reads the timeline's
/// window to place itself, so every frame of a zoom or a scroll worked all of
/// them out again: on the 60 minute reference edit (524 clips, 377 cuts) a
/// frame of zoom held the main thread about 740 ms and a frame of scroll 550 ms
/// (2026-11-14), almost all of it SwiftUI going over views nobody could see.
///
/// The margin is there so a slow scroll does not build and throw away views at
/// the edge on every frame, and the ends are snapped to steps of a quarter of a
/// window (rounded up to a power of two milliseconds, so a zoom keeps the same
/// steps for a while too): two frames of a scroll mostly get the very same
/// sight, so the lists cut from it are the same lists and nothing is built.
public struct TimelineSight: Hashable, Sendable {
    /// The earliest moment anything is built for.
    public let fromMS: Double
    /// The latest moment anything is built for.
    public let toMS: Double

    /// How much past each side of the window is built, as a share of it.
    public static let margin = 0.5

    public init(ruler: MotionStripRuler, margin: Double = TimelineSight.margin) {
        let span = max(1, ruler.spanMS)
        let step = pow(2, (log2(max(1, span * margin / 2))).rounded(.up))
        let start = ruler.startMS
        fromMS = ((start - span * margin) / step).rounded(.down) * step
        toMS = ((start + span + span * margin) / step).rounded(.up) * step
    }

    /// Whether anything from `fromMS` to `toMS` reaches into the sight.
    public func reaches(fromMS start: Double, toMS end: Double) -> Bool {
        end >= fromMS && start <= toMS
    }

    /// The clips whose bars reach into the sight, any without a bar, and any
    /// `keeping` names wherever they are: a clip picked or in a hand keeps its
    /// view, since a drag lives in it and the panel reads it.
    public func clips(_ groups: [MotionStripGroup], keeping kept: Set<UUID> = []) -> [MotionStripGroup] {
        groups.filter { group in
            guard let bar = group.bar else { return true }
            return reaches(fromMS: Double(bar.inMS), toMS: Double(bar.outMS)) || kept.contains(group.layerID)
        }
    }

    /// The edit points in the sight.
    public func editPoints(_ points: [TimelineEditPoint]) -> [TimelineEditPoint] {
        points.filter { reaches(fromMS: Double($0.atMS), toMS: Double($0.atMS)) }
    }

    /// The gaps that reach into the sight.
    public func gaps(_ gaps: [TimelineGap]) -> [TimelineGap] {
        gaps.filter { reaches(fromMS: Double($0.range.lowerBound), toMS: Double($0.range.upperBound)) }
    }
}
