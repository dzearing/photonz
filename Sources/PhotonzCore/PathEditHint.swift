import CoreGraphics
import Foundation

/// What the chip under the canvas says while a path's points are showing.
///
/// Four gestures decide whether this feels like a drawing app or like a
/// puzzle, and none of them is guessable: double click the outline to add a
/// point, double click a point to curve it, double click a LEVER to straighten
/// that one side, and Option drag to free a point's two sides. The chip says
/// the ones that apply to what is picked right now rather than listing all
/// four at once.
///
/// It lives here rather than in the canvas because which line applies is a
/// decision about the shape under the hand, and the app layer should be able
/// to ask a tested answer rather than work it out again.
public enum PathEditHint {

    /// What the chip is called while a path's points are showing.
    public static let title = "Path"

    /// Nothing picked yet: how to get started, and the two double clicks that
    /// do the most.
    public static let opening = "Drag a point to reshape. Double click a point to curve it, "
        + "or the outline to add one."

    /// A hard corner picked. It has no levers on it, so it is not told to drag
    /// one: the way forward is to curve it first.
    public static let cornerPicked = "This point is a hard corner. "
        + "Double click it to curve it, or Delete to take it out."

    /// A point with a lever on each side.
    public static let bendPicked = "Drag a lever to bend the curve. "
        + "Double click a lever to straighten that side, Option drag frees the two sides."

    /// A point curved on one side and straight on the other: what it is, and
    /// the way back out in both directions.
    public static let halfPicked = "This point curves on one side only. "
        + "Double click the point to curve both sides, or its lever to straighten it too."

    /// Several points picked: the keys that reach all of them.
    public static let severalPicked = "Arrow keys nudge the points you picked. "
        + "Delete takes them out."

    /// The line for a path with `picked` of its points selected, and `anchor`
    /// the one point picked where there is exactly one.
    ///
    /// With one picked and no anchor named it falls back to the general line
    /// about levers, which is what the chip said before it could tell one
    /// point from another.
    public static func line(picked: Int, anchor: PathAnchor? = nil) -> String {
        switch picked {
        case 0: return opening
        case 1:
            guard let anchor else { return bendPicked }
            if anchor.isHalfSmooth { return halfPicked }
            if anchor.handleIn == nil && anchor.handleOut == nil { return cornerPicked }
            return bendPicked
        default: return severalPicked
        }
    }
}
