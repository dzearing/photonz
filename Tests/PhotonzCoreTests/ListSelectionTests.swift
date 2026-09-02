import Foundation
import PhotonzCore
import Testing

/// Shift-click and command-click in the Layers and Measurements lists, the way
/// the Finder and Photoshop's Layers panel read them. `order` is the list
/// top to bottom; ids are compared by position in it.
@Suite("List row selection: plain, shift and command clicks")
struct ListSelectionTests {

    private let rows: [UUID] = (0..<8).map { _ in UUID() }

    private func ids(_ indexes: Int...) -> Set<UUID> { Set(indexes.map { rows[$0] }) }

    @Test func plainClickSelectsOnlyThatRowAndAnchorsThere() {
        var sel = ListSelection(selected: ids(0, 3, 4), anchor: rows[3])
        sel.click(rows[5], .plain, in: rows)
        #expect(sel.selected == ids(5))
        #expect(sel.anchor == rows[5])
    }

    @Test func shiftClickWithNoAnchorActsLikeAPlainClick() {
        var sel = ListSelection()
        sel.click(rows[2], .extend, in: rows)
        #expect(sel.selected == ids(2))
        #expect(sel.anchor == rows[2])
    }

    @Test func shiftClickSelectsTheInclusiveRangeBelowTheAnchor() {
        var sel = ListSelection()
        sel.click(rows[1], .plain, in: rows)
        sel.click(rows[3], .extend, in: rows)
        #expect(sel.selected == ids(1, 2, 3))
        #expect(sel.anchor == rows[1], "the anchor stays where the plain click landed")
    }

    @Test func shiftClickSelectsTheInclusiveRangeAboveTheAnchor() {
        var sel = ListSelection()
        sel.click(rows[5], .plain, in: rows)
        sel.click(rows[2], .extend, in: rows)
        #expect(sel.selected == ids(2, 3, 4, 5))
        #expect(sel.anchor == rows[5])
    }

    @Test func secondShiftClickPivotsAroundTheAnchor() {
        // Finder: the range is always anchor..clicked; rows the previous
        // shift-click swept in on the other side let go.
        var sel = ListSelection()
        sel.click(rows[3], .plain, in: rows)
        sel.click(rows[6], .extend, in: rows)
        #expect(sel.selected == ids(3, 4, 5, 6))
        sel.click(rows[1], .extend, in: rows)
        #expect(sel.selected == ids(1, 2, 3))
    }

    @Test func shiftClickKeepsRowsAddedByCommandClick() {
        var sel = ListSelection()
        sel.click(rows[0], .plain, in: rows)
        sel.click(rows[4], .toggle, in: rows)
        #expect(sel.anchor == rows[4], "command-click moves the anchor")
        sel.click(rows[6], .extend, in: rows)
        #expect(sel.selected == ids(0, 4, 5, 6))
    }

    @Test func commandClickAddsThenRemovesARow() {
        var sel = ListSelection()
        sel.click(rows[0], .plain, in: rows)
        sel.click(rows[2], .toggle, in: rows)
        #expect(sel.selected == ids(0, 2))
        sel.click(rows[2], .toggle, in: rows)
        #expect(sel.selected == ids(0))
        #expect(sel.anchor == rows[2])
    }

    @Test func commandClickCanEmptyTheSelection() {
        var sel = ListSelection()
        sel.click(rows[0], .plain, in: rows)
        sel.click(rows[0], .toggle, in: rows)
        #expect(sel.selected.isEmpty)
    }

    @Test func commandClickForgetsThePreviousShiftRange() {
        // After a command-click the next shift-click ranges from the new
        // anchor and nothing from the old sweep is taken back.
        var sel = ListSelection()
        sel.click(rows[0], .plain, in: rows)
        sel.click(rows[2], .extend, in: rows)
        sel.click(rows[5], .toggle, in: rows)
        sel.click(rows[7], .extend, in: rows)
        #expect(sel.selected == ids(0, 1, 2, 5, 6, 7))
    }

    @Test func plainClickForgetsThePreviousShiftRange() {
        var sel = ListSelection()
        sel.click(rows[0], .plain, in: rows)
        sel.click(rows[2], .extend, in: rows)
        sel.click(rows[5], .plain, in: rows)
        sel.click(rows[3], .extend, in: rows)
        #expect(sel.selected == ids(3, 4, 5))
    }

    @Test func shiftClickAfterTheAnchorLeftTheListActsLikeAPlainClick() {
        // The anchored layer was deleted: nothing to range from.
        var sel = ListSelection(selected: ids(1, 2), anchor: UUID())
        sel.click(rows[4], .extend, in: rows)
        #expect(sel.selected == ids(4))
        #expect(sel.anchor == rows[4])
    }

    @Test func clickingARowOutsideTheListSelectsJustThatRow() {
        // Defensive: a stale row id still yields a sane single selection.
        var sel = ListSelection()
        sel.click(rows[1], .plain, in: rows)
        let stranger = UUID()
        sel.click(stranger, .extend, in: rows)
        #expect(sel.selected == [stranger])
    }

    @Test func shiftClickOnTheAnchorItselfKeepsOtherRows() {
        var sel = ListSelection()
        sel.click(rows[2], .plain, in: rows)
        sel.click(rows[5], .toggle, in: rows)   // anchor is now 5
        sel.click(rows[5], .extend, in: rows)
        #expect(sel.selected == ids(2, 5))
    }

    @Test func rangeCanBeSeededFromAnExternalSelection() {
        // A canvas click selected one layer; the list must range from it.
        var sel = ListSelection(selected: ids(3), anchor: rows[3])
        sel.click(rows[5], .extend, in: rows)
        #expect(sel.selected == ids(3, 4, 5))
    }
}
