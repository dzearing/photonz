import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the one line under the layers list says when the selection reaches
/// further than the rows on screen.
struct LayersSelectionSummaryTests {

    private func leaf(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)),
              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    private func group(_ name: String, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)), frame: .zero)
    }

    private func copy(_ name: String, of componentID: UUID, _ children: [Layer]) -> Layer {
        Layer(name: name,
              content: .group(GroupContent(children: children, instanceOf: componentID)),
              frame: .zero)
    }

    private func component(_ name: String, id componentID: UUID, _ children: [Layer]) -> Layer {
        Layer(name: name,
              content: .group(GroupContent(children: children, componentID: componentID)),
              frame: .zero)
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: layers)
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func ids(_ document: PhotonzDocument, _ names: [String]) -> Set<UUID> {
        Set(document.allLayers.filter { names.contains($0.name) }.map(\.id))
    }

    // MARK: - Nothing is inside a copy

    @Test func aPlainSelectionSaysWhatItAlwaysSaid() {
        let document = doc([leaf("One"), leaf("Two"), leaf("Three")])
        let summary = document.layersSelectionSummary(picked: ids(document, ["One", "Two"]))
        #expect(summary.count == 2)
        #expect(summary.insideCopies == 0)
        #expect(summary.text == "2 layers selected")
    }

    @Test func layersInsideAnOrdinaryGroupAreNotInsideACopy() {
        let document = doc([group("Card", [leaf("Label"), leaf("Dot")])])
        let summary = document.layersSelectionSummary(picked: ids(document, ["Label", "Dot"]))
        #expect(summary.insideCopies == 0)
        #expect(summary.text == "2 layers selected")
    }

    @Test func fewerThanTwoPickedSaysNothingAtAll() {
        let componentID = UUID()
        let document = doc([copy("Copy", of: componentID, [leaf("Piece")])])
        #expect(document.layersSelectionSummary(picked: []).text == nil)
        #expect(document.layersSelectionSummary(picked: ids(document, ["Piece"])).text == nil)
    }

    // MARK: - The case this was filed from

    @Test func piecesInsideACopyAreCountedAndSaidOutLoud() {
        let componentID = UUID()
        let document = doc([
            component("Component", id: componentID, [leaf("Rectangle"), leaf("Rectangle 2")]),
            copy("Component 2", of: componentID, [leaf("Piece"), leaf("Piece 2")]),
        ])
        let summary = document.layersSelectionSummary(
            picked: ids(document, ["Rectangle", "Rectangle 2", "Piece", "Piece 2"]))
        #expect(summary.count == 4)
        #expect(summary.insideCopies == 2)
        #expect(summary.copiesReached == 1)
        #expect(summary.text == "4 layers selected, 2 inside a copy")
    }

    @Test func theCopyItselfHasARowSoItIsNotCountedAsInsideOne() {
        let componentID = UUID()
        let document = doc([
            leaf("Loose"),
            copy("Copy", of: componentID, [leaf("Piece")]),
        ])
        let summary = document.layersSelectionSummary(picked: ids(document, ["Loose", "Copy"]))
        #expect(summary.insideCopies == 0)
        #expect(summary.text == "2 layers selected")
    }

    @Test func piecesInTwoCopiesSayCopies() {
        let componentID = UUID()
        let document = doc([
            leaf("Loose"),
            copy("Copy", of: componentID, [leaf("Piece")]),
            copy("Copy 2", of: componentID, [leaf("Piece 2")]),
        ])
        let summary = document.layersSelectionSummary(picked: ids(document, ["Loose", "Piece", "Piece 2"]))
        #expect(summary.insideCopies == 2)
        #expect(summary.copiesReached == 2)
        #expect(summary.text == "3 layers selected, 2 inside copies")
    }

    @Test func everythingPickedInsideOneCopyReadsAsAll() {
        let componentID = UUID()
        let document = doc([copy("Copy", of: componentID, [leaf("Piece"), leaf("Piece 2")])])
        let summary = document.layersSelectionSummary(picked: ids(document, ["Piece", "Piece 2"]))
        #expect(summary.count == 2)
        #expect(summary.insideCopies == 2)
        #expect(summary.text == "2 layers selected, all inside a copy")
    }

    // MARK: - Awkward shapes

    @Test func aPieceBuriedDeepInsideACopyStillCounts() {
        let componentID = UUID()
        let document = doc([
            leaf("Loose"),
            leaf("Loose 2"),
            copy("Copy", of: componentID, [group("Row", [leaf("Deep")])]),
        ])
        let summary = document.layersSelectionSummary(picked: ids(document, ["Loose", "Loose 2", "Deep"]))
        #expect(summary.insideCopies == 1)
        #expect(summary.text == "3 layers selected, 1 inside a copy")
    }

    @Test func aCopyInsideACopyIsCountedOnceAgainstTheCopyYouCanSee() {
        let outer = UUID()
        let inner = UUID()
        let document = doc([
            leaf("Loose"),
            copy("Copy", of: outer, [copy("Inner", of: inner, [leaf("Piece")])]),
        ])
        let summary = document.layersSelectionSummary(picked: ids(document, ["Loose", "Inner", "Piece"]))
        // The inner copy has no row either: only the outermost copy does.
        #expect(summary.insideCopies == 2)
        #expect(summary.copiesReached == 1)
        #expect(summary.text == "3 layers selected, 2 inside a copy")
    }

    @Test func anIdTheDocumentHasNeverHeardOfIsStillCountedAsPicked() {
        let document = doc([leaf("One"), leaf("Two")])
        var picked = ids(document, ["One", "Two"])
        picked.insert(UUID())
        let summary = document.layersSelectionSummary(picked: picked)
        #expect(summary.count == 3)
        #expect(summary.insideCopies == 0)
    }
}
