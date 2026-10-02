import CoreGraphics
import Foundation

/// A row lifted out of a list and carried up or down it by the pointer, as
/// geometry alone: where the rows left standing are drawn, where the gap
/// opens between them, where the lifted row rides, and which half of which
/// row the pointer is over. The layers list (`LayerRowDrag`) and the
/// timeline's track headers (`TrackRowDrag`) are both this one drag; each
/// reads its own landing from what is under the pointer.
///
/// Rows may be of any height, each measured in the list's own points, top
/// down, with `spacing` between two rows. The rows that ride along with the
/// lifted one (the rest of a selection, a group's contents) are tucked away
/// for the length of the drag and the list closes up over them. The gap is
/// the lifted row's own height.
///
/// Everything is read as the list is drawn right now, gap and all, which is
/// what keeps the drag calm: the moment the gap moves under the pointer, the
/// pointer is over the gap, and a pointer over the gap changes nothing. So a
/// row swaps once as the pointer crosses the middle of its neighbour, and
/// never flickers back and forth.
public struct RowLift: Equatable, Sendable {

    /// One row as the list laid it out.
    public struct Row: Equatable, Sendable {
        public var id: UUID
        public var top: CGFloat
        public var height: CGFloat

        public init(id: UUID, top: CGFloat, height: CGFloat) {
            self.id = id
            self.top = top
            self.height = height
        }
    }

    /// What the pointer is over, as the list is drawn now.
    public enum Spot: Equatable, Sendable {
        /// The gap, which changes nothing.
        case gap
        /// Above every row.
        case aboveAll
        /// Below every row.
        case pastAll
        /// A standing row, by its place in `rest`, and which half of it.
        case row(Int, upperHalf: Bool)
    }

    /// The row under the pointer when the drag began.
    public let grabbedID: UUID
    /// The space between two rows.
    public let spacing: CGFloat
    /// How far below the lifted row's top edge the pointer took hold of it,
    /// so it keeps its place under the pointer rather than jumping to it.
    public let grabOffset: CGFloat
    /// Every row, top down, as laid out.
    public private(set) var rows: [Row] = []
    /// The lifted row.
    public private(set) var grabbed: Row
    /// Every row left standing: what the gap opens between.
    public private(set) var rest: [Row] = []
    /// Where the gap sits when the row is back where it came from.
    public private(set) var homeGap = 0
    /// Where the gap is now, counted in rows of `rest`: 0 is above the first.
    public var gap = 0
    /// The pointer, in the list's points.
    public var pointerY: CGFloat
    /// Each standing row's top edge with the list closed up over everything
    /// travelling and no gap open.
    private var closedTops: [CGFloat] = []

    /// Lifts `grabbing` with the pointer at `pointerY`, tucking `riding` away
    /// for the length of the drag. Nil when it is not in the list, or nothing
    /// is left standing to carry it past.
    public init?(grabbing: UUID, riding: Set<UUID> = [], rows: [Row], spacing: CGFloat,
                 pointerY: CGFloat) {
        guard let grabbed = rows.first(where: { $0.id == grabbing }) else { return nil }
        self.grabbedID = grabbing
        self.spacing = spacing
        self.grabbed = grabbed
        self.pointerY = pointerY
        self.grabOffset = pointerY - grabbed.top
        relay(rows: rows, riding: riding)
        guard !rest.isEmpty else { return nil }
        gap = homeGap
    }

    /// Lays the rows out again (a shut group sprang open under the pointer).
    /// The gap goes home; the owner puts it back where its landing says.
    public mutating func relay(rows: [Row], riding: Set<UUID>) {
        guard let grabbed = rows.first(where: { $0.id == grabbedID }) else { return }
        self.rows = rows
        self.grabbed = grabbed
        var standing: [Row] = []
        var tops: [CGFloat] = []
        var removed: CGFloat = 0
        var home = 0
        for row in rows {
            if row.id == grabbedID || riding.contains(row.id) {
                if row.id == grabbedID { home = standing.count }
                removed += row.height + spacing
                continue
            }
            standing.append(row)
            tops.append(row.top - removed)
        }
        rest = standing
        closedTops = tops
        homeGap = home
        gap = min(gap, standing.count)
    }

    // MARK: - Where things are drawn

    /// How far every row the gap has passed moves: the lifted row and the
    /// space under it.
    public var shift: CGFloat { grabbed.height + spacing }

    /// Where a standing row's top edge is drawn now.
    private func drawnTop(_ standing: Int) -> CGFloat {
        closedTops[standing] + (standing >= gap ? shift : 0)
    }

    /// The top edge of slot `index` among the standing rows, counting the
    /// slot past the last.
    public func slotTop(_ index: Int) -> CGFloat {
        if closedTops.indices.contains(index) { return closedTops[index] }
        guard let last = rest.indices.last else { return rows.first?.top ?? 0 }
        return closedTops[last] + rest[last].height + spacing
    }

    /// Where the gap's top edge is drawn.
    public var gapTop: CGFloat { slotTop(gap) }

    /// How tall the gap is: the lifted row's own height.
    public var gapHeight: CGFloat { grabbed.height }

    /// Where the lifted row's top edge is drawn: under the pointer, and never
    /// past the first or last place a row could stand.
    public var liftedTop: CGFloat {
        min(max(pointerY - grabOffset, slotTop(0)), slotTop(rest.count))
    }

    /// How far a standing row is drawn from where the list laid it out. Zero
    /// for a row that is travelling.
    public func offset(of id: UUID) -> CGFloat {
        guard let standing = rest.firstIndex(where: { $0.id == id }) else { return 0 }
        return drawnTop(standing) - rest[standing].top
    }

    /// How far whatever sits under the last row is drawn from its own place:
    /// up by every row tucked away.
    public var trailingOffset: CGFloat {
        guard let last = rows.last else { return 0 }
        return slotTop(rest.count) + shift - (last.top + last.height + spacing)
    }

    // MARK: - What the pointer is over

    /// What the pointer at `y` is over, as drawn now.
    public func spot(_ y: CGFloat) -> Spot {
        let gapTop = self.gapTop
        if y >= gapTop, y < gapTop + shift { return .gap }
        if y < slotTop(0) { return .aboveAll }
        for index in rest.indices {
            let top = drawnTop(index)
            let pitch = rest[index].height + spacing
            if y >= top, y < top + pitch { return .row(index, upperHalf: y < top + pitch / 2) }
        }
        return .pastAll
    }
}
