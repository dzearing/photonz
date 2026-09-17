import Foundation
import PhotonzCore

/// Every colour row question and answer, asked of a `ColorTarget` rather than
/// of one slot.
///
/// A row that paints one kind of colour hands straight through to the
/// slot-shaped call it always made, so nothing about the Fill row, the Text row
/// or the toolbar swatches changes. A row painting two — the Outline row over a
/// rectangle and a screenshot — fans out over both and lands as ONE undo step,
/// which is the whole promise of merging the two rows into one: pick a colour
/// once, undo once, and the shape gets its stroke while the picture gets its
/// ring.
extension EditorState {

    /// The same row, over the layers it reaches RIGHT NOW.
    ///
    /// Every question below asks this first, and so does every paint, so a
    /// colour row the panel skipped over a click behaves exactly like one it
    /// rebuilt: it was handed the NAME of the row it edits, not the layers that
    /// happened to be picked when it was drawn (`ColorTarget.Source`).
    ///
    /// A row whose part has left the panel altogether reaches nothing rather
    /// than keeping hold of layers nobody has picked any more.
    func resolved(_ target: ColorTarget) -> ColorTarget {
        guard case .partRow(let id) = target.source else { return target }
        guard let row = layerPartRows.first(where: { $0.id == id }), !row.colors.isEmpty else {
            return ColorTarget(emptying: target)
        }
        return ColorTarget(target, layers: row.colors)
    }

    /// The picked layers one colour of a row reaches.
    private func reach(_ part: ColorTarget.Part) -> [UUID] {
        part.layerIDs ?? colorStyleTargetIDs
    }

    /// What the row shows: what the layers it speaks for are painted, and the
    /// style painting them when they all wear one.
    ///
    /// The count of picked layers is the WHOLE selection whichever way the row
    /// reaches, so "Applies to 1 of the 2 selected layers" still counts the
    /// layers a person picked rather than the ones the row happened to claim.
    func colorStyleSelection(_ rowTarget: ColorTarget) -> ColorStyleSelection {
        let target = resolved(rowTarget)
        guard let document else {
            return ColorStyleSelection(slot: target.lead, members: [], selectionCount: 0)
        }
        let all = colorStyleTargetIDs
        if let place = target.effectIndex {
            return document.colorStyleSelection(layerIDs: reach(target.parts[0]), effectAt: place)
        }
        var members: [ColorStyleSelection.Member] = []
        var capable = 0
        for part in target.parts {
            let one = document.colorStyleSelection(layerIDs: reach(part), slot: part.slot)
            members += one.members
            capable += one.capableCount
        }
        return ColorStyleSelection(slot: target.lead, members: members,
                                   selectionCount: all.count, capableCount: capable)
    }

    /// Which layers take which colour when this row is painted. Empty parts are
    /// dropped, so a screenshot with no ring does not turn one on behind the
    /// person's back.
    private func work(_ rowTarget: ColorTarget) -> [(slot: ColorSlot, ids: [UUID])] {
        let target = resolved(rowTarget)
        guard let document else { return [] }
        return target.parts.compactMap { part in
            let ids = document.colorStyleSelection(layerIDs: reach(part), slot: part.slot).layerIDs
            return ids.isEmpty ? nil : (part.slot, ids)
        }
    }

    /// The saved colours this row offers. Every slot a row holds shares a style
    /// role today — a shape's stroke and a picture's ring are both ink — so the
    /// lead's list is the list.
    func colorStyles(for target: ColorTarget) -> [ColorStyle] {
        colorStyles(for: target.lead)
    }

    /// ...and the colours it can paint with but cannot wear the name of, for
    /// the same reason and out of the same slot (`BorrowedColors.swift`).
    func borrowedColors(for target: ColorTarget) -> [BorrowedColor] {
        borrowedColors(for: target.lead)
    }

    /// Paints the whole row with one of those, in one step, wearing no name.
    func useBorrowedColor(_ target: ColorTarget, styleID: UUID) {
        guard colorStylesEnabled,
              let borrowed = document?.borrowedColor(id: styleID, for: target.lead) else { return }
        // Painting a row takes it off any name it was following, in the same
        // step, exactly as picking a plain colour does: `setPaint` unbinds
        // before it paints, so this is ONE undo and the row never claims to
        // follow a colour it is no longer painted.
        setSelectionPaint(target, paint: borrowed.paint)
    }

    /// What the row's layers are painted with, when they agree.
    func selectionPaint(_ rowTarget: ColorTarget) -> Paint? {
        let target = resolved(rowTarget)
        if let place = target.effectIndex {
            return document?.sharedPaint(layerIDs: reach(target.parts[0]), effectAt: place)
        }
        guard target.isSplit else { return selectionPaint(slot: target.lead) }
        let members = colorStyleSelection(target).members
        guard let first = members.first?.paint else { return nil }
        return members.dropFirst().allSatisfy { $0.paint.draws(sameAs: first) } ? first : nil
    }

    /// What the row's chip shows: the paint in flight while a drag is
    /// happening, the document's otherwise.
    func previewedPaint(_ target: ColorTarget) -> Paint? {
        if let preview = paintPreview, preview.slot == target.lead,
           target.effectIndex == nil { return preview.paint }
        return selectionPaint(target)
    }

    /// One frame of a colour drag over the row, recording nothing.
    func previewSelectionPaint(_ rowTarget: ColorTarget, paint: Paint) {
        let target = resolved(rowTarget)
        if let place = target.effectIndex {
            let ids = colorStyleSelection(target).layerIDs
            guard !ids.isEmpty else { return }
            previewLayerStyle(ids: ids) { $0.updateEffect(at: place) { $0.colorHex = paint.hex } }
            return
        }
        guard target.isSplit else {
            previewSelectionPaint(slot: target.lead, paint: paint)
            return
        }
        let work = work(target)
        guard !work.isEmpty, var doc = document else { return }
        let ids = work.flatMap(\.ids)
        if paintPreview?.slot != target.lead || paintPreview?.ids != ids {
            stylePreview = nil
            discardDragPreview()
        }
        paintPreview = (target.lead, ids, paint)
        for one in work { _ = doc.setPaint(layerIDs: one.ids, slot: one.slot, paint: paint) }
        submit(doc)
    }

    /// Letting go of a colour: ONE undo step over every layer the row speaks
    /// for, whichever of its colours each of them wears.
    func commitSelectionPaint(_ target: ColorTarget, paint: Paint) {
        paintPreview = nil
        setSelectionPaint(target, paint: paint)
    }

    /// Paints the row across everything it reaches, in one step.
    func setSelectionPaint(_ rowTarget: ColorTarget, paint: Paint) {
        let target = resolved(rowTarget)
        if let place = target.effectIndex {
            let ids = colorStyleSelection(target).layerIDs
            guard !ids.isEmpty else { return }
            discardDragPreview()
            perform { _ = $0.setPaint(layerIDs: ids, effectAt: place, paint: paint) }
            recordRecentColor(hex: paint.hex)
            return
        }
        guard target.isSplit else {
            setSelectionPaint(slot: target.lead, paint: paint)
            return
        }
        let work = work(target)
        guard !work.isEmpty else { return }
        discardDragPreview()
        perform { doc in
            for one in work { _ = doc.setPaint(layerIDs: one.ids, slot: one.slot, paint: paint) }
        }
        for one in work { armToolsFromSelection(slot: one.slot, targets: one.ids) }
        recordRecentColor(hex: paint.hex)
    }

    /// Points the row at a saved colour, in one step.
    func useColorStyle(_ rowTarget: ColorTarget, styleID: UUID) {
        let target = resolved(rowTarget)
        if let place = target.effectIndex {
            let ids = colorStyleSelection(target).layerIDs
            guard !ids.isEmpty else { return }
            discardDragPreview()
            perform { _ = $0.bindColorStyle(layerIDs: ids, effectAt: place, styleID: styleID) }
            return
        }
        guard target.isSplit else {
            useColorStyle(slot: target.lead, styleID: styleID)
            return
        }
        for one in work(target) { useColorStyle(slot: one.slot, styleID: styleID) }
    }

    /// Every colour on the row stays exactly as it is and becomes its own
    /// layer's again.
    func unlinkColorStyle(_ rowTarget: ColorTarget) {
        let target = resolved(rowTarget)
        if let place = target.effectIndex {
            let ids = colorStyleSelection(target).layerIDs
            guard !ids.isEmpty else { return }
            perform(reportingLinkBreaks: false) {
                $0.unbindColorStyle(layerIDs: ids, effectAt: place)
            }
            return
        }
        guard target.isSplit else {
            unlinkColorStyle(slot: target.lead)
            return
        }
        for one in work(target) { unlinkColorStyle(slot: one.slot) }
    }

    /// What a saved colour would do to this row if it landed on it.
    func styleWelcome(_ target: ColorTarget, styleID: UUID) -> ColorDrop.StyleWelcome {
        styleWelcome(slot: target.lead, styleID: styleID)
    }

    /// The Color row under an effect, or nil for one that paints no colour.
    func effectColorTarget(_ row: LayerEffectRow) -> ColorTarget? { ColorTarget(effect: row) }

    /// The name the Save as Style field opens on.
    func suggestedColorStyleName(_ rowTarget: ColorTarget) -> String {
        let target = resolved(rowTarget)
        guard target.isSplit || target.effectIndex != nil else {
            return suggestedColorStyleName(slot: target.lead)
        }
        let paint = colorStyleSelection(target).savablePaint ?? Paint(hex: "#000000")
        let base = PhotonzDocument.colorStyleNameBase(for: paint)
        return document?.freshColorStyleName(base: base) ?? base
    }

    /// "Save as Style" on the row: keeps what its layers share under a name and
    /// points every one of them at it, whichever colour each one wears.
    @discardableResult
    func saveColorStyle(_ rowTarget: ColorTarget, name: String? = nil) -> UUID? {
        let target = resolved(rowTarget)
        if let place = target.effectIndex {
            guard colorStylesEnabled else { return nil }
            // The field closes whether or not a style comes of it, exactly as
            // it does on every other row: leaving it open under a row that is
            // already wearing the name it just made is a field asking a
            // question that has been answered.
            colorStyleNaming = nil
            let ids = colorStyleSelection(target).layerIDs
            guard !ids.isEmpty else { return nil }
            discardDragPreview()
            var saved: UUID?
            perform { saved = $0.saveColorStyle(from: ids, effectAt: place, name: name) }
            return saved
        }
        guard target.isSplit else { return saveColorStyle(slot: target.lead, name: name) }
        guard let styleID = saveColorStyle(slot: target.lead, name: name) else { return nil }
        for one in work(target) where one.slot != target.lead {
            useColorStyle(slot: one.slot, styleID: styleID)
        }
        return styleID
    }
}
