import CoreGraphics
import Testing
@testable import PhotonzCore

/// The top edge of the timeline dock is a drag handle (user 2026-09-28: "make
/// the pane vertically resizable similar to the right panel"). These pin what
/// the edge may do: the tracks area never shrinks past one track, the dock
/// never takes more than about 70% of the window, a drag moves the edge one
/// for one with the pointer, and nothing chosen means the height it always had.
@Suite("Timeline dock height")
struct TimelineDockHeightTests {

    // The transport and the timeline's bar are about 92 tall together; the
    // tracks area can be no shorter than a ruler, one track and its scroller.
    let sizing = TimelineDockHeight(chrome: 92, floor: 70, windowHeight: 1000)

    /// Layout is floating point: 70% of 1000 is not exactly 700.
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    // MARK: The ceiling

    @Test("The dock may take up to 70% of the window, transport and bar included")
    func ceilingIsSeventyPercent() {
        #expect(near(sizing.ceiling, 700 - 92))
    }

    @Test("In a window too short for the share, the floor still wins")
    func floorBeatsCeilingInATinyWindow() {
        let tiny = TimelineDockHeight(chrome: 92, floor: 70, windowHeight: 200)
        #expect(tiny.ceiling == 70)
        #expect(tiny.body(chosen: 400, natural: 150) == 70)
        #expect(tiny.body(chosen: nil, natural: 150) == 70)
    }

    // MARK: What the tracks area is given

    @Test("With nothing chosen the dock is as tall as it always was")
    func nothingChosenIsNatural() {
        #expect(sizing.body(chosen: nil, natural: 180) == 180)
    }

    @Test("With nothing chosen a short window still caps it")
    func naturalIsCapped() {
        let short = TimelineDockHeight(chrome: 92, floor: 70, windowHeight: 300)
        #expect(near(short.body(chosen: nil, natural: 180), 300 * 0.7 - 92))
    }

    @Test("A chosen height is kept, even taller than the tracks inside it")
    func chosenIsKept() {
        #expect(sizing.body(chosen: 420, natural: 180) == 420)
        #expect(sizing.body(chosen: 90, natural: 180) == 90)
    }

    @Test("A chosen height past either end is held at that end")
    func chosenIsClamped() {
        #expect(sizing.body(chosen: 20, natural: 180) == 70)
        #expect(near(sizing.body(chosen: 900, natural: 180), 608))
    }

    @Test("A window made shorter squeezes a chosen height, and gives it back when it grows")
    func windowResizeSqueezesThenRestores() {
        let short = TimelineDockHeight(chrome: 92, floor: 70, windowHeight: 500)
        #expect(near(short.body(chosen: 420, natural: 180), 350 - 92))
        #expect(sizing.body(chosen: 420, natural: 180) == 420)
    }

    // MARK: A drag on the edge

    @Test("Pulling the edge up makes the tracks taller by exactly as far")
    func dragUpGrows() {
        #expect(sizing.dragged(fromBody: 180, pointerMovedDown: -120) == 300)
    }

    @Test("Pushing the edge down makes them shorter by exactly as far")
    func dragDownShrinks() {
        #expect(sizing.dragged(fromBody: 180, pointerMovedDown: 60) == 120)
    }

    @Test("A drag stops at one track and at the window's share")
    func dragIsClamped() {
        #expect(sizing.dragged(fromBody: 180, pointerMovedDown: 500) == 70)
        #expect(near(sizing.dragged(fromBody: 180, pointerMovedDown: -900), 608))
    }

    // MARK: What is remembered

    @Test("Nothing on file, or zero, means the default height")
    func storedZeroIsDefault() {
        #expect(TimelineDockHeight.chosen(stored: 0) == nil)
        #expect(TimelineDockHeight.chosen(stored: -4) == nil)
        #expect(TimelineDockHeight.chosen(stored: 260) == 260)
    }

    @Test("The default is written as zero, so a double-click forgets the choice")
    func defaultIsStoredAsZero() {
        #expect(TimelineDockHeight.defaultStored == 0)
    }
}
