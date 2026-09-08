import CoreGraphics
import Foundation

/// Versions: one component holding more than one drawing of itself
/// (`docs/design/ui-building.md`, "A component holds more than one version").
///
/// A button has a normal look, a hover look and a disabled look. Before this
/// they were three components, and the three drifted apart the first time
/// somebody edited one. A **version** is a second complete drawing under the
/// same name: the Library shows one tile, and every copy picks which version it
/// is showing.
///
/// Each version is a whole drawing rather than a list of differences, which is
/// what the user chose on 2026-09-05. It buys the thing a list of differences
/// cannot: a version may differ in ANY way at all — a different shape, an extra
/// part, a different arrangement — not only in colour and wording. The cost
/// that comes with it, accepted with the choice, is that a change meant for
/// every version has to be made in each one. A new version is therefore made by
/// duplicating one that already exists, so versions start out identical and
/// only differ where somebody made them differ.
///
/// A version is an ORDINARY main on the canvas: same group, same layers list,
/// same tools, same undo. That is deliberate — a version you cannot see is a
/// version you cannot edit — and it is why nothing here teaches the renderer,
/// hit testing or the package writer a new word.
///
/// Make Alternatives (`ComponentChoice`) is a different thing and stays one: it
/// swaps one layer for a sibling INSIDE one drawing.

// MARK: - One version

/// One version of a component: what it is called, and the drawing that is it.
public struct ComponentVersion: Hashable, Sendable, Identifiable {
    /// Its identity, which is what a copy stores to say which one it shows.
    /// A component that has only ever had one version has never needed one, so
    /// there the layer's own id stands in: nothing can be pointing at it under
    /// another name, because there was never another name.
    public var id: UUID
    /// What the menu on a copy calls it.
    public var name: String
    /// The main on the canvas that draws it.
    public var layerID: UUID

    public init(id: UUID, name: String, layerID: UUID) {
        self.id = id
        self.name = name
        self.layerID = layerID
    }
}

extension Layer {

    /// Which version of its component this main draws, nil while the component
    /// has only one.
    public var componentVersionID: UUID? { group?.versionID }

    /// What this version is called, nil while the component has only one.
    public var componentVersionName: String? { group?.versionName }

    /// Which version this copy shows, nil for a copy showing the first one.
    public var instanceVersionID: UUID? { group?.instanceVersion }
}

// MARK: - Reading a component's versions

extension PhotonzDocument {

    /// How far to the right of the original a new version is put down, in
    /// canvas points. Enough air that the two read as two drawings.
    static let componentVersionGap: CGFloat = 24

    /// Every version of a component, in the order the tree holds them. The
    /// first is the one a copy shows when it has not been told otherwise.
    ///
    /// A component nobody has given a second version to answers with exactly
    /// one, so everything downstream can be written as though versions were
    /// always there.
    public func componentVersions(of componentID: UUID) -> [ComponentVersion] {
        var found: [ComponentVersion] = []
        for main in mainComponents where main.componentID == componentID {
            found.append(ComponentVersion(id: main.componentVersionID ?? main.id,
                                          name: main.componentVersionName
                                            ?? ComponentNaming.versionName(at: found.count),
                                          layerID: main.id))
        }
        return found
    }

    /// One version by id, nil for an id this component does not hold.
    public func componentVersion(of componentID: UUID, id: UUID) -> ComponentVersion? {
        componentVersions(of: componentID).first { $0.id == id }
    }

    /// How many versions a component holds, which is what its shelf tile says.
    public func componentVersionCount(of componentID: UUID) -> Int {
        mainComponents.reduce(0) { $0 + ($1.componentID == componentID ? 1 : 0) }
    }

    /// The drawing of one version, falling back to the component's first when
    /// the version named is not one it has. Falling back rather than answering
    /// nothing is what keeps a copy drawing something after the version it was
    /// showing is deleted.
    public func mainComponent(componentID: UUID, version: UUID?) -> Layer? {
        guard let version else { return mainComponent(componentID: componentID) }
        let versions = componentVersions(of: componentID)
        guard let match = versions.first(where: { $0.id == version }) ?? versions.first
        else { return nil }
        return layer(id: match.layerID)
    }

    /// Whether adding a version to this component would do anything.
    public func canAddComponentVersion(componentID: UUID) -> Bool {
        mainComponent(componentID: componentID) != nil
    }

    // MARK: - Adding one

    /// Gives a component another version by duplicating one it already has, and
    /// returns the new version's id.
    ///
    /// The duplicate is a complete drawing of its own with its own layers, so
    /// editing one version never moves the other. It keeps the KNOB IDS of the
    /// version it came from and points them at its own layers, which is what
    /// lets a copy keep the wording and the colours it chose when it is
    /// switched from one version to the other — a duplicate with fresh knob ids
    /// would reset every copy the moment it switched.
    ///
    /// It lands loose on the canvas beside the version it came from rather than
    /// inside whatever holds that one, so adding a version to a button that
    /// lives on a screen never drops a stray button into the screen.
    @discardableResult
    public mutating func addComponentVersion(componentID: UUID, from version: UUID? = nil,
                                             name: String? = nil) -> UUID? {
        guard let source = mainComponent(componentID: componentID, version: version) else { return nil }
        let existing = componentVersions(of: componentID)
        // From here on every version of this component says which one it is and
        // every copy says which one it shows, so what a copy draws can never
        // depend on the order the layers happen to sit in.
        settleComponentVersionIdentities(componentID: componentID)
        guard let settled = layer(id: source.id) else { return nil }
        var copy = settled.reidentified()
        guard var group = copy.group else { return nil }
        let chosen = ComponentNaming.normalized(name)
            ?? ComponentNaming.freshVersionName(taken: existing.map(\.name), count: existing.count)
        // `reidentified` mints a component of its own, because duplicating a
        // main is how you get a second component. This is the other errand:
        // the same component, one more drawing of it.
        group.componentID = componentID
        let versionID = UUID()
        group.versionID = versionID
        group.versionName = chosen
        copy.content = .group(group)
        copy.name = settled.name
        copy.isLocked = false
        let parent = parentOrigin(of: settled.id) ?? .zero
        let sourceBox = settled.localBounds.offsetBy(dx: parent.x, dy: parent.y)
        let landing = roomForDrawing(size: sourceBox.size, beside: sourceBox)
        // The copy goes in at the top level, so its own box IS its canvas box:
        // sitting it where the source sits and then shifting by the difference
        // lands it exactly on the spot that was found.
        copy.frame.origin = CGPoint(x: settled.frame.origin.x + parent.x + (landing.x - sourceBox.minX),
                                    y: settled.frame.origin.y + parent.y + (landing.y - sourceBox.minY))
        addLayer(copy)
        return versionID
    }

    /// Where a new drawing of `size` can sit on the canvas without covering
    /// anything that is already there.
    ///
    /// It reads the way a row of drawings reads: along from `source`, stepping
    /// clear of whatever it runs into, and when the row runs out of canvas,
    /// down to a fresh row under everything in the way, starting back at
    /// `source`'s left edge. Two rules keep it somewhere a person can actually
    /// get to: it never overlaps a top-level layer, and it never leaves the
    /// canvas, because the canvas camera cannot travel past the canvas and a
    /// drawing dropped over the edge is one nobody can look at.
    ///
    /// Only TOP-LEVEL layers count as taken, because that is where the new
    /// drawing goes: adding a version to a button that lives on a screen steps
    /// clear of the whole screen rather than trying to squeeze in beside the
    /// button inside it. A layer covering the WHOLE canvas is scenery rather
    /// than an occupant and is stepped over: nearly every document has one (a
    /// screenshot, the locked Background of a blank one), there is nowhere on
    /// the canvas that is not on top of it, and counting it would mean nothing
    /// ever finds room and every version lands on the last one.
    ///
    /// A canvas with no room left anywhere falls back to the old behaviour, one
    /// gap along from `source`: an overlap is a worse answer than nothing at
    /// all, but losing the drawing entirely is worse than both.
    func roomForDrawing(size: CGSize, beside source: CGRect,
                        gap: CGFloat = PhotonzDocument.componentVersionGap) -> CGPoint {
        let fallback = CGPoint(x: source.maxX + gap, y: source.minY)
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let taken = layers.compactMap { canvasBounds(of: $0.id) }
            .filter { !$0.isEmpty && !$0.contains(canvas) }
        guard size.width <= canvas.width, size.height <= canvas.height else { return fallback }

        // The row the source is on first, then a row under each thing that
        // could be blocking it, nearest first.
        var rows = [source.minY]
        rows += taken.map { ($0.maxY + gap).rounded() }.filter { $0 > source.minY }
        rows = Array(Set(rows)).sorted()

        for row in rows {
            guard row + size.height <= canvas.maxY else { continue }
            // A fresh row starts back at the left, under the source; the
            // source's own row starts clear of the source itself.
            var x = (row == source.minY ? source.maxX + gap : source.minX).rounded()
            // Each step lands strictly further right than the last, so this
            // cannot run longer than there are things to step over.
            for _ in 0...taken.count {
                guard x + size.width <= canvas.maxX else { break }
                let spot = CGRect(x: x, y: row, width: size.width, height: size.height)
                guard let blocker = taken.first(where: { $0.intersects(spot) }) else {
                    return spot.origin
                }
                x = (blocker.maxX + gap).rounded()
            }
        }
        return fallback
    }

    /// Gives every version of a component an id and a name, and every copy of
    /// it the id of the version it is showing.
    ///
    /// Runs the moment a component gets its second version. Until then none of
    /// this is written down: a component with one version has nothing to tell
    /// apart, and a document saved before versions existed is byte for byte
    /// what it was.
    private mutating func settleComponentVersionIdentities(componentID: UUID) {
        let versions = componentVersions(of: componentID)
        guard let first = versions.first else { return }
        for version in versions {
            guard let main = layer(id: version.layerID),
                  main.componentVersionID == nil || main.componentVersionName == nil else { continue }
            updateLayer(id: version.layerID) { layer in
                guard var group = layer.group else { return }
                group.versionID = group.versionID ?? version.id
                group.versionName = group.versionName ?? version.name
                layer.content = .group(group)
            }
        }
        // A copy that says nothing shows the first version, so it says so now,
        // while "the first version" still means what it meant when it was made.
        stampInstanceVersions(of: componentID, to: first.id)
    }

    /// Writes a version id onto every copy of a component that has none.
    private mutating func stampInstanceVersions(of componentID: UUID, to version: UUID) {
        func stamp(_ list: [Layer]) -> [Layer] {
            list.map { layer in
                var copy = layer
                guard var group = copy.group else { return copy }
                if layer.instanceOf == componentID, group.instanceVersion == nil {
                    group.instanceVersion = version
                }
                group.children = stamp(group.children)
                copy.content = .group(group)
                return copy
            }
        }
        layers = stamp(layers)
    }

    // MARK: - Naming one

    /// Renames a version. A blank name is refused rather than leaving a
    /// nameless row in the menu on every copy.
    public mutating func renameComponentVersion(componentID: UUID, version: UUID, to name: String) {
        guard let match = componentVersion(of: componentID, id: version),
              let chosen = ComponentNaming.normalized(name) else { return }
        updateLayer(id: match.layerID) { layer in
            guard var group = layer.group else { return }
            group.versionName = chosen
            layer.content = .group(group)
        }
    }

    // MARK: - Which version a copy shows

    /// The versions this copy could show, empty for everything that is not a
    /// copy. One version is not a choice, so the menu is only worth showing
    /// while this has two or more in it.
    public func instanceVersions(of instance: UUID) -> [ComponentVersion] {
        guard let componentID = layer(id: instance)?.instanceOf else { return [] }
        return componentVersions(of: componentID)
    }

    /// The version this copy is showing: the one it was set to while that
    /// version still exists, and the component's first otherwise.
    public func instanceVersion(of instance: UUID) -> UUID? {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf else { return nil }
        let versions = componentVersions(of: componentID)
        if let own = copy.instanceVersionID, versions.contains(where: { $0.id == own }) { return own }
        return versions.first?.id
    }

    /// Whether this copy could be set to this version: it is a copy, it is not
    /// locked, and the version is one its own component holds. A version of
    /// some other component is refused rather than quietly ignored.
    public func canSetInstanceVersion(instance: UUID, to version: UUID) -> Bool {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf, !copy.isLocked
        else { return false }
        return componentVersion(of: componentID, id: version) != nil
    }

    /// Sets which version one copy shows. Everything the copy owns for itself —
    /// its answers to the knobs, its own size, its own look — is untouched, and
    /// the next sync redraws it from the version it now names.
    @discardableResult
    public mutating func setInstanceVersion(instance: UUID, to version: UUID) -> Bool {
        guard canSetInstanceVersion(instance: instance, to: version) else { return false }
        updateLayer(id: instance) { layer in
            guard var group = layer.group else { return }
            group.instanceVersion = version
            layer.content = .group(group)
        }
        return true
    }

    /// The same for every copy picked at once, and how many took it.
    @discardableResult
    public mutating func setInstanceVersion(instances: [UUID], to version: UUID) -> Int {
        instances.reduce(0) { setInstanceVersion(instance: $1, to: version) ? $0 + 1 : $0 }
    }
}

// MARK: - Telling two drawings apart on the canvas

extension PhotonzDocument {

    /// The version each drawing on the canvas should say it is, by layer id.
    ///
    /// Every version of a component carries the component's name, so a button
    /// with a Disabled version puts two boxes on the canvas both labelled
    /// Button. This is what the label adds after the name so the picture says
    /// which one you are looking at, the same rule the layers list uses.
    ///
    /// An original speaks whenever its component holds more than one version.
    /// A COPY only speaks when it is showing something other than the first
    /// version: a screen built out of twelve ordinary buttons would otherwise
    /// wear twelve labels all saying the same word, and the thing worth
    /// spotting is the odd one out.
    ///
    /// Empty for a document with no versions anywhere, which is every document
    /// until somebody asks for a second version, so the canvas draws exactly
    /// what it always did.
    ///
    /// One walk of the tree and one pass over the mains, because the canvas
    /// asks for this again on every pan, zoom and nudge.
    public func canvasVersionNames() -> [UUID: String] {
        let byComponent = multiVersionComponents()
        guard !byComponent.isEmpty else { return [:] }

        var names: [UUID: String] = [:]
        for versions in byComponent.values {
            for version in versions { names[version.layerID] = version.name }
        }
        for layer in allLayers {
            guard let name = Self.versionName(of: layer, in: byComponent) else { continue }
            names[layer.id] = name
        }
        return names
    }

    /// Every component holding more than one version, with its versions in the
    /// order the tree holds them. One pass over the mains, and empty for a
    /// document nobody has given a second version to — which is every document
    /// until somebody asks for one.
    ///
    /// This is what both the canvas label and the layers row are worked out
    /// from, so the picture and the list can never disagree about which drawing
    /// you are looking at.
    func multiVersionComponents() -> [UUID: [ComponentVersion]] {
        var byComponent: [UUID: [ComponentVersion]] = [:]
        for main in mainComponents {
            guard let componentID = main.componentID else { continue }
            var versions = byComponent[componentID] ?? []
            versions.append(ComponentVersion(id: main.componentVersionID ?? main.id,
                                             name: main.componentVersionName
                                               ?? ComponentNaming.versionName(at: versions.count),
                                             layerID: main.id))
            byComponent[componentID] = versions
        }
        return byComponent.filter { $0.value.count > 1 }
    }

    /// The version one layer should say it is, or nil for a layer with nothing
    /// to say — which is nearly every layer.
    ///
    /// An ORIGINAL speaks whenever its component holds more than one version:
    /// two boxes both called Button need telling apart. A COPY only speaks when
    /// it is showing something other than the first version, because a screen
    /// built out of twelve ordinary buttons would otherwise carry twelve labels
    /// all saying the same word, and the thing worth spotting is the odd one
    /// out.
    static func versionName(of layer: Layer, in byComponent: [UUID: [ComponentVersion]]) -> String? {
        if let componentID = layer.componentID {
            return byComponent[componentID]?.first { $0.layerID == layer.id }?.name
        }
        guard let componentID = layer.instanceOf,
              let versions = byComponent[componentID], let first = versions.first
        else { return nil }
        // A copy pointing at a version that has since been deleted falls back
        // to the first, exactly as `instanceVersion(of:)` does, so nothing ever
        // names a drawing that is no longer there.
        let shown = layer.instanceVersionID.flatMap { id in
            versions.first { $0.id == id }
        } ?? first
        return shown.id == first.id ? nil : shown.name
    }
}

// MARK: - What they are called

extension ComponentNaming {

    /// What the first version is called before anybody names it. It only ever
    /// shows once a second version exists, which is the moment it starts
    /// meaning something.
    public static let defaultVersionName = "Default"

    /// What the version in position `index` is called before anybody names it.
    public static func versionName(at index: Int) -> String {
        index == 0 ? defaultVersionName : "Version \(index + 1)"
    }

    /// A version name nobody is using yet: "Version 2", then "Version 3"…
    static func freshVersionName(taken: [String], count: Int) -> String {
        var index = max(count + 1, 2)
        while taken.contains("Version \(index)") { index += 1 }
        return "Version \(index)"
    }

    /// The detail line on a component's tile: how many versions it holds and
    /// how many copies of it are out. A component with one version says nothing
    /// about versions, because one version is just the component.
    public static func detail(instanceCount: Int, versionCount: Int) -> String {
        guard versionCount > 1 else { return detail(instanceCount: instanceCount) }
        let versions = "\(versionCount) versions"
        switch instanceCount {
        case 0: return versions
        case 1: return "\(versions) • 1 copy"
        default: return "\(versions) • \(instanceCount) copies"
        }
    }
}
