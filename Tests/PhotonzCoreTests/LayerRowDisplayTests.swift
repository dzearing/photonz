import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the layers panel draws for each row, gathered in one walk. The panel
/// used to ask the document for a layer once per row, which searches the whole
/// tree, so a long list cost the square of its own length to draw.
struct LayerRowDisplayTests {

    private func leaf(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)),
              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    private func group(_ name: String, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)), frame: .zero)
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: layers)
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    // MARK: - The same rows the panel already showed

    @Test func rowsMatchThePanelRowsInOrderAndShape() {
        let document = doc([group("Card", [leaf("Label"), leaf("Box")]), leaf("Top")])
        let card = id(document, "Card")
        let plain = document.panelRows(expanded: [card])
        let display = document.layerRows(expanded: [card], selected: [])
        #expect(display.map(\.row) == plain)
        #expect(display.map(\.name) == ["Top", "Card", "Box", "Label"])
        #expect(display.map(\.id) == plain.map(\.id))
    }

    @Test func rowCarriesWhatItsOwnControlsDraw() {
        var hidden = leaf("Hidden")
        hidden.isVisible = false
        var locked = leaf("Locked")
        locked.isLocked = true
        let document = doc([hidden, locked])
        let rows = document.layerRows(expanded: [], selected: [])
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        #expect(byName["Hidden"]?.isVisible == false)
        #expect(byName["Hidden"]?.isLocked == false)
        #expect(byName["Locked"]?.isLocked == true)
        #expect(byName["Locked"]?.isVisible == true)
    }

    @Test func onlySelectedRowsSayTheyAreSelected() {
        let document = doc([leaf("One"), leaf("Two"), leaf("Three")])
        let two = id(document, "Two")
        let rows = document.layerRows(expanded: [], selected: [two])
        #expect(rows.filter(\.isSelected).map(\.name) == ["Two"])
    }

    // MARK: - Why it exists: a click that changes one row changes one row

    @Test func movingTheSelectionLeavesEveryUntouchedRowEqual() {
        let document = doc((1...20).map { leaf("Layer \($0)") })
        let before = document.layerRows(expanded: [], selected: [id(document, "Layer 3")])
        let after = document.layerRows(expanded: [], selected: [id(document, "Layer 9")])
        let changed = zip(before, after).filter { $0 != $1 }.map(\.0.name)
        #expect(changed.sorted() == ["Layer 3", "Layer 9"])
    }

    @Test func aRowIsEqualToItselfAcrossTwoReads() {
        let document = doc([group("Card", [leaf("Label")]), leaf("Top")])
        let card = id(document, "Card")
        #expect(document.layerRows(expanded: [card], selected: [card])
                == document.layerRows(expanded: [card], selected: [card]))
    }

    // MARK: - Component marks and the rasterize item

    @Test func componentFactsRideAlongWithTheRow() {
        var document = doc([group("Button", [leaf("Label")]), leaf("Picture")])
        _ = document.makeComponent(id: id(document, "Button"))
        let rows = document.layerRows(expanded: [], selected: [])
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        #expect(byName["Button"]?.isMainComponent == true)
        #expect(byName["Button"]?.isComponentInstance == false)
        #expect(byName["Picture"]?.isMainComponent == false)
        #expect(byName["Picture"]?.isRasterizable == document.layer(id: id(document, "Picture"))?.isRasterizable)
    }

    // MARK: - A closed group hides its contents here too

    @Test func closedGroupContributesOneRow() {
        let document = doc([group("Card", [leaf("Label"), leaf("Box")])])
        let rows = document.layerRows(expanded: [], selected: [])
        #expect(rows.map(\.name) == ["Card"])
        #expect(rows[0].row.childCount == 2)
    }
}
