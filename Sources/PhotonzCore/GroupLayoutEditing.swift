import CoreGraphics
import Foundation

/// Telling a group to arrange its own contents, and keeping every stack and
/// grid in the document arranged after any edit at all.
///
/// The keeping-arranged half runs from `History.perform`, so no command has to
/// know this feature exists: paste a layer into a stack, delete one, drag one
/// past another, undo, redo — the flow runs inside the same undo step and the
/// contents come out in order.
extension PhotonzDocument {

    /// Whether "Stack" or "Grid" would do anything: exactly one unlocked group
    /// is picked. A photo has no contents to arrange, and a locked group is
    /// locked.
    public func canSetGroupLayout(ids: Set<UUID>) -> Bool {
        guard ids.count == 1, let id = ids.first, let layer = layer(id: id) else { return false }
        return layer.isGroup && !layer.isLocked
    }

    /// Makes a group arrange itself, or stops it. Nothing moves at the moment
    /// you press it: the layout is READ off where the contents already are, so
    /// a row you spaced by eye at 16 points becomes a row with a gap of 16.
    ///
    /// A group's box is whatever its contents add up to, so the flow lays out
    /// from the group's own corner. That is only a stable place to start from
    /// once the contents actually begin there, so the contents are pulled back
    /// to the corner and the group's own anchor moves the same amount — the
    /// same sum grouping already does, and nothing on the canvas shifts.
    public mutating func setGroupLayout(id: UUID, kind: GroupLayoutKind?) {
        guard let layer = layer(id: id), let group = layer.group else { return }
        guard let kind else {
            updateLayer(id: id) { $0.setGroupLayout(nil) }
            return
        }
        let container = group.isFrame ? CGRect(origin: .zero, size: layer.frame.standardized.size)
                                      : nil
        var boxes = layer.children.filter(\.isVisible).map(\.localBounds)
        if boxes.isEmpty { boxes = layer.children.map(\.localBounds) }
        var inferred = GroupLayout.inferred(from: boxes, kind: kind, container: container)
        // Everything a group already carries about how it flows is kept, so
        // turning a stack into a grid and back does not forget the gap.
        if let existing = group.layout {
            inferred = GroupLayout(kind: kind, direction: existing.direction,
                                   columns: existing.columns, gap: existing.gap,
                                   rowGap: existing.rowGap, padding: existing.padding)
        }
        updateLayer(id: id) { layer in
            if !group.isFrame { layer.pullContentsToItsCorner() }
            layer.setGroupLayout(inferred)
        }
    }

    /// One number on a group's layout, typed in the inspector.
    public mutating func updateGroupLayout(id: UUID, _ change: (inout GroupLayout) -> Void) {
        guard let existing = layer(id: id)?.group?.layout else { return }
        var next = existing
        change(&next)
        guard next != existing else { return }
        updateLayer(id: id) { $0.setGroupLayout(next) }
    }

    /// Layer ▸ Stack Selection / Grid Selection. Several layers picked become
    /// one group that arranges them; one group picked simply starts arranging
    /// itself. Returns the group that ended up doing the arranging.
    @discardableResult
    public mutating func stackSelection(ids: Set<UUID>, kind: GroupLayoutKind) -> UUID? {
        if canSetGroupLayout(ids: ids), let id = ids.first {
            setGroupLayout(id: id, kind: kind)
            return id
        }
        guard canGroup(ids: ids), let made = groupLayers(ids: ids, name: freshGroupName())
        else { return nil }
        setGroupLayout(id: made.id, kind: kind)
        return made.id
    }

    /// Every stack and grid in the document, arranged. Runs after each edit;
    /// a document with none in it is untouched, and so is a stack whose
    /// contents are already where they belong.
    public mutating func reflowLayouts() {
        let flowed = layers.map(GroupFlow.flowing)
        guard flowed != layers else { return }
        layers = flowed
    }

    /// Whether anything in this document arranges itself, which is the only
    /// question the reflow pass needs to ask before doing nothing.
    public var holdsArrangedGroups: Bool {
        allLayers.contains { $0.group?.layout != nil }
    }
}

extension Layer {
    /// This group's layout, set or cleared, leaving everything else about the
    /// group alone.
    mutating func setGroupLayout(_ layout: GroupLayout?) {
        guard var group else { return }
        group.children = children
        group.layout = layout
        content = .group(group)
    }

    /// Moves this group's contents so they start at its own corner, and moves
    /// the corner by the same amount, so nothing on the canvas has moved when
    /// it is over. A group's stored size is unused, so only the origin counts.
    mutating func pullContentsToItsCorner() {
        guard isGroup, !isFrame, let first = children.first else { return }
        let union = children.dropFirst().reduce(first.localBounds) { $0.union($1.localBounds) }
        guard union.origin != .zero else { return }
        children = children.map { child in
            var moved = child
            moved.frame = child.frame.offsetBy(dx: -union.minX, dy: -union.minY)
            return moved
        }
        frame = frame.offsetBy(dx: union.minX, dy: union.minY)
    }
}
