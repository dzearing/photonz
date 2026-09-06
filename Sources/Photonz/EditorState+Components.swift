import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Component intents: making an original, placing copies, the knobs an
// original exposes, and editing a piece inside a copy.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Components (Next flag `next-components`)

    /// Opens the rename field on a row, the way double-clicking the name does.
    func beginRenamingLayer(id: UUID) {
        layerAwaitingRename = id
    }

    /// Whether Make Component, the canvas mark and the Components shelf exist
    /// at all.
    var componentsEnabled: Bool { Experiments.shared.componentsEnabled }

    /// Whether Layer > Make Component would do anything.
    var canMakeComponent: Bool {
        guard componentsEnabled, let document else { return false }
        return document.canMakeComponent(ids: actionableLayerIDs)
    }

    /// Layer > Make Component (Option Command K): promotes the selected group
    /// to a main, in one undo step, and then does the two things that make the
    /// command legible.
    ///
    /// It **shows the Library on the Components shelf**, because the whole
    /// point of the command is that the thing you drew lands somewhere you can
    /// fetch it from, and the shelf is off until asked for. Pressing a key and
    /// seeing nothing change anywhere you are looking is the failure this
    /// avoids.
    ///
    /// Then it **puts the Component section's Name field ready to type in**,
    /// with the name selected, so naming it is typing rather than hunting for a
    /// field. A component nobody named is a tile called "Component".
    func makeComponent() {
        guard canMakeComponent, let id = actionableLayerIDs.first else { return }
        discardDragPreview()
        var made: UUID?
        perform { made = $0.makeComponent(id: id) }
        guard let componentID = made else { return }
        selectedLayerID = id
        setLibraryVisible(true)
        UserDefaults.standard.set(LibraryScope.components.rawValue, forKey: LibraryPanel.scopeKey)
        // ...and the shelf scrolls to the new tile, which is listed after the
        // components already in the document and so is often below the shelf's
        // own fold.
        pendingLibraryTileID = componentID.uuidString
        // ...and setLibraryVisible cleared any picked tile, so the layer is
        // still the one selected thing. Name it.
        componentAwaitingName = componentID
    }

    /// Every main in the open document, as shelf items, and after them the
    /// starters this document has not taken yet (Next, `next-starter-components`).
    ///
    /// The document's own come first: what you made is what you are most
    /// likely reaching for, and the app's five are always there underneath.
    /// A starter you HAVE taken is listed by the document rather than twice,
    /// because a starter's id is its component id.
    var componentEntries: [LibraryEntry] {
        guard componentsEnabled else { return [] }
        let mine = document?.componentLibraryEntries ?? []
        guard starterComponentsEnabled else { return mine }
        return mine + (document?.starterComponentEntries ?? [])
    }

    /// Whether the shelf is stocked with the app's own components.
    var starterComponentsEnabled: Bool { Experiments.shared.starterComponentsEnabled }

    /// The starter behind a shelf tile, nil for a component somebody made.
    /// Only answers for one the document has NOT taken yet: once it is in the
    /// document it is an ordinary component and is described as one.
    func starterComponent(entryID: String) -> StarterComponent? {
        guard starterComponentsEnabled, let id = UUID(uuidString: entryID),
              document?.mainComponent(componentID: id) == nil else { return nil }
        return StarterComponent(componentID: id)
    }

    /// The starter behind the picked Components tile.
    var selectedStarterComponent: StarterComponent? {
        selectedLibraryItemID.flatMap { starterComponent(entryID: $0) }
    }

    /// What a shelf tile draws a picture of: a starter's subtree, built in the
    /// app's own colors at one to one. Not in any document, so it is built
    /// fresh and cached rather than looked up.
    func starterPreviewLayer(_ kind: StarterComponent) -> Layer {
        if let cached = starterPreviewLayers[kind] { return cached }
        let layer = StarterComponents.layer(kind, measure: { TextRasterizer.naturalSize($0) })
        starterPreviewLayers[kind] = layer
        return layer
    }

    /// The picture on a starter's tile, at least `dimension` pixels along its
    /// long side. Rendered off a one-layer document, on the same path every
    /// other thumbnail takes, and kept: the five never change, so this happens
    /// once per size per launch and only once the Components shelf has
    /// actually been looked at.
    ///
    /// The subtree is BUILT at the size it will be drawn rather than built
    /// small and blown up, so a badge on a tile is as crisp as a card is.
    func starterThumbnail(_ kind: StarterComponent, dimension: CGFloat) -> CGImage? {
        let key = ShelfPictureKey(id: kind.componentID, dimension: Int(dimension))
        if let cached = starterThumbnails[key] { return cached }
        let box = starterPreviewLayer(kind).localBounds
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = max(dimension / max(box.width, box.height), 1)
        var preview = StarterComponents.layer(kind, scale: scale,
                                              measure: { TextRasterizer.naturalSize($0) })
        let scaledBox = preview.localBounds
        guard scaledBox.width > 0, scaledBox.height > 0 else { return nil }
        preview.frame.origin = .zero
        let document = PhotonzDocument(canvasSize: scaledBox.size, layers: [preview])
        guard let image = previewRenderer.thumbnail(for: preview.id, in: document,
                                                    store: store,
                                                    maxDimension: dimension) else { return nil }
        starterThumbnails[key] = image
        return image
    }

    /// Puts a component in the picture, whether it is one of the app's or one
    /// of yours: the single path a drag from the shelf, a double click on a
    /// tile and the Layer menu row all run.
    ///
    /// A starter the document has not taken yet arrives as the ORIGINAL, with
    /// its named colors and its knobs; everything else, including a second
    /// drop of the same starter, is a copy.
    @discardableResult
    func placeComponent(componentID: UUID, at point: CGPoint) -> UUID? {
        if let starter = StarterComponent(componentID: componentID),
           document?.mainComponent(componentID: componentID) == nil {
            return insertStarterComponent(starter, at: point)
        }
        return insertComponentInstance(componentID: componentID, at: point)
    }

    /// Brings a starter into the open document, centred on a canvas point. One
    /// undo step: the component, the colors it paints from and the knobs it
    /// offers all arrive or none of them do.
    @discardableResult
    func insertStarterComponent(_ kind: StarterComponent, at point: CGPoint) -> UUID? {
        guard starterComponentsEnabled, document != nil else { return nil }
        discardDragPreview()
        var placed: UUID?
        perform {
            placed = $0.insertStarterComponent(kind, at: point,
                                               measure: { TextRasterizer.naturalSize($0) })
        }
        guard let placed else { return nil }
        selectedLibraryItemID = nil
        selectLayer(placed, inGroup: self.document?.parentID(of: placed))
        return placed
    }

    /// The main behind the picked Components tile, or nil when the pick is not
    /// a component.
    var selectedComponentLayer: Layer? {
        guard componentsEnabled, let raw = selectedLibraryItemID,
              let componentID = UUID(uuidString: raw) else { return nil }
        return document?.mainComponent(componentID: componentID)
    }

    /// The Component section's Name field. One name in one place: renaming here
    /// renames the layer, which is what the layers list, the canvas mark and
    /// the tile are all reading.
    func renameComponent(componentID: UUID, to name: String) {
        guard componentsEnabled else { return }
        perform { $0.renameComponent(componentID: componentID, to: name) }
    }

    /// The component id behind the picked Components tile, whatever it is
    /// called and wherever the original sits.
    var selectedComponentID: UUID? { selectedComponentLayer?.componentID }

    /// Whether Layer ▸ Insert Component would do anything: a component is
    /// picked on the shelf, whether it is one of yours or one of the app's.
    var canInsertPickedComponent: Bool {
        selectedComponentID != nil || selectedStarterComponent != nil
    }

    /// Layer ▸ Insert Component, and what a double click on a Components tile
    /// does: puts a copy in the middle of what you are looking at.
    ///
    /// The middle of the VIEW, not the middle of the canvas: on a document
    /// zoomed in on one screen, the middle of the canvas is usually off screen,
    /// and a copy you have to go and find is a copy you did not place.
    func insertPickedComponent() {
        if let componentID = selectedComponentID {
            insertComponentInstance(componentID: componentID, at: visibleCanvasCentre)
        } else if let starter = selectedStarterComponent {
            insertStarterComponent(starter, at: visibleCanvasCentre)
        }
    }

    /// The middle of what the canvas is showing, in document coordinates.
    var visibleCanvasCentre: CGPoint {
        guard let document else { return .zero }
        guard let viewport else {
            return CGPoint(x: document.canvasSize.width / 2, y: document.canvasSize.height / 2)
        }
        let visible = CGRect(x: -viewport.origin.x / viewport.zoom,
                             y: -viewport.origin.y / viewport.zoom,
                             width: viewport.viewSize.width / viewport.zoom,
                             height: viewport.viewSize.height / viewport.zoom)
            .intersection(CGRect(origin: .zero, size: document.canvasSize))
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            return CGPoint(x: document.canvasSize.width / 2, y: document.canvasSize.height / 2)
        }
        return CGPoint(x: visible.midX, y: visible.midY)
    }

    /// Places a copy of a component with its centre on a canvas point: the one
    /// path a drag from the shelf, a double click on a tile and the menu row
    /// all run, so all three land the same copy in the same place.
    ///
    /// The copy becomes the selection, because the thing you just placed is the
    /// thing you want to move next, and the shelf lets go of its tile so the
    /// dock talks about the copy rather than the component you took it from.
    @discardableResult
    func insertComponentInstance(componentID: UUID, at point: CGPoint) -> UUID? {
        guard Experiments.shared.componentsEnabled, let document else { return nil }
        guard document.mainComponent(componentID: componentID) != nil else { return nil }
        // Dropping a component onto its own original would make a thing that
        // draws forever, so it is refused out loud rather than quietly ignored.
        // The same answer is what the canvas draws mid-drag, so a drag that is
        // going to be refused says so before the button comes up.
        if document.componentDropTarget(of: componentID, at: point) == .refused {
            raiseComponentCycleNotice()
            return nil
        }
        discardDragPreview()
        var placed: UUID?
        perform { placed = $0.insertComponentInstance(of: componentID, at: point) }
        guard let placed else { return nil }
        selectedLibraryItemID = nil
        selectLayer(placed, inGroup: self.document?.parentID(of: placed))
        return placed
    }

    private func raiseComponentCycleNotice() {
        guard Experiments.shared.componentsEnabled else { return }
        raiseCanvasNotice(.componentCycle)
    }

    /// "Select on Canvas" on a Components tile: answers "where is this thing?"
    /// by selecting the main itself, which hands the dock back to the layer.
    func selectComponentOnCanvas(componentID: UUID) {
        guard let main = document?.mainComponent(componentID: componentID) else { return }
        selectLayer(main.id, inGroup: document?.parentID(of: main.id))
    }

    // MARK: - Component knobs and overrides (Next flag `next-components`)

    /// The knobs an original exposes, in the order it lists them.
    func componentProperties(of componentID: UUID) -> [ComponentProperty] {
        guard componentsEnabled else { return [] }
        return document?.componentProperties(of: componentID) ?? []
    }

    /// What the Add Property menu lists: the layers inside the original and the
    /// knob each one could become.
    func componentPropertyCandidates(componentID: UUID) -> [ComponentPropertyCandidate] {
        guard componentsEnabled else { return [] }
        return document?.componentPropertyCandidates(componentID: componentID) ?? []
    }

    @discardableResult
    func addComponentProperty(componentID: UUID, target: UUID, kind: ComponentPropertyKind,
                              slot: ColorSlot? = nil) -> UUID? {
        guard componentsEnabled else { return nil }
        var added: UUID?
        perform {
            added = $0.addComponentProperty(componentID: componentID, target: target,
                                            kind: kind, slot: slot)
        }
        componentPropertyAwaitingName = added
        return added
    }

    func removeComponentProperty(componentID: UUID, propertyID: UUID) {
        guard componentsEnabled else { return }
        perform { $0.removeComponentProperty(componentID: componentID, propertyID: propertyID) }
    }

    func renameComponentProperty(componentID: UUID, propertyID: UUID, to name: String) {
        guard componentsEnabled else { return }
        perform { $0.renameComponentProperty(componentID: componentID, propertyID: propertyID, to: name) }
    }

    /// The shapes a choice can land on: exactly what the original holds.
    func componentVariantOptions(componentID: UUID, propertyID: UUID) -> [Layer] {
        guard componentsEnabled else { return [] }
        return document?.componentVariantOptions(componentID: componentID, propertyID: propertyID) ?? []
    }

    /// The same shapes with labels a person can tell apart, which is what the
    /// choice menu lists.
    func componentVariantOptionLabels(componentID: UUID,
                                      propertyID: UUID) -> [(id: UUID, label: String)] {
        guard componentsEnabled else { return [] }
        return document?.componentVariantOptionLabels(componentID: componentID,
                                                      propertyID: propertyID) ?? []
    }

    /// What a copy shows for a knob: its own answer, or the original's.
    func instanceValue(instance: UUID, property: UUID) -> ComponentPropertyValue? {
        document?.instanceValue(instance: instance, property: property)
    }

    /// Which knobs this copy has answered for itself, which is what puts the
    /// revert control on a row.
    func instanceOverrides(instance: UUID) -> Set<UUID> {
        document?.instanceOverrides(instance: instance) ?? []
    }

    /// Sets one knob on one copy.
    ///
    /// It is performed WITHOUT the "copies followed" pill: that pill exists to
    /// say how far an edit to an original reached, and this edit reached one
    /// copy, the one whose panel the person is typing into and looking at.
    func setInstanceOverride(instance: UUID, property: UUID, value: ComponentPropertyValue) {
        guard componentsEnabled else { return }
        perform(announcing: false) {
            $0.setInstanceOverride(instance: instance, property: property, value: value)
        }
    }

    /// Puts one knob back to following the original.
    func clearInstanceOverride(instance: UUID, property: UUID) {
        guard componentsEnabled else { return }
        perform(announcing: false) { $0.clearInstanceOverride(instance: instance, property: property) }
    }

    /// The picked layers in draw order. The same set every whole-selection
    /// command acts on, ordered, so a row over several copies reads the same
    /// way twice running and one undo step lands the same way every time.
    var orderedSelectedLayerIDs: [UUID] {
        let picked = actionableLayerIDs
        guard !picked.isEmpty, let document else { return [] }
        return document.allLayers.map(\.id).filter { picked.contains($0) }
    }

    /// What the Component section shows for what is picked: the copies it
    /// speaks for, their original's knobs, and what each knob reads across
    /// them. One copy or five, this is the same reading, which is what lets one
    /// typed word rename five buttons.
    var componentKnobSelection: ComponentKnobSelection {
        guard componentsEnabled, let document else { return .none }
        return document.componentKnobSelection(layerIDs: orderedSelectedLayerIDs)
    }

    /// The same reading for copies named outright rather than picked, which is
    /// how a piece INSIDE a copy answers for the copy it belongs to.
    func componentKnobSelection(instances: [UUID]) -> ComponentKnobSelection {
        guard componentsEnabled, let document else { return .none }
        return document.componentKnobSelection(layerIDs: instances)
    }

    /// Sets one knob on every picked copy, in ONE undo step however many it
    /// reached.
    ///
    /// Like setting it on one copy, it lands without the "copies followed"
    /// pill: that pill says how far an edit to an ORIGINAL reached, and this
    /// edit reached exactly the copies whose panel is on screen.
    func setInstanceOverride(instances: [UUID], property: UUID, value: ComponentPropertyValue) {
        guard componentsEnabled, !instances.isEmpty else { return }
        perform(announcing: false) {
            _ = $0.setInstanceOverride(instances: instances, property: property, value: value)
        }
    }

    /// Puts one knob back to following the original on every picked copy, in
    /// one undo step.
    func clearInstanceOverride(instances: [UUID], property: UUID) {
        guard componentsEnabled, !instances.isEmpty else { return }
        perform(announcing: false) {
            _ = $0.clearInstanceOverride(instances: instances, property: property)
        }
    }

    // MARK: - A colour knob on a copy

    /// What one colour knob row shows: the same `ColorStyleSelection` a colour
    /// row on the canvas shows, so the two can never disagree about whether a
    /// colour is shared, named or Mixed.
    func componentColorSelection(instances: [UUID], property: UUID) -> ColorStyleSelection {
        guard componentsEnabled, let document else {
            return ColorStyleSelection(slot: .fill, members: [], selectionCount: 0, capableCount: 0)
        }
        return document.componentColorSelection(instances: instances, property: property)
    }

    /// The saved colours a knob row offers: the ones kept for the part it
    /// paints, exactly as the canvas row scopes them.
    func componentColorStyles(instances: [UUID], property: UUID) -> [ColorStyle] {
        guard let slot = document?.componentColorSlot(instance: instances.first ?? UUID(),
                                                      property: property) else { return [] }
        return colorStyles(for: slot)
    }

    /// One frame of a colour drag on a knob: paints the copies and renders,
    /// recording nothing, so the picture follows the pull instead of appearing
    /// when you let go.
    func previewInstanceColor(instances: [UUID], property: UUID, paint: Paint) {
        guard componentsEnabled, var doc = document, !instances.isEmpty else { return }
        knobPaintPreview = (instances, property, paint)
        guard doc.setInstanceColor(instances: instances, property: property,
                                   answer: ComponentColorAnswer(paint: paint)) > 0 else { return }
        // A copy is refilled from its original by the sync, which normally runs
        // inside `History.perform`; a preview records nothing, so it has to ask
        // for the refill itself or the copy would not repaint at all.
        doc.syncComponentInstances()
        submit(doc)
    }

    /// The paint a knob row's swatch shows: the one in flight while a drag is
    /// happening, so the chip under the picker keeps up with the canvas.
    func previewedInstanceColor(instances: [UUID], property: UUID) -> Paint? {
        guard let preview = knobPaintPreview, preview.property == property,
              preview.instances == instances else { return nil }
        return preview.paint
    }

    /// Letting go: ONE undo step for the whole gesture, however many copies it
    /// reached, and one entry in the recents row.
    func setInstanceColor(instances: [UUID], property: UUID, paint: Paint) {
        guard componentsEnabled else { return }
        knobPaintPreview = nil
        perform(announcing: false) {
            _ = $0.setInstanceColor(instances: instances, property: property,
                                    answer: ComponentColorAnswer(paint: paint))
        }
        recordRecentColor(hex: paint.hex)
    }

    /// Answers a knob with a saved colour, so editing that colour later moves
    /// every copy pointing at it.
    func setInstanceColorStyle(instances: [UUID], property: UUID, styleID: UUID) {
        guard componentsEnabled, colorStylesEnabled else { return }
        knobPaintPreview = nil
        perform(announcing: false) {
            _ = $0.setInstanceColorStyle(instances: instances, property: property, styleID: styleID)
        }
    }

    /// Lets a knob go back to a colour of its own, keeping what it is wearing.
    /// Not the same as Revert, which puts the copy back on the original.
    func unlinkInstanceColorStyle(instances: [UUID], property: UUID) {
        guard componentsEnabled, colorStylesEnabled else { return }
        perform(announcing: false) {
            _ = $0.unlinkInstanceColorStyle(instances: instances, property: property)
        }
    }

    // MARK: - Editing a piece inside a copy

    /// The copy a layer is a piece of, and where that piece came from. Nil for
    /// an ordinary layer, which is everything outside a copy.
    func componentPiece(of id: UUID) -> ComponentPiece? {
        guard componentsEnabled else { return nil }
        return document?.componentPiece(of: id)
    }

    /// The copy the selection is a piece of, which is what puts the Component
    /// section on the panel when you have clicked into one.
    var selectedComponentPiece: ComponentPiece? {
        guard let id = selectedLayerID else { return nil }
        return componentPiece(of: id)
    }

    /// What typing over a layer means: nothing special, a knob to land on, or
    /// a refusal with a way forward.
    func wordingEdit(of id: UUID) -> ComponentPieceEdit {
        guard componentsEnabled else { return .ordinary }
        return document?.wordingEdit(of: id) ?? .ordinary
    }

    /// Says out loud why an edit inside a copy went nowhere. Nothing else on
    /// screen would: the double click would simply not open a field.
    func refuseWordingEdit(_ refusal: ComponentPieceRefusal) {
        wordingOffer = refusal.remedy == .exposeWording ? refusal.piece : nil
        raiseCanvasNotice(.componentPieceRefused(refusal))
    }

    /// The offer this copy is carrying, if any: the piece somebody just tried
    /// to type over.
    func wordingOffer(for instance: UUID) -> ComponentPiece? {
        guard let offer = wordingOffer, offer.instance == instance,
              canExposePieceWording(of: offer.layer) else { return nil }
        return offer
    }

    /// Takes the offer: the original grows a wording knob for that piece, and
    /// the copy can answer it in the field that appears.
    func takeWordingOffer(_ piece: ComponentPiece) {
        exposePieceWording(of: piece.layer)
        wordingOffer = nil
    }

    /// Lands words typed over a piece on the copy's own answer, or puts the
    /// piece back to following the original when the field was emptied.
    func commitPieceWording(of id: UUID, to string: String) {
        guard componentsEnabled else { return }
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let instance = document?.componentPiece(of: id)?.instance
        perform(announcing: false) { document in
            if isEmpty {
                document.clearPieceWording(of: id)
            } else {
                document.setPieceWording(of: id, to: string)
            }
        }
        // The copy is what is left selected, so the knob that just took the
        // words is on screen with a way back beside it. The piece itself is
        // never selectable, and leaving nothing selected after typing would
        // hide the one control that says what just happened.
        if let instance { selectLayer(instance, inGroup: document?.parentID(of: instance)) }
    }

    /// Whether Make Wording Adjustable would do anything for this piece.
    func canExposePieceWording(of id: UUID) -> Bool {
        guard componentsEnabled else { return false }
        return document?.canExposePieceWording(of: id) ?? false
    }

    /// Makes a piece's wording adjustable from the copy you are looking at: the
    /// knob goes on the original, so every copy gets it, and this copy can
    /// answer it straight away.
    @discardableResult
    func exposePieceWording(of id: UUID) -> UUID? {
        guard componentsEnabled else { return nil }
        var added: UUID?
        perform { added = $0.exposePieceWording(of: id) }
        return added
    }

    /// Picks the whole copy a piece belongs to, which is where everything a
    /// copy CAN be told sits.
    func selectEnclosingCopy(of piece: ComponentPiece) {
        selectLayer(piece.instance, inGroup: document?.parentID(of: piece.instance))
    }

    /// Stops the copy a piece belongs to from following its original, from the
    /// piece you were trying to edit. Detach is the one way to get at a piece
    /// the original never made adjustable, so it is offered where you hit the
    /// wall rather than only where the copy answers for itself.
    func detachEnclosingCopy(of piece: ComponentPiece) {
        selectEnclosingCopy(of: piece)
        detachInstance()
    }

    /// Which parts of a copy's look are its own rather than the original's,
    /// named as their controls are, in the order they sit in the dock.
    func instanceStyleOverrideLabels(instance: UUID) -> [String] {
        guard componentsEnabled else { return [] }
        return document?.instanceStyleOverrideLabels(instance: instance) ?? []
    }

    /// Whether one part of a copy's look is its own, which is what puts the way
    /// back on an Effects row.
    func isInstanceStyleOwn(instance: UUID, field: LayerStyleField) -> Bool {
        guard componentsEnabled else { return false }
        return document?.isInstanceStyleOwn(instance: instance, field: field) ?? false
    }

    /// Puts one part of a copy's look back to following the original.
    ///
    /// Like setting a knob, it is performed without the "copies followed" pill:
    /// the change lands on the one copy whose panel the person is looking at.
    func clearInstanceStyleOverride(instance: UUID, field: LayerStyleField) {
        guard componentsEnabled else { return }
        stylePreview = nil
        discardDragPreview()
        perform(announcing: false) { $0.clearInstanceStyleOverride(instance: instance, field: field) }
    }

    /// What the "its own look" row says for the picked copies: one copy's own
    /// parts, or how many of several have a look of their own.
    func instanceOwnLookLabel(instances: [UUID]) -> String? {
        guard componentsEnabled else { return nil }
        return document?.instanceOwnLookLabel(instances: instances)
    }

    /// Puts every picked copy's look back to the original's, in one undo step.
    func clearInstanceStyleOverrides(instances: [UUID]) {
        guard componentsEnabled, !instances.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform(announcing: false) { _ = $0.clearInstanceStyleOverrides(instances: instances) }
    }

    /// Puts a copy's whole look back to the original's.
    func clearInstanceStyleOverrides(instance: UUID) {
        guard componentsEnabled else { return }
        stylePreview = nil
        discardDragPreview()
        perform(announcing: false) { $0.clearInstanceStyleOverrides(instance: instance) }
    }

    /// What this copy owns about its own box, in words: `1200 wide`, `48 tall`,
    /// or both. Nil for a copy that is the size of its original, which is what
    /// keeps the row off the section until there is something to say.
    func instanceOwnSizeLabel(instance: UUID) -> String? {
        guard componentsEnabled else { return nil }
        return document?.instanceOwnSizeLabel(instance: instance)
    }

    /// The same row for the picked copies: one copy's own words, or how many of
    /// several have a size of their own.
    func instanceOwnSizeLabel(instances: [UUID]) -> String? {
        guard componentsEnabled else { return nil }
        return document?.instanceOwnSizeLabel(instances: instances)
    }

    /// Puts every picked copy back on its original's size, in one undo step.
    func clearInstanceSize(instances: [UUID]) {
        guard componentsEnabled, !instances.isEmpty else { return }
        discardDragPreview()
        perform(announcing: false) { _ = $0.clearInstanceSize(instances: instances) }
    }

    /// Puts a copy back on its original's size, both sides at once.
    ///
    /// Like the way back on a knob, it lands without the "copies followed"
    /// pill: the change reaches the one copy whose panel is on screen.
    func clearInstanceSize(instance: UUID) {
        guard componentsEnabled else { return }
        discardDragPreview()
        perform(announcing: false) { $0.clearInstanceSize(instances: [instance]) }
    }

    /// Whether Layer ▸ Detach Instance would do anything: one unlocked copy is
    /// selected.
    var canDetachInstance: Bool {
        guard componentsEnabled, let document else { return false }
        return document.canDetachInstance(ids: actionableLayerIDs)
    }

    /// Layer ▸ Detach Instance (⌥⌘B): turns the selected copy into ordinary
    /// layers that no longer follow the original.
    ///
    /// It says so out loud, because nothing on screen changes when it runs: the
    /// picture the instant after is the picture the instant before, and a
    /// command that looks like it did nothing is a command people press twice.
    func detachInstance() {
        guard canDetachInstance, let document else { return }
        let ids = orderedSelectedLayerIDs
            .filter { document.detachableInstances(ids: [$0]).isEmpty == false }
        guard let first = ids.first else { return }
        // Every picked copy follows ONE original on this panel, so the word on
        // screen can name it; a stray copy of something else is named by count
        // alone rather than by picking a favourite.
        let names = Set(ids.compactMap { id in
            document.layer(id: id)?.instanceOf
                .flatMap { document.mainComponent(componentID: $0)?.name }
        })
        discardDragPreview()
        var detached = 0
        perform(announcing: false) { detached = $0.detachInstances(ids: ids) }
        guard detached > 0 else { return }
        // One copy detached is still the copy whose panel you were looking at,
        // so it stays the selection; several stay exactly as they were picked.
        if ids.count == 1 { selectLayer(first, inGroup: self.document?.parentID(of: first)) }
        raiseCanvasNotice(.componentDetached(component: names.count == 1 ? names.first ?? nil : nil,
                                             count: detached))
    }

    /// Whether Layer ▸ Select Original would do anything: the selection is a
    /// copy whose original is still in the document.
    var canSelectComponentOriginal: Bool { selectedInstanceOriginal != nil }

    /// The component the selected copy follows, when there is exactly one copy
    /// selected and its original is still here.
    private var selectedInstanceOriginal: UUID? {
        guard componentsEnabled, let document, actionableLayerIDs.count == 1,
              let id = actionableLayerIDs.first,
              let componentID = document.layer(id: id)?.instanceOf,
              document.mainComponent(componentID: componentID) != nil else { return nil }
        return componentID
    }

    /// Exposes the first piece of the selected original that can take this
    /// kind of knob. The Add menu lives in the dock, which a scripted playtest
    /// cannot reach with the pointer, so a walk asks for it here.
    func exposeFirstProperty(kind: ComponentPropertyKind) {
        guard componentsEnabled, let id = actionableLayerIDs.first,
              let componentID = document?.layer(id: id)?.componentID,
              let candidate = componentPropertyCandidates(componentID: componentID)
                  .first(where: { $0.kinds.contains(kind) }) else { return }
        // A colour knob names WHICH colour, so a walk asking for one takes the
        // first the candidate offers, which is a shape's fill.
        addComponentProperty(componentID: componentID, target: candidate.layerID, kind: kind,
                             slot: kind == .color ? candidate.colorSlots.first : nil)
    }

    /// Answers the selected copy's first colour knob with the first saved
    /// colour kept for that part. The list of saved colours is a menu in the
    /// dock, which a walk cannot open, so this is the way in.
    func answerFirstColorKnobWithSavedColor() {
        guard componentsEnabled, let id = actionableLayerIDs.first,
              let componentID = document?.layer(id: id)?.instanceOf,
              let property = componentProperties(of: componentID).first(where: { $0.kind == .color }),
              let style = componentColorStyles(instances: [id], property: property.id).first
        else { return }
        setInstanceColorStyle(instances: [id], property: property.id, styleID: style.id)
    }

    /// Moves the picked copies' first choice knob on to its next option, the
    /// same edit picking the next row of that knob's menu makes — and, like the
    /// menu, it reaches every picked copy in one step. Scripted playtests only:
    /// a walk cannot open a menu inside the dock.
    func cycleInstanceChoice() {
        let selection = componentKnobSelection
        guard let componentID = selection.componentID, let id = selection.instances.first,
              let property = selection.properties.first(where: { $0.kind == .variant })
        else { return }
        let options = componentVariantOptions(componentID: componentID, propertyID: property.id)
        guard !options.isEmpty else { return }
        // From what the picked copies READ, which is the value they share; a
        // row saying Mixed steps from the first option, the way choosing from
        // its menu would.
        let current = selection.reading(property.id).optionValue
            ?? instanceValue(instance: id, property: property.id)?.optionValue
        let index = options.firstIndex { $0.id == current } ?? 0
        let next = options[(index + 1) % options.count]
        setInstanceOverride(instances: selection.instances, property: property.id,
                            value: .variant(next.id))
    }

    /// Whether Layer ▸ Make Alternatives would do anything: the selection can
    /// become a set of alternatives with a knob that picks between them.
    var canMakeChoice: Bool {
        guard componentsEnabled, Experiments.shared.layerGroupsEnabled, let document else { return false }
        return document.canMakeChoice(ids: actionableLayerIDs)
    }

    /// Layer ▸ Make Alternatives: the selected shapes become a group of
    /// alternatives inside the original, and the original grows the knob every
    /// copy uses to pick between them. One undo step.
    ///
    /// It says so out loud, because settling the choice HIDES all but one of
    /// the shapes that were just selected: without a word on screen the command
    /// reads as having deleted one of them.
    func makeChoice() {
        guard canMakeChoice else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var made: PhotonzDocument.MadeChoice?
        perform(announcing: false) { made = $0.makeChoice(ids: ids) }
        guard let made, let document else { return }
        // The new group is selected, the same way ⌘G leaves the group it made
        // selected: the next thing you do is almost always to it.
        groupContextID = document.parentID(of: made.group)
        selectedLayerID = made.group
        setSelection(nil, captureLayers: false)
        let knob = document.componentHome(of: made.group)
            .flatMap { document.componentProperty(componentID: $0, propertyID: made.property) }?.name
        raiseCanvasNotice(.componentChoiceMade(options: made.options, knob: knob ?? "the choice knob"))
    }

    /// Layer ▸ Select Original: jumps from a copy to the thing every copy
    /// follows, which is where a change to all of them is made.
    func selectComponentOriginal() {
        guard let componentID = selectedInstanceOriginal else { return }
        selectComponentOnCanvas(componentID: componentID)
    }
}
