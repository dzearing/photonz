import CoreGraphics
import Testing
@testable import PhotonzCore

/// While a Library tile is the pick, the timeline keeps the height it had, so
/// the shelf above it never moves between the two clicks of a double click.
@Suite("Timeline height hold")
struct TimelineHeightHoldTests {

    @Test("Nothing held: the timeline is as tall as its tracks, every time")
    func followsTheTracksWhenFree() {
        var hold = TimelineHeightHold()
        #expect(hold.natural(220, holding: false) == 220)
        #expect(hold.natural(140, holding: false) == 140)
        #expect(hold.natural(300, holding: false) == 300)
    }

    @Test("A tile picked over a layer whose rows fold keeps the taller height")
    func keepsTheHeightTheTileWasClickedAt() {
        var hold = TimelineHeightHold()
        _ = hold.natural(260, holding: false) // a title's parts open under it
        #expect(hold.natural(180, holding: true) == 260)
        // ...and for every pass while the tile stays picked.
        #expect(hold.natural(180, holding: true) == 260)
    }

    @Test("Tracks that grow while a tile is picked still get their room")
    func growsWhileHeld() {
        var hold = TimelineHeightHold()
        _ = hold.natural(180, holding: false)
        #expect(hold.natural(240, holding: true) == 240)
    }

    @Test("Picking anything else lets the timeline fit its tracks again")
    func letsGoWhenThePickMoves() {
        var hold = TimelineHeightHold()
        _ = hold.natural(260, holding: false)
        _ = hold.natural(180, holding: true)
        #expect(hold.natural(180, holding: false) == 180)
        // ...and a later tile holds that height, not the old one.
        #expect(hold.natural(150, holding: true) == 180)
    }

    @Test("A tile picked before the timeline was ever measured holds nothing")
    func nothingToHoldYet() {
        var hold = TimelineHeightHold()
        #expect(hold.natural(200, holding: true) == 200)
    }
}
