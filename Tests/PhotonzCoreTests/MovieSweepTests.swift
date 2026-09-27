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
}
