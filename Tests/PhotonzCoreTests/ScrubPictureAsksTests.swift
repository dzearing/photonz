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
}
