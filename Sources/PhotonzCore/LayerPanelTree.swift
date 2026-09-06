import CoreGraphics
import Foundation

/// One row of the layers panel. The panel reads top down (the topmost layer
/// first), and a group's contents sit indented directly under it when the
/// group is open.
public struct LayerPanelRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// How far in the row is drawn: 0 for a layer sitting loose on the canvas,
    /// 1 for a layer inside a group, and so on.
    public let depth: Int
    public let isGroup: Bool
    /// How many layers the group holds directly, which is the number a closed
    /// group row shows. Zero for anything that is not a group.
    public let childCount: Int
    /// Whether this group's contents are showing under it.
    public let isExpanded: Bool
    /// The group this row lives in, nil at the top level.
    public let parentID: UUID?

    public init(id: UUID, depth: Int, isGroup: Bool, childCount: Int,
                isExpanded: Bool, parentID: UUID?) {
        self.id = id
        self.depth = depth
        self.isGroup = isGroup
        self.childCount = childCount
        self.isExpanded = isExpanded
        self.parentID = parentID
    }
}

/// What a drop on a layers-panel row means, decided by where the pointer sits
/// in that row: the top strip inserts the dragged layers in front of it, the
/// bottom strip behind it, and the middle of a group row drops them inside.
public enum LayerDropZone: Hashable, Sendable {
    case above, inside, below

    /// The share of a row's height each edge strip takes when the row offers
    /// all three zones. A third each reads as three even bands.
    static let edgeShare: CGFloat = 1.0 / 3.0

    /// Reads the pointer's position in a row.
    ///
    /// - `offersInside`: the row is a group that can take contents.
    /// - `offersBelow`: there is a meaningful slot directly under the row. An
    ///   OPEN group has none: the slot under its row already belongs to its own
    ///   topmost child, so aiming there would land the layer somewhere the eye
    ///   never pointed. Its bottom strip means inside instead.
    public static func forPointer(y: CGFloat, rowHeight: CGFloat,
                                  offersInside: Bool, offersBelow: Bool) -> LayerDropZone {
        guard rowHeight > 0 else { return .above }
        let fraction = min(max(y / rowHeight, 0), 1)
        guard offersInside else { return fraction < 0.5 ? .above : .below }
        guard offersBelow else { return fraction < edgeShare ? .above : .inside }
        if fraction < edgeShare { return .above }
        if fraction > 1 - edgeShare { return .below }
        return .inside
    }
}

/// Where a drag in the layers panel wants to put what it is carrying.
/// `above` and `below` always mean *become that row's sibling*, in that row's
/// own list — which is the whole of taking a layer out of a group: drop it
/// against a row that sits loose on the canvas.
public enum LayerDrop: Hashable, Sendable {
    /// Into the group, on top of what it already holds.
    case inside(UUID)
    /// Directly in front of (visually above) the row, as its sibling.
    case above(UUID)
    /// Directly behind (visually below) the row, as its sibling.
    case below(UUID)

    public var targetID: UUID {
        switch self {
        case .inside(let id), .above(let id), .below(let id): id
        }
    }
}

extension PhotonzDocument {

    // MARK: - What a drag over a row is promising

    /// What a drag that picked up `dragging` is carrying: the whole selection
    /// when the row you grabbed is part of it (the way Delete and Duplicate
    /// already work), else that row on its own.
    public static func rowsCarried(byDragging dragging: UUID, selection: Set<UUID>) -> Set<UUID> {
        selection.contains(dragging) ? selection : [dragging]
    }

    /// Where a drag would land if it were released now: the whole reading of
    /// the pointer over one row, and the thing the drop line draws. Nil when
    /// nothing can land here, which is when the pointer shows no entry.
    ///
    /// `allowsInside` is the groups feature flag: with it off a group row is
    /// just a row, and the list reorders the way it always did.
    public func dropProposal(carrying ids: Set<UUID>, over row: LayerPanelRow,
                             pointerY: CGFloat, rowHeight: CGFloat,
                             allowsInside: Bool = true) -> LayerDrop? {
        guard !ids.isEmpty, !ids.contains(row.id) else { return nil }
        let offersInside = allowsInside && row.isGroup && canDrop(ids: ids, .inside(row.id))
        let drop: LayerDrop = switch LayerDropZone.forPointer(
            y: pointerY, rowHeight: rowHeight,
            offersInside: offersInside,
            // The slot under an OPEN group row already belongs to its own
            // topmost child, so that row has no "below".
            offersBelow: !(row.isGroup && row.isExpanded)) {
        case .above: .above(row.id)
        case .inside: .inside(row.id)
        case .below: .below(row.id)
        }
        return canDrop(ids: ids, drop) ? drop : nil
    }

    // MARK: - Rows

    /// The rows the layers panel shows, top down, with the contents of every
    /// group in `expanded` indented under it. A document with no groups gives
    /// back exactly the flat top-down list the panel has always drawn.
    public func panelRows(expanded: Set<UUID>) -> [LayerPanelRow] {
        var rows: [LayerPanelRow] = []
        func walk(_ list: [Layer], depth: Int, parent: UUID?) {
            for layer in list.reversed() {
                // A copy of a component has no twist open: what is inside it
                // belongs to its original, so a row you could open would show
                // pieces nobody can keep an edit to.
                let openable = layer.isOpenableGroup
                let open = openable && expanded.contains(layer.id)
                rows.append(LayerPanelRow(id: layer.id, depth: depth,
                                          isGroup: openable,
                                          childCount: openable ? layer.children.count : 0,
                                          isExpanded: open, parentID: parent))
                if open { walk(layer.children, depth: depth + 1, parent: layer.id) }
            }
        }
        walk(layers, depth: 0, parent: nil)
        return rows
    }

    /// Every group in the document the layers list can twist open, at any
    /// depth. A copy of a component is not one: what is inside it belongs to
    /// its original, so its row has no twist open.
    ///
    /// This is what an open/shut record is measured against, so a group that
    /// has been deleted since last time leaves nothing behind.
    public var openableGroupIDs: Set<UUID> {
        var out: Set<UUID> = []
        func walk(_ list: [Layer]) {
            for layer in list where layer.isOpenableGroup {
                out.insert(layer.id)
                walk(layer.children)
            }
        }
        walk(layers)
        return out
    }

    /// Every group above a layer, innermost first — the set that has to be
    /// open for the layer's row to be on screen. Empty for a layer sitting
    /// loose on the canvas.
    public func ancestorIDs(of id: UUID) -> [UUID] {
        guard let path = path(of: id), path.count > 1 else { return [] }
        var out: [UUID] = []
        for depth in stride(from: path.count - 1, through: 1, by: -1) {
            if let ancestor = layer(atPath: Array(path.prefix(depth))) { out.append(ancestor.id) }
        }
        return out
    }

    // MARK: - Dropping

    /// Whether a drag carrying `ids` could land here at all — what decides
    /// between showing a drop line and showing the no-entry cursor.
    public func canDrop(ids: Set<UUID>, _ drop: LayerDrop) -> Bool {
        !droppableMembers(ids: ids, drop).isEmpty
    }

    /// The layers a drop would actually move, in panel order, top down.
    /// Empty when the drop is impossible.
    private func droppableMembers(ids: Set<UUID>, _ drop: LayerDrop) -> [UUID] {
        let target = drop.targetID
        guard !ids.contains(target), let targetPath = path(of: target) else { return [] }
        if case .inside = drop {
            // `isOpenableGroup`: a copy of a component is not a container you
            // can put anything in, because its contents are its original's.
            guard let group = layer(id: target), group.isOpenableGroup, !group.isLocked else { return [] }
        }
        // A group can never be dropped into its own contents: that is a loop
        // with no way back out. Locked layers stay put, the way Bring Forward
        // and Group already leave them.
        let movable = ids.filter { id in
            guard let layer = layer(id: id), !layer.isLocked, let path = path(of: id) else { return false }
            return !(targetPath.count > path.count && Array(targetPath.prefix(path.count)) == path)
        }
        guard !movable.isEmpty else { return [] }
        // Panel order, so a drag carrying several rows keeps their stacking.
        return panelRows(expanded: Set(allLayers.map(\.id))).map(\.id).filter { movable.contains($0) }
    }

    /// Moves everything in `ids` to where the drop points, in ONE mutation so
    /// a drag is one undo step. Each layer's position is rewritten into its new
    /// parent's space, so nothing jumps on screen: a layer dragged into a group
    /// stays exactly where it was. Returns false when the drop is impossible or
    /// would change nothing, which is what keeps a wasted drag off the undo
    /// stack.
    @discardableResult
    public mutating func dropLayers(ids: Set<UUID>, _ drop: LayerDrop) -> Bool {
        let ordered = droppableMembers(ids: ids, drop)
        guard !ordered.isEmpty else { return false }
        guard let destination = dropSpaceOrigin(drop) else { return false }
        let before = layers
        let origins = ordered.reduce(into: [UUID: CGPoint]()) { out, id in
            out[id] = parentOrigin(of: id)
        }
        // Bottom up, so the block goes back in the order the panel showed it.
        var moved: [Layer] = []
        for id in ordered.reversed() {
            guard var layer = removeLayer(id: id), let from = origins[id] ?? nil else { continue }
            layer.frame = layer.frame.offsetBy(dx: from.x - destination.x, dy: from.y - destination.y)
            moved.append(layer)
        }
        guard !moved.isEmpty, let targetPath = path(of: drop.targetID) else {
            layers = before
            return false
        }
        switch drop {
        case .inside:
            withChildren(atPath: targetPath) { $0.append(contentsOf: moved) }
        case .above, .below:
            let slot = targetPath[targetPath.count - 1]
            let at: Int
            if case .above = drop { at = slot + 1 } else { at = slot }
            if targetPath.count == 1 {
                layers.insert(contentsOf: moved, at: min(max(0, at), layers.count))
            } else {
                withChildren(atPath: Array(targetPath.dropLast())) { children in
                    children.insert(contentsOf: moved, at: min(max(0, at), children.count))
                }
            }
        }
        // A drag that put everything back where it started is not an edit.
        guard layers != before else {
            layers = before
            return false
        }
        return true
    }

    /// Where the coordinate space a drop lands in starts, in canvas
    /// coordinates — what each moved layer's position is rewritten against.
    private func dropSpaceOrigin(_ drop: LayerDrop) -> CGPoint? {
        switch drop {
        case .inside(let id):
            guard let group = layer(id: id), let origin = parentOrigin(of: id) else { return nil }
            return CGPoint(x: origin.x + group.frame.origin.x, y: origin.y + group.frame.origin.y)
        case .above(let id), .below(let id):
            return parentOrigin(of: id)
        }
    }

    // MARK: - A picture arriving from outside the list

    /// Where a picture arriving from OUTSIDE the document — dragged in from
    /// the Finder, off the Library shelf — would land if it were let go over
    /// this row now. This is what the drop line under the pointer draws, and
    /// it is read the same three ways a row drag is: the top strip puts the
    /// newcomer in front of the row, the bottom strip behind it, and the
    /// middle of a group row puts it inside.
    ///
    /// It is separate from `dropProposal` because nothing is being carried:
    /// there is no layer that could be its own parent, and a LOCKED row still
    /// takes a newcomer beside it — the row is locked, the list it sits in is
    /// not. Only dropping INSIDE a locked group is refused, because that is
    /// the one case where the locked layer itself would change.
    ///
    /// `allowsInside` is the groups feature flag, exactly as it is there.
    public func incomingDropProposal(over row: LayerPanelRow, pointerY: CGFloat,
                                     rowHeight: CGFloat, allowsInside: Bool = true) -> LayerDrop? {
        guard let target = layer(id: row.id) else { return nil }
        let offersInside = allowsInside && target.isOpenableGroup && !target.isLocked
        return switch LayerDropZone.forPointer(
            y: pointerY, rowHeight: rowHeight,
            offersInside: offersInside,
            // The slot under an OPEN group row already belongs to its own
            // topmost child, the same as for a row being dragged.
            offersBelow: !(row.isGroup && row.isExpanded)) {
        case .above: .above(row.id)
        case .inside: .inside(row.id)
        case .below: .below(row.id)
        }
    }

    /// Where a picture let go on the right hand panel, but not on any one row,
    /// lands: inside the frame under the middle of the canvas when there is
    /// one — because that is the box the picture itself is about to be placed
    /// in — and on top of everything otherwise.
    ///
    /// Nil for a document with no layers at all, which has no stack to sit on
    /// top of.
    public func incomingDropOnTop() -> LayerDrop? {
        let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        if let frame = frameID(under: centre) { return .inside(frame) }
        guard let top = layers.last else { return nil }
        return .above(top.id)
    }

    /// Puts a BRAND NEW layer exactly where the drop line said it would go.
    ///
    /// `layer.frame` arrives in canvas coordinates and is rewritten into the
    /// space it lands in, so the picture sits on screen where it was shown
    /// however deep in the tree its row is. Returns false when the drop cannot
    /// take it, which leaves the document untouched and keeps a refused drag
    /// off the undo stack.
    @discardableResult
    public mutating func insertLayer(_ newcomer: Layer, _ drop: LayerDrop) -> Bool {
        guard let targetPath = path(of: drop.targetID),
              let destination = dropSpaceOrigin(drop) else { return false }
        if case .inside = drop {
            guard let group = layer(id: drop.targetID),
                  group.isOpenableGroup, !group.isLocked else { return false }
        }
        var placed = uniquelyNamed(newcomer)
        placed.frame = placed.frame.offsetBy(dx: -destination.x, dy: -destination.y)
        switch drop {
        case .inside:
            withChildren(atPath: targetPath) { $0.append(placed) }
        case .above, .below:
            let slot = targetPath[targetPath.count - 1]
            let at: Int
            if case .above = drop { at = slot + 1 } else { at = slot }
            if targetPath.count == 1 {
                layers.insert(placed, at: min(max(0, at), layers.count))
            } else {
                withChildren(atPath: Array(targetPath.dropLast())) { children in
                    children.insert(placed, at: min(max(0, at), children.count))
                }
            }
        }
        return true
    }

    /// The canvas-space box a newcomer landing at `drop` is placed in: the
    /// group it lands inside, the group whose list it joins, or the whole
    /// canvas for a drop against a layer sitting loose on it.
    func incomingPlacementBox(_ drop: LayerDrop) -> CGRect {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        switch drop {
        case .inside(let id):
            return canvasBounds(of: id) ?? canvas
        case .above(let id), .below(let id):
            guard let parent = parentID(of: id) else { return canvas }
            return canvasBounds(of: parent) ?? canvas
        }
    }
}

// MARK: - What a row draws

/// One row of the layers panel and the handful of facts about its layer that
/// the row actually draws. Nothing else: the row is a small value, so two
/// equal values mean the panel can leave that row exactly as it is.
///
/// This exists because the panel used to hold only the row's id and ask the
/// document for the layer again while drawing, once per row. That search walks
/// the whole tree, so a list of 120 layers did 120 walks of 120 layers every
/// time anything in the dock changed.
public struct LayerRowDisplay: Identifiable, Hashable, Sendable {
    /// Where the row sits in the tree: depth, group-ness, child count, whether
    /// it is open.
    public let row: LayerPanelRow
    public let name: String
    public let isVisible: Bool
    public let isLocked: Bool
    /// Part of the current selection, so the row draws its highlight.
    public let isSelected: Bool
    public let isMainComponent: Bool
    public let isComponentInstance: Bool
    /// Which version of its component this drawing is, on a main whose
    /// component holds more than one (`ComponentVersions`). Every version
    /// carries the component's name, so without this a button with a Disabled
    /// version is two rows both called Button.
    public let versionName: String?
    /// Whether the row's menu offers "Rasterize Layer".
    public let isRasterizable: Bool

    public var id: UUID { row.id }

    public init(row: LayerPanelRow, name: String, isVisible: Bool, isLocked: Bool,
                isSelected: Bool, isMainComponent: Bool, isComponentInstance: Bool,
                versionName: String? = nil, isRasterizable: Bool) {
        self.versionName = versionName
        self.row = row
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isSelected = isSelected
        self.isMainComponent = isMainComponent
        self.isComponentInstance = isComponentInstance
        self.isRasterizable = isRasterizable
    }
}

extension PhotonzDocument {

    /// The version name a row prints: only on a main whose component holds more
    /// than one drawing of itself.
    static func versionName(of layer: Layer, counts: [UUID: Int]) -> String? {
        guard let componentID = layer.componentID, (counts[componentID] ?? 0) > 1 else { return nil }
        return layer.componentVersionName
    }

    /// Every row the layers panel shows, in the order it shows them, each one
    /// carrying what it draws — from a single walk of the tree.
    ///
    /// `selected` is the whole selection, the single pick and the marquee's
    /// rows alike. Only the rows in it come back marked, which is the point:
    /// a click that moves the selection changes exactly two of these values,
    /// so the panel redraws exactly two rows.
    public func layerRows(expanded: Set<UUID>, selected: Set<UUID>) -> [LayerRowDisplay] {
        var rows: [LayerRowDisplay] = []
        // Which components hold more than one drawing of themselves. A version
        // name is only worth printing while there is another version to tell it
        // apart from: a component back down to one is a component again, and a
        // row still wearing "Default" reads as a state nobody can get out of.
        var versionCounts: [UUID: Int] = [:]
        for main in mainComponents {
            guard let componentID = main.componentID else { continue }
            versionCounts[componentID, default: 0] += 1
        }
        func walk(_ list: [Layer], depth: Int, parent: UUID?) {
            for layer in list.reversed() {
                // A copy of a component has no twist open: what is inside it
                // belongs to its original, so a row you could open would show
                // pieces nobody can keep an edit to.
                let openable = layer.isOpenableGroup
                let open = openable && expanded.contains(layer.id)
                rows.append(LayerRowDisplay(
                    row: LayerPanelRow(id: layer.id, depth: depth, isGroup: openable,
                                       childCount: openable ? layer.children.count : 0,
                                       isExpanded: open, parentID: parent),
                    name: layer.name,
                    isVisible: layer.isVisible,
                    isLocked: layer.isLocked,
                    isSelected: selected.contains(layer.id),
                    isMainComponent: layer.isMainComponent,
                    isComponentInstance: layer.isComponentInstance,
                    versionName: Self.versionName(of: layer, counts: versionCounts),
                    isRasterizable: layer.isRasterizable))
                if open { walk(layer.children, depth: depth + 1, parent: layer.id) }
            }
        }
        walk(layers, depth: 0, parent: nil)
        return rows
    }
}
