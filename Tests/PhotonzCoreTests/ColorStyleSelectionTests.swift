import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One color row speaking for a whole selection: pick three boxes, choose a
/// name once, and all three wear it (`docs/design/ui-building.md`, step D8).
///
/// The row has to be honest about what it is looking at. Three boxes that all
/// wear Accent say Accent; three that wear different things say Mixed, because
/// naming one of them would be a row claiming a style two of the layers under
/// it are not wearing.
struct ColorStyleSelectionTests {

    // MARK: - Fixtures

    private func box(_ name: String = "Box", fill: String? = "#3366FF",
                     stroke: String = "#101010") -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = stroke
        annotation.fillColorHex = fill
        return Layer(name: name, content: .annotation(annotation),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func text(_ name: String = "Label", color: String = "#FFFFFF") -> Layer {
        Layer(name: name, content: .text(TextContent(string: "Hi", colorHex: color)),
              frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private func member(_ id: UUID, _ hex: String, _ style: UUID? = nil)
    -> ColorStyleSelection.Member {
        ColorStyleSelection.Member(id: id, colorHex: hex, styleID: style)
    }

    // MARK: - What the row shows

    @Test func nothingPickedShowsNothing() {
        let selection = ColorStyleSelection(slot: .fill, members: [], selectionCount: 0)
        #expect(selection.reading == .empty)
        #expect(selection.isEmpty)
    }

    @Test func layersSharingOneColorShowThatColor() {
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF"), member(UUID(), "#3366FF"), member(UUID(), "#3366ff"),
        ], selectionCount: 3)
        #expect(selection.reading == .color("#3366FF"))
        #expect(selection.savableColorHex == "#3366FF")
    }

    @Test func layersWearingDifferentColorsSayMixed() {
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF"), member(UUID(), "#FF0000"),
        ], selectionCount: 2)
        #expect(selection.reading == .mixed)
        // ...and there is no single color to save under a name.
        #expect(selection.savableColorHex == nil)
    }

    @Test func layersAllWearingOneStyleNameIt() {
        let accent = UUID()
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF", accent), member(UUID(), "#3366FF", accent),
        ], selectionCount: 2)
        #expect(selection.reading == .style(accent))
        #expect(selection.boundStyleID == accent)
    }

    /// The acceptance the whole row hangs on: two different styles is Mixed,
    /// never one of the two.
    @Test func layersWearingDifferentStylesSayMixed() {
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF", UUID()), member(UUID(), "#00A870", UUID()),
        ], selectionCount: 2)
        #expect(selection.reading == .mixed)
        #expect(selection.boundStyleID == nil)
        #expect(selection.wearsAnyStyle)
    }

    /// One wearing Accent and one painted the very same blue by hand is still
    /// Mixed: they are not the same fact, and unlinking would do something to
    /// only one of them.
    @Test func aStyledLayerBesideAnUnstyledOneOfTheSameColorIsMixed() {
        let accent = UUID()
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF", accent), member(UUID(), "#3366FF"),
        ], selectionCount: 2)
        #expect(selection.reading == .mixed)
        #expect(selection.savableColorHex == nil)
    }

    // MARK: - Saying how much of the selection it reaches

    @Test func aRowSpeakingForEveryPickedLayerSaysNothingExtra() {
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF"), member(UUID(), "#3366FF"),
        ], selectionCount: 2)
        #expect(selection.note == nil)
    }

    @Test func aRowSkippingSomePickedLayersSaysSo() {
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF"),
        ], selectionCount: 3)
        #expect(selection.note == "Applies to 1 of the 3 selected layers.")
    }

    // MARK: - Reading a selection off a document

    @Test func aSlotOnlyCountsLayersThatHaveAColorInIt() {
        let filled = box("Filled")
        let hollow = box("Hollow", fill: nil)
        let doc = document([filled, hollow])
        let selection = doc.colorStyleSelection(layerIDs: [filled.id, hollow.id], slot: .fill)
        // The hollow box has a fill slot and no fill color, so a style aimed
        // at Fill must not switch its fill on behind the person's back.
        #expect(selection.layerIDs == [filled.id])
        #expect(selection.selectionCount == 2)
        #expect(selection.note == "Applies to 1 of the 2 selected layers.")
    }

    @Test func aRowSaysNothingAboutLayersThatSimplyHaveNoSuchColor() {
        // A caption has no fill. A Fill row announcing that it skipped it would
        // put three lines of small print under any mixed selection, and say
        // nothing a person did not already know.
        let shape = box()
        let label = text()
        let doc = document([shape, label])
        let fill = doc.colorStyleSelection(layerIDs: [shape.id, label.id], slot: .fill)
        #expect(fill.layerIDs == [shape.id])
        #expect(fill.selectionCount == 2)
        #expect(fill.capableCount == 1)
        #expect(fill.note == nil)
    }

    @Test func aLockedLayerStaysOutOfTheRow() {
        var locked = box("Locked")
        locked.isLocked = true
        let free = box("Free")
        let doc = document([locked, free])
        let selection = doc.colorStyleSelection(layerIDs: [locked.id, free.id], slot: .fill)
        #expect(selection.layerIDs == [free.id])
    }

    @Test func theRowsOfferedAreTheSlotsTheSelectionActuallyHas() {
        let shape = box()
        let label = text()
        let doc = document([shape, label])
        let slots = doc.colorStyleSlots(layerIDs: [shape.id, label.id])
        #expect(slots == [.fill, .stroke, .text])
    }

    @Test func aSelectionWithNoColorsAnywhereOffersNoRows() {
        let group = Layer(name: "Group", content: .group(GroupContent(children: [])), frame: .zero)
        let doc = document([group])
        #expect(doc.colorStyleSlots(layerIDs: [group.id]).isEmpty)
    }

    // MARK: - The rows the Color section shows

    @Test func aBoxWithItsFillSwitchedOffKeepsItsFillRow() {
        // The row is the only way back to a fill, so it cannot go away just
        // because there is no color in it right now.
        let empty = box("Empty", fill: nil)
        let doc = document([empty])
        #expect(doc.colorRowSlots(layerIDs: [empty.id]) == [.fill, .stroke])
        #expect(doc.colorStyleSlots(layerIDs: [empty.id]) == [.stroke])
    }

    @Test func eachKindOfLayerOffersOnlyTheRowsItHas() {
        let label = text()
        var arrowContent = AnnotationContent(shape: .arrow, start: .zero,
                                             end: CGPoint(x: 20, y: 20))
        arrowContent.colorHex = "#FF0000"
        let arrow = Layer(name: "Arrow", content: .annotation(arrowContent), frame: .zero)
        let frame = Layer.frameLayer(name: "Frame", origin: .zero,
                                     size: CGSize(width: 200, height: 200))
        let plain = Layer(name: "Group", content: .group(GroupContent(children: [])), frame: .zero)
        let doc = document([label, arrow, frame, plain])
        #expect(doc.colorRowSlots(layerIDs: [label.id]) == [.text])
        #expect(doc.colorRowSlots(layerIDs: [arrow.id]) == [.stroke])
        #expect(doc.colorRowSlots(layerIDs: [frame.id]) == [.fill])
        #expect(doc.colorRowSlots(layerIDs: [plain.id]).isEmpty)
    }

    @Test func aLockedLayerBringsNoRowsOfItsOwn() {
        var locked = box("Locked")
        locked.isLocked = true
        var arrowContent = AnnotationContent(shape: .arrow, start: .zero,
                                             end: CGPoint(x: 20, y: 20))
        arrowContent.colorHex = "#FF0000"
        let arrow = Layer(name: "Arrow", content: .annotation(arrowContent), frame: .zero)
        let doc = document([locked, arrow])
        #expect(doc.colorRowSlots(layerIDs: [locked.id]).isEmpty)
        #expect(doc.colorRowSlots(layerIDs: [locked.id, arrow.id]) == [.stroke])
    }

    // MARK: - The switch that turns a fill on and off

    @Test func theFillSwitchIsOnOnlyWhenEveryFillableLayerHasOne() {
        let filled = box("Filled")
        let empty = box("Empty", fill: nil)
        let doc = document([filled, empty])
        #expect(doc.colorSwitch(layerIDs: [filled.id], slot: .fill).isOn)
        #expect(doc.colorSwitch(layerIDs: [empty.id], slot: .fill).isOn == false)
        let both = doc.colorSwitch(layerIDs: [filled.id, empty.id], slot: .fill)
        #expect(both.isOn == false)
        #expect(both.layerIDs == [filled.id, empty.id])
    }

    @Test func onlyTheFillRowHasASwitch() {
        let shape = box()
        let label = text()
        let doc = document([shape, label])
        #expect(doc.colorSwitch(layerIDs: [shape.id], slot: .stroke).isOffered == false)
        #expect(doc.colorSwitch(layerIDs: [label.id], slot: .text).isOffered == false)
        #expect(doc.colorSwitch(layerIDs: [shape.id], slot: .fill).isOffered)
    }

    @Test func aSelectionWithNothingFillableHasNoSwitch() {
        var arrowContent = AnnotationContent(shape: .arrow, start: .zero,
                                             end: CGPoint(x: 20, y: 20))
        arrowContent.colorHex = "#FF0000"
        let arrow = Layer(name: "Arrow", content: .annotation(arrowContent), frame: .zero)
        let doc = document([arrow])
        #expect(doc.colorSwitch(layerIDs: [arrow.id], slot: .fill).isOffered == false)
    }

    @Test func switchingAFillOnSeedsItFromTheShapesOwnOutline() {
        let empty = box("Empty", fill: nil, stroke: "#123456")
        var doc = document([empty])
        let changed = doc.setColorEnabled(layerIDs: [empty.id], slot: .fill, on: true)
        #expect(changed == 1)
        #expect(doc.layer(id: empty.id)?.colorHex(for: .fill) == "#123456")
    }

    @Test func switchingAFrameOnGivesItTheDefaultSurface() {
        let frame = Layer.frameLayer(name: "Frame", origin: .zero,
                                     size: CGSize(width: 200, height: 200),
                                     backgroundHex: nil)
        var doc = document([frame])
        _ = doc.setColorEnabled(layerIDs: [frame.id], slot: .fill, on: true)
        #expect(doc.layer(id: frame.id)?.colorHex(for: .fill) == Layer.defaultFrameBackgroundHex)
    }

    @Test func switchingAFillOffClearsItAndLetsGoOfItsStyle() {
        let filled = box("Filled")
        var doc = document([filled])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#00A870")
        doc.bindColorStyle(layerIDs: [filled.id], slot: .fill, styleID: accent)
        let changed = doc.setColorEnabled(layerIDs: [filled.id], slot: .fill, on: false)
        #expect(changed == 1)
        #expect(doc.layer(id: filled.id)?.colorHex(for: .fill) == nil)
        #expect(doc.layer(id: filled.id)?.colorStyleID(for: .fill) == nil)
    }

    @Test func oneSwitchReachesEveryPickedLayerAndSkipsTheOnesAlreadyThere() {
        let filled = box("Filled")
        let a = box("A", fill: nil, stroke: "#111111")
        let b = box("B", fill: nil, stroke: "#222222")
        var doc = document([filled, a, b])
        let changed = doc.setColorEnabled(layerIDs: [filled.id, a.id, b.id], slot: .fill, on: true)
        #expect(changed == 2)
        #expect(doc.layer(id: a.id)?.colorHex(for: .fill) == "#111111")
        #expect(doc.layer(id: b.id)?.colorHex(for: .fill) == "#222222")
        #expect(doc.layer(id: filled.id)?.colorHex(for: .fill) == "#3366FF")
    }

    @Test func aLockedLayerIsNeverSwitched() {
        var locked = box("Locked", fill: nil)
        locked.isLocked = true
        var doc = document([locked])
        #expect(doc.setColorEnabled(layerIDs: [locked.id], slot: .fill, on: true) == 0)
        #expect(doc.layer(id: locked.id)?.colorHex(for: .fill) == nil)
    }

    @Test func aSlotWithNoSwitchIgnoresBeingSwitched() {
        let shape = box()
        var doc = document([shape])
        #expect(doc.setColorEnabled(layerIDs: [shape.id], slot: .stroke, on: false) == 0)
        #expect(doc.layer(id: shape.id)?.colorHex(for: .stroke) == "#101010")
    }

    // MARK: - Painting the whole selection

    @Test func oneStylePaintsEveryPickedLayer() {
        let a = box("A", fill: "#3366FF")
        let b = box("B", fill: "#FF0000")
        let c = box("C", fill: "#00FF00")
        var doc = document([a, b, c])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#00A870")
        let painted = doc.bindColorStyle(layerIDs: [a.id, b.id, c.id], slot: .fill, styleID: accent)
        #expect(painted == 3)
        for id in [a.id, b.id, c.id] {
            #expect(doc.layer(id: id)?.colorHex(for: .fill) == "#00A870")
            #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == accent)
        }
    }

    @Test func layersWithoutThatSlotAreSimplySkipped() {
        let shape = box()
        let label = text()
        var doc = document([shape, label])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#00A870")
        let painted = doc.bindColorStyle(layerIDs: [shape.id, label.id], slot: .fill,
                                         styleID: accent)
        #expect(painted == 1)
        #expect(doc.layer(id: label.id)?.colorHex(for: .text) == "#FFFFFF")
    }

    @Test func unlinkingTheSelectionKeepsEveryColorAndDropsEveryBinding() {
        let a = box("A")
        let b = box("B")
        var doc = document([a, b])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#00A870")
        doc.bindColorStyle(layerIDs: [a.id, b.id], slot: .fill, styleID: accent)
        doc.unbindColorStyle(layerIDs: [a.id, b.id], slot: .fill)
        for id in [a.id, b.id] {
            #expect(doc.layer(id: id)?.colorHex(for: .fill) == "#00A870")
            #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == nil)
        }
    }

    // MARK: - Saving what a selection shares

    @Test func savingFromASelectionNamesTheColorTheyShareAndPointsThemAllAtIt() {
        let a = box("A", fill: "#3366FF")
        let b = box("B", fill: "#3366FF")
        var doc = document([a, b])
        let saved = doc.saveColorStyle(from: [a.id, b.id], slot: .fill, name: "Accent")
        #expect(saved != nil)
        #expect(doc.colorStyle(id: saved!)?.colorHex == "#3366FF")
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .fill) == saved)
        #expect(doc.layer(id: b.id)?.colorStyleID(for: .fill) == saved)
        #expect(doc.colorStyleUsageCount(id: saved!) == 2)
    }

    @Test func savingFromLayersThatDoNotAgreeSavesNothing() {
        let a = box("A", fill: "#3366FF")
        let b = box("B", fill: "#FF0000")
        var doc = document([a, b])
        #expect(doc.saveColorStyle(from: [a.id, b.id], slot: .fill, name: "Accent") == nil)
        #expect(doc.colorStyles.isEmpty)
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .fill) == nil)
    }

    /// Saving from exactly one layer is the same call, so the button in a
    /// single layer's row and the one over a selection cannot drift apart.
    @Test func savingFromOneLayerStillWorksTheWayItAlwaysDid() {
        let a = box("A", fill: "#3366FF")
        var doc = document([a])
        let saved = doc.saveColorStyle(from: a.id, slot: .fill, name: "Accent")
        #expect(doc.colorStyle(id: saved!)?.name == "Accent")
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .fill) == saved)
    }

    // MARK: - What the whole-selection rows are called

    @Test func everySlotHasAnUnambiguousLabelForAMixedSelection() {
        // Two rows both saying "Color" is what this exists to avoid.
        let titles = ColorSlot.allCases.map(\.selectionTitle)
        #expect(titles == ["Fill", "Outline", "Text", "Border"])
        #expect(Set(titles).count == titles.count)
    }

    // MARK: - Painting a selection one one-off color

    @Test func pickingAColorPaintsEveryPickedLayerThatHasThatKindOfColor() {
        let a = box("A", fill: "#3366FF")
        let b = box("B", fill: "#FF0000")
        let c = box("C", fill: "#00FF00")
        var doc = document([a, b, c])
        let painted = doc.setColorHex(layerIDs: [a.id, b.id, c.id], slot: .fill, hex: "#123456")
        #expect(painted == 3)
        for id in [a.id, b.id, c.id] {
            #expect(doc.layer(id: id)?.colorHex(for: .fill) == "#123456")
        }
        // ...and the row that said Mixed now says the color they share.
        #expect(doc.colorStyleSelection(layerIDs: [a.id, b.id, c.id], slot: .fill).reading
                == .color("#123456"))
    }

    /// The write reaches exactly the layers the row speaks for, so what the
    /// row promises and what a pick does can never drift apart.
    @Test func paintingSkipsTheLayersTheRowItselfLeavesOut() {
        let painted = box("Painted", fill: "#3366FF")
        var locked = box("Locked", fill: "#3366FF")
        locked.isLocked = true
        let noFill = box("No fill", fill: nil)
        let ids = [painted.id, locked.id, noFill.id]
        var doc = document([painted, locked, noFill])
        #expect(doc.setColorHex(layerIDs: ids, slot: .fill, hex: "#123456") == 1)
        #expect(doc.layer(id: painted.id)?.colorHex(for: .fill) == "#123456")
        #expect(doc.layer(id: locked.id)?.colorHex(for: .fill) == "#3366FF")
        // Switched off stays switched off: painting must never turn a fill on.
        #expect(doc.layer(id: noFill.id)?.colorHex(for: .fill) == nil)
    }

    @Test func paintingReachesEverySlotItsOwnWay() {
        let shape = box("Box", fill: "#3366FF", stroke: "#101010")
        let label = text("Label", color: "#FFFFFF")
        var doc = document([shape, label])
        #expect(doc.setColorHex(layerIDs: [shape.id, label.id], slot: .stroke, hex: "#AA0000") == 1)
        #expect(doc.setColorHex(layerIDs: [shape.id, label.id], slot: .text, hex: "#00AA00") == 1)
        #expect(doc.layer(id: shape.id)?.colorHex(for: .stroke) == "#AA0000")
        #expect(doc.layer(id: label.id)?.colorHex(for: .text) == "#00AA00")
    }

    /// A color chosen by hand is the layer's own. Leaving the binding on would
    /// mean the next edit to that style silently repainted it.
    @Test func paintingByHandTakesALayerOffItsStyle() {
        let a = box("A", fill: "#3366FF")
        let b = box("B", fill: "#3366FF")
        var doc = document([a, b])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#00A870")
        doc.bindColorStyle(layerIDs: [a.id], slot: .fill, styleID: accent)
        #expect(doc.setColorHex(layerIDs: [a.id, b.id], slot: .fill, hex: "#123456") == 2)
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .fill) == nil)
        #expect(doc.layer(id: a.id)?.colorHex(for: .fill) == "#123456")
        // The style itself is untouched: nothing else wearing it moves.
        #expect(doc.colorStyle(id: accent)?.colorHex == "#00A870")
    }

    @Test func paintingNothingChangesNothing() {
        let a = box("A", fill: "#3366FF")
        var doc = document([a])
        #expect(doc.setColorHex(layerIDs: [], slot: .fill, hex: "#123456") == 0)
        #expect(doc.layer(id: a.id)?.colorHex(for: .fill) == "#3366FF")
    }

    // MARK: - Saying what a pick will do before it is picked

    @Test func aMixedRowHoldingStyledLayersWarnsThatPaintingLetsThemGo() {
        let styled = UUID()
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF", styled), member(UUID(), "#FF0000"),
        ], selectionCount: 2)
        #expect(selection.reading == .mixed)
        #expect(selection.unlinkNote == "A color picked here takes 1 of them off their style.")
    }

    @Test func aRowWithNoStyleInItSaysNothingExtra() {
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF"), member(UUID(), "#FF0000"),
        ], selectionCount: 2)
        #expect(selection.unlinkNote == nil)
    }

    /// Layers that all wear one style say nothing UNDER the row: that row is
    /// not about to lose a style by accident, because the only way to paint it
    /// by hand is to open its picker, and the picker says so itself
    /// (`styleReplacementNote`). A sentence in the panel that is true every
    /// time you look at it is a sentence nobody reads.
    @Test func aRowAllWearingOneStyleSaysNothingExtra() {
        let accent = UUID()
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#00A870", accent), member(UUID(), "#00A870", accent),
        ], selectionCount: 2)
        #expect(selection.reading == .style(accent))
        #expect(selection.unlinkNote == nil)
    }

    // MARK: - What the picker says over a colour that comes from a style

    @Test func aStyledRowsPickerSaysAPickWouldTakeItOffTheStyle() {
        let accent = UUID()
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#00A870", accent),
        ], selectionCount: 1)
        #expect(selection.styleReplacementNote == "A color picked here takes this off the style.")
    }

    @Test func aStyledRowOverSeveralLayersSaysHowManyAPickWouldTakeOff() {
        let accent = UUID()
        let selection = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#00A870", accent), member(UUID(), "#00A870", accent),
            member(UUID(), "#00A870", accent),
        ], selectionCount: 3)
        #expect(selection.styleReplacementNote
                == "A color picked here takes all 3 of them off the style.")
    }

    /// A row painted with a colour of its own has no style to lose, and a row
    /// that disagrees already says so under itself with `unlinkNote`. Saying it
    /// twice in two different places is how a warning stops meaning anything.
    @Test func aRowWithNoOneStyleSaysNothingInItsPicker() {
        let styled = UUID()
        let own = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF"),
        ], selectionCount: 1)
        let mixed = ColorStyleSelection(slot: .fill, members: [
            member(UUID(), "#3366FF", styled), member(UUID(), "#FF0000"),
        ], selectionCount: 2)
        #expect(own.styleReplacementNote == nil)
        #expect(mixed.styleReplacementNote == nil)
        #expect(mixed.unlinkNote != nil)
    }
}
