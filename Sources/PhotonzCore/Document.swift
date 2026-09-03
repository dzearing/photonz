import CoreGraphics
import Foundation

/// The photonz document: a canvas plus an ordered stack of layers.
/// Index 0 renders at the bottom. Pure value type — all mutation goes
/// through methods so commands/undo can wrap them uniformly.
public struct PhotonzDocument: Hashable, Codable, Sendable {
    public var canvasSize: CGSize
    public var layers: [Layer]
    /// Bitmap pixels per logical point of the source capture (1 for non-Retina,
    /// 2 for a Retina screenshot). Measures divide raw pixel distances by this to
    /// read out in points. Set from the capture's `backingScaleFactor`.
    public var pixelScale: CGFloat

    public init(canvasSize: CGSize, layers: [Layer] = [], pixelScale: CGFloat = 1) {
        self.canvasSize = canvasSize
        self.layers = layers
        self.pixelScale = pixelScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canvasSize = try c.decode(CGSize.self, forKey: .canvasSize)
        layers = try c.decode([Layer].self, forKey: .layers)
        // `pixelScale` postdates the format; legacy documents omit it.
        pixelScale = try c.decodeIfPresent(CGFloat.self, forKey: .pixelScale) ?? 1
    }

    /// A new document built around a base image, which becomes the bottom layer.
    /// The background is born locked (Photoshop convention): clicks on it fall
    /// through to the marquee instead of dragging the whole image around.
    /// `pixelScale` carries the capture's backing scale so measures read in points.
    public static func withBaseImage(_ ref: ImageRef, pixelScale: CGFloat = 1) -> PhotonzDocument {
        let layer = Layer(name: "Background", content: .image(ref),
                          frame: CGRect(origin: .zero, size: ref.pixelSize),
                          isLocked: true)
        return PhotonzDocument(canvasSize: ref.pixelSize, layers: [layer], pixelScale: pixelScale)
    }

    // MARK: - Layer access

    /// Every layer in the document, groups and their contents alike, in
    /// draw order with each group listed before what it holds.
    public var allLayers: [Layer] {
        layers.flatMap(\.selfAndDescendants)
    }

    /// Finds a layer anywhere in the tree, inside groups included. For a
    /// document with no groups this is exactly the flat lookup it always was.
    public func layer(id: UUID) -> Layer? {
        func search(_ list: [Layer]) -> Layer? {
            for layer in list {
                if layer.id == id { return layer }
                if layer.isGroup, let found = search(layer.children) { return found }
            }
            return nil
        }
        return search(layers)
    }

    /// The layer's slot in the TOP-LEVEL stack. Nil for a layer that lives
    /// inside a group — ask for its `path` instead.
    public func index(of id: UUID) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// Where a layer sits in the tree: one index per level, outermost first,
    /// so `[1, 0]` is the bottom layer of the second top-level layer's group.
    /// Nil when the id is not in the document.
    public func path(of id: UUID) -> [Int]? {
        func search(_ list: [Layer], _ prefix: [Int]) -> [Int]? {
            for (i, layer) in list.enumerated() {
                if layer.id == id { return prefix + [i] }
                if layer.isGroup, let found = search(layer.children, prefix + [i]) { return found }
            }
            return nil
        }
        return search(layers, [])
    }

    /// The layer at a tree path, nil if the path does not lead anywhere.
    public func layer(atPath path: [Int]) -> Layer? {
        var list = layers
        var found: Layer?
        for index in path {
            guard list.indices.contains(index) else { return nil }
            found = list[index]
            list = list[index].children
        }
        return found
    }

    /// The group a layer lives in, nil when it sits loose on the canvas.
    public func parentID(of id: UUID) -> UUID? {
        guard let path = path(of: id), path.count > 1 else { return nil }
        return layer(atPath: Array(path.dropLast()))?.id
    }

    /// Where a layer's own coordinate space starts, in canvas coordinates: the
    /// sum of the origins of every group above it, and `.zero` for a layer
    /// sitting loose on the canvas.
    public func parentOrigin(of id: UUID) -> CGPoint? {
        guard let path = path(of: id) else { return nil }
        var origin = CGPoint.zero
        var list = layers
        for index in path.dropLast() {
            guard list.indices.contains(index) else { return nil }
            origin.x += list[index].frame.origin.x
            origin.y += list[index].frame.origin.y
            list = list[index].children
        }
        return origin
    }

    /// A layer's stored frame moved into canvas coordinates. For a top-level
    /// layer this is the frame itself, which is why nothing about a document
    /// without groups changes.
    public func canvasFrame(of id: UUID) -> CGRect? {
        guard let layer = layer(id: id), let origin = parentOrigin(of: id) else { return nil }
        return layer.frame.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// The canvas-space box a layer and everything inside it occupies. Same as
    /// `canvasFrame` for a leaf; for a group it follows the contents.
    public func canvasBounds(of id: UUID) -> CGRect? {
        guard let layer = layer(id: id), let origin = parentOrigin(of: id) else { return nil }
        return layer.localBounds.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// Every layer in canvas coordinates with the groups dissolved away: the
    /// leaves only, bottom-up, each one's frame moved into canvas space and
    /// each one carrying the visibility, lock and opacity of the groups above
    /// it. This is what the renderer and everything else that thinks in canvas
    /// coordinates runs on until they learn the tree themselves.
    ///
    /// A document with no groups hands back its own array untouched.
    public var flattenedLayers: [Layer] {
        guard layers.contains(where: \.isGroup) else { return layers }
        var out: [Layer] = []
        func walk(_ list: [Layer], origin: CGPoint, visible: Bool, locked: Bool, opacity: Double) {
            for layer in list {
                let visible = visible && layer.isVisible
                let locked = locked || layer.isLocked
                let opacity = opacity * layer.style.opacity
                if layer.isGroup {
                    walk(layer.children,
                         origin: CGPoint(x: origin.x + layer.frame.origin.x,
                                         y: origin.y + layer.frame.origin.y),
                         visible: visible, locked: locked, opacity: opacity)
                } else {
                    var flat = layer
                    flat.frame = layer.frame.offsetBy(dx: origin.x, dy: origin.y)
                    flat.isVisible = visible
                    flat.isLocked = locked
                    flat.style.opacity = opacity
                    out.append(flat)
                }
            }
        }
        walk(layers, origin: .zero, visible: true, locked: false, opacity: 1)
        return out
    }

    /// Edits the list a layer sits in, handing the callback that list and the
    /// layer's slot in it. A top-level layer takes the same single pass over
    /// the stack it always did, so a document with no groups pays nothing for
    /// them. Returns whether the layer was found.
    @discardableResult
    private mutating func withSiblings(of id: UUID, _ mutate: (inout [Layer], Int) -> Void) -> Bool {
        if let index = layers.firstIndex(where: { $0.id == id }) {
            mutate(&layers, index)
            return true
        }
        guard layers.contains(where: \.isGroup), let path = path(of: id), path.count > 1
        else { return false }
        var found = false
        withChildren(atPath: Array(path.dropLast())) { children in
            guard let index = children.firstIndex(where: { $0.id == id }) else { return }
            mutate(&children, index)
            found = true
        }
        return found
    }

    /// Edits the CHILDREN of the group at `path`.
    private mutating func withChildren(atPath path: [Int], _ mutate: (inout [Layer]) -> Void) {
        func descend(_ list: inout [Layer], _ path: ArraySlice<Int>) {
            guard let index = path.first, list.indices.contains(index) else { return }
            let rest = path.dropFirst()
            if rest.isEmpty {
                mutate(&list[index].children)
            } else {
                descend(&list[index].children, rest)
            }
        }
        descend(&layers, path[...])
    }

    /// The topmost editable layer under a canvas point. Top-down order;
    /// invisible and locked layers never hit. `zoom` keeps stroke hit slop
    /// constant in screen points.
    public func hitTest(_ point: CGPoint, zoom: CGFloat = 1) -> Layer? {
        hitTestPath(point, zoom: zoom).flatMap { layer(atPath: $0) }
    }

    /// The same search, reported as a tree path, so a caller that wants the
    /// GROUP a click landed in rather than the layer itself can walk back up.
    /// A hidden or locked group is skipped whole: nothing inside it can be
    /// picked without unhiding or unlocking it first.
    public func hitTestPath(_ point: CGPoint, zoom: CGFloat = 1) -> [Int]? {
        func search(_ list: [Layer], _ point: CGPoint, _ prefix: [Int]) -> [Int]? {
            for index in list.indices.reversed() {
                let layer = list[index]
                guard layer.isVisible, !layer.isLocked else { continue }
                if layer.isGroup {
                    let local = CGPoint(x: point.x - layer.frame.origin.x,
                                        y: point.y - layer.frame.origin.y)
                    if let found = search(layer.children, local, prefix + [index]) { return found }
                } else if layer.contains(canvasPoint: point, zoom: zoom) {
                    return prefix + [index]
                }
            }
            return nil
        }
        return search(layers, point, [])
    }

    /// The layers a marquee rubber-band captures: every visible, unlocked layer
    /// whose (transformed) bounds sit FULLY INSIDE `rect`, bottom-up. Fully
    /// inside — not intersecting — so sweeping around a cluster never grabs a
    /// long arrow that merely passes through. Locked layers (the background)
    /// and hidden layers never join.
    public func layerIDs(fullyInside rect: CGRect) -> [UUID] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        return layers.filter { layer in
            guard layer.isVisible, !layer.isLocked else { return false }
            // A group is grabbed whole or not at all: sweeping across half a
            // button never pulls its label out of it.
            var bounds = layer.isGroup ? layer.localBounds : layer.frame
            if !layer.isGroup, !layer.transform.isIdentity {
                let corners = layer.transformedCorners
                guard let first = corners.first else { return false }
                bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }
            }
            return rect.contains(bounds)
        }.map(\.id)
    }

    // MARK: - Layer mutation

    public mutating func addLayer(_ layer: Layer, at index: Int? = nil) {
        layers.insert(layer, at: index.map { min(max(0, $0), layers.count) } ?? layers.count)
    }

    /// Puts a layer inside a group, at `index` among the group's own children
    /// (top of the group by default). The layer's frame is read as already
    /// being in the group's space. Returns false when `groupID` is not a group.
    @discardableResult
    public mutating func addLayer(_ layer: Layer, toGroup groupID: UUID, at index: Int? = nil) -> Bool {
        guard let path = path(of: groupID), self.layer(atPath: path)?.isGroup == true,
              !layer.selfAndDescendants.contains(where: { $0.id == groupID }) else { return false }
        withChildren(atPath: path) { children in
            children.insert(layer, at: index.map { min(max(0, $0), children.count) } ?? children.count)
        }
        return true
    }

    /// Moves a layer into a group (or out to the canvas with `toGroup: nil`),
    /// REWRITING its position so it does not jump: dragging a layer into a
    /// group leaves it exactly where it was on screen. Returns false when the
    /// move is impossible — an unknown id, a target that is not a group, or a
    /// group being dropped inside itself.
    @discardableResult
    public mutating func moveLayer(id: UUID, toGroup groupID: UUID?, at index: Int? = nil) -> Bool {
        guard let layer = layer(id: id), let from = parentOrigin(of: id) else { return false }
        var to = CGPoint.zero
        if let groupID {
            guard let target = self.layer(id: groupID), target.isGroup,
                  // A group dropped inside itself (or inside one of its own
                  // children) would be a loop with no way back out.
                  !layer.selfAndDescendants.contains(where: { $0.id == groupID }),
                  let origin = parentOrigin(of: groupID) else { return false }
            to = CGPoint(x: origin.x + target.frame.origin.x, y: origin.y + target.frame.origin.y)
        }
        guard var moved = removeLayer(id: id) else { return false }
        moved.frame = moved.frame.offsetBy(dx: from.x - to.x, dy: from.y - to.y)
        if let groupID {
            return addLayer(moved, toGroup: groupID, at: index)
        }
        addLayer(moved, at: index)
        return true
    }

    @discardableResult
    public mutating func removeLayer(id: UUID) -> Layer? {
        var removed: Layer?
        withSiblings(of: id) { siblings, index in
            removed = siblings.remove(at: index)
        }
        return removed
    }

    /// Removes every layer in `ids` in one mutation, so a batch delete is a
    /// single history step. Reaches inside groups; removing a group takes
    /// everything it holds with it. Unknown ids are ignored.
    public mutating func removeLayers(ids: Set<UUID>) {
        func prune(_ list: inout [Layer]) {
            list.removeAll { ids.contains($0.id) }
            for i in list.indices where list[i].isGroup {
                prune(&list[i].children)
            }
        }
        prune(&layers)
    }

    /// Moves a layer to a new slot AMONG ITS OWN SIBLINGS. A child reorders
    /// inside its group and never escapes it.
    public mutating func moveLayer(id: UUID, to newIndex: Int) {
        withSiblings(of: id) { siblings, index in
            let layer = siblings.remove(at: index)
            siblings.insert(layer, at: min(max(0, newIndex), siblings.count))
        }
    }

    /// Edits a layer wherever it lives, inside a group included.
    public mutating func updateLayer(id: UUID, _ mutate: (inout Layer) -> Void) {
        withSiblings(of: id) { siblings, index in
            mutate(&siblings[index])
        }
    }

    /// Reorders layers from the layers panel, which lists them top-down
    /// (visual index 0 = topmost = last in `layers`). Source offsets and the
    /// destination use SwiftUI `onMove` semantics: the destination indexes the
    /// visual array *before* the moved rows are removed.
    public mutating func moveLayers(visualSources: IndexSet, visualDestination: Int) {
        var visual = Array(layers.reversed())
        let moved = visualSources.compactMap { visual.indices.contains($0) ? visual[$0] : nil }
        guard !moved.isEmpty else { return }
        let movedIDs = Set(moved.map(\.id))
        var destination = visualDestination - visualSources.count { $0 < visualDestination }
        visual.removeAll { movedIDs.contains($0.id) }
        destination = min(max(0, destination), visual.count)
        visual.insert(contentsOf: moved, at: destination)
        layers = visual.reversed()
    }

    /// One step of the Layers menu's arrange commands, applied to a whole
    /// selection at once.
    public enum RestackStep: Sendable, Hashable {
        case toFront, forward, backward, toBack
    }

    /// Moves every unlocked layer in `ids` one arrange step, together: the
    /// selected layers keep their relative order and the gaps between them,
    /// a member that already presses against the top (or the floor) pins the
    /// members behind it in place, and nothing passes the locked Background
    /// at the bottom. Locked members and unknown ids are ignored. Returns
    /// whether the stack changed, so a no-op never costs an undo step.
    @discardableResult
    public mutating func restackLayers(ids: Set<UUID>, _ step: RestackStep) -> Bool {
        // Arrange works inside one list at a time: a selection spanning a group
        // and the canvas restacks in each place, and a child never climbs out
        // of its group by pressing Bring to Front.
        var changed = false
        var lists = Set<[Int]>()
        for id in ids {
            guard let path = path(of: id) else { continue }
            lists.insert(Array(path.dropLast()))
        }
        for list in lists.sorted(by: { $0.count > $1.count }) {
            if list.isEmpty {
                var top = layers
                if Self.restack(&top, ids: ids, step) { layers = top; changed = true }
            } else {
                withChildren(atPath: list) { children in
                    changed = Self.restack(&children, ids: ids, step) || changed
                }
            }
        }
        return changed
    }

    private static func restack(_ layers: inout [Layer], ids: Set<UUID>, _ step: RestackStep) -> Bool {
        let moving = Set(layers.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id))
        guard !moving.isEmpty else { return false }
        let floor = layers.prefix(while: \.isLocked).count
        let before = layers.map(\.id)
        switch step {
        case .toFront:
            let block = layers.filter { moving.contains($0.id) }
            layers.removeAll { moving.contains($0.id) }
            layers.append(contentsOf: block)
        case .toBack:
            let block = layers.filter { moving.contains($0.id) }
            layers.removeAll { moving.contains($0.id) }
            layers.insert(contentsOf: block, at: min(floor, layers.count))
        case .forward:
            // Top down, so a member that just moved up leaves its slot free
            // for the member beneath it, and a pinned member pins the rest.
            for i in stride(from: layers.count - 2, through: 0, by: -1)
            where moving.contains(layers[i].id) && !moving.contains(layers[i + 1].id) {
                layers.swapAt(i, i + 1)
            }
        case .backward:
            for i in layers.indices
            where i > floor && moving.contains(layers[i].id) && !moving.contains(layers[i - 1].id) {
                layers.swapAt(i, i - 1)
            }
        }
        return layers.map(\.id) != before
    }

    /// Duplicates every layer in `ids` in one mutation, each copy directly
    /// above its own original, so a multi-selection duplicates in a single
    /// history step. Returns the copies bottom-up. Unknown ids are ignored.
    @discardableResult
    public mutating func duplicateLayers(ids: Set<UUID>, offsetBy offset: CGPoint = .zero) -> [Layer] {
        var copies: [Layer] = []
        func walk(_ list: inout [Layer]) {
            var result: [Layer] = []
            result.reserveCapacity(list.count)
            for var layer in list {
                if layer.isGroup, !ids.contains(layer.id) {
                    // A group that is not itself being duplicated may still
                    // hold something that is.
                    walk(&layer.children)
                }
                result.append(layer)
                if ids.contains(layer.id) {
                    let copy = layer.duplicated(offsetBy: offset)
                    copies.append(copy)
                    result.append(copy)
                }
            }
            list = result
        }
        walk(&layers)
        return copies
    }

    /// Duplicates a layer directly above the original (panel context menu, ⌘V
    /// of a copied layer reuses `Layer.duplicated`). Returns the copy.
    @discardableResult
    public mutating func duplicateLayer(id: UUID, offsetBy offset: CGPoint = .zero) -> Layer? {
        var copy: Layer?
        withSiblings(of: id) { siblings, index in
            let made = siblings[index].duplicated(offsetBy: offset)
            siblings.insert(made, at: index + 1)
            copy = made
        }
        return copy
    }

    // MARK: - Grouping

    /// Wraps a selection in a new group, in one mutation so it is one undo step.
    ///
    /// The group's origin is the top left of what was selected, and each
    /// member's position is rewritten against it once, so nothing moves on
    /// screen. Only layers that share a parent can be wrapped together: the
    /// selected layer nearest the canvas (and topmost, on a tie) decides which
    /// list takes part, and ids elsewhere in the tree are left where they are
    /// rather than being yanked out of their group. Locked layers (the
    /// background) never join. Returns the new group, or nil when nothing
    /// could be grouped.
    @discardableResult
    public mutating func groupLayers(ids: Set<UUID>, name: String = "Group") -> Layer? {
        let paths = ids.compactMap { path(of: $0) }
        guard let anchor = paths.min(by: {
            $0.count != $1.count ? $0.count < $1.count : ($0.last ?? 0) > ($1.last ?? 0)
        }) else { return nil }
        let parent = Array(anchor.dropLast())
        var group: Layer?
        func build(_ list: inout [Layer]) {
            let members = list.filter { ids.contains($0.id) && !$0.isLocked }
            guard !members.isEmpty else { return }
            var union = members[0].localBounds
            for member in members.dropFirst() { union = union.union(member.localBounds) }
            let origin = union.origin
            let slot = list.lastIndex { ids.contains($0.id) && !$0.isLocked } ?? list.count
            let below = list[..<slot].count { ids.contains($0.id) && !$0.isLocked }
            let children = members.map { member -> Layer in
                var child = member
                child.frame = member.frame.offsetBy(dx: -origin.x, dy: -origin.y)
                return child
            }
            let made = Layer(name: name, content: .group(GroupContent(children: children)),
                             frame: CGRect(origin: origin, size: .zero))
            list.removeAll { ids.contains($0.id) && !$0.isLocked }
            list.insert(made, at: min(max(0, slot - below), list.count))
            group = made
        }
        if parent.isEmpty { build(&layers) } else { withChildren(atPath: parent) { build(&$0) } }
        return group
    }

    /// Dissolves a group, putting its children back into their grandparent's
    /// list in the group's own slot with their positions rewritten into that
    /// space, so nothing moves on screen. Returns the freed layers' ids,
    /// bottom-up; empty when `id` is not a group.
    @discardableResult
    public mutating func ungroupLayer(id: UUID) -> [UUID] {
        guard let group = layer(id: id), group.isGroup else { return [] }
        let origin = group.frame.origin
        let freed = group.children.map { child -> Layer in
            var child = child
            child.frame = child.frame.offsetBy(dx: origin.x, dy: origin.y)
            return child
        }
        withSiblings(of: id) { siblings, index in
            siblings.replaceSubrange(index...index, with: freed)
        }
        return freed.map(\.id)
    }

    /// Copies a region of the canvas into a new layer placed directly on top
    /// ("promote selection to layer"). The caller supplies the ImageRef for the
    /// rasterized region (rendering lives outside the core model).
    @discardableResult
    public mutating func promoteRegionToLayer(region: CGRect, rasterized ref: ImageRef, name: String = "Promoted Layer") -> Layer {
        let clamped = Geometry.clampCrop(region, toCanvas: canvasSize)
        let layer = Layer(name: name, content: .image(ref), frame: clamped)
        layers.append(layer)
        return layer
    }

    /// The one-click blur-behind recipe: stacks a blurred full-canvas copy of
    /// the composite, then a sharp copy cropped to `selection` on top — the
    /// selection stays crisp while everything around it blurs. Both layers
    /// share `ref` (one full-canvas rasterization); both stay fully
    /// non-destructive (the blur is a style, the cutout a stored crop).
    @discardableResult
    public mutating func blurBehind(selection: CGRect, rasterized ref: ImageRef,
                                    blurRadius: CGFloat = 16) -> (blur: Layer, focus: Layer) {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        var blur = Layer(name: "Blur Behind", content: .image(ref), frame: canvasRect)
        blur.style.blurRadius = blurRadius
        var focus = Layer(name: "Focus", content: .image(ref), frame: canvasRect)
        focus.cropContent(to: Geometry.clampCrop(selection, toCanvas: canvasSize))
        layers.append(blur)
        layers.append(focus)
        return (blur, focus)
    }

    /// Bakes a vector layer into pixels ("Rasterize Layer"). The caller renders
    /// the layer WITH all its style effects (blur, shadow, border, corner radius,
    /// opacity) and geometry (crop, transform) into `ref`, covering the padded
    /// on-canvas `frame`, then hands both here. This swaps the layer's content to
    /// the bitmap and resets the now-baked style/crop/transform to their defaults
    /// so nothing is applied twice, while keeping the layer's identity, name,
    /// stacking slot, visibility, and lock. Blend mode is the one exception: it
    /// composites against the layers BELOW, which an isolated bitmap can't bake,
    /// so the layer's effective blend mode is carried onto the image layer (a
    /// rasterized highlight keeps multiplying). Undo restores the vector layer.
    public mutating func rasterizeLayer(id: UUID, rasterized ref: ImageRef, frame: CGRect) {
        updateLayer(id: id) { layer in
            let blend = layer.effectiveBlendMode
            layer.content = .image(ref)
            layer.frame = frame
            layer.crop = nil
            layer.transform = .identity
            layer.style = LayerStyle(blendMode: blend)
        }
    }

    // MARK: - Canvas operations

    /// Crops the whole document. Layer frames are re-expressed relative to the
    /// new canvas origin; layers entirely outside the crop are removed.
    public mutating func crop(to rect: CGRect) {
        let r = Geometry.clampCrop(rect, toCanvas: canvasSize)
        canvasSize = r.size
        // Only the top level shifts: a group's children are stored against the
        // group, so moving the group once moves everything inside it.
        layers = layers.compactMap { layer in
            var l = layer
            l.frame.origin.x -= r.origin.x
            l.frame.origin.y -= r.origin.y
            let canvasRect = CGRect(origin: .zero, size: r.size)
            guard l.localBounds.intersects(canvasRect) else { return nil }
            return l
        }
    }

    /// Resizes the canvas, scaling all layer frames proportionally.
    public mutating func resize(to newSize: CGSize) {
        let scale = Geometry.resizeScale(from: canvasSize, to: newSize)
        canvasSize = newSize
        // Everything scales, groups included: a group's offset and the numbers
        // stored inside it are both in document points, so both follow the
        // canvas or the picture would come apart.
        func scaleAll(_ list: inout [Layer]) {
            for i in list.indices {
                let f = list[i].frame
                list[i].frame = CGRect(x: f.origin.x * scale.x, y: f.origin.y * scale.y,
                                       width: f.width * scale.x, height: f.height * scale.y)
                if list[i].isGroup { scaleAll(&list[i].children) }
            }
        }
        scaleAll(&layers)
    }
}
