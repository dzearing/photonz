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
                rowGap: CGFloat = GroupLayout.defaultGap,
                padding: GroupPadding = .none,
                width: CGFloat? = nil,
                height: CGFloat? = nil) {
        self.kind = kind
        self.direction = direction
        self.columns = columns
        self.gap = gap
        self.rowGap = rowGap
        self.padding = padding
        self.width = width
        self.height = height
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
        case kind, direction, columns, gap, rowGap, padding, width, height
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
        rowGap = try c.decodeIfPresent(CGFloat.self, forKey: .rowGap) ?? GroupLayout.defaultGap
        // Either shape of room: the single number older documents hold, or the
        // four sides a card with uneven room needs.
        padding = try c.decodeIfPresent(GroupPadding.self, forKey: .padding) ?? .none
        // A group saved before a stack could be given a size of its own opens
        // as one that is the size of its contents, which is what it was.
        width = try c.decodeIfPresent(CGFloat.self, forKey: .width)
        height = try c.decodeIfPresent(CGFloat.self, forKey: .height)
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
