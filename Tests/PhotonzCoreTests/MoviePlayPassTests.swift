import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Playing a full-screen Retina recording showed a frame up to half a second
/// old (`a-full-screen-retina-recording-keeps-up-while-it`). Reproduced by
/// `playing-a-recording-never-blinks-walk`: 17 of 24 looks held a frame 16
/// behind. Reading exact frames one at a time managed about 15 a second on the
/// fixture, four side by side; one pass reads the same three seconds in half a
/// second. So playing reads in one pass that keeps a little ahead of the
/// playhead, and is started again when the playhead goes somewhere it is not.
@Suite("Reading ahead of a playing playhead in one pass")
struct MoviePlayPassTests {

    /// A 3.6s recording: grid frames 0 to 109.
    private let movie = MovieRef(pixelSize: CGSize(width: 3456, height: 2234), durationMS: 3600)
    private var last: Int { movie.frameIndex(atSourceMS: movie.durationMS) }

    @Test("A pass runs from the playhead to the end of the recording")
    func window() {
        #expect(MoviePlayPass.window(from: 30, movie: movie) == 30...last)
        #expect(MoviePlayPass.window(from: -4, movie: movie) == 0...last)
        #expect(MoviePlayPass.window(from: last + 9, movie: movie) == last...last)
    }

    @Test("A pass waits once it is far enough ahead of the playhead")
    func pacing() {
        #expect(!MoviePlayPass.shouldWait(next: 10 + MoviePlayPass.aheadFrames, playhead: 10))
        #expect(MoviePlayPass.shouldWait(next: 11 + MoviePlayPass.aheadFrames, playhead: 10))
        #expect(!MoviePlayPass.shouldWait(next: 3, playhead: 10))
    }

    @Test("A pass keeping up with the playhead goes on")
    func keepsUp() {
        let serves = MoviePlayPass.serves(running: 20...last, reached: 34, playhead: 30,
                                          inHand: { $0 < 34 })
        #expect(serves)
    }

    @Test("A pass that has not reached the playhead yet but is close goes on")
    func closeBehind() {
        let serves = MoviePlayPass.serves(running: 20...last, reached: 30 - MoviePlayPass.fallenBehindFrames,
                                          playhead: 30, inHand: { _ in false })
        #expect(serves)
    }

    @Test("A pass fallen well behind the playhead is started again where it is")
    func fallenBehind() {
        let serves = MoviePlayPass.serves(running: 20...last, reached: 29 - MoviePlayPass.fallenBehindFrames,
                                          playhead: 30, inHand: { _ in false })
        #expect(!serves)
    }

    @Test("A playhead that went back before the pass starts it again")
    func wentBack() {
        #expect(!MoviePlayPass.serves(running: 20...last, reached: 25, playhead: 12, inHand: { _ in true }))
    }

    @Test("A playhead back over ground the pass let go of starts it again")
    func backOverLostGround() {
        #expect(!MoviePlayPass.serves(running: 20...last, reached: 60, playhead: 30,
                                      inHand: { $0 > 50 }))
        #expect(MoviePlayPass.serves(running: 20...last, reached: 60, playhead: 30,
                                     inHand: { $0 > 25 }))
    }

    @Test("A frame the pass is about to reach is its to read")
    func coversAhead() {
        #expect(MoviePlayPass.covers(frame: 36, running: 20...last, reached: 34, playhead: 30))
        #expect(MoviePlayPass.covers(frame: 34, running: 20...last, reached: 34, playhead: 30))
    }

    @Test("A frame the pass already went by is not its to read")
    func notBehind() {
        #expect(!MoviePlayPass.covers(frame: 33, running: 20...last, reached: 34, playhead: 30))
    }

    @Test("A frame far past the playhead, across a cut, is read on its own")
    func notAcrossACut() {
        #expect(!MoviePlayPass.covers(frame: 90, running: 20...last, reached: 34, playhead: 30))
        #expect(MoviePlayPass.covers(frame: 30 + MoviePlayPass.aheadFrames, running: 20...last,
                                     reached: 34, playhead: 30))
    }

    @Test("A frame outside the pass is not its to read")
    func outside() {
        #expect(!MoviePlayPass.covers(frame: 5, running: 20...last, reached: 20, playhead: 20))
    }
}

@Suite("Where a one-pass read has got to")
struct MovieSweepGridReachTests {

    @Test("The next frame to fill starts at the first and moves as samples arrive")
    func next() {
        var grid = MovieSweepGrid(frames: 10...20)
        #expect(grid.nextFrame == 10)
        _ = grid.arrived(atMS: 330)
        _ = grid.arrived(atMS: 347)
        #expect(grid.nextFrame == 11)
    }
}
