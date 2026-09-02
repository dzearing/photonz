import Foundation

/// How a click on a list row should change the selection, the way the Finder
/// and Photoshop's Layers panel read the modifier keys.
public enum RowClick: Equatable, Sendable {
    /// No modifier: this row and nothing else.
    case plain
    /// Shift: every row between the anchor and this one, inclusive.
    case extend
    /// Command: add this row, or remove it if it is already selected.
    case toggle
}

/// Selection state for a list of rows identified by `UUID`, driven by clicks.
///
/// The rules are NSTableView's, so a Mac user's hands already know them:
///
/// - A plain click selects only that row and makes it the **anchor**.
/// - A command-click toggles the row and moves the anchor to it.
/// - A shift-click selects the run from the anchor to the clicked row. Rows
///   the previous shift-click swept in are let go first (the range pivots
///   around the anchor), while rows added by command-click stay. The anchor
///   does not move, so a second shift-click re-ranges from the same row.
/// - With no usable anchor (nothing clicked yet, or the anchored row left the
///   list) a shift-click is just a plain click.
///
/// `order` is the list top to bottom; ids not in it still select, on their
/// own, so a stale row can never wedge the list.
public struct ListSelection: Equatable, Sendable, Codable {
    /// The selected rows.
    public var selected: Set<UUID>
    /// The row a shift-click ranges from: the last plain or command click.
    public var anchor: UUID?
    /// The rows the most recent shift-click swept in, so the next one can
    /// pivot around the anchor instead of only growing.
    public var extendedRange: Set<UUID>

    public init(selected: Set<UUID> = [], anchor: UUID? = nil, extendedRange: Set<UUID> = []) {
        self.selected = selected
        self.anchor = anchor
        self.extendedRange = extendedRange
    }

    /// Applies one click on `id`, with `order` as the list's row order.
    public mutating func click(_ id: UUID, _ click: RowClick, in order: [UUID]) {
        switch click {
        case .plain:
            selectOnly(id)
        case .toggle:
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
            extendedRange = []
        case .extend:
            guard let anchor,
                  let from = order.firstIndex(of: anchor),
                  let to = order.firstIndex(of: id) else {
                selectOnly(id)
                return
            }
            let range = Set(order[min(from, to)...max(from, to)])
            selected = selected.subtracting(extendedRange).union(range)
            extendedRange = range
        }
    }

    /// The same click, as a new value.
    public func clicking(_ id: UUID, _ click: RowClick, in order: [UUID]) -> ListSelection {
        var copy = self
        copy.click(id, click, in: order)
        return copy
    }

    private mutating func selectOnly(_ id: UUID) {
        selected = [id]
        anchor = id
        extendedRange = []
    }
}
