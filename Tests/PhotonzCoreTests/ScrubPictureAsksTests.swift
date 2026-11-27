import PhotonzCore
import Testing

/// When a canvas asks for a picture while a hand drags the playhead
/// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 17).
///
/// The first move of a refresh is asked for at once; a second move in the
/// same refresh waits for the next one. A frame that lands from the decoder
/// waits too, and while a picture is still on its way it waits for that
/// picture: the picture asked for next is drawn from every frame in hand,
/// the landed one included, so asking again on the refresh drew the same
/// picture twice and held the main thread while the first was trying to go up.
@Suite("A scrub asks for a picture once a refresh")
struct ScrubPictureAsksTests {

    @Test("The first move of a refresh is asked for at once, a second one at the next refresh")
    func movesByRefresh() {
        var asks = ScrubPictureAsks()
        do { let said = asks.handMoved(atRefresh: 1); #expect(said) }
        _ = asks.asked()
        do { let said = asks.handMoved(atRefresh: 1); #expect(!said) }
        // A move left waiting is asked for at the refresh, picture on its way or not.
        do { let said = asks.refreshed(atRefresh: 2); #expect(said) }
        do { let said = asks.refreshed(atRefresh: 3); #expect(!said) }
        do { let said = asks.handMoved(atRefresh: 2); #expect(said) }
    }

    @Test("A frame landing while a picture is on its way waits for that picture")
    func landingWaitsForThePictureOnItsWay() {
        var asks = ScrubPictureAsks()
        let first = asks.asked()
        asks.frameLanded()
        #expect(asks.pictureOnItsWay)
        do { let said = asks.refreshed(atRefresh: 9); #expect(!said) }
        do { let said = asks.refreshed(atRefresh: 9); #expect(!said) }
        asks.shown(first)
        #expect(!asks.pictureOnItsWay)
        do { let said = asks.refreshed(atRefresh: 9); #expect(said) }
        do { let said = asks.refreshed(atRefresh: 9); #expect(!said) }
    }

    @Test("A frame landing with nothing on its way is asked for at the next refresh")
    func landingWithNothingOnItsWay() {
        var asks = ScrubPictureAsks()
        asks.shown(asks.asked())
        asks.frameLanded()
        do { let said = asks.refreshed(atRefresh: 9); #expect(said) }
    }

    @Test("The hand's own next move takes a landing with it")
    func aMoveTakesTheLandingWithIt() {
        var asks = ScrubPictureAsks()
        let first = asks.asked()
        asks.frameLanded()
        do { let said = asks.handMoved(atRefresh: 1); #expect(said) }
        let second = asks.asked()
        asks.shown(first)
        asks.shown(second)
        do { let said = asks.refreshed(atRefresh: 9); #expect(!said) }
    }

    @Test("Pictures skipped on the way count as shown once a later one arrives")
    func skippedPicturesAreNotWaitedFor() {
        var asks = ScrubPictureAsks()
        _ = asks.asked()
        _ = asks.asked()
        let third = asks.asked()
        asks.frameLanded()
        asks.shown(third)
        #expect(!asks.pictureOnItsWay)
        do { let said = asks.refreshed(atRefresh: 9); #expect(said) }
        // An older picture arriving late does not put anything back on its way.
        asks.shown(1)
        #expect(!asks.pictureOnItsWay)
    }

    @Test("Letting go asks for whatever is still waiting, picture on its way or not")
    func lettingGo() {
        var asks = ScrubPictureAsks()
        _ = asks.asked()
        asks.frameLanded()
        do { let said = asks.lettingGo(); #expect(said) }
        do { let said = asks.lettingGo(); #expect(!said) }
        do { let said = asks.refreshed(atRefresh: 9); #expect(!said) }
    }

    // A frame that lands while the hand is moving rides with the hand's next
    // move rather than being drawn at the refresh on its own. Drawn on its
    // own it started a whole picture at the very start of the refresh, and
    // the move made a moment later waited behind it: on the 6 minute
    // reference edit that was most of the moments a dragged picture was two
    // or three refreshes behind the hand (`scrubbing-a-long-edit-never-trails-the-pointer-b`).

    @Test("A frame landing while the hand moves waits for the hand's next move")
    func landingWaitsWhileTheHandMoves() {
        var asks = ScrubPictureAsks()
        do { let said = asks.handMoved(atRefresh: 4); #expect(said) }
        asks.shown(asks.asked())
        asks.frameLanded()
        // The refresh straight after a move: the hand is moving, so its next
        // move carries the landed frame.
        do { let said = asks.refreshed(atRefresh: 5); #expect(!said) }
        #expect(asks.landingWaiting)
        do { let said = asks.handMoved(atRefresh: 5); #expect(said) }
        _ = asks.asked()
        #expect(!asks.landingWaiting)
    }

    @Test("A frame landing is drawn once the hand has held still for a refresh")
    func landingIsDrawnWhenTheHandHolds() {
        var asks = ScrubPictureAsks()
        do { let said = asks.handMoved(atRefresh: 4); #expect(said) }
        asks.shown(asks.asked())
        asks.frameLanded()
        do { let said = asks.refreshed(atRefresh: 5); #expect(!said) }
        // No move in refresh 5: the hand has stopped, and the frame is drawn.
        do { let said = asks.refreshed(atRefresh: 6); #expect(said) }
        do { let said = asks.refreshed(atRefresh: 7); #expect(!said) }
    }

    @Test("A move left waiting is still drawn at the next refresh while the hand moves")
    func aWaitingMoveIsNotHeld() {
        var asks = ScrubPictureAsks()
        do { let said = asks.handMoved(atRefresh: 4); #expect(said) }
        _ = asks.asked()
        do { let said = asks.handMoved(atRefresh: 4); #expect(!said) }
        asks.frameLanded()
        do { let said = asks.refreshed(atRefresh: 5); #expect(said) }
    }

    // The display link calls back anywhere from 1 to 9 ms after the refresh
    // it is for. Counted by its calls, a move made in that gap read as a
    // second move in the refresh before and waited for the late call, so its
    // picture missed the refresh it could have made
    // (`scrubbing-a-long-edit-never-trails-the-pointer-b`, pass 8).

    @Test("A move after a refresh whose call has not come yet is in the new refresh")
    func aRefreshCountsBeforeItsCall() {
        let interval = 1.0 / 120
        // The last call was for a refresh at 10.000 s, numbered 7.
        #expect(ScrubPictureAsks.refresh(at: 10.004, numbered: 7, lastRefreshAt: 10.0, interval: interval) == 7)
        // 1.5 ms after the next refresh, its call not come yet: refresh 8.
        #expect(ScrubPictureAsks.refresh(at: 10.0 + interval + 0.0015, numbered: 7,
                                         lastRefreshAt: 10.0, interval: interval) == 8)
        // ...and once its call comes, the call says 8 as well.
        let called = ScrubPictureAsks.refreshNumber(after: 7, at: 10.0 + interval, previousAt: 10.0, interval: interval)
        #expect(called == 8)
        #expect(ScrubPictureAsks.refresh(at: 10.0 + interval + 0.005, numbered: called,
                                         lastRefreshAt: 10.0 + interval, interval: interval) == 8)
        // Just short of the refresh is still the refresh before.
        #expect(ScrubPictureAsks.refresh(at: 10.0 + interval - 0.0005, numbered: 7,
                                         lastRefreshAt: 10.0, interval: interval) == 7)
        // Before the display has refreshed once there is only the number.
        #expect(ScrubPictureAsks.refresh(at: 3, numbered: 0, lastRefreshAt: 0, interval: interval) == 0)
    }

    @Test("A link paused between drags catches up with the clock when it calls again")
    func aPausedLinkCatchesUp() {
        let interval = 1.0 / 120
        var asks = ScrubPictureAsks()
        // The link last called for refresh 40, at 10 s, then paused. A drag
        // starts two seconds later: its first move is asked for at once.
        let first = ScrubPictureAsks.refresh(at: 12.0001, numbered: 40, lastRefreshAt: 10, interval: interval)
        #expect(first == 40 + 240)
        do { let said = asks.handMoved(atRefresh: first); #expect(said) }
        _ = asks.asked()
        // The link wakes and calls for the next refresh, at 12 s + one interval.
        let wokeAt = 12 + interval
        let woke = ScrubPictureAsks.refreshNumber(after: 40, at: wokeAt, previousAt: 10, interval: interval)
        #expect(woke == first + 1)
        do { let said = asks.refreshed(atRefresh: woke); #expect(!said) }
        // The next move, in that refresh, is the first of it: asked for at once.
        let second = ScrubPictureAsks.refresh(at: wokeAt + 0.0015, numbered: woke, lastRefreshAt: wokeAt, interval: interval)
        do { let said = asks.handMoved(atRefresh: second); #expect(said) }
    }

    @Test("The move after a late call's refresh is asked for at once, and the call then asks for nothing")
    func aMoveBeforeALateCallIsAskedAtOnce() {
        let interval = 1.0 / 120
        var asks = ScrubPictureAsks()
        // A move at refresh 7, asked for at once.
        do { let said = asks.handMoved(atRefresh: ScrubPictureAsks.refresh(at: 10.0015, numbered: 7, lastRefreshAt: 10, interval: interval)); #expect(said) }
        _ = asks.asked()
        // The next move, 1.5 ms after the next refresh, its call 5 ms late.
        let next = ScrubPictureAsks.refresh(at: 10 + interval + 0.0015, numbered: 7, lastRefreshAt: 10, interval: interval)
        do { let said = asks.handMoved(atRefresh: next); #expect(said) }
        _ = asks.asked()
        // The late call for that refresh has nothing left to ask for.
        let called = ScrubPictureAsks.refreshNumber(after: 7, at: 10 + interval, previousAt: 10, interval: interval)
        do { let said = asks.refreshed(atRefresh: called); #expect(!said) }
        // A second move in the same refresh waits for the next one.
        do { let said = asks.handMoved(atRefresh: ScrubPictureAsks.refresh(at: 10 + interval + 0.006, numbered: called, lastRefreshAt: 10 + interval, interval: interval)); #expect(!said) }
        do { let said = asks.refreshed(atRefresh: called + 1); #expect(said) }
    }
}
