import CoreGraphics

/// **Layers on top, the pick under it, the Library last.**
///
/// The right hand panel reads top to bottom the way the user expects it to
/// (the user, 2026-10-18: "the panes are totally confusing!!!! layers isn't
/// at the top, i can't drag the pane up and down"). Layers, with its search,
/// sits in a pane at the top, and Measurements under it when the document has
/// any. A divider the person can see and drag sits under that pane. Below it
/// the picked thing's sections scroll, and the Library, when it is shown at
/// all, comes last. This reverses the 2026-10-13 card answer "Pick on top,
/// lists in a pane at the bottom" by the user's later word.
///
/// There are no empty bands. The pane is the height the divider was left at,
/// or less when its lists need less (a short or folded Layers), so the
/// sections below always meet it. With nothing below (nothing picked), the
/// pane is the whole panel.
///
/// Where the divider was left is remembered per kind of document
/// (`heightKey(forKind:)`): a recording's panel and a picture's are different
/// jobs. Double clicking it forgets it, and the pane takes its share again.
///
/// Sections are named by their raw ids (`InspectorSectionID` in the app), so
/// the rule stays pure.
public enum PanelListsPane {

    /// The sections in the pane on top, in the order they are drawn there:
    /// lists about the whole document rather than settings of the pick.
    public static let listOrder: [String] = ["layers", "measurements"]
    public static var listSections: Set<String> { Set(listOrder) }

    /// The shelf. A list too, but a thing you go and fetch from rather than
    /// the document's own tree, so it comes last, under the pick.
    public static let shelfSection = "library"

    /// How much of the panel the pane takes before anybody has moved the
    /// divider, when its lists need that much.
    public static let defaultShare: CGFloat = 0.4

    /// ...and how tall it starts before the panel has been laid out at all.
    public static let defaultHeight: CGFloat = 300

    /// The least the sections below are ever left, however low the divider
    /// was set: a header and a few rows, so a pick never arrives with nowhere
    /// to show.
    public static let belowFloor: CGFloat = 160

    /// The panel's draw order split into the pane on top (Layers, then
    /// Measurements) and everything below it in the order it came, with the
    /// Library moved to the end.
    public static func split(_ order: [String]) -> (lists: [String], below: [String]) {
        let lists = listOrder.filter(order.contains)
        let below = order.filter { !listSections.contains($0) && $0 != shelfSection }
        return (lists, order.contains(shelfSection) ? below + [shelfSection] : below)
    }

    /// The settings key the divider's height is kept under for one kind of
    /// document (a window mode's id: image, icon, design, video).
    public static func heightKey(forKind kind: String) -> String {
        "inspector.listsPaneHeight.\(kind)"
    }

    /// The height chosen for the pane: where the divider was left, or its
    /// share of the column until it has been moved. Nought or less is "never
    /// moved", which is what double clicking the divider writes.
    public static func chosenHeight(stored: CGFloat?, column: CGFloat?) -> CGFloat {
        if let stored, stored > 0 { return stored }
        return column.map { $0 * defaultShare } ?? defaultHeight
    }

    /// The highest the divider may set the pane in a column this tall: all of
    /// it but the floor below, and never less than the pane's own floor.
    public static func maxAllowedHeight(column: CGFloat?, floor: CGFloat) -> CGFloat {
        guard let column else { return .greatestFiniteMagnitude }
        return max(floor, column - belowFloor)
    }

    /// How far down the divider may be dragged: no further than the pane's
    /// lists reach, so a blank band can never be dragged open under them, and
    /// never into the floor below.
    public static func gripCeiling(column: CGFloat?, listsNeed: CGFloat?, floor: CGFloat) -> CGFloat {
        let most = maxAllowedHeight(column: column, floor: floor)
        return max(floor, min(listsNeed ?? most, most))
    }

    /// How tall the pane on top is drawn.
    ///
    /// - Parameters:
    ///   - chosen: `chosenHeight(stored:column:)`.
    ///   - column: the height the pane and the sections below share, nil
    ///     until laid out.
    ///   - listsNeed: the pane's lists drawn whole, folds honoured
    ///     (`contentHeight`), nil until measured.
    ///   - belowIsEmpty: nothing is drawn under the divider, so the pane is
    ///     the whole panel.
    ///   - floor: the pane's least height, its first header.
    public static func height(chosen: CGFloat, column: CGFloat?, listsNeed: CGFloat?,
                              belowIsEmpty: Bool, floor: CGFloat) -> CGFloat {
        if belowIsEmpty, let column { return max(column, floor) }
        let hugged = listsNeed.map { min(chosen, $0) } ?? chosen
        return min(max(hugged, floor), maxAllowedHeight(column: column, floor: floor))
    }

    /// What a list asks the dock for: all of its rows in the pane, where the
    /// pane's divider already sets how much room there is, or its rows capped by
    /// its own grab bar in a dock with no pane.
    ///
    /// A list in the pane used to keep its grab bar's ceiling too, 200pt (five
    /// rows) unless dragged, so once the pane began holding its height six
    /// layers stopped at five and scrolled with blank glass under them in the
    /// same pane (2026-10-15).
    public static func listAsks(content: CGFloat, grabBar: CGFloat, inPane: Bool) -> CGFloat {
        inPane ? content : min(content, grabBar)
    }

    /// The most a list may be drawn: the dock's share for it, and outside the
    /// pane also what its grab bar was dragged to, whichever is lower.
    public static func listCeiling(grabBar: CGFloat, dock: CGFloat?, inPane: Bool) -> CGFloat {
        let dock = dock ?? .greatestFiniteMagnitude
        return inPane ? dock : min(grabBar, dock)
    }

    /// The height of a column of sections drawn whole: each header with the
    /// hairline under it, each open body, and the padding above and below.
    /// Nil until every header and every open body has been measured.
    public static func contentHeight(_ sections: [(header: CGFloat?, body: CGFloat?)],
                                     padding: CGFloat, divider: CGFloat) -> CGFloat? {
        var total = 2 * padding
        for section in sections {
            guard let header = section.header else { return nil }
            total += header + divider + (section.body ?? 0)
        }
        return total
    }
}
