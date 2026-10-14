import CoreGraphics
import Testing
@testable import PhotonzCore

/// The panel splits like Photoshop's Properties over Layers: the pick's own
/// sections on top, the document's lists in a pane at the bottom that keeps
/// its height whatever is picked (the user, 2026-10-13, option B of "Where do
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
        let a = PanelListsPane.height(stored: 300, content: 900, column: 700, floor: 45)
        let b = PanelListsPane.height(stored: 300, content: 900, column: 700, floor: 45)
        #expect(a == 300)
        #expect(a == b)
    }

    @Test("Lists shorter than the pane, or folded to their headers, give the room back to the pick")
    func shrinksToItsContent() {
        #expect(PanelListsPane.height(stored: 300, content: 90, column: 700, floor: 45) == 90)
    }

    @Test("The pick always keeps room of its own, however tall the pane was left")
    func pickKeepsAFloor() {
        let height = PanelListsPane.height(stored: 900, content: 2000, column: 600, floor: 45)
        #expect(height == 600 - PanelListsPane.pickFloor)
    }

    @Test("A window too short for both still shows the pane's first header")
    func tinyWindow() {
        #expect(PanelListsPane.height(stored: 300, content: 900, column: 100, floor: 45) == 45)
    }

    @Test("Before anything is measured the pane takes the height it was left")
    func unmeasured() {
        #expect(PanelListsPane.height(stored: 280, content: nil, column: 700, floor: 45) == 280)
        #expect(PanelListsPane.height(stored: 280, content: nil, column: nil, floor: 45) == 280)
    }

    @Test("Until the grip is moved the pane takes its share of the panel, so a laptop keeps the pick")
    func startsAtItsShare() {
        // A laptop window over a video: 410pt shared. The pick keeps most.
        let laptop = PanelListsPane.height(stored: nil, content: 900, column: 410, floor: 45)
        #expect(laptop == 410 * PanelListsPane.defaultShare)
        #expect(410 - laptop > laptop)
        // Nothing laid out yet: the plain default.
        #expect(PanelListsPane.height(stored: nil, content: nil, column: nil, floor: 45)
            == PanelListsPane.defaultHeight)
    }

    @Test("Until the grip is moved, the pane is tall enough for its lists at their least, up to half the panel")
    func startsTallEnoughForItsLists() {
        // Layers and the Library at their floors need 413pt of a 930pt panel:
        // more than the pane's 40 per cent, so the pane takes 413 and the
        // shelf is not cut across its foot.
        #expect(PanelListsPane.height(stored: nil, content: 600, column: 930, floor: 45, fit: 413) == 413)
        // ...but never more than half: a laptop window keeps half for the pick.
        #expect(PanelListsPane.height(stored: nil, content: 600, column: 410, floor: 45, fit: 413) == 205)
        // A height the grip set is the person's, whatever the lists need.
        #expect(PanelListsPane.height(stored: 200, content: 600, column: 930, floor: 45, fit: 413) == 200)
    }

    @Test("The highest the grip may set the pane leaves the pick its floor")
    func maxAllowed() {
        #expect(PanelListsPane.maxAllowedHeight(column: 700, floor: 45) == 700 - PanelListsPane.pickFloor)
        #expect(PanelListsPane.maxAllowedHeight(column: 100, floor: 45) == 45)
    }
}
