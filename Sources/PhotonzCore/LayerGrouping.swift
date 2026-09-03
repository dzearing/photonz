import CoreGraphics
import Foundation

/// Grouping as the interface sees it: what ⌘G and ⇧⌘G are allowed to do, where
/// a click on the canvas lands once layers can nest, and how a tree of layers
/// reads in canvas coordinates.
///
/// The one rule everything here follows: **a click picks the outermost thing
/// you are not already inside**. A group is one object until you deliberately
/// step into it, which is what makes a grouped card behave like a card rather
/// than like the pieces it is made of. Stepping in is a double click, and the
/// group you stepped into is the *context* every function below takes.
/// See `docs/design/ui-building.md`, "The two canvas gestures".
extension PhotonzDocument {

    // MARK: - What the menu rows are allowed to do

    /// Whether ⌘G would make a group out of `ids`.
    ///
    /// Grouping happens inside ONE list: the selected layer nearest the canvas
    /// decides which one, and ids that live elsewhere in the tree stay where
    /// they are rather than being yanked out of their group. So the row is live
    /// only when at least two unlocked layers of that one list are selected.
    /// The locked Background never joins, which is why Select All then ⌘G on a
    /// screenshot with one annotation on it does nothing.
    public func canGroup(ids: Set<UUID>) -> Bool {
        groupableMembers(ids: ids).count >= 2
    }

    /// The selected ids that a ⌘G would actually wrap up, in the order they
    /// sit in their shared list. Empty when nothing can be grouped.
    func groupableMembers(ids: Set<UUID>) -> [UUID] {
        let paths = ids.compactMap { path(of: $0) }
        // The anchor: nearest the canvas, topmost on a tie. `groupLayers` picks
        // the same one, so the row's enablement and the command agree.
        guard let anchor = paths.min(by: {
            $0.count != $1.count ? $0.count < $1.count : ($0.last ?? 0) > ($1.last ?? 0)
        }) else { return [] }
        let parent = Array(anchor.dropLast())
        let siblings = parent.isEmpty ? layers : (layer(atPath: parent)?.children ?? [])
        return siblings.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id)
    }

    /// Whether ⇧⌘G would take something apart: at least one unlocked group is
    /// selected. A mixed selection still offers it, and only the groups in it
    /// come apart.
    public func canUngroup(ids: Set<UUID>) -> Bool {
        !ungroupableMembers(ids: ids).isEmpty
    }

    private func ungroupableMembers(ids: Set<UUID>) -> [UUID] {
        ids.filter { id in
            guard let layer = layer(id: id) else { return false }
            return layer.isGroup && !layer.isLocked
        }
    }

    /// A name no group in the document is using yet: "Group", then "Group 2",
    /// "Group 3"… so two groups made a second apart are tellable apart in the
    /// layers list.
    public func freshGroupName(base: String = "Group") -> String {
        let taken = Set(allLayers.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Dissolves every group in `ids` in ONE mutation, so ⇧⌘G over a
    /// multi-selection is a single undo step. Each group's children land back
    /// in its own slot with their positions rewritten, so nothing moves on
    /// screen; a group nested inside one being dissolved comes out whole.
    /// Returns the freed layers' ids, which is what the caller selects next.
    /// Non-groups and locked groups are ignored.
    @discardableResult
    public mutating func ungroupLayers(ids: Set<UUID>) -> [UUID] {
        // Deepest first, so dissolving an outer group can't invalidate the
        // path of an inner one still to come.
        let targets = ungroupableMembers(ids: ids)
            .compactMap { id -> (id: UUID, depth: Int)? in
                path(of: id).map { (id, $0.count) }
            }
            .sorted { $0.depth > $1.depth }
        var freed: [UUID] = []
        for target in targets {
            freed.append(contentsOf: ungroupLayer(id: target.id))
        }
        return freed
    }

    // MARK: - Where a click lands

    /// What a plain click selects, and the group it resolved inside.
    ///
    /// `context` is where the pointer already is: nil for the canvas, or the
    /// group a double click stepped into. A click inside that group (or inside
    /// one of the groups above it) picks the child at that level; a click
    /// anywhere else leaves the group behind and picks a top-level layer, so
    /// there is always one obvious way back out. Nil when nothing was hit.
    public func selectionTarget(at point: CGPoint, zoom: CGFloat = 1,
                                inside context: UUID?) -> (id: UUID, context: UUID?)? {
        guard let hit = hitTestPath(point, zoom: zoom) else { return nil }
        // Walk out from where we are: the deepest context the click is
        // actually inside wins, so clicking a sibling keeps you at that level.
        var candidate = context
        while let id = candidate, let candidatePath = path(of: id) {
            if hit.count > candidatePath.count, Array(hit.prefix(candidatePath.count)) == candidatePath,
               let picked = layer(atPath: Array(hit.prefix(candidatePath.count + 1))) {
                return (picked.id, id)
            }
            candidate = parentID(of: id)
        }
        guard let outermost = layer(atPath: [hit[0]]) else { return nil }
        return (outermost.id, nil)
    }

    /// What a ⇧-click adds to the selection, or drops from it.
    ///
    /// A ⇧-click extends the selection at the level you are already on, and
    /// only there: at the top level it picks whole groups, the way a plain
    /// click does, and inside a group it picks that group's own pieces. A
    /// ⇧-click that lands anywhere else — out on the canvas while you are
    /// inside a group — returns nil and does nothing, because the alternative
    /// is a selection made of layers from two different lists and a silent
    /// step back out of the group you were working in. Nil too when nothing
    /// was hit.
    public func extendTarget(at point: CGPoint, zoom: CGFloat = 1,
                             inside context: UUID?) -> UUID? {
        // A context whose group has since gone means the top level.
        let level = context.flatMap { layer(id: $0) != nil ? $0 : nil }
        guard let pick = selectionTarget(at: point, zoom: zoom, inside: level),
              pick.context == level else { return nil }
        return pick.id
    }

    /// What a double click selects: one level deeper than a plain click would
    /// go. Returns the layer that becomes selected and the group that becomes
    /// the new context, or nil when there is nothing deeper under the pointer —
    /// which is when a double click means whatever it already meant (opening a
    /// text layer for typing, a caption for editing).
    public func descendTarget(at point: CGPoint, zoom: CGFloat = 1,
                              inside context: UUID?) -> (id: UUID, context: UUID)? {
        guard let hit = hitTestPath(point, zoom: zoom),
              let current = selectionTarget(at: point, zoom: zoom, inside: context),
              let currentPath = path(of: current.id),
              layer(id: current.id)?.isGroup == true,
              hit.count > currentPath.count,
              let picked = layer(atPath: Array(hit.prefix(currentPath.count + 1)))
        else { return nil }
        return (picked.id, current.id)
    }

    // MARK: - Canvas coordinates, for everything that draws

    /// A layer with its frame moved into CANVAS coordinates — what the canvas
    /// draws handles, knobs and outlines against.
    ///
    /// A leaf reports its own frame; a group reports the box it actually
    /// occupies, since a group's stored size is unused and its origin is only
    /// an anchor. For a top-level layer this is the layer itself, which is why
    /// nothing about a document without groups changes.
    ///
    /// The children of a returned group are NOT rewritten: they stay in their
    /// own space, and asking for one of them by id is how you place it.
    public func canvasLayer(id: UUID) -> Layer? {
        guard var layer = layer(id: id), let origin = parentOrigin(of: id) else { return nil }
        layer.frame = layer.localBounds.offsetBy(dx: origin.x, dy: origin.y)
        return layer
    }

    /// The topmost editable layer under a canvas point, with its frame in
    /// canvas coordinates — the form everything that draws wants it in.
    public func canvasHitTest(_ point: CGPoint, zoom: CGFloat = 1) -> Layer? {
        hitTest(point, zoom: zoom).flatMap { canvasLayer(id: $0.id) }
    }

    /// A canvas-space frame written back into the space the layer is stored
    /// in. For a top-level layer this is the frame unchanged. Leaves only: a
    /// group's stored frame is an anchor, not a box, so a group moves through
    /// `moveLayer(id:toCanvasOrigin:)` instead.
    public func parentSpaceFrame(_ frame: CGRect, of id: UUID) -> CGRect? {
        guard let origin = parentOrigin(of: id) else { return nil }
        return frame.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    /// Moves a layer so the top left of the box it occupies lands on
    /// `parentOrigin`, in the space the layer is stored in — what the
    /// inspector's X and Y fields type into.
    public mutating func moveLayer(id: UUID, toParentOrigin parentOrigin: CGPoint) {
        guard let current = layer(id: id)?.localBounds else { return }
        let delta = CGPoint(x: parentOrigin.x - current.origin.x,
                            y: parentOrigin.y - current.origin.y)
        guard delta != .zero else { return }
        updateLayer(id: id) { $0.frame = $0.frame.offsetBy(dx: delta.x, dy: delta.y) }
    }

    /// Moves a layer so the top left of the box it occupies lands on
    /// `canvasOrigin`. A group carries everything inside it, in one number
    /// changing rather than one per child — which is what makes dragging a
    /// whole grouped card across the canvas free.
    public mutating func moveLayer(id: UUID, toCanvasOrigin canvasOrigin: CGPoint) {
        guard let current = canvasBounds(of: id) else { return }
        let delta = CGPoint(x: canvasOrigin.x - current.origin.x,
                            y: canvasOrigin.y - current.origin.y)
        guard delta != .zero else { return }
        updateLayer(id: id) { $0.frame = $0.frame.offsetBy(dx: delta.x, dy: delta.y) }
    }
}
