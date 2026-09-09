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

    // MARK: One effect opened inside the Effects list
    //
    // The same rule, one level down. An effect is a small pane with a chevron,
    // and pressing it open grows it downwards: in a short window the settings
    // that appear can land past the bottom of the panel, so you press a
    // chevron and nothing you can see happens. The numbers here are the ones a
    // 1280x600 window really produced on 2026-09-08.

    @Test func bringsAnOpenedEffectUpFromBelowTheBottomOfTheDock() {
        // Shadow opened at the foot of a 568pt dock: 49pt of it hangs off.
        #expect(DockReveal.action(sectionTop: 383, sectionHeight: 234,
                                  viewportHeight: 568) == .bottom)
    }

    @Test func leavesAnOpenedEffectAloneWhenItIsAlreadyWhollyOnScreen() {
        // The ordinary case, and the one that must never move: a panel with
        // room for the effect you just opened does not scroll at all.
        #expect(DockReveal.action(sectionTop: 200, sectionHeight: 234,
                                  viewportHeight: 568) == .none)
    }

    @Test func showsTheTopOfAnEffectTooTallForTheRoomItIsIn() {
        // Inside a squeezed Effects list the room is the list's own window, not
        // the dock: an effect taller than that window shows its heading and its
        // first settings rather than its end.
        #expect(DockReveal.action(sectionTop: 120, sectionHeight: 234,
                                  viewportHeight: 186) == .top)
    }

    // MARK: Nothing measured yet

    @Test func doesNothingBeforeTheDockHasBeenMeasured() {
        #expect(DockReveal.action(sectionTop: 0, sectionHeight: 300, viewportHeight: 0) == .none)
        #expect(DockReveal.action(sectionTop: 0, sectionHeight: 0, viewportHeight: 800) == .none)
    }
}
