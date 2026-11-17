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

    @Test("A hunting hand looks a quarter second of its pace ahead for clips coming up")
    func cutReach() {
        #expect(MovieSweep.cutReachMS(pace: 5000) == 1250)
        #expect(MovieSweep.cutReachMS(pace: 0) == 0)
        #expect(MovieSweep.cutReachMS(pace: 9000) <= 4000)
        #expect(MovieSweep.cutReachMS(pace: 100_000) == 4000)
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
