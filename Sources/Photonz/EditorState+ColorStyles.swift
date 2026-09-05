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
        showColorStyleShelf()
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Save as Style: opens the name field under that color row. The row it
    /// belongs to is the one for that slot, whatever is picked, because only
    /// one field is open at a time and the selection is what it is about.
    func beginNamingColorStyle(slot: ColorSlot) {
        guard colorStylesEnabled else { return }
        colorStyleNaming = ColorStyleNamingRequest(slot: slot)
    }

    /// Escape, or the name landing: the field closes.
    func endNamingColorStyle() {
        colorStyleNaming = nil
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
    private var colorStyleTargetIDs: [UUID] {
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
        guard let document else { return CornerRadiusSelection(members: [], selectionCount: 0) }
        return document.cornerRadiusSelection(layerIDs: colorStyleTargetIDs)
    }

    /// Live drag on that row: rounds every picked layer without recording an
    /// undo step, each of them the way it rounds.
    func previewCornerRadius(ids: [UUID], _ radius: CGFloat) {
        guard !ids.isEmpty, var doc = document else { return }
        // This row does not go through the layer-style preview, so anything a
        // previous drag left there would be read back as the current look.
        stylePreview = nil
        discardDragPreview()
        doc.setCornerRadius(layerIDs: ids, to: radius)
        submit(doc)
    }

    /// Letting go of it: ONE undo step, however many layers the pull reached,
    /// plus the corners the next rectangle you draw starts with.
    func commitCornerRadius(ids: [UUID], _ radius: CGFloat) {
        guard !ids.isEmpty, let doc = document else { return }
        stylePreview = nil
        discardDragPreview()
        perform { $0.setCornerRadius(layerIDs: ids, to: radius) }
        if ids.contains(where: { doc.layer(id: $0)?.annotation?.shape == .rectangle }) {
            annotationStyles.setCornerRadius(radius, forShape: .rectangle)
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
        showColorStyleShelf()
        // The saved color is one tile among the ones already kept, so the shelf
        // scrolls to it for the same reason a new component's tile does.
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Puts the Library on screen with the Styles shelf showing, which is
    /// where a saved color is renamed, recolored, or told which parts of a
    /// layer to turn up on. Saving does this, and so does a color row whose
    /// list is empty because the saved colors are all for other parts.
    func showColorStyleShelf() {
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
    private func armToolsFromSelection(slot: ColorSlot, targets: [UUID],
                                       rememberingBorder: Bool = true) {
        guard let document else { return }
        let arming = document.toolArming(layerIDs: targets, slot: slot)
        if !arming.isEmpty {
            for entry in arming {
                annotationStyles.arm(entry.paint, styleID: entry.styleID,
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
                                     slot: slot, forShape: shape)
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
