import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// What the layers list shows: its rows, its groups, its thumbnails, and what
// the dock promises a file held over it.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    /// Layers in panel order (visual index 0 = topmost).
    var panelLayers: [Layer] {
        (document?.layers ?? []).reversed()
    }

    func withoutRememberingOpenGroups(_ body: () -> Void) {
        isRestoringOpenGroups = true
        body()
        isRestoringOpenGroups = false
    }

    /// Where this window's open/shut record is filed: the file it is editing.
    /// Nil for a picture that has never been saved or opened from anywhere,
    /// which is simply not remembered — there is nothing to come back to.
    private var openGroupMemoryKey: String? {
        (documentURL ?? openedFileURL)?.standardizedFileURL.path
    }

    static let openGroupsKey = "layers.openGroups"

    private static func loadOpenGroupMemory() -> OpenGroupMemory {
        guard let data = UserDefaults.standard.data(forKey: openGroupsKey),
              let memory = try? JSONDecoder().decode(OpenGroupMemory.self, from: data)
        else { return OpenGroupMemory() }
        return memory
    }

    /// Files away which groups are open now, dropping any the document no
    /// longer has. Nothing is written when the record would be unchanged, so
    /// selecting your way around a picture is not a stream of writes.
    func rememberExpandedGroups() {
        // Only the release that HAS groups keeps a record of them, so nothing
        // about this reaches a release whose layers list is flat.
        guard Experiments.shared.layerGroupsEnabled else { return }
        guard let key = openGroupMemoryKey, let document else { return }
        var memory = Self.loadOpenGroupMemory()
        let before = memory
        memory.remember(expandedGroupIDs, for: key, stillInDocument: document.openableGroupIDs)
        guard memory != before, let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: Self.openGroupsKey)
    }

    /// Reopens the groups this file had open last time. Called once the file
    /// the window is editing is known, which for a picture opened from disk is
    /// after the document has been installed.
    func restoreExpandedGroups() {
        guard Experiments.shared.layerGroupsEnabled else { return }
        guard let key = openGroupMemoryKey, let document else { return }
        let remembered = Self.loadOpenGroupMemory()
            .openGroups(for: key, stillInDocument: document.openableGroupIDs)
        withoutRememberingOpenGroups { expandedGroupIDs.formUnion(remembered) }
        // Written straight back, so a group deleted while the file was closed
        // is gone from the record whether or not the list is ever touched.
        rememberExpandedGroups()
    }

    /// The rows the layers list draws, top down, with an open group's contents
    /// indented under it. With the groups flag off every group stays shut, so
    /// the list is the flat one it has always been.
    var panelRows: [LayerPanelRow] {
        document?.panelRows(expanded: Experiments.shared.layerGroupsEnabled ? expandedGroupIDs : [])
            ?? []
    }

    /// The same rows, each carrying what it draws — name, visibility, lock,
    /// whether it is selected, its component marks — from a single walk of the
    /// tree.
    ///
    /// The layers list reads THIS rather than holding ids and asking for each
    /// layer again while it draws: a lookup by id searches the whole document,
    /// so a hundred rows meant a hundred walks of a hundred layers on every
    /// click. It also makes each row a small value the list can compare, which
    /// is what lets an untouched row skip its redraw entirely.
    var layerRows: [LayerRowDisplay] {
        var selected = multiSelectedLayerIDs
        if let selectedLayerID { selected.insert(selectedLayerID) }
        return document?.layerRows(
            expanded: Experiments.shared.layerGroupsEnabled ? expandedGroupIDs : [],
            selected: selected,
            // Cutting off what does not fit is auto layout's doing, so the mark
            // that says a container has cut something off ships with it.
            marksOutOfView: Experiments.shared.autoLayoutEnabled) ?? []
    }

    /// The twist-open control on a group row.
    func toggleGroupExpanded(id: UUID) {
        if expandedGroupIDs.contains(id) { expandedGroupIDs.remove(id) } else { expandedGroupIDs.insert(id) }
    }

    /// Opens every group above a layer, so its row is on screen. Called
    /// whenever the selection changes, which is what keeps the canvas and the
    /// list saying the same thing.
    func revealInLayersList(_ id: UUID) {
        guard let document else { return }
        let ancestors = document.ancestorIDs(of: id)
        // Only a group that is not open yet is worth a write: the layers list
        // animates on this set, so an unchanged write is a re-layout for nothing.
        guard ancestors.contains(where: { !expandedGroupIDs.contains($0) }) else { return }
        expandedGroupIDs.formUnion(ancestors)
    }

    /// Whether a drag carrying `ids` can land here — what decides between a
    /// drop line and the no-entry cursor.
    func canDropRows(ids: Set<UUID>, _ drop: LayerDrop) -> Bool {
        guard let document else { return false }
        if case .inside = drop, !Experiments.shared.layerGroupsEnabled { return false }
        return document.canDrop(ids: ids, drop)
    }

    /// Where a drag hovering over a row would land, which is what the drop
    /// line draws. Nil means nothing can land here.
    func dropProposal(carrying ids: Set<UUID>, over row: LayerPanelRow,
                      pointerY: CGFloat, rowHeight: CGFloat) -> LayerDrop? {
        document?.dropProposal(carrying: ids, over: row, pointerY: pointerY, rowHeight: rowHeight,
                               allowsInside: Experiments.shared.layerGroupsEnabled)
    }

    // MARK: - What the right hand panel promises a file held over it

    /// What the panel is about to do with the thing being held over it, which
    /// is what its border and the line in the layers list draw. Nil when
    /// nothing is in the air over the panel.
    ///
    /// It lives here rather than in the panel because three different targets
    /// answer for the same surface — a section, a layer row, and the panel
    /// itself — and they have to speak with one voice.
    enum PanelDropOffer: Equatable {
        /// The panel will take it, and the picture will land here. The landing
        /// is nil only when there is no stack to land in, where the file opens
        /// a window of its own instead.
        case accepts(LayerDrop?)
        /// The panel cannot use what is being held over it.
        case refuses
    }

    /// Says what the panel will do with what is in the air. Called on every
    /// frame of a drag, so an unchanged answer writes nothing.
    func offerPanelDrop(_ offer: PanelDropOffer, from owner: AnyHashable) {
        panelDropOwner = owner
        guard panelDropOffer != offer else { return }
        panelDropOffer = offer
    }

    /// The thing in the air has left this target, or landed on it.
    func endPanelDrop(from owner: AnyHashable) {
        guard panelDropOwner == owner else { return }
        panelDropOwner = nil
        panelDropOffer = nil
    }

    /// The landing the panel is currently promising, which is what the drop
    /// line in the layers list draws.
    var panelDropLanding: LayerDrop? {
        guard case .accepts(let drop) = panelDropOffer else { return nil }
        return drop
    }

    /// Where a picture arriving from outside would land if it were let go over
    /// this row now.
    func incomingDropProposal(over row: LayerPanelRow, pointerY: CGFloat,
                              rowHeight: CGFloat) -> LayerDrop? {
        document?.incomingDropProposal(over: row, pointerY: pointerY, rowHeight: rowHeight,
                                       allowsInside: Experiments.shared.layerGroupsEnabled)
    }

    /// Where a picture let go on the panel, but not on any one row, lands.
    /// Not gated on the groups flag: a frame under the middle of the canvas
    /// swallows an incoming picture whatever that flag says, and the promise
    /// has to match what actually happens.
    var incomingDropOnTop: LayerDrop? { document?.incomingDropOnTop() }

    /// A finished drag in the layers list: one undo step, and the layers keep
    /// their place on the canvas.
    func dropRows(ids: Set<UUID>, _ drop: LayerDrop) {
        guard canDropRows(ids: ids, drop) else { return }
        discardDragPreview()
        var landed = false
        perform { landed = $0.dropLayers(ids: ids, drop) }
        guard landed else { return }
        // Dropping into a group opens it, so you can see where what you were
        // carrying went.
        if case .inside(let groupID) = drop { expandedGroupIDs.insert(groupID) }
        // What you just dragged is what you are now holding, so the inspector
        // and the canvas talk about the layer you acted on rather than
        // whatever happened to be selected before the drag.
        selectLayers(ids)
    }

    /// A layer's style, preview-aware so inspector sliders don't snap back
    /// mid-drag.
    func previewedStyle(of id: UUID) -> LayerStyle? {
        if let style = stylePreview?.styles[id] { return style }
        return document?.layer(id: id)?.style
    }

    /// Live inspector-slider update over every layer the row speaks for:
    /// renders the new style without touching history. The first preview of a
    /// gesture drops any held drag sprite (it shows the old style).
    func previewLayerStyle(ids: [UUID], _ mutate: (inout LayerStyle) -> Void) {
        guard !ids.isEmpty, var doc = document else { return }
        // A drag that has moved to a different row or a different selection is
        // a new gesture: nothing of the old one carries over.
        if stylePreview?.ids != ids {
            discardDragPreview()
            stylePreview = (ids, [:])
        }
        var styles = stylePreview?.styles ?? [:]
        for id in ids {
            guard var style = styles[id] ?? doc.layer(id: id)?.style else { continue }
            mutate(&style)
            styles[id] = style
            doc.updateLayer(id: id) { $0.style = style }
        }
        stylePreview = (ids, styles)
        submit(doc)
    }

    func previewLayerStyle(id: UUID, _ mutate: (inout LayerStyle) -> Void) {
        previewLayerStyle(ids: [id], mutate)
    }

    /// Slider release: ONE undo step from the pre-gesture styles to the last
    /// previewed ones, however many layers the drag reached (a no-change
    /// release is a History no-op).
    func commitLayerStyle(ids: [UUID]) {
        guard let preview = stylePreview, preview.ids == ids else { return }
        stylePreview = nil
        perform { doc in
            for (id, style) in preview.styles {
                doc.updateLayer(id: id) { $0.style = style }
            }
        }
        rememberStyleDefault(of: ids)
    }

    func commitLayerStyle(id: UUID) { commitLayerStyle(ids: [id]) }

    /// One-shot style edit (steppers, toggles, the shadow switch): a single
    /// undo step over the whole selection, no preview.
    func setLayerStyle(ids: [UUID], _ mutate: @escaping (inout LayerStyle) -> Void) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { doc in _ = doc.updateLayerStyles(layerIDs: ids, mutate) }
        rememberStyleDefault(of: ids)
    }

    func setLayerStyle(id: UUID, _ mutate: @escaping (inout LayerStyle) -> Void) {
        setLayerStyle(ids: [id], mutate)
    }

    /// The next rectangle you draw inherits the one you just styled — but only
    /// when you styled ONE. Over a selection the layers still differ in every
    /// field the drag did not touch, so there is no "the style you just made"
    /// to hand the tool, and picking one of them would hand it three fields
    /// nobody set.
    func rememberStyleDefault(of ids: [UUID]) {
        guard ids.count == 1, let only = ids.first else { return }
        captureStyleDefault(layerID: only)
    }

    /// Remember a styled layer's effects as its TOOL's default, so the next
    /// object of that kind inherits them — per shape for annotations, and for the
    /// measure tool as a whole.
    private func captureStyleDefault(layerID: UUID) {
        guard let layer = document?.layer(id: layerID) else { return }
        if let shape = layer.annotation?.shape {
            annotationStyles.setLayerStyle(layer.style, forShape: shape)
            saveAnnotationStyles()
        } else if layer.measure != nil {
            updateMeasureStyles { $0.layerStyle = layer.style }
        }
    }

    func toggleLayerVisibility(id: UUID) {
        discardDragPreview()
        // Toggling a member of the multi-selection drives the WHOLE selection
        // to the clicked layer's new state, in one undo step.
        if multiSelectedLayerIDs.contains(id) {
            let show = !(document?.layer(id: id)?.isVisible ?? true)
            let ids = multiSelectedLayerIDs
            perform { doc in
                for layerID in ids {
                    doc.updateLayer(id: layerID) { $0.isVisible = show }
                }
            }
            return
        }
        perform { $0.updateLayer(id: id) { $0.isVisible.toggle() } }
    }

    func toggleLayerLock(id: UUID) {
        // Locking a member of the multi-selection locks/unlocks all of it (and
        // locked layers leave the selection — they're no longer editable).
        if multiSelectedLayerIDs.contains(id) {
            let lock = !(document?.layer(id: id)?.isLocked ?? false)
            let ids = multiSelectedLayerIDs
            perform { doc in
                for layerID in ids {
                    doc.updateLayer(id: layerID) { $0.isLocked = lock }
                }
            }
            if lock { multiSelectedLayerIDs = [] }
            return
        }
        perform { $0.updateLayer(id: id) { $0.isLocked.toggle() } }
        if document?.layer(id: id)?.isLocked == true, selectedLayerID == id {
            selectedLayerID = nil
        }
    }

    func renameLayer(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { $0.updateLayer(id: id) { $0.name = trimmed } }
    }

    func deleteLayer(id: UUID) {
        // Deleting a member of the multi-selection deletes the whole selection.
        if multiSelectedLayerIDs.contains(id) {
            deleteLayers(ids: Array(multiSelectedLayerIDs))
            return
        }
        discardDragPreview()
        if selectedLayerID == id { selectedLayerID = nil }
        perform { $0.removeLayer(id: id) }
    }

    /// The panel row thumbnail: cached per layer, re-rendered asynchronously
    /// whenever the layer changes (the hash covers content, frame, and style).
    func thumbnail(for layer: Layer) -> CGImage? {
        let hash = layer.hashValue
        if let cached = thumbnailCache[layer.id], cached.hash == hash { return cached.image }
        guard let doc = document else { return thumbnailCache[layer.id]?.image }
        if !thumbnailsInFlight.contains(hash) {
            let renderer = previewRenderer
            let store = store
            let id = layer.id
            // Defer the in-flight bookkeeping off the view-body read path.
            Task { @MainActor [weak self] in
                guard let self, !self.thumbnailsInFlight.contains(hash) else { return }
                self.thumbnailsInFlight.insert(hash)
                // One count per render actually started, so a walk can say
                // whether opening a hundred layer document costs a hundred
                // renders or the handful the panel is showing. Probe only.
                #if PHOTONZ_PLAYTEST
                ViewBuildMeter.shared.built(.layerThumbnail)
                #endif
                let image = await Task.detached(priority: .utility) {
                    renderer.thumbnail(for: id, in: doc, store: store, maxDimension: 80)
                }.value
                self.thumbnailsInFlight.remove(hash)
                if let image { self.thumbnailCache[id] = (hash, image) }
            }
        }
        return thumbnailCache[layer.id]?.image
    }

    /// The picture for every row the layers list is about to draw, gathered in
    /// one walk of the tree. Rows inside a shut group are not asked for, so a
    /// closed group still costs nothing to keep closed.
    ///
    /// The list hands each row its own image rather than letting the row ask:
    /// a row that reads the thumbnail cache becomes an observer of it, and
    /// then every thumbnail that lands redraws every row.
    func thumbnails(for rows: [LayerRowDisplay]) -> [UUID: CGImage] {
        guard let document, !rows.isEmpty else { return [:] }
        let wanted = Set(rows.map(\.id))
        var out: [UUID: CGImage] = [:]
        out.reserveCapacity(wanted.count)
        for layer in document.allLayers where wanted.contains(layer.id) {
            if let image = thumbnail(for: layer) { out[layer.id] = image }
        }
        return out
    }

    #if PHOTONZ_PLAYTEST
    /// Forget every picture the panel has made. Adopting a document does this
    /// too, so a walk can use it to measure what a big document costs to open
    /// without having to save and reopen one.
    func forgetLayerThumbnails() {
        thumbnailCache = [:]
        thumbnailsInFlight = []
    }
    #endif

    /// The Library shelf's picture of a component, sharp enough to be blown up
    /// and cropped in a tile. Same render path as the panel row thumbnail,
    /// asked for at a bigger size and cached on its own.
    func shelfThumbnail(for layer: Layer, dimension: CGFloat) -> CGImage? {
        let key = ShelfPictureKey(id: layer.id, dimension: Int(dimension))
        let hash = layer.hashValue
        if let cached = shelfThumbnails[key], cached.hash == hash { return cached.image }
        guard let doc = document else { return shelfThumbnails[key]?.image }
        if !shelfThumbnailsInFlight.contains(key) {
            let renderer = previewRenderer
            let store = store
            let id = layer.id
            Task { @MainActor [weak self] in
                guard let self, !self.shelfThumbnailsInFlight.contains(key) else { return }
                self.shelfThumbnailsInFlight.insert(key)
                let image = await Task.detached(priority: .utility) {
                    renderer.thumbnail(for: id, in: doc, store: store, maxDimension: dimension)
                }.value
                self.shelfThumbnailsInFlight.remove(key)
                if let image { self.shelfThumbnails[key] = (hash, image) }
            }
        }
        return shelfThumbnails[key]?.image
    }
}
