import CoreGraphics

/// Whether a press on one of a measurement's handles has become a drag.
///
/// A caliper's feet and its head are grabbed with several points of slack
/// around the dot, so the point a press LANDS on is almost never the handle
/// itself. Treating that landing as an edit is how a click meant only to take
/// hold of an end quietly moved it: the end jumped under the pointer, the
/// other end levelled onto it, and a reading that had been lined up carefully
/// came out a different number with nothing said about it.
///
/// So a press is only an edit once the hand has actually travelled. Until then
/// the measurement stays exactly as it was placed and no undo step is taken.
/// The distance is what moved ON SCREEN, not in the document, so a click does
/// not get harder to make the further you zoom in.
public enum MeasureHandlePress {
    /// How far the pointer must travel, in view points, before the press is a
    /// drag. The same distance a caption pill uses, so every grab on the
    /// canvas agrees on what counts as a click.
    public static let travelThreshold: CGFloat = 2

    /// True once the pointer has moved far enough from where it pressed for
    /// this to be a drag rather than a click.
    ///
    /// - Parameters:
    ///   - start: where the press landed, in document points.
    ///   - point: where the pointer is now, in document points.
    ///   - zoom: document points to view points.
    public static func travelled(from start: CGPoint, to point: CGPoint, zoom: CGFloat) -> Bool {
        guard zoom > 0 else { return false }
        return hypot(point.x - start.x, point.y - start.y) * zoom >= travelThreshold
    }
}
