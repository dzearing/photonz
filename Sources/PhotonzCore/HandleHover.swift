import CoreGraphics
import Foundation

// MARK: - Every transform handle answers the pointer before you click
//
// The pointer already changes over a handle (`CanvasPointer`): resize arrows,
// the turn arrow, an open hand. That says WHAT a press does, not WHICH of the
// small marks under the pointer it takes, and on the 3D arcs it said nothing a
// person could see at all (the user, 2026-10-12: "I don't know that I'm
// selecting them").
//
// So the handle itself answers too. Every place the canvas draws a handle also
// says where it drew it (`HandleMark`); the pointer cue, which mirrors the
// press, says what a press would do; and the mark that cue belongs to is drawn
// lit, a quarter larger, filled in the accent. The cue decides and the mark
// only shows it, so a lit handle is always the handle a press takes.

/// One handle as drawn on screen, in the canvas view's points.
public struct HandleMark: Hashable, Sendable {
    public enum Shape: Hashable, Sendable {
        /// A square this many points across.
        case square(CGFloat)
        /// A dot this many points across.
        case circle(CGFloat)
    }

    /// What a press on it does, in the pointer cue's own terms.
    public enum Role: Hashable, Sendable {
        case resize(ResizeHandle)
        case rotate
        case grab
    }

    public let center: CGPoint
    public let shape: Shape
    public let role: Role

    public init(center: CGPoint, shape: Shape, role: Role) {
        self.center = center
        self.shape = shape
        self.role = role
    }

    /// How a walk names it: `resize-topLeft`, `rotate`, `grab`.
    public var name: String {
        switch role {
        case .resize(let handle): "resize-" + handle.rawValue
        case .rotate: "rotate"
        case .grab: "grab"
        }
    }

    /// Half its drawn size.
    var halfSize: CGFloat {
        switch shape {
        case .square(let side): side / 2
        case .circle(let diameter): diameter / 2
        }
    }
}

public enum HandleHover {
    /// How much larger a lit handle is drawn.
    public static let grow: CGFloat = 1.25
    /// How far past its drawing a grab dot still counts as under the pointer,
    /// in view points: the reach the presses give their dots
    /// (`CanvasPointer.measureHandleTolerance`, the endpoints' 9, a path
    /// point's 8), rounded up so the mark never comes up short of the press.
    public static let reach: CGFloat = 10
    /// How long the pointer rests on a 3D handle before its name appears.
    public static let labelDelay: TimeInterval = 0.35

    /// The mark a press at `p` would take, given the cue the pointer read
    /// there, or nil when no handle is under it.
    ///
    /// The cue is the authority: it mirrors the press, so the mark only has to
    /// be found for it. A resize lights the square of that very handle, even
    /// with the pointer out along its edge, where an edge grab takes it; the
    /// knob lights for a turn; a grab lights the nearest grab dot within reach,
    /// and nothing when the grab has no dot (a caption pill, a caliper's
    /// number), where the open hand already says it all.
    public static func lit(cue: CanvasPointerCue?, at p: CGPoint, among marks: [HandleMark]) -> HandleMark? {
        guard let cue else { return nil }
        func distance(_ mark: HandleMark) -> CGFloat {
            hypot(mark.center.x - p.x, mark.center.y - p.y)
        }
        switch cue {
        case .resize(let handle):
            return marks.filter { $0.role == .resize(handle) }.min { distance($0) < distance($1) }
        case .rotate:
            return marks.filter { $0.role == .rotate }.min { distance($0) < distance($1) }
        case .grab:
            return marks
                .filter { $0.role == .grab && distance($0) <= max($0.halfSize, reach) }
                .min { distance($0) < distance($1) }
        }
    }

    /// Where the lit handle is drawn: its own shape, a quarter larger, about
    /// the same middle.
    public static func litRect(for mark: HandleMark) -> CGRect {
        let half = mark.halfSize * grow
        return CGRect(x: mark.center.x - half, y: mark.center.y - half, width: half * 2, height: half * 2)
    }
}

extension SpaceHandle {
    /// The name shown beside the pointer resting on this handle: the value its
    /// drag changes, in the 3D section's own words, and the words the pill
    /// under the drag then starts with.
    public var hoverLabel: String {
        switch self {
        case .swing: "Rotation Y"
        case .tip: "Rotation X"
        case .depth: "Depth"
        }
    }
}
