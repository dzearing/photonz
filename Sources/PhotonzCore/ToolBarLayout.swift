import Foundation

/// A family of tools that shares ONE slot in the tool bar, the way a pro
/// editor has always folded its marquees or its shapes into a single button.
///
/// The slot shows the member you used last, a click picks that member up, and
/// press-and-hold lists the family. Each member keeps whatever letter it has,
/// a letter pressed again walks the members it owns, and shift plus any
/// member's letter walks the whole family, so a keyboard user never needs the
/// list.
public enum ToolGroup: String, CaseIterable, Hashable, Codable, Sendable {
    /// The region selectors: rectangle, ellipse, magic wand (Photoshop's M
    /// and W).
    case selection
    /// The plain drawing shapes: line, rectangle, ellipse. Arrow is NOT here:
    /// it is the redline tool people reach for most and never hides.
    case shapes
    /// Change what a thing's bounds are: Crop in space, Trim in time
    /// (`docs/design/video-surface.md` §10). Resize Image rides at the foot of
    /// the same flyout, so the slot has always been this family; Trim simply
    /// makes the family two tools instead of one.
    case bounds

    /// The members, in cycle order. The first is the default.
    public var tools: [Tool] {
        switch self {
        case .selection: [.rectSelect, .ellipseSelect, .wand]
        case .shapes: [.line, .rectangle, .ellipse]
        case .bounds: [.crop, .trim]
        }
    }

    /// The family's name, for its menu and its tooltip.
    public var title: String {
        switch self {
        case .selection: "Selection"
        case .shapes: "Shapes"
        case .bounds: "Crop and Trim"
        }
    }

    /// A letter that belongs to the family rather than to any member: it picks
    /// up the members that have no letter of their own, and walks them when
    /// pressed again. The marquee pair has no letters of its own, so M stands
    /// for the pair; the shapes each keep their own.
    public var groupKey: Character? {
        switch self {
        case .selection: "m"
        // Crop keeps its own C and Trim answers to the same letter, so the
        // pair walks on C without the family taking the letter off Crop — the
        // ungrouped bar still has a C that crops.
        case .shapes, .bounds: nil
        }
    }

    /// The members this document can actually use, in cycle order.
    ///
    /// A family can hold a tool that only some documents have anything for:
    /// Trim needs a duration, and in a screenshot there is nothing to trim. The
    /// ring is filtered before it is walked so C in a screenshot means Crop and
    /// pressing it again does nothing new. Filtered down to nothing it still
    /// stands for its first member, because a slot that vanishes is a slot that
    /// moves.
    public func tools(offered: Set<Tool>? = nil) -> [Tool] {
        guard let offered else { return tools }
        let kept = tools.filter { offered.contains($0) }
        return kept.isEmpty ? [tools[0]] : kept
    }

    /// Every letter that, with shift held, walks the family: the group key
    /// first, then each member's own key. Deduplicated, in that order.
    public var cycleKeys: [Character] { cycleKeys(offered: nil) }

    public func cycleKeys(offered: Set<Tool>? = nil) -> [Character] {
        var keys: [Character] = []
        if let groupKey { keys.append(groupKey) }
        for tool in tools(offered: offered) {
            if let key = tool.shortcutKey, !keys.contains(key) { keys.append(key) }
        }
        return keys
    }

    /// The members a PLAIN press of `key` walks, in the order it walks them.
    ///
    /// A member's own letter owns that member alone, so O is Ellipse however
    /// often you press it. The family's letter owns every member that has no
    /// letter of its own, which today is exactly Photoshop's marquee pair: M
    /// picks a marquee and pressing it again swaps the box for the ellipse.
    /// The wand has W of its own, so it is never what M hands you.
    public func tools(answeringTo key: Character, offered: Set<Tool>? = nil) -> [Tool] {
        let members = tools(offered: offered)
        if key == groupKey { return members.filter { $0.shortcutKey == nil } }
        return members.filter { $0.shortcutKey == key }
    }

    /// The tool a plain press of `key` picks up, given the tool in hand and
    /// the member this family remembers. Nil for a letter the family does not
    /// answer to.
    ///
    /// Already holding one of the letter's tools means the press moves on to
    /// the next one; otherwise you get the remembered member when the letter
    /// owns it, and the letter's first tool when it does not.
    public func tool(forKey key: Character, active: Tool, remembered: Tool,
                     offered: Set<Tool>? = nil) -> Tool? {
        let ring = tools(answeringTo: key, offered: offered)
        guard !ring.isEmpty else { return nil }
        if let index = ring.firstIndex(of: active) { return ring[(index + 1) % ring.count] }
        return ring.contains(remembered) ? remembered : ring[0]
    }

    /// The letters that hand you a DIFFERENT tool when you press them again,
    /// so a tooltip can teach that without the bar guessing which ones do.
    public var swapKeys: [Character] { swapKeys(offered: nil) }

    public func swapKeys(offered: Set<Tool>? = nil) -> [Character] {
        cycleKeys(offered: offered).filter { tools(answeringTo: $0, offered: offered).count > 1 }
    }

    /// The member after `tool`, wrapping. A tool from outside the family
    /// starts the walk at the first member.
    public func next(after tool: Tool, offered: Set<Tool>? = nil) -> Tool {
        let members = tools(offered: offered)
        guard let index = members.firstIndex(of: tool) else { return members[0] }
        return members[(index + 1) % members.count]
    }

    /// The member a stored raw value names, or the first member when the
    /// value is missing, stale, or names a tool outside the family.
    public func member(from raw: String?) -> Tool {
        guard let raw, let tool = Tool(rawValue: raw), tools.contains(tool) else { return tools[0] }
        return tool
    }

    /// The family holding `tool`, nil for a tool that stands alone.
    public static func containing(_ tool: Tool) -> ToolGroup? {
        allCases.first { $0.tools.contains(tool) }
    }
}

/// The tool bar's order: families of slots, each slot a lone tool or a
/// group. Pure data, so the order is a tested product decision rather than
/// whatever the view happened to list.
///
/// The families read left to right as what you do to a picture: pick and cut
/// and measure it, draw on it, paint it. Photoshop's principle (families, one
/// slot per family, last member remembered) rather than its literal sequence,
/// because it has no arrow, highlight or zoom callout to place.
public struct ToolBarLayout: Hashable, Sendable {
    public enum Entry: Hashable, Sendable, Codable {
        case tool(Tool)
        case group(ToolGroup)
        /// The timeline's Blade. Not a canvas tool (a click on the picture has
        /// nothing to cut), so it is not a `Tool`: it is the same Blade the
        /// timeline's own bar holds, and only a document with time shows it.
        case blade
    }

    public let families: [[Entry]]

    public init(families: [[Entry]]) {
        self.families = families
    }

    /// Every slot in bar order, families flattened.
    public var entries: [Entry] { families.flatMap { $0 } }

    /// The slot that stands for `tool`: its group's, or its own.
    ///
    /// A family whose slot the bar draws as a lone tool — Crop's, which holds
    /// Trim as well but is only ever drawn once — answers with that tool, so
    /// asking where Trim lives gives back the slot a person can actually see.
    public func entry(for tool: Tool) -> Entry? {
        if let group = ToolGroup.containing(tool) {
            if entries.contains(.group(group)) { return .group(group) }
            if let member = group.tools.first(where: { entries.contains(.tool($0)) }) {
                return .tool(member)
            }
        }
        return entries.contains(.tool(tool)) ? .tool(tool) : nil
    }

    /// The grouped bar. Resize Image is not a tool and is not listed: it rides
    /// at the foot of the Crop flyout, the same family (change the picture's
    /// bounds), and in the Image menu.
    public static let families = bar(withFrame: false)

    /// The bar with the frame tool in it (Next, `next-frames`). It joins the
    /// end of the drawing family — a frame IS something you draw on the canvas —
    /// rather than being spliced in earlier, so no tool anybody already reaches
    /// for moves to a new slot.
    public static let familiesWithFrame = ToolBarLayout.bar(withFrame: true)

    /// The bar as this release's flags leave it.
    ///
    /// Every tool a flag adds joins the END of the drawing family, never the
    /// middle: a slot a person has already learned the position of must not
    /// move because they turned something else on.
    ///
    /// The one exception is the lens, which takes the ZOOM CALLOUT'S slot
    /// rather than joining the end. The two were the same idea drawn twice — a
    /// box that shows the picture underneath differently — so the callout is
    /// now what the Lens does when it is set to Magnify (`LensKind`), and the
    /// bar carries one box for both instead of two side by side. The lens
    /// inherits the slot rather than the callout keeping it because the slot is
    /// now the wider thing: six kinds, of which magnify is one.
    public static func bar(withFrame: Bool, withLens: Bool = false,
                           withPen: Bool = false, withComponent: Bool = false) -> ToolBarLayout {
        var drawing: [Entry] = [.tool(.arrow), .group(.shapes), .tool(.highlight),
                                .tool(.text)]
        drawing.append(withLens ? .tool(.lens) : .tool(.zoomCallout))
        if withFrame { drawing.append(.tool(.frame)) }
        if withPen { drawing.append(.tool(.pen)) }
        if withComponent { drawing.append(.tool(.component)) }
        return ToolBarLayout(families: [
            [.tool(.select), .group(.selection), .tool(.crop), .tool(.measure)],
            drawing,
            [.tool(.fill)],
        ])
    }
}

/// A tool bar with some of its slots in front and the rest folded under More.
///
/// The bar shows every slot that fits the room it has and folds only the rest,
/// the way Photoshop, Final Cut and Keynote overflow a tool strip: widen the
/// window and tools come back, narrow it and they fold from the end, and More
/// is there only while something is in it. The fold is by SLOT, so a family is
/// never split (`docs/design/modes.md` §2), and every folded tool keeps its key
/// and its row under More; nothing is removed.
///
/// A document with time puts the video's own tools first (`videoLeading`), so
/// they are the last to fold; a picture folds from the end of its own bar.
public struct ToolBarFold: Hashable, Sendable {
    /// The slots in front, in families, a hairline between each.
    public let shown: [[ToolBarLayout.Entry]]
    /// Every slot that is not in front, in the order the bar would draw it.
    public let folded: [ToolBarLayout.Entry]

    /// How wide the things on the bar are, which is all the fold needs to
    /// know about how the bar is drawn. The bar is one row: slots, a hairline
    /// between families and More at the end, `gap` between every two of them.
    public struct Metrics: Hashable, Sendable {
        /// A slot nobody has measured: one control.
        public var slot: CGFloat
        /// Between any two neighbours on the row.
        public var gap: CGFloat
        /// A hairline's own width, the room either side of it included.
        public var hairline: CGFloat
        /// The More button.
        public var more: CGFloat
        /// Slots measured wider or narrower than `slot`, as they were drawn.
        public var widths: [ToolBarLayout.Entry: CGFloat]

        public init(slot: CGFloat, gap: CGFloat, hairline: CGFloat, more: CGFloat,
                    widths: [ToolBarLayout.Entry: CGFloat] = [:]) {
            self.slot = slot
            self.gap = gap
            self.hairline = hairline
            self.more = more
            self.widths = widths
        }

        public func width(of entry: ToolBarLayout.Entry) -> CGFloat {
            widths[entry] ?? slot
        }

        /// The row `families` draw, with More at its end or not.
        public func width(of families: [[ToolBarLayout.Entry]], more hasMore: Bool) -> CGFloat {
            let rows = families.filter { !$0.isEmpty }
            var total: CGFloat = 0
            var children = 0
            for (index, family) in rows.enumerated() {
                if index > 0 { total += hairline; children += 1 }
                for entry in family { total += width(of: entry); children += 1 }
            }
            if hasMore { total += more; children += 1 }
            return total + gap * CGFloat(max(0, children - 1))
        }
    }

    /// Folds `layout` down to `front`. A front slot the layout does not hold
    /// (the Blade, which only a document with time has) is kept as it is.
    public init(_ layout: ToolBarLayout, front: [[ToolBarLayout.Entry]]) {
        var seen: Set<ToolBarLayout.Entry> = []
        var shown: [[ToolBarLayout.Entry]] = []
        for family in front {
            var kept: [ToolBarLayout.Entry] = []
            for entry in family {
                let slot = Self.slot(for: entry, in: layout)
                if seen.insert(slot).inserted { kept.append(slot) }
            }
            if !kept.isEmpty { shown.append(kept) }
        }
        self.shown = shown
        self.folded = layout.entries.filter { !seen.contains($0) }
    }

    /// Folds `layout` to the `room` it has: as many slots as fit, in priority
    /// order, and More for the rest only when there is a rest.
    ///
    /// Priority is `leading` first (the video's own tools on a document with
    /// time), then the rest of the bar in its own order, so the slots that
    /// fold first are the ones at the far end. The row is drawn as `leading`'s
    /// families and then the bar's own families, each holding only what is in
    /// front, so a slot coming or going never reorders the ones that stay.
    ///
    /// `lit` is the slot in hand. When it would fold it takes the place of the
    /// lowest slots that make room for it, so a tool you are holding is on the
    /// bar whenever the bar has room for it at all; with none it stays under
    /// More and More lights.
    public init(_ layout: ToolBarLayout, leading: [[ToolBarLayout.Entry]] = [],
                room: CGFloat, metrics: Metrics, keeping lit: ToolBarLayout.Entry? = nil) {
        self.init(drawing: Self.drawingOrder(layout, leading: leading), folding: [],
                  room: room, metrics: metrics, keeping: lit)
    }

    /// Folds `layout` to a mode's `strip` (`WindowMode.toolStrip`): only the
    /// strip's slots can be in front, in the strip's order and families, as
    /// many as fit the `room`; every other slot of the bar is under More in the
    /// bar's own order, with its key and its row.
    ///
    /// A strip slot the layout does not hold (a tool this release has not
    /// switched on) is left out rather than drawn dead. `lit` swaps in only
    /// from the strip: a tool from outside it stays under More and More lights,
    /// because the mode chose what is in front.
    public init(_ layout: ToolBarLayout, strip: [[ToolBarLayout.Entry]],
                room: CGFloat, metrics: Metrics, keeping lit: ToolBarLayout.Entry? = nil) {
        var seen: Set<ToolBarLayout.Entry> = []
        var draw: [[ToolBarLayout.Entry]] = []
        for family in strip {
            var kept: [ToolBarLayout.Entry] = []
            for entry in family {
                let slot = Self.slot(for: entry, in: layout)
                guard layout.entries.contains(slot) else { continue }
                if seen.insert(slot).inserted { kept.append(slot) }
            }
            if !kept.isEmpty { draw.append(kept) }
        }
        self.init(drawing: draw, folding: layout.entries.filter { !seen.contains($0) },
                  room: room, metrics: metrics, keeping: lit)
    }

    /// The fold both public room-based folds share: `draw` is every slot that
    /// may be in front, in families and priority order; `rest` is under More
    /// whatever the room.
    private init(drawing draw: [[ToolBarLayout.Entry]], folding rest: [ToolBarLayout.Entry],
                 room: CGFloat, metrics: Metrics, keeping lit: ToolBarLayout.Entry?) {
        let priority = draw.flatMap { $0 }
        func row(_ keep: Set<ToolBarLayout.Entry>) -> [[ToolBarLayout.Entry]] {
            draw.map { $0.filter(keep.contains) }.filter { !$0.isEmpty }
        }
        func fits(_ keep: Set<ToolBarLayout.Entry>) -> Bool {
            metrics.width(of: row(keep), more: keep.count < priority.count || !rest.isEmpty) <= room
        }
        var count = priority.count
        while count > 0, !fits(Set(priority.prefix(count))) { count -= 1 }
        var keep = Set(priority.prefix(count))
        if let lit, priority.contains(lit), !keep.contains(lit) {
            var fewer = count
            while fewer >= 0 {
                let swapped = Set(priority.prefix(fewer)).union([lit])
                if fits(swapped) { keep = swapped; break }
                fewer -= 1
            }
        }
        self.shown = row(keep)
        self.folded = priority.filter { !keep.contains($0) } + rest
    }

    /// The families the bar draws in, left to right: `leading`'s, then the
    /// bar's own with what `leading` already took out of them. Empty families
    /// are left out, and a slot is never drawn twice.
    private static func drawingOrder(_ layout: ToolBarLayout,
                                     leading: [[ToolBarLayout.Entry]]) -> [[ToolBarLayout.Entry]] {
        var seen: Set<ToolBarLayout.Entry> = []
        var families: [[ToolBarLayout.Entry]] = []
        for family in leading + layout.families {
            var kept: [ToolBarLayout.Entry] = []
            for entry in family {
                let slot = slot(for: entry, in: layout)
                if seen.insert(slot).inserted { kept.append(slot) }
            }
            if !kept.isEmpty { families.append(kept) }
        }
        return families
    }

    /// The slot in `layout` that `entry` stands for: a member of a family is
    /// the family's slot, so asking for Rectangle keeps all three shapes.
    private static func slot(for entry: ToolBarLayout.Entry,
                             in layout: ToolBarLayout) -> ToolBarLayout.Entry {
        switch entry {
        case .tool(let tool): layout.entry(for: tool) ?? entry
        case .group(let group): group.tools.lazy.compactMap { layout.entry(for: $0) }.first ?? entry
        case .blade: entry
        }
    }

    /// The tools every document with time puts first, as `video.html` draws
    /// them: Select, then Blade, Title / Text and Shape, then Measure
    /// (UX-PATTERNS D4, video). The mock's Hand and Zoom are not tools in this
    /// app (space-drag, pinch and the View menu do those jobs), so they are
    /// not here.
    public static let videoLeading: [[ToolBarLayout.Entry]] = [
        [.tool(.select)],
        [.blade, .tool(.text), .group(.shapes)],
        [.tool(.measure)],
    ]

    /// Every slot in front, families flattened.
    public var shownEntries: [ToolBarLayout.Entry] { shown.flatMap { $0 } }

    /// The slot, in front or under More, that stands for `tool`.
    public func entry(for tool: Tool) -> ToolBarLayout.Entry? {
        ToolBarLayout(families: shown + [folded]).entry(for: tool)
    }

    /// Whether `tool` lives under More.
    public func isFolded(_ tool: Tool) -> Bool {
        entry(for: tool).map(folded.contains) ?? false
    }

    /// The one slot that is lit. The Blade in hand outranks the canvas tool,
    /// because arming it is putting everything else down, and a bar with two
    /// tools lit is a bar that cannot say which one a click will use.
    public func lit(activeTool: Tool, bladeInHand: Bool) -> ToolBarLayout.Entry? {
        if bladeInHand, shownEntries.contains(.blade) { return .blade }
        return entry(for: activeTool)
    }
}
