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
        do { let said = asks.refreshed(); #expect(said) }
        do { let said = asks.refreshed(); #expect(!said) }
        do { let said = asks.handMoved(atRefresh: 2); #expect(said) }
    }

    @Test("A frame landing while a picture is on its way waits for that picture")
    func landingWaitsForThePictureOnItsWay() {
        var asks = ScrubPictureAsks()
        let first = asks.asked()
        asks.frameLanded()
        #expect(asks.pictureOnItsWay)
        do { let said = asks.refreshed(); #expect(!said) }
        do { let said = asks.refreshed(); #expect(!said) }
        asks.shown(first)
        #expect(!asks.pictureOnItsWay)
        do { let said = asks.refreshed(); #expect(said) }
        do { let said = asks.refreshed(); #expect(!said) }
    }

    @Test("A frame landing with nothing on its way is asked for at the next refresh")
    func landingWithNothingOnItsWay() {
        var asks = ScrubPictureAsks()
        asks.shown(asks.asked())
        asks.frameLanded()
        do { let said = asks.refreshed(); #expect(said) }
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
        do { let said = asks.refreshed(); #expect(!said) }
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
        do { let said = asks.refreshed(); #expect(said) }
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
        do { let said = asks.refreshed(); #expect(!said) }
    }
}
