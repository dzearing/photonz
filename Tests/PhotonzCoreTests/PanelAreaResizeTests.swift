import CoreGraphics
import Testing
@testable import PhotonzCore

/// The grab bar under a bounded panel area. It was drawn, it changed the
/// pointer to a resize cursor, and it moved nothing: the drag wrote a ceiling
/// while the area was drawn at min(content, ceiling), so with a short list
/// every drag landed on a number nothing read. These pin the two rules that
/// fix it — no bar while there is nothing to resize, and a drag that can never
/// leave the content behind.
@Suite("Panel area resize")
struct PanelAreaResizeTests {

    // A layers list: floor 120, hard ceiling 600. Three rows plus the Canvas
    // row is about 162 tall, two rows about 122, one about 82.
    let floor: CGFloat = 120
    let hardCeiling: CGFloat = 600

    // MARK: Whether there is anything to drag

    @Test("A list shorter than the floor offers no grab bar")
    func shortListHasNoHandle() {
        #expect(!PanelAreaResize.isResizable(contentHeight: 82,
                                             minHeight: floor,
                                             maxAllowedHeight: hardCeiling))
    }

    @Test("A list exactly at the floor offers no grab bar either")
    func atTheFloorHasNoHandle() {
        #expect(!PanelAreaResize.isResizable(contentHeight: floor,
                                             minHeight: floor,
                                             maxAllowedHeight: hardCeiling))
    }

    @Test("A list taller than the floor offers one")
    func tallListHasAHandle() {
        #expect(PanelAreaResize.isResizable(contentHeight: 162,
                                            minHeight: floor,
                                            maxAllowedHeight: hardCeiling))
    }

    @Test("An empty area offers none")
    func emptyHasNoHandle() {
        #expect(!PanelAreaResize.isResizable(contentHeight: 0,
                                             minHeight: floor,
                                             maxAllowedHeight: hardCeiling))
    }

    // MARK: What a drag does

    @Test("Dragging down grows the area point for point")
    func dragDownGrows() {
        let h = PanelAreaResize.draggedHeight(base: 200, translation: 60, contentHeight: 500,
                                              minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(h == 260)
    }

    @Test("Dragging up shrinks it point for point")
    func dragUpShrinks() {
        let h = PanelAreaResize.draggedHeight(base: 200, translation: -60, contentHeight: 500,
                                              minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(h == 140)
    }

    @Test("It never goes below the floor")
    func stopsAtTheFloor() {
        let h = PanelAreaResize.draggedHeight(base: 200, translation: -900, contentHeight: 500,
                                              minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(h == floor)
    }

    @Test("It never goes past the content, so every point of the drag moves the area")
    func stopsAtTheContent() {
        let h = PanelAreaResize.draggedHeight(base: 140, translation: 900, contentHeight: 162,
                                              minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(h == 162)
    }

    @Test("A very long list stops at the panel's own ceiling instead")
    func stopsAtTheHardCeiling() {
        let h = PanelAreaResize.draggedHeight(base: 400, translation: 900, contentHeight: 4000,
                                              minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(h == hardCeiling)
    }

    @Test("Every point of a short list's range moves the area")
    func shortRangeTracksOneForOne() {
        // Three rows: the whole range is 120 to 162, and it is real.
        for pull in stride(from: CGFloat(-40), through: 40, by: 5) {
            let h = PanelAreaResize.draggedHeight(base: 140, translation: pull, contentHeight: 162,
                                                  minHeight: floor, maxAllowedHeight: hardCeiling)
            #expect(h == min(162, max(floor, 140 + pull)))
        }
    }

    // MARK: What gets remembered

    @Test("A drag that stops short of the bottom remembers where it stopped")
    func remembersWhereItStopped() {
        let cap = PanelAreaResize.storedCeiling(base: 300, translation: -100, contentHeight: 500,
                                                minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(cap == 200)
    }

    @Test("Pulled all the way open, it remembers no ceiling rather than today's content")
    func pulledOpenMeansLetItGrow() {
        // Three rows, pulled to the bottom. Remembering 162 would stop the
        // fourth row from ever getting room.
        let cap = PanelAreaResize.storedCeiling(base: 140, translation: 400, contentHeight: 162,
                                                minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(cap == hardCeiling)
    }

    @Test("A long list pulled to the panel's ceiling remembers that ceiling")
    func longListRemembersTheHardCeiling() {
        let cap = PanelAreaResize.storedCeiling(base: 400, translation: 900, contentHeight: 4000,
                                                minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(cap == hardCeiling)
    }

    // MARK: The height the area is drawn at

    @Test("The area hugs content under the ceiling and caps content over it")
    func heightHugsThenCaps() {
        #expect(PanelAreaResize.height(contentHeight: 82, ceiling: 200) == 82)
        #expect(PanelAreaResize.height(contentHeight: 500, ceiling: 200) == 200)
    }

    @Test("Dragging then drawing agree: the area lands where the pointer left it")
    func dragAndDrawAgree() {
        let content: CGFloat = 500
        let cap = PanelAreaResize.storedCeiling(base: 200, translation: 90, contentHeight: content,
                                                minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(PanelAreaResize.height(contentHeight: content, ceiling: cap) == 290)
    }

    // MARK: The Library shelf, the other area with a grab bar

    @Test("One row of tiles is shorter than the shelf's floor, so no grab bar")
    func oneShelfRowHasNoHandle() {
        let content = LibraryShelfLayout.contentHeight(tileCount: 3, width: 260)
        #expect(content < 104)
        #expect(!PanelAreaResize.isResizable(contentHeight: content,
                                             minHeight: 104, maxAllowedHeight: 560))
    }

    @Test("Two rows of tiles are taller than it, so there is")
    func twoShelfRowsHaveAHandle() {
        let content = LibraryShelfLayout.contentHeight(tileCount: 8, width: 260)
        #expect(content > 104)
        #expect(PanelAreaResize.isResizable(contentHeight: content,
                                            minHeight: 104, maxAllowedHeight: 560))
    }

    // MARK: Nonsense in, sense out

    @Test("Measurements that have not landed yet cannot make a negative area")
    func negativeMeasurementsAreSafe() {
        #expect(PanelAreaResize.ceiling(contentHeight: -50, maxAllowedHeight: 600) == 0)
        #expect(PanelAreaResize.height(contentHeight: -50, ceiling: 200) == 0)
        let h = PanelAreaResize.draggedHeight(base: 0, translation: -10, contentHeight: 0,
                                              minHeight: floor, maxAllowedHeight: hardCeiling)
        #expect(h == 0)
    }
}
