import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A text treatment saved under a name, that any piece of text can wear, and
/// that re-sets everything wearing it when it is edited
/// (`docs/design/ui-building.md`, "Styles are named values layers point at").
///
/// The colour half of the same idea is `ColorStyleTests`; this is the half that
/// keeps a font, a size, a weight and a colour together as one thing.
struct TextStyleTests {

    // MARK: - Fixtures

    private func text(_ name: String = "Heading", string: String = "Hello",
                      font: String = "SF Pro", size: CGFloat = 24,
                      weight: TextWeight = .regular,
                      color: String = "#FFFFFF") -> Layer {
        Layer(name: name,
              content: .text(TextContent(string: string, fontName: font, fontSize: size,
                                         colorHex: color, weight: weight)),
              frame: CGRect(x: 0, y: 0, width: 120, height: 40))
    }

    private func box() -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: 60, y: 30))),
              frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private let heading = TextTreatment(fontName: "Georgia", fontSize: 32,
                                        weight: .bold, colorHex: "#112233")

    // MARK: - What a piece of text is set in

    @Test func aTextLayerReportsTheTreatmentItIsSetIn() {
        let layer = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        #expect(layer.textTreatment == heading)
    }

    @Test func anythingThatIsNotTextHasNoTreatment() {
        #expect(box().textTreatment == nil)
    }

    // MARK: - Saving one

    @Test func savingKeepsTheTreatmentAndPointsTheTextAtIt() {
        let layer = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var doc = document([layer])
        let id = doc.saveTextStyle(from: [layer.id], name: "Heading")
        #expect(id != nil)
        #expect(doc.textStyles.count == 1)
        #expect(doc.textStyles[0].name == "Heading")
        #expect(doc.textStyles[0].treatment == heading)
        // The point of saving is to keep using it, so the text you saved from
        // is the style's first wearer.
        #expect(doc.layer(id: layer.id)?.textStyleID == id)
    }

    @Test func savingWithNoNameMakesOneUpAndNeverRepeatsIt() {
        var doc = document([text("A"), text("B")])
        let ids = doc.layers.map(\.id)
        _ = doc.saveTextStyle(from: [ids[0]])
        _ = doc.addTextStyle(treatment: heading)
        #expect(doc.textStyles.map(\.name) == [PhotonzDocument.textStyleNameBase,
                                               "\(PhotonzDocument.textStyleNameBase) 2"])
    }

    @Test func savingFromSeveralPiecesOfTextNeedsThemToAgree() {
        let a = text("A", size: 24)
        let b = text("B", size: 48)
        var doc = document([a, b])
        let saved = doc.saveTextStyle(from: [a.id, b.id], name: "Heading")
        #expect(saved == nil)
        #expect(doc.textStyles.isEmpty)
    }

    @Test func savingFromSeveralPiecesThatAgreeDressesAllOfThem() {
        let a = text("A", font: "Georgia", size: 32, weight: .bold, color: "#112233")
        let b = text("B", font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var doc = document([a, b])
        let id = doc.saveTextStyle(from: [a.id, b.id], name: "Heading")
        #expect(doc.layer(id: a.id)?.textStyleID == id)
        #expect(doc.layer(id: b.id)?.textStyleID == id)
    }

    @Test func savingFromSomethingThatIsNotTextKeepsNothing() {
        let shape = box()
        var doc = document([shape])
        let saved = doc.saveTextStyle(from: [shape.id], name: "Heading")
        #expect(saved == nil)
        #expect(doc.textStyles.isEmpty)
    }

    // MARK: - Wearing one

    @Test func wearingAStyleSetsTheTextInIt() {
        let a = text("A", font: "Georgia", size: 32, weight: .bold, color: "#112233")
        let b = text("B")
        var doc = document([a, b])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        let dressed = doc.bindTextStyle(layerIDs: [b.id], styleID: id)
        #expect(dressed)
        #expect(doc.layer(id: b.id)?.textTreatment == heading)
        #expect(doc.layer(id: b.id)?.textStyleID == id)
        // ...and the words themselves are left alone.
        #expect(doc.layer(id: b.id)?.text?.string == "Hello")
    }

    @Test func aStyleThisDocumentDoesNotHaveIsRefused() {
        let a = text()
        var doc = document([a])
        let dressed = doc.bindTextStyle(layerIDs: [a.id], styleID: UUID())
        #expect(dressed == false)
        #expect(doc.layer(id: a.id)?.textStyleID == nil)
    }

    @Test func lettingGoKeepsTheTypeAndDropsOnlyTheName() {
        let a = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var doc = document([a])
        _ = doc.saveTextStyle(from: [a.id], name: "Heading")
        doc.unbindTextStyle(layerIDs: [a.id])
        #expect(doc.layer(id: a.id)?.textStyleID == nil)
        #expect(doc.layer(id: a.id)?.textTreatment == heading)
    }

    @Test func wearingATextStyleTakesTheColourWithIt() {
        // The text's colour was pointed at a saved colour. A text style keeps a
        // colour of its own, so two names would be claiming one colour: the
        // text style wins and the colour style is let go of.
        let a = text(color: "#FF0000")
        var doc = document([a])
        let colour = doc.addColorStyle(name: "Ink", colorHex: "#FF0000")
        let painted = doc.bindColorStyle(layerID: a.id, slot: .text, styleID: colour)
        #expect(painted)
        let styled = doc.addTextStyle(name: "Heading", treatment: heading)
        let dressed = doc.bindTextStyle(layerIDs: [a.id], styleID: styled)
        #expect(dressed)
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .text) == nil)
        #expect(doc.layer(id: a.id)?.colorHex(for: .text) == "#112233")
    }

    // MARK: - Editing one

    @Test func editingTheStyleReSetsEveryPieceOfTextWearingIt() {
        let a = text("A", font: "Georgia", size: 32, weight: .bold, color: "#112233")
        let b = text("B")
        let c = text("C")
        var doc = document([a, b, c])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        _ = doc.bindTextStyle(layerIDs: [b.id], styleID: id)
        var bigger = heading
        bigger.fontSize = 48
        let dressed = doc.setTextStyle(styleID: id, treatment: bigger)
        #expect(dressed == 2)
        #expect(doc.layer(id: a.id)?.text?.fontSize == 48)
        #expect(doc.layer(id: b.id)?.text?.fontSize == 48)
        // The one wearing nothing is untouched.
        #expect(doc.layer(id: c.id)?.text?.fontSize == 24)
    }

    @Test func editingAStyleNobodyWearsChangesTheStyleAndNothingElse() {
        var doc = document([text()])
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var bigger = heading
        bigger.fontSize = 48
        let dressed = doc.setTextStyle(styleID: id, treatment: bigger)
        #expect(dressed == 0)
        #expect(doc.textStyle(id: id)?.treatment.fontSize == 48)
    }

    @Test func renamingLeavesEverythingWearingItAlone() {
        let a = text()
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        doc.renameTextStyle(id: id, to: "Title")
        #expect(doc.textStyle(id: id)?.name == "Title")
        #expect(doc.layer(id: a.id)?.textStyleID == id)
    }

    @Test func aBlankNameIsRefusedRatherThanLeavingANamelessTile() {
        let a = text()
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        doc.renameTextStyle(id: id, to: "   ")
        #expect(doc.textStyle(id: id)?.name == "Heading")
    }

    @Test func takingAStyleOffTheShelfNeverReSetsAnything() {
        let a = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        doc.deleteTextStyle(id: id)
        #expect(doc.textStyles.isEmpty)
        #expect(doc.layer(id: a.id)?.textStyleID == nil)
        #expect(doc.layer(id: a.id)?.textTreatment == heading)
    }

    // MARK: - What the shelf says about one

    @Test func theShelfSaysHowMuchOfTheDocumentLeansOnAStyle() {
        let a = text("A")
        let b = text("B")
        var doc = document([a, b])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        #expect(doc.textStyleUsageCount(id: id) == 1)
        _ = doc.bindTextStyle(layerIDs: [b.id], styleID: id)
        #expect(doc.textStyleUsageCount(id: id) == 2)
        #expect(doc.layersUsingTextStyle(id: id) == [a.id, b.id])
    }

    @Test func aStyleGetsATileOfItsOwnOnTheStylesShelf() {
        let a = text("A")
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        let entries = doc.textStyleLibraryEntries
        #expect(entries.count == 1)
        #expect(entries[0].id == id.uuidString)
        #expect(entries[0].scope == .styles)
        #expect(entries[0].name == "Heading")
        #expect(entries[0].detail == "1 use")
    }

    // MARK: - The claim staying true

    @Test func textSetSomeOtherWayQuietlyLetsGoOfTheName() {
        let a = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        doc.updateLayer(id: a.id) { $0 = TextBuilder.restyled(layer: $0, fontSize: 12) }
        let broke = doc.reconcileTextStyles()
        #expect(broke == 1)
        #expect(doc.layer(id: a.id)?.textStyleID == nil)
        #expect(doc.layer(id: a.id)?.text?.fontSize == 12)
        // Unchanged text keeps its name however many times this runs.
        _ = doc.bindTextStyle(layerIDs: [a.id], styleID: id)
        let again = doc.reconcileTextStyles()
        let twice = doc.reconcileTextStyles()
        #expect(again == 0)
        #expect(twice == 0)
    }

    @Test func aNameThisDocumentNoLongerHasLetsGoToo() {
        let a = text()
        var doc = document([a])
        _ = doc.saveTextStyle(from: [a.id], name: "Heading")
        doc.textStyles.removeAll()
        let broke = doc.reconcileTextStyles()
        #expect(broke == 1)
        #expect(doc.layer(id: a.id)?.textStyleID == nil)
    }

    @Test func aDocumentWithNoTextStylesReconcilesToNothing() {
        var doc = document([text()])
        let broke = doc.reconcileTextStyles()
        #expect(broke == 0)
    }

    // MARK: - Saying so out loud

    @Test func textThatStoppedFollowingItsStyleIsReportedLikeAColourThatDid() {
        let a = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var history = History(document: document([a]))
        history.perform { _ = $0.saveTextStyle(from: [a.id], name: "Heading") }
        let report = history.perform {
            $0.updateLayer(id: a.id) { $0 = TextBuilder.restyled(layer: $0, fontSize: 12) }
        }
        #expect(report.linkBreaks.breaks.count == 1)
        #expect(report.linkBreaks.breaks[0].kind == .textStyle)
        #expect(report.linkBreaks.breaks[0].source == "Heading")
        #expect(report.linkBreaks.detail == "1 piece of text no longer follows Heading")
        #expect(history.current.layer(id: a.id)?.textStyleID == nil)
    }

    @Test func takingTheStyleOffTheShelfIsNotAnAppLoggedBreak() {
        // Remove already means "this text is its own now", and the app
        // repeating your own command back at you is not news.
        let a = text()
        var history = History(document: document([a]))
        history.perform { _ = $0.saveTextStyle(from: [a.id], name: "Heading") }
        let id = history.current.textStyles[0].id
        let report = history.perform { $0.deleteTextStyle(id: id) }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func swappingOneStyleForAnotherIsAChoiceRatherThanABreak() {
        let a = text()
        var history = History(document: document([a]))
        history.perform { _ = $0.saveTextStyle(from: [a.id], name: "Heading") }
        history.perform { _ = $0.addTextStyle(name: "Caption", treatment: heading) }
        let other = history.current.textStyles[1].id
        let report = history.perform { _ = $0.bindTextStyle(layerIDs: [a.id], styleID: other) }
        #expect(report.linkBreaks.isEmpty)
        #expect(history.current.layer(id: a.id)?.textStyleID == other)
    }

    // MARK: - On disk

    @Test func aDocumentWithNoTextStylesWritesExactlyWhatItAlwaysWrote() throws {
        let doc = document([text()])
        let data = try JSONEncoder().encode(doc)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("textStyles"))
        #expect(!json.contains("textStyleID"))
    }

    @Test func aSavedStyleSurvivesARoundTrip() throws {
        let a = text(font: "Georgia", size: 32, weight: .bold, color: "#112233")
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.textStyle(id: id)?.name == "Heading")
        #expect(back.textStyle(id: id)?.treatment == heading)
        #expect(back.layer(id: a.id)?.textStyleID == id)
    }

    // MARK: - What the Style row speaks for

    @Test func oneHeadingWearingAStyleReadsAsThatStyle() {
        let a = text()
        var doc = document([a])
        let id = doc.saveTextStyle(from: [a.id], name: "Heading")!
        let row = doc.textStyleSelection(layerIDs: [a.id])
        #expect(row.reading == .style(id))
        #expect(row.boundStyleID == id)
        #expect(row.savableTreatment == nil)
        #expect(row.note == nil)
    }

    @Test func textThatAgreesAndWearsNoNameOffersItselfToBeSaved() {
        let a = text("A", font: "Georgia", size: 32, weight: .bold, color: "#112233")
        let b = text("B", font: "Georgia", size: 32, weight: .bold, color: "#112233")
        let doc = document([a, b])
        let row = doc.textStyleSelection(layerIDs: [a.id, b.id])
        #expect(row.reading == .own(heading))
        #expect(row.savableTreatment == heading)
        #expect(row.unlinkNote == nil)
    }

    @Test func textThatDisagreesSaysSoRatherThanNamingOneOfThem() {
        let a = text("A", size: 24)
        let b = text("B", size: 48)
        let doc = document([a, b])
        let row = doc.textStyleSelection(layerIDs: [a.id, b.id])
        #expect(row.reading == .mixed)
        #expect(row.boundStyleID == nil)
        #expect(row.savableTreatment == nil)
    }

    @Test func oneWearingAStyleAndOneNotIsMixedAndSaysWhatAPickWouldCost() {
        let a = text("A")
        let b = text("B")
        var doc = document([a, b])
        _ = doc.saveTextStyle(from: [a.id], name: "Heading")
        let row = doc.textStyleSelection(layerIDs: [a.id, b.id])
        #expect(row.reading == .mixed)
        #expect(row.wearsAnyStyle)
        #expect(row.unlinkNote == "Changing the font, size, weight or colour takes 1 of them off their style.")
    }

    @Test func theRowSaysWhenTheSelectionHoldsThingsThatAreNotText() {
        let a = text("A")
        let shape = box()
        let doc = document([a, shape])
        let row = doc.textStyleSelection(layerIDs: [a.id, shape.id])
        #expect(row.count == 1)
        #expect(row.note == "Applies to 1 of the 2 selected layers.")
    }

    @Test func lockedTextSitsOutTheRowEntirely() {
        var a = text("A")
        a.isLocked = true
        let doc = document([a])
        #expect(doc.textStyleSelection(layerIDs: [a.id]).isEmpty)
    }

    @Test func aStyledRowSaysWhatSettingTheTypeByHandWouldCost() {
        let a = text()
        var doc = document([a])
        _ = doc.saveTextStyle(from: [a.id], name: "Heading")
        let row = doc.textStyleSelection(layerIDs: [a.id])
        #expect(row.unlinkNote == "Changing the font, size, weight or colour takes this off the style.")
    }
}
