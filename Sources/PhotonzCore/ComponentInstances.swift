import CoreGraphics
import Foundation

/// Copies that follow their original (`docs/design/ui-building.md`, step C5).
///
/// A **copy** — an instance — is a group carrying `instanceOf`, the id of the
/// component it follows. What is inside it is not its own: the document keeps
/// every copy's contents equal to the original's, so the only way anything
/// inside a copy changes is by editing the original. That is why a copy is one
/// object everywhere a person meets it — a click picks the whole copy, a double
/// click does not go into it, its layers row has no twist open, and nothing can
/// be dropped inside it. A piece you could select inside a copy is a piece you
/// could edit and lose the next time the original moved. Reaching in on purpose
/// is what overrides are for, and they are the next step.
///
/// Because the contents are kept rather than referenced, everything that
/// already walks a tree — the renderer, hit testing, export, thumbnails, the
/// package writer — sees an ordinary group and needs to know nothing about
/// components at all.

// MARK: - Reading a copy

extension Layer {

    /// The component this layer is a copy of, nil for everything else.
    public var instanceOf: UUID? { group?.instanceOf }

    /// Whether this layer is a copy placed from the Library.
    public var isComponentInstance: Bool { instanceOf != nil }

    /// Whether this layer can be opened, dropped into and descended into: a
    /// group, but not a copy, whose contents belong to its original.
    public var isOpenableGroup: Bool { isGroup && !isComponentInstance }
}

/// What one sync did, so the app can say it out loud.
public struct ComponentSyncReport: Hashable, Sendable {
    /// How many copies had their contents rewritten. Placing a copy and moving
    /// one both count zero: this is "how many followed an edit".
    public var updatedInstances: Int
    /// The components whose copies moved, so a notice can name one by name.
    public var componentIDs: Set<UUID>

    public init(updatedInstances: Int = 0, componentIDs: Set<UUID> = []) {
        self.updatedInstances = updatedInstances
        self.componentIDs = componentIDs
    }

    public var isEmpty: Bool { updatedInstances == 0 }
}

// MARK: - Deriving a copy's ids

/// The ids inside a copy.
///
/// They are DERIVED from the copy and the piece they stand for rather than
/// minted fresh, so refilling a copy twice produces exactly the same document.
/// Without that, the sync that runs after every edit would rewrite every id in
/// every copy each time, and an edit that changed nothing would still be
/// recorded as an undo step.
enum ComponentIdentity {

    /// A stable id for `source` as it appears inside `instance`.
    static func derived(instance: UUID, source: UUID) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: instance.uuid) { a in
            withUnsafeBytes(of: source.uuid) { b in
                // Two independently mixed halves per byte, so neither input can
                // be cancelled out by the other.
                for i in 0..<16 {
                    bytes[i] = mix(UInt64(a[i]) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(b[i]) &+ UInt64(i))
                }
            }
        }
        // A version-4 shape, so anything reading the bytes sees a normal UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// SplitMix64's finaliser, taken down to a byte.
    private static func mix(_ value: UInt64) -> UInt8 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return UInt8(truncatingIfNeeded: z)
    }
}

// MARK: - Placing and keeping copies

extension PhotonzDocument {

    /// How deep copies inside copies are followed. A component that held itself
    /// is refused when it is placed, so this only ever guards a document that
    /// arrived from somewhere else.
    static let componentNestingLimit = 8

    /// Whether the document holds any copy at all. Checked before every sync,
    /// which runs after every edit, so it stops at the first one it finds and
    /// builds nothing: a document that has never seen a component pays one
    /// walk of the tree and no allocation.
    public var holdsComponentInstance: Bool {
        func search(_ list: [Layer]) -> Bool {
            for layer in list where layer.isGroup {
                if layer.isComponentInstance || search(layer.children) { return true }
            }
            return false
        }
        return search(layers)
    }

    /// Whether any original in the document exposes a knob, or any copy
    /// answers one. Checked before pruning, which runs after every edit, so it
    /// stops at the first one it finds: a document that has never seen a
    /// component pays one walk of the tree and no allocation.
    var holdsComponentKnob: Bool {
        func search(_ list: [Layer]) -> Bool {
            for layer in list {
                guard let group = layer.group else { continue }
                if !group.properties.isEmpty || !group.overrides.isEmpty { return true }
                if search(group.children) { return true }
            }
            return false
        }
        return search(layers)
    }

    /// Every copy of a component, wherever in the tree it sits.
    public func instances(of componentID: UUID) -> [Layer] {
        allLayers.filter { $0.instanceOf == componentID }
    }

    /// How many copies of a component are out: what the shelf tile says.
    public func instanceCount(of componentID: UUID) -> Int {
        instances(of: componentID).count
    }

    /// The components a layer's subtree relies on: the ones it holds copies of,
    /// and everything those rely on in turn.
    private func componentsUsed(by layer: Layer, depth: Int = 0) -> Set<UUID> {
        guard depth < Self.componentNestingLimit else { return [] }
        var used: Set<UUID> = []
        if let referenced = layer.instanceOf {
            used.insert(referenced)
            if let main = mainComponent(componentID: referenced) {
                used.formUnion(componentsUsed(by: main, depth: depth + 1))
            }
        }
        for child in layer.children { used.formUnion(componentsUsed(by: child, depth: depth + 1)) }
        return used
    }

    /// Whether a copy of `componentID` may go inside `group` (nil for the
    /// canvas).
    ///
    /// It may not if that would make a component hold itself, directly or
    /// through anything it already holds: such a thing has no size and no
    /// picture, it just draws forever. The check is here rather than in the
    /// interface so no gesture can make one by accident.
    public func canInsertInstance(of componentID: UUID, intoGroup group: UUID?) -> Bool {
        guard mainComponent(componentID: componentID) != nil else { return false }
        guard let group else { return true }
        guard let target = layer(id: group), target.isOpenableGroup, !target.isLocked else { return false }
        // Every component this drop would land inside, including the target itself.
        var enclosing: Set<UUID> = []
        var current: UUID? = group
        while let id = current {
            if let component = layer(id: id)?.componentID { enclosing.insert(component) }
            if layer(id: id)?.isComponentInstance == true { return false }
            current = parentID(of: id)
        }
        guard !enclosing.contains(componentID) else { return false }
        // ...and a component that already holds any of them may not go inside them.
        guard let main = mainComponent(componentID: componentID) else { return false }
        return enclosing.isDisjoint(with: componentsUsed(by: main))
    }

    /// Places a copy of a component with its centre on `point` in canvas
    /// coordinates, and returns the new layer's id.
    ///
    /// With no group named, the copy lands on the frame it was dropped on, the
    /// same rule a shape drawn there follows — otherwise dropping a button on a
    /// phone screen would leave the button floating above the screen and moving
    /// the screen would leave it behind.
    @discardableResult
    public mutating func insertComponentInstance(of componentID: UUID, at point: CGPoint,
                                                 intoGroup group: UUID? = nil) -> UUID? {
        guard let main = mainComponent(componentID: componentID) else { return nil }
        if let group { guard canInsertInstance(of: componentID, intoGroup: group) else { return nil } }
        let box = main.localBounds
        // The copy's own anchor sits where the original's does relative to what
        // it holds, so the two draw identically; then the whole thing is moved
        // so its box is centred on the drop.
        let anchor = CGPoint(x: point.x - box.midX + main.frame.origin.x,
                             y: point.y - box.midY + main.frame.origin.y)
        var copy = Layer(name: main.name,
                         content: .group(GroupContent(children: [], isFrame: main.isFrame,
                                                      clipsContents: main.group?.clipsContents ?? true,
                                                      backgroundHex: main.group?.backgroundHex,
                                                      instanceOf: componentID)),
                         frame: CGRect(origin: anchor, size: main.frame.size))
        // A copy takes the original's look at the moment it is placed; where it
        // sits, whether it is hidden and what it is called are its own.
        copy.style = main.style
        // A copy arrives answering nothing: it shows exactly what the original
        // shows, and the knobs are there to be turned afterwards.
        copy.children = resolvedChildren(of: componentID, instance: copy.id,
                                         overrides: [], stack: [])

        if let group {
            let origin = canvasBounds(of: group)?.origin ?? .zero
            copy.frame = copy.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            guard addLayer(copy, toGroup: group) else { return nil }
            return copy.id
        }
        // Dropping onto a frame that the copy may not join leaves it loose on
        // the canvas rather than refusing the drop outright.
        let host = frameID(under: point)
        if let host, !canInsertInstance(of: componentID, intoGroup: host) {
            addLayer(copy)
        } else {
            addLayerDrawnOnFrame(copy)
        }
        return copy.id
    }

    /// The contents a copy should be holding: the original's, with every id
    /// derived from this copy so two layers never share one, and with any copy
    /// found inside filled in the same way.
    private func resolvedChildren(of componentID: UUID, instance: UUID,
                                  overrides: [ComponentOverride], stack: [UUID]) -> [Layer] {
        guard stack.count < Self.componentNestingLimit, !stack.contains(componentID),
              let main = mainComponent(componentID: componentID) else { return [] }
        var children = main.children.map { rebound($0, instance: instance, stack: stack + [componentID]) }
        // The original's picture first, then the few facts this copy owns
        // written over the top. That order is what lets an edit to the original
        // still reach a copy that has overridden something else.
        applyOverrides(overrides, of: componentID, to: &children, instance: instance)
        return children
    }

    /// Whether two subtrees differ in anything a person could see.
    ///
    /// Ids inside a copy are derived from the copy, so re-minting the copy's
    /// own id — which is what duplicating it does — re-mints every id under it
    /// without one pixel moving. Comparing on ids would call that an update and
    /// put a notice on screen about nothing.
    static func differsBeyondIdentity(_ a: [Layer], _ b: [Layer]) -> Bool {
        guard a.count == b.count else { return true }
        return !zip(a, b).allSatisfy(sameIgnoringIdentity)
    }

    private static func sameIgnoringIdentity(_ a: Layer, _ b: Layer) -> Bool {
        guard a.name == b.name, a.frame == b.frame, a.crop == b.crop,
              a.transform == b.transform, a.style == b.style,
              a.isVisible == b.isVisible, a.isLocked == b.isLocked else { return false }
        guard let ga = a.group else { return b.group == nil && a.content == b.content }
        guard let gb = b.group, ga.isFrame == gb.isFrame, ga.clipsContents == gb.clipsContents,
              ga.backgroundHex == gb.backgroundHex, ga.componentID == gb.componentID,
              ga.instanceOf == gb.instanceOf, ga.properties == gb.properties,
              ga.overrides == gb.overrides else { return false }
        return !differsBeyondIdentity(ga.children, gb.children)
    }

    /// One piece of an original, as it appears inside a copy.
    private func rebound(_ layer: Layer, instance: UUID, stack: [UUID]) -> Layer {
        let id = ComponentIdentity.derived(instance: instance, source: layer.id)
        var copy = Layer(id: id, name: layer.name, content: layer.content, frame: layer.frame,
                         crop: layer.crop, transform: layer.transform, style: layer.style,
                         isVisible: layer.isVisible, isLocked: layer.isLocked)
        if let nested = layer.instanceOf {
            copy.children = resolvedChildren(of: nested, instance: id,
                                             overrides: layer.componentOverrides, stack: stack)
        } else if layer.isGroup {
            copy.children = layer.children.map { rebound($0, instance: instance, stack: stack) }
        }
        return copy
    }

    /// Puts every copy back in step with its original, and says how many
    /// followed. Runs after every edit (`History.perform`), so no command has
    /// to remember to call it and no copy can drift.
    ///
    /// A copy whose original is gone is not emptied: it keeps exactly what it
    /// was drawing and becomes an ordinary group. Deleting an original must
    /// never delete the work built out of it.
    @discardableResult
    public mutating func syncComponentInstances() -> ComponentSyncReport {
        // A knob whose layer was deleted out of the original is a knob nothing
        // will ever read, so it goes in the same step the layer did.
        if holdsComponentKnob { pruneComponentProperties() }
        guard holdsComponentInstance else { return ComponentSyncReport() }
        var report = ComponentSyncReport()
        let snapshot = self

        func rewrite(_ list: [Layer], stack: [UUID]) -> [Layer] {
            list.map { layer in
                var copy = layer
                if let componentID = layer.instanceOf {
                    guard let main = snapshot.mainComponent(componentID: componentID),
                          !stack.contains(componentID) else {
                        // The original is gone (or would loop): let go of the
                        // link and keep the picture.
                        var group = copy.group ?? GroupContent()
                        group.instanceOf = nil
                        group.overrides = []
                        group.children = copy.children
                        copy.content = .group(group)
                        return copy
                    }
                    var group = copy.group ?? GroupContent()
                    group.isFrame = main.isFrame
                    group.clipsContents = main.group?.clipsContents ?? true
                    group.backgroundHex = main.group?.backgroundHex
                    group.children = snapshot.resolvedChildren(of: componentID, instance: layer.id,
                                                               overrides: group.overrides,
                                                               stack: stack)
                    copy.content = .group(group)
                    if main.isFrame { copy.frame.size = main.frame.size }
                    if Self.differsBeyondIdentity(copy.children, layer.children) {
                        report.updatedInstances += 1
                        report.componentIDs.insert(componentID)
                    }
                    return copy
                }
                if layer.isGroup {
                    let inner = layer.componentID.map { stack + [$0] } ?? stack
                    copy.children = rewrite(layer.children, stack: inner)
                }
                return copy
            }
        }
        layers = rewrite(layers, stack: [])
        return report
    }
}

// MARK: - What the shelf says

extension ComponentNaming {
    /// The detail line on a component's tile: what it is, or how many copies of
    /// it are out, which is the question a shelf full of components raises.
    public static func detail(instanceCount: Int) -> String {
        switch instanceCount {
        case 0: return mainDetail
        case 1: return "1 copy"
        default: return "\(instanceCount) copies"
        }
    }
}
