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
    public var kind: GroupLayoutKind
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
    /// The space kept clear inside the edges. A group that arranges itself has
    /// edges of its own — whether it was given a size or takes the one its
    /// contents make — so the contents start this far in and the box carries
    /// this much on every side.
    public var padding: CGFloat
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

    public init(kind: GroupLayoutKind,
                direction: StackDirection = .column,
                columns: Int = GroupLayout.defaultColumns,
                gap: CGFloat = GroupLayout.defaultGap,
                rowGap: CGFloat = GroupLayout.defaultGap,
                padding: CGFloat = 0,
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
    public var usedPadding: CGFloat { max(0, padding) }

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

    private enum CodingKeys: String, CodingKey {
        case kind, direction, columns, gap, rowGap, padding, width, height
    }

    /// Read forgivingly: a layout saved by an older build that knew fewer
    /// numbers opens with this build's defaults rather than refusing to open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(GroupLayoutKind.self, forKey: .kind) ?? .stack
        direction = try c.decodeIfPresent(StackDirection.self, forKey: .direction) ?? .column
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? GroupLayout.defaultColumns
        gap = try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? GroupLayout.defaultGap
        rowGap = try c.decodeIfPresent(CGFloat.self, forKey: .rowGap) ?? GroupLayout.defaultGap
        padding = try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 0
        // A group saved before a stack could be given a size of its own opens
        // as one that is the size of its contents, which is what it was.
        width = try c.decodeIfPresent(CGFloat.self, forKey: .width)
        height = try c.decodeIfPresent(CGFloat.self, forKey: .height)
    }
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

    /// The space already being kept clear inside a screen's edges. A plain
    /// group has no edges of its own, so it has none.
    private static func inferredPadding(_ boxes: [CGRect], _ container: CGRect?) -> CGFloat {
        guard let container, !boxes.isEmpty else { return 0 }
        let left = (boxes.map(\.minX).min() ?? 0) - container.minX
        let top = (boxes.map(\.minY).min() ?? 0) - container.minY
        return max(0, min(left, top).rounded())
    }
}
