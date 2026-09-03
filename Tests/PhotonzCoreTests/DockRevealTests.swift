import CoreGraphics
import PhotonzCore
import Testing

/// What the right dock does when the app opens a section for you. The rule
/// that matters most is the first one: a section already on screen never
/// moves, because a dock that twitches every time you press a key is a dock
/// you stop trusting.
@Suite("DockReveal")
struct DockRevealTests {

    // MARK: Nothing to do

    @Test func leavesASectionAloneWhenItIsFullyOnScreen() {
        #expect(DockReveal.action(sectionTop: 100, sectionHeight: 300, viewportHeight: 800) == .none)
    }

    @Test func leavesASectionAloneWhenItEndsExactlyAtTheBottom() {
        #expect(DockReveal.action(sectionTop: 500, sectionHeight: 300, viewportHeight: 800) == .none)
    }

    @Test func leavesASectionAloneWhenItStartsExactlyAtTheTop() {
        #expect(DockReveal.action(sectionTop: 0, sectionHeight: 300, viewportHeight: 800) == .none)
    }

    @Test func ignoresSubPointDustAtEitherEdge() {
        #expect(DockReveal.action(sectionTop: -0.3, sectionHeight: 300, viewportHeight: 800) == .none)
        #expect(DockReveal.action(sectionTop: 500.3, sectionHeight: 300, viewportHeight: 800) == .none)
    }

    // MARK: Below the fold

    @Test func takesTheShortestMoveForASectionThatHangsOffTheBottom() {
        // The Library sitting at the bottom of a full dock: only its header is
        // on screen, so the dock scrolls just far enough to finish it.
        #expect(DockReveal.action(sectionTop: 760, sectionHeight: 300, viewportHeight: 800) == .bottom)
    }

    @Test func revealsASectionThatIsEntirelyPastTheBottom() {
        #expect(DockReveal.action(sectionTop: 900, sectionHeight: 300, viewportHeight: 800) == .bottom)
    }

    @Test func revealsASectionOnePointShortOfFitting() {
        #expect(DockReveal.action(sectionTop: 501, sectionHeight: 300, viewportHeight: 800) == .bottom)
    }

    // MARK: Above the fold

    @Test func scrollsBackUpToASectionThatHasRunOffTheTop() {
        #expect(DockReveal.action(sectionTop: -50, sectionHeight: 300, viewportHeight: 800) == .top)
    }

    @Test func scrollsBackUpToASectionEntirelyAboveTheFold() {
        #expect(DockReveal.action(sectionTop: -400, sectionHeight: 300, viewportHeight: 800) == .top)
    }

    // MARK: Taller than the dock

    @Test func showsTheStartOfASectionTooTallToFit() {
        // A long shelf in a short window can never be all on screen; its top is
        // the part worth showing.
        #expect(DockReveal.action(sectionTop: 300, sectionHeight: 600, viewportHeight: 400) == .top)
    }

    @Test func leavesATallSectionAloneWhileItFillsTheDock() {
        // Already covering the whole visible area: the reader has scrolled to a
        // spot inside it, and yanking them back to the top would lose it.
        #expect(DockReveal.action(sectionTop: -100, sectionHeight: 600, viewportHeight: 400) == .none)
    }

    @Test func pullsATallSectionBackWhenItHasSlippedPastTheBottom() {
        #expect(DockReveal.action(sectionTop: -550, sectionHeight: 600, viewportHeight: 400) == .top)
    }

    // MARK: Nothing measured yet

    @Test func doesNothingBeforeTheDockHasBeenMeasured() {
        #expect(DockReveal.action(sectionTop: 0, sectionHeight: 300, viewportHeight: 0) == .none)
        #expect(DockReveal.action(sectionTop: 0, sectionHeight: 0, viewportHeight: 800) == .none)
    }
}
