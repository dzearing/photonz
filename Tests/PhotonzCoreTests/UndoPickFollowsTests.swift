import Foundation
import Testing
@testable import PhotonzCore

/// Undo and Redo on a video put the step's picture on screen in the press's own
/// pass, and the pick a pass behind it, when the pick moves from one clip to
/// another that both stand in the document. Everything else moves the pick at
/// once, as it always has.
@Suite("Undo pick follows a pass later")
struct UndoPickFollowsTests {

    private let captions = UUID()
    private let talk = UUID()

    @Test("Redo of a cut, Captions in hand, hands the piece over a pass later")
    func movingBetweenTwoClipsWaitsAPass() {
        #expect(UndoPickFollows.aPassLater(from: captions, to: talk, restoredMulti: [],
                                           leavingStillStands: true, documentHasTime: true))
    }

    @Test("A pick that stays on the same clip moves at once")
    func sameClipMovesAtOnce() {
        #expect(!UndoPickFollows.aPassLater(from: talk, to: talk, restoredMulti: [],
                                            leavingStillStands: true, documentHasTime: true))
    }

    @Test("Nothing in hand before: the panel already builds from empty a section at a time")
    func fromNothingMovesAtOnce() {
        #expect(!UndoPickFollows.aPassLater(from: nil, to: talk, restoredMulti: [],
                                            leavingStillStands: false, documentHasTime: true))
    }

    @Test("Letting go of everything moves at once: a panel must never describe what is gone")
    func toNothingMovesAtOnce() {
        #expect(!UndoPickFollows.aPassLater(from: talk, to: nil, restoredMulti: [],
                                            leavingStillStands: true, documentHasTime: true))
    }

    @Test("A clip the step took away is never left in hand for a pass")
    func leavingClipGoneMovesAtOnce() {
        #expect(!UndoPickFollows.aPassLater(from: talk, to: captions, restoredMulti: [],
                                            leavingStillStands: false, documentHasTime: true))
    }

    @Test("Several things coming back into hand move at once")
    func multiPickMovesAtOnce() {
        #expect(!UndoPickFollows.aPassLater(from: captions, to: talk, restoredMulti: [talk, captions],
                                            leavingStillStands: true, documentHasTime: true))
    }

    @Test("A picture without time keeps the pick in the press's own pass")
    func pictureMovesAtOnce() {
        #expect(!UndoPickFollows.aPassLater(from: captions, to: talk, restoredMulti: [],
                                            leavingStillStands: true, documentHasTime: false))
    }
}
