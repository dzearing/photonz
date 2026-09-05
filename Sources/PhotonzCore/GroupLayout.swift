import CoreGraphics
import Foundation

/// A group that arranges its own contents.
///
/// Two shapes, and they are the two people actually draw: a **stack** lays
/// everything out along one axis with an even gap, and a **grid** fills rows of
/// equal cells. Set one on a group and you stop nudging things into place: add
/// a row, delete a row, drag one past another, and the group puts everything
/// back in order on its own.
///
/// The rule that keeps this small: **the flow owns the axis it flows along, and
/// the placement rules this app already has own the other one**
/// (`LayerPlacement`). A column stack decides every Y; whether a row sits left,
/// centred, right or stretched across is the same Horizontal menu that was
/// already in the Layout section, and any one layer can still answer it
/// differently for itself. So nothing here is a second way to say "centre it".
///
/// See `docs/design/ui-building.md`, "A group can arrange its own contents".
public enum GroupLayoutKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// One line of contents, along one axis, with an even gap.
    case stack
    /// Rows of equal cells, filled left to right and wrapped at a column count.
    case grid

    /// What the inspector calls it.
    public var title: String {
        switch self {
        case .stack: "Stack"
        case .grid: "Grid"
        }
    }
}

/// Which way a stack runs.
public enum StackDirection: String, CaseIterable, Hashable, Codable, Sendable {
    case row
    case column

    public var title: String {
        switch self {
        case .row: "Row"
        case .column: "Column"
        }
    }

    /// True when the flow runs left to right, so the OTHER axis is the one the
    /// placement rules answer for.
    public var isHorizontal: Bool { self == .row }
}

/// How a group arranges what is inside it: which shape, and the numbers that
/// shape it. Every number is typed, never dragged for, because "12 points
/// between the rows" is the thing being built to.
public struct GroupLayout: Hashable, Codable, Sendable {
    /// Which shape this group arranges its contents in, or nil for a group
    /// that arranges nothing and simply closes around what is inside it. A
    /// group that has never been given a layout at all has none of this and is
    /// left exactly as it was drawn; the moment somebody asks for room at its
    /// edges or a size of its own, it gets one of these with no kind.
    public var kind: GroupLayoutKind?
    /// Which way a stack runs. A grid always fills rows left to right, so this
    /// is ignored there and kept, so flipping between the two does not lose it.
    public var direction: StackDirection
    /// How many cells a grid puts in a row before it wraps. Never below one.
    public var columns: Int
    /// The space between one thing and the next along the flow: between the
    /// items of a stack, and between the columns of a grid.
    public var gap: CGFloat
    /// Whether a stack shares the room it has LEFT OVER between its rows
    /// instead of holding the gap above. A nav bar is a logo at one end and
    /// buttons at the other, and that is the only shape a single gap cannot
    /// make. There is only room to share where the stack is bigger than its
    /// contents, so this does nothing at all on a stack that is the size of
    /// what is inside it, and `couldSpread` is what the inspector asks before
    /// it offers the choice. The gap itself is KEPT while this is on, so
    /// turning it back off restores the number that was there.
    public var spreadsGap: Bool = false
    /// The space between a grid's rows. Kept apart from `gap` because a card
    /// grid usually wants more air above than beside.
    public var rowGap: CGFloat
    /// The room kept clear inside the edges, on each of the four sides. A group
    /// that arranges itself has edges of its own — whether it was given a size
    /// or takes the one its contents make — so the contents start this far in
    /// and the box carries this much on each side. One number typed once still
    /// means the same room all round.
    public var padding: GroupPadding
    /// How wide this group is, or nil for a group that is as wide as whatever
    /// is inside it. A number here is what lets a menu be 320 points wide and
    /// every row stretch to that width without building it on a screen.
    /// Ignored on a screen, whose box is its own frame.
    public var width: CGFloat?
    /// How tall this group is, or nil for a group as tall as its contents.
    public var height: CGFloat?
    /// The narrowest this group may ever be, or nil where nothing holds it
    /// open. A button with one letter in it is still a button because of this
    /// number; without one it is as narrow as one letter plus its room.
    public var minWidth: CGFloat?
    /// The widest this group may ever get, or nil where nothing stops it. What
    /// keeps a card with a very long title from running off the screen.
    public var maxWidth: CGFloat?
    /// The shortest this group may ever be, or nil where nothing holds it open.
    public var minHeight: CGFloat?
    /// The tallest this group may ever get, or nil where nothing stops it.
    public var maxHeight: CGFloat?

    /// The gap a layout starts with when nothing suggests another: the same 12
    /// points the starter components are built on.
    public static let defaultGap: CGFloat = 12
    public static let defaultColumns = 3

    /// What the Arrangement row calls a group that arranges nothing.
    public static let freeTitle = "Free"

    /// A group that arranges nothing and closes around what is inside it:
    /// everything stays where it was put, and the box is as big as the pieces
    /// plus the room at the edges, on either axis that was given no size.
    public static func free(padding: GroupPadding = .none,
                            width: CGFloat? = nil, height: CGFloat? = nil) -> GroupLayout {
        GroupLayout(kind: nil, padding: padding, width: width, height: height)
    }

    public init(kind: GroupLayoutKind?,
                direction: StackDirection = .column,
                columns: Int = GroupLayout.defaultColumns,
                gap: CGFloat = GroupLayout.defaultGap,
                spreadsGap: Bool = false,
                rowGap: CGFloat = GroupLayout.defaultGap,
                padding: GroupPadding = .none,
                width: CGFloat? = nil,
                height: CGFloat? = nil,
                minWidth: CGFloat? = nil,
                maxWidth: CGFloat? = nil,
                minHeight: CGFloat? = nil,
                maxHeight: CGFloat? = nil) {
        self.kind = kind
        self.direction = direction
        self.columns = columns
        self.gap = gap
        self.spreadsGap = spreadsGap
        self.rowGap = rowGap
        self.padding = padding
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    /// The column count actually used. A grid of nought columns is not a thing
    /// anyone means, and typing over the field passes through zero on the way
    /// to a number, so it is read as one rather than refused.
    public var usedColumns: Int { max(1, columns) }

    /// The gaps actually used. Negative space between two things is a look
    /// (overlapping avatars), but it is not what a typed number that slipped
    /// below nought means, so the model holds the floor.
    public var usedGap: CGFloat { max(0, gap) }
    public var usedRowGap: CGFloat { max(0, rowGap) }

    /// Whether this layout actually spreads its contents. Only a stack does:
    /// a grid already shares its width out between its columns, and a group
    /// that arranges nothing has no gap to spread in the first place.
    public var spreadsContents: Bool { kind == .stack && spreadsGap }

    /// Whether spreading could do anything here, which is the question the
    /// Gap row asks before it offers the choice. A stack only has room to
    /// share where the axis it FLOWS along is bigger than its contents: a
    /// size of its own, or a floor holding it open. A row told how tall it is
    /// still has nothing left over across. A screen is a box somebody drew, so
    /// the app answers that one for itself.
    public var couldSpread: Bool {
        guard kind == .stack else { return false }
        return direction.isHorizontal ? (usedWidth != nil || usedMinWidth != nil)
                                      : (usedHeight != nil || usedMinHeight != nil)
    }
    public var usedPadding: GroupPadding { padding.used }

    /// The size actually used on each axis: the number given, never negative,
    /// or nil where the group is the size of what is in it. A number that is
    /// not a real number is read as no number at all rather than handing the
    /// flow an infinity.
    public var usedWidth: CGFloat? { Self.usedSide(width) }
    public var usedHeight: CGFloat? { Self.usedSide(height) }

    private static func usedSide(_ side: CGFloat?) -> CGFloat? {
        guard let side, side.isFinite else { return nil }
        return max(0, side)
    }

    /// Whether this group is the size of whatever is inside it, one axis at a
    /// time. What the inspector's Width and Height rows say.
    public var hugsWidth: Bool { usedWidth == nil }
    public var hugsHeight: Bool { usedHeight == nil }

    // MARK: - The smallest and the largest it may get

    /// The limits actually kept, read the same forgiving way as every other
    /// number here: a number that is not a real number is no limit at all
    /// rather than an infinity handed to the flow, and one below nought is
    /// nought, because typing over a field passes through odd values on the
    /// way to a number.
    public var usedMinWidth: CGFloat? { Self.usedSide(minWidth) }
    public var usedMaxWidth: CGFloat? { Self.usedSide(maxWidth) }
    public var usedMinHeight: CGFloat? { Self.usedSide(minHeight) }
    public var usedMaxHeight: CGFloat? { Self.usedSide(maxHeight) }

    /// Whether anything at all holds this axis, which is the only question the
    /// flow has to ask before doing any extra work for limits.
    public var limitsWidth: Bool { usedMinWidth != nil || usedMaxWidth != nil }
    public var limitsHeight: Bool { usedMinHeight != nil || usedMaxHeight != nil }
    public var limitsSize: Bool { limitsWidth || limitsHeight }

    /// A width held to what this group is allowed to be.
    public func heldWidth(_ width: CGFloat) -> CGFloat {
        Self.held(width, least: usedMinWidth, most: usedMaxWidth)
    }

    /// A height held to what this group is allowed to be.
    public func heldHeight(_ height: CGFloat) -> CGFloat {
        Self.held(height, least: usedMinHeight, most: usedMaxHeight)
    }

    /// A size held to what this group is allowed to be, on both axes at once.
    public func held(_ size: CGSize) -> CGSize {
        CGSize(width: heldWidth(size.width), height: heldHeight(size.height))
    }

    /// The smallest wins where the two cross. Somebody typing 96 over a 9
    /// passes through that state on the way, so it has to mean something
    /// sensible rather than being refused, and "the floor wins" is the rule
    /// anybody who has written a stylesheet already carries.
    private static func held(_ side: CGFloat, least: CGFloat?, most: CGFloat?) -> CGFloat {
        var out = side
        if let most { out = Swift.min(out, most) }
        if let least { out = Swift.max(out, least) }
        return out
    }

    /// What the limits say, in words, or nil where there are none. The Layout
    /// section reads this out under the rows, so a group that stopped growing
    /// says why rather than looking stuck.
    public var limitsSentence: String? {
        let clauses = [usedMinWidth.map { "narrower than \(Int($0.rounded()))" },
                       usedMaxWidth.map { "wider than \(Int($0.rounded()))" },
                       usedMinHeight.map { "shorter than \(Int($0.rounded()))" },
                       usedMaxHeight.map { "taller than \(Int($0.rounded()))" }]
            .compactMap { $0 }
        guard !clauses.isEmpty else { return nil }
        return "It never gets " + clauses.joined(separator: " or ") + "."
    }

    /// Which axis the flow itself decides. The other one is the placement
    /// rules', and the inspector says so rather than leaving a live menu that
    /// changes nothing.
    public var flowsHorizontally: Bool { kind == .stack && direction.isHorizontal }

    /// Whether this group puts its contents somewhere at all. A stack and a
    /// grid do; a group that only closes around what is in it leaves them
    /// where they were put, so Scale, dragging and typed positions all still
    /// mean what they always did.
    public var arranges: Bool { kind != nil }

    /// What the Arrangement row shows for this layout.
    public var title: String { kind?.title ?? Self.freeTitle }

    /// Whether the flow itself decides how TALL the things in it are. A grid
    /// shares its cell height out and a row hands every item the height of the
    /// row, so a Stretch down the box means something in both. A column runs
    /// down the page, where each item's height is its own and there is nothing
    /// for that choice to fill.
    public var decidesHeight: Bool { kind != .stack || direction.isHorizontal }

    private enum CodingKeys: String, CodingKey {
        case kind, direction, columns, gap, spreadsGap, rowGap, padding, width, height
        case minWidth, maxWidth, minHeight, maxHeight
    }

    /// Read forgivingly: a layout saved by an older build that knew fewer
    /// numbers opens with this build's defaults rather than refusing to open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // No kind at all is a group that arranges nothing and only closes
        // around what is in it. Every document written before that existed
        // names its kind, so nothing already saved reads as one.
        kind = try c.decodeIfPresent(GroupLayoutKind.self, forKey: .kind)
        direction = try c.decodeIfPresent(StackDirection.self, forKey: .direction) ?? .column
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? GroupLayout.defaultColumns
        gap = try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? GroupLayout.defaultGap
        // A stack saved before a row could push its contents to its two ends
        // opens holding the one gap it always held, which is what it was.
        spreadsGap = try c.decodeIfPresent(Bool.self, forKey: .spreadsGap) ?? false
        rowGap = try c.decodeIfPresent(CGFloat.self, forKey: .rowGap) ?? GroupLayout.defaultGap
        // Either shape of room: the single number older documents hold, or the
        // four sides a card with uneven room needs.
        padding = try c.decodeIfPresent(GroupPadding.self, forKey: .padding) ?? .none
        // A group saved before a stack could be given a size of its own opens
        // as one that is the size of its contents, which is what it was.
        width = try c.decodeIfPresent(CGFloat.self, forKey: .width)
        height = try c.decodeIfPresent(CGFloat.self, forKey: .height)
        // A group saved before there were limits opens with none, which is
        // exactly what it had, and a layout that carries none writes none, so
        // a document nobody set one on stays the file it always was.
        minWidth = try c.decodeIfPresent(CGFloat.self, forKey: .minWidth)
        maxWidth = try c.decodeIfPresent(CGFloat.self, forKey: .maxWidth)
        minHeight = try c.decodeIfPresent(CGFloat.self, forKey: .minHeight)
        maxHeight = try c.decodeIfPresent(CGFloat.self, forKey: .maxHeight)
    }

    /// Written by hand for one reason: a stack that holds one gap writes
    /// nothing at all about spreading, so every document saved before rows
    /// could push to their ends is byte for byte the file it always was.
    /// Everything else is written exactly as it always was, in the order it
    /// always was, and `everyNumberRoundTrips` in the tests is what stops the
    /// next number added here from being forgotten in this list.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encode(direction, forKey: .direction)
        try c.encode(columns, forKey: .columns)
        try c.encode(gap, forKey: .gap)
        if spreadsGap { try c.encode(true, forKey: .spreadsGap) }
        try c.encode(rowGap, forKey: .rowGap)
        try c.encode(padding, forKey: .padding)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encodeIfPresent(minWidth, forKey: .minWidth)
        try c.encodeIfPresent(maxWidth, forKey: .maxWidth)
        try c.encodeIfPresent(minHeight, forKey: .minHeight)
        try c.encodeIfPresent(maxHeight, forKey: .maxHeight)
    }
}

// MARK: - The space kept clear inside the edges

/// The room a group leaves inside its own four edges.
///
/// One number is the common case and stays one number: type 16 and every side
/// gets 16. Real cards are not symmetric though — contents 16 in from the left,
/// 12 down from the top and 24 up from the bottom is an ordinary card — so each
/// side is its own number underneath, and a card like that gets built by typing
/// rather than by nudging pieces about.
///
/// It SAVES as a single number for as long as all four agree, which is exactly
/// what every document written before there were four sides holds. Those
/// documents open with the room they had and save again unchanged.
public struct GroupPadding: Hashable, Codable, Sendable {
    public var top: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat

    /// No room on any side: what a group has until somebody asks for some, and
    /// what every document written before this existed comes back as.
    public static let none = GroupPadding(0)

    public init(top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// The same room on all four sides.
    public init(_ all: CGFloat) {
        self.init(top: all, right: all, bottom: all, left: all)
    }

    /// Which edge, in the order they are shown and typed: clockwise from the
    /// top, the order anybody who has written a CSS shorthand already carries.
    public enum Side: String, CaseIterable, Hashable, Sendable {
        case top, right, bottom, left

        /// What the inspector calls it.
        public var title: String {
            switch self {
            case .top: "Top"
            case .right: "Right"
            case .bottom: "Bottom"
            case .left: "Left"
            }
        }
    }

    public subscript(side: Side) -> CGFloat {
        get {
            switch side {
            case .top: top
            case .right: right
            case .bottom: bottom
            case .left: left
            }
        }
        set {
            switch side {
            case .top: top = newValue
            case .right: right = newValue
            case .bottom: bottom = newValue
            case .left: left = newValue
            }
        }
    }

    /// The one number all four sides are, or nil where they disagree. What the
    /// single Padding field shows, and what it goes blank for.
    public var uniform: CGFloat? {
        top == right && right == bottom && bottom == left ? top : nil
    }

    public var isUniform: Bool { uniform != nil }

    /// The room actually kept. Negative room is not a thing anyone means, and
    /// typing over a field passes through odd values on the way to a number,
    /// so the model holds the floor rather than refusing the typing.
    public var used: GroupPadding {
        GroupPadding(top: Self.usedSide(top), right: Self.usedSide(right),
                     bottom: Self.usedSide(bottom), left: Self.usedSide(left))
    }

    private static func usedSide(_ side: CGFloat) -> CGFloat {
        side.isFinite ? max(0, side) : 0
    }

    /// The four numbers, clockwise from the top, the way a CSS shorthand
    /// writes them: `16/16/24/16`.
    ///
    /// What the single Padding field shows when the four sides are CLOSED and
    /// disagree. Closing them used to leave the word Mixed and nothing else,
    /// so room typed on one side was unreadable until they were opened again.
    public var shorthand: String {
        Side.allCases.map { "\(Int(self[$0].rounded()))" }.joined(separator: "/")
    }

    /// The same four numbers with their sides named: `12 top, 16 right, 24
    /// bottom, 16 left`. For anywhere there is room for words — a tooltip, and
    /// the sentence a copy reads its original's room off — so nobody has to
    /// already carry the clockwise order to know which number is which.
    public var inWords: String {
        Side.allCases.map { "\(Int(self[$0].rounded())) \($0.rawValue)" }
            .joined(separator: ", ")
    }

    /// The room taken out of the width, and out of the height.
    public var horizontal: CGFloat { left + right }
    public var vertical: CGFloat { top + bottom }

    private enum CodingKeys: String, CodingKey { case top, right, bottom, left }

    /// Read either shape: the single number every older document holds, or the
    /// four sides a card with uneven room needs.
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(CGFloat.self) {
            self.init(single)
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(top: try c.decodeIfPresent(CGFloat.self, forKey: .top) ?? 0,
                      right: try c.decodeIfPresent(CGFloat.self, forKey: .right) ?? 0,
                      bottom: try c.decodeIfPresent(CGFloat.self, forKey: .bottom) ?? 0,
                      left: try c.decodeIfPresent(CGFloat.self, forKey: .left) ?? 0)
        }
    }

    /// Written as one number while the sides agree, so a document that never
    /// asked for uneven room is byte for byte the file it always was.
    public func encode(to encoder: Encoder) throws {
        if let uniform {
            var c = encoder.singleValueContainer()
            try c.encode(uniform)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(top, forKey: .top)
        try c.encode(right, forKey: .right)
        try c.encode(bottom, forKey: .bottom)
        try c.encode(left, forKey: .left)
    }
}

/// One number where four are wanted: `padding: 16` still means 16 all round,
/// so nothing that only ever wanted even room has to say so four times.
extension GroupPadding: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public init(integerLiteral value: Int) { self.init(CGFloat(value)) }
    public init(floatLiteral value: Double) { self.init(CGFloat(value)) }
}

// MARK: - Reading a layout off what somebody already arranged by hand

extension GroupLayout {

    /// The layout that best describes where these boxes ALREADY are.
    ///
    /// This is what makes turning a hand-arranged group into a stack safe: a
    /// row somebody spaced by eye at 16 points comes back as a row with a gap
    /// of 16, so pressing the button moves nothing. Where the spacing is
    /// uneven the average wins, which is the tidy-up you were going to do by
    /// hand anyway.
    public static func inferred(from boxes: [CGRect], kind: GroupLayoutKind,
                                container: CGRect?) -> GroupLayout {
        var layout = GroupLayout(kind: kind, padding: inferredPadding(boxes, container))
        guard boxes.count > 1 else { return layout }
        let union = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        let widest = boxes.map(\.width).max() ?? 0
        let tallest = boxes.map(\.height).max() ?? 0
        // Which way is this arrangement actually spread out? The box everything
        // occupies, minus the biggest single thing in it, is the run.
        layout.direction = (union.width - widest) > (union.height - tallest) ? .row : .column
        if kind == .stack {
            layout.gap = gap(between: boxes, horizontal: layout.direction.isHorizontal)
        } else {
            let rows = GroupFlow.rows(of: boxes)
            layout.columns = max(1, rows.map(\.count).max() ?? GroupLayout.defaultColumns)
            layout.gap = gap(between: rows.first?.map { boxes[$0] } ?? [], horizontal: true)
            layout.rowGap = gapBetweenRows(rows.map { $0.map { boxes[$0] } })
        }
        return layout
    }

    /// The average space between neighbours along one axis, rounded to a whole
    /// point. Half-point gaps are exactly what typed numbers exist to stop.
    private static func gap(between boxes: [CGRect], horizontal: Bool) -> CGFloat {
        guard boxes.count > 1 else { return GroupLayout.defaultGap }
        let ordered = boxes.sorted { horizontal ? $0.minX < $1.minX : $0.minY < $1.minY }
        var total: CGFloat = 0
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            total += horizontal ? next.minX - previous.maxX : next.minY - previous.maxY
        }
        return max(0, (total / CGFloat(ordered.count - 1)).rounded())
    }

    private static func gapBetweenRows(_ rows: [[CGRect]]) -> CGFloat {
        guard rows.count > 1 else { return GroupLayout.defaultGap }
        var total: CGFloat = 0
        for (previous, next) in zip(rows, rows.dropFirst()) {
            let bottom = previous.map(\.maxY).max() ?? 0
            let top = next.map(\.minY).min() ?? 0
            total += top - bottom
        }
        return max(0, (total / CGFloat(rows.count - 1)).rounded())
    }

    /// The room already being kept clear inside a screen's edges. A plain group
    /// starts life exactly as big as its contents, so it is keeping none.
    ///
    /// Only the two edges the contents START at can be read off them: the left
    /// margin of a column and the top of it are real, while the space below the
    /// last row is just the rest of the screen and reading it as room would
    /// leave a stack claiming three hundred points of bottom padding. So the
    /// far sides mirror the near ones, which is the even card somebody who
    /// spaced a screen by eye was drawing anyway, and either can be typed over.
    private static func inferredPadding(_ boxes: [CGRect], _ container: CGRect?) -> GroupPadding {
        guard let container, !boxes.isEmpty else { return .none }
        let left = max(0, ((boxes.map(\.minX).min() ?? 0) - container.minX).rounded())
        let top = max(0, ((boxes.map(\.minY).min() ?? 0) - container.minY).rounded())
        return GroupPadding(top: top, right: left, bottom: top, left: left)
    }
}
