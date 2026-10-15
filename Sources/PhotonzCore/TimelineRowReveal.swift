import CoreGraphics

/// **The rows a pick or a key opens are brought on screen by a scroll, never
/// by a taller timeline.**
///
/// The timeline is as tall as its tracks (`TimelineDockHeight`), and the rows
/// that open INSIDE a track (a picked title's parts, the key lane of a value
/// just keyed) scroll inside it rather than growing it, so the picture above
/// never re-zooms on a pick. That can open a row past the timeline's foot, so
/// the timeline scrolls the least that brings it in, the way a list reveals the
/// row you just added, and not at all when it is already on screen.
public enum TimelineRowReveal {
    /// Where the tracks' scroll goes to show `row`, or nil to leave it. A row
    /// taller than the timeline shows its top: the part a person reads first.
    public static func offset(revealing row: TimelineRowExtent, offset: CGFloat,
                              viewportHeight: CGFloat, contentHeight: CGFloat) -> CGFloat? {
        guard viewportHeight > 0 else { return nil }
        let furthest = max(0, contentHeight - viewportHeight)
        var landing = offset
        if row.bottom > offset + viewportHeight { landing = row.bottom - viewportHeight }
        if row.top < landing { landing = row.top }
        landing = min(max(0, landing), furthest)
        return abs(landing - offset) < 0.5 ? nil : landing
    }
}
