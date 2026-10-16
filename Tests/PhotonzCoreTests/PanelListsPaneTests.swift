import CoreGraphics
import Testing
@testable import PhotonzCore

/// The panel splits like Photoshop's Properties over Layers: the pick's own
/// sections on top, the document's lists in a pane at the bottom that keeps
/// its height whatever is picked or folded (the user, 2026-10-13, option B of "Where do
/// Layers and Library sit when something is picked?").
@Suite("The lists pane under the pick")
struct PanelListsPaneTests {

    @Test("A rectangle picked: its sections on top, Layers and Library below")
    func rectangleSplits() {
        let split = PanelListsPane.split(["layers", "color", "effects", "motion", "library"])
        #expect(split.pick == ["color", "effects", "motion"])
        #expect(split.lists == ["layers", "library"])
    }

    @Test("A tool's settings stay with the pick, never in the lists pane")
    func toolSettingsStayOnTop() {
        let split = PanelListsPane.split(["layers", "measureTool", "color", "measurements", "library"])
        #expect(split.pick == ["measureTool", "color"])
        #expect(split.lists == ["layers", "measurements", "library"])
    }

    @Test("On a video Captions and Transitions stay at the foot of the pick's column")
    func videoKeepsItsFormsWithThePick() {
        let split = PanelListsPane.split(["keys", "speed", "color", "captions", "transitions"])
        #expect(split.pick == ["keys", "speed", "color", "captions", "transitions"])
        #expect(split.lists.isEmpty)
    }

    @Test("A video with its timeline folded away gets its Layers list back, in the pane")
    func videoWithTheTimelineFolded() {
        let split = PanelListsPane.split(["layers", "keys", "captions", "transitions"])
        #expect(split.pick == ["keys", "captions", "transitions"])
        #expect(split.lists == ["layers"])
    }

    @Test("The picked tile's own section is about the pick, so it sits on top")
    func libraryItemIsThePick() {
        let split = PanelListsPane.split(["layers", "libraryItem", "library"])
        #expect(split.pick == ["libraryItem"])
        #expect(split.lists == ["layers", "library"])
    }

    @Test("Nothing picked: nothing on top, and the lists keep their place")
    func nothingPicked() {
        let split = PanelListsPane.split(["layers", "library"])
        #expect(split.pick.isEmpty)
        #expect(split.lists == ["layers", "library"])
    }

    @Test("The pane is the height you left it, whatever the pick")
    func keepsItsHeight() {
        let a = PanelListsPane.height(stored: 300, held: nil, column: 700, lists: ["layers"], floor: 45)
        let b = PanelListsPane.height(stored: 300, held: nil, column: 700, lists: ["layers"], floor: 45)
        #expect(a == 300)
        #expect(a == b)
    }

    // The pane used to shrink to its content, anchored at the panel's foot, so
    // folding Layers dropped its header about 93pt and switching the Library
    // from Media to Comps lifted its scope control 65pt: the second click on
    // the same spot missed (2026-10-14). The user's answer was a pane that
    // KEEPS its height; a Photoshop panel keeps its size whatever it holds.
    @Test("Short or folded lists leave the pane the height it was, so nothing moves under the pointer")
    func keepsItsHeightWhenItsListsShrink() {
        #expect(PanelListsPane.height(stored: 300, held: nil, column: 700, lists: ["layers"], floor: 45) == 300)
        let held = PanelListsPane.Hold(column: 700, lists: ["layers", "library"], height: 330)
        // Layers folded: what the lists need at their least drops, the pane does not.
        #expect(PanelListsPane.height(stored: nil, held: held, column: 700, lists: ["layers", "library"],
                                      floor: 45, fit: 120) == 330)
        // Comps in place of Media: the same.
        #expect(PanelListsPane.height(stored: nil, held: held, column: 700, lists: ["layers", "library"],
                                      floor: 45, fit: 345) == 330)
    }

    @Test("The pane's starting height is worked out once its lists are measured, and then held")
    func holdsItsStartingHeight() {
        let lists = ["layers", "library"]
        // Nothing measured yet: nothing to hold, the pane takes its share.
        #expect(PanelListsPane.hold(nil, column: 930, lists: lists, fit: nil) == nil)
        #expect(PanelListsPane.hold(nil, column: nil, lists: lists, fit: 413) == nil)
        // Measured: the height it starts at is held...
        let first = PanelListsPane.hold(nil, column: 930, lists: lists, fit: 413)
        #expect(first == PanelListsPane.Hold(column: 930, lists: lists, height: 413))
        // ...and lists needing less (Comps in place of Media) leave it alone.
        #expect(PanelListsPane.hold(first, column: 930, lists: lists, fit: 200) == first)
        #expect(PanelListsPane.hold(first, column: 930, lists: lists, fit: nil) == first)
    }

    @Test("A held pane grows when its lists need more room at their least, so a shelf is never cut across its foot")
    func holdGrowsForItsLists() {
        let lists = ["layers", "library"]
        let first = PanelListsPane.Hold(column: 930, lists: lists, height: 372)
        // A style saved onto an empty Styles shelf: the shelf needs a whole row.
        #expect(PanelListsPane.hold(first, column: 930, lists: lists, fit: 440)
            == PanelListsPane.Hold(column: 930, lists: lists, height: 440))
        // ...never past half the panel.
        #expect(PanelListsPane.hold(first, column: 930, lists: lists, fit: 900)
            == PanelListsPane.Hold(column: 930, lists: lists, height: 465))
    }

    @Test("A new window height, or a list joining the pane, works the height out again")
    func rehold() {
        let lists = ["layers", "library"]
        let first = PanelListsPane.Hold(column: 930, lists: lists, height: 413)
        // The window made shorter: half of the new panel at most.
        #expect(PanelListsPane.hold(first, column: 410, lists: lists, fit: 413)
            == PanelListsPane.Hold(column: 410, lists: lists, height: 205))
        // Measurements arrives in the pane.
        let three = ["layers", "measurements", "library"]
        #expect(PanelListsPane.hold(first, column: 930, lists: three, fit: 465)
            == PanelListsPane.Hold(column: 930, lists: three, height: 465))
        // A hold for another window height or other lists is not read.
        #expect(PanelListsPane.height(stored: nil, held: first, column: 410, lists: lists, floor: 45)
            == 410 * PanelListsPane.defaultShare)
        #expect(PanelListsPane.height(stored: nil, held: first, column: 930, lists: three, floor: 45)
            == 930 * PanelListsPane.defaultShare)
    }

    @Test("The pick always keeps room of its own, however tall the pane was left")
    func pickKeepsAFloor() {
        let height = PanelListsPane.height(stored: 900, held: nil, column: 600, lists: ["layers"], floor: 45)
        #expect(height == 600 - PanelListsPane.pickFloor)
    }

    @Test("A window too short for both still shows the pane's first header")
    func tinyWindow() {
        #expect(PanelListsPane.height(stored: 300, held: nil, column: 100, lists: ["layers"], floor: 45) == 45)
    }

    @Test("Before anything is laid out the pane takes the height it was left")
    func unmeasured() {
        #expect(PanelListsPane.height(stored: 280, held: nil, column: 700, lists: ["layers"], floor: 45) == 280)
        #expect(PanelListsPane.height(stored: 280, held: nil, column: nil, lists: ["layers"], floor: 45) == 280)
    }

    @Test("A height the grip set beats the held one")
    func gripBeatsTheHold() {
        let held = PanelListsPane.Hold(column: 700, lists: ["layers"], height: 330)
        #expect(PanelListsPane.height(stored: 250, held: held, column: 700, lists: ["layers"], floor: 45) == 250)
    }

    @Test("Until the grip is moved the pane takes its share of the panel, so a laptop keeps the pick")
    func startsAtItsShare() {
        // A laptop window over a video: 410pt shared. The pick keeps most.
        let laptop = PanelListsPane.height(stored: nil, held: nil, column: 410, lists: ["layers"], floor: 45)
        #expect(laptop == 410 * PanelListsPane.defaultShare)
        #expect(410 - laptop > laptop)
        // Nothing laid out yet: the plain default.
        #expect(PanelListsPane.height(stored: nil, held: nil, column: nil, lists: ["layers"], floor: 45)
            == PanelListsPane.defaultHeight)
    }

    @Test("Until the grip is moved, the pane is tall enough for its lists at their least, up to half the panel")
    func startsTallEnoughForItsLists() {
        let lists = ["layers", "library"]
        // Layers and the Library at their floors need 413pt of a 930pt panel:
        // more than the pane's 40 per cent, so the pane takes 413 and the
        // shelf is not cut across its foot.
        #expect(PanelListsPane.height(stored: nil, held: nil, column: 930, lists: lists, floor: 45, fit: 413) == 413)
        // ...but never more than half: a laptop window keeps half for the pick.
        #expect(PanelListsPane.height(stored: nil, held: nil, column: 410, lists: lists, floor: 45, fit: 413) == 205)
        // A height the grip set is the person's, whatever the lists need.
        #expect(PanelListsPane.height(stored: 200, held: nil, column: 930, lists: lists, floor: 45, fit: 413) == 200)
    }

    @Test("The highest the grip may set the pane leaves the pick its floor")
    func maxAllowed() {
        #expect(PanelListsPane.maxAllowedHeight(column: 700, floor: 45) == 700 - PanelListsPane.pickFloor)
        #expect(PanelListsPane.maxAllowedHeight(column: 100, floor: 45) == 45)
    }

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

    @Test("In the pane the Library shelf fills the room under it before it scrolls")
    func theShelfFillsThePane() {
        // library-shelf-height-walk, 2026-10-15: five starter cards want 344pt,
        // the shelf's grab bar was pulled up to 105 and the pane had 172 for
        // the shelf. It stopped at 105 over 67pt of blank glass.
        #expect(PanelListsPane.listAsks(content: 344, grabBar: 105, inPane: true) == 344)
        #expect(PanelListsPane.listCeiling(grabBar: 105, dock: 172, inPane: true) == 172)
        #expect(PanelListsPane.listCeiling(grabBar: 105, dock: 172, inPane: false) == 105)
    }
}
