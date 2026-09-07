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
