import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Copying a layer and pasting it used to leave two rows reading exactly the
/// same word, while duplicating that very layer already produced "Hero banner
/// copy" — so the two ways of making a copy disagreed. A pasted layer is now
/// named the way a duplicate is, and only when there is something to tell it
/// apart from.
@Suite("A pasted layer takes a free name")
struct PastedLayerNamingTests {

    private func leaf(_ name: String) -> Layer {
        let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        return Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func doc(_ names: String...) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: names.map { leaf($0) })
    }

    private func taken(_ doc: PhotonzDocument) -> Set<String> {
        Set(doc.allLayers.map(\.name))
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    // MARK: The copy is tellable apart

    @Test func pastingOverTheLayerItCameFromGainsTheCopyWord() {
        let d = doc("Hero banner")
        #expect(LayerNaming.pastedName(of: "Hero banner", taken: taken(d)) == "Hero banner copy")
    }

    @Test func pastingAnAppNamedLayerTakesTheNextNumber() {
        let d = doc("Rectangle")
        #expect(LayerNaming.pastedName(of: "Rectangle", taken: taken(d)) == "Rectangle 2")
    }

    @Test func pastingTheSameLayerTwiceGivesTwoDifferentNames() {
        var d = doc("Hero banner")
        let first = LayerNaming.pastedName(of: "Hero banner", taken: taken(d))
        d.addLayer(leaf(first))
        let second = LayerNaming.pastedName(of: "Hero banner", taken: taken(d))
        #expect(first == "Hero banner copy")
        #expect(second == "Hero banner copy 2")
        #expect(Set([first, second, "Hero banner"]).count == 3)
    }

    // MARK: Nothing is renamed until there is something to tell apart

    @Test func pastingIntoADocumentThatHasNoSuchNameKeepsIt() {
        let d = doc("Sidebar")
        #expect(LayerNaming.pastedName(of: "Hero banner", taken: taken(d)) == "Hero banner")
    }

    @Test func pastingIntoAnEmptyDocumentKeepsTheName() {
        #expect(LayerNaming.pastedName(of: "Hero banner", taken: []) == "Hero banner")
    }

    @Test func copyingACopyNeverStacksTheWordUp() {
        let d = doc("Hero banner", "Hero banner copy")
        #expect(LayerNaming.pastedName(of: "Hero banner copy", taken: taken(d)) == "Hero banner copy 2")
    }

    // MARK: The two ways of making a copy agree

    @Test func aPastedNameMatchesWhatDuplicatingThatLayerWouldCallIt() {
        for name in ["Hero banner", "Rectangle", "Hero banner copy", "Screenshot 10.30.45"] {
            var d = doc(name, "Sidebar")
            let pasted = LayerNaming.pastedName(of: name, taken: taken(d))
            let duplicated = d.duplicateLayer(id: id(d, name))?.name
            #expect(pasted == duplicated, "paste and duplicate disagree on \(name)")
        }
    }

    @Test func theLayerThatWasAlreadyThereKeepsItsName() {
        var d = doc("Hero banner")
        d.addLayer(leaf(LayerNaming.pastedName(of: "Hero banner", taken: taken(d))))
        #expect(d.layers.map(\.name) == ["Hero banner", "Hero banner copy"])
    }
}
