import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Scrubbing back fast froze the picture for half a second
/// (`scrubbing-back-fast-keeps-the-video-picture-movi`). Reproduced by
/// `scrub-never-blacks-out-walk`: the fixture has a key frame every two
/// seconds, every exact read decodes from the key frame before it, and the
/// reads do not run side by side, so the picture sat on one frame for 19
/// display frames while the hand went back over 26. One pass over the stretch
/// the hand is heading into reads every frame of it for the price of one.
@Suite("Reading the stretch a moving hand is heading into")
struct MovieSweepTests {

    /// A 3.6s recording: grid frames 0 to 109.
    private let movie = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 3600)

    @Test("Going back, the stretch reaches well behind the hand and a little in front")
    func windowBackward() {
        let window = MovieSweep.window(from: 80, backward: true, movie: movie)
        #expect(window.upperBound == 80 + MovieSweep.behindMS / MovieRef.frameStepMS)
        #expect(window.lowerBound == 80 - MovieSweep.aheadMS / MovieRef.frameStepMS)
    }

    @Test("Going forward, the stretch is the mirror of going back")
    func windowForward() {
        let window = MovieSweep.window(from: 20, backward: false, movie: movie)
        #expect(window.lowerBound == 20 - MovieSweep.behindMS / MovieRef.frameStepMS)
        #expect(window.upperBound == 20 + MovieSweep.aheadMS / MovieRef.frameStepMS)
    }

    @Test("The stretch never runs off either end of the recording")
    func windowClamped() {
        #expect(MovieSweep.window(from: 5, backward: true, movie: movie).lowerBound == 0)
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        #expect(MovieSweep.window(from: last - 2, backward: false, movie: movie).upperBound == last)
    }

    @Test("Nothing is read when every frame the hand is heading for is in hand")
    func nothingMissing() {
        let next = MovieSweep.next(handFrame: 50, backward: true, movie: movie,
                                   inHand: { _ in true }, running: nil)
        #expect(next == nil)
    }

    @Test("The stretch starts at the first frame ahead of the hand that is missing")
    func startsAtFirstMissing() {
        // Frames 44 and up are in hand; the hand is at 50 going back.
        let next = MovieSweep.next(handFrame: 50, backward: true, movie: movie,
                                   inHand: { $0 >= 44 }, running: nil)
        #expect(next == MovieSweep.window(from: 43, backward: true, movie: movie))
    }

    @Test("A stretch already being read that covers the hand is left to finish")
    func runningCoversHand() {
        let next = MovieSweep.next(handFrame: 50, backward: true, movie: movie,
                                   inHand: { _ in false }, running: 10...52)
        #expect(next == nil)
    }

    @Test("A stretch being read that the hand has left is replaced")
    func runningLeftBehind() {
        let next = MovieSweep.next(handFrame: 90, backward: false, movie: movie,
                                   inHand: { _ in false }, running: 10...52)
        #expect(next == MovieSweep.window(from: 90, backward: false, movie: movie))
    }

    @Test("Each grid frame gets the sample on screen at that moment, at 60 frames a second")
    func gridAtSixty() {
        var grid = MovieSweepGrid(frames: 0...2)
        let samples = [0, 16.67, 33.33, 50, 66.67, 83.33]
        var fills: [Int: Double] = [:]
        var previous: Double?
        for ms in samples {
            for index in grid.arrived(atMS: ms) { fills[index] = previous }
            previous = ms
        }
        for index in grid.finished() { fills[index] = previous }
        #expect(fills == [0: 0, 1: 33.33, 2: 66.67])
    }

    @Test("A still stretch of a screen recording holds its one sample across the grid")
    func gridVariableRate() {
        var grid = MovieSweepGrid(frames: 0...35)
        var fills: [Int: Double] = [:]
        var previous: Double?
        for ms in [0.0, 1000] {
            for index in grid.arrived(atMS: ms) { fills[index] = previous }
            previous = ms
        }
        for index in grid.finished() { fills[index] = previous }
        #expect((0...29).allSatisfy { fills[$0] == 0 })
        #expect((30...35).allSatisfy { fills[$0] == 1000 })
    }

    @Test("Grid frames before the first sample the reader gave are left alone")
    func gridBeforeFirstSample() {
        var grid = MovieSweepGrid(frames: 10...12)
        var fills: [Int: Double] = [:]
        var previous: Double?
        for ms in [366.67, 383.33, 400] {
            for index in grid.arrived(atMS: ms) { fills[index] = previous }
            previous = ms
        }
        for index in grid.finished() { fills[index] = previous }
        #expect(fills[10] == nil)
        #expect(fills[11] == 366.67)
        #expect(fills[12] == 400)
    }

    @Test("A small copy is at most the rough width, the same shape as the frame")
    func roughSize() {
        let rough = MovieSweep.roughSize(for: CGSize(width: 2160, height: 1396))
        #expect(rough.width == MovieSweep.roughWidth)
        #expect(rough.height == (1396 * MovieSweep.roughWidth / 2160).rounded())
        #expect(MovieSweep.roughSize(for: CGSize(width: 640, height: 400)) == CGSize(width: 640, height: 400))
    }

    // MARK: A hand faster than a stretch can follow

    @Test("A hand's pace is the edit it crossed over its last tenth of a second")
    func handPace() {
        var pace = MovieSweep.HandPace()
        #expect(pace.editMSPerSecond == 0)
        pace.moved(toMS: 1000, atMS: 0)
        #expect(pace.editMSPerSecond == 0)
        // Five seconds of edit a second, the way a person hunts.
        for step in 1...12 { pace.moved(toMS: 1000 + step * 42, atMS: Double(step) * 8.33) }
        #expect(abs(pace.editMSPerSecond - 5000) < 100)
        #expect(!MovieSweep.glimpses(pace: pace.editMSPerSecond))
        // Three minutes of edit a second: no stretch keeps up with that.
        for step in 13...24 { pace.moved(toMS: 1504 + (step - 12) * 1500, atMS: Double(step) * 8.33) }
        #expect(MovieSweep.glimpses(pace: pace.editMSPerSecond))
        // Moves that arrive together are not read as a burst of speed.
        var burst = MovieSweep.HandPace()
        burst.moved(toMS: 0, atMS: 0)
        burst.moved(toMS: 40, atMS: 0.5)
        #expect(!MovieSweep.glimpses(pace: burst.editMSPerSecond))
        burst.reset()
        #expect(burst.editMSPerSecond == 0)
    }

    @Test("A playhead at rest has the second around it read small, more of it ahead than behind")
    func restingWindow() {
        // 3.6s of recording, 109 grid frames.
        let step = MovieRef.frameStepMS
        let around = MovieSweep.restingWindow(around: 60, movie: movie)
        #expect(around.contains(60))
        #expect(around.lowerBound == 60 - MovieSweep.restBehindMS / step)
        #expect(around.upperBound == 60 + MovieSweep.restAheadMS / step)
        #expect(around.count <= MovieSweep.roughBudget)
        // ...kept inside the recording at either end.
        #expect(MovieSweep.restingWindow(around: 2, movie: movie).lowerBound == 0)
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        #expect(MovieSweep.restingWindow(around: last - 1, movie: movie).upperBound == last)
        // Two at rest at once fit the small frames' budget together, still
        // more ahead than behind.
        let two = MovieSweep.restingWindow(around: 60, movie: movie, places: 2)
        #expect(two.count * 2 <= MovieSweep.roughBudget * 3 / 4 + 2)
        #expect(two.upperBound - 60 > 60 - two.lowerBound)
    }

    @Test("A hunting hand looks a quarter second of its pace ahead for clips coming up")
    func cutReach() {
        #expect(MovieSweep.cutReachMS(pace: 5000) == 1250)
        #expect(MovieSweep.cutReachMS(pace: 0) == 0)
        #expect(MovieSweep.cutReachMS(pace: 9000) <= 4000)
        #expect(MovieSweep.cutReachMS(pace: 100_000) == 4000)
    }

    @Test("A key frame for a hand too fast to follow is read for where the hand will be when it lands")
    func glimpseLead() {
        // A key frame takes about 17ms to read and waits up to a refresh for
        // the one before it: 25ms of a hand crossing six minutes in two
        // seconds (180s of edit a second) is four and a half seconds.
        #expect(MovieSweep.glimpseLeadMS(pace: 180_000) == 4500)
        // Nothing ahead of a hand slow enough to be read in stretches.
        #expect(MovieSweep.glimpseLeadMS(pace: 5000) == 0)
        #expect(MovieSweep.glimpseLeadMS(pace: 0) == 0)
    }

    @Test("A hand too fast to follow reads only the frame under it, once")
    func glimpse() {
        let next = MovieSweep.next(handFrame: 50, backward: false, movie: movie,
                                   inHand: { _ in false }, running: nil, glimpse: true)
        #expect(next == 50...50)
        // ...nothing when it is in hand already, or being read.
        #expect(MovieSweep.next(handFrame: 50, backward: false, movie: movie,
                                inHand: { $0 == 50 }, running: nil, glimpse: true) == nil)
        #expect(MovieSweep.next(handFrame: 50, backward: false, movie: movie,
                                inHand: { _ in false }, running: 50...50, glimpse: true) == nil)
        // A stretch running where the hand is still covers it.
        #expect(MovieSweep.next(handFrame: 50, backward: false, movie: movie,
                                inHand: { _ in false }, running: 40...88, glimpse: true) == nil)
    }

    @Test("A stretch turns into pictures only the frames the hand has not passed")
    func worthShowing() {
        let slack = MovieSweep.behindMS / MovieRef.frameStepMS
        #expect(MovieSweep.worthShowing(frame: 60, hand: 60, backward: false))
        #expect(MovieSweep.worthShowing(frame: 60 - slack, hand: 60, backward: false))
        #expect(!MovieSweep.worthShowing(frame: 60 - slack - 1, hand: 60, backward: false))
        #expect(MovieSweep.worthShowing(frame: 90, hand: 60, backward: false))
        #expect(MovieSweep.worthShowing(frame: 60 + slack, hand: 60, backward: true))
        #expect(!MovieSweep.worthShowing(frame: 60 + slack + 1, hand: 60, backward: true))
        #expect(MovieSweep.worthShowing(frame: 20, hand: 60, backward: true))
    }

    // A hunt read in stretches that each started only once the last had
    // finished trailed the hand by 8 to 45 refreshes at every restart: a pass
    // reads about as fast as a hand hunting at five times its playing speed,
    // so the next one started with the hand already at its first frame, and
    // first decoded from the key frame before it, up to two seconds of film
    // (2026-11-20, speed walk hunt).

    @Test("A hand going forward under it is followed to the end of the recording in one pass")
    func followingReachesTheEnd() {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let window = MovieSweep.window(from: 20, backward: false, movie: movie, follows: true)
        #expect(window.lowerBound == 20 - MovieSweep.behindMS / MovieRef.frameStepMS)
        #expect(window.upperBound == last)
        #expect(MovieSweep.next(handFrame: 20, backward: false, movie: movie, inHand: { _ in false },
                                running: nil, follows: true) == window)
    }

    @Test("Going back, or ahead of the hand, a stretch stays a stretch")
    func followingOnlyForward() {
        #expect(MovieSweep.window(from: 80, backward: true, movie: movie, follows: true)
                == MovieSweep.window(from: 80, backward: true, movie: movie))
    }

    @Test("A pass following the hand waits once it is a stretch ahead of it, and never behind it")
    func followingPaces() {
        let ahead = MovieSweep.followLeadMS / MovieRef.frameStepMS
        #expect(ahead < MovieSweep.aheadMS / MovieRef.frameStepMS)
        // ...with room to spare in the small frames' budget beside the
        // frames of clips coming up.
        #expect(ahead * 2 <= MovieSweep.roughBudget)
        #expect(!MovieSweep.waits(nextFrame: 60 + ahead, hand: 60))
        #expect(MovieSweep.waits(nextFrame: 60 + ahead + 1, hand: 60))
        #expect(!MovieSweep.waits(nextFrame: 40, hand: 60))
        // Before the hand is on the recording there is nothing to pace by.
        #expect(!MovieSweep.waits(nextFrame: 500, hand: nil))
    }

    @Test("A pass following the hand covers everything ahead of it, so nothing else starts")
    func followingCovers() {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        #expect(MovieSweep.next(handFrame: 90, backward: false, movie: movie, inHand: { _ in false },
                                running: 17...last, follows: true) == nil)
    }

    // The read around a playhead at rest stopped at its window's end, so the
    // first move of a hunt started a new pass that decoded from the key frame
    // before it: 173ms before its first frame, and the frame under the hand
    // sat 17 to 22 refreshes behind for the first fifth of a second
    // (2026-11-20, speed walk hunt, pass 21).

    @Test("A read around a playhead at rest reaches on to the end of the recording, paused at its window")
    func restingPass() {
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        let pass = MovieSweep.restingPass(around: 60, movie: movie)
        let window = MovieSweep.restingWindow(around: 60, movie: movie)
        #expect(pass.frames == window.lowerBound...last)
        #expect(pass.pausesAfter == window.upperBound)
        // ...one of two at rest at once pauses at its share.
        let two = MovieSweep.restingPass(around: 60, movie: movie, places: 2)
        #expect(two.pausesAfter == MovieSweep.restingWindow(around: 60, movie: movie, places: 2).upperBound)
        #expect(two.frames.upperBound == last)
    }

    @Test("A read at rest waits at its window's end until a hand takes it, then follows the hand")
    func restWaits() {
        let ahead = MovieSweep.followLeadMS / MovieRef.frameStepMS
        // No hand yet: reads its window, then waits.
        #expect(!MovieSweep.restWaits(nextFrame: 80, hand: nil, pausesAfter: 80))
        #expect(MovieSweep.restWaits(nextFrame: 81, hand: nil, pausesAfter: 80))
        // A hand on it: paced like any pass following one, past the window.
        #expect(!MovieSweep.restWaits(nextFrame: 81, hand: 70, pausesAfter: 80))
        #expect(!MovieSweep.restWaits(nextFrame: 70 + ahead, hand: 70, pausesAfter: 80))
        #expect(MovieSweep.restWaits(nextFrame: 70 + ahead + 1, hand: 70, pausesAfter: 80))
        // ...and a hand gone back behind it never lets it run on alone.
        #expect(MovieSweep.restWaits(nextFrame: 81, hand: 20, pausesAfter: 80))
    }

    @Test("A pass opened for a clip coming up reads what the budget keeps of it, then waits for the hand")
    func comingPauses() {
        let step = MovieRef.frameStepMS
        #expect(MovieSweep.comingPausesAfter(40, movie: movie) == 40 + MovieSweep.comingLeadMS / step)
        let last = movie.frameIndex(atSourceMS: movie.durationMS)
        #expect(MovieSweep.comingPausesAfter(last - 1, movie: movie) == last)
        // What it reads before waiting is all kept beside the frames ahead
        // of the hand, so none is let go as it lands.
        #expect(MovieSweep.comingLeadMS / step * MovieFrameQueue<Int>.asideWeight
                <= MovieSweep.followLeadMS / step)
    }
}

/// A hand too fast for a stretch is shown the key frame nearest it, which
/// decodes on its own: at three minutes of edit a second, a key frame a
/// second of film away was under the hand less than a refresh ago.
@Suite("The key frame nearest a fast hand")
struct MovieKeyFramesTests {

    @Test("The nearest key frame either side, a tie going to the one behind")
    func nearest() {
        let step = MovieRef.frameStepMS
        let keys = MovieKeyFrames(sourceMS: [0, 59 * step, 118 * step, 177 * step])
        #expect(keys.nearest(to: 0)?.frame == 0)
        #expect(keys.nearest(to: 20)?.frame == 0)
        #expect(keys.nearest(to: 40)?.frame == 59)
        #expect(keys.nearest(to: 59)?.frame == 59)
        #expect(keys.nearest(to: 90)?.frame == 118)
        #expect(keys.nearest(to: 300)?.frame == 177)
        #expect(MovieKeyFrames(sourceMS: [10 * step, 20 * step]).nearest(to: 15)?.frame == 10)
        #expect(MovieKeyFrames(sourceMS: []).nearest(to: 15) == nil)
    }

    /// The key frame nearest a hand can be one its clip never plays: just
    /// before the clip's first frame, or after its last. Shown, it is a
    /// picture the edit never shows, from a part of the recording the hand
    /// was nowhere near (2026-11-17).
    @Test("The nearest key frame the clip plays, or the nearest at all where it plays none")
    func nearestWithin() {
        let step = MovieRef.frameStepMS
        let keys = MovieKeyFrames(sourceMS: [0, 59 * step, 118 * step, 177 * step])
        #expect(keys.nearest(to: 65, within: 60...150)?.frame == 118)
        #expect(keys.nearest(to: 170, within: 60...150)?.frame == 118)
        #expect(keys.nearest(to: 100, within: 60...150)?.frame == 118)
        #expect(keys.nearest(to: 65, within: nil)?.frame == 59)
        // Two inside: the one nearer the hand, never the outside one beyond.
        let close = MovieKeyFrames(sourceMS: [59 * step, 118 * step, 160 * step, 177 * step])
        #expect(close.nearest(to: 172, within: 60...170)?.frame == 160)
        #expect(close.nearest(to: 120, within: 60...170)?.frame == 118)
        // A clip shorter than the gap between two key frames has none of its
        // own: the nearest at all, as before.
        #expect(keys.nearest(to: 65, within: 60...100)?.frame == 59)
        #expect(MovieKeyFrames(sourceMS: []).nearest(to: 15, within: 0...30) == nil)
    }

    @Test("A clip says the stretch of its recording it plays, cut pieces and all")
    func playedSpan() {
        var layer = Layer(name: "Screen recording",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                          frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        #expect(layer.playedSourceSpanMS == nil)
        layer.time = LayerTime(inMS: 500, outMS: 4500, sourceInMS: 2000, sourceLengthMS: 4000)
        #expect(layer.playedSourceSpanMS == 2000...6000)
        var pieces = layer.clipPieces ?? ClipPieces(single: LayerTime(inMS: 0, outMS: 1))
        _ = pieces.split(atMS: 1000)
        _ = pieces.remove(at: 0)
        layer.setClipPieces(pieces)
        #expect(layer.playedSourceSpanMS == 3000...6000)
    }

    @Test("A key frame is asked for at exactly its moment, not its grid frame's")
    func exactMoment() {
        // A 60 frame a second recording's key frame at 1.9667s is on grid
        // frame 59, whose moment (1947ms) is a frame before it.
        let keys = MovieKeyFrames(sourceMS: [1967, 0])
        #expect(keys.frames == [0, 59])
        #expect(keys.nearest(to: 58)?.sourceMS == 1967)
        #expect(keys.sourceMS == [0, 1967])
    }

    @Test("Key frames are kept in order, once each")
    func ordered() {
        let keys = MovieKeyFrames(sourceMS: [118, 0, 59, 59])
        #expect(keys.sourceMS == [0, 59, 118])
    }
}
