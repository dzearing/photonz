import CoreGraphics
import Testing
@testable import PhotonzCore

/// The Library in its own pane at the foot of the panel, so nothing the pick
/// does above it moves a tile under the pointer (2026-10-19: a title page
/// tile slid 110pt between the two clicks of a double click).
@Suite("The Library's pane at the foot of the panel")
struct PanelShelfPaneTests {

    // MARK: Its chosen height

    @Test("The pane is the height the divider left it, whatever the pick")
    func keepsItsHeight() {
        #expect(PanelShelfPane.height(stored: 300, held: nil, column: 700, floor: 45) == 300)
    }

    @Test("Switching the shelf's scope or folding it leaves a held pane where it was")
    func holdsWhenTheShelfShrinks() {
        let held = PanelShelfPane.Hold(column: 700, height: 330)
        #expect(PanelShelfPane.height(stored: nil, held: held, column: 700, floor: 45, fit: 120) == 330)
        #expect(PanelShelfPane.height(stored: nil, held: held, column: 700, floor: 45, fit: 345) == 330)
    }

    @Test("Its starting height is worked out once the shelf is measured, and then held")
    func holdsItsStartingHeight() {
        #expect(PanelShelfPane.hold(nil, column: 930, fit: nil) == nil)
        #expect(PanelShelfPane.hold(nil, column: nil, fit: 413) == nil)
        let first = PanelShelfPane.hold(nil, column: 930, fit: 413)
        #expect(first == PanelShelfPane.Hold(column: 930, height: 413))
        #expect(PanelShelfPane.hold(first, column: 930, fit: 200) == first)
        #expect(PanelShelfPane.hold(first, column: 930, fit: nil) == first)
    }

    @Test("A held pane grows when the shelf needs more at its least, never past half the panel")
    func holdGrows() {
        let first = PanelShelfPane.Hold(column: 930, height: 372)
        #expect(PanelShelfPane.hold(first, column: 930, fit: 440) == PanelShelfPane.Hold(column: 930, height: 440))
        #expect(PanelShelfPane.hold(first, column: 930, fit: 900) == PanelShelfPane.Hold(column: 930, height: 465))
    }

    @Test("A new window height works the height out again, and an old hold is not read")
    func rehold() {
        let first = PanelShelfPane.Hold(column: 930, height: 413)
        #expect(PanelShelfPane.hold(first, column: 410, fit: 413) == PanelShelfPane.Hold(column: 410, height: 205))
        #expect(PanelShelfPane.height(stored: nil, held: first, column: 410, floor: 45)
            == 410 * PanelShelfPane.defaultShare)
    }

    @Test("The pick always keeps room of its own, however high the divider was pulled")
    func pickKeepsAFloor() {
        #expect(PanelShelfPane.height(stored: 900, held: nil, column: 600, floor: 45)
            == 600 - PanelShelfPane.aboveFloor)
        #expect(PanelShelfPane.maxAllowedHeight(column: 700, floor: 45) == 700 - PanelShelfPane.aboveFloor)
    }

    @Test("A window too short for both still shows the shelf's header")
    func tinyWindow() {
        #expect(PanelShelfPane.height(stored: 300, held: nil, column: 100, floor: 45) == 45)
        #expect(PanelShelfPane.maxAllowedHeight(column: 100, floor: 45) == 45)
    }

    @Test("Until the divider is moved: its share, or what the shelf needs up to half")
    func startsAtItsShare() {
        #expect(PanelShelfPane.height(stored: nil, held: nil, column: 410, floor: 45) == 410 * PanelShelfPane.defaultShare)
        #expect(PanelShelfPane.height(stored: nil, held: nil, column: nil, floor: 45) == PanelShelfPane.defaultHeight)
        #expect(PanelShelfPane.height(stored: nil, held: nil, column: 930, floor: 45, fit: 413) == 413)
        #expect(PanelShelfPane.height(stored: nil, held: nil, column: 410, floor: 45, fit: 413) == 205)
        #expect(PanelShelfPane.height(stored: 200, held: nil, column: 930, floor: 45, fit: 413) == 200)
    }

    // MARK: It grows into any room the pick leaves

    @Test("Everything above folded: the pane takes every point the pick leaves")
    func growsIntoTheRoom() {
        #expect(PanelShelfPane.drawnHeight(chosen: 218, column: 645, aboveNeeds: 111, foldedHeight: nil) == 534)
    }

    @Test("A pick that needs more than is left: the pane keeps the height chosen")
    func keepsTheChosenHeight() {
        #expect(PanelShelfPane.drawnHeight(chosen: 218, column: 645, aboveNeeds: 900, foldedHeight: nil) == 218)
        #expect(PanelShelfPane.drawnHeight(chosen: 218, column: 645, aboveNeeds: 427, foldedHeight: nil) == 218)
    }

    @Test("The shelf folded: it is its header, and an overflowing pick has the rest")
    func foldedShelf() {
        #expect(PanelShelfPane.drawnHeight(chosen: 300, column: 645, aboveNeeds: 900, foldedHeight: 45) == 45)
        #expect(PanelShelfPane.drawnHeight(chosen: 300, column: 645, aboveNeeds: 111, foldedHeight: 45) == 534)
    }

    @Test("Before the pick is measured the pane is drawn at the height chosen")
    func unmeasured() {
        #expect(PanelShelfPane.drawnHeight(chosen: 218, column: 645, aboveNeeds: nil, foldedHeight: nil) == 218)
        #expect(PanelShelfPane.drawnHeight(chosen: 218, column: nil, aboveNeeds: 111, foldedHeight: nil) == 218)
    }

    // MARK: A shelf is never cut across its first row

    /// tutorial-the-library-walk, 2026-10-19: a colour saved onto an empty
    /// Styles shelf in a 900pt window with twelve layers. Layers took 245pt of
    /// a 612pt column, the pane got 179pt and the new tile's name sat 28pt
    /// under the panel's foot. The shelf needed 207pt at its least.
    @Test("The pane is at least what the shelf needs to show its first row whole")
    func neverCutsTheFirstRow() {
        #expect(PanelShelfPane.atLeastTheShelf(179, least: 207, column: 358) == 207)
        // ...taken from the sections above down to their header, no further.
        #expect(PanelShelfPane.atLeastTheShelf(179, least: 400, column: 358)
            == 358 - PanelShelfPane.aboveLeast)
        // Already tall enough: nothing changes.
        #expect(PanelShelfPane.atLeastTheShelf(300, least: 207, column: 358) == 300)
        // Unmeasured: nothing changes.
        #expect(PanelShelfPane.atLeastTheShelf(179, least: nil, column: 358) == 179)
        #expect(PanelShelfPane.atLeastTheShelf(179, least: 207, column: nil) == 179)
    }

    // MARK: The divider

    @Test("Pulled up past the room the pick leaves: that is the new choice")
    func gripUp() {
        #expect(PanelShelfPane.gripChoice(dragged: 560, startChosen: 218, roomLeft: 534) == 560)
    }

    @Test("Pulled down while the pick fits: the choice stays unless it goes under it")
    func gripDown() {
        #expect(PanelShelfPane.gripChoice(dragged: 500, startChosen: 218, roomLeft: 534) == 218)
        #expect(PanelShelfPane.gripChoice(dragged: 150, startChosen: 218, roomLeft: 534) == 150)
        #expect(PanelShelfPane.gripChoice(dragged: 250, startChosen: 300, roomLeft: 200) == 250)
    }

    @Test("Each kind of document keeps its own divider")
    func keys() {
        #expect(PanelShelfPane.heightKey(forKind: "video") != PanelShelfPane.heightKey(forKind: "image"))
        #expect(PanelShelfPane.heightKey(forKind: "video") != PanelListsPane.heightKey(forKind: "video"))
    }
}
