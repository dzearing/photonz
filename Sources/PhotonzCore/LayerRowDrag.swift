import CoreGraphics
import Foundation

/// A row being carried up or down the layers list by the pointer, the way a
/// person expects a list to feel: the row they grabbed lifts and rides the
/// pointer, and the rows around it move out of its way, so the gap they leave
/// IS where it will land. There is no line to hunt for.
///
/// Everything here is measured in the list's own points, top down, with the
/// first row's top edge at zero, and every row the same `pitch` tall (a row's
/// height plus the spacing under it), which is how the list lays itself out.
///
/// Where it lands is read from which HALF of which row the pointer is over, as
/// the list is drawn right now, gap and all (the user, 2026-09-30):
///
/// - the top half of a row puts it above that row, the bottom half below it;
/// - the bottom half of an OPEN group's own row puts it inside, in the group's
///   first slot, since the slot under that row already belongs to the group;
/// - so at the foot of an open group, the bottom half of its LAST child keeps
///   it inside the group, and the top half of the row under the group puts it
///   below the group at the group's own level. Both open the very same gap;
///   what tells them apart is how far in the gap is drawn.
///
/// Reading the list as drawn is what keeps it calm: the moment the gap moves
/// under the pointer, the pointer is over the gap, and a pointer over the gap
/// changes nothing. So a row swaps once as the pointer crosses the middle of
/// its neighbour, and never flickers back and forth.
///
/// The rows that travel with the grabbed one (the rest of a selection, and
/// everything inside a group being carried) are tucked away for the length of
/// the drag, and the list closes up over them.
public struct LayerRowDrag: Equatable, Sendable {
    /// The row under the pointer when the drag began.
    public let grabbedID: UUID
    /// Everything the drop will move: the grabbed row, and the rest of the
    /// selection when the grabbed row was part of it.
    public let carried: Set<UUID>
    /// One row's height plus the spacing under it.
    public let pitch: CGFloat
    /// The rows the list is showing, top down, exactly as laid out.
    public private(set) var rows: [LayerPanelRow]
    /// The rows that ride along with the grabbed one and are tucked away while
    /// it is in the air.
    public private(set) var hidden: Set<UUID> = []
    /// Every row left standing in the list, top down: what the gap opens
    /// between.
    public private(set) var rest: [LayerPanelRow] = []
    /// Where the gap sits when the row is back where it came from.
    public private(set) var homeGap: Int = 0
    /// Where the gap is now, counted in rows of `rest`: 0 is above the first.
    public private(set) var gap: Int = 0
    /// How far in the gap is drawn, which is the list the row would join.
    public private(set) var gapDepth: Int = 0
    /// Where letting go would put what is carried, nil while the gap is still
    /// the one the row left, where letting go changes nothing.
    public private(set) var landing: LayerDrop?
    /// The pointer, in the list's points.
    public private(set) var pointerY: CGFloat
    /// How far below the grabbed row's top edge the pointer took hold of it, so
    /// the row keeps its place under the pointer rather than jumping to it.
    public let grabOffset: CGFloat

    /// Picks `grabbing` up with the pointer at `pointerY`. Nil when there is
    /// nothing to carry it past, or when the row is not in the list.
    public init?(grabbing: UUID, carrying: Set<UUID>, rows: [LayerPanelRow],
                 pitch: CGFloat, pointerY: CGFloat) {
        guard pitch > 0, let index = rows.firstIndex(where: { $0.id == grabbing }) else { return nil }
        self.grabbedID = grabbing
        self.carried = carrying.union([grabbing])
        self.pitch = pitch
        self.rows = rows
        self.pointerY = pointerY
        self.grabOffset = pointerY - CGFloat(index) * pitch
        lay(rows)
        guard !rest.isEmpty else { return nil }
        gap = homeGap
        gapDepth = rows[index].depth
    }

    /// Everything that follows from the rows: which ride along, which stand,
    /// and where the grabbed one came from.
    private mutating func lay(_ rows: [LayerPanelRow]) {
        self.rows = rows
        var riding: Set<UUID> = []
        var standing: [LayerPanelRow] = []
        var home = 0
        // A carried row takes everything under it that sits deeper than it,
        // which is exactly its contents: the list draws a group's contents
        // directly under its row, one level in.
        var carriedDepth: Int?
        for row in rows {
            if let depth = carriedDepth, row.depth > depth {
                riding.insert(row.id)
                continue
            }
            carriedDepth = nil
            if carried.contains(row.id) {
                carriedDepth = row.depth
                if row.id == grabbedID { home = standing.count } else { riding.insert(row.id) }
                continue
            }
            standing.append(row)
        }
        hidden = riding
        rest = standing
        homeGap = home
    }

    // MARK: - Where things are drawn

    /// Where the lifted row's top edge is drawn: under the pointer, and never
    /// past the first or last place a row could stand.
    public var liftedTop: CGFloat {
        min(max(pointerY - grabOffset, 0), CGFloat(rest.count) * pitch)
    }

    /// Where the gap's top edge is drawn.
    public var gapTop: CGFloat { CGFloat(gap) * pitch }

    /// Whether this row is drawn somewhere other than its own slot: the grabbed
    /// row (drawn lifted) and every row riding along with it (tucked away).
    public func isTravelling(_ id: UUID) -> Bool { id == grabbedID || hidden.contains(id) }

    /// How far a standing row is drawn from where the list laid it out: a row
    /// between the grabbed one's old slot and the gap moves one row towards
    /// the old slot. Zero for a row that is travelling.
    public func offset(of id: UUID) -> CGFloat {
        guard let natural = rows.firstIndex(where: { $0.id == id }),
              let standing = rest.firstIndex(where: { $0.id == id }) else { return 0 }
        let drawn = standing < gap ? standing : standing + 1
        return CGFloat(drawn - natural) * pitch
    }

    /// How far whatever sits under the last row (the Canvas row) is drawn from
    /// its own slot: up by one row for every row tucked away.
    public var trailingOffset: CGFloat {
        CGFloat(rest.count + 1 - rows.count) * pitch
    }

    /// The standing row the pointer is over, nil over the gap or past the ends.
    public var rowUnderPointer: LayerPanelRow? {
        guard pointerY >= 0 else { return nil }
        let drawn = Int((pointerY / pitch).rounded(.down))
        guard drawn != gap else { return nil }
        let standing = drawn < gap ? drawn : drawn - 1
        return rest.indices.contains(standing) ? rest[standing] : nil
    }

    /// The shut group a pointer resting here is aiming at, which the list
    /// springs open after a beat so the drop can go inside it (the mock's
    /// "hover a beat longer and it springs open").
    ///
    /// That is the group the pointer is over, or the one directly above the
    /// gap it is resting in: crossing the middle of a row moves the gap under
    /// the pointer, so a pointer that came down onto a group ends up in the gap
    /// just under it, and that is still aiming at the group.
    public var springTarget: UUID? {
        if let row = rowUnderPointer {
            return row.isGroup && !row.isExpanded ? row.id : nil
        }
        guard case .below(let id)? = landing,
              let row = rest.first(where: { $0.id == id }),
              row.isGroup, !row.isExpanded,
              pointerY >= gapTop, pointerY < gapTop + pitch else { return nil }
        return row.id
    }

    // MARK: - Moving

    /// The pointer moved. `canLand` is the document's own answer to whether
    /// what is carried may land at a place; a place it refuses leaves the gap
    /// where it was, so the gap never promises a drop that will not happen.
    public mutating func move(pointerY: CGFloat, canLand: (LayerDrop) -> Bool) {
        self.pointerY = pointerY
        guard let (drop, newGap, depth) = reading(pointerY), canLand(drop) else { return }
        landing = drop
        gap = newGap
        gapDepth = depth
    }

    /// What the pointer at `y` is asking for, as drawn now: nil while it is
    /// over the gap, which changes nothing.
    private func reading(_ y: CGFloat) -> (LayerDrop, Int, Int)? {
        guard let first = rest.first, let last = rest.last else { return nil }
        // Above the first row: the very top of the list.
        guard y >= 0 else { return (.above(first.id), 0, first.depth) }
        let drawn = Int((y / pitch).rounded(.down))
        guard drawn != gap else { return nil }
        let standing = drawn < gap ? drawn : drawn - 1
        // Past the last row: the very bottom, out at the canvas's own level,
        // under whatever the last row lives in.
        guard standing < rest.count else {
            let root = rest.last { $0.depth == 0 } ?? last
            return (.below(root.id), rest.count, root.depth)
        }
        let row = rest[standing]
        let fraction = y / pitch - CGFloat(drawn)
        if fraction < 0.5 { return (.above(row.id), standing, row.depth) }
        if row.isGroup && row.isExpanded { return (.inside(row.id), standing + 1, row.depth + 1) }
        return (.below(row.id), standing + 1, row.depth)
    }

    /// Called off: the gap goes back to the slot the row came from, and
    /// letting go now changes nothing.
    public mutating func returnHome() {
        landing = nil
        gap = homeGap
        gapDepth = rows.first { $0.id == grabbedID }?.depth ?? 0
    }

    /// The list under the drag changed shape (a shut group sprang open under
    /// the pointer). Keeps the landing it had and reads the pointer again
    /// against the new rows.
    public mutating func reflow(rows: [LayerPanelRow], canLand: (LayerDrop) -> Bool) {
        guard rows.contains(where: { $0.id == grabbedID }) else { return }
        var previous = landing
        lay(rows)
        // Below a group that has just opened is its first slot now: the row
        // under it is its own first child, so the gap there is inside it.
        if case .below(let id)? = previous,
           rest.contains(where: { $0.id == id && $0.isGroup && $0.isExpanded }) {
            previous = .inside(id)
            landing = previous
        }
        if let previous, let placed = place(of: previous) {
            gap = placed.gap
            gapDepth = placed.depth
        } else {
            landing = nil
            gap = homeGap
            gapDepth = rows.first { $0.id == grabbedID }?.depth ?? 0
        }
        move(pointerY: pointerY, canLand: canLand)
    }

    /// Where the gap stands for a landing, nil when its row is not standing.
    private func place(of drop: LayerDrop) -> (gap: Int, depth: Int)? {
        guard let index = rest.firstIndex(where: { $0.id == drop.targetID }) else { return nil }
        let row = rest[index]
        return switch drop {
        case .above: (index, row.depth)
        case .below: (index + 1, row.depth)
        case .inside: (index + 1, row.depth + 1)
        }
    }
}
