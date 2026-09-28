import CoreGraphics
import Testing
@testable import PhotonzCore

/// A tile that plays the same short loop for ever (a caption style, a
/// transition) is handed to Core Animation as the frames that differ and the
/// moment each one starts, so nothing on the main thread runs while it plays.
/// The reel is those frames, read off the loop once.
struct LoopReelTests {
    @Test func aReelKeepsOnlyTheFramesThatChange() {
        // A frame a step, changing every 100ms: 0, 0, 0, 1, 1, 1, 2 ...
        let reel = LoopReel(lapMS: 300, stepMS: 33) { ms in ms / 100 }
        #expect(reel.shots.map(\.frame) == [0, 1, 2])
        #expect(reel.shots.map(\.startMS) == [0, 132, 231])
    }

    @Test func aStillLoopIsOneFrame() {
        let reel = LoopReel(lapMS: 2_900, stepMS: 33) { _ in "still" }
        #expect(reel.shots.count == 1)
        #expect(reel.keyTimes == [0, 1])
    }

    @Test func keyTimesRunFromNoughtToOneWithOneMoreThanTheFrames() {
        let reel = LoopReel(lapMS: 300, stepMS: 33) { ms in ms / 100 }
        // Core Animation's discrete keyframes: a time for each frame and one
        // to close the lap.
        #expect(reel.keyTimes.count == reel.shots.count + 1)
        #expect(reel.keyTimes.first == 0)
        #expect(reel.keyTimes.last == 1)
        #expect(reel.keyTimes == reel.keyTimes.sorted())
    }

    @Test func aReelAnswersWhatShowsAtAnyMomentOfAnyLap() {
        let reel = LoopReel(lapMS: 300, stepMS: 33) { ms in ms / 100 }
        #expect(reel.frame(atMS: 0) == 0)
        #expect(reel.frame(atMS: 140) == 1)
        #expect(reel.frame(atMS: 299) == 2)
        #expect(reel.frame(atMS: 300 + 140) == 1, "the second lap is the first again")
    }

    @Test func aBadStepStillMakesAReel() {
        let reel = LoopReel(lapMS: 0, stepMS: 0) { _ in 7 }
        #expect(reel.shots.map(\.frame) == [7])
        #expect(reel.keyTimes == [0, 1])
    }

    // MARK: - A caption style tile

    /// The reel plays the words exactly as the tile drew them a tick at a
    /// time: every frame is the caption at the moment it starts.
    @Test func aCaptionStyleReelIsTheCaptionAtEachMoment() {
        for preset in CaptionLook.Preset.allCases {
            let look = CaptionLook.preset(preset)
            let reel = look.previewReel(fontSize: 10, width: 90)
            #expect(reel.lapMS == CaptionLook.previewCycleMS)
            #expect(!reel.shots.isEmpty)
            for shot in reel.shots {
                #expect(shot.frame == look.previewText(atMS: shot.startMS, fontSize: 10, width: 90))
            }
            for pair in zip(reel.shots, reel.shots.dropFirst()) {
                #expect(pair.0.frame != pair.1.frame, "\(preset): a frame is only kept when it changes")
            }
        }
    }

    /// Far fewer frames than ticks: the words hold still between moves, and a
    /// held word is one frame however long it is held.
    @Test func aCaptionStyleReelHoldsAStillWordAsOneFrame() {
        let steps = CaptionLook.previewCycleMS / CaptionLook.previewStepMS
        var plain = CaptionLook.preset(.caption)
        plain.word.motion = .none
        let reel = plain.previewReel(fontSize: 10, width: 90)
        #expect(reel.shots.count < steps / 4)
        #expect(reel.shots.count >= 2, "the words still move on")
    }

    // MARK: - A transition tile

    @Test func aTransitionTileGoesThereAndBackWithABeatAtEachEnd() {
        #expect(TransitionTileLoop.progress(atSeconds: 0) == 0)
        let half = TransitionTileLoop.cycleSeconds / 2
        #expect(TransitionTileLoop.progress(atSeconds: half) == 1)
        #expect(TransitionTileLoop.progress(atSeconds: half * 0.5) > 0.3)
        #expect(TransitionTileLoop.progress(atSeconds: half * 0.5) < 0.7)
        // The way back is the way there, backwards.
        let there = TransitionTileLoop.progress(atSeconds: 0.3)
        let back = TransitionTileLoop.progress(atSeconds: TransitionTileLoop.cycleSeconds - 0.3)
        #expect(abs(there - back) < 0.0001)
    }

    /// The way back shares the way there's frames, so a tile draws each
    /// moment of its transition once.
    @Test func aTransitionReelDrawsEachMomentOnce() {
        let reel = TransitionTileLoop.reel
        #expect(reel.lapMS == Int((TransitionTileLoop.cycleSeconds * 1000).rounded()))
        #expect(reel.shots.first?.frame == 0)
        #expect(reel.shots.contains { $0.frame == 1 })
        let distinct = Set(reel.shots.map(\.frame))
        #expect(distinct.count < reel.shots.count, "the way back reuses the way there")
        #expect(distinct.count <= 41, "one frame per fortieth of the way across, at most")
        for frame in distinct { #expect(frame >= 0 && frame <= 1) }
    }
}
