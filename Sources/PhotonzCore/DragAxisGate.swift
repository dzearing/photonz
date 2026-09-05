import CoreGraphics
import Foundation

/// Which axes a drag is allowed to catch lines on, decided from the direction
/// the hand is actually travelling.
///
/// Dragging a caliper's leg straight up should not make vertical lines flash
/// past it: the leg is not looking for anything sideways, and a guide that
/// appears for one frame is noise. So a drag that is clearly travelling one way
/// stops catching on the other axis.
///
/// The trap is deciding that afresh on every mouse event. A hand moving mostly
/// downward produces a ratio that wanders either side of any single threshold,
/// so a gate with one threshold flips on alternate frames and the snap flickers
/// with it. This gate has TWO thresholds and a wide dead band between them: it
/// only changes its mind when the travel is unambiguous, and otherwise keeps
/// the decision it already made. Ambiguity holds; it never toggles.
public struct DragAxisGate: Equatable, Sendable {
    public enum Axes: Equatable, Sendable {
        /// Slow, diagonal or undecided: both axes may catch.
        case both
        /// Travelling left and right: only the x axis may catch.
        case horizontal
        /// Travelling up and down: only the y axis may catch.
        case vertical
    }

    /// Older motion counts for less: the gate follows the last handful of
    /// events rather than the whole drag.
    public static let decay: CGFloat = 0.7
    /// How lopsided the travel must be, and how much of it there must be,
    /// before one axis is shut out.
    public static let lockRatio: CGFloat = 3
    public static let lockMotion: CGFloat = 4
    /// How even sustained travel must become before both axes open again. The
    /// gap between this and `lockRatio` is the dead band no wobble can cross.
    public static let balancedRatio: CGFloat = 2

    public private(set) var axes: Axes = .both
    /// Decayed sum of recent travel, in document points.
    public private(set) var motion: CGVector = .zero
    private var last: CGPoint?

    public init() {}

    /// A new drag starts undecided, from wherever the press landed.
    public mutating func reset(at point: CGPoint? = nil) {
        motion = .zero
        last = point
        axes = .both
    }

    /// Feed one pointer position; call once per drag event, before snapping.
    public mutating func track(_ point: CGPoint) {
        if let last {
            motion.dx = motion.dx * Self.decay + (point.x - last.x)
            motion.dy = motion.dy * Self.decay + (point.y - last.y)
        }
        last = point

        let ax = abs(motion.dx), ay = abs(motion.dy)
        if ay > ax * Self.lockRatio, ay > Self.lockMotion {
            axes = .vertical
        } else if ax > ay * Self.lockRatio, ax > Self.lockMotion {
            axes = .horizontal
        } else if ax > Self.lockMotion, ay > Self.lockMotion,
                  max(ax, ay) < min(ax, ay) * Self.balancedRatio {
            // Real travel both ways: the drag has genuinely gone diagonal, so
            // a corner is being dragged and both axes matter again.
            axes = .both
        }
        // Anything else is ambiguous, and ambiguity keeps the last decision.
    }

    /// Vertical lines are only offered while the drag is not clearly vertical.
    public var capturesX: Bool { axes != .vertical }
    /// And horizontal lines while it is not clearly horizontal.
    public var capturesY: Bool { axes != .horizontal }
}
