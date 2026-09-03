import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Step D8: a color saved under a name, that any layer can point at, and that
/// repaints everything pointing at it when it is edited
/// (`docs/design/ui-building.md`, "Styles are named values layers point at").
struct ColorStyleTests {

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

    // MARK: - The slots a layer offers

    @Test func aBoxOffersItsInteriorAndItsInk() {
        #expect(box().colorSlots == [.fill, .stroke])
    }

    @Test func aLineOffersOnlyItsInk() {
        let line = Layer(name: "Line",
                         content: .annotation(AnnotationContent(shape: .line, start: .zero,
                                                                end: CGPoint(x: 10, y: 10))),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(line.colorSlots == [.stroke])
    }

    @Test func textOffersItsInk() {
        #expect(text().colorSlots == [.text])
    }

    @Test func aFrameOffersItsSurfaceAndAnOrdinaryGroupOffersNothing() {
        let frame = Layer(name: "Screen",
                          content: .group(GroupContent(children: [], isFrame: true,
                                                       backgroundHex: "#FFFFFF")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(frame.colorSlots == [.fill])
        let group = Layer(name: "Group", content: .group(GroupContent(children: [])),
                          frame: .zero)
        #expect(group.colorSlots.isEmpty)
    }

    @Test func aSlotReadsTheColorThatIsThere() {
        #expect(box(fill: "#AABBCC", stroke: "#112233").colorHex(for: .fill) == "#AABBCC")
        #expect(box(fill: "#AABBCC", stroke: "#112233").colorHex(for: .stroke) == "#112233")
        #expect(box(fill: nil).colorHex(for: .fill) == nil)
        #expect(text(color: "#00FF00").colorHex(for: .text) == "#00FF00")
        #expect(text().colorHex(for: .fill) == nil)
    }

    // MARK: - Saving a color as a style

    @Test func savingAFillMakesAStyleAndPointsTheLayerAtIt() {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        let styleID = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")
        #expect(styleID != nil)
        #expect(doc.colorStyles.count == 1)
        #expect(doc.colorStyles[0].name == "Accent")
        #expect(doc.colorStyles[0].colorHex == "#3366FF")
        #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == styleID)
    }

    @Test func savingASlotWithNoColorInItSavesNothing() {
        var doc = document([box(fill: nil)])
        #expect(doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Accent") == nil)
        #expect(doc.colorStyles.isEmpty)
    }

    @Test func aSavedStyleIsNamedForYouWhenYouSayNothing() {
        var doc = document([box(), box()])
        _ = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill)
        _ = doc.saveColorStyle(from: doc.layers[1].id, slot: .stroke)
        #expect(doc.colorStyles.map(\.name) == ["Color", "Color 2"])
    }

    @Test func aBlankNameFallsBackToTheMadeUpOne() {
        var doc = document([box()])
        _ = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "   ")
        #expect(doc.colorStyles[0].name == "Color")
    }

    // MARK: - Pointing a layer at a style

    @Test func aLayerCanBeSetToUseAStyleAndTakesItsColor() {
        var doc = document([box(fill: "#3366FF"), box(fill: "#FF0000")])
        let first = doc.layers[0].id, second = doc.layers[1].id
        let styleID = doc.saveColorStyle(from: first, slot: .fill, name: "Accent")!
        let bound = doc.bindColorStyle(layerID: second, slot: .fill, styleID: styleID)
        #expect(bound)
        #expect(doc.layer(id: second)?.colorHex(for: .fill) == "#3366FF")
        #expect(doc.layer(id: second)?.colorStyleID(for: .fill) == styleID)
    }

    @Test func aStyleCannotBeBoundToASlotTheLayerDoesNotHave() {
        var doc = document([box(), text()])
        let styleID = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Accent")!
        let boundToNothing = doc.bindColorStyle(layerID: doc.layers[1].id, slot: .stroke, styleID: styleID)
        #expect(boundToNothing == false)
        #expect(doc.layer(id: doc.layers[1].id)?.colorStyleID(for: .stroke) == nil)
    }

    @Test func aStyleThatIsNotThereCannotBeBound() {
        var doc = document([box()])
        let boundToGhost = doc.bindColorStyle(layerID: doc.layers[0].id, slot: .fill, styleID: UUID())
        #expect(boundToGhost == false)
    }

    @Test func unlinkingKeepsTheColorItIsWearing() {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        _ = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")
        doc.unbindColorStyle(layerID: id, slot: .fill)
        #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == nil)
        #expect(doc.layer(id: id)?.colorHex(for: .fill) == "#3366FF")
        #expect(doc.colorStyles.count == 1)
    }

    // MARK: - Editing a style

    @Test func editingAStyleRepaintsEveryLayerUsingIt() {
        var doc = document([box(fill: "#3366FF"), box(fill: "#FF0000"), text(color: "#3366FF")])
        let ids = doc.layers.map(\.id)
        let styleID = doc.saveColorStyle(from: ids[0], slot: .fill, name: "Accent")!
        _ = doc.bindColorStyle(layerID: ids[1], slot: .fill, styleID: styleID)
        _ = doc.bindColorStyle(layerID: ids[2], slot: .text, styleID: styleID)

        let repainted = doc.setColorStyleHex(styleID: styleID, hex: "#00FF88")
        #expect(repainted == 3)
        #expect(doc.layer(id: ids[0])?.colorHex(for: .fill) == "#00FF88")
        #expect(doc.layer(id: ids[1])?.colorHex(for: .fill) == "#00FF88")
        #expect(doc.layer(id: ids[2])?.colorHex(for: .text) == "#00FF88")
        #expect(doc.colorStyle(id: styleID)?.colorHex == "#00FF88")
    }

    @Test func editingAStyleIsOneUndoStep() {
        var history = History(document: document([box(fill: "#3366FF"), box(fill: "#3366FF")]))
        let ids = history.current.layers.map(\.id)
        var styleID: UUID?
        history.perform { doc in
            styleID = doc.saveColorStyle(from: ids[0], slot: .fill, name: "Accent")
            _ = doc.bindColorStyle(layerID: ids[1], slot: .fill, styleID: styleID!)
        }
        history.perform { _ = $0.setColorStyleHex(styleID: styleID!, hex: "#00FF88") }
        #expect(history.current.layers.allSatisfy { $0.colorHex(for: .fill) == "#00FF88" })

        history.undo()
        #expect(history.current.layers.allSatisfy { $0.colorHex(for: .fill) == "#3366FF" })
        #expect(history.current.colorStyle(id: styleID!)?.colorHex == "#3366FF")
    }

    @Test func repaintingReachesInsideGroups() {
        var doc = document([box(fill: "#3366FF")])
        let inner = doc.layers[0].id
        let group = doc.groupLayers(ids: [inner], name: "Group")!
        _ = group
        let styleID = doc.saveColorStyle(from: inner, slot: .fill, name: "Accent")!
        let repainted = doc.setColorStyleHex(styleID: styleID, hex: "#123456")
        #expect(repainted == 1)
        #expect(doc.layer(id: inner)?.colorHex(for: .fill) == "#123456")
    }

    @Test func renamingAStyleKeepsItsColorAndItsUsers() {
        var doc = document([box()])
        let styleID = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Accent")!
        doc.renameColorStyle(id: styleID, to: "Brand")
        #expect(doc.colorStyle(id: styleID)?.name == "Brand")
        doc.renameColorStyle(id: styleID, to: "  ")
        #expect(doc.colorStyle(id: styleID)?.name == "Brand")
        #expect(doc.layer(id: doc.layers[0].id)?.colorStyleID(for: .fill) == styleID)
    }

    @Test func deletingAStyleLeavesEveryLayerPaintedAsItWas() {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        let styleID = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")!
        _ = doc.setColorStyleHex(styleID: styleID, hex: "#00FF88")
        doc.deleteColorStyle(id: styleID)
        #expect(doc.colorStyles.isEmpty)
        #expect(doc.layer(id: id)?.colorHex(for: .fill) == "#00FF88")
        #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == nil)
    }

    // MARK: - Counting the users

    @Test func aStyleSaysHowManyLayersWearIt() {
        var doc = document([box(), box(), text()])
        let ids = doc.layers.map(\.id)
        let styleID = doc.saveColorStyle(from: ids[0], slot: .fill, name: "Accent")!
        #expect(doc.colorStyleUsageCount(id: styleID) == 1)
        _ = doc.bindColorStyle(layerID: ids[1], slot: .fill, styleID: styleID)
        _ = doc.bindColorStyle(layerID: ids[1], slot: .stroke, styleID: styleID)
        #expect(doc.colorStyleUsageCount(id: styleID) == 3)
    }

    @Test func theShelfListsEveryStyleWithItsColorAndItsUse() {
        var doc = document([box(fill: "#3366FF")])
        let styleID = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Accent")!
        let entries = doc.colorStyleLibraryEntries
        #expect(entries.count == 1)
        #expect(entries[0].id == styleID.uuidString)
        #expect(entries[0].scope == .styles)
        #expect(entries[0].name == "Accent")
        #expect(entries[0].detail == "1 use")
        doc.unbindColorStyle(layerID: doc.layers[0].id, slot: .fill)
        #expect(doc.colorStyleLibraryEntries[0].detail == "not used yet")
    }

    // MARK: - A layer wearing no style behaves exactly as before

    @Test func aDocumentWithNoStylesIsUntouchedByEveryStyleCall() {
        let plain = document([box(), text()])
        var doc = plain
        _ = doc.setColorStyleHex(styleID: UUID(), hex: "#000000")
        doc.renameColorStyle(id: UUID(), to: "Nope")
        doc.deleteColorStyle(id: UUID())
        doc.unbindColorStyle(layerID: doc.layers[0].id, slot: .fill)
        let broken = doc.reconcileColorStyles()
        #expect(broken == 0)
        #expect(doc == plain)
    }

    // MARK: - The safety net: a color changed by hand lets go of its style

    @Test func aColorChangedBehindTheStylesBackLetsGoOfTheStyle() {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        let styleID = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")!
        doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some("#FF0000")) }
        let broke = doc.reconcileColorStyles()
        #expect(broke == 1)
        #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == nil)
        #expect(doc.layer(id: id)?.colorHex(for: .fill) == "#FF0000")
        #expect(doc.colorStyle(id: styleID)?.colorHex == "#3366FF")
    }

    @Test func aSlotEmptiedOfItsColorLetsGoOfTheStyle() {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        _ = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")
        doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some(nil)) }
        let broke = doc.reconcileColorStyles()
        #expect(broke == 1)
        #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == nil)
    }

    @Test func aStyleThatIsGoneLetsGoOfEveryLayerPointingAtIt() {
        var doc = document([box()])
        let id = doc.layers[0].id
        _ = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")
        doc.colorStyles = []
        let broke = doc.reconcileColorStyles()
        #expect(broke == 1)
        #expect(doc.layer(id: id)?.colorStyleID(for: .fill) == nil)
    }

    @Test func historyRunsTheSafetyNetSoARowNeverClaimsAStyleItIsNotWearing() {
        var history = History(document: document([box(fill: "#3366FF")]))
        let id = history.current.layers[0].id
        history.perform { _ = $0.saveColorStyle(from: id, slot: .fill, name: "Accent") }
        history.perform { doc in
            doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some("#FF0000")) }
        }
        #expect(history.current.layer(id: id)?.colorStyleID(for: .fill) == nil)
    }

    // MARK: - Copies of a component follow a style edit

    @Test func editingAStyleRepaintsEveryCopyOfAComponentUsingIt() {
        var doc = document([box(fill: "#3366FF")])
        let inner = doc.layers[0].id
        let group = doc.groupLayers(ids: [inner], name: "Button")!
        let componentID = doc.makeComponent(id: group.id)!
        let styleID = doc.saveColorStyle(from: inner, slot: .fill, name: "Accent")!
        var history = History(document: doc)
        history.perform { _ = $0.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200)) }
        history.perform { _ = $0.setColorStyleHex(styleID: styleID, hex: "#00FF88") }

        let copy = history.current.instances(of: componentID).first
        #expect(copy != nil)
        #expect(copy?.children.first?.colorHex(for: .fill) == "#00FF88")
        #expect(copy?.children.first?.colorStyleID(for: .fill) == styleID)
    }

    // MARK: - What is written to disk

    @Test func aDocumentWithNoStylesEncodesExactlyAsItAlwaysDid() throws {
        let doc = document([box(), text()])
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(doc)) as? [String: Any]
        #expect(json?.keys.contains("colorStyles") == false)
        let layers = json?["layers"] as? [[String: Any]]
        #expect(layers?[0].keys.contains("colorStyleBindings") == false)
    }

    @Test func stylesAndBindingsSurviveASaveAndLoad() throws {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        let styleID = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")!
        let round = try JSONDecoder().decode(PhotonzDocument.self,
                                             from: try JSONEncoder().encode(doc))
        #expect(round == doc)
        #expect(round.colorStyle(id: styleID)?.name == "Accent")
        #expect(round.layer(id: id)?.colorStyleID(for: .fill) == styleID)
    }

    /// A document written before styles existed carries neither key. Stripping
    /// them from a fresh one is the same payload, and it has to decode.
    @Test func aDocumentSavedBeforeStylesExistedStillOpens() throws {
        var doc = document([box(fill: "#3366FF"), text()])
        _ = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Accent")
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(doc)) as! [String: Any]
        json.removeValue(forKey: "colorStyles")
        json["layers"] = (json["layers"] as! [[String: Any]]).map { layer -> [String: Any] in
            var stripped = layer
            stripped.removeValue(forKey: "colorStyleBindings")
            return stripped
        }
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let opened = try JSONDecoder().decode(PhotonzDocument.self, from: legacy)
        #expect(opened.colorStyles.isEmpty)
        #expect(opened.layers.count == 2)
        #expect(opened.layers[0].colorStyleID(for: .fill) == nil)
        #expect(opened.layers[0].colorHex(for: .fill) == "#3366FF")
    }

    // MARK: - Copying a layer keeps what it points at

    @Test func aDuplicatedLayerStillPointsAtTheStyle() {
        var doc = document([box(fill: "#3366FF")])
        let id = doc.layers[0].id
        let styleID = doc.saveColorStyle(from: id, slot: .fill, name: "Accent")!
        let copy = doc.layer(id: id)!.duplicated(offsetBy: CGPoint(x: 10, y: 10))
        #expect(copy.colorStyleID(for: .fill) == styleID)
    }
}
