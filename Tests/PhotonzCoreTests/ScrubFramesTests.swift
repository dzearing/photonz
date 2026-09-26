import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Scrubbing is smooth and never goes black
/// (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
///
/// What the model says about a hand dragging the playhead: which frame stands
/// in for one still being read, and which frame a drawn document shows.
@Suite("A scrub shows the nearest frame in hand")
struct ScrubFramesTests {

    static func movie() -> MovieRef {
        MovieRef(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                 pixelSize: CGSize(width: 3456, height: 2234), durationMS: 8000)
    }

    static func ms(_ frame: Int) -> Int { frame * MovieRef.frameStepMS }

    // MARK: - Reading a drawn frame back

    @Test("A frame's reference reads back as the frame it is")
    func aFrameReadsBack() {
        let movie = Self.movie()
        for frame in [0, 1, 17, 240] {
            #expect(movie.frameIndex(ofFrameID: movie.frameRef(atSourceMS: Self.ms(frame)).id) == frame)
        }
    }

    @Test("Another recording's frame, or any other picture, is not one of this recording's")
    func otherPicturesAreNotFrames() {
        let movie = Self.movie()
        let other = MovieRef(pixelSize: movie.pixelSize, durationMS: 8000)
        #expect(movie.frameIndex(ofFrameID: other.frameRef(atSourceMS: Self.ms(5)).id) == nil)
        #expect(movie.frameIndex(ofFrameID: UUID()) == nil)
    }

    // MARK: - Which frame stands in

    static func hand(_ frames: [Int], travel: MovieFramesInHand.Travel, nearest: Bool) -> MovieFramesInHand {
        var hand = MovieFramesInHand()
        for frame in frames { hand.insert(movie: movie().id, frameIndex: frame) }
        hand.travel = travel
        hand.nearest = nearest
        return hand
    }

    @Test("A hand scrubbing back never jumps to a far frame read long ago")
    func backwardScrubShowsTheNearestFrame() {
        // Frame 60 was read on an earlier pass; 101 is the one just shown.
        let hand = Self.hand([60, 101, 104], travel: .backward, nearest: true)
        #expect(hand.frameIndexToShow(100, of: Self.movie().id) == 101)
    }

    @Test("A hand scrubbing forward shows the nearest frame too, whichever side it is on")
    func forwardScrubShowsTheNearestFrame() {
        let hand = Self.hand([40, 51], travel: .forward, nearest: true)
        #expect(hand.frameIndexToShow(50, of: Self.movie().id) == 51)
    }

    @Test("Two frames as near as each other: the one on the side the hand came from wins")
    func aTieGoesToWhereTheHandCameFrom() {
        let back = Self.hand([49, 51], travel: .backward, nearest: true)
        #expect(back.frameIndexToShow(50, of: Self.movie().id) == 51)
        let forward = Self.hand([49, 51], travel: .forward, nearest: true)
        #expect(forward.frameIndexToShow(50, of: Self.movie().id) == 49)
    }

    @Test("Playing forward still never shows a frame from ahead while one behind is in hand")
    func playingForwardHoldsBehind() {
        let hand = Self.hand([45, 51], travel: .forward, nearest: false)
        #expect(hand.frameIndexToShow(50, of: Self.movie().id) == 45)
    }

    @Test("Playing backward holds the frame after, the one it has just shown")
    func playingBackwardHoldsAfter() {
        let hand = Self.hand([45, 55], travel: .backward, nearest: false)
        #expect(hand.frameIndexToShow(50, of: Self.movie().id) == 55)
        let only = Self.hand([45], travel: .backward, nearest: false)
        #expect(only.frameIndexToShow(50, of: Self.movie().id) == 45)
    }

    @Test("The frame itself, when it is in hand, always wins")
    func theFrameItselfWins() {
        let hand = Self.hand([49, 50, 51], travel: .backward, nearest: true)
        #expect(hand.frameIndexToShow(50, of: Self.movie().id) == 50)
    }
}

/// A recording's canvas is composited at the size it is shown, not at the
/// recording's own size: a full-screen Retina recording fitted in a window is
/// shown at under half its pixels, and compositing all of them for every
/// refresh of a scrub is what left the picture a frame or two behind the hand
/// (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
@Suite("A recording is composited at the size it is shown")
struct CompositeScaleTests {

    @Test("Shown under its own size, it is composited in eighths just big enough")
    func eighthsJustBigEnough() {
        #expect(CompositeScale.forShown(0.47) == 0.5)
        #expect(CompositeScale.forShown(0.5) == 0.5)
        #expect(CompositeScale.forShown(0.51) == 0.625)
    }

    @Test("Never bigger than its own size, never under an eighth")
    func clamped() {
        #expect(CompositeScale.forShown(1.3) == 1)
        #expect(CompositeScale.forShown(4) == 1)
        #expect(CompositeScale.forShown(0.01) == 0.125)
        #expect(CompositeScale.forShown(0) == 0.125)
        #expect(CompositeScale.forShown(.nan) == 1)
    }
}
