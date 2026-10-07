import CoreGraphics
import PhotonzCore
import Testing

/// The dock builds a section's settings only when they are near enough to be
/// seen. These tests pin who waits (a section that arrives starting well below
/// the bottom of the dock), who never does (the top section, anything within
/// reach, anything the dock cannot place yet), and that a section built once
/// stays built for as long as it stays in the dock.
@Suite("PanelBodyReach")
struct PanelBodyReachTests {

    /// A clip's dock, as measured on a five minute recording: a 606pt view.
    let viewport: CGFloat = 606

    // MARK: Who waits

    @Test func theTopSectionIsNeverHeld() {
        var reach = PanelBodyReach()
        reach.draw(["keys"], bottoms: [:], viewport: viewport)
        #expect(reach.isHeld("keys") == false)
    }

    @Test func aSectionArrivingWellBelowTheFoldIsHeld() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        // Gain arrives next pass, under Fades, which ended at 906.
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        #expect(reach.isHeld("gain"))
        #expect(reach.isHeld("fades") == false)
    }

    @Test func aSectionArrivingWithinReachOfTheFoldIsBuilt() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "sound"], bottoms: [:], viewport: viewport)
        // Starts 77pt under the bottom edge: a slow scroll shows it next.
        reach.draw(["keys", "sound", "fades"], bottoms: ["keys": 180, "sound": 683], viewport: viewport)
        #expect(reach.isHeld("fades") == false)
    }

    @Test func aDockThatHasNotMeasuredItselfBuildsEverything() {
        var reach = PanelBodyReach()
        reach.draw(["keys"], bottoms: [:], viewport: nil)
        reach.draw(["keys", "captions"], bottoms: ["keys": 2000], viewport: nil)
        #expect(reach.isHeld("captions") == false)
    }

    @Test func sectionsArrivingTogetherAreBuiltBecauseNothingAboveThemIsPlacedYet() {
        // A window opening shows every section in its first pass: nothing has
        // a place yet, so nothing can be said to be out of sight.
        var reach = PanelBodyReach()
        reach.draw(["keys", "time", "captions"], bottoms: ["keys": 4000, "time": 5000],
                   viewport: viewport)
        #expect(reach.held.isEmpty)
    }

    @Test func aSectionUnderOneThatArrivedThisSamePassIsBuilt() {
        // Its neighbour's bottom is a stale number from an earlier visit.
        var reach = PanelBodyReach()
        reach.draw(["keys"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "time", "captions"], bottoms: ["keys": 180, "time": 2000],
                   viewport: viewport)
        #expect(reach.isHeld("captions") == false)
    }

    @Test func aSectionUnderAHeldOneIsHeldToo() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        reach.draw(["keys", "fades", "gain", "captions"],
                   bottoms: ["keys": 180, "fades": 906, "gain": 1021], viewport: viewport)
        #expect(reach.isHeld("gain"))
        #expect(reach.isHeld("captions"))
    }

    // MARK: Who stays

    @Test func aBuiltSectionCarriedBelowTheFoldStaysBuilt() {
        // A cut's Edit point section, built at the top, carried to 974 by a
        // clip pick: it is not held, so the next cut finds it already there.
        var reach = PanelBodyReach()
        reach.draw(["editPoint", "transitions"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "editPoint", "transitions"], bottoms: ["editPoint": 1084, "transitions": 1400],
                   viewport: viewport)
        #expect(reach.held.isEmpty)
    }

    @Test func aHeldSectionStaysHeldWhileItStaysInTheDock() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 300, "gain": 400],
                   viewport: viewport)
        #expect(reach.isHeld("gain"))
    }

    @Test func aSectionThatLeavesAndComesBackIsDecidedAgain() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        reach.draw(["editPoint"], bottoms: [:], viewport: viewport)
        #expect(reach.held.isEmpty)
        reach.draw(["editPoint", "gain"], bottoms: ["editPoint": 116], viewport: viewport)
        #expect(reach.isHeld("gain") == false)
    }

    @Test func drawingTheSamePassTwiceChangesNothing() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        let once = reach
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        #expect(reach == once)
    }

    // MARK: Coming into sight

    @Test func aHeldSectionScrolledWithinReachAsksToBeBuilt() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        #expect(reach.comesNear("gain", top: 900, viewport: viewport) == false)
        #expect(reach.comesNear("gain", top: 700, viewport: viewport))
        #expect(reach.comesNear("fades", top: 10, viewport: viewport) == false)
    }

    @Test func theTopmostSectionThatCameNearIsBuiltFirst() {
        var reach = PanelBodyReach()
        reach.draw(["keys", "fades"], bottoms: [:], viewport: viewport)
        reach.draw(["keys", "fades", "gain"], bottoms: ["keys": 180, "fades": 906], viewport: viewport)
        reach.draw(["keys", "fades", "gain", "captions"],
                   bottoms: ["keys": 180, "fades": 906, "gain": 1021], viewport: viewport)
        #expect(reach.nextToBuild(among: ["captions", "gain"]) == "gain")
        reach.build("gain")
        #expect(reach.isHeld("gain") == false)
        #expect(reach.nextToBuild(among: ["captions", "gain"]) == "captions")
        reach.buildAll()
        #expect(reach.held.isEmpty)
        #expect(reach.nextToBuild(among: ["captions"]) == nil)
    }

    // MARK: Rows inside a section

    @Test func rowsOnScreenOrJustOffItAreWithinReach() {
        #expect(PanelBodyReach.isWithinReach(top: 100, bottom: 400, viewport: viewport))
        // Starting just under the bottom edge, or ending just over the top.
        #expect(PanelBodyReach.isWithinReach(top: 700, bottom: 1000, viewport: viewport))
        #expect(PanelBodyReach.isWithinReach(top: -400, bottom: -60, viewport: viewport))
    }

    @Test func rowsCarriedFarBelowOrScrolledFarAboveAreOutOfReach() {
        // Captions' styles after a clip pick: the section starts at 1382.
        #expect(PanelBodyReach.isWithinReach(top: 1520, bottom: 2100, viewport: viewport) == false)
        #expect(PanelBodyReach.isWithinReach(top: -900, bottom: -300, viewport: viewport) == false)
    }

    @Test func rowsAreLetGoWellBeforeTheNextClick() {
        // The quickest click after a pick that the walks time comes about
        // 0.7s later; a scroll past them takes longer than a frame or two.
        #expect(PanelBodyReach.letGoAfter > 0.2)
        #expect(PanelBodyReach.letGoAfter < 0.7)
    }
}
