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

    /// Why a copy is not asked how it arranges its contents: the answer is its
    /// original's, and a copy is rebuilt from the original after every edit, so
    /// an answer given here would be gone by the next redraw.
    public static let instanceArrangementReason = "A copy arranges its contents the way its original does. Use Edit Original in the Component section to change it for every copy."

    /// Whether "Stack" or "Grid" would do anything: exactly one unlocked group
    /// is picked, and it is not a copy. A photo has no contents to arrange, a
    /// locked group is locked, and a copy's contents belong to its original.
    public func canSetGroupLayout(ids: Set<UUID>) -> Bool {
        guard ids.count == 1, let id = ids.first, let layer = layer(id: id) else { return false }
        return layer.isGroup && !layer.isLocked && !layer.isComponentInstance
    }

    /// Whether this group's rules about its own contents, the arrangement and
    /// where the contents sit, are its to set. A copy's are not: every one of
    /// them is refilled from the original by `syncComponentInstances`, so the
    /// only honest thing the Layout section can do with a copy is show them and
    /// say who owns them.
    public func ownsContentRules(id: UUID) -> Bool {
        guard let layer = layer(id: id), layer.isGroup else { return false }
        return !layer.isComponentInstance
    }

    /// Makes a group arrange itself, or stops it. Nothing moves at the moment
    /// you press it: the layout is READ off where the contents already are, so
    /// a row you spaced by eye at 16 points becomes a row with a gap of 16, and
    /// a group asked only to close around its contents keeps exactly the room
    /// they already have.
    ///
    /// A group's box is whatever its contents add up to, so the flow lays out
    /// from the group's own corner. That is only a stable place to start from
    /// once the contents actually begin there, so the contents are pulled back
    /// to the corner and the group's own anchor moves the same amount — the
    /// same sum grouping already does, and nothing on the canvas shifts.
    public mutating func setGroupLayout(id: UUID, kind: GroupLayoutKind?) {
        guard let layer = layer(id: id), let group = layer.group,
              ownsContentRules(id: id) else { return }
        let container = group.isFrame ? CGRect(origin: .zero, size: layer.frame.standardized.size)
                                      : nil
        // Free: it arranges nothing, so there is nothing to read off but the
        // room its contents already have. Everything else it carries — the
        // gap, the columns, a size of its own — stays where it is, so going
        // Stack, Free, Stack does not forget the numbers on the way.
        guard let kind else {
            var free = group.layout ?? GroupLayout.free(
                padding: GroupFlow.room(around: layer.children,
                                        contentPlacement: group.contentPlacement,
                                        inside: container))
            free.kind = nil
            updateLayer(id: id) { layer in
                if !group.isFrame, group.layout == nil { layer.pullContentsToItsCorner() }
                layer.setGroupLayout(free)
            }
            return
        }
        // Read off the boxes a person can SEE, because that is what the gap
        // this infers will mean once the stack flows: measure a column of
        // labels by their frames and it comes back with a gap four points
        // tighter than the one somebody spaced by eye.
        var boxes = layer.children.filter(\.isVisible).map(\.contentBounds)
        if boxes.isEmpty { boxes = layer.children.map(\.contentBounds) }
        var inferred = GroupLayout.inferred(from: boxes, kind: kind, container: container)
        // Everything a group already carries about how it flows is kept, so
        // turning a stack into a grid and back does not forget the gap.
        // Kept by changing only the kind, never by listing the fields: a list
        // is a place to forget the next number somebody adds, and the limits
        // were exactly that number (found 2026-09-05).
        if var existing = group.layout {
            existing.kind = kind
            inferred = existing
        }
        updateLayer(id: id) { layer in
            // Only a group being arranged for the FIRST time needs pulling
            // back: one that already arranges itself starts its contents at
            // its own corner already, inside whatever padding it keeps, and
            // pulling that padding away would walk the group across the canvas
            // every time somebody switched it between a stack and a grid.
            if !group.isFrame, group.layout == nil { layer.pullContentsToItsCorner() }
            layer.setGroupLayout(inferred)
        }
    }

    /// One number on a group's layout, typed in the inspector.
    ///
    /// A group that has never been given a layout gets one here, keeping the
    /// room its contents already have, so typing a size or a padding into a
    /// plain group is the moment it starts closing around them — and the group
    /// does not move while that happens.
    public mutating func updateGroupLayout(id: UUID, _ change: (inout GroupLayout) -> Void) {
        guard let layer = layer(id: id), let group = layer.group,
              ownsContentRules(id: id) else { return }
        if group.layout == nil { setGroupLayout(id: id, kind: nil) }
        guard let existing = self.layer(id: id)?.group?.layout else { return }
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
    ///
    /// It runs until nothing moves, because one pass is not always enough: a
    /// stack works out where its rows go from the sizes they had going in, and
    /// a label stretched across the stack RE-WRAPS to the width it was given,
    /// so it is taller than it was when the row under it was placed. The second
    /// pass closes that gap. Passes are capped, so a pair of rules that
    /// disagreed could never spin here.
    public mutating func reflowLayouts() {
        for _ in 0..<Self.reflowPasses {
            let flowed = layers.map(GroupFlow.flowing)
            guard flowed != layers else { return }
            layers = flowed
        }
    }

    /// How many times the flow may run before it gives up and leaves the
    /// contents where the last pass put them. Two settles everything the app
    /// can build today; the third is headroom.
    static let reflowPasses = 3

    /// Whether anything in this document arranges itself, which is the only
    /// question the reflow pass needs to ask before doing nothing.
    public var holdsArrangedGroups: Bool {
        allLayers.contains { $0.group?.layout != nil }
    }
}

extension Layer {
    /// The layout this group is working to, including the one a group nobody
    /// has touched is already working to: it arranges nothing, it is as big as
    /// what is inside it, and the room it keeps at its edges is the room its
    /// contents already have. What the Layout section shows, so arriving at a
    /// plain group and arriving at one somebody has set up read the same.
    public var workingLayout: GroupLayout {
        if let layout = group?.layout { return layout }
        guard let group else { return .free() }
        let box = group.isFrame ? CGRect(origin: .zero, size: frame.standardized.size) : nil
        return .free(padding: GroupFlow.room(around: group.children,
                                             contentPlacement: group.contentPlacement,
                                             inside: box))
    }

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
