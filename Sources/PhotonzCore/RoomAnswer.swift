import CoreGraphics
import Foundation

/// What a group will do with more room, in one line it can say BEFORE anybody
/// types a number.
///
/// Room at a group's edges has two honest answers and they look like opposites:
///
/// - A **loose drawing**, where nothing is painted to the group's own edges,
///   grows its box outward and leaves every piece exactly where it was drawn.
///   Its box is not a thing anybody can see, so moving the drawing to make room
///   inside an invisible box would be the app rearranging your work to no
///   visible end.
/// - A **button**, where one piece has been named the surface, keeps the corner
///   it is pinned at and moves the pieces in. There the box IS the thing you
///   can see, so the pill has to stay where you put it and grow.
///
/// Both are right for the drawing they happen to, which is why neither was
/// changed. What was missing is that nothing on screen said which one you were
/// about to get, and whether a piece is the surface is not something a box on
/// the canvas shows. So a group carries its answer, the Layout section prints
/// it under the room field, and `RoomAnswerTests` holds each answer against
/// what `GroupFlow` actually does so the sentence and the canvas cannot drift.
public enum RoomAnswer: String, CaseIterable, Hashable, Sendable {
    /// Nothing is painted to this group's edges and at least one side is the
    /// size of its contents, so the box grows outward around them.
    case growsTheBoxOutward
    /// A surface, a stack or a grid answers to the room, so the pieces start
    /// that far in from the edges and the box grows from the corner it is
    /// pinned at.
    case movesThePiecesIn
    /// The box is a size somebody gave it and nothing inside stretches, so
    /// there is nowhere for the room to go.
    case movesNothing

    /// The line the Layout section prints under the room field.
    ///
    /// One line each, in the idiom the section's other two sentences already
    /// use: short, about the thing that is NOT on screen, and never a
    /// restatement of a control two rows up.
    public var sentence: String {
        switch self {
        case .growsTheBoxOutward:
            return "More room grows the box outward, and nothing inside moves."
        case .movesThePiecesIn:
            return "More room moves the pieces in from the edges."
        case .movesNothing:
            // Not "nothing here stretches": the surface of a button given a
            // size of its own stretches, and is painted to those edges room
            // and all, so it is the BOX being a number somebody gave that
            // leaves the room nowhere to go. True of a screen as well, whose
            // box is a frame that was drawn.
            return "This box is the size it was given, so more room moves nothing."
        }
    }
}

extension Layer {
    /// What more room at this group's edges would do, or nil where there is
    /// nothing to say: anything that is not a group, and a group with nothing
    /// inside it, where the room lands on no pieces at all.
    public var roomAnswer: RoomAnswer? {
        guard let group, !group.children.isEmpty else { return nil }
        let layout = workingLayout
        // A stack and a grid ARRANGE what they hold: the flow starts every
        // piece in from the edges by exactly this much, whatever else is in
        // the group.
        if layout.arranges { return .movesThePiecesIn }
        let rules = group.children.map { $0.resolvedPlacement(in: self) }
        // A screen's box is a frame somebody drew, and so is a group given
        // both its sides, so neither of them has an edge that room can push
        // outward. Only a piece that stretches can show the room there.
        let hugs = !isFrame && (layout.usedWidth == nil || layout.usedHeight == nil)
        guard hugs else {
            // The surface is painted to the box's OWN edges, room and all, so
            // on a box nobody can grow it shows nothing. A rail stretched one
            // way is painted to the room INSIDE the edges, so it stands off
            // them by whatever is typed.
            let rail = rules.contains {
                !$0.isSurface && ($0.horizontal == .stretch || $0.vertical == .stretch)
            }
            return rail ? .movesThePiecesIn : .movesNothing
        }
        return rules.contains(where: \.isSurface) ? .movesThePiecesIn : .growsTheBoxOutward
    }
}
