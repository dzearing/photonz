import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A row carried up and down the layers list by the pointer: which half of
/// which row decides where it lands, the gap that opens there, and what the
/// document does when it is let go.
struct LayerRowDragTests {

    private let pitch: CGFloat = 10

    private func leaf(_ name: String, locked: Bool = false) -> Layer {
        var layer = Layer(name: name, content: .text(TextContent(string: name)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        layer.isLocked = locked
        return layer
    }

    private func group(_ name: String, locked: Bool = false, _ children: [Layer]) -> Layer {
        var layer = Layer(name: name, content: .group(GroupContent(children: children.reversed())),
                          frame: CGRect(origin: .zero, size: .zero))
        layer.isLocked = locked
        return layer
    }

    /// Layers given TOP DOWN, the way the list reads (inside a group too), so a
    /// test reads like the list it is about.
    private func doc(_ topDown: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: topDown.reversed())
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func names(_ document: PhotonzDocument, _ ids: [UUID]) -> [String] {
        ids.compactMap { document.layer(id: $0)?.name }
    }

    /// The panel top down, every group open, each name indented by depth.
    private func panel(_ document: PhotonzDocument) -> [String] {
        document.panelRows(expanded: Set(document.allLayers.map(\.id))).map { row in
            String(repeating: "  ", count: row.depth) + (document.layer(id: row.id)?.name ?? "?")
        }
    }

    /// Picks `name` up by the middle of its row.
    private func pickUp(_ name: String, in document: PhotonzDocument,
                        expanded: Set<String> = [], carrying: Set<String> = []) -> LayerRowDrag? {
        let open = Set(expanded.map { id(document, $0) })
        let rows = document.panelRows(expanded: open)
        guard let index = rows.firstIndex(where: { $0.id == id(document, name) }) else { return nil }
        return LayerRowDrag(grabbing: id(document, name),
                            carrying: Set(carrying.map { id(document, $0) }),
                            rows: rows, pitch: pitch,
                            pointerY: (CGFloat(index) + 0.5) * pitch)
    }

    /// Moves the pointer to `fraction` of the way down the row called `name`
    /// AS THE LIST DRAWS IT NOW, in small steps from where it is, the way a
    /// hand gets there.
    private func move(_ drag: inout LayerRowDrag, over name: String, at fraction: CGFloat,
                      in document: PhotonzDocument) {
        let target = id(document, name)
        guard let standing = drag.rest.firstIndex(where: { $0.id == target }) else {
            Issue.record("\(name) is not standing in the list")
            return
        }
        let drawn = standing < drag.gap ? standing : standing + 1
        let goal = (CGFloat(drawn) + fraction) * pitch
        slide(&drag, to: goal, in: document)
    }

    private func slide(_ drag: inout LayerRowDrag, to goal: CGFloat, in document: PhotonzDocument) {
        let carried = drag.carried
        let from = drag.pointerY
        for step in 1...20 {
            let y = from + (goal - from) * CGFloat(step) / 20
            drag.move(pointerY: y) { document.canDrop(ids: carried, $0) }
        }
    }

    private func drop(_ drag: LayerRowDrag, in document: inout PhotonzDocument) -> Bool {
        guard let landing = drag.landing else { return false }
        return document.dropLayers(ids: drag.carried, landing)
    }

    // MARK: - Halves

    @Test func topHalfOfARowPutsItAbove() throws {
        var document = doc([leaf("A"), leaf("B"), leaf("C"), leaf("D")])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "C", at: 0.25, in: document)
        #expect(drag.landing == .above(id(document, "C")))
        #expect(drag.gap == 1)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["B", "A", "C", "D"])
    }

    @Test func bottomHalfOfARowPutsItBelow() throws {
        var document = doc([leaf("A"), leaf("B"), leaf("C"), leaf("D")])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "C", at: 0.75, in: document)
        #expect(drag.landing == .below(id(document, "C")))
        #expect(drag.gap == 2)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["B", "C", "A", "D"])
    }

    @Test func draggingUpReadsTheSameHalves() throws {
        var document = doc([leaf("A"), leaf("B"), leaf("C"), leaf("D")])
        var drag = try #require(pickUp("D", in: document))
        move(&drag, over: "B", at: 0.25, in: document)
        #expect(drag.landing == .above(id(document, "B")))
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["A", "D", "B", "C"])
    }

    @Test func aPointerOverTheGapChangesNothing() throws {
        let document = doc([leaf("A"), leaf("B"), leaf("C"), leaf("D")])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "B", at: 0.75, in: document)
        let landing = drag.landing
        let gap = drag.gap
        // The gap is now where B's bottom half was drawn; wandering inside it,
        // top to bottom, is the calm that stops a row swapping back and forth.
        let carried = drag.carried
        for y in stride(from: drag.gapTop + 0.5, to: drag.gapTop + pitch, by: 1) {
            drag.move(pointerY: y) { document.canDrop(ids: carried, $0) }
            #expect(drag.landing == landing)
            #expect(drag.gap == gap)
        }
    }

    @Test func putBackWhereItCameFromIsNoEdit() throws {
        var document = doc([leaf("A"), leaf("B"), leaf("C")])
        var drag = try #require(pickUp("B", in: document))
        move(&drag, over: "C", at: 0.75, in: document)
        move(&drag, over: "A", at: 0.75, in: document)
        #expect(drag.gap == drag.homeGap)
        #expect(!drop(drag, in: &document))
        #expect(panel(document) == ["A", "B", "C"])
    }

    @Test func aShutGroupIsReadInHalvesLikeAnyRow() throws {
        let document = doc([leaf("A"), group("G", [leaf("G1")]), leaf("R")])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "G", at: 0.75, in: document)
        #expect(drag.landing == .below(id(document, "G")))
        #expect(drag.gapDepth == 0)
    }

    // MARK: - The foot and head of an open group

    @Test func bottomHalfOfAGroupsLastChildLandsInsideAsItsLastChild() throws {
        var document = doc([leaf("A"), group("G", [leaf("G1"), leaf("G2")]), leaf("R")])
        var drag = try #require(pickUp("A", in: document, expanded: ["G"]))
        move(&drag, over: "G2", at: 0.75, in: document)
        #expect(drag.landing == .below(id(document, "G2")))
        #expect(drag.gapDepth == 1)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["G", "  G1", "  G2", "  A", "R"])
    }

    @Test func topHalfOfTheRowBelowAGroupLandsBelowTheGroup() throws {
        var document = doc([leaf("A"), group("G", [leaf("G1"), leaf("G2")]), leaf("R")])
        var drag = try #require(pickUp("A", in: document, expanded: ["G"]))
        move(&drag, over: "G2", at: 0.75, in: document)
        let insideGap = drag.gap
        move(&drag, over: "R", at: 0.25, in: document)
        #expect(drag.landing == .above(id(document, "R")))
        // The very same gap, drawn one level out: that indent is the only
        // thing that tells the two apart, so it has to change.
        #expect(drag.gap == insideGap)
        #expect(drag.gapDepth == 0)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["G", "  G1", "  G2", "A", "R"])
    }

    @Test func bottomHalfOfAnOpenGroupsRowLandsInItsFirstSlot() throws {
        var document = doc([leaf("A"), group("G", [leaf("G1"), leaf("G2")]), leaf("R")])
        var drag = try #require(pickUp("R", in: document, expanded: ["G"]))
        move(&drag, over: "G", at: 0.75, in: document)
        #expect(drag.landing == .inside(id(document, "G")))
        #expect(drag.gapDepth == 1)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["A", "G", "  R", "  G1", "  G2"])
    }

    @Test func pastTheLastRowLandsAtTheBottomOutsideEveryGroup() throws {
        var document = doc([leaf("A"), group("G", [leaf("G1"), leaf("G2")])])
        var drag = try #require(pickUp("A", in: document, expanded: ["G"]))
        slide(&drag, to: CGFloat(drag.rows.count + 2) * pitch, in: document)
        #expect(drag.landing == .below(id(document, "G")))
        #expect(drag.gapDepth == 0)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["G", "  G1", "  G2", "A"])
    }

    @Test func aboveTheFirstRowLandsAtTheTop() throws {
        var document = doc([leaf("A"), leaf("B"), leaf("C")])
        var drag = try #require(pickUp("C", in: document))
        slide(&drag, to: -30, in: document)
        #expect(drag.landing == .above(id(document, "A")))
        #expect(drag.gap == 0)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["C", "A", "B"])
    }

    // MARK: - What rides along

    @Test func aGroupCarriesItsContentsAndCanNeverLandInsideItself() throws {
        var document = doc([group("G", [group("Inner", [leaf("Dot")]), leaf("G1")]), leaf("R")])
        var drag = try #require(pickUp("G", in: document, expanded: ["G", "Inner"]))
        // Everything inside rides along, so none of it is a place to land.
        #expect(Set(names(document, Array(drag.hidden))) == ["Inner", "Dot", "G1"])
        #expect(names(document, drag.rest.map(\.id)) == ["R"])
        move(&drag, over: "R", at: 0.75, in: document)
        #expect(drag.landing == .below(id(document, "R")))
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["R", "G", "  Inner", "    Dot", "  G1"])
    }

    @Test func theListClosesUpOverWhatRidesAlong() throws {
        let document = doc([group("G", [leaf("G1"), leaf("G2")]), leaf("R"), leaf("S")])
        let drag = try #require(pickUp("G", in: document, expanded: ["G"]))
        // R and S sit two rows further down than they are drawn: the two
        // children tucked away, and the gap standing where G was.
        #expect(drag.offset(of: id(document, "R")) == -2 * pitch)
        #expect(drag.offset(of: id(document, "S")) == -2 * pitch)
        #expect(drag.trailingOffset == -2 * pitch)
        #expect(drag.isTravelling(id(document, "G1")))
        #expect(drag.isTravelling(id(document, "G")))
        #expect(!drag.isTravelling(id(document, "R")))
    }

    @Test func theRowsBetweenMoveOneRowOutOfTheWay() throws {
        let document = doc([leaf("A"), leaf("B"), leaf("C"), leaf("D")])
        var drag = try #require(pickUp("A", in: document))
        #expect(drag.offset(of: id(document, "B")) == 0)
        move(&drag, over: "C", at: 0.75, in: document)
        // A's old slot is closed and the gap stands under C: B and C moved up
        // one row each, and D, under the gap, is where it always was.
        #expect(drag.offset(of: id(document, "B")) == -pitch)
        #expect(drag.offset(of: id(document, "C")) == -pitch)
        #expect(drag.offset(of: id(document, "D")) == 0)
        #expect(drag.gapTop == 2 * pitch)
    }

    @Test func aSelectionTravelsTogetherAndKeepsItsOrder() throws {
        var document = doc([leaf("A"), leaf("B"), leaf("C"), leaf("D")])
        var drag = try #require(pickUp("A", in: document, carrying: ["A", "C"]))
        #expect(names(document, Array(drag.hidden)) == ["C"])
        #expect(names(document, drag.rest.map(\.id)) == ["B", "D"])
        move(&drag, over: "D", at: 0.75, in: document)
        #expect(drop(drag, in: &document))
        #expect(panel(document) == ["B", "D", "A", "C"])
    }

    @Test func calledOffItGoesBackAndChangesNothing() throws {
        let document = doc([leaf("A"), group("G", [leaf("G1")]), leaf("R")])
        var drag = try #require(pickUp("A", in: document, expanded: ["G"]))
        move(&drag, over: "G1", at: 0.75, in: document)
        #expect(drag.gapDepth == 1)
        drag.returnHome()
        #expect(drag.landing == nil)
        #expect(drag.gap == drag.homeGap)
        #expect(drag.gapDepth == 0)
        #expect(drag.offset(of: id(document, "G")) == 0)
        #expect(drag.gapTop == 0)
    }

    // MARK: - Where the lifted row is drawn

    @Test func theLiftedRowKeepsItsHoldAndStaysInsideTheList() throws {
        let document = doc([leaf("A"), leaf("B"), leaf("C")])
        var drag = try #require(pickUp("B", in: document))
        #expect(drag.liftedTop == pitch)
        drag.move(pointerY: 1.5 * pitch + 3) { _ in true }
        #expect(drag.liftedTop == pitch + 3)
        drag.move(pointerY: -100) { _ in true }
        #expect(drag.liftedTop == 0)
        drag.move(pointerY: 100) { _ in true }
        #expect(drag.liftedTop == 2 * pitch)
    }

    // MARK: - What the document refuses

    @Test func aLockedGroupRefusesAndTheGapStaysWhereItWas() throws {
        let document = doc([leaf("A"), group("G", locked: true, [leaf("G1")]), leaf("R")])
        var drag = try #require(pickUp("A", in: document, expanded: ["G"]))
        move(&drag, over: "G", at: 0.25, in: document)
        let before = (drag.landing, drag.gap)
        move(&drag, over: "G", at: 0.75, in: document)
        #expect(drag.landing == before.0)
        #expect(drag.gap == before.1)
    }

    @Test func aLockedRowCannotBeCarriedAnywhere() throws {
        let document = doc([leaf("A", locked: true), leaf("B"), leaf("C")])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "C", at: 0.75, in: document)
        #expect(drag.landing == nil)
        #expect(drag.gap == drag.homeGap)
    }

    @Test func aRowWithNothingToPassIsNotPickedUp() {
        let document = doc([leaf("Only")])
        #expect(pickUp("Only", in: document) == nil)
    }

    // MARK: - A shut group springing open under the pointer

    @Test func aGroupThatOpensUnderTheDragKeepsTheLandingAndOffersItsFirstSlot() throws {
        let document = doc([leaf("A"), group("G", [leaf("G1"), leaf("G2")]), leaf("R")])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "G", at: 0.75, in: document)
        #expect(drag.landing == .below(id(document, "G")))
        // Crossing G's middle put the gap under the pointer, and a pointer
        // resting in the gap just under a shut group is aiming at it.
        #expect(drag.rowUnderPointer == nil)
        #expect(drag.springTarget == id(document, "G"))
        let opened = document.panelRows(expanded: [id(document, "G")])
        let carried = drag.carried
        drag.reflow(rows: opened) { document.canDrop(ids: carried, $0) }
        #expect(drag.rest.count == 4)
        // Under an open group's row is its first slot.
        #expect(drag.landing == .inside(id(document, "G")))
        #expect(drag.gapDepth == 1)
        #expect(drag.springTarget == nil)
    }

    @Test func onlyAShutGroupSpringsOpen() throws {
        let document = doc([leaf("A"), leaf("B"), group("G", [leaf("G1")])])
        var drag = try #require(pickUp("A", in: document))
        move(&drag, over: "B", at: 0.75, in: document)
        #expect(drag.springTarget == nil)
        let open = try #require(pickUp("A", in: document, expanded: ["G"]))
        #expect(open.springTarget == nil)
    }

    @Test func comingUpOntoAShutGroupAimsAtItToo() throws {
        let document = doc([group("G", [leaf("G1")]), leaf("B"), leaf("A")])
        var drag = try #require(pickUp("A", in: document))
        // From below, the bottom half of G agrees with the gap already under
        // it, so the pointer is left resting on G's own row.
        move(&drag, over: "G", at: 0.75, in: document)
        #expect(drag.rowUnderPointer?.id == id(document, "G"))
        #expect(drag.springTarget == id(document, "G"))
    }
}
