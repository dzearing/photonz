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
/// the list you clicked in.
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

    /// How tall the pane is drawn.
    ///
    /// - Parameters:
    ///   - stored: the height the grip last left it at, nil until the grip
    ///     has been moved, and then the pane takes its share of the column.
    ///   - content: what its lists would take with nothing capping them, nil
    ///     until they have been measured. Lists shorter than the pane, or all
    ///     folded to their headers, give the rest back to the pick.
    ///   - column: the height the two parts share, nil until laid out.
    ///   - floor: the pane's least height, its first header.
    ///   - fit: what the lists need drawn at their least without the pane
    ///     scrolling, nil when unknown. Read only until the grip is moved.
    public static func height(stored: CGFloat?, content: CGFloat?,
                              column: CGFloat?, floor: CGFloat, fit: CGFloat? = nil) -> CGFloat {
        let start = stored ?? column.map { column in
            max(column * defaultShare, min(fit ?? 0, column * mostDefaultShare))
        } ?? defaultHeight
        let wanted = min(start, content ?? start)
        return min(max(wanted, floor), maxAllowedHeight(column: column, floor: floor))
    }
}
