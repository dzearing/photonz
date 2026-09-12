import CoreGraphics
import Foundation

/// One shelf the whole app shares (the decision "A component you build is only
/// in the document you built it in", answered 2026-09-09 with "One shelf the
/// whole app shares").
///
/// Until now a component belonged to one document: build a button, a card and
/// a nav bar for one screen, start a second file tomorrow, and none of them are
/// there. The starter set was the one exception, and this is built on exactly
/// the machinery that makes the starters work rather than beside it:
///
/// - **A shared component's id IS its component id**, so a document saved today
///   opens tomorrow still pointing at it, one shelf tile covers the untaken and
///   the taken case, and a second drop places a copy rather than a second
///   original.
/// - **The drawing is data, not a reference.** A document that uses a shared
///   component keeps a complete original of its own, marked as following the
///   shelf. So everything that walks a tree — the renderer, hit testing, export,
///   the package writer — sees an ordinary component and needs to know nothing
///   about the shelf at all, and a document handed to somebody else still draws
///   even though the shelf did not travel with it.
/// - **They paint from named styles**, and those travel with them, so a button
///   that was Accent blue where it was made is this document's Accent here.
///
/// The shelf is the truth about what the component LOOKS like; each document is
/// the truth about where it sits. Editing the original in any document
/// publishes the drawing; every other document takes it on the next look.

// MARK: - What a shared component IS

/// One component as it lives outside any document.
///
/// The drawing travels with its corner at zero, because where a component sits
/// is each document's own business, and every version of it travels, because a
/// version is another drawing of the same thing and a shelf that dropped them
/// would have lost the point of them.
public struct SharedComponent: Codable, Hashable, Sendable, Identifiable {
    /// The component id, the same in every document that uses it.
    public let id: UUID
    /// What it is called. The same name the layer, the badge and the tile wear.
    public var name: String
    /// Every version of it, first version first, each with its corner at zero.
    public var drawings: [Layer]
    /// The named colors the drawings paint from, so a document that has never
    /// seen them gets them along with the component.
    public var colorStyles: [ColorStyle]
    /// ...and the named text treatments.
    public var textStyles: [TextStyle]
    /// ...and the named effects.
    public var effectStyles: [EffectStyle]

    public init(id: UUID, name: String, drawings: [Layer],
                colorStyles: [ColorStyle] = [], textStyles: [TextStyle] = [],
                effectStyles: [EffectStyle] = []) {
        self.id = id
        self.name = name
        self.drawings = drawings
        self.colorStyles = colorStyles
        self.textStyles = textStyles
        self.effectStyles = effectStyles
    }
}

/// Everything on the shared shelf.
///
/// A plain ordered list rather than a dictionary: the shelf is read far more
/// often than it is written, it is small by nature (a kit, not a database), and
/// the order things were put on it is the order the tiles read in.
public struct SharedComponentShelf: Codable, Hashable, Sendable {
    /// What a tile on the shared shelf writes under its picture, the way a
    /// starter's says "starter".
    public static let shelfDetail = "shared"

    public private(set) var components: [SharedComponent]

    public init(_ components: [SharedComponent] = []) {
        self.components = components
    }

    public var isEmpty: Bool { components.isEmpty }

    public func component(id: UUID) -> SharedComponent? {
        components.first { $0.id == id }
    }

    /// Puts a component on the shelf, replacing the one already there IN PLACE
    /// so a tile never jumps to the end of the shelf because somebody edited it.
    public mutating func put(_ component: SharedComponent) {
        if let index = components.firstIndex(where: { $0.id == component.id }) {
            components[index] = component
        } else {
            components.append(component)
        }
    }

    public mutating func remove(id: UUID) {
        components.removeAll { $0.id == id }
    }

    /// What the Library's Components scope shows for the shelf: one tile per
    /// shared component.
    public var entries: [LibraryEntry] {
        components.map {
            LibraryEntry(id: $0.id.uuidString, scope: .components, name: $0.name,
                         detail: SharedComponentShelf.shelfDetail)
        }
    }

    /// The same, minus anything this document already holds an original of.
    /// One tile per component, whether it came from the shelf or from your own
    /// hands — exactly the rule the starters already follow.
    public func entries(notIn document: PhotonzDocument) -> [LibraryEntry] {
        let taken = Set(document.mainComponents.compactMap(\.componentID))
        return components
            .filter { !taken.contains($0.id) }
            .map { LibraryEntry(id: $0.id.uuidString, scope: .components, name: $0.name,
                                detail: SharedComponentShelf.shelfDetail) }
    }
}

/// What one look at the shelf did to a document.
public struct SharedComponentSyncReport: Hashable, Sendable {
    /// How many shared components took a newer drawing.
    public var updatedComponents: Int
    /// The names of the ones whose original is no longer on the shelf. Their
    /// drawings are untouched; what is gone is the link.
    public var missing: [String]

    public init(updatedComponents: Int = 0, missing: [String] = []) {
        self.updatedComponents = updatedComponents
        self.missing = missing
    }

    public var isEmpty: Bool { updatedComponents == 0 && missing.isEmpty }

    /// The break, said in the same words every other broken link uses
    /// (`LinkBreaks`). Empty when nothing broke.
    public var linkBreaks: LinkBreakReport {
        guard !missing.isEmpty else { return LinkBreakReport() }
        return LinkBreakReport(breaks: [LinkBreak(kind: .sharedOriginalMissing,
                                                  count: missing.count,
                                                  source: PhotonzDocument.sharedShelfName)])
    }
}

// MARK: - Reading one in a document

extension Layer {

    /// Whether this original follows the shared shelf: editing it publishes it,
    /// and an edit made to it in another document arrives here.
    public var isSharedComponent: Bool { group?.isShared == true }
}

extension PhotonzDocument {

    /// What the shelf is called in a sentence about it.
    public static let sharedShelfName = "the shared shelf"

    /// The components in this document that follow the shared shelf, in the
    /// order the tree holds them and each named once however many versions it
    /// has.
    public var sharedComponentIDs: [UUID] {
        var seen: Set<UUID> = []
        return mainComponents.compactMap { layer in
            guard layer.isSharedComponent, let id = layer.componentID,
                  seen.insert(id).inserted else { return nil }
            return id
        }
    }

    /// Whether this document follows the shelf at all. Checked before every
    /// sync, so a document that has never used a shared component pays one walk
    /// of the tree and no allocation.
    public var followsSharedComponents: Bool {
        mainComponents.contains { $0.isSharedComponent }
    }

    /// This document's component as the shelf would hold it: every version of
    /// its drawing with its corner at zero, and the named styles it paints
    /// from. Nil for a component that is not in this document.
    public func sharedComponent(componentID: UUID) -> SharedComponent? {
        let versions = componentVersions(of: componentID)
        guard let first = versions.first, let main = layer(id: first.layerID) else { return nil }
        var drawings: [Layer] = []
        for version in versions {
            guard var drawing = layer(id: version.layerID) else { continue }
            drawing.frame.origin = .zero
            drawings.append(drawing)
        }
        let used = styleIDs(in: drawings)
        return SharedComponent(
            id: componentID, name: main.name, drawings: drawings,
            colorStyles: colorStyles.filter { used.color.contains($0.id) },
            textStyles: textStyles.filter { used.text.contains($0.id) },
            effectStyles: effectStyles.filter { used.effect.contains($0.id) })
    }

    /// Every named style the drawings claim to be wearing.
    private func styleIDs(in drawings: [Layer]) -> (color: Set<UUID>, text: Set<UUID>,
                                                    effect: Set<UUID>) {
        var color: Set<UUID> = []
        var text: Set<UUID> = []
        var effect: Set<UUID> = []
        for drawing in drawings {
            for layer in drawing.selfAndDescendants {
                for binding in layer.colorStyleBindings ?? [] { color.insert(binding.styleID) }
                if let id = layer.textStyleID { text.insert(id) }
                for binding in layer.effectStyleBindings ?? [] { effect.insert(binding.styleID) }
            }
        }
        return (color, text, effect)
    }

    // MARK: - Putting one on the shelf and taking it off

    /// Puts a component on the shared shelf, and hands back what the shelf
    /// should hold. Every version of it is marked, because they are drawings of
    /// one component and it is the component that is shared.
    @discardableResult
    public mutating func shareComponent(componentID: UUID) -> SharedComponent? {
        guard mainComponent(componentID: componentID) != nil else { return nil }
        setShared(true, componentID: componentID)
        return sharedComponent(componentID: componentID)
    }

    /// Takes it off: this document keeps the drawing exactly as it is and stops
    /// following. Nothing is deleted and no copy notices.
    public mutating func unshareComponent(componentID: UUID) {
        setShared(false, componentID: componentID)
    }

    private mutating func setShared(_ shared: Bool, componentID: UUID) {
        for version in componentVersions(of: componentID) {
            updateLayer(id: version.layerID) { layer in
                guard var group = layer.group, group.isShared != shared else { return }
                group.isShared = shared
                layer.content = .group(group)
            }
        }
    }

    // MARK: - Taking one off the shelf

    /// Puts a shared component in the picture, centred on a canvas point.
    ///
    /// The first drop brings the ORIGINAL in, along with the named styles it
    /// paints from and every version of it, and from then on it is an ordinary
    /// component of this document that happens to follow the shelf. Every drop
    /// after that places a copy, exactly as the shelf does for a starter, so
    /// there is never a second original claiming the name.
    @discardableResult
    public mutating func adoptSharedComponent(_ shared: SharedComponent, at point: CGPoint,
                                              inside context: UUID? = nil) -> UUID? {
        if mainComponent(componentID: shared.id) != nil {
            return insertComponentInstance(of: shared.id, at: point, inside: context)
        }
        guard var main = shared.drawings.first else { return nil }
        adoptSharedStyles(shared)
        let box = main.localBounds
        main.frame.origin = CGPoint(x: (point.x - box.width / 2).rounded(),
                                    y: (point.y - box.height / 2).rounded())
        if !main.isFrame, let host = dropHostID(under: point, inside: context),
           canDropNewLayer(intoGroup: host) {
            let corner = childOrigin(of: host) ?? .zero
            main.frame = main.frame.offsetBy(dx: -corner.x, dy: -corner.y)
            // A row decides the order of what it holds, so where along it you
            // let go is where the component goes (`dropSlot`).
            var index: Int?
            if let slot = dropSlot(inGroup: host, at: point) {
                let inner = main.contentBounds
                main.frame = main.frame.offsetBy(dx: slot.origin.x - inner.minX,
                                                 dy: slot.origin.y - inner.minY)
                index = slot.index
            }
            guard addLayer(main, toGroup: host, at: index) else { return nil }
        } else {
            addLayerDrawnOnFrame(main)
        }
        // The other versions land loose beside the first, the way adding a
        // version does, rather than dropping strays into whatever it landed in.
        placeExtraVersions(of: shared, beside: main.id)
        repaintFromLocalStyles(shared)
        return main.id
    }

    /// The versions after the first, each somewhere clear on the canvas.
    private mutating func placeExtraVersions(of shared: SharedComponent, beside firstID: UUID) {
        for drawing in shared.drawings.dropFirst() {
            guard let anchor = layer(id: firstID) else { continue }
            let parent = parentOrigin(of: firstID) ?? .zero
            let anchorBox = anchor.localBounds.offsetBy(dx: parent.x, dy: parent.y)
            var version = drawing
            let landing = roomForDrawing(size: version.localBounds.size, beside: anchorBox)
            let box = version.localBounds
            version.frame.origin = CGPoint(x: landing.x - box.minX, y: landing.y - box.minY)
            addLayer(version)
        }
    }

    // MARK: - Following the shelf

    /// Puts every shared component in this document back in step with the
    /// shelf, and says what that did.
    ///
    /// This is what runs when a document is opened and whenever the shelf
    /// changes under an open one. A component whose original is no longer on
    /// the shelf is LEFT ALONE and reported: the drawing is the document's,
    /// what is gone is the link, and losing the picture because a file was
    /// tidied away would be the worst answer of the three.
    @discardableResult
    public mutating func syncSharedComponents(from shelf: SharedComponentShelf)
        -> SharedComponentSyncReport {
        guard followsSharedComponents else { return SharedComponentSyncReport() }
        var updated = 0
        var missing: [String] = []
        for componentID in sharedComponentIDs {
            guard let shared = shelf.component(id: componentID) else {
                missing.append(mainComponent(componentID: componentID)?.name
                                ?? PhotonzDocument.componentNameBase)
                continue
            }
            if refill(from: shared) { updated += 1 }
        }
        return SharedComponentSyncReport(updatedComponents: updated, missing: missing)
    }

    /// This document's original rewritten from the shelf's, version by version.
    /// Returns whether anything actually changed, so a look at an unchanged
    /// shelf records nothing.
    private mutating func refill(from shared: SharedComponent) -> Bool {
        var changed = adoptSharedStyles(shared)
        var seen: Set<UUID> = []
        var anchorID: UUID?
        for drawing in shared.drawings {
            let key = drawing.group?.versionID
            guard let local = mainComponent(componentID: shared.id, version: key),
                  key == nil || local.componentVersionID == key else {
                // A version that appeared on the shelf since this document last
                // looked: it lands loose beside the first, the way adding one
                // by hand does.
                if let anchorID { placeVersion(drawing, beside: anchorID) }
                changed = true
                continue
            }
            if anchorID == nil { anchorID = local.id }
            seen.insert(local.id)
            let before = local
            // The whole drawing, ids and all, so refilling twice from the same
            // shelf produces exactly the same document and an unchanged shelf
            // records no edit. Only where it SITS is kept, because that is the
            // one thing about it this document decides.
            updateLayer(id: local.id) { layer in
                let origin = layer.frame.origin
                layer = drawing
                layer.frame.origin = origin
            }
            if layer(id: local.id) != before { changed = true }
        }
        // ...and a version somebody deleted on the shelf goes here too. The
        // copies showing it are put on one that still exists by the sync that
        // runs after every edit, which already knows how to do that.
        for version in componentVersions(of: shared.id) where !seen.contains(version.layerID) {
            removeLayer(id: version.layerID)
            changed = true
        }
        if changed { repaintFromLocalStyles(shared) }
        return changed
    }

    private mutating func placeVersion(_ drawing: Layer, beside anchorID: UUID) {
        guard let anchor = layer(id: anchorID) else { return }
        let parent = parentOrigin(of: anchorID) ?? .zero
        let anchorBox = anchor.localBounds.offsetBy(dx: parent.x, dy: parent.y)
        var version = drawing
        let landing = roomForDrawing(size: version.localBounds.size, beside: anchorBox)
        let box = version.localBounds
        version.frame.origin = CGPoint(x: landing.x - box.minX, y: landing.y - box.minY)
        addLayer(version)
    }

    // MARK: - The styles it paints from

    /// The named styles a shared component wears, brought into this document.
    ///
    /// Matched by id and by id alone. A style this document already has WINS,
    /// however it is painted, which is what makes a shared button arrive in
    /// this document's Accent rather than dragging somebody else's blue in
    /// behind it. Returns whether anything was added.
    @discardableResult
    private mutating func adoptSharedStyles(_ shared: SharedComponent) -> Bool {
        var added = false
        for style in shared.colorStyles where colorStyle(id: style.id) == nil {
            colorStyles.append(style)
            added = true
        }
        for style in shared.textStyles where textStyle(id: style.id) == nil {
            textStyles.append(style)
            added = true
        }
        for style in shared.effectStyles where effectStyle(id: style.id) == nil {
            effectStyles.append(style)
            added = true
        }
        return added
    }

    /// Repaints whatever the arriving drawing says it is wearing from THIS
    /// document's copy of that style, so the name on a piece is true of the
    /// color on it. Without this a button that was blue where it was made
    /// arrives blue in a document whose Accent is red, and the first edit
    /// anywhere quietly breaks the link to hold the claim honest.
    private mutating func repaintFromLocalStyles(_ shared: SharedComponent) {
        for style in shared.colorStyles {
            guard let mine = colorStyle(id: style.id) else { continue }
            setColorStylePaint(styleID: mine.id, paint: mine.paint)
        }
        for style in shared.textStyles {
            guard let mine = textStyle(id: style.id) else { continue }
            setTextStyle(styleID: mine.id, treatment: mine.treatment)
        }
        for style in shared.effectStyles {
            guard let mine = effectStyle(id: style.id) else { continue }
            setEffectStyle(styleID: mine.id, effect: mine.effect)
        }
    }
}

// MARK: - What one edit should publish

extension PhotonzDocument {

    /// The shared components whose drawing differs between two versions of this
    /// document: what an edit that just landed should publish to the shelf.
    ///
    /// Only components that were ALREADY shared before the edit are considered,
    /// so a component arriving off the shelf never publishes itself straight
    /// back, and only ones that really changed are named, so moving a shared
    /// button across the canvas publishes nothing.
    public static func sharedComponentsToPublish(from before: PhotonzDocument,
                                                 to after: PhotonzDocument) -> [SharedComponent] {
        guard after.followsSharedComponents else { return [] }
        let was = Set(before.sharedComponentIDs)
        return after.sharedComponentIDs.compactMap { id in
            guard was.contains(id), let now = after.sharedComponent(componentID: id) else {
                return nil
            }
            guard before.sharedComponent(componentID: id) != now else { return nil }
            return now
        }
    }
}
