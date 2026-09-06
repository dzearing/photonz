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
        let origin = parentOrigin(of: settled.id) ?? .zero
        let width = max(settled.frame.width, settled.localBounds.maxX)
        copy.frame.origin = CGPoint(x: settled.frame.origin.x + origin.x + width + Self.componentVersionGap,
                                    y: settled.frame.origin.y + origin.y)
        addLayer(copy)
        return versionID
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
