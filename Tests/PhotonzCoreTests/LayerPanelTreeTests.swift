import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The layers panel once layers can hold layers: what rows it shows, what a
/// drop on a row means, and where a dragged layer lands.
struct LayerPanelTreeTests {

    private func leaf(_ name: String, _ frame: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10)) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    private func group(_ name: String, origin: CGPoint = .zero, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: origin, size: .zero))
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: layers)
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    // MARK: - Which groups can be opened at all

    @Test func everyGroupAtEveryDepthCanBeOpened() {
        let document = doc([
            leaf("Loose"),
            group("Card", [leaf("Label"), group("Inner", [leaf("Dot")])]),
        ])
        #expect(document.openableGroupIDs == [id(document, "Card"), id(document, "Inner")])
    }

    @Test func aDocumentWithNoGroupsHasNothingToOpen() {
        let document = doc([leaf("One"), leaf("Two")])
        #expect(document.openableGroupIDs.isEmpty)
    }

    // MARK: - Rows

    @Test func flatDocumentListsTopDown() {
        let document = doc([leaf("Bottom"), leaf("Top")])
        let rows = document.panelRows(expanded: [])
        #expect(rows.map { document.layer(id: $0.id)?.name } == ["Top", "Bottom"])
        #expect(rows.allSatisfy { $0.depth == 0 })
        #expect(rows.allSatisfy { !$0.isGroup })
        #expect(rows.allSatisfy { $0.parentID == nil })
    }

    @Test func closedGroupHidesItsContentsAndCountsThem() {
        let document = doc([group("Card", [leaf("Label"), leaf("Box")])])
        let rows = document.panelRows(expanded: [])
        #expect(rows.count == 1)
        #expect(rows[0].isGroup)
        #expect(!rows[0].isExpanded)
        #expect(rows[0].childCount == 2)
    }

    @Test func openGroupIndentsItsContentsUnderIt() {
        let document = doc([group("Card", [leaf("Label"), leaf("Box")])])
        let card = id(document, "Card")
        let rows = document.panelRows(expanded: [card])
        #expect(rows.map { document.layer(id: $0.id)?.name } == ["Card", "Box", "Label"])
        #expect(rows.map(\.depth) == [0, 1, 1])
        #expect(rows[1].parentID == card)
        #expect(rows[0].isExpanded)
    }

    @Test func nestedGroupsIndentOneLevelEach() {
        let document = doc([group("Outer", [group("Inner", [leaf("Leaf")])])])
        let rows = document.panelRows(expanded: [id(document, "Outer"), id(document, "Inner")])
        #expect(rows.map { document.layer(id: $0.id)?.name } == ["Outer", "Inner", "Leaf"])
        #expect(rows.map(\.depth) == [0, 1, 2])
    }

    @Test func aClosedGroupInsideAnOpenOneStaysClosed() {
        let document = doc([group("Outer", [group("Inner", [leaf("Leaf")])])])
        let rows = document.panelRows(expanded: [id(document, "Outer")])
        #expect(rows.map { document.layer(id: $0.id)?.name } == ["Outer", "Inner"])
    }

    @Test func aLayerAncestorsAreWhatMustOpenToRevealIt() {
        let document = doc([group("Outer", [group("Inner", [leaf("Leaf")])])])
        #expect(document.ancestorIDs(of: id(document, "Leaf"))
                == [id(document, "Inner"), id(document, "Outer")])
        #expect(document.ancestorIDs(of: id(document, "Outer")).isEmpty)
    }

    // MARK: - What a drop on a row means

    @Test func aPlainRowSplitsInHalf() {
        #expect(LayerDropZone.forPointer(y: 4, rowHeight: 38, offersInside: false, offersBelow: true) == .above)
        #expect(LayerDropZone.forPointer(y: 30, rowHeight: 38, offersInside: false, offersBelow: true) == .below)
    }

    @Test func aClosedGroupRowSplitsInThirds() {
        #expect(LayerDropZone.forPointer(y: 2, rowHeight: 38, offersInside: true, offersBelow: true) == .above)
        #expect(LayerDropZone.forPointer(y: 19, rowHeight: 38, offersInside: true, offersBelow: true) == .inside)
        #expect(LayerDropZone.forPointer(y: 36, rowHeight: 38, offersInside: true, offersBelow: true) == .below)
    }

    @Test func anOpenGroupRowHasNoBelowBecauseItsChildrenAreThere() {
        // The slot under an open group row already belongs to its topmost
        // child, so the bottom of the row means inside, not after.
        #expect(LayerDropZone.forPointer(y: 2, rowHeight: 38, offersInside: true, offersBelow: false) == .above)
        #expect(LayerDropZone.forPointer(y: 36, rowHeight: 38, offersInside: true, offersBelow: false) == .inside)
    }

    @Test func aZeroHeightRowNeverCrashes() {
        #expect(LayerDropZone.forPointer(y: 0, rowHeight: 0, offersInside: false, offersBelow: true) == .above)
    }

    // MARK: - Dropping

    @Test func droppingOnAGroupPutsTheLayerInsideItAtTheTop() {
        var document = doc([group("Card", [leaf("Box")]), leaf("Note")])
        let card = id(document, "Card")
        let note = id(document, "Note")
        let moved1 = document.dropLayers(ids: [note], .inside(card))
        #expect(moved1)
        #expect(document.parentID(of: note) == card)
        #expect(document.layer(id: card)?.children.map(\.name) == ["Box", "Note"])
        #expect(document.layers.count == 1)
    }

    @Test func aLayerDroppedIntoAGroupDoesNotMoveOnScreen() {
        var document = doc([group("Card", origin: CGPoint(x: 30, y: 40), [leaf("Box")]),
                            leaf("Note", CGRect(x: 100, y: 5, width: 10, height: 10))])
        let note = id(document, "Note")
        let moved2 = document.dropLayers(ids: [note], .inside(id(document, "Card")))
        #expect(moved2)
        #expect(document.canvasFrame(of: note) == CGRect(x: 100, y: 5, width: 10, height: 10))
        #expect(document.layer(id: note)?.frame == CGRect(x: 70, y: -35, width: 10, height: 10))
    }

    @Test func droppingAgainstATopLevelRowTakesALayerOutOfItsGroup() {
        var document = doc([group("Card", origin: CGPoint(x: 30, y: 40),
                                  [leaf("Box"), leaf("Label", CGRect(x: 2, y: 3, width: 10, height: 10))]),
                            leaf("Note")])
        let label = id(document, "Label")
        let moved3 = document.dropLayers(ids: [label], .above(id(document, "Note")))
        #expect(moved3)
        #expect(document.parentID(of: label) == nil)
        #expect(document.layer(id: label)?.frame == CGRect(x: 32, y: 43, width: 10, height: 10))
        #expect(document.layers.map(\.name) == ["Card", "Note", "Label"])
    }

    @Test func aboveMeansHigherInTheStackAndBelowMeansLower() {
        var document = doc([leaf("A"), leaf("B"), leaf("C")])   // panel reads C, B, A
        let moved4 = document.dropLayers(ids: [id(document, "A")], .above(id(document, "C")))
        #expect(moved4)
        #expect(document.layers.map(\.name) == ["B", "C", "A"])
        let moved5 = document.dropLayers(ids: [id(document, "A")], .below(id(document, "B")))
        #expect(moved5)
        #expect(document.layers.map(\.name) == ["A", "B", "C"])
    }

    @Test func aMultiRowDropKeepsTheRowsRelativeOrder() {
        var document = doc([leaf("A"), leaf("B"), leaf("C"), group("Card", [leaf("Box")])])
        let ids: Set<UUID> = [id(document, "A"), id(document, "C")]
        let moved6 = document.dropLayers(ids: ids, .inside(id(document, "Card")))
        #expect(moved6)
        #expect(document.layer(id: id(document, "Card"))?.children.map(\.name) == ["Box", "A", "C"])
        #expect(document.layers.map(\.name) == ["B", "Card"])
    }

    @Test func aGroupCannotBeDroppedInsideItselfOrItsOwnChild() {
        var document = doc([group("Outer", [group("Inner", [leaf("Leaf")])])])
        let outer = id(document, "Outer")
        #expect(!document.canDrop(ids: [outer], .inside(outer)))
        #expect(!document.canDrop(ids: [outer], .inside(id(document, "Inner"))))
        #expect(!document.canDrop(ids: [outer], .above(id(document, "Leaf"))))
        let moved7 = document.dropLayers(ids: [outer], .inside(id(document, "Inner")))
        #expect(!moved7)
        #expect(document.layer(id: outer)?.children.count == 1)
    }

    @Test func onlyAGroupTakesAnInsideDrop() {
        var document = doc([leaf("A"), leaf("B")])
        #expect(!document.canDrop(ids: [id(document, "A")], .inside(id(document, "B"))))
        let moved8 = document.dropLayers(ids: [id(document, "A")], .inside(id(document, "B")))
        #expect(!moved8)
    }

    @Test func aLockedLayerStaysPutTheWayTheArrangeCommandsLeaveIt() {
        var document = doc([Layer(name: "Background", content: .text(TextContent(string: "bg")),
                                  frame: CGRect(x: 0, y: 0, width: 200, height: 200), isLocked: true),
                            group("Card", [leaf("Box")])])
        #expect(!document.canDrop(ids: [id(document, "Background")], .inside(id(document, "Card"))))
        let moved9 = document.dropLayers(ids: [id(document, "Background")], .inside(id(document, "Card")))
        #expect(!moved9)
        #expect(document.layers.map(\.name) == ["Background", "Card"])
    }

    @Test func aLockedGroupDoesNotSwallowWhatYouDragOverIt() {
        var document = doc([group("Card", [leaf("Box")]), leaf("Note")])
        document.updateLayer(id: id(document, "Card")) { $0.isLocked = true }
        #expect(!document.canDrop(ids: [id(document, "Note")], .inside(id(document, "Card"))))
    }

    @Test func aDropThatChangesNothingIsRefusedSoItCostsNoUndoStep() {
        var document = doc([leaf("A"), leaf("B")])
        // B already sits directly above A, so both spellings of that slot are no-ops.
        let moved10 = document.dropLayers(ids: [id(document, "B")], .above(id(document, "A")))
        #expect(!moved10)
        let moved11 = document.dropLayers(ids: [id(document, "A")], .below(id(document, "B")))
        #expect(!moved11)
        #expect(document.layers.map(\.name) == ["A", "B"])
    }

    @Test func droppingOnItselfIsRefused() {
        var document = doc([leaf("A"), leaf("B")])
        #expect(!document.canDrop(ids: [id(document, "A")], .above(id(document, "A"))))
        #expect(!document.canDrop(ids: [id(document, "A")], .below(id(document, "A"))))
    }

    @Test func aGroupMovedIntoAnotherGroupCarriesItsContents() {
        var document = doc([group("Inner", origin: CGPoint(x: 10, y: 10), [leaf("Leaf")]),
                            group("Outer", origin: CGPoint(x: 100, y: 0), [leaf("Box")])])
        let inner = id(document, "Inner")
        let leafID = id(document, "Leaf")
        let before = document.canvasBounds(of: leafID)
        let moved12 = document.dropLayers(ids: [inner], .inside(id(document, "Outer")))
        #expect(moved12)
        #expect(document.parentID(of: inner) == id(document, "Outer"))
        #expect(document.canvasBounds(of: leafID) == before)
    }

    @Test func unknownIdsDropNothing() {
        var document = doc([leaf("A")])
        let moved13 = document.dropLayers(ids: [UUID()], .above(id(document, "A")))
        #expect(!moved13)
        let moved14 = document.dropLayers(ids: [], .above(id(document, "A")))
        #expect(!moved14)
    }

    // MARK: - What the drop line promises, row by row

    /// The whole reading of a pointer over a row, which is what the panel's
    /// drop delegate calls and what the drop line draws.
    private func proposal(_ document: PhotonzDocument, carrying ids: Set<UUID>,
                          overRowNamed name: String, expanded: Set<UUID> = [],
                          atFraction fraction: CGFloat,
                          allowsInside: Bool = true) -> LayerDrop? {
        let rows = document.panelRows(expanded: expanded)
        guard let row = rows.first(where: { document.layer(id: $0.id)?.name == name }) else { return nil }
        return document.dropProposal(carrying: ids, over: row,
                                     pointerY: 38 * fraction, rowHeight: 38,
                                     allowsInside: allowsInside)
    }

    @Test func theMiddleOfAShutGroupRowPromisesInside() {
        let document = doc([group("Card", [leaf("Box")]), leaf("Note")])
        let note: Set<UUID> = [id(document, "Note")]
        #expect(proposal(document, carrying: note, overRowNamed: "Card", atFraction: 0.5)
                == .inside(id(document, "Card")))
        #expect(proposal(document, carrying: note, overRowNamed: "Card", atFraction: 0.05)
                == .above(id(document, "Card")))
        #expect(proposal(document, carrying: note, overRowNamed: "Card", atFraction: 0.95)
                == .below(id(document, "Card")))
    }

    @Test func theBottomOfAnOpenGroupRowPromisesInsideNotAfter() {
        let document = doc([group("Card", [leaf("Box")]), leaf("Note")])
        let card = id(document, "Card")
        #expect(proposal(document, carrying: [id(document, "Note")], overRowNamed: "Card",
                         expanded: [card], atFraction: 0.95) == .inside(card))
    }

    @Test func aChildRowPromisesToStayInsideItsOwnGroup() {
        let document = doc([group("Card", [leaf("Box"), leaf("Label")]), leaf("Note")])
        let card = id(document, "Card")
        // Dropping a loose layer against a row that lives in the group makes
        // it that row's sibling — which is to say, inside the group.
        #expect(proposal(document, carrying: [id(document, "Note")], overRowNamed: "Box",
                         expanded: [card], atFraction: 0.9) == .below(id(document, "Box")))
    }

    @Test func aTopLevelRowIsHowAChildGetsBackOut() {
        let document = doc([group("Card", [leaf("Box"), leaf("Label")]), leaf("Note")])
        let card = id(document, "Card")
        let label: Set<UUID> = [id(document, "Label")]
        #expect(proposal(document, carrying: label, overRowNamed: "Note",
                         expanded: [card], atFraction: 0.1) == .above(id(document, "Note")))
    }

    @Test func aRowPromisesNothingToItself() {
        let document = doc([leaf("A"), leaf("B")])
        #expect(proposal(document, carrying: [id(document, "A")], overRowNamed: "A", atFraction: 0.1) == nil)
    }

    @Test func aGroupPromisesNothingOverItsOwnContents() {
        let document = doc([group("Outer", [leaf("Leaf")]), leaf("Note")])
        let outer = id(document, "Outer")
        #expect(proposal(document, carrying: [outer], overRowNamed: "Leaf",
                         expanded: [outer], atFraction: 0.5) == nil)
    }

    @Test func withTheGroupsFlagOffAGroupRowIsJustARow() {
        let document = doc([group("Card", [leaf("Box")]), leaf("Note")])
        let note: Set<UUID> = [id(document, "Note")]
        #expect(proposal(document, carrying: note, overRowNamed: "Card",
                         atFraction: 0.5, allowsInside: false) == .below(id(document, "Card")))
    }

    @Test func aDragCarriesTheWholeSelectionOnlyWhenItGrabbedPartOfIt() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(PhotonzDocument.rowsCarried(byDragging: a, selection: [a, b]) == [a, b])
        #expect(PhotonzDocument.rowsCarried(byDragging: c, selection: [a, b]) == [c])
        #expect(PhotonzDocument.rowsCarried(byDragging: a, selection: []) == [a])
    }
}
