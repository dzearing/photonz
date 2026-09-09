import CoreGraphics

/// How the right-hand dock shares out the height it has.
///
/// The dock holds a stack of groups, and left to themselves they come to more
/// than the window is tall: measured on 2026-09-07 with two pieces of text
/// picked, six groups ran to 1339 points against a 996 point dock, which put
/// Effects — and Corner Radius, its third slider — nearly 300 points below the
/// fold. Every one of those groups was drawn at its full natural height, and
/// the dock scrolled.
///
/// The rule this encodes is that **a list gives up room and a form does not.**
/// A group whose body is a list (Layers, the parts of what you picked, saved
/// measurements, the Library shelf) has a length nobody designed: it is however
/// many rows the document happens to have, so shortening it and letting it
/// scroll inside itself costs nothing but a scroll you were going to do anyway.
/// A group whose body is a form (Text, Position & Size, Effects) has a set of
/// controls somebody chose, and shortening it does not compress anything — it
/// just hides controls behind a second scroller, which is the same hunt one
/// level deeper.
///
/// So the arithmetic is: the forms are paid first at their natural height, and
/// whatever is left over is shared between the lists, tallest first, each down
/// to its own floor and no further. `overflow` says whether that was enough. It
/// often is not — the dock can simply be asked for more than it has — and then
/// the dock scrolls as it always did, only by much less.
///
/// A list is never STRETCHED to fill space it does not need: three layers draw
/// three rows, and the glass under them stays empty rather than the list
/// growing into it. (UX-PATTERNS §3 allows exactly one group per dock to grow
/// into the leftover; nothing in the app asks for that yet, and a Layers list
/// that changed height every time the leftover changed would be worse than the
/// gap it filled.)
///
/// One case is still over, on purpose. With two pieces of text picked in a
/// window as tall as the display allows, Effects runs 838-1030 in a 996 point
/// dock: 34 points below the fold, so Corner Radius sits on the bottom edge and
/// the line under it is cut off. Every other shape the dock takes fits. The 34
/// points are the multi-selection captions — each section speaking for several
/// layers says so under its own controls — and on 2026-09-07 the user was asked
/// whether to say that once instead of six times and answered leave the words
/// alone: the promise is worth repeating wherever the eye lands, and a short
/// scroll in this one case is the price. So do not "fix" this by trimming those
/// captions. Room for Effects has to come from somewhere else.
public enum DockHeightBudget {
    /// One group in the dock, as the budget sees it.
    public struct Group: Sendable, Equatable {
        /// Which group this is, so the caller can find its height again.
        public let key: String
        /// The height this group costs no matter what: its header, plus any
        /// part of its body that cannot scroll — the count line and the grab
        /// bar under the layers list, for instance.
        public let fixed: CGFloat
        /// How tall the scrollable part of the body would like to be. Zero for
        /// a form, and zero for a group that is collapsed.
        public let flexible: CGFloat
        /// The least that scrollable part may be squeezed to before the budget
        /// gives up and lets the dock scroll instead.
        public let floor: CGFloat

        public init(key: String, fixed: CGFloat, flexible: CGFloat, floor: CGFloat) {
            self.key = key
            self.fixed = max(0, fixed)
            self.flexible = max(0, flexible)
            self.floor = max(0, floor)
        }

        /// The shortest this group's list can be drawn: its floor, or its own
        /// content when there is less of it than the floor. A list of two rows
        /// is drawn as two rows, not padded out to look like four.
        var squeezed: CGFloat { min(flexible, floor) }
    }

    /// One block in a list whose entries are PANES rather than rows: an
    /// effect, drawn as a heading with its own settings folded under it.
    public struct Block: Sendable, Equatable {
        /// How tall this pane is right now, folded or open.
        public let height: CGFloat
        /// Whether its settings are showing.
        public let isOpen: Bool

        public init(height: CGFloat, isOpen: Bool) {
            self.height = max(0, height)
            self.isOpen = isOpen
        }
    }

    /// The most of the dock a list may claim as its floor for panes nobody
    /// asked to see. Reaching an open pane from the top of the list pays for
    /// every pane above it, and a floor that took the whole window would starve
    /// every group under it, so past this share the list gives up and scrolls
    /// inside itself like anything else. The pane you just opened is exempt:
    /// see `paneListFloor`.
    public static let floorShareOfDock: CGFloat = 0.45

    /// How short a list of PANES may be squeezed before the budget stops
    /// asking.
    ///
    /// A list of rows can be cut anywhere: the cut lands between two rows, or
    /// through one row that looks like the rows above it, and it reads as a
    /// list with more in it. A list of panes cannot. Each entry is a heading
    /// with a set of controls under it, so a cut lands through the middle of a
    /// slider, and a half-drawn slider reads as a rendering fault however
    /// carefully the edge is faded. Reported by the user on 2026-09-08: one
    /// border opened in a full dock, and the Width slider was sliced in half.
    ///
    /// So the rule for a pane list is: **whatever else is squeezed, one pane is
    /// drawn whole, and the entries either side of it show through the fade.**
    /// Nothing more is: three effects open is a list you scroll, and the cut
    /// edge fading is the honest answer there.
    ///
    /// WHICH pane is the whole of it. Told nothing, this is the first open one,
    /// and everything above it is counted in too, since a list left where it
    /// was starts at its beginning. Told which pane you just opened (`focus`),
    /// it is that one, measured from a peek at the entry above rather than from
    /// the top of the list, because opening a pane scrolls the list to it. That
    /// is the difference between opening the second of two effects in a short
    /// window and seeing its top half — the panel having kept room for the
    /// FIRST one — and seeing the effect you actually pressed.
    ///
    /// The two are capped differently on purpose. Reaching an open pane from
    /// the top of the list can drag in any number of panes nobody asked to see,
    /// so that stops at `floorShareOfDock`. The pane you just opened is the one
    /// thing you did ask for, so it may take as much of the dock as it needs,
    /// up to the whole of it, and the dock scrolls for the rest.
    ///
    /// The `peek` is not decoration. Squeezed to the open pane exactly, the cut
    /// lands in the gap between two entries and the section ends on clean empty
    /// glass: it reads as a list holding one effect, and the two under it are
    /// gone with nothing saying so (seen in a probe capture, 2026-09-08). A
    /// sliver of the next heading under the fade is what makes the edge mean
    /// "there is more" instead of "that is all".
    ///
    /// `spacing` is the gap between two panes and the insets are the padding
    /// the list draws above and below its stack. A list with nothing open in it
    /// is a list of headings, which cuts as cleanly as any row list, so it
    /// keeps `base`.
    /// - Parameter focus: the pane the user just opened, by its place in the
    ///   list. Ignored when it names a pane that is not there or is folded
    ///   shut, so a stale request quietly falls back to the first open pane.
    public static func paneListFloor(_ blocks: [Block],
                                     focus: Int? = nil,
                                     spacing: CGFloat,
                                     topInset: CGFloat,
                                     bottomInset: CGFloat,
                                     peek: CGFloat,
                                     base: CGFloat,
                                     viewport: CGFloat?) -> CGFloat {
        // What follows the pane: either there is more under it, and the cut
        // shows the top of it, or there is not, and the list ends on its own
        // padding.
        func below(_ index: Int) -> CGFloat {
            index == blocks.count - 1 ? bottomInset : spacing + peek
        }

        if let focus, blocks.indices.contains(focus), blocks[focus].isOpen {
            // A sliver of the entry above, so the top of the list reads as a
            // list rather than as the beginning of one.
            let above: CGFloat = focus == 0 ? topInset : peek + spacing
            let wanted = above + blocks[focus].height + below(focus)
            guard let viewport else { return max(base, wanted) }
            return max(base, min(wanted, viewport))
        }

        guard let openIndex = blocks.firstIndex(where: \.isOpen) else { return base }
        let through = blocks.prefix(through: openIndex)
        var wanted = topInset + through.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(through.count - 1)
        wanted += below(openIndex)
        guard let viewport else { return max(base, wanted) }
        return max(base, min(wanted, viewport * floorShareOfDock))
    }

    /// The height to draw each scrollable body at, by group key. Groups with
    /// nothing scrollable in them are absent.
    ///
    /// `viewport` is nil until the dock has been measured. That is one frame at
    /// launch, and squeezing every list to its floor for that frame and back
    /// again is a visible flinch, so an unmeasured dock is left alone.
    public static func flexibleHeights(_ groups: [Group],
                                       viewport: CGFloat?) -> [String: CGFloat] {
        let lists = groups.filter { $0.flexible > 0 }
        guard !lists.isEmpty else { return [:] }
        var heights: [String: CGFloat] = [:]

        guard let viewport else {
            for list in lists { heights[list.key] = list.flexible }
            return heights
        }

        let room = viewport - groups.reduce(0) { $0 + $1.fixed }
        let wanted = lists.reduce(0) { $0 + $1.flexible }
        // Room to spare: nothing is squeezed, and nothing is stretched either.
        if wanted <= room {
            for list in lists { heights[list.key] = list.flexible }
            return heights
        }
        // Not even the floors fit. Every list goes as short as it may, and the
        // dock scrolls the rest; `overflow` is how much.
        let floors = lists.reduce(0) { $0 + $1.squeezed }
        if floors >= room {
            for list in lists { heights[list.key] = list.squeezed }
            return heights
        }

        // Somewhere in between: find the water line. Every list is drawn at the
        // line, except that it never goes under its own floor and never over
        // its own content, so the tall ones give first and the short ones are
        // left alone until the line reaches them.
        let line = waterLine(lists, room: room)
        for list in lists {
            let height = min(list.flexible, max(list.squeezed, line))
            // Down to whole points, never up: rounding up is how a budget
            // spends room it does not have.
            heights[list.key] = height.rounded(.down)
        }
        return heights
    }

    /// How much taller than the dock the groups still are once every list has
    /// given what it can. Zero means the whole dock is on screen and the outer
    /// scroller has nothing to do.
    public static func overflow(_ groups: [Group], viewport: CGFloat?) -> CGFloat {
        guard let viewport else { return 0 }
        let heights = flexibleHeights(groups, viewport: viewport)
        let total = groups.reduce(0) { $0 + $1.fixed + (heights[$1.key] ?? 0) }
        return max(0, total - viewport)
    }

    /// The height every list is levelled to, solved exactly rather than
    /// searched for: the total handed out rises with the line in straight
    /// segments, and the segments turn only where some list meets its floor or
    /// runs out of content.
    private static func waterLine(_ lists: [Group], room: CGFloat) -> CGFloat {
        func handedOut(at line: CGFloat) -> CGFloat {
            lists.reduce(0) { $0 + min($1.flexible, max($1.squeezed, line)) }
        }
        let corners = Set(lists.flatMap { [$0.squeezed, $0.flexible] })
            .sorted()
        var low = corners.first ?? 0
        for corner in corners.dropFirst() {
            let atCorner = handedOut(at: corner)
            if atCorner >= room {
                // The line is between `low` and this corner, where the total
                // rises one point for every list still taking room.
                let base = handedOut(at: low)
                // The lists still taking room across this stretch: already off
                // their floor at the bottom of it, not yet out of content at
                // the top.
                let takers = CGFloat(lists.filter { $0.squeezed <= low && $0.flexible >= corner }
                    .count)
                guard takers > 0, atCorner > base else { return low }
                return low + (room - base) / takers
            }
            low = corner
        }
        return low
    }
}
