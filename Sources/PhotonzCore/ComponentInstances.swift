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
    /// How many copies were showing a version that has since been deleted, and
    /// were put back on one their component still has. Nothing else on screen
    /// says so: the copy simply draws something else the next time you look.
    public var strandedInstances: Int
    /// What those copies landed on, so the notice can name it.
    public var strandedOnVersion: String?

    public init(updatedInstances: Int = 0, componentIDs: Set<UUID> = [],
                strandedInstances: Int = 0, strandedOnVersion: String? = nil) {
        self.updatedInstances = updatedInstances
        self.componentIDs = componentIDs
        self.strandedInstances = strandedInstances
        self.strandedOnVersion = strandedOnVersion
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

/// What letting go of a component over a point on the canvas would do.
///
/// One answer with three shapes, so the outline the canvas draws mid-drag, the
/// frame it lights up, and the no-entry pointer all come from the same place as
/// the drop itself.
public enum ComponentDropTarget: Equatable, Sendable {
    /// Nothing would happen: the copy would end up inside itself.
    case refused
    /// It would join this container: the screen under the pointer, or the
    /// group you have stepped inside.
    case inside(UUID)
    /// It would land loose on the canvas.
    case canvas
}

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
            // Every version of it, not only the one this copy shows: a version
            // is a drawing of the same component, so a component that would
            // hold itself through any of them draws forever just the same.
            for version in componentVersions(of: referenced) {
                guard let main = self.layer(id: version.layerID) else { continue }
                used.formUnion(componentsUsed(by: main, depth: depth + 1))
            }
        }
        for child in layer.children { used.formUnion(componentsUsed(by: child, depth: depth + 1)) }
        return used
    }

    /// What letting go of a component over a canvas point would do.
    ///
    /// Asked while the drag is still in the air, so the canvas can draw the
    /// answer before the button comes up, and asked again by the drop itself,
    /// so the picture and what happens can never disagree.
    ///
    /// `context` is the group you have stepped INSIDE, so a piece let go on a
    /// bar or a card you are arranging joins it rather than landing beside it.
    public func componentDropTarget(of componentID: UUID, at point: CGPoint,
                                    inside context: UUID? = nil) -> ComponentDropTarget {
        // A starter is still the app's rather than the document's until it is
        // dropped, so there is no main to reason about: it arrives whole and
        // joins whatever container it lands on, the way a drawn shape does.
        let isArrivingStarter = mainComponent(componentID: componentID) == nil
            && StarterComponent(componentID: componentID) != nil
        guard isArrivingStarter || mainComponent(componentID: componentID) != nil else { return .refused }
        guard let host = dropHostID(under: point, inside: context) else { return .canvas }
        if isArrivingStarter { return canDropNewLayer(intoGroup: host) ? .inside(host) : .canvas }
        // A copy landing inside its own original would draw forever, so that
        // one drop is refused rather than quietly landed somewhere else.
        if encloses(componentID: componentID, at: host) { return .refused }
        return canInsertInstance(of: componentID, intoGroup: host) ? .inside(host) : .canvas
    }

    /// Whether a brand new layer — a starter arriving off the shelf, which has
    /// no original in this document yet — may go inside `group` (nil for the
    /// canvas). Nothing goes inside a COPY of a component: what is in there
    /// belongs to the original, so an edit made in it could not be kept. A
    /// component cannot hold ITSELF this way, because the thing arriving is
    /// not in the document at all yet.
    public func canDropNewLayer(intoGroup group: UUID?) -> Bool {
        guard let group else { return true }
        guard let target = layer(id: group), target.isOpenableGroup, !target.isLocked
        else { return false }
        return !isInsideCopy(group)
    }

    /// The box a dropped copy would fill, so the canvas can outline where it
    /// is going at the size it will actually be. Nil for an id that is not a
    /// component at all.
    ///
    /// `version` says which drawing, for a component that holds more than one:
    /// versions may differ in size, so the outline in the air has to be the
    /// size of the one being placed.
    public func componentDropSize(
        of componentID: UUID, version: UUID? = nil,
        measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize
    ) -> CGSize? {
        if let main = mainComponent(componentID: componentID, version: version) {
            return main.localBounds.size
        }
        guard let starter = StarterComponent(componentID: componentID) else { return nil }
        return StarterComponents.layer(starter, scale: max(pixelScale, 1),
                                       measure: measure).localBounds.size
    }

}

/// Where a piece let go over the canvas would end up.
public struct ComponentDropLanding: Equatable, Sendable {
    /// The box the piece would fill, where it would actually come to rest.
    public var rect: CGRect
    /// The group it would join, nil out on the bare canvas.
    public var host: UUID?
    /// Where among that group's own contents it would sit, for a container
    /// that decides the order of what it holds. Nil where the order is not the
    /// container's to decide, and the piece stays where it was let go.
    public var index: Int?
    /// The box that group would have with the room held open: bigger than the
    /// one it has now whenever a row has to grow to take the piece. Nil where
    /// nothing about the group changes.
    public var hostBox: CGRect?

    public init(rect: CGRect, host: UUID? = nil, index: Int? = nil, hostBox: CGRect? = nil) {
        self.rect = rect
        self.host = host
        self.index = index
        self.hostBox = hostBox
    }
}

extension PhotonzDocument {

    /// Where a dropped piece would actually END UP, and what it would join.
    ///
    /// For a container that arranges nothing that is the box under the pointer,
    /// which is what the canvas has always drawn. A row or a stack packs its
    /// contents from its own edge, so a piece let go over the right-hand half
    /// of a bar lands over on the left with the rest: drawing the box under the
    /// pointer would promise somewhere the piece is not going. This asks the
    /// flow the same question the drop is about to ask it, so the outline in
    /// the air is where the piece lands.
    ///
    /// `index` says WHERE among the host's contents it would go, for a
    /// container that decides the order of what it holds. Nil out on the canvas
    /// and inside a group that arranges nothing: order is not theirs to decide
    /// there, so a piece simply stays where it was let go.
    ///
    /// Nil where the drop would be refused, and where the id is not a component
    /// at all.
    public func componentDropLanding(
        of componentID: UUID, at point: CGPoint, inside context: UUID? = nil,
        version: UUID? = nil,
        measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize
    ) -> ComponentDropLanding? {
        let target = componentDropTarget(of: componentID, at: point, inside: context)
        guard target != .refused,
              let size = componentDropSize(of: componentID, version: version, measure: measure)
        else { return nil }
        let loose = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                           width: size.width, height: size.height)
        guard case .inside(let host) = target else { return ComponentDropLanding(rect: loose) }
        guard let group = layer(id: host), let slot = dropSlot(inGroup: host, at: point),
              let corner = childOrigin(of: host) else {
            return ComponentDropLanding(rect: loose, host: host)
        }
        // The stand-in put through the very flow the drop will run, in the very
        // slot the drop will use, so the box drawn in the air is the gap the
        // piece is going to take, and the group is the size it will be once it
        // has taken it.
        var probe = group
        probe.children.insert(standIn(size: size, at: slot.origin), at: slot.index)
        let opened = GroupFlow.flowing(probe)
        return ComponentDropLanding(
            rect: opened.children[slot.index].frame.offsetBy(dx: corner.x, dy: corner.y),
            host: host, index: slot.index,
            hostBox: opened.localBounds.offsetBy(dx: corner.x - group.frame.origin.x,
                                                 dy: corner.y - group.frame.origin.y))
    }

    /// This document with the room a drop would take HELD OPEN: everything
    /// where it is, plus an empty space the size of the piece in the air, in
    /// the slot the pointer is asking for. The pieces either side move along to
    /// make it, so the box drawn in the air sits in a gap that is really there
    /// rather than on top of the neighbour it is about to displace.
    ///
    /// Nothing is added to the picture: the room draws nothing and is thrown
    /// away the moment the drag ends. Nil where nothing has to move — out on
    /// the canvas, and inside a group that arranges nothing, a piece lands
    /// where you let go and its neighbours never knew.
    public func holdingRoomForComponentDrop(
        of componentID: UUID, at point: CGPoint, inside context: UUID? = nil,
        version: UUID? = nil,
        measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize
    ) -> PhotonzDocument? {
        guard case .inside(let host) = componentDropTarget(of: componentID, at: point,
                                                           inside: context),
              let size = componentDropSize(of: componentID, version: version, measure: measure),
              let slot = dropSlot(inGroup: host, at: point) else { return nil }
        var room = standIn(size: size, at: slot.origin)
        room.style.opacity = 0
        var out = self
        guard out.addLayer(room, toGroup: host, at: slot.index) else { return nil }
        out.reflowLayouts()
        return out
    }

    /// Where a piece let go at `point` would sit among an arranging group's own
    /// contents, and the corner it has to take to be READ into that slot.
    ///
    /// A stack orders what it holds by where things ARE rather than by the
    /// order they are stored in, so an index on its own would not stick. The
    /// piece arrives at the very corner of the piece it is to follow, and the
    /// flow's tie-break — first in the contents wins — puts it in the gap after
    /// it. At the head of the row it takes the first piece's corner and is
    /// stored just before it, which reads the same way round.
    ///
    /// Nil for a group that arranges nothing.
    func dropSlot(inGroup host: UUID, at point: CGPoint) -> (index: Int, origin: CGPoint)? {
        guard let group = layer(id: host), let layout = group.group?.layout, layout.arranges,
              let corner = childOrigin(of: host) else { return nil }
        let items = GroupFlow.arrangedItems(of: group)
        guard let first = items.first else { return (group.children.count, .zero) }
        let local = CGPoint(x: point.x - corner.x, y: point.y - corner.y)
        let slot = GroupFlow.slot(at: local, among: items, layout: layout)
        guard slot > 0 else { return (first.index, first.box.origin) }
        let after = items[slot - 1]
        return (after.index + 1, after.box.origin)
    }

    /// A piece of nothing the size of what is being dropped, at a corner in the
    /// group's own space. A plain box rather than an empty group: the flow
    /// measures what a piece SHOWS, and an empty group shows nothing, so the
    /// row would pack a piece of no size at all.
    private func standIn(size: CGSize, at origin: CGPoint) -> Layer {
        Layer(name: "",
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: size.width,
                                                                  y: size.height))),
              frame: CGRect(origin: origin, size: size))
    }

    /// Whether the drop target sits inside the component being placed, walking
    /// out from the target to the canvas.
    func encloses(componentID: UUID, at host: UUID) -> Bool {
        var current: UUID? = host
        while let id = current {
            if layer(id: id)?.componentID == componentID { return true }
            current = parentID(of: id)
        }
        return false
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

    /// Whether a whole subtree may be moved inside `group` (nil for the
    /// canvas) without a component ending up holding itself.
    ///
    /// `canInsertInstance` asks this about a copy that does not exist yet;
    /// this asks it about a layer already on the canvas, which is what dragging
    /// one onto a screen needs. Same two refusals: nothing goes inside a COPY
    /// of a component, because a copy shows its original's pieces and an edit
    /// made there could not be kept, and nothing goes anywhere that would put a
    /// component inside itself, directly or through anything it already holds —
    /// such a thing has no size and no picture, it just draws forever.
    public func canMoveSubtree(_ id: UUID, intoGroup group: UUID?) -> Bool {
        guard let moved = layer(id: id) else { return false }
        guard let group else { return true }
        guard let target = layer(id: group), target.isOpenableGroup, !target.isLocked else { return false }
        // Every component this move would land inside, including the target.
        var enclosing: Set<UUID> = []
        var current: UUID? = group
        while let this = current {
            guard let here = layer(id: this) else { break }
            if here.isComponentInstance { return false }
            if let component = here.componentID { enclosing.insert(component) }
            current = parentID(of: this)
        }
        guard !enclosing.isEmpty else { return true }
        // ...against every component the moved subtree IS or RELIES ON.
        var carried = componentsUsed(by: moved)
        for layer in moved.selfAndDescendants {
            if let component = layer.componentID { carried.insert(component) }
        }
        return enclosing.isDisjoint(with: carried)
    }

    /// Places a copy of a component with its centre on `point` in canvas
    /// coordinates, and returns the new layer's id.
    ///
    /// The copy lands in whatever the drop point is inside: the screen it was
    /// dropped on, the same rule a shape drawn there follows — otherwise
    /// dropping a button on a phone screen would leave the button floating
    /// above the screen and moving the screen would leave it behind — or the
    /// group named by `context`, which is the one you have stepped inside.
    ///
    /// `version` is which drawing the copy arrives showing, for a component
    /// that holds more than one (`ComponentVersions`). Naming none is the
    /// component's first, which is what every copy used to be; naming one the
    /// component does not hold falls back to the first rather than refusing,
    /// so a stale choice still places something.
    @discardableResult
    public mutating func insertComponentInstance(of componentID: UUID, at point: CGPoint,
                                                 inside context: UUID? = nil,
                                                 version: UUID? = nil) -> UUID? {
        guard let main = mainComponent(componentID: componentID, version: version) else { return nil }
        // The one answer, asked once: the same call the canvas draws its
        // outline from, so what a drag in the air promised is what the drop
        // does. A copy that would land inside its own original draws forever,
        // so it is refused here rather than trusted not to be asked for.
        let target = componentDropTarget(of: componentID, at: point, inside: context)
        guard target != .refused else { return nil }
        let box = main.localBounds
        // The copy's own anchor sits where the original's does relative to what
        // it holds, so the two draw identically; then the whole thing is moved
        // so its box is centred on the drop.
        let anchor = CGPoint(x: point.x - box.midX + main.frame.origin.x,
                             y: point.y - box.midY + main.frame.origin.y)
        var content = GroupContent(children: [], isFrame: main.isFrame,
                                   clipsContents: main.group?.clipsContentsSetting,
                                   backgroundHex: main.group?.backgroundHex,
                                   instanceOf: componentID,
                                   followedStyle: main.style)
        // A copy of a component with versions says which one it is showing from
        // the moment it lands, so restacking the versions never changes what an
        // already placed copy draws.
        content.instanceVersion = main.componentVersionID
        // A copy arranges itself the way its original does. Without this a copy
        // of a stack is a loose heap that happens to look right until something
        // inside it changes size — which is exactly what a copy answering a
        // wording knob does.
        content.layout = main.group?.layout
        content.contentPlacement = main.group?.contentPlacement
        var copy = Layer(name: main.name, content: .group(content),
                         frame: CGRect(origin: anchor, size: main.frame.size))
        // A copy takes the original's look at the moment it is placed and keeps
        // following it part by part after that; where it sits, whether it is
        // hidden and what it is called are its own.
        copy.style = main.style
        // A copy arrives answering nothing: it shows exactly what the original
        // shows, and the knobs are there to be turned afterwards.
        copy.children = resolvedChildren(of: componentID, version: main.componentVersionID,
                                         instance: copy.id, overrides: [], stack: [])

        // A copy that is itself a SCREEN is never swallowed: a screen dropped on
        // a screen is a second screen, not one hidden inside the other.
        guard !copy.isFrame, case .inside(let host) = target else {
            addLayer(copy)
            return copy.id
        }
        let corner = childOrigin(of: host) ?? .zero
        copy.frame = copy.frame.offsetBy(dx: -corner.x, dy: -corner.y)
        // A row decides the ORDER of what it holds, so letting go halfway along
        // one says halfway along, not "on the end however far left you let go".
        var index: Int?
        if let slot = dropSlot(inGroup: host, at: point) {
            let box = copy.contentBounds
            copy.frame = copy.frame.offsetBy(dx: slot.origin.x - box.minX,
                                             dy: slot.origin.y - box.minY)
            index = slot.index
        }
        guard addLayer(copy, toGroup: host, at: index) else { return nil }
        return copy.id
    }

    /// The contents a copy should be holding: the original's, with every id
    /// derived from this copy so two layers never share one, and with any copy
    /// found inside filled in the same way.
    private func resolvedChildren(of componentID: UUID, version: UUID?, instance: UUID,
                                  overrides: [ComponentOverride], stack: [UUID]) -> [Layer] {
        guard stack.count < Self.componentNestingLimit, !stack.contains(componentID),
              let main = mainComponent(componentID: componentID, version: version) else { return [] }
        var children = main.children.map { rebound($0, instance: instance, stack: stack + [componentID]) }
        // The original's picture first, then the few facts this copy owns
        // written over the top. That order is what lets an edit to the original
        // still reach a copy that has overridden something else.
        applyOverrides(overrides, of: componentID, version: version, to: &children,
                       instance: instance, contents: main.group?.contentPlacement)
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
        guard a.colorStyleBindings == b.colorStyleBindings, a.placement == b.placement,
              a.flowFill == b.flowFill else {
            return false
        }
        guard let ga = a.group else { return b.group == nil && a.content == b.content }
        guard let gb = b.group, ga.isFrame == gb.isFrame, ga.clipsContents == gb.clipsContents,
              ga.backgroundHex == gb.backgroundHex, ga.componentID == gb.componentID,
              ga.instanceOf == gb.instanceOf, ga.instanceVersion == gb.instanceVersion,
              ga.versionID == gb.versionID, ga.versionName == gb.versionName,
              ga.properties == gb.properties,
              ga.overrides == gb.overrides, ga.instanceSize == gb.instanceSize,
              ga.layout == gb.layout,
              ga.contentPlacement == gb.contentPlacement else { return false }
        return !differsBeyondIdentity(ga.children, gb.children)
    }

    /// One piece of an original, as it appears inside a copy.
    private func rebound(_ layer: Layer, instance: UUID, stack: [UUID]) -> Layer {
        let id = ComponentIdentity.derived(instance: instance, source: layer.id)
        var copy = Layer(id: id, name: layer.name, content: layer.content, frame: layer.frame,
                         crop: layer.crop, transform: layer.transform, style: layer.style,
                         isVisible: layer.isVisible, isLocked: layer.isLocked,
                         colorStyleBindings: layer.colorStyleBindings,
                         placement: layer.placement, flowFill: layer.flowFill)
        if let nested = layer.instanceOf {
            let version = layer.instanceVersionID
            copy.children = resolvedChildren(of: nested, version: version, instance: id,
                                             overrides: layer.componentOverrides, stack: stack)
            // A copy inside a component follows ITS original's look here as
            // well, rather than carrying whatever look it happened to be
            // holding when this pass started: the two are put in step in the
            // same sync, and which one runs first must not decide the answer.
            if let inner = mainComponent(componentID: nested, version: version), var group = copy.group {
                copy.style = LayerStyle.following(inner.style, own: layer.style,
                                                  lastSeen: group.followedStyle)
                group.followedStyle = inner.style
                // The room this nested copy was given for itself travels out
                // here too, rather than waiting for the pass that rewrites the
                // original it sits in: which of the two runs first must not
                // decide what a copy of the outer component shows.
                applyRootOverrides(layer.componentOverrides, of: nested, version: version,
                                   to: &group.layout)
                group.children = copy.children
                copy.content = .group(group)
            }
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
                    // The version this copy asked for, while its component
                    // still has it. A version somebody deleted leaves the copy
                    // on one that exists rather than on nothing at all, and is
                    // reported so the app can say so.
                    var version = layer.instanceVersionID
                    if let asked = version,
                       snapshot.componentVersion(of: componentID, id: asked) == nil {
                        version = nil
                        if snapshot.mainComponent(componentID: componentID) != nil {
                            report.strandedInstances += 1
                            report.strandedOnVersion = snapshot.componentVersions(of: componentID)
                                .first?.name
                        }
                    }
                    guard let main = snapshot.mainComponent(componentID: componentID,
                                                            version: version),
                          !stack.contains(componentID) else {
                        // The original is gone (or would loop): let go of the
                        // link and keep the picture.
                        var group = copy.group ?? GroupContent()
                        group.instanceOf = nil
                        group.instanceVersion = nil
                        group.overrides = []
                        group.followedStyle = nil
                        // The size it was wearing is already in its layout, so
                        // letting go of the record changes nothing on screen.
                        group.instanceSize = nil
                        group.children = copy.children
                        copy.content = .group(group)
                        return copy
                    }
                    var group = copy.group ?? GroupContent()
                    group.isFrame = main.isFrame
                    group.clipsContentsSetting = main.group?.clipsContentsSetting
                    group.backgroundHex = main.group?.backgroundHex
                    // How the original arranges its contents follows too, so a
                    // copy of a stack closes up around a row that changed size
                    // rather than leaving a hole where the row used to end.
                    // A side this copy was given for itself is written back
                    // over the top, which is the one thing about the box that
                    // is the copy's (`InstanceSizing`).
                    group.layout = InstanceSizing.layout(main: main, own: group.instanceSize)
                    // ...and then the room this copy was given for itself, if
                    // its original offers that as a knob. Last, so the copy's
                    // own answer stands over the original's.
                    snapshot.applyRootOverrides(group.overrides, of: componentID, version: version,
                                                to: &group.layout)
                    group.contentPlacement = main.group?.contentPlacement
                    // A copy left holding a version that is gone is put back on
                    // one that exists, in writing, so it stops asking.
                    group.instanceVersion = version
                    group.children = snapshot.resolvedChildren(of: componentID, version: version,
                                                               instance: layer.id,
                                                               overrides: group.overrides,
                                                               stack: stack)
                    // The look follows part by part: everything this copy has
                    // not set for itself comes from the original again, and the
                    // original's look is remembered so the next edit can tell
                    // the two apart.
                    copy.style = LayerStyle.following(main.style, own: layer.style,
                                                      lastSeen: group.followedStyle)
                    group.followedStyle = main.style
                    copy.content = .group(group)
                    if main.isFrame {
                        copy.frame.size = InstanceSizing.frameSize(main: main,
                                                                   own: group.instanceSize)
                    }
                    // The contents arrived laid out for the ORIGINAL's box, so
                    // a copy with a box of its own places them into it the way
                    // the original would have if it were that size.
                    if group.instanceSize?.isFollowing == false {
                        copy = InstanceSizing.fitted(copy, filling: main.localBounds.size)
                    }
                    // The layout counts as well as the contents: a copy given
                    // its own room has moved nothing yet, and the flow pass
                    // that moves its contents only runs again when the copy is
                    // reported as changed.
                    if Self.differsBeyondIdentity(copy.children, layer.children)
                        || copy.style != layer.style
                        || copy.group?.layout != layer.group?.layout {
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
    /// `ComponentVersions` adds the version count on top of this.
    public static func detail(instanceCount: Int) -> String {
        switch instanceCount {
        case 0: return mainDetail
        case 1: return "1 copy"
        default: return "\(instanceCount) copies"
        }
    }
}
