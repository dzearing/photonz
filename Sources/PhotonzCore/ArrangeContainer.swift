import CoreGraphics
import Foundation

/// The box ONE piece lines up inside, and which of the six align commands
/// actually do something there.
///
/// A layer picked on its own has nothing to line up with unless something
/// holds it. Two kinds of thing hold it, and they answer differently:
///
/// - **A screen has a box of its own.** Its size is the size it was given, so
///   the reference is simply that box and all six commands mean something.
/// - **A plain group has no box of its own.** Its box is whatever its contents
///   add up to, so the box a piece lines up inside is *everything else in the
///   group*: the button's background, for a word sitting on it. Taking the
///   group's own box instead would mean lining a piece up against a box the
///   piece itself helps define, and a word hanging over the button's edge would
///   then centre itself, shrink the group under its own feet and be off centre
///   again. Leaving the piece out keeps the reference still, so one press lands
///   it and a second press does nothing.
public struct ArrangeContainer: Equatable, Sendable {
    /// The layer doing the holding: the screen, or the group.
    public var id: UUID
    /// The box, in canvas points, the piece lines up inside.
    public var bounds: CGRect
    /// Whether the sideways three (left, centre, right) can move the piece.
    public var horizontal: Bool
    /// Whether the up-and-down three (top, middle, bottom) can.
    public var vertical: Bool

    public init(id: UUID, bounds: CGRect, horizontal: Bool = true, vertical: Bool = true) {
        self.id = id
        self.bounds = bounds
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Whether this one command has anywhere to move the piece.
    public func allows(_ alignment: LayerAlignment) -> Bool {
        alignment.isHorizontal ? horizontal : vertical
    }

    /// Whether any of the six do. A container that allows nothing is no
    /// container: six buttons that cannot move anything are worse than none.
    public var allowsNothing: Bool { !horizontal && !vertical }
}

extension PhotonzDocument {
    /// What the piece `id` lines up inside, or nil when nothing holds it in a
    /// way that means anything.
    ///
    /// Nil in four cases, all on purpose:
    ///
    /// - Nothing holds it. A layer alone on the canvas has no reference, which
    ///   is why Align needs two layers out there.
    /// - What holds it arranges its own contents. A stack or a grid decides
    ///   where its rows go and puts them back after every edit, so an align
    ///   press inside one is undone before you see it. Where those pieces sit
    ///   is what the Layout section is for.
    /// - The group holds nothing else. A group of one is exactly its only
    ///   child, so there is no box to line that child up inside.
    /// - The piece is as big as the reference on both axes, so no command
    ///   could move it anywhere.
    ///
    /// The search stops at the immediate parent and never climbs. A word inside
    /// a button inside a screen answers to the button, not to the screen:
    /// flying it to the middle of the screen would take it out of the button it
    /// belongs to.
    public func arrangeContainer(of id: UUID) -> ArrangeContainer? {
        guard let box = canvasContentBounds(of: id),
              let parentID = parentID(of: id),
              let parent = layer(id: parentID),
              let group = parent.group,
              group.layout?.arranges != true else { return nil }
        if group.isFrame {
            guard let bounds = canvasContentBounds(of: parentID) else { return nil }
            return ArrangeContainer(id: parentID, bounds: bounds)
        }
        var union: CGRect?
        for child in group.children where child.id != id {
            guard let sibling = canvasContentBounds(of: child.id) else { continue }
            union = union.map { $0.union(sibling) } ?? sibling
        }
        guard let bounds = union else { return nil }
        let container = ArrangeContainer(id: parentID, bounds: bounds,
                                         horizontal: box.width < bounds.width,
                                         vertical: box.height < bounds.height)
        return container.allowsNothing ? nil : container
    }
}
