import CoreGraphics
import Testing
@testable import PhotonzCore

/// The panel reads top to bottom: Layers (and Measurements) in a pane on top,
/// a divider the person drags, then the picked thing's sections, and the
/// Library last when it is shown (the user, 2026-10-18: "layers isn't at the
/// top, i can't drag the pane up and down"). This reverses the 2026-10-13
/// card answer "Pick on top, lists in a pane at the bottom".
@Suite("The lists pane on top of the pick")
struct PanelListsPaneTests {

    // MARK: Which section goes where

    @Test("A rectangle picked: Layers on top, its sections below, the Library in its own pane last")
    func rectangleSplits() {
        let split = PanelListsPane.split(["layers", "color", "effects", "motion", "library"])
        #expect(split.lists == ["layers"])
        #expect(split.below == ["color", "effects", "motion"])
        #expect(split.shelf == ["library"])
    }

    @Test("Layers comes first and Measurements second, whatever order the dock had them in")
    func layersThenMeasurements() {
        let split = PanelListsPane.split(["measureTool", "measurements", "color", "layers", "library"])
        #expect(split.lists == ["layers", "measurements"])
        #expect(split.below == ["measureTool", "color"])
        #expect(split.shelf == ["library"])
    }

    /// A click on a tile picks it, and picking brings the tile's own section.
    /// Drawn above the shelf in one scroller, that section pushed every tile
    /// 110pt down between the two clicks of a double click (2026-10-19). With
    /// the shelf in its own pane, the section stays with the pick.
    @Test("The Library is in its own part however high the dock had it, its picked tile's section with the pick")
    func libraryIsLast() {
        let split = PanelListsPane.split(["layers", "library", "libraryItem", "color", "effects"])
        #expect(split.below == ["libraryItem", "color", "effects"])
        #expect(split.shelf == ["library"])
    }

    @Test("On a video the timeline is the layer list: nothing on top, the Library under the pick")
    func videoHasNoPaneOnTop() {
        let split = PanelListsPane.split(["keys", "speed", "color", "captions", "transitions", "library"])
        #expect(split.lists.isEmpty)
        #expect(split.below == ["keys", "speed", "color", "captions", "transitions"])
        #expect(split.shelf == ["library"])
    }

    @Test("Nothing picked: Layers on top and nothing below")
    func nothingPicked() {
        let split = PanelListsPane.split(["layers"])
        #expect(split.lists == ["layers"])
        #expect(split.below.isEmpty)
        #expect(split.shelf.isEmpty)
    }

    // MARK: How tall the pane on top is drawn

    @Test("The pane is the height the divider was left at when its lists fill it")
    func keepsTheChosenHeight() {
        #expect(PanelListsPane.height(chosen: 300, column: 800, listsNeed: 600,
                                      belowIsEmpty: false, floor: 45) == 300)
    }

    @Test("A short or folded Layers: the pane hugs it, so the sections below meet it with no gap")
    func hugsShortLists() {
        // Two rows and the header.
        #expect(PanelListsPane.height(chosen: 300, column: 800, listsNeed: 120,
                                      belowIsEmpty: false, floor: 45) == 120)
        // Folded: just the header and the padding.
        #expect(PanelListsPane.height(chosen: 300, column: 800, listsNeed: 46,
                                      belowIsEmpty: false, floor: 45) == 46)
    }

    @Test("Nothing picked: Layers fills the panel")
    func nothingPickedFillsThePanel() {
        #expect(PanelListsPane.height(chosen: 300, column: 800, listsNeed: 120,
                                      belowIsEmpty: true, floor: 45) == 800)
    }

    @Test("The sections below always keep room of their own, however low the divider was left")
    func belowKeepsAFloor() {
        #expect(PanelListsPane.height(chosen: 900, column: 600, listsNeed: 2000,
                                      belowIsEmpty: false, floor: 45) == 600 - PanelListsPane.belowFloor)
    }

    @Test("A window too short for both still shows the pane's first header")
    func tinyWindow() {
        #expect(PanelListsPane.height(chosen: 300, column: 100, listsNeed: 600,
                                      belowIsEmpty: false, floor: 45) == 45)
    }

    @Test("Before anything is measured the pane is drawn at the height chosen")
    func unmeasured() {
        #expect(PanelListsPane.height(chosen: 280, column: nil, listsNeed: nil,
                                      belowIsEmpty: false, floor: 45) == 280)
        #expect(PanelListsPane.height(chosen: 280, column: 800, listsNeed: nil,
                                      belowIsEmpty: false, floor: 45) == 280)
    }

    @Test("Until the divider is moved the pane takes its share of the panel")
    func startsAtItsShare() {
        #expect(PanelListsPane.chosenHeight(stored: nil, column: 800) == 800 * PanelListsPane.defaultShare)
        #expect(PanelListsPane.chosenHeight(stored: nil, column: nil) == PanelListsPane.defaultHeight)
        #expect(PanelListsPane.chosenHeight(stored: 250, column: 800) == 250)
        // Nought is "never moved", which is what double clicking the divider writes.
        #expect(PanelListsPane.chosenHeight(stored: 0, column: 800) == 800 * PanelListsPane.defaultShare)
    }

    @Test("The divider runs from the pane's first header to whatever its lists need, short of the floor below")
    func gripRange() {
        // Lists longer than the panel can spare: the floor below stops it.
        #expect(PanelListsPane.gripCeiling(column: 700, listsNeed: 2000, floor: 45) == 700 - PanelListsPane.belowFloor)
        // A short list: no further than its last row, so no blank band can be dragged open.
        #expect(PanelListsPane.gripCeiling(column: 700, listsNeed: 200, floor: 45) == 200)
        // Never under its own floor.
        #expect(PanelListsPane.gripCeiling(column: 700, listsNeed: 20, floor: 45) == 45)
        #expect(PanelListsPane.maxAllowedHeight(column: 100, floor: 45) == 45)
    }

    @Test("Each kind of document remembers its own divider")
    func rememberedPerKind() {
        #expect(PanelListsPane.heightKey(forKind: "image") == "inspector.listsPaneHeight.image")
        #expect(PanelListsPane.heightKey(forKind: "video") != PanelListsPane.heightKey(forKind: "image"))
    }

    // MARK: A list inside the pane

    @Test("In the pane a list grows into the room the pane holds before it scrolls")
    func aListInThePaneFillsIt() {
        // Six layers want 270pt; the list's own grab bar was left at 200 and
        // the pane has room for all of it, so nothing caps it at 200.
        #expect(PanelListsPane.listAsks(content: 270, grabBar: 200, inPane: true) == 270)
        #expect(PanelListsPane.listCeiling(grabBar: 200, dock: nil, inPane: true) == .greatestFiniteMagnitude)
        // A list longer than the pane is drawn to the share the pane hands
        // it, which is the whole of the room under its header, then scrolls.
        #expect(PanelListsPane.listCeiling(grabBar: 200, dock: 310, inPane: true) == 310)
        #expect(PanelListsPane.listCeiling(grabBar: 600, dock: 310, inPane: true) == 310)
    }

    @Test("Outside the pane the list's own grab bar still caps it")
    func outsideThePaneTheGrabBarCaps() {
        #expect(PanelListsPane.listAsks(content: 270, grabBar: 200, inPane: false) == 200)
        #expect(PanelListsPane.listAsks(content: 120, grabBar: 200, inPane: false) == 120)
        #expect(PanelListsPane.listCeiling(grabBar: 200, dock: nil, inPane: false) == 200)
        #expect(PanelListsPane.listCeiling(grabBar: 200, dock: 150, inPane: false) == 150)
        #expect(PanelListsPane.listCeiling(grabBar: 200, dock: 310, inPane: false) == 200)
    }

    @Test("A list told it is in a pane fills the room under it before it scrolls")
    func theShelfFillsThePane() {
        // library-shelf-height-walk, 2026-10-15: five starter cards want 344pt,
        // the shelf's grab bar was pulled up to 105 and the pane had 172 for
        // the shelf. It stopped at 105 over 67pt of blank glass.
        #expect(PanelListsPane.listAsks(content: 344, grabBar: 105, inPane: true) == 344)
        #expect(PanelListsPane.listCeiling(grabBar: 105, dock: 172, inPane: true) == 172)
        #expect(PanelListsPane.listCeiling(grabBar: 105, dock: 172, inPane: false) == 105)
    }

    @Test("What the pick needs: its headers, open bodies and the dividers, with the padding")
    func pickNeedsAddsUpItsSections() {
        let needs = PanelListsPane.contentHeight(
            [(header: 33, body: nil), (header: 33, body: 97), (header: 33, body: nil)],
            padding: 6, divider: 1)
        let expected: CGFloat = 6 + 34 + 34 + 97 + 34 + 6
        #expect(needs == expected)
        #expect(PanelListsPane.contentHeight([], padding: 6, divider: 1) == 12)
    }

    @Test("What the pick needs is unknown while an open section is unmeasured")
    func pickNeedsWaitsForMeasurements() {
        #expect(PanelListsPane.contentHeight([(header: nil, body: nil)], padding: 6, divider: 1) == nil)
    }
}
