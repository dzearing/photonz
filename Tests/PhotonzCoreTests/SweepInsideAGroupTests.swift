import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A rubber band reads the level you are working on. Once you have stepped
/// inside a group, the band sweeps that group's own pieces — the same list a
/// click at that level picks from — instead of reaching past them and grabbing
/// whole layers off the top of the document
/// (`docs/design/ui-building.md`, "A sweep picks at the level you are on").
@Suite("A sweep picks at the level you are on")
struct SweepInsideAGroupTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    private func group(_ name: String, at origin: CGPoint, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: origin, size: .zero))
    }

    /// Canvas 400×400. "Back" covers it. "Button" is anchored at (50, 60) and
    /// holds Box at local (0, 0), Label at local (8, 50) and a nested group
    /// "Badge" at local (0, 80) holding one Dot. In canvas coordinates that is
    /// Box (50, 60, 100×40), Label (58, 110, 60×20), Badge (50, 140, 20×20).
    private func makeTree() -> PhotonzDocument {
        let badge = group("Badge", at: CGPoint(x: 0, y: 80),
                          [leaf("Dot", CGRect(x: 0, y: 0, width: 20, height: 20))])
        let button = group("Button", at: CGPoint(x: 50, y: 60), [
            leaf("Box", CGRect(x: 0, y: 0, width: 100, height: 40)),
            leaf("Label", CGRect(x: 8, y: 50, width: 60, height: 20)),
            badge,
        ])
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                               layers: [leaf("Back", CGRect(x: 0, y: 0, width: 400, height: 400)),
                                        button])
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func names(_ doc: PhotonzDocument, _ ids: [UUID]) -> [String] {
        ids.compactMap { doc.layer(id: $0)?.name }
    }

    private var wholeCanvas: CGRect { CGRect(x: 0, y: 0, width: 400, height: 400) }

    // MARK: - Inside a group

    @Test func aSweepInsideAGroupPicksThatGroupsOwnPieces() {
        let doc = makeTree()
        let band = CGRect(x: 40, y: 50, width: 120, height: 90) // round Box and Label only
        let picked = doc.layerIDs(fullyInside: band, inside: id(doc, "Button"))
        #expect(names(doc, picked) == ["Box", "Label"])
    }

    @Test func aSweepInsideAGroupNeverReachesPastItToTheTopLevel() {
        let doc = makeTree()
        let picked = doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Button"))
        #expect(names(doc, picked) == ["Box", "Label", "Badge"])
    }

    @Test func aNestedGroupIsTakenWholeAndNeverHalfItsContents() {
        let doc = makeTree()
        let band = CGRect(x: 40, y: 130, width: 60, height: 40) // round Badge alone
        let picked = doc.layerIDs(fullyInside: band, inside: id(doc, "Button"))
        #expect(names(doc, picked) == ["Badge"])
        #expect(!doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Button"))
            .contains(id(doc, "Dot")))
    }

    @Test func aSweepInsideAGroupSkipsAPieceThatOnlyPartlyFits() {
        let doc = makeTree()
        let band = CGRect(x: 40, y: 50, width: 90, height: 90) // cuts Box in half
        #expect(names(doc, doc.layerIDs(fullyInside: band, inside: id(doc, "Button"))) == ["Label"])
    }

    @Test func aSweepInsideAGroupLeavesHiddenAndLockedPiecesAlone() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Box")) { $0.isVisible = false }
        doc.updateLayer(id: id(doc, "Label")) { $0.isLocked = true }
        let picked = doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Button"))
        #expect(names(doc, picked) == ["Badge"])
    }

    @Test func steppingIntoTheNestedGroupPicksItsOwnPiece() {
        let doc = makeTree()
        let picked = doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Badge"))
        #expect(names(doc, picked) == ["Dot"])
    }

    // MARK: - Everywhere else, nothing changes

    @Test func withNoGroupToBeInsideASweepWorksExactlyAsItDid() {
        let doc = makeTree()
        let picked = doc.layerIDs(fullyInside: wholeCanvas, inside: nil)
        #expect(names(doc, picked) == ["Back", "Button"])
        #expect(picked == doc.layerIDs(fullyInside: wholeCanvas))
    }

    @Test func aContextThatIsNotAGroupSweepsTheTopLevel() {
        let doc = makeTree()
        let expected = doc.layerIDs(fullyInside: wholeCanvas)
        #expect(doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Back")) == expected)
        #expect(doc.layerIDs(fullyInside: wholeCanvas, inside: UUID()) == expected)
    }

    @Test func aCopyIsOneObjectSoItsInsidesAreNeverSwept() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Button")) { layer in
            guard var copy = layer.group else { return }
            copy.instanceOf = UUID()
            layer.content = .group(copy)
        }
        let expected = doc.layerIDs(fullyInside: wholeCanvas)
        #expect(doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Button")) == expected)
    }

    @Test func anEmptyBandPicksNothingAtAnyLevel() {
        let doc = makeTree()
        #expect(doc.layerIDs(fullyInside: .zero, inside: id(doc, "Button")).isEmpty)
    }

    // MARK: - A screen cuts off what leaves it

    @Test func aScreenNeverHandsOverWhatItCutsOff() {
        let onIt = leaf("Header", CGRect(x: 10, y: 10, width: 50, height: 20))
        let offIt = leaf("Spilled", CGRect(x: 10, y: 300, width: 50, height: 20))
        let screen = Layer(name: "Screen",
                           content: .group(GroupContent(children: [onIt, offIt], isFrame: true)),
                           frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [screen])
        let picked = doc.layerIDs(fullyInside: wholeCanvas, inside: id(doc, "Screen"))
        #expect(names(doc, picked) == ["Header"])
    }

    // MARK: - ⇧ adds within the same group

    @Test func aShiftSweepInsideAGroupAddsOnlyThatGroupsPieces() {
        let doc = makeTree()
        let band = CGRect(x: 40, y: 100, width: 120, height: 40) // round Label only
        let picked = BareCanvasPress.spares
            .selection(afterSweeping: doc.layerIDs(fullyInside: band, inside: id(doc, "Button")),
                       startingFrom: [id(doc, "Box")])
        #expect(picked == Set([id(doc, "Box"), id(doc, "Label")]))
    }
}
