import CoreGraphics

/// **A tile picked in the Library never moves the shelf you clicked in.**
///
/// With nothing chosen by its top edge, the timeline is as tall as its tracks
/// (`TimelineDockHeight`), and a picked layer opens rows of its own on them: a
/// title's parts, the lanes of what is moving on it. Picking a Library tile
/// lets go of that layer, so its rows folded, the timeline got shorter, and the
/// canvas and the panel above it grew by the difference. The pane holding the
/// Library is at the panel's foot, so the shelf slid down under the pointer and
/// the second click of a double click landed beside the tile it meant (42pt on
/// a laptop window with a title's headline picked, 2026-10-14).
///
/// So while a Library tile is the pick, the timeline keeps the height it had
/// when the tile was clicked. It still grows if its tracks need more, and the
/// moment anything else is picked it fits its tracks again.
public struct TimelineHeightHold: Sendable, Hashable {
    /// The tracks' height the last time nothing was being held.
    public private(set) var lastFree: CGFloat?

    public init() {}

    /// The natural height to draw: the tracks' own, or while `holding`, no
    /// less than it was when the hold began.
    public mutating func natural(_ natural: CGFloat, holding: Bool) -> CGFloat {
        guard holding else {
            lastFree = natural
            return natural
        }
        return max(natural, lastFree ?? natural)
    }
}
