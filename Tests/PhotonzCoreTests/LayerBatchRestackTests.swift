import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Layers menu's arrange and duplicate commands over a multi-selection:
/// every selected layer moves together, gaps between them survive, nothing
/// passes the locked Background, and the stack never gains a spurious change.
@Suite("Batch restack & duplicate")
struct LayerBatchRestackTests {

    /// Bottom → top: a locked Background, then A, B, C, D.
    private func makeDocument() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.addLayer(Layer(name: "Background", content: .text(TextContent(string: "bg")),
                           frame: CGRect(x: 0, y: 0, width: 100, height: 100), isLocked: true))
        for name in ["A", "B", "C", "D"] {
            doc.addLayer(Layer(name: name, content: .text(TextContent(string: name)),
                               frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        }
        return doc
    }

    private func ids(_ doc: PhotonzDocument, _ names: String...) -> Set<UUID> {
        Set(doc.layers.filter { names.contains($0.name) }.map(\.id))
    }

    private func names(_ doc: PhotonzDocument) -> [String] { doc.layers.map(\.name) }

    // MARK: Bring to Front / Send to Back

    @Test func toFrontLiftsTheSelectionAsOneBlockKeepingItsOrder() {
        var doc = makeDocument()
        let changed = doc.restackLayers(ids: ids(doc, "A", "C"), .toFront)
        #expect(changed)
        #expect(names(doc) == ["Background", "B", "D", "A", "C"])
    }

    @Test func toBackStopsOnTheLockedBackground() {
        var doc = makeDocument()
        let changed = doc.restackLayers(ids: ids(doc, "B", "D"), .toBack)
        #expect(changed)
        #expect(names(doc) == ["Background", "B", "D", "A", "C"])
    }

    @Test func toFrontIsANoOpWhenTheSelectionAlreadyTopsTheStack() {
        var doc = makeDocument()
        let changed = doc.restackLayers(ids: ids(doc, "C", "D"), .toFront)
        #expect(!changed)
        #expect(names(doc) == ["Background", "A", "B", "C", "D"])
    }

    // MARK: Bring Forward / Send Backward

    @Test func forwardMovesEachSelectedLayerUpOneAndKeepsTheGap() {
        var doc = makeDocument()
        let changed = doc.restackLayers(ids: ids(doc, "A", "C"), .forward)
        #expect(changed)
        #expect(names(doc) == ["Background", "B", "A", "D", "C"])
    }

    @Test func forwardMovesAContiguousBlockTogether() {
        var doc = makeDocument()
        doc.restackLayers(ids: ids(doc, "A", "B"), .forward)
        #expect(names(doc) == ["Background", "C", "A", "B", "D"])
    }

    @Test func forwardHoldsTheWholeSelectionWhenItsTopIsAlreadyOnTop() {
        // Photoshop: the block presses against the top and nothing reorders.
        var doc = makeDocument()
        let changed = doc.restackLayers(ids: ids(doc, "C", "D"), .forward)
        #expect(!changed)
        #expect(names(doc) == ["Background", "A", "B", "C", "D"])
    }

    @Test func forwardWithAGapStillMovesTheLowerLayerWhenTheUpperIsPinned() {
        var doc = makeDocument()
        doc.restackLayers(ids: ids(doc, "B", "D"), .forward)
        #expect(names(doc) == ["Background", "A", "C", "B", "D"])
    }

    @Test func backwardMovesEachSelectedLayerDownOneAndKeepsTheGap() {
        var doc = makeDocument()
        doc.restackLayers(ids: ids(doc, "B", "D"), .backward)
        #expect(names(doc) == ["Background", "B", "A", "D", "C"])
    }

    @Test func backwardNeverPassesTheLockedBackground() {
        var doc = makeDocument()
        let changed = doc.restackLayers(ids: ids(doc, "A", "B"), .backward)
        #expect(!changed)
        #expect(names(doc) == ["Background", "A", "B", "C", "D"])
    }

    @Test func backwardWithAGapMovesTheUpperWhenTheLowerRestsOnTheFloor() {
        var doc = makeDocument()
        doc.restackLayers(ids: ids(doc, "A", "C"), .backward)
        #expect(names(doc) == ["Background", "A", "C", "B", "D"])
    }

    // MARK: Locked members and unknown ids

    @Test func lockedMembersStayPutAndUnknownIdsAreIgnored() {
        var doc = makeDocument()
        var selection = ids(doc, "Background", "C")
        selection.insert(UUID())
        doc.restackLayers(ids: selection, .toBack)
        #expect(names(doc) == ["Background", "C", "A", "B", "D"])
    }

    @Test func aSingleUnlockedLayerRestacksLikeBefore() {
        var doc = makeDocument()
        doc.restackLayers(ids: ids(doc, "B"), .forward)
        #expect(names(doc) == ["Background", "A", "C", "B", "D"])
        doc.restackLayers(ids: ids(doc, "B"), .toBack)
        #expect(names(doc) == ["Background", "B", "A", "C", "D"])
    }

    // MARK: Duplicate

    @Test func duplicateLayersPutsEachCopyDirectlyAboveItsOriginal() {
        var doc = makeDocument()
        let copies = doc.duplicateLayers(ids: ids(doc, "A", "C"), offsetBy: CGPoint(x: 16, y: 16))
        #expect(copies.map(\.name) == ["A copy", "C copy"])
        #expect(names(doc) == ["Background", "A", "A copy", "B", "C", "C copy", "D"])
        #expect(copies.allSatisfy { $0.frame.origin == CGPoint(x: 16, y: 16) })
        #expect(Set(copies.map(\.id)).isDisjoint(with: ids(doc, "A", "C")))
    }

    @Test func duplicateLayersWithNothingKnownChangesNothing() {
        var doc = makeDocument()
        let copies = doc.duplicateLayers(ids: [UUID()])
        #expect(copies.isEmpty)
        #expect(names(doc) == ["Background", "A", "B", "C", "D"])
    }
}
