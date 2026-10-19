import CoreGraphics

/// **The Library in a pane of its own at the foot of the panel.**
///
/// The panel reads Layers, then the picked thing's sections, then the
/// Library (`PanelListsPane`). Drawn at the foot of the pick's own scroller,
/// the shelf moved whenever the pick did: a click on a title page tile lets go
/// of the picked title, its sections leave the scroller above the shelf, and
/// every tile slid out from under the pointer before the second click of a
/// double click (110pt on a recording, 2026-10-19). With a clip picked it sat
/// a thousand points down, where nothing scrolled to it and a guide pointing
/// at it pointed at nothing. So the shelf has a pane of its own, the way it
/// had on a recording until 2026-10-18, with a divider over it:
///
/// - It starts at its share of the panel, or at what the shelf needs at its
///   least up to half, and HOLDS that (`Hold`): switching scope or folding the
///   shelf never moves it.
/// - It grows into any room the pick's sections leave, so there is never empty
///   panel between the last section and the shelf (`drawnHeight`, the user,
///   2026-10-18: "why does the library pane have this giant gap above it???").
/// - While the pointer is inside it, it holds still whatever the pick does,
///   and settles once the pointer leaves (the app side).
/// - The divider over it sets the height it is chosen at, remembered per kind
///   of document (`heightKey(forKind:)`).
///
/// Heights are in points, so the rule stays pure.
public enum PanelShelfPane {

    /// How much of the panel the shelf takes before anybody has moved the
    /// divider: less than half, so on a laptop window the pick keeps most.
    public static let defaultShare: CGFloat = 0.4

    /// ...or, when the shelf needs more than that drawn at its least (a shelf
    /// cut across its foot is a shelf whose tiles have no names), as much as
    /// it needs up to this share.
    public static let mostDefaultShare: CGFloat = 0.5

    /// ...and how tall it starts before the panel has been laid out at all.
    public static let defaultHeight: CGFloat = 300

    /// The least the pick's sections above are ever left, however high the
    /// divider was pulled: a header and a few rows.
    public static let aboveFloor: CGFloat = 160

    /// The settings key the divider's height is kept under for one kind of
    /// document (a window mode's id: image, icon, design, video).
    public static func heightKey(forKind kind: String) -> String {
        "inspector.shelfPaneHeight.\(kind)"
    }

    /// The height the pane holds before anybody has moved the divider, and
    /// the column it was worked out for. Only a new window height works it
    /// out again, and the pointer is not in the pane for that.
    public struct Hold: Equatable, Sendable {
        public var column: CGFloat
        public var height: CGFloat

        public init(column: CGFloat, height: CGFloat) {
            self.column = column
            self.height = height
        }

        /// Whether this hold was worked out for the panel as it is now.
        public func holds(column: CGFloat?) -> Bool { column == self.column }
    }

    /// How tall the pane starts before the divider is moved: its share of
    /// the column, or what the shelf needs at its least up to half of it.
    public static func startingHeight(column: CGFloat?, fit: CGFloat?) -> CGFloat {
        guard let column else { return defaultHeight }
        return max(column * defaultShare, min(fit ?? 0, column * mostDefaultShare))
    }

    /// The hold to keep: `current` while it was worked out for this column,
    /// else a new one once the column and the shelf's least height have both
    /// been measured, else none. A hold only ever GROWS, and only when the
    /// shelf needs more room at its least than it has.
    public static func hold(_ current: Hold?, column: CGFloat?, fit: CGFloat?) -> Hold? {
        if let current, current.holds(column: column) {
            guard let column, let fit else { return current }
            let wanted = startingHeight(column: column, fit: fit)
            guard wanted > current.height else { return current }
            return Hold(column: column, height: wanted)
        }
        guard let column, let fit else { return nil }
        return Hold(column: column, height: startingHeight(column: column, fit: fit))
    }

    /// The highest the divider may set the pane in a column this tall: all of
    /// it but the floor above, and never less than the pane's own floor.
    public static func maxAllowedHeight(column: CGFloat?, floor: CGFloat) -> CGFloat {
        guard let column else { return .greatestFiniteMagnitude }
        return max(floor, column - aboveFloor)
    }

    /// The height chosen for the pane: where the divider left it, else the
    /// height it holds, else its starting height.
    ///
    /// - Parameters:
    ///   - stored: where the divider was left, nil until it has been moved.
    ///   - held: the starting height the pane is holding, read only when it
    ///     was worked out for this column.
    ///   - column: the height the pick and the pane share, nil until laid out.
    ///   - floor: the pane's least height, the shelf's header.
    ///   - fit: what the shelf needs drawn at its least, nil when unknown.
    public static func height(stored: CGFloat?, held: Hold?, column: CGFloat?,
                              floor: CGFloat, fit: CGFloat? = nil) -> CGFloat {
        let start = stored
            ?? held.flatMap { $0.holds(column: column) ? $0.height : nil }
            ?? startingHeight(column: column, fit: fit)
        return min(max(start, floor), maxAllowedHeight(column: column, floor: floor))
    }

    /// How tall the pane is DRAWN: the height chosen for it, or every point
    /// the pick's sections leave empty, whichever is more. Only when the pick
    /// needs more than the column has left does the chosen height decide, and
    /// then the pick's part scrolls.
    ///
    /// - Parameters:
    ///   - chosen: `height(...)`.
    ///   - column: the height the pick and the pane share, nil until laid out.
    ///   - aboveNeeds: the pick's sections drawn whole, nil until measured.
    ///   - foldedHeight: the pane's height with the shelf folded, nil while it
    ///     is open: a folded shelf is its header and asks for nothing more.
    public static func drawnHeight(chosen: CGFloat, column: CGFloat?, aboveNeeds: CGFloat?,
                                   foldedHeight: CGFloat?) -> CGFloat {
        let asks = foldedHeight.map { min(chosen, $0) } ?? chosen
        guard let column, let aboveNeeds else { return chosen }
        return max(asks, column - aboveNeeds)
    }

    /// The least the sections above are left when the shelf needs the room
    /// to show its first row of tiles whole: their first header.
    public static let aboveLeast: CGFloat = 48

    /// `height` raised to what the shelf needs at its least (`least`: its
    /// header, its controls and its first row of tiles whole), taking the
    /// room from the sections above down to `aboveLeast`. A shelf cut across
    /// its first row is a row of pictures with no names, and the name is what
    /// a tile says; the sections above scroll in what is left. Only until the
    /// divider is moved: a height the person set is theirs.
    public static func atLeastTheShelf(_ height: CGFloat, least: CGFloat?, column: CGFloat?) -> CGFloat {
        guard let least, let column else { return height }
        return max(height, min(least, column - aboveLeast))
    }

    /// What the divider writes down as the chosen height when it is let go
    /// at `dragged`, having taken hold of a pane chosen at `startChosen`, with
    /// `roomLeft` the room the pick leaves empty.
    ///
    /// Above the room left it is the new choice. At or under it the pane is
    /// drawn at the room left anyway, so pulling down there gives the pick
    /// nothing and must not quietly make the pane taller the next time the
    /// pick overflows; the choice only moves when the divider goes under it.
    public static func gripChoice(dragged: CGFloat, startChosen: CGFloat,
                                  roomLeft: CGFloat?) -> CGFloat {
        guard let roomLeft, dragged <= roomLeft else { return dragged }
        return min(startChosen, dragged)
    }
}
