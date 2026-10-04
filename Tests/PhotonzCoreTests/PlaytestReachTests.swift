import CoreGraphics
import Testing
@testable import PhotonzCore

/// A walk that cannot tell "you have to scroll" from "something is on top of
/// it" reports the second for both, and a runner goes hunting for a bug that
/// is not there. These are the three answers, told apart.
@Suite("Whether a walk could press what it is pointing at")
struct PlaytestReachTests {

    /// A window 1000 points tall with a 600 point dock viewport in it, the way
    /// the editor is laid out: window coordinates run bottom up.
    private let window = CGRect(x: 0, y: 0, width: 1400, height: 1000)
    private let dock = CGRect(x: 1100, y: 200, width: 300, height: 600)

    private func row(atY y: Double, height: Double = 24) -> CGRect {
        CGRect(x: 1110, y: y, width: 280, height: height)
    }

    @Test("A control sitting in the open can be pressed")
    func inTheOpen() {
        #expect(PlaytestReach.problem(box: row(atY: 500), window: window, scrollStrip: dock) == nil)
    }

    @Test("A control whose box is whole inside the window but whose visible rect is short still counts as covered")
    func coveredBySomethingStill() {
        let problem = PlaytestReach.problem(box: row(atY: 500), window: window, scrollStrip: dock,
                                            visible: CGRect(x: 1110, y: 510, width: 280, height: 14))
        #expect(problem?.cutter == .somethingStill)
        #expect(problem?.side == .below)
    }

    /// The bug this exists for: a row a third of a point past the bottom of
    /// the list it is in, because a height was divided by three. It is on
    /// screen, a person can press it, and judged strictly it was out of reach
    /// and the list had no scroll left to give.
    @Test("A third of a point of overhang is arithmetic, not a hidden control")
    func subPointOverhangIsNotOutOfReach() {
        let justPast = CGRect(x: 1110, y: dock.minY - 0.34, width: 280, height: 24)
        #expect(PlaytestReach.problem(box: justPast, window: window, scrollStrip: dock) == nil)
    }

    @Test("A row scrolled below the dock's viewport is a scroller's doing")
    func belowTheViewport() {
        let problem = PlaytestReach.problem(box: row(atY: 120), window: window, scrollStrip: dock)
        #expect(problem?.cutter == .aScroller)
        #expect(problem?.side == .below)
        #expect(problem?.points == 80)
    }

    @Test("A row scrolled above the dock's viewport says above, by how far")
    func aboveTheViewport() {
        let problem = PlaytestReach.problem(box: row(atY: 900), window: window, scrollStrip: dock)
        #expect(problem?.cutter == .aScroller)
        #expect(problem?.side == .above)
        #expect(problem?.points == 124)
    }

    /// Nothing scrolls and it is off the window: a reveal must not claim
    /// something is covering it, and must not claim a scroll would help.
    @Test("Off the window with nothing scrolling blames the window")
    func offTheWindowEntirely() {
        let problem = PlaytestReach.problem(box: row(atY: 1200), window: window, scrollStrip: window)
        #expect(problem?.cutter == .theWindow)
        #expect(problem?.side == .above)
        #expect(problem?.points == 224)
    }

    /// Off the window AND inside something that scrolls is still the
    /// scroller's to fix, because turning its wheel is what brings it back.
    @Test("Off the window inside a scroller is still the scroller's doing")
    func offTheWindowButHeldByAScroller() {
        let problem = PlaytestReach.problem(box: row(atY: 1200), window: window, scrollStrip: dock)
        #expect(problem?.cutter == .aScroller)
    }

    @Test("A scrolling area with nothing of it on screen hides the whole control")
    func theListItselfIsOffTheWindow() {
        let problem = PlaytestReach.problem(box: row(atY: 500), window: window, scrollStrip: .null)
        #expect(problem?.cutter == .aScroller)
        #expect(problem?.points == 24)
    }

    @Test("A marker with no size of its own is judged by where it is")
    func anEmptyBoxIsJudgedByItsPoint() {
        let marker = CGRect(x: 1200, y: 500, width: 0, height: 0)
        #expect(PlaytestReach.problem(box: marker, window: window, scrollStrip: dock) == nil)
        let below = CGRect(x: 1200, y: 100, width: 0, height: 0)
        #expect(PlaytestReach.problem(box: below, window: window, scrollStrip: dock)?.cutter == .aScroller)
    }

    @Test("Nothing known to clip it means only the window and its scrollers decide")
    func infiniteVisibleDecidesNothing() {
        #expect(PlaytestReach.problem(box: row(atY: 500), window: window,
                                      scrollStrip: dock, visible: .infinite) == nil)
    }

    // MARK: What the walk prints

    @Test("Each of the three says which it is, and what would fix it")
    func sentencesTellThemApart() {
        let scroller = PlaytestReach.Problem(cutter: .aScroller, side: .below, points: 80)
        let said = PlaytestReach.sentence(scroller, control: "Corner Radius")
        #expect(said.contains("\"Corner Radius\""))
        #expect(said.contains("80pt"))
        #expect(said.contains("scrolling area"))
        // Nobody has scrolled yet, so it says what would work...
        #expect(said.contains("\"reveal\" step"))
        // ...and after a reveal has tried and got nowhere, it stops promising
        // the step that just failed.
        let afterTrying = PlaytestReach.sentence(scroller, control: "Corner Radius", tried: true)
        #expect(afterTrying.contains("would not scroll any further"))
        #expect(!afterTrying.contains("\"reveal\" step"))

        let stuck = PlaytestReach.Problem(cutter: .somethingStill, side: .below, points: 12)
        let stuckSaid = PlaytestReach.sentence(stuck, control: "Time section")
        #expect(stuckSaid.contains("cutting it off"))
        #expect(stuckSaid.contains("inside everything that scrolls"))

        let tooShort = PlaytestReach.Problem(cutter: .theWindow, side: .above, points: 224)
        let tooShortSaid = PlaytestReach.sentence(tooShort, control: "Layers section")
        #expect(tooShortSaid.contains("window itself"))
        #expect(tooShortSaid.contains("Make the window taller"))
    }

    @Test("A sideways overhang reads as a sentence, not as a word dropped in")
    func sidewaysReadsProperly() {
        let said = PlaytestReach.sentence(
            PlaytestReach.Problem(cutter: .aScroller, side: .right, points: 9), control: "Width")
        #expect(said.contains("past the right edge of"))
    }

    // MARK: Which scroller turns

    /// The bug this was written for (2026-10-04): with the dock at its top, the
    /// Library shelf showed 3 points of itself above the dock's bottom edge.
    /// The shelf, being innermost, took every turn, sliding a 106 point tile
    /// back and forth along a strip 3 points tall, and the dock that could
    /// have brought the whole shelf up never moved.
    @Test("A scroller showing less of itself than the control is tall hands the turn to the one around it")
    func aSliverOfAListDoesNotTakeTheTurn() {
        let tile = CGRect(x: 1478, y: 214, width: 114, height: 106)
        let shelfSliver = CGRect(x: 1478, y: 339, width: 236, height: 3)
        let dockStrip = CGRect(x: 1460, y: 339, width: 270, height: 600)
        let turns = PlaytestReach.turns(for: tile, reaches: [shelfSliver, dockStrip])
        #expect(turns.first?.index == 1)
        // Down the dock, which the wheel writes as a negative number, by the
        // whole gap and the margin.
        #expect(turns.first?.by == -(339 - 214 + PlaytestReach.revealMargin))
        #expect(!turns.contains { $0.index == 0 })
    }

    @Test("A scroller with room for the control turns first, innermost before the one around it")
    func innermostTurnsFirstWhenItCanHoldIt() {
        let tile = CGRect(x: 1478, y: 100, width: 114, height: 106)
        let shelf = CGRect(x: 1478, y: 300, width: 236, height: 160)
        let dockStrip = CGRect(x: 1460, y: 200, width: 270, height: 600)
        let turns = PlaytestReach.turns(for: tile, reaches: [shelf, dockStrip])
        #expect(turns.map(\.index) == [0, 1])
        #expect(turns[0].by == -(300 - 100 + PlaytestReach.revealMargin))
    }

    @Test("A scroller already holding the control has nothing to turn")
    func alreadyInsideIsNoTurn() {
        let row = CGRect(x: 1110, y: 400, width: 280, height: 24)
        let turns = PlaytestReach.turns(for: row, reaches: [dock])
        #expect(turns.isEmpty)
    }

    @Test("Above the strip, the wheel turns up")
    func aboveTurnsUp() {
        let row = CGRect(x: 1110, y: 820, width: 280, height: 24)
        let turns = PlaytestReach.turns(for: row, reaches: [dock])
        #expect(turns.first?.by == 844 - 800 + PlaytestReach.revealMargin)
    }

    /// A control taller than every strip around it cannot be shown whole by
    /// anything, but turning still brings the most of it in, so the old order
    /// stands rather than nothing being tried at all.
    @Test("When no strip can hold the control, every scroller still gets its turn, innermost first")
    func nothingCanHoldItKeepsTheOldOrder() {
        let tall = CGRect(x: 1110, y: -900, width: 280, height: 700)
        let turns = PlaytestReach.turns(for: tall, reaches: [CGRect(x: 1100, y: 300, width: 300, height: 100), dock])
        #expect(turns.map(\.index) == [0, 1])
    }
}
