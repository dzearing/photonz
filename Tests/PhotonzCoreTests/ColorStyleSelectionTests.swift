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
        #expect(titles == ["Fill", "Outline", "Text"])
        #expect(Set(titles).count == titles.count)
    }
}
