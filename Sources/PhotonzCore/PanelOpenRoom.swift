import CoreGraphics

/// **Opening a folded section takes its room from the near side.**
///
/// The user, 2026-10-24: "if I expand a collapsed pane, it should not pull
/// other panes behind it out but can collapse panes on the other side to make
/// room". Reproduced the same day in a 620 point window with a rectangle
/// picked: opening the Library at the foot cut Appearance across its Fill row
/// and pushed Motion out of sight, and in a recording with a clip picked,
/// opening the Library pushed Appearance and Effects off the panel.
///
/// Every section's body opens DOWNWARD, under its own header, the Library's
/// included (its pane at the foot grows up to make room, but its body is
/// drawn under its header like any other). So the sections BEHIND an opened
/// section are the ones after it, under it: they keep their folds, and the
/// ones on screen stay on screen. The room comes from the NEAR side, the
/// sections above it, folded one at a time, the nearest first, and only as
/// many as it takes for the opened section to be whole on screen with
/// everything under it still there.
///
/// Two refinements, each for a reason:
///
/// - **Appearance and Effects fold last.** The panel promises those two are
///   never out of reach (the user, 2026-09-07, `DockHeightBudget`). A folded
///   header is still in reach, so they may fold, but only once every ordinary
///   section on the near side, the Layers list included, has.
/// - **A fold that cannot win does not happen.** When folding everything on
///   the near side still leaves the opened section and what is under it
///   taller than the panel, nothing folds: the person would lose every open
///   section and the panel would scroll anyway. The section opens as it
///   always did. That is always the case for the top section, Layers, which
///   has nothing above it.
///
/// The caller hands in only what is on screen: a section scrolled out of
/// sight costs the panel nothing that folding it would give back.
public enum PanelOpenRoom {

    /// One section of the panel as this rule sees it, in the order the panel
    /// draws them, top to bottom.
    public struct Entry: Sendable, Equatable {
        public let key: String
        /// What the section takes folded: its header.
        public let folded: CGFloat
        /// What it takes open: drawn whole for the one being opened, at the
        /// least the panel draws it for the rest (a list squeezed to its
        /// floor, a form whole).
        public let open: CGFloat
        /// Whether it is open now.
        public let isOpen: Bool
        /// One of the sections the panel promises are always in reach.
        public let isPromised: Bool

        public init(key: String, folded: CGFloat, open: CGFloat, isOpen: Bool, isPromised: Bool = false) {
            self.key = key
            self.folded = max(0, folded)
            self.open = max(0, open)
            self.isOpen = isOpen
            self.isPromised = isPromised
        }

        /// What it takes as it is now.
        public var now: CGFloat { isOpen ? open : folded }
    }

    /// What opening a section does to the rest.
    public struct Plan: Sendable, Equatable {
        /// The sections to fold, in the order they were chosen.
        public let folds: [String]
        /// Whether the opened section and everything under it fit once those
        /// are folded. False means nothing could be won and `folds` is empty.
        public let fits: Bool

        public init(folds: [String], fits: Bool) {
            self.folds = folds
            self.fits = fits
        }
    }

    /// Half a point either way is the same height: measurements come back in
    /// fractions and a fold over a rounding error is a fold for nothing.
    static let tolerance: CGFloat = 0.5

    /// Which sections to fold so the section at `opening` opens whole.
    ///
    /// - Parameters:
    ///   - entries: the panel's sections on screen, top to bottom.
    ///   - opening: the one being opened, by its place in `entries`. A stale
    ///     request (out of range, or a section already open) folds nothing.
    ///   - room: the height the panel has for them.
    public static func plan(_ entries: [Entry], opening: Int, room: CGFloat) -> Plan {
        guard entries.indices.contains(opening), !entries[opening].isOpen else {
            return Plan(folds: [], fits: true)
        }
        var total = entries.indices.reduce(CGFloat(0)) { sum, index in
            sum + (index == opening ? entries[index].open : entries[index].now)
        }
        if total <= room + tolerance { return Plan(folds: [], fits: true) }

        // The near side, nearest first: ordinary sections, then the promised.
        let near = entries[..<opening].reversed().filter { $0.isOpen && $0.open > $0.folded }
        let order = near.filter { !$0.isPromised } + near.filter(\.isPromised)
        var folds: [String] = []
        for entry in order {
            folds.append(entry.key)
            total -= entry.open - entry.folded
            if total <= room + tolerance { return Plan(folds: folds, fits: true) }
        }
        return Plan(folds: [], fits: false)
    }
}
