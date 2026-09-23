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

/// The second rule of revealing, added on 2026-09-23: **after an action, the
/// panel looks at what the action produced.**
///
/// A reveal is the app pointing at something you could not have known was
/// there. It is not allowed to do that at the cost of the thing you just made:
/// dropping a component on the canvas scrolled the dock to the Library shelf
/// and pushed the new component's own section clean off the top of the panel,
/// so the answer to "what did I just put down" was above the edge and you had
/// to scroll back up to it.
///
/// The numbers in this suite are the ones a 1240x900 window really produced on
/// 2026-09-22 (queue/audits/2026-09-22-component-drag-lands-a-copy.json): a
/// dock 841 points tall, the new Component section at 169 with 171 points of
/// height, and the Library shelf at 893 with 218.
@Suite("DockReveal, keeping what an action produced")
struct DockRevealKeepingProducedTests {

    // MARK: The case this was written for

    @Test func refusesAShelfRevealThatWouldCutTheComponentJustDropped() {
        // Revealing the shelf wants to travel 270 points. The Component
        // section can only afford 169 before its head goes over the edge.
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 169, keepingWholeHeight: 171,
                                  viewportHeight: 841) == .produced(.top))
    }

    @Test func aShelfRevealThatFitsStillHappens() {
        // The same shelf in a taller dock: the whole of it can come up with
        // the Component section still whole, so the reveal gets what it asked
        // for.
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 0, keepingWholeHeight: 171,
                                  viewportHeight: 1111) == .nothing)
        #expect(DockReveal.reveal(sectionTop: 500, sectionHeight: 218,
                                  keepingWholeTop: 300, keepingWholeHeight: 171,
                                  viewportHeight: 700) == .reveal(.bottom))
    }

    // MARK: Nothing produced

    @Test func withNothingProducedItIsTheOldRuleExactly() {
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 0, keepingWholeHeight: 0,
                                  viewportHeight: 841) == .reveal(.bottom))
        #expect(DockReveal.reveal(sectionTop: 100, sectionHeight: 218,
                                  keepingWholeTop: 0, keepingWholeHeight: 0,
                                  viewportHeight: 841) == .nothing)
    }

    // MARK: A dock that must not twitch

    @Test func staysPutWhenTheProducedSectionCanAffordNothingAtAll() {
        // The produced section is already flush with the top: any travel
        // towards the shelf cuts it, so the dock does not move.
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 0, keepingWholeHeight: 171,
                                  viewportHeight: 841) == .nothing)
    }

    @Test func staysPutWhenNothingNeedsRevealingAndTheProducedSectionIsWhole() {
        #expect(DockReveal.reveal(sectionTop: 300, sectionHeight: 218,
                                  keepingWholeTop: 100, keepingWholeHeight: 171,
                                  viewportHeight: 841) == .nothing)
    }

    @Test func ignoresSubPointDustInTheCap() {
        // 0.3 of a point of room is not room, and spending it is a twitch.
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 0.3, keepingWholeHeight: 171,
                                  viewportHeight: 841) == .nothing)
    }

    // MARK: The produced section is the one that is off screen

    @Test func pullsTheProducedSectionBackWhenItHasRunOffTheTop() {
        // Whatever the reveal wanted, a produced section above the fold is
        // the thing the panel is for. This is the state the bug left behind.
        #expect(DockReveal.reveal(sectionTop: 623, sectionHeight: 218,
                                  keepingWholeTop: -101, keepingWholeHeight: 171,
                                  viewportHeight: 841) == .produced(.top))
    }

    @Test func pullsTheProducedSectionUpWhenARevealAboveWouldPushItOffTheBottom() {
        // The mirror image: the thing to reveal is above the fold, and
        // scrolling back up to it would take the produced section's foot past
        // the bottom edge. The dock goes as far up as the produced section's
        // own foot allows.
        #expect(DockReveal.reveal(sectionTop: -300, sectionHeight: 218,
                                  keepingWholeTop: 600, keepingWholeHeight: 171,
                                  viewportHeight: 841) == .produced(.bottom))
    }

    @Test func showsTheTopOfAProducedSectionTallerThanTheDock() {
        // It can never be whole, so its beginning is the part worth keeping,
        // exactly as a too-tall reveal target gets its top.
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 200, keepingWholeHeight: 900,
                                  viewportHeight: 841) == .produced(.top))
    }

    // MARK: Nothing measured yet

    @Test func doesNothingBeforeTheDockHasBeenMeasured() {
        #expect(DockReveal.reveal(sectionTop: 893, sectionHeight: 218,
                                  keepingWholeTop: 169, keepingWholeHeight: 171,
                                  viewportHeight: 0) == .nothing)
    }
}
