import CoreGraphics
import Foundation

/// Where a component's ORIGINAL lives: in the document, never in the picture.
///
/// The user, 2026-10-04, after one drag of a Card put two Cards on the canvas:
/// "when i drag a component to the canvas, why are there 2 copies". A drag off
/// the Library puts down one instance and nothing else, the way a library drag
/// does in Figma. The original is still the document's — every instance is
/// filled from it, it is saved with the file, and Edit Original opens it — but
/// it sits in `componentOriginals` rather than `layers`, so everything that
/// walks the picture (the renderer, export, copy as image, hit testing, the
/// Layers list, the timeline) leaves it out by construction rather than by
/// remembering to.
///
/// Model lookups reach it: `layer(id:)`, `updateLayer(id:)`, `removeLayer(id:)`,
/// `mainComponents`, the sync that refills instances and the style passes all
/// read the library as well as the picture.
///
/// An original can still turn up in the picture: Make Component flips a group
/// you drew into one, a file saved before this has its originals on the canvas,
/// and a paste can carry one. `parkOriginals` moves each into the library and
/// leaves an instance in its place, so the canvas shows exactly what it showed;
/// `History` runs it after every edit and when a document opens.
extension PhotonzDocument {

    // MARK: - Finding one

    /// Edits a layer that lives in the component library, wherever inside an
    /// original it sits. Returns whether it was found.
    @discardableResult
    mutating func withLibrarySiblings(of id: UUID, _ mutate: (inout [Layer], Int) -> Void) -> Bool {
        func descend(_ list: inout [Layer]) -> Bool {
            if let index = list.firstIndex(where: { $0.id == id }) {
                mutate(&list, index)
                return true
            }
            for index in list.indices where list[index].isGroup {
                var children = list[index].children
                if descend(&children) {
                    list[index].children = children
                    return true
                }
            }
            return false
        }
        guard !componentOriginals.isEmpty else { return false }
        return descend(&componentOriginals)
    }

    /// The group a piece inside an original in the library sits in; nil for
    /// an original itself, which stands at the library's top level, and for an
    /// id the library does not hold.
    func libraryParentID(of id: UUID) -> UUID? {
        func search(_ list: [Layer], parent: UUID?) -> UUID?? {
            for layer in list {
                if layer.id == id { return .some(parent) }
                guard layer.isGroup else { continue }
                if let found = search(layer.children, parent: layer.id) { return found }
            }
            return nil
        }
        guard !componentOriginals.isEmpty, let found = search(componentOriginals, parent: nil)
        else { return nil }
        return found
    }

    /// Where a library layer's own coordinate space starts: `.zero` for an
    /// original, the sum of the groups above it for a piece inside one. Nil
    /// when the id is not in the library.
    func libraryParentOrigin(of id: UUID) -> CGPoint? {
        func search(_ list: [Layer], _ origin: CGPoint) -> CGPoint? {
            for layer in list {
                if layer.id == id { return origin }
                guard layer.isGroup else { continue }
                let inner = CGPoint(x: origin.x + layer.frame.origin.x, y: origin.y + layer.frame.origin.y)
                if let found = search(layer.children, inner) { return found }
            }
            return nil
        }
        guard !componentOriginals.isEmpty else { return nil }
        return search(componentOriginals, .zero)
    }

    /// Whether the layer is an original in the library, or something inside one.
    public func isInComponentLibrary(_ id: UUID) -> Bool {
        guard !componentOriginals.isEmpty else { return false }
        return componentOriginals.contains { $0.selfAndDescendants.contains { $0.id == id } }
    }

    /// Puts a drawing in the library. It is held at the origin: where an
    /// original sits means nothing once it is off the canvas, and every
    /// instance places itself.
    public mutating func addOriginal(_ original: Layer) {
        var original = original
        let box = original.localBounds
        original.frame.origin = CGPoint(x: original.frame.origin.x - box.minX,
                                        y: original.frame.origin.y - box.minY)
        componentOriginals.append(original)
    }

    // MARK: - Moving originals off the canvas

    /// Whether any original sits in the picture. Stops at the first.
    var holdsMainInPicture: Bool {
        func search(_ list: [Layer]) -> Bool {
            for layer in list where layer.isGroup {
                if layer.isMainComponent || search(layer.children) { return true }
            }
            return false
        }
        return search(layers)
    }

    /// Moves every original in the picture into the library and leaves an
    /// instance of it where it was, so the canvas draws exactly what it drew.
    /// The original keeps its id (every knob aimed at it, every version and
    /// every saved reference still finds it); the instance is a new layer with
    /// everything else the layer had: where it sits, its place in time, its
    /// track, its name. Returns what moved: the original's id against the id
    /// of the instance standing in its place.
    ///
    /// An original whose component the library already holds that version of
    /// is not kept twice: the one in the picture becomes an instance and the
    /// library's stays the source.
    @discardableResult
    public mutating func parkOriginals() -> [UUID: UUID] {
        guard holdsMainInPicture else { return [:] }
        // Outermost first: an original holding another takes it along.
        var found: [UUID] = []
        func collect(_ list: [Layer]) {
            for layer in list where layer.isGroup {
                if layer.isMainComponent { found.append(layer.id) } else { collect(layer.children) }
            }
        }
        collect(layers)

        var moved: [UUID: UUID] = [:]
        for id in found {
            guard let main = layer(id: id), let componentID = main.componentID else { continue }
            let origin = parentOrigin(of: id) ?? .zero
            let held = componentOriginals.contains {
                $0.componentID == componentID && $0.componentVersionID == main.componentVersionID
            }
            var standIn = instanceStandingIn(for: main, componentID: componentID)
            if !held {
                var original = main
                original.frame = original.frame.offsetBy(dx: origin.x, dy: origin.y)
                // Its place in time and on a track are the instance's now.
                original.time = nil
                original.trackID = nil
                componentOriginals.append(original)
                standIn.children = resolvedChildren(of: componentID,
                                                    version: main.componentVersionID,
                                                    instance: standIn.id, overrides: [], stack: [])
            }
            // The original leaves the picture and the instance takes its slot.
            let placed = standIn
            updateLayer(id: id) { $0 = placed }
            moved[id] = standIn.id
        }
        return moved
    }

    /// The instance that takes an original's place on the canvas: a new layer
    /// that is otherwise the same one — where it sits, its place in time, its
    /// track, what it is called — holding the original's contents as a copy
    /// does.
    private func instanceStandingIn(for main: Layer, componentID: UUID) -> Layer {
        var standIn = main.duplicated()
        standIn.name = main.name
        standIn.isLocked = main.isLocked
        guard var group = main.group else { return standIn }
        let version = main.componentVersionID
        group.componentID = nil
        group.versionID = nil
        group.versionName = nil
        group.variantName = nil
        group.variantAnswers = []
        group.properties = []
        group.isShared = false
        group.instanceOf = componentID
        group.instanceVersion = version
        group.overrides = []
        group.pieceTextStyles = []
        group.instanceSize = nil
        group.followedStyle = main.style
        group.children = resolvedChildren(of: componentID, version: version, instance: standIn.id,
                                          overrides: [], stack: [])
        standIn.content = .group(group)
        return standIn
    }

    // MARK: - Edit Original: a space of its own

    /// The room left round a component's drawings in its editing space.
    public static let editingSpaceMargin: CGFloat = 80
    /// The gap between two drawings of one component in its editing space.
    public static let editingSpaceGap: CGFloat = 40

    /// A document holding only this component's drawings on a page the size
    /// of the document's own: what Edit
    /// Original opens, the way Figma opens a main component on its own and
    /// Sketch has a symbols page. The page is the document's size, or bigger
    /// when the drawings need it, so another version added in the space has
    /// clear page beside the first to land on.
    ///
    /// Everything else the document knows comes along — its named styles, the
    /// other components (a drawing can hold an instance of one) — except the
    /// picture and its timeline, which are not what you are editing.
    public func editingSpace(forComponent componentID: UUID) -> PhotonzDocument? {
        let drawings = mainComponents.filter { $0.componentID == componentID }
        guard !drawings.isEmpty else { return nil }
        let margin = Self.editingSpaceMargin
        let gap = Self.editingSpaceGap
        let boxes = drawings.map(\.localBounds)
        let rowWidth = boxes.reduce(0) { $0 + $1.width } + gap * CGFloat(boxes.count - 1)
        let tallest = boxes.map(\.height).max() ?? 0
        let page = CGSize(width: max(canvasSize.width, rowWidth + margin * 2).rounded(.up),
                          height: max(canvasSize.height, tallest + margin * 2).rounded(.up))
        // Drawings that already sit clear on the page open exactly where they
        // are: a component you just made opens where the group stood, and the
        // versions you laid out last time are where you left them. Anything
        // else (a starter, held at the library's origin) is laid out in a row
        // in the middle.
        let room = CGRect(origin: .zero, size: page).insetBy(dx: gap, dy: gap)
        let clear = boxes.allSatisfy { room.contains($0) }
            && !boxes.enumerated().contains { i, a in
                boxes.enumerated().contains { j, b in i < j && a.intersects(b) }
            }
        var laidOut: [Layer] = []
        if clear {
            laidOut = drawings
        } else {
            var x = ((page.width - rowWidth) / 2).rounded()
            let top = ((page.height - tallest) / 2).rounded()
            for (drawing, box) in zip(drawings, boxes) {
                var placed = drawing
                placed.frame.origin = CGPoint(x: placed.frame.origin.x + x - box.minX,
                                              y: placed.frame.origin.y + top - box.minY)
                laidOut.append(placed)
                x += box.width + gap
            }
        }
        var space = self
        space.canvasSize = page
        space.layers = laidOut
        space.componentOriginals = componentOriginals.filter { $0.componentID != componentID }
        space.guides = []
        space.tracks = []
        space.trackGroups = []
        space.markers = []
        space.markInMS = nil
        space.markOutMS = nil
        space.durationMS = nil
        // A component asking two questions opens as the grid the variants mock
        // draws: a row per answer to the first, a column per answer to the
        // rest, with room above and to the left for the names along its edges.
        space.layOutComponentVariantGridOnPage(componentID: componentID)
        return space
    }

    /// Writes an editing space back: its drawings of the component replace the
    /// ones in the library, in the same place in the Library's order, and the
    /// named styles changed while it was open change here too, so the canvas
    /// and every instance follow when the sync runs.
    ///
    /// Anything drawn loose beside the component joins its first drawing
    /// rather than being lost, except a copy of the component itself, and a
    /// space emptied of the component leaves the
    /// component as it was: deleting an original is not what Done means.
    public mutating func returnFromEditingSpace(_ space: PhotonzDocument, componentID: UUID) {
        var drawings = space.layers.filter { $0.componentID == componentID }
        guard !drawings.isEmpty else { return }
        var others: [Layer] = []
        for layer in space.layers where layer.componentID != componentID {
            if layer.isMainComponent {
                others.append(layer)
                continue
            }
            // A copy of the component itself, or of anything holding one, left
            // loose on the page (a paste, say) would make a component that
            // draws forever, so it stays out rather than joining.
            if layer.instanceOf == componentID
                || space.componentsUsed(by: layer).contains(componentID) { continue }
            var child = layer
            child.frame = child.frame.offsetBy(dx: -drawings[0].frame.origin.x,
                                               dy: -drawings[0].frame.origin.y)
            drawings[0].children.append(child)
        }
        adoptStyles(from: space)
        let slot = componentOriginals.firstIndex { $0.componentID == componentID }
        let before = slot.map { componentOriginals[..<$0].count { $0.componentID != componentID } }
        var library = componentOriginals.filter { $0.componentID != componentID }
        let at = min(before ?? library.count, library.count)
        library.insert(contentsOf: drawings, at: at)
        componentOriginals = library
        for other in others { addOriginal(other) }
    }

    /// The named styles an editing space changed, replayed on this document
    /// through the same commands the Library uses, so every layer bound to one
    /// is repainted here as it was there.
    private mutating func adoptStyles(from space: PhotonzDocument) {
        for style in space.colorStyles {
            guard let mine = colorStyle(id: style.id) else { colorStyles.append(style); continue }
            if mine.paint != style.paint { setColorStylePaint(styleID: style.id, paint: style.paint) }
            if mine.name != style.name { renameColorStyle(id: style.id, to: style.name) }
            if mine.roles != style.roles, let index = colorStyles.firstIndex(where: { $0.id == style.id }) {
                colorStyles[index].roles = style.roles
            }
        }
        for style in colorStyles where !space.colorStyles.contains(where: { $0.id == style.id }) {
            deleteColorStyle(id: style.id)
        }
        for style in space.textStyles {
            guard let mine = textStyles.first(where: { $0.id == style.id }) else {
                textStyles.append(style); continue
            }
            if mine.treatment != style.treatment { setTextStyle(styleID: style.id, treatment: style.treatment) }
            if mine.name != style.name { renameTextStyle(id: style.id, to: style.name) }
        }
        for style in space.effectStyles {
            guard let mine = effectStyles.first(where: { $0.id == style.id }) else {
                effectStyles.append(style); continue
            }
            if mine.effect != style.effect { setEffectStyle(styleID: style.id, effect: style.effect) }
            if mine.name != style.name { renameEffectStyle(id: style.id, to: style.name) }
        }
    }
}
