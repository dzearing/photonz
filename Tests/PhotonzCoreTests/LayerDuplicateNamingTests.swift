import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Duplicating a layer twice used to leave two rows reading exactly the same
/// word, so the only way to tell them apart was to click each one and watch the
/// canvas. A copy takes a free name instead: one the app named itself is
/// numbered the way a second drawn shape is, and one a person named keeps their
/// word and gains "copy".
@Suite("A copy takes a free name")
struct LayerDuplicateNamingTests {

    private func leaf(_ name: String, _ frame: CGRect = CGRect(x: 0, y: 0, width: 40, height: 20)) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func doc(_ names: String...) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: names.map { leaf($0) })
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func names(_ doc: PhotonzDocument) -> [String] { doc.layers.map(\.name) }

    // MARK: A name the app wrote is numbered

    @Test func aCopyOfAnAppNamedLayerTakesTheNextNumber() {
        var d = doc("Rectangle")
        let copy = d.duplicateLayer(id: id(d, "Rectangle"))
        #expect(copy?.name == "Rectangle 2")
        #expect(names(d) == ["Rectangle", "Rectangle 2"])
    }

    @Test func duplicatingTheSameLayerTwiceGivesTwoDifferentNames() {
        var d = doc("Rectangle")
        let source = id(d, "Rectangle")
        d.duplicateLayer(id: source)
        d.duplicateLayer(id: source)
        #expect(Set(names(d)).count == 3)
        #expect(Set(names(d)) == ["Rectangle", "Rectangle 2", "Rectangle 3"])
    }

    @Test func aCopySkipsNumbersAlreadyInUse() {
        var d = doc("Rectangle", "Rectangle 2")
        let copy = d.duplicateLayer(id: id(d, "Rectangle"))
        #expect(copy?.name == "Rectangle 3")
    }

    // MARK: A name a person typed is kept

    @Test func aCopyOfAPersonNamedLayerKeepsTheirWord() {
        var d = doc("Submit button")
        let copy = d.duplicateLayer(id: id(d, "Submit button"))
        #expect(copy?.name == "Submit button copy")
    }

    @Test func aSecondCopyOfAPersonNamedLayerIsNumbered() {
        var d = doc("Submit button")
        let source = id(d, "Submit button")
        d.duplicateLayer(id: source)
        d.duplicateLayer(id: source)
        #expect(names(d) == ["Submit button", "Submit button copy 2", "Submit button copy"])
    }

    @Test func copyingACopyDoesNotStackTheWordCopy() {
        var d = doc("Card")
        let copy = d.duplicateLayer(id: id(d, "Card"))
        #expect(copy?.name == "Card copy")
        let second = d.duplicateLayer(id: id(d, "Card copy"))
        #expect(second?.name == "Card copy 2")
        let third = d.duplicateLayer(id: id(d, "Card copy 2"))
        #expect(third?.name == "Card copy 3")
    }

    // MARK: Every way of duplicating agrees

    @Test func duplicatingAWholeSelectionNamesEveryCopy() {
        var d = doc("Rectangle", "Ellipse", "Card")
        let copies = d.duplicateLayers(ids: [id(d, "Rectangle"), id(d, "Ellipse"), id(d, "Card")])
        #expect(Set(copies.map(\.name)) == ["Rectangle 2", "Ellipse 2", "Card copy"])
        #expect(Set(names(d)).count == 6)
    }

    @Test func optionDraggingACopyNamesItTheSameWay() {
        var d = doc("Rectangle", "Card")
        let made = d.duplicateLayers(movingCopiesTo: [id(d, "Rectangle"): CGPoint(x: 100, y: 100),
                                                      id(d, "Card"): CGPoint(x: 200, y: 200)])
        #expect(Set(made.compactMap { d.layer(id: $0)?.name }) == ["Rectangle 2", "Card copy"])
    }

    @Test func aCopyInsideAGroupAvoidsNamesUsedAnywhereElse() {
        var d = doc("Rectangle")
        let group = d.groupLayers(ids: [id(d, "Rectangle")], name: "Card")
        #expect(group != nil)
        let copy = d.duplicateLayer(id: id(d, "Rectangle"))
        #expect(copy?.name == "Rectangle 2")
        #expect(d.layer(id: id(d, "Card"))?.children.map(\.name) == ["Rectangle", "Rectangle 2"])
    }

    @Test func duplicatingAGroupNumbersTheGroupAndLeavesItsInsidesAlone() {
        var d = doc("Rectangle")
        guard let group = d.groupLayers(ids: [id(d, "Rectangle")], name: "Group") else {
            Issue.record("could not group"); return
        }
        let copy = d.duplicateLayer(id: group.id)
        #expect(copy?.name == "Group 2")
        #expect(copy?.children.map(\.name) == ["Rectangle"])
    }

    // MARK: Undo

    @Test func undoPutsTheNamesBack() {
        let before = doc("Rectangle", "Card")
        var history = History(document: before)
        history.perform { $0.duplicateLayers(ids: [$0.layers[0].id, $0.layers[1].id]) }
        #expect(Set(history.current.layers.map(\.name)).count == 4)
        history.undo()
        #expect(history.current == before)
    }

    // MARK: The naming rule on its own

    @Test func aCopyNameIsBuiltFromTheSourceName() {
        #expect(LayerNaming.copyName(of: "Rectangle", taken: ["Rectangle"]) == "Rectangle 2")
        #expect(LayerNaming.copyName(of: "Rectangle 4", taken: ["Rectangle 4"]) == "Rectangle")
        #expect(LayerNaming.copyName(of: "Card", taken: ["Card"]) == "Card copy")
        #expect(LayerNaming.copyName(of: "Card copy 7", taken: ["Card copy 7"]) == "Card copy")
        #expect(LayerNaming.copyName(of: "copy", taken: ["copy"]) == "copy copy")
    }
}
