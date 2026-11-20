import Foundation
import PhotonzCore
import Testing

/// A scrub asks for frames faster than they can be read
/// (`scrubbing-is-smooth-never-goes-black-and-the-pic`). Reproduced by
/// `scrub-never-blacks-out-walk`: every move queued a read and nothing was ever
/// let go, so the frame under the hand waited behind a dozen the hand had
/// already left, and the picture shown trailed the one wanted by 13 frames.
@Suite("Reading frames for a moving playhead")
struct MovieFrameQueueTests {

    @Test("No more reads run at once than there are hands to read them")
    func readsAreBounded() {
        var queue = MovieFrameQueue<Int>(capacity: 2)
        queue.replace(with: [1, 2, 3])
        #expect(queue.take() == 1)
        #expect(queue.take() == 2)
        #expect(queue.take() == nil)
        queue.finished()
        #expect(queue.take() == 3)
    }

    @Test("A newer moment's frames replace the ones nobody has started on")
    func latestMomentWins() {
        var queue = MovieFrameQueue<Int>(capacity: 1)
        queue.replace(with: [10, 11, 12])
        #expect(queue.take() == 10)
        // The hand moved on before 11 and 12 were started.
        queue.replace(with: [40, 41])
        queue.finished()
        #expect(queue.take() == 40)
        queue.finished()
        #expect(queue.take() == 41)
        queue.finished()
        #expect(queue.take() == nil)
    }

    @Test("Finishing more reads than started never lets more run")
    func finishingIsClamped() {
        var queue = MovieFrameQueue<Int>(capacity: 1)
        queue.finished()
        queue.replace(with: [1, 2])
        #expect(queue.take() == 1)
        #expect(queue.take() == nil)
    }

    // MARK: - Which frame the budget lets go

    @Test("The frame let go is the one farthest from where the playhead is")
    func farthestGoes() {
        let movie = UUID()
        let resident = [(movie, 50), (movie, 10), (movie, 52), (movie, 49)]
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: 51]) == 1)
    }

    @Test("Scrubbing back and forth keeps the frames on both sides of the playhead")
    func bothSidesStay() {
        let movie = UUID()
        let resident = [(movie, 45), (movie, 55), (movie, 70)]
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [movie: 50]) == 2)
    }

    @Test("A recording nothing is looking at goes before any frame near a playhead")
    func unwatchedRecordingGoesFirst() {
        let near = UUID(), gone = UUID()
        let resident = [(near, 90), (gone, 3), (near, 5)]
        #expect(MovieFrameQueue<Int>.farthest(resident, from: [near: 6]) == 1)
    }

    // A second hunt over the same ground found the budget full of the frames
    // of clips coming up, read on the first, and every frame read ahead of
    // the hand was the farthest thing in it and let go as it landed: the
    // picture sat 25 refreshes on one frame (2026-11-20, pass 21).

    @Test("While a hand moves, a recording only coming up counts its frames as farther than the one under the hand")
    func comingUpGoesBeforeUnderTheHand() {
        let under = UUID(), coming = UUID()
        // 30 frames ahead of the hand against 20 from a clip coming up.
        let resident = [(under, 130), (coming, 520)]
        let foci = [under: [100], coming: [500]]
        #expect(MovieFrameQueue<Int>.farthest(resident, from: foci, forward: true) == 0)
        #expect(MovieFrameQueue<Int>.farthest(resident, from: foci, forward: true, aside: [coming]) == 1)
        // ...but its first frames still outrank the far end of the hand's.
        let first = [(under, 140), (coming, 505)]
        #expect(MovieFrameQueue<Int>.farthest(first, from: foci, forward: true, aside: [coming]) == 0)
        // Frames the hand passed still go before a coming clip's first ones.
        let passed = [(under, 80), (coming, 505)]
        #expect(MovieFrameQueue<Int>.farthest(passed, from: foci, forward: true, aside: [coming]) == 0)
    }
}
