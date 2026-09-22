import Foundation
import PhotonzCore
import Testing

/// A guide's card goes away when somebody buries the window it is teaching in,
/// and stays put when the only thing looking at that window is a walk.
@Suite("Whether a guide's card is on screen")
struct TutorialCardPresenceTests {

    @Test("A person watching an uncovered window sees the card")
    func personSeesTheCard() {
        #expect(TutorialCardPresence.shouldBeOnScreen(
            miniaturized: false, windowVisible: true, aWalkIsDriving: false))
    }

    @Test("A person who buried the window does not get a card over what they are reading")
    func buriedForAPersonTakesTheCardAway() {
        #expect(!TutorialCardPresence.shouldBeOnScreen(
            miniaturized: false, windowVisible: false, aWalkIsDriving: false))
    }

    @Test("A miniaturized window has nowhere to put a card")
    func miniaturizedTakesTheCardAway() {
        #expect(!TutorialCardPresence.shouldBeOnScreen(
            miniaturized: true, windowVisible: true, aWalkIsDriving: false))
        #expect(!TutorialCardPresence.shouldBeOnScreen(
            miniaturized: true, windowVisible: true, aWalkIsDriving: true))
    }

    /// The whole point. A walk photographs the window it drives, and whatever
    /// else happens to be in front of that window — another app, the screen
    /// saver, the login window over a locked Mac — must not decide whether the
    /// card is in the picture. Otherwise the same walk on the same code answers
    /// one way with somebody at the Mac and another way with nobody there,
    /// which is what made 31 of 31 tutorial walks fail on the night of
    /// 2026-09-14.
    @Test("A covered window still gets its card while a walk is driving")
    func aWalkKeepsTheCard() {
        #expect(TutorialCardPresence.shouldBeOnScreen(
            miniaturized: false, windowVisible: false, aWalkIsDriving: true))
        #expect(TutorialCardPresence.shouldBeOnScreen(
            miniaturized: false, windowVisible: true, aWalkIsDriving: true))
    }

    @Test("A walk's answer does not depend on what is in front of the window")
    func theAnswerIsTheSameEitherWay() {
        for miniaturized in [true, false] {
            #expect(TutorialCardPresence.shouldBeOnScreen(
                miniaturized: miniaturized, windowVisible: true, aWalkIsDriving: true)
                == TutorialCardPresence.shouldBeOnScreen(
                    miniaturized: miniaturized, windowVisible: false, aWalkIsDriving: true))
        }
    }
}
