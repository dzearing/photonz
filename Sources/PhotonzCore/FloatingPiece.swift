import CoreGraphics
import Foundation

/// A piece taken out of the line its group arranges and placed by hand, in
/// front of the rest.
///
/// The mirror of the surface (`SurfaceCommand.swift`). A row or a column puts
/// every piece in the line and leaves exactly one exception, the surface, which
/// is painted to the group's own edges and is always BEHIND. A notification dot
/// on the corner of a card and a New ribbon over the top of one want the same
/// step out of the line and the opposite depth, and until this the only way to
/// get it was to wrap the card in a second group that arranges nothing, which
/// works and leaves an invisible group in the layers list for ever.
///
/// The one number kept here is the size of the box the piece was last placed
/// in, and it is kept because nothing else could keep it. The flow re-runs
/// after every edit and only ever sees the box as it is NOW, so a card that
/// grows a line taller has no way to tell a badge pinned to its bottom corner
/// how far to come down. Written down, the answer is a subtraction.
public struct FloatingPiece: Hashable, Codable, Sendable {
    /// The size the group's box had the last time this piece was placed, or nil
    /// the first time round, where there is nothing to carry it from and the
    /// piece simply stays where it is.
    public var placedIn: CGSize?

    public init(placedIn: CGSize? = nil) {
        self.placedIn = placedIn
    }
}

/// What one piece inside a group is DOING, in the words the Role row says it.
///
/// Four readings and only three of them are answers you can pick: spanning the
/// group is a state a piece arrives in by being stretched the way its stack
/// runs, and mixed is what a selection that disagrees reads. One list so the
/// panel, the menu and the tests cannot end up with four different words for
/// the same thing.
public enum PieceRole: String, CaseIterable, Hashable, Sendable {
    /// In the line, like everything else.
    case arranged
    /// Out of the line, painted to the group's own edges, behind the rest.
    case surface
    /// Out of the line, placed by hand, in front of the rest.
    case inFront
    /// Stretched the way its stack runs: painted right across the group without
    /// being the thing behind everything in it.
    case spanning
    /// Several pieces picked, and they are not all doing the same thing.
    case mixed

    public var title: String {
        switch self {
        case .arranged: ResolvedPlacement.arrangedTitle
        case .surface: ResolvedPlacement.surfaceTitle
        case .inFront: ResolvedPlacement.inFrontTitle
        case .spanning: ResolvedPlacement.spanningTitle
        case .mixed: PlacementSelection.mixedText
        }
    }
}

/// The words the Layer menu wears for the third answer, and the sentence that
/// says what taking it does. Kept beside the surface's own so the two cannot
/// drift into being two unrelated features wearing one row.
public enum FloatingCommand {
    /// The menu row's name: the panel's words in the case a menu wears, so a
    /// person reading either recognises the other.
    public static let menuTitle = "In Front of the Rest"

    /// What picking it gives you, for the hover line on a live row.
    public static let reason =
        "Take this piece out of the line and leave it where you put it, in front of the rest. "
        + "The others arrange themselves as though it were not there, and Horizontal and "
        + "Vertical say which edges it holds when the group is resized."
}

extension Layer {
    /// Whether this piece has been taken out of the line and placed by hand.
    /// True of the flag alone: whether there is a line to have left is a
    /// question about the group holding it (`ResolvedPlacement.floats`).
    public var floatsInFront: Bool { floating != nil }
}

extension PhotonzDocument {

    /// Take every picked piece out of the line and put it in front of the rest,
    /// or hand it back to the arrangement, in ONE step that one undo puts back.
    ///
    /// Three things happen at once and they are one act. A piece taking the
    /// room its stack has left over stops first: there is no room left over for
    /// something that is not in the line, and stopping is what hands it back the
    /// size it was drawn at. It stops being the surface, because behind
    /// everything and in front of everything cannot both be true. And it comes
    /// to the front of its group, because the row is called In Front of the Rest
    /// and a piece that stayed underneath a card would make that a lie.
    public mutating func setFloating(ids: [UUID], _ floats: Bool) {
        for id in ids where layer(id: id) != nil {
            guard floats else {
                updateLayer(id: id) { $0.floating = nil }
                continue
            }
            if layer(id: id)?.fillsTheFlow == true { setFillsTheFlow(id: id, false) }
            updateLayer(id: id) { $0.floating = FloatingPiece() }
            bringToTheFrontOfItsGroup(id)
        }
    }

    /// Puts one piece nearest the viewer among its own siblings. Last in the
    /// list is nearest, which is the one thing the layers panel reverses.
    private mutating func bringToTheFrontOfItsGroup(_ id: UUID) {
        let siblings = containingGroup(of: id)?.children.count ?? layers.count
        moveLayer(id: id, to: siblings)
    }
}
