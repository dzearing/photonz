import CoreGraphics

/// How tall the timeline dock's tracks area is, given what its top edge has
/// been dragged to.
///
/// The edge is a drag handle, the same idea as the right panel's leading edge
/// (user 2026-09-28). What it moves is the TRACKS area, not the whole dock: the
/// transport and the timeline's bar above it (`chrome`) keep their height, so a
/// caption bar arriving or leaving does not quietly eat the tracks somebody
/// made room for.
///
/// - The floor is one track: a ruler, a lane and the scroller strip under it.
///   Pushed any lower there would be a timeline with nothing to edit on it.
/// - The ceiling is about 70% of the window for the whole dock, so the
///   picture always keeps a real share of it. In a window too short for that,
///   the floor wins: a dock with no track in it is worse than a small picture.
/// - Nothing chosen (nothing on file, or a double-click on the edge) is the
///   height the dock always had: as tall as its tracks, up to its own cap.
public struct TimelineDockHeight: Sendable, Hashable {
    /// The share of the window the whole dock may take.
    public static let windowShare: CGFloat = 0.7
    /// What is written to the settings for "nothing chosen".
    public static let defaultStored: Double = 0

    /// The transport and the timeline's bar: the part of the dock above the
    /// tracks, which a drag never changes.
    public var chrome: CGFloat
    /// The shortest the tracks area may be.
    public var floor: CGFloat
    /// The editor window's height.
    public var windowHeight: CGFloat

    public init(chrome: CGFloat, floor: CGFloat, windowHeight: CGFloat) {
        self.chrome = max(0, chrome)
        self.floor = max(0, floor)
        self.windowHeight = max(0, windowHeight)
    }

    /// The tallest the tracks area may be in this window.
    public var ceiling: CGFloat {
        max(floor, windowHeight * Self.windowShare - chrome)
    }

    /// Any height, held between the floor and the ceiling.
    public func clamped(_ height: CGFloat) -> CGFloat {
        min(ceiling, max(floor, height))
    }

    /// The tracks area's height: the one chosen by hand, or with none, its
    /// natural height. Either way inside the floor and the ceiling, so a
    /// window made shorter squeezes it and one made taller gives it back.
    public func body(chosen: CGFloat?, natural: CGFloat) -> CGFloat {
        clamped(chosen ?? natural)
    }

    /// Where a drag on the top edge leaves the tracks area, given its height
    /// when the drag began and how far the pointer has moved DOWN since.
    /// The edge follows the pointer one for one, so up is taller.
    public func dragged(fromBody base: CGFloat, pointerMovedDown dy: CGFloat) -> CGFloat {
        clamped(base - dy)
    }

    /// The height on file, or nil for "nothing chosen".
    public static func chosen(stored: Double) -> CGFloat? {
        stored > 0 ? CGFloat(stored) : nil
    }
}
