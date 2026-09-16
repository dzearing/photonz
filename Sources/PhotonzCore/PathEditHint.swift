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

    /// The same moment with the PEN in hand rather than Select: a finished
    /// path picked up again by pressing P over it. A shape no longer lands
    /// with the Pen still in hand (`EditorState.addPath` hands back to Select,
    /// like every other tool that makes something), so this is the line for
    /// somebody who chose the Pen over a shape that already exists.
    ///
    /// It offers three of the four gestures and NOT the outline double click,
    /// because the Pen cannot reach that one: the first of the two clicks
    /// starts a new path and lets the finished one go before the second
    /// arrives. Offering a gesture that will not answer is worse than not
    /// naming it.
    ///
    /// The last sentence is there because the points appearing on a shape
    /// under a drawing tool reads like the tool changed under you. It did not:
    /// a press anywhere off the points still starts the next shape.
    public static let penOpening = "Drag a point to reshape this shape. "
        + "Double click a point to curve it. Click anywhere else to draw another."

    /// A path that has been TURNED. Reshaping moves the box the shape sits in
    /// and a turn is measured about the middle of that box, so a point dragged
    /// out on a turned path would swing the whole shape round under the hand.
    ///
    /// It used to say nothing at all: the points simply were not drawn, with
    /// no line, no pointer change and nothing to ask. Saying why, and naming
    /// the one field that undoes it, is the difference between a limit and a
    /// thing that looks broken.
    public static let turned = "This path is turned, so its points cannot be dragged. "
        + "Set A back to 0 under Position and Size, on the Layer menu, and they come back."

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

    /// The line the chip leads with the instant a shape has been turned into a
    /// path, before you touch anything.
    ///
    /// The question asked beforehand says what the command will do, but it
    /// carries a "Don't ask again", and the second time somebody uses this
    /// there is no question at all: a rectangle becomes a path with nothing
    /// said, and the row in the layers list quietly stops being the kind of
    /// thing it was. One line naming what just happened, and what to do with
    /// it, is the difference between a command that worked and a command you
    /// have to take on trust. It steps aside for the ordinary reshaping lines
    /// the moment a point is picked.
    public static func justTurned(paths: Int) -> String {
        let what = paths <= 1 ? "a path" : "\(paths) paths"
        return "Turned into \(what). Drag any point to reshape it, "
            + "or Command Z to put the shape back."
    }

    /// The same line when nothing had to be turned, because everything picked
    /// was already an outline: two runs drawn with the Pen welded into one.
    ///
    /// Its own wording rather than `justTurned`'s, because "Turned into a path"
    /// over two things that were already paths says nothing happened, and the
    /// way back is to the SEPARATE paths rather than to a shape.
    public static func justJoined(paths: Int) -> String {
        let what = paths <= 1 ? "one path" : "\(paths) paths"
        return "Joined into \(what). Drag any point to reshape it, "
            + "or Command Z to put the separate paths back."
    }

    /// The line when the join was offered, was asked for, and found nothing to
    /// weld.
    ///
    /// The command is offered on any two open outlines picked together rather
    /// than only on ones that would actually meet, because a dimmed row teaches
    /// nobody what "meet" means. This is the other half of that bargain: it
    /// changes nothing, and it names the gap and the way to close it, so the
    /// second try works.
    public static func nothingJoined(gap: CGFloat = PathJoin.tolerance) -> String {
        "Nothing joined: no two ends are within \(PathJoin.toleranceText(gap)) of each other. "
            + "Drag an end onto another to bring them together."
    }

    /// The line for a path with `picked` of its points selected, and `anchor`
    /// the one point picked where there is exactly one.
    ///
    /// With one picked and no anchor named it falls back to the general line
    /// about levers, which is what the chip said before it could tell one
    /// point from another.
    /// `penInHand` is the Pen rather than Select, which changes only the line
    /// with nothing picked: the gestures on a POINT are the same ones whichever
    /// tool is holding the canvas.
    public static func line(picked: Int, anchor: PathAnchor? = nil,
                            penInHand: Bool = false) -> String {
        switch picked {
        case 0: return penInHand ? penOpening : opening
        case 1:
            guard let anchor else { return bendPicked }
            if anchor.isHalfSmooth { return halfPicked }
            if anchor.handleIn == nil && anchor.handleOut == nil { return cornerPicked }
            return bendPicked
        default: return severalPicked
        }
    }
}
