// One number that is really four, and the house rules for the row that holds it.
//
// Two things in this app are four numbers underneath and one number nearly
// every time anybody sets them: the room a group keeps inside its edges
// (`GroupPadding`, four sides) and how round a box is (`CornerRadii`, four
// corners). Both used to be met by four boxes stacked open in the panel, which
// is the laziest possible way to ask for a number that is usually one number,
// and between them they spent about a hundred points of a panel that does not
// fit its own contents saying what the row above them already said.
//
// So both are now ONE row: a number that means all four, and a small control
// beside it that opens the four in a popout. Nothing here draws anything — that
// is the app layer's business (`FourSidedPopout.swift`) — but the two rules
// that must not drift between the places it appears live here, once.
import CoreGraphics

public enum FourSidedNumber {
    /// What the one row shows in place of a number while its four parts
    /// disagree: the house word, the same one every other control in the dock
    /// says when the things it speaks for do not agree (`MixedValue`).
    ///
    /// It used to be the four numbers run together, `10/16/10/16`, because the
    /// only other place they could be read was four rows that were usually
    /// shut. That reason is gone: the four are one press away in the popout,
    /// and they are in this row's own tooltip in words. What is left of the
    /// shorthand is a row that has to be parsed rather than glanced at, and a
    /// second answer to a question the app had already settled.
    public static func standIn(uniform: CGFloat?) -> String {
        uniform == nil ? MixedValue.text : ""
    }

    /// The way back to one number, said the same way wherever the row appears.
    /// Tacked onto the end of whatever the row was already saying, so a person
    /// who has set one side on its own is never left hunting for how to undo
    /// that without undoing.
    ///
    /// - Parameter part: what one of the four is called here, singular:
    ///   "side" for room, "corner" for rounding.
    public static func levelUp(part: String) -> String {
        "Type one number to give every \(part) the same."
    }
}
