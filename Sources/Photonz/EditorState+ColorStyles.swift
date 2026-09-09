import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Colour styles and the colour rows that use them, plus the recently used
// colours the pickers remember.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Recent colors (13.2)

    static let recentColorsKey = "recentColors"

    static func loadRecentColors() -> RecentColors {
        guard let data = UserDefaults.standard.data(forKey: recentColorsKey),
              let recents = try? JSONDecoder().decode(RecentColors.self, from: data) else {
            return RecentColors()
        }
        return recents
    }

    /// The single funnel for the shared recents list. Called from every COMMIT
    /// path (not preview): annotation color, per-layer annotation color, text
    /// color, and LayerStyle border/shadow (which is what a callout's ring
    /// is). Malformed hex is ignored by `RecentColors.record`.
    func recordRecentColor(hex: String) {
        recentColors.record(hex: hex)
        if let data = try? JSONEncoder().encode(recentColors) {
            UserDefaults.standard.set(data, forKey: Self.recentColorsKey)
        }
    }

    // MARK: - Color styles (Next flag `next-styles`)

    /// Whether colors can be saved under a name at all.
    var colorStylesEnabled: Bool { Experiments.shared.colorStylesEnabled }

    /// `next-color-picker`: whether every color row opens the app's designed
    /// picker rather than the one it shipped with (and, on a few rows, the
    /// system color panel).
    var designedColorPickerEnabled: Bool { Experiments.shared.designedColorPickerEnabled }

    /// The binding a color well hands its popover.
    /// The same well opened or shut by the swatch that owns it, which is what
    /// clicking a toolbar swatch twice means.
    func toggleColorWell(_ key: String) {
        openColorWell = openColorWell == key ? nil : key
    }

    func colorWellBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.openColorWell == key },
                set: { [weak self] shown in self?.openColorWell = shown ? key : nil })
    }

    /// Saves a color the picker is holding under a name, whatever it came from.
    ///
    /// This is the picker's own Save style, which differs from the color row's
    /// in one way: the row saves what the picked layers are painted in and
    /// points them at it, while this saves a color that may be nothing's yet,
    /// so it only puts it on the shelf. Both land in the Library the same way,
    /// and both show it, because a style you cannot see is a button that
    /// appears to do nothing.
    @discardableResult
    func saveColorStyle(hex: String, name: String? = nil, slot: ColorSlot? = nil) -> UUID? {
        saveColorStyle(paint: Paint(hex: hex), name: name, slot: slot)
    }

    /// The same, with the whole paint the picker is holding, so a gradient
    /// somebody has just aimed is kept aimed rather than saved as the one stop
    /// they happened to be editing.
    @discardableResult
    func saveColorStyle(paint: Paint, name: String? = nil, slot: ColorSlot? = nil) -> UUID? {
        guard colorStylesEnabled else { return nil }
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.addColorStyle(name: name, paint: paint,
                                           roles: slot.map { [$0.styleRole] }) }
        guard let styleID = saved else { return nil }
        showStylesShelf()
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Save as Style: opens the name field under the row that paints this kind
    /// of colour, whatever is picked, because only one field is open at a time
    /// and the selection is what it is about.
    func beginNamingColorStyle(slot: ColorSlot) {
        beginNamingColorStyle(colorRowTarget(slot: slot))
    }

    /// The row on screen that paints a kind of colour.
    ///
    /// The name field belongs to a row, and the Appearance list builds each of
    /// its rows knowing WHICH picked layers wear which colour. A bare kind of
    /// colour therefore addresses no row that is actually up: asking to name a
    /// fill that way opened a field under a row nobody could see, so Save as
    /// Style looked like a button that did nothing (reported 2026-09-07).
    /// Everything that reaches a row by the colour it paints comes through
    /// here first.
    func colorRowTarget(slot: ColorSlot) -> ColorTarget {
        guard Experiments.shared.shapePartsEnabled, let document else {
            return ColorTarget(slot)
        }
        let row = document.layerPartRow(layerIDs: colorStyleTargetIDs, slot: slot)
        return row.flatMap { ColorTarget($0.colors) } ?? ColorTarget(slot)
    }

    /// The same, for a row that paints more than one kind of colour.
    func beginNamingColorStyle(_ target: ColorTarget) {
        guard colorStylesEnabled else { return }
        // One field at a time, wherever it was opened from.
        colorStyleShelfNaming = nil
        colorStyleNaming = ColorStyleNamingRequest(target: target)
    }

    /// Escape, or the name landing: the field closes.
    func endNamingColorStyle() {
        colorStyleNaming = nil
    }

    // MARK: - A color let go of on the Library shelf

    /// What the Library shelf would do with the paint being held over it right
    /// now. The shelf lights up on this answer, so what it promises while the
    /// colour is in the air is exactly what letting go does.
    func colorShelfDrop(_ paint: Paint, from saved: ColorDrop.SavedColor? = nil) -> ColorDrop.Answer {
        // A colour dragged OFF the shelf is already on it. The shelf is the
        // whole Library panel, tiles included, so a tile picked up and let go
        // an inch away would otherwise offer to save a second copy of itself.
        let cameFrom = saved.flatMap { one in colorStyles.first { $0.id == one.id }?.name }
        let shelf = ColorDrop.Shelf(canSave: colorStylesEnabled && document != nil,
                                    alreadySaved: colorStyles.first {
                                        $0.paint.draws(sameAs: paint)
                                    }?.name,
                                    cameFrom: cameFrom)
        return ColorDrop.answer(dropping: paint, on: shelf)
    }

    /// A colour let go of on the Library shelf: the name field opens with that
    /// colour beside it, and nothing is saved until the name lands.
    ///
    /// Asking FIRST is the whole point. Quietly making one called "Color 1"
    /// would contradict the decision every other way of saving a colour
    /// already keeps, and would leave a tile nobody meant to make.
    ///
    /// The shelf turns to Styles as the colour lands, BEFORE the name is
    /// typed, so the field is above the shelf the colour is joining rather
    /// than above a wall of screenshots that then vanishes on Return. Escape
    /// puts the shelf back, so a drop nobody meant to make leaves the Library
    /// exactly as it found it.
    func beginNamingDroppedColor(_ paint: Paint) {
        guard colorShelfDrop(paint).lightsUp else { return }
        colorStyleNaming = nil
        // A second colour dropped while the field is still open keeps the
        // shelf the FIRST one interrupted, which is the one Escape owes.
        let before = colorStyleShelfNaming?.scopeBefore ?? libraryScope
        colorStyleShelfNaming = DroppedColorNaming(paint: paint, scopeBefore: before)
        showStylesShelf()
    }

    /// Escape, or the field losing its colour: nothing was made, so there is
    /// nothing to undo either, and the shelf goes back to whatever it was
    /// showing before the colour arrived.
    func endNamingDroppedColor() {
        guard let naming = colorStyleShelfNaming else { return }
        colorStyleShelfNaming = nil
        libraryScope = naming.scopeBefore
    }

    /// The name lands: the colour goes on the shelf, and the row it was
    /// dragged off is left exactly as it was — a drop here KEEPS a colour, it
    /// does not paint with one.
    @discardableResult
    func saveDroppedColorStyle(name: String) -> UUID? {
        guard let naming = colorStyleShelfNaming else { return nil }
        colorStyleShelfNaming = nil
        // No slot, so no roles: a colour saved from the shelf came off no
        // particular row and is offered on all of them.
        return saveColorStyle(paint: naming.paint, name: name)
    }

    /// Which shelf the Library is showing. It lives in settings rather than in
    /// this object because the panel remembers it across launches, so this is
    /// the one place that reads and writes it by hand.
    private var libraryScope: String {
        get {
            UserDefaults.standard.string(forKey: LibraryPanel.scopeKey)
                ?? LibraryScope.media.rawValue
        }
        set { UserDefaults.standard.set(newValue, forKey: LibraryPanel.scopeKey) }
    }

    /// The name the shelf's field opens on: one nobody is using yet, and named
    /// for what it is, so a saved ramp is offered "Gradient" over "Color 4".
    func suggestedColorStyleName(paint: Paint) -> String {
        let base = PhotonzDocument.colorStyleNameBase(for: paint)
        return document?.freshColorStyleName(base: base) ?? base
    }

    /// Every style in the open document, as shelf items.
    var colorStyleEntries: [LibraryEntry] {
        guard colorStylesEnabled else { return [] }
        return document?.colorStyleLibraryEntries ?? []
    }

    /// Every style in the open document, in the order the shelf lists them.
    var colorStyles: [ColorStyle] {
        guard colorStylesEnabled else { return [] }
        return document?.colorStyles ?? []
    }

    /// The styles ONE color row offers: only the ones meant for the part it
    /// paints, so a color kept for hairlines is not on the menu as something
    /// to fill a box with.
    func colorStyles(for slot: ColorSlot) -> [ColorStyle] {
        guard colorStylesEnabled else { return [] }
        return document?.colorStyles(for: slot) ?? []
    }

    /// What a saved color is offered for right now, including the answer
    /// worked out for one saved before anybody said.
    func colorStyleRoles(styleID: UUID) -> [ColorStyleRole] {
        document?.effectiveColorStyleRoles(id: styleID) ?? []
    }

    /// The Style section's "Use it for" checkboxes: which parts of a layer
    /// this saved color turns up on. Ticking nothing is refused, because a
    /// color offered nowhere is a shelf tile that cannot be used.
    func setColorStyleRoles(styleID: UUID, roles: [ColorStyleRole]) {
        guard colorStylesEnabled else { return }
        perform { $0.setColorStyleRoles(id: styleID, roles: roles) }
    }

    /// The style behind the picked Styles tile, or nil when the pick is not a
    /// style.
    var selectedColorStyle: ColorStyle? {
        guard colorStylesEnabled, let raw = selectedLibraryItemID,
              let styleID = UUID(uuidString: raw) else { return nil }
        return document?.colorStyle(id: styleID)
    }

    /// The style painting one of a layer's colors, nil when that color is the
    /// layer's own.
    func colorStyle(layerID: UUID, slot: ColorSlot) -> ColorStyle? {
        guard colorStylesEnabled,
              let styleID = document?.layer(id: layerID)?.colorStyleID(for: slot) else { return nil }
        return document?.colorStyle(id: styleID)
    }

    /// The name the Save as Style field opens on: one nobody is using yet.
    var suggestedColorStyleName: String {
        document?.freshColorStyleName() ?? PhotonzDocument.colorStyleNameBase
    }

    /// The name the field opens on for ONE row: a saved ramp is offered
    /// "Gradient" rather than "Color 4", because a shelf where half the tiles
    /// called Color are gradients is a shelf nobody reads.
    func suggestedColorStyleName(slot: ColorSlot) -> String {
        let paint = colorStyleSelection(slot: slot).savablePaint ?? Paint(hex: "#000000")
        let base = PhotonzDocument.colorStyleNameBase(for: paint)
        return document?.freshColorStyleName(base: base) ?? base
    }

    /// The layers a color row speaks for: the whole multi-selection when there
    /// is one, else the one selected layer — the same set every other
    /// whole-selection command acts on. In draw order, so the row reads the
    /// same way twice running and one undo step lands the same way every time.
    var colorStyleTargetIDs: [UUID] {
        let picked = actionableLayerIDs
        guard !picked.isEmpty, let document else { return [] }
        return document.allLayers.map(\.id).filter { picked.contains($0) }
    }

    /// What the Effects and Shadow rows show: the picked layers that can be
    /// restyled, the look each of them is wearing right now, and whether they
    /// agree. One layer picked or twenty, this is the same reading, which is
    /// what lets one pull on Corner Radius round every button you picked.
    ///
    /// Preview-aware, so a slider mid-drag reads what is on the canvas rather
    /// than snapping back to what is on disk between frames.
    var layerStyleSelection: LayerStyleSelection {
        guard let document else { return LayerStyleSelection(members: [], selectionCount: 0) }
        return document.layerStyleSelection(layerIDs: colorStyleTargetIDs) { layer in
            self.previewedStyle(of: layer.id) ?? layer.style
        }
    }

    /// What the type rows show: the picked TEXT layers and what they are set
    /// in. One label picked or ten, this is the same reading, which is what
    /// lets three labels be made 14pt in one go instead of three.
    var textSelection: TextLayerSelection {
        guard let document else { return TextLayerSelection(members: [], selectionCount: 0) }
        return document.textSelection(layerIDs: colorStyleTargetIDs)
    }

    /// The same for the shape rows: the picked shapes, the settings they all
    /// have, and what those settings read across them.
    var shapeSelection: ShapeSelection {
        guard let document else { return ShapeSelection(members: [], selectionCount: 0) }
        return document.shapeSelection(layerIDs: colorStyleTargetIDs)
    }

    /// What the ONE Corner Radius row shows: how round each picked layer is
    /// right now, whichever way it rounds. A rectangle curves the outline it
    /// draws and everything else has its corners masked off, and this row
    /// speaks for both, so one pull can round a screenshot and the box drawn on
    /// top of it together.
    var cornerRadiusSelection: CornerRadiusSelection {
        guard let document = cornerReadingDocument else {
            return CornerRadiusSelection(members: [], selectionCount: 0)
        }
        return document.cornerRadiusSelection(layerIDs: colorStyleTargetIDs)
    }

    /// The document as the corner rows should READ it: the one being edited,
    /// plus whatever a corner dot being pulled on the canvas is showing. A
    /// number that says 0 over a shape that is visibly round is the row lying
    /// about the picture beside it.
    private var cornerReadingDocument: PhotonzDocument? {
        guard var document else { return nil }
        guard let preview = cornerRadiiPreview else { return document }
        document.setCornerRadii(layerIDs: preview.ids, to: preview.radii)
        return document
    }

    /// Live drag on that row: rounds every picked layer without recording an
    /// undo step, each of them the way it rounds. Pulling the ONE slider gives
    /// every corner the same number, which is what it has always meant.
    func previewCornerRadius(ids: [UUID], _ radius: CGFloat) {
        previewCornerRadii(ids: ids, CornerRadii(radius))
    }

    /// The same, with a corner of its own on each corner: what the four opened
    /// rows write.
    func previewCornerRadii(ids: [UUID], _ radii: CornerRadii) {
        guard !ids.isEmpty, var doc = document else { return }
        // This row does not go through the layer-style preview, so anything a
        // previous drag left there would be read back as the current look.
        stylePreview = nil
        discardDragPreview()
        doc.setCornerRadii(layerIDs: ids, to: radii)
        // The rows read this while the drag is in flight, so what the panel
        // says and what the canvas draws are the same number.
        cornerRadiiPreview = (ids, radii)
        submit(doc)
    }

    /// Letting go of it: ONE undo step, however many layers the pull reached,
    /// plus the corners the next rectangle you draw starts with.
    func commitCornerRadius(ids: [UUID], _ radius: CGFloat) {
        commitCornerRadii(ids: ids, CornerRadii(radius))
    }

    /// The same, corner by corner. The next rectangle you draw starts with the
    /// four you just set, so a segmented control is three shapes in a row
    /// rather than three shapes and twelve numbers.
    func commitCornerRadii(ids: [UUID], _ radii: CornerRadii) {
        guard !ids.isEmpty, let doc = document else { return }
        stylePreview = nil
        discardDragPreview()
        perform { $0.setCornerRadii(layerIDs: ids, to: radii) }
        if ids.contains(where: { doc.layer(id: $0)?.annotation?.shape == .rectangle }) {
            annotationStyles.setCornerRadii(radii, forShape: .rectangle)
            saveAnnotationStyles()
        }
        rememberStyleDefault(of: ids)
    }

    /// ONE corner of every picked layer, live, leaving its other three alone.
    func previewCornerRadius(ids: [UUID], corner: CornerRadii.Corner, _ radius: CGFloat) {
        guard !ids.isEmpty, var doc = document else { return }
        stylePreview = nil
        discardDragPreview()
        doc.setCornerRadius(layerIDs: ids, corner: corner, to: radius)
        submit(doc)
    }

    /// ...and letting go of it: ONE undo step.
    func commitCornerRadius(ids: [UUID], corner: CornerRadii.Corner, _ radius: CGFloat) {
        guard !ids.isEmpty, let doc = document else { return }
        stylePreview = nil
        discardDragPreview()
        perform { $0.setCornerRadius(layerIDs: ids, corner: corner, to: radius) }
        if let shaped = ids.first(where: { doc.layer(id: $0)?.annotation?.shape == .rectangle }),
           let radii = document?.layer(id: shaped)?.roundedCornerRadii {
            annotationStyles.setCornerRadii(radii, forShape: .rectangle)
            saveAnnotationStyles()
        }
        rememberStyleDefault(of: ids)
    }

    /// Whether anything picked can be restyled at all, which is what decides
    /// whether the Effects and Shadow sections are in the panel. A locked layer
    /// is not restylable, so a selection of nothing but locked layers brings no
    /// sections rather than rows of dead sliders — the same call the Color rows
    /// make.
    var hasRestylableSelection: Bool {
        guard let document else { return false }
        return actionableLayerIDs.contains { document.layer(id: $0)?.isLocked == false }
    }

    /// The Shadow switch: turns a shadow on for every picked layer that has
    /// none, or off for all of them, in one step. On means on EVERYWHERE, so
    /// three boxes where one is shadowed read off and one click shadows the
    /// other two rather than un-shadowing the first.
    func setSelectionShadowEnabled(_ on: Bool) {
        let ids = layerStyleSelection.layerIDs
        guard !ids.isEmpty else { return }
        setLayerStyle(ids: ids) { style in
            if on {
                // A layer that already has one keeps the shadow it tuned.
                if style.shadow == nil { style.shadow = ShadowStyle() }
            } else {
                style.shadow = nil
            }
        }
    }

    // MARK: - The Appearance list, which is a list you add to
    // MARK: - The Effects list (`next-shape-parts`)

    /// The rows the Effects list shows, one per entry, speaking for everything
    /// picked. Empty on a shape nobody has added anything to, which is the
    /// point of the split: Appearance is what a shape IS, this is what you ADD.
    var layerEffectRows: [LayerEffectRow] {
        guard let document else { return [] }
        return document.layerEffectRows(layerIDs: colorStyleTargetIDs)
    }

    /// Whether the plus can still offer this. A layer has one softness, so once
    /// there is a blur in the list the menu says so by going quiet rather than
    /// letting a second one in and then ignoring it.
    func canAddEffect(_ kind: AddableEffect) -> Bool {
        guard let document else { return false }
        let ids = layerStyleSelection.layerIDs
        guard !ids.isEmpty else { return false }
        if kind.kind.isCountable { return true }
        return ids.contains { id in
            document.layer(id: id)?.style.effects.contains { $0.kind == kind.kind } == false
        }
    }

    /// The plus: one press, one new row on every picked layer, one undo.
    func addEffect(_ kind: AddableEffect) {
        let ids = layerStyleSelection.layerIDs
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        // The rows below this one are about to shift up a place, and a fold is
        // known by its place (`foldedEffectRows`).
        forgetEffectFolds()
        perform { _ = $0.addEffect(kind, layerIDs: ids) }
        rememberStyleDefault(of: ids)
    }

    /// The cross on a row: takes that entry out of the list. Different from the
    /// eye beside it, which keeps everything about the effect and stops it
    /// drawing.
    ///
    /// Taking one away arms the tool exactly as adding one does, so the next
    /// box comes out without it. Adding already reached the tool and removing
    /// did not, which is why a blur you had just got rid of came straight back
    /// on the next rectangle (reported by the user on 2026-09-07).
    func removeEffect(row: LayerEffectRow) {
        guard !row.switchIDs.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        forgetEffectFolds()
        perform { _ = $0.removeEffect(layerIDs: row.switchIDs, at: row.index) }
        rememberStyleDefault(of: layerStyleSelection.layerIDs)
    }

    /// Whether a row could land in that place: inside the list, and not above a
    /// row that holds a fixed place.
    func canMoveEffect(row: LayerEffectRow, to target: Int) -> Bool {
        guard let document, let first = row.switchIDs.first,
              let layer = document.layer(id: first) else { return false }
        let floor = layer.style.pinnedCount
        return target >= floor && target < layer.style.effects.count && target != row.index
    }

    /// A row dragged into a different place, which is a change to what paints
    /// over what: the top of the list is nearest the eye.
    ///
    /// The order is part of the look, so it arms the tool too: leave a ring
    /// over a shadow and the next box paints them the same way round.
    func moveEffect(row: LayerEffectRow, to target: Int) {
        guard canMoveEffect(row: row, to: target) else { return }
        stylePreview = nil
        discardDragPreview()
        forgetEffectFolds()
        perform { _ = $0.moveEffect(layerIDs: row.switchIDs, from: row.index, to: target) }
        rememberStyleDefault(of: layerStyleSelection.layerIDs)
    }

    /// The eye on one entry in the list.
    ///
    /// Switching one off arms the tool as well, and because the entry keeps
    /// every number on it the next box starts with the same effect, off and
    /// ready — the same bargain the Outline switch already struck.
    func setEffectEnabled(row: LayerEffectRow, on: Bool) {
        guard !row.switchIDs.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.setEffectEnabled(layerIDs: row.switchIDs, at: row.index, on: on) }
        rememberStyleDefault(of: layerStyleSelection.layerIDs)
    }

    /// Letting a colour go on an effect whose tick is OFF: it comes back on
    /// wearing that colour, in one step one undo puts back. The same move the
    /// Outline row takes, for the same reason.
    func dropColorOnOffEffect(_ row: LayerEffectRow, landing: ColorDrop.Landing) {
        guard let document else { return }
        let ids = row.switchIDs.filter { document.layer(id: $0)?.isLocked == false }
        guard !ids.isEmpty else { return }
        guard row.kind.colorSlot != nil else { return }
        discardDragPreview()
        // Switched on AND painted in one step one undo puts back, which is what
        // the row promised while the colour was in the air. A colour that
        // arrived under a NAME lands as that name, exactly as it does on every
        // other row, so the drag is not a quieter, lossier way to do the move
        // the menu does properly.
        perform { doc in
            _ = doc.setEffectEnabled(layerIDs: ids, at: row.index, on: true)
            if let brings = landing.brings {
                _ = doc.bindColorStyle(layerIDs: ids, effectAt: row.index, styleID: brings.id)
            } else {
                _ = doc.setColorHex(layerIDs: ids, effectAt: row.index,
                                    hex: landing.paint.hex)
            }
        }
        rememberStyleDefault(of: ids)
    }

    /// The Corner Radius the Appearance panel shows: only the picked layers that
    /// HAVE corners. An ellipse has none, so it brings no row rather than a
    /// slider that does nothing to what you have picked.
    var corneredRadiusSelection: CornerRadiusSelection {
        guard let document = cornerReadingDocument else {
            return CornerRadiusSelection(members: [], selectionCount: 0)
        }
        return document.cornerRadiusSelection(layerIDs: colorStyleTargetIDs, cornersOnly: true)
    }

    /// The Kind popup on one entry: behind the layer, or cast into it.
    func setShadowKind(index: Int, ids: [UUID], to kind: ShadowKind) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.setShadowKind(layerIDs: ids, at: index, to: kind) }
        rememberStyleDefault(of: ids)
    }

    /// The Position popup on one border entry: which side of the layer's edge
    /// that ring sits on. The same question the Outline row asks in Appearance,
    /// and the thing that makes an inner border and an outer border two entries.
    func setBorderEffectPosition(at index: Int, ids: [UUID], to position: BorderPosition) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.updateBorderEffect(layerIDs: ids, at: index) { $0.position = position } }
        rememberStyleDefault(of: ids)
    }

    /// The Follows popup on one border entry: whether that ring goes round a
    /// label's letters or round the box the words sit in
    /// (`BorderFollows.swift`). Only a label is ever asked.
    func setBorderEffectFollows(at index: Int, ids: [UUID], to follows: BorderFollows) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.updateBorderEffect(layerIDs: ids, at: index) { $0.follows = follows } }
        rememberStyleDefault(of: ids)
    }

    /// Turns one glow outside the layer's edge or inside it, over every picked
    /// layer with a glow at that place. The same move the shadow's Kind makes:
    /// one effect drawn somewhere else, never a second row.
    func setGlowKind(at index: Int, ids: [UUID], to kind: GlowKind) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { _ = $0.updateGlowEffect(layerIDs: ids, at: index) { $0.kind = kind } }
        rememberStyleDefault(of: ids)
    }

    // MARK: - The parts a layer is made of (`next-shape-parts`)

    /// The rows the parts list shows: Fill, Outline, Text, Shadow, each one
    /// speaking for everything picked. The model itself lives in
    /// `PhotonzCore/LayerParts.swift`; this is just the selection it reads.
    var layerPartRows: [LayerPartRow] {
        guard let document else { return [] }
        return document.layerPartRows(layerIDs: colorStyleTargetIDs)
    }

    /// Letting a colour go on a part whose switch is OFF: the part comes on
    /// wearing that colour, in one step one undo puts back.
    ///
    /// A row that is off shows its name and its switch and nothing else, which
    /// is the point of the switch. The cost, until this, was that the colour
    /// had nowhere to land: a colour carried over from Fill was refused by the
    /// Outline row of a bare box, and the only way to a coloured edge was to
    /// find the switch, flip it, and repaint whatever came back (reported
    /// 2026-09-07). Letting go says both things at once.
    ///
    /// A colour that arrived under a NAME points the part at that name, the
    /// same way the row's own menu does, so the drag is never the quieter,
    /// lossier way to do it. The shadow keeps only the colour: its row has no
    /// saved colours to offer in the first place.
    func dropColorOnOffPart(_ row: LayerPartRow, landing: ColorDrop.Landing) {
        guard let part = row.part, let document else { return }
        let ids = row.switchIDs.filter { document.layer(id: $0)?.isLocked == false }
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { doc in
            _ = doc.turnOnPart(part, layerIDs: ids, paint: landing.paint,
                               index: row.index ?? 0)
            guard let brings = landing.brings else { return }
            for (slot, group) in Self.styleSlots(part, ids: ids, in: doc) {
                _ = doc.bindColorStyle(layerIDs: group, slot: slot, styleID: brings.id)
            }
        }
        // Armed the same way every other edit on this row is, so the next box
        // comes out the way this one was just left.
        switch part {
        case .fill:
            armToolsFromSelection(slot: .fill, targets: ids)
        case .shadow:
            rememberStyleDefault(of: ids)
        }
        recordRecentColor(hex: landing.paint.hex)
    }

    /// Which colour of each layer a part's row stands for, grouped by kind, so
    /// one Outline row over a box and a screenshot points the shape's stroke
    /// and the picture's ring at the same name. The shadow has none: its
    /// colour is not one of the layer's slots.
    private static func styleSlots(_ part: LayerPart, ids: [UUID],
                                   in doc: PhotonzDocument) -> [ColorSlot: [UUID]] {
        var slots: [ColorSlot: [UUID]] = [:]
        for id in ids {
            guard let layer = doc.layer(id: id) else { continue }
            switch part {
            case .fill: slots[.fill, default: []].append(id)
            case .shadow: break
            }
        }
        return slots
    }

    /// What one color row shows: the picked layers that have a color in this
    /// slot, what they are painted, and the style painting them when they all
    /// wear one. One layer picked or twenty, this is the same reading, which is
    /// what lets the Color section be the ONE place a color lives.
    ///
    /// Not gated on saved styles: a color still has to be readable and
    /// settable with `next-styles` off. What that flag takes away is the styles
    /// button beside the color, and `ColorStyleControl` hides itself.
    func colorStyleSelection(slot: ColorSlot) -> ColorStyleSelection {
        guard let document else {
            return ColorStyleSelection(slot: slot, members: [], selectionCount: 0)
        }
        return document.colorStyleSelection(layerIDs: colorStyleTargetIDs, slot: slot)
    }

    /// The slots the selection actually has a color in. What a style can be
    /// saved from or applied to.
    var colorStyleSlots: [ColorSlot] {
        guard let document else { return [] }
        return document.colorStyleSlots(layerIDs: colorStyleTargetIDs)
    }

    /// The rows the Color section shows, in inspector order: every slot the
    /// picked layers HAVE, whether or not there is a color in it right now. A
    /// box with its fill switched off keeps its Fill row, because that row is
    /// the way back to a fill.
    var colorRowSlots: [ColorSlot] {
        guard let document else { return [] }
        return document.colorRowSlots(layerIDs: colorStyleTargetIDs)
    }

    /// What the checkbox on a color row reads: offered only where the color can
    /// be absent at all, and on only when every layer it speaks for has one.
    func colorSwitch(slot: ColorSlot) -> ColorSwitch {
        guard let document else { return ColorSwitch(slot: slot, layerIDs: [], onCount: 0) }
        return document.colorSwitch(layerIDs: colorStyleTargetIDs, slot: slot)
    }

    /// The checkbox on a color row: switches a box's inside, or a frame's
    /// surface, on or off across everything picked, in one step.
    func setColorEnabled(slot: ColorSlot, on: Bool) {
        guard document != nil else { return }
        let targets = colorSwitch(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setColorEnabled(layerIDs: targets, slot: slot, on: on) }
        // Switching a box's inside off here arms the tool with no inside, so
        // the next box comes out an outline like the one just emptied. Same
        // rule as picking a colour on the row above it.
        armToolsFromSelection(slot: slot, targets: targets)
    }

    /// How many layers are picked, which is what the whole-selection Color
    /// section says out loud before anything is changed.
    var colorStyleSelectionCount: Int { colorStyleTargetIDs.count }

    /// "Save as Style" on a color row: takes the name typed in the little
    /// field, saves the color the picked layers share under it, and points
    /// every one of them at it. Nil when they do not share one.
    ///
    /// It also **shows the Library on the Styles shelf**, because a style you
    /// cannot see is a button that appears to do nothing. The layers stay
    /// selected, so the row you saved from is right there saying which style it
    /// is now wearing.
    @discardableResult
    func saveColorStyle(slot: ColorSlot, name: String? = nil) -> UUID? {
        guard colorStylesEnabled else { return nil }
        colorStyleNaming = nil
        let targets = colorStyleTargetIDs
        guard !targets.isEmpty else { return nil }
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.saveColorStyle(from: targets, slot: slot, name: name) }
        guard let styleID = saved else { return nil }
        // Saving points the layers you saved from at the new name, so the tool
        // that draws them comes away holding it: naming a colour and then
        // drawing the next shape in a copy of it would undo the naming.
        armToolsFromSelection(slot: slot, targets: targets, rememberingBorder: false)
        showStylesShelf()
        // The saved color is one tile among the ones already kept, so the shelf
        // scrolls to it for the same reason a new component's tile does.
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Puts the Library on screen with the Styles shelf showing, which is
    /// where a saved colour or text style is renamed, changed, or told which
    /// parts of a layer to turn up on. Saving does this, and so does a colour
    /// row whose list is empty because the saved colours are all for other
    /// parts.
    func showStylesShelf() {
        setLibraryVisible(true)
        UserDefaults.standard.set(LibraryScope.styles.rawValue, forKey: LibraryPanel.scopeKey)
    }

    /// Points every picked layer's color at a style, which paints all of them
    /// in ONE step: pick three boxes, choose Accent once, undo once.
    func useColorStyle(slot: ColorSlot, styleID: UUID) {
        guard colorStylesEnabled else { return }
        // Only a color meant for this part. The menu already offers no other,
        // so this is the belt: a walk or a stale menu cannot put a color kept
        // for hairlines on the inside of a box.
        guard document?.colorStyles(for: slot).contains(where: { $0.id == styleID }) == true
        else { return }
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.bindColorStyle(layerIDs: targets, slot: slot, styleID: styleID) }
        // The tool comes away holding the NAME, so the next shape of that kind
        // is drawn in it too and still follows it the day it is edited. A plain
        // colour on this row has always carried over; a saved one now does the
        // same thing, which is the only way the two picks mean one thing.
        armToolsFromSelection(slot: slot, targets: targets)
    }

    /// What a colour row would do with a saved colour let go of on it.
    ///
    /// A row wears names, so the only question is whether it wears THIS one:
    /// a colour kept for fills is not something to draw a hairline in, which
    /// is the same rule the row's own menu uses to decide what to offer. When
    /// it does not fit, the colour still lands and the swatch says the name
    /// stayed behind.
    func styleWelcome(slot: ColorSlot, styleID: UUID) -> ColorDrop.StyleWelcome {
        guard colorStylesEnabled else { return .neverWearsNames }
        let offered = document?.colorStyles(for: slot).contains { $0.id == styleID } ?? false
        return offered ? .wearsIt : .notThisOne
    }

    /// The saved colour the toolbar's swatch is wearing, as the thing a drag
    /// carries. The same style `toolColorStyle` reports, in the words drag and
    /// drop speaks.
    func toolSavedColor(slot: ColorSlot) -> ColorDrop.SavedColor? {
        toolColorStyle(slot: slot).map { ColorDrop.SavedColor(id: $0.id, name: $0.name) }
    }

    /// What the TOOLBAR's swatch would do with a saved colour let go of on it.
    ///
    /// With a shape picked the bar's swatch is that shape's colour, so it
    /// answers the way that shape's row does. With nothing picked it is the
    /// tool in your hand, and a tool only remembers the two colours a shape is
    /// drawn in: a text colour and a border colour are not something a tool can
    /// carry a NAME for, so there the colour lands on its own.
    func toolStyleWelcome(slot: ColorSlot, styleID: UUID) -> ColorDrop.StyleWelcome {
        guard colorStylesEnabled else { return .neverWearsNames }
        if selectedAnnotationLayer != nil { return styleWelcome(slot: slot, styleID: styleID) }
        guard let shape = activeTool.annotationShape else { return .neverWearsNames }
        switch slot {
        case .stroke: break
        case .fill: guard shape == .rectangle || shape == .ellipse else { return .neverWearsNames }
        case .text, .border, .shadow, .glow: return .neverWearsNames
        }
        return styleWelcome(slot: slot, styleID: styleID)
    }

    /// A saved colour let go of on the TOOLBAR's swatch.
    ///
    /// With a shape picked the bar's swatch is that shape's colour, so this is
    /// the row's own move. With nothing picked it is the tool in your hand, and
    /// what a tool holds is a preference rather than part of the picture: the
    /// name is armed straight, so the next shape comes out wearing it and still
    /// follows it the day the colour behind the name is edited.
    func useToolColorStyle(slot: ColorSlot, styleID: UUID) {
        guard colorStylesEnabled else { return }
        if selectedAnnotationLayer != nil {
            useColorStyle(slot: slot, styleID: styleID)
            return
        }
        guard let style = document?.colorStyle(id: styleID),
              let shape = activeTool.annotationShape else { return }
        annotationStyles.arm(style.paint(for: slot), styleID: style.id, name: style.name,
                             slot: slot, forShape: shape)
        saveAnnotationStyles()
        recordRecentColor(hex: style.paint(for: slot).hex)
    }

    /// "Unlink": every picked color stays exactly as it is, it just becomes its
    /// own layer's again, in one step.
    func unlinkColorStyle(slot: ColorSlot) {
        guard colorStylesEnabled else { return }
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        perform(reportingLinkBreaks: false) { $0.unbindColorStyle(layerIDs: targets, slot: slot) }
        // ...and the tool lets go with them, so the next shape is a colour of
        // its own like the ones just unlinked.
        armToolsFromSelection(slot: slot, targets: targets, rememberingBorder: false)
    }

    /// The color well on a whole-selection row: paints every picked layer that
    /// has this kind of color the one color chosen, in ONE step. Pick three
    /// boxes, choose a blue once, undo once.
    ///
    /// Layers wearing a style in that slot are taken off it, which the row says
    /// in words before the color is picked.
    func setSelectionColor(slot: ColorSlot, hex: String) {
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setColorHex(layerIDs: targets, slot: slot, hex: hex) }
        armToolsFromSelection(slot: slot, targets: targets)
        recordRecentColor(hex: hex)
    }

    /// Paints a slot across the selection with a whole paint — flat colour or
    /// gradient. The gradient counterpart of `setSelectionColor`, and the only
    /// way a gradient reaches the document.
    func setSelectionPaint(slot: ColorSlot, paint: Paint) {
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPaint(layerIDs: targets, slot: slot, paint: paint) }
        armToolsFromSelection(slot: slot, targets: targets)
        // The recents row is a row of colours, so a gradient leaves its flat
        // colour there rather than nothing.
        recordRecentColor(hex: paint.hex)
    }

    /// Painting a shape from the panel arms the tool that draws it, so the next
    /// shape of that kind comes out the colour just chosen — the same thing the
    /// toolbar swatch has always done, and the same thing Thickness, Corner
    /// Radius and the Effects sliders already do from this panel. Colour was
    /// the one field where picking in the two places meant two different
    /// things.
    ///
    /// Every kind of shape the pick reached is armed for itself, so painting a
    /// box and an arrow blue leaves both tools blue and the ellipse tool alone.
    /// A kind whose shapes end up disagreeing arms nothing rather than being
    /// guessed at. Read AFTER the change, so it is what the shapes are wearing
    /// now rather than what was aimed at them.
    ///
    /// `rememberingBorder` is off for the two callers that repaint nothing —
    /// saving a colour under a name, and letting go of a name. A ring rides
    /// along with the rest of a shape's remembered look, so arming it there
    /// would snapshot the shadow and the corner radius of whatever happened to
    /// be picked as the new defaults, off the back of a button that only named
    /// a colour.
    func armToolsFromSelection(slot: ColorSlot, targets: [UUID],
                                       rememberingBorder: Bool = true) {
        guard let document else { return }
        let arming = document.toolArming(layerIDs: targets, slot: slot)
        if !arming.isEmpty {
            for entry in arming {
                annotationStyles.arm(entry.paint, styleID: entry.styleID,
                                     // The name rides along with the id: what
                                     // the tool holds outlives this document,
                                     // and the moment worth speaking about is
                                     // the one where the document cannot
                                     // supply the name any more.
                                     name: entry.styleID
                                         .flatMap { document.colorStyle(id: $0)?.name },
                                     slot: slot, forShape: entry.shape)
            }
            saveAnnotationStyles()
        }
        // A ring is styling laid over a layer rather than part of the shape, so
        // it rides along with the rest of a shape's remembered look, exactly
        // the way pulling its width in the Effects section already does.
        if slot == .border, rememberingBorder { rememberStyleDefault(of: targets) }
    }

    /// What the picked layers are painted with in a slot, when they agree.
    func selectionPaint(slot: ColorSlot) -> Paint? {
        document?.sharedPaint(layerIDs: colorStyleTargetIDs, slot: slot)
    }

    /// What a colour row's chip shows: the paint in flight while a drag is
    /// happening, the document's otherwise. Without it the little swatch under
    /// the picker would sit on the old colour for a whole pull and then jump on
    /// release, while the canvas beside it had been following all along.
    func previewedPaint(slot: ColorSlot) -> Paint? {
        if let preview = paintPreview, preview.slot == slot { return preview.paint }
        return selectionPaint(slot: slot)
    }

    /// One frame of a colour drag: paints the slot across everything picked and
    /// renders it, recording nothing. Same shape as `previewLayerStyle`, and
    /// for the same reason — a live tick per frame in history would make one
    /// pull a hundred undo steps and the recents row a transcript of it.
    func previewSelectionPaint(slot: ColorSlot, paint: Paint) {
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty, var doc = document else { return }
        // A drag that has moved to a different row or a different selection is
        // a new gesture: nothing of the old one carries over, and a held drag
        // sprite would be showing the old colour.
        if paintPreview?.slot != slot || paintPreview?.ids != targets {
            stylePreview = nil
            discardDragPreview()
        }
        paintPreview = (slot, targets, paint)
        _ = doc.setPaint(layerIDs: targets, slot: slot, paint: paint)
        submit(doc)
    }

    /// Puts the canvas back on the document if a colour drag is somehow still
    /// in flight — the picker was dismissed with the pointer down, so the
    /// release that would have committed never came. Without this the canvas
    /// would keep showing a colour the document does not have until the next
    /// edit. A no-op the rest of the time, which is nearly always.
    func discardPickerPreview() {
        guard paintPreview != nil || stylePreview != nil || knobPaintPreview != nil else { return }
        paintPreview = nil
        stylePreview = nil
        knobPaintPreview = nil
        rerender()
    }

    /// Letting go of a colour drag: ONE undo step from the colour the slot had
    /// before the drag started to the one it ended on, however many layers it
    /// reached, and ONE entry in the recents row for the whole gesture.
    func commitSelectionPaint(slot: ColorSlot, paint: Paint) {
        paintPreview = nil
        setSelectionPaint(slot: slot, paint: paint)
    }

    /// Repaints a style and everything wearing it, as one undo step.
    func setColorStyleHex(styleID: UUID, hex: String) {
        setColorStylePaint(styleID: styleID, paint: Paint(hex: hex))
    }

    /// Repaints a style with a whole paint — this is how a saved gradient is
    /// edited — and everything wearing it follows, as one undo step.
    func setColorStylePaint(styleID: UUID, paint: Paint) {
        guard colorStylesEnabled else { return }
        discardDragPreview()
        perform { _ = $0.setColorStylePaint(styleID: styleID, paint: paint) }
        refreshArmedColorStyles(styleID: styleID)
        // The recents row is a row of colours, so a ramp leaves its flat colour
        // there rather than nothing.
        recordRecentColor(hex: paint.hex)
    }

    /// A tool holding a saved colour that has just been repainted has to show
    /// the new one. What the tool holds is the name; the colour it remembers
    /// beside it is only what that name stands for right now, and the toolbar
    /// swatch and the live drag preview both read that colour. Without this
    /// they would sit on the old one until the tool was armed again, so the
    /// shape you drew would not be the shape the swatch promised.
    private func refreshArmedColorStyles(styleID: UUID) {
        guard let style = document?.colorStyle(id: styleID) else { return }
        var changed = false
        for shape in AnnotationShape.allCases {
            for slot in [ColorSlot.stroke, .fill]
            where annotationStyles.colorStyleID(forShape: shape, slot: slot) == styleID {
                annotationStyles.arm(style.paint(for: slot), styleID: styleID,
                                     name: style.name, slot: slot, forShape: shape)
                changed = true
            }
        }
        if changed { saveAnnotationStyles() }
    }

    /// The Style section's Name field. One name in one place: the shelf tile
    /// and every row wearing it read the same string.
    func renameColorStyle(styleID: UUID, to name: String) {
        guard colorStylesEnabled else { return }
        perform { $0.renameColorStyle(id: styleID, to: name) }
    }

    /// Takes a style off the shelf. Nothing is repainted: every layer keeps the
    /// color it is wearing and simply owns it again.
    func deleteColorStyle(styleID: UUID) {
        guard colorStylesEnabled else { return }
        perform { $0.deleteColorStyle(id: styleID) }
        // The tool lets go of the name for the same reason every layer does:
        // it keeps the colour it is holding and simply owns it again.
        var released = false
        for shape in AnnotationShape.allCases {
            for slot in [ColorSlot.stroke, .fill]
            where annotationStyles.colorStyleID(forShape: shape, slot: slot) == styleID {
                annotationStyles.setColorStyleID(nil, slot: slot, forShape: shape)
                released = true
            }
        }
        if released { saveAnnotationStyles() }
        if selectedLibraryItemID == styleID.uuidString { selectedLibraryItemID = nil }
    }

    // MARK: - What the toolbar swatch is holding

    /// The saved colour the toolbar's swatch stands for, or nil when the colour
    /// there is just a colour.
    ///
    /// It reads the selected shape when there is one and the tool in your hand
    /// otherwise, exactly the way the swatch's colour does, so the name and the
    /// colour under it always describe the same thing. A name this document has
    /// never heard of is no name at all: what the tool holds outlives any one
    /// document, so the swatch would otherwise claim a colour nobody could find.
    func toolColorStyle(slot: ColorSlot) -> ColorStyle? {
        guard colorStylesEnabled, let document else { return nil }
        let id = selectedAnnotationLayer.map { $0.colorStyleID(for: slot) }
            ?? annotationStyles.colorStyleID(for: activeTool, slot: slot)
        guard let id else { return nil }
        return document.colorStyle(id: id)
    }

    /// Unlink, from the toolbar swatch: the colour stays exactly as it is, it
    /// just stops being a name. With a shape selected that is the same unlink
    /// the shape's own Colour row offers; with nothing selected it is the tool
    /// in your hand letting go, so the next shape is a colour of its own.
    func releaseToolColorStyle(slot: ColorSlot) {
        guard colorStylesEnabled else { return }
        if selectedAnnotationLayer != nil {
            unlinkColorStyle(slot: slot)
            return
        }
        guard let shape = activeTool.annotationShape else { return }
        annotationStyles.setColorStyleID(nil, slot: slot, forShape: shape)
        saveAnnotationStyles()
    }

    // MARK: - When the saved colour cannot come with the tool

    /// A plain colour pick that speaks up if it is standing on a name.
    ///
    /// Arming a tool with Accent and then dragging the picker underneath the
    /// Using Accent line lets go of Accent. That has always been what picking
    /// a plain colour means, and the row's tip said so, but nothing said it at
    /// the moment it happened — so the next shape came out a colour of its own
    /// while the person still thought they were drawing Accent.
    ///
    /// The answer takes the place of the Using line it just made untrue, which
    /// is the one spot the eye is already on. The canvas pill every other
    /// broken link uses cannot have this one: the picker that caused it is open
    /// over the canvas and covers the pill.
    ///
    /// Only when nothing is selected. With a shape picked, the swatch and its
    /// row are about THAT shape, and the colour it let go of is already
    /// reported by the pill (`LinkBreakReport`); saying it twice for one pick
    /// is noise.
    ///
    /// The name comes off inside `pick`, so a second pull of the same picker
    /// has nothing left to say. That is what keeps this to one showing rather
    /// than one per pick.
    func pickingPlainColor(slot: ColorSlot, _ pick: () -> Void) {
        let notice = lettingGoOfToolColorStyle(slot: slot)
        pick()
        if let notice { toolColorStyleLetGo = notice }
    }

    private func lettingGoOfToolColorStyle(slot: ColorSlot) -> ToolColorStyleNotice? {
        guard colorStylesEnabled, selectedAnnotationLayer == nil,
              let shape = activeTool.annotationShape else { return nil }
        return annotationStyles.lettingGoOfColorStyle(slot: slot, forShape: shape)
    }

    /// The way back from a name the tool has just let go of: the same colour
    /// picked up again, so a pull of the picker you did not mean costs one
    /// click rather than a trip to the Library. Undo cannot do this — what a
    /// tool holds is a preference, not part of the picture, so it was never in
    /// the history.
    func rearmToolColorStyle(_ notice: ToolColorStyleNotice) {
        guard colorStylesEnabled, let style = document?.colorStyle(id: notice.styleID) else { return }
        annotationStyles.arm(style.paint(for: notice.slot), styleID: style.id, name: style.name,
                             slot: notice.slot, forShape: notice.shape)
        saveAnnotationStyles()
        toolColorStyleLetGo = nil
    }

    /// Whether there is a way back to offer: a style this document still has.
    /// One deleted since is no way back, so the row says what happened and
    /// stops there.
    func canRearmToolColorStyle(_ notice: ToolColorStyleNotice) -> Bool {
        colorStylesEnabled && document?.colorStyle(id: notice.styleID) != nil
    }

    /// The saved colour the tool let go of in the picker open right now, for
    /// the part of the shape this row paints.
    func letGoNotice(slot: ColorSlot) -> ToolColorStyleNotice? {
        guard let notice = toolColorStyleLetGo, notice.slot == slot,
              notice.shape == activeTool.annotationShape else { return nil }
        return notice
    }

    /// Says, once, that the shape just drawn could not wear the name its tool
    /// is holding, and which part of it came out plain instead.
    ///
    /// Two things do that. This document may never have heard of the name:
    /// what a tool holds is a preference that outlives any one document and a
    /// saved colour lives INSIDE one, so drawing in another document quietly
    /// gives you the flat colour the tool remembers beside the name. Or this
    /// document has the name and keeps it for other parts, so a colour ticked
    /// back to outlines and text leaves the inside of a box plain. The tool
    /// keeps the name either way. Nothing is wrong, but it is not what the
    /// swatch promised either, so each is worth one line.
    ///
    /// Once per name per part per document, because the alternative is a pill
    /// on every shape of a run, which is how a true sentence becomes noise. The
    /// part is in the key rather than just the name, so a colour that cannot
    /// come along for two different reasons is not silently down to one of
    /// them.
    func announceArmedColorStyleLeftBehind(_ layer: Layer) {
        guard colorStylesEnabled, let document,
              let notice = document.armedColorStyleLeftBehind(layer, styles: annotationStyles),
              announcedColorStyleNotices.insert(AnnouncedColorStyleNotice(notice)).inserted
        else { return }
        raiseCanvasNotice(.toolColorStyle(notice))
    }

    /// How many of the document's colors this style paints.
    func colorStyleUsageCount(styleID: UUID) -> Int {
        document?.colorStyleUsageCount(id: styleID) ?? 0
    }

    /// "Select what uses this": the layers wearing a style become the
    /// selection, which is how the shelf answers "where is this thing?".
    func selectLayersUsingColorStyle(styleID: UUID) {
        guard let ids = document?.layersUsingColorStyle(id: styleID), !ids.isEmpty else { return }
        selectLayers(Set(ids))
    }
}

/// One sentence this window has already said about a saved colour a tool could
/// not bring with it: which colour, why, and which part of the shape.
///
/// The reason and the part are in the key beside the name because they are
/// different sentences about the same colour, and having said one must not
/// silence the other. The SHAPE is deliberately not: "Accent is not for fills"
/// is a fact about Accent, and hearing it again on the next kind of shape adds
/// nothing.
struct AnnouncedColorStyleNotice: Hashable {
    let styleID: UUID
    let kind: ToolColorStyleNotice.Kind
    let slot: ColorSlot

    init(_ notice: ToolColorStyleNotice) {
        styleID = notice.styleID
        kind = notice.kind
        slot = notice.slot
    }
}
