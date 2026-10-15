import CoreGraphics

/// **The pick on top, the lists in a pane at the bottom.**
///
/// The right hand panel answers one question: what is this thing I have
/// picked, and what can I set on it right now. Its lists (Layers, Measurements,
/// the Library) are about the whole document, not the pick, and while they
/// shared one scrolling column with it the panel opened on a list every time (the user, 2026-10-13: "clogging up
/// the right pane with useless non contextual crap").
///
/// So the panel splits the way Photoshop's Properties sits over Layers: the
/// pick's sections scroll in the top part, and the lists share a pane at the
/// bottom that keeps its height when the pick changes, with a grip between the
/// two (the user chose this, option B of "Where do Layers and Library sit when
/// something is picked?", 2026-10-13). Nothing jumps: picking a row never moves
/// the list you clicked in, and folding a list or switching the Library's
/// scope never moves the pane (`Hold`).
///
/// On a video the timeline is the layer list, and Captions and Transitions
/// stay at the foot of the pick's own column: both are forms the pane cannot
/// shorten, and on a laptop window a pane holding them pushed a picked
/// sound's Fades below the fold that the audio mock keeps on screen
/// (measured 2026-10-13, `sound-fades-in-the-panel-walk`). Whether they move
/// into the pane anyway is a question for the user, on its own card.
///
/// Sections are named by their raw ids (`InspectorSectionID` in the app), so
/// the rule stays pure.
public enum PanelListsPane {

    /// The sections that are lists about the document rather than settings of
    /// the pick.
    public static let listSections: Set<String> = ["layers", "measurements", "library"]

    /// How much of the panel the pane takes before anybody has moved the
    /// grip: less than half, so on a laptop window over a video the pick's
    /// own sections keep most of the height.
    public static let defaultShare: CGFloat = 0.4

    /// ...or, when its lists need more than that to be drawn at their least
    /// without the pane scrolling (a shelf cut across its foot is a shelf
    /// whose tiles have no names), as much as they need up to this share.
    public static let mostDefaultShare: CGFloat = 0.5

    /// ...and how tall it starts before the panel has been laid out at all.
    public static let defaultHeight: CGFloat = 300

    /// The least the pick's part is ever left, however tall the pane was set:
    /// a header and a few rows, so a pick never arrives with nowhere to show.
    public static let pickFloor: CGFloat = 160

    /// The panel's draw order split into the two parts, each in the order it
    /// came.
    public static func split(_ order: [String]) -> (pick: [String], lists: [String]) {
        (order.filter { !listSections.contains($0) }, order.filter(listSections.contains))
    }

    /// The highest the grip may set the pane in a column this tall: all of it
    /// but the pick's floor, and never less than the pane's own floor.
    public static func maxAllowedHeight(column: CGFloat?, floor: CGFloat) -> CGFloat {
        guard let column else { return .greatestFiniteMagnitude }
        return max(floor, column - pickFloor)
    }

    /// The height the pane holds before anybody has moved the grip, and what
    /// it was worked out for.
    ///
    /// The pane keeps its height while somebody works in it: folding a list,
    /// switching the Library's scope or a list growing or shrinking never
    /// moves it. It used to shrink to its content, anchored at the panel's
    /// foot, and the header or the scope control just clicked moved out from
    /// under the pointer, so a second click on the same spot missed (93pt for
    /// Layers folding, 65pt for Media to Comps, 2026-10-14). Only a new window
    /// height or a list joining or leaving the pane works it out again, and
    /// the pointer is not in the pane for either.
    public struct Hold: Equatable, Sendable {
        public var column: CGFloat
        public var lists: [String]
        public var height: CGFloat

        public init(column: CGFloat, lists: [String], height: CGFloat) {
            self.column = column
            self.lists = lists
            self.height = height
        }

        /// Whether this hold was worked out for the panel as it is now.
        public func holds(column: CGFloat?, lists: [String]) -> Bool {
            column == self.column && lists == self.lists
        }
    }

    /// How tall the pane starts before the grip is moved: its share of the
    /// column, or what its lists need at their least up to half of it.
    public static func startingHeight(column: CGFloat?, fit: CGFloat?) -> CGFloat {
        guard let column else { return defaultHeight }
        return max(column * defaultShare, min(fit ?? 0, column * mostDefaultShare))
    }

    /// The hold to keep: `current` while it was worked out for this column
    /// and these lists, else a new one once the column and the lists' least
    /// height have both been measured, else none.
    ///
    /// A hold only ever GROWS, and only when its lists need more room drawn
    /// at their least than it has (a style saved onto a shelf that had none):
    /// a shelf cut across its foot has tiles nobody can reach. `fit` counts
    /// every list open and at its whole floor, so folding one or switching
    /// what it shows never changes it, and a list needing less never shrinks
    /// the pane.
    public static func hold(_ current: Hold?, column: CGFloat?, lists: [String],
                            fit: CGFloat?) -> Hold? {
        if let current, current.holds(column: column, lists: lists) {
            guard let column, let fit else { return current }
            let wanted = startingHeight(column: column, fit: fit)
            guard wanted > current.height else { return current }
            return Hold(column: column, lists: lists, height: wanted)
        }
        guard let column, let fit else { return nil }
        return Hold(column: column, lists: lists,
                    height: startingHeight(column: column, fit: fit))
    }

    /// How tall the pane is drawn.
    ///
    /// - Parameters:
    ///   - stored: the height the grip last left it at, nil until the grip
    ///     has been moved.
    ///   - held: the starting height the pane is holding (`Hold`), read only
    ///     when it was worked out for this column and these lists.
    ///   - column: the height the two parts share, nil until laid out.
    ///   - lists: the sections in the pane.
    ///   - floor: the pane's least height, its first header.
    ///   - fit: what the lists need drawn at their least without the pane
    ///     scrolling, nil when unknown. Read only when nothing is held and
    ///     the grip has not been moved.
    public static func height(stored: CGFloat?, held: Hold?, column: CGFloat?, lists: [String],
                              floor: CGFloat, fit: CGFloat? = nil) -> CGFloat {
        let start = stored
            ?? held.flatMap { $0.holds(column: column, lists: lists) ? $0.height : nil }
            ?? startingHeight(column: column, fit: fit)
        return min(max(start, floor), maxAllowedHeight(column: column, floor: floor))
    }
}
