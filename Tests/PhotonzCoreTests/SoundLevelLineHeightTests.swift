import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A sound at its recorded level draws its volume line near the top of its
/// lane** (`SoundLaneShape.levelY`).
///
/// video-audio.html places the line with `yOfLevel(v) = 90 - v * 78` out of a
/// lane 100 tall: the recorded level at 12, silence at 90. The timeline put the
/// recorded level about three tenths of the way down, keeping the top third for
/// turning a sound up. The room above the recorded level is now the strip
/// between 12 and the top, so a sound can still be turned up and the line shows
/// it.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("A sound's volume line at the mock's height")
struct SoundLevelLineHeightTests {

    private let lane: CGFloat = 84
    private let inset: CGFloat = 5.5

    private func y(_ gain: Double, _ height: CGFloat = 84) -> CGFloat {
        SoundLaneShape.levelY(forGain: gain, height: height, inset: inset)
    }

    private func gain(_ y: CGFloat, _ height: CGFloat = 84) -> Double {
        SoundLaneShape.gain(atLevelY: y, height: height, inset: inset)
    }

    // MARK: - Where the mock puts it

    @Test func theRecordedLevelIsTwelveHundredthsDown() {
        #expect(abs(y(AudioLevel.unityGain) - lane * 0.12) < 0.0001)
        #expect(y(AudioLevel.unityGain) < lane / 5)
    }

    @Test func silenceIsNinetyHundredthsDown() {
        #expect(abs(y(0) - lane * 0.90) < 0.0001)
    }

    @Test func belowTheRecordedLevelTheLineFallsStraightAsTheMockDrawsIt() {
        // 90 - 0.5 * 78 = 51 out of 100.
        #expect(abs(y(0.5) - lane * 0.51) < 0.0001)
        // A duck to a quarter: 90 - 19.5 = 70.5.
        #expect(abs(y(0.25) - lane * 0.705) < 0.0001)
    }

    @Test func aNarrowLaneKeepsTheSameShares() {
        #expect(abs(y(1, 72) - 72 * 0.12) < 0.0001)
        #expect(abs(y(0, 72) - 72 * 0.90) < 0.0001)
    }

    // MARK: - Room to turn it up

    @Test func louderThanRecordedStillRisesAboveIt() {
        #expect(y(1.5) < y(1))
        #expect(y(2) < y(1.5))
    }

    @Test func asLoudAsALevelGoesIsTheTopOfTheRoom() {
        #expect(abs(y(AudioLevel.loudestGain) - inset) < 0.0001)
        #expect(abs(y(5) - inset) < 0.0001)
        #expect(abs(y(-1) - y(0)) < 0.0001)
    }

    @Test func aShortBarStillHasRoomAboveTheRecordedLevel() {
        // The icon strip's 36 point bar: 12 of 100 is 4.3 points, inside the
        // room a dot needs, so the recorded level comes down far enough to
        // leave a few points to turn it up in.
        let unity = y(1, 36)
        #expect(unity > inset + 2)
        #expect(y(2, 36) < unity)
        #expect(y(0, 36) <= 36 - inset)
        #expect(y(0, 36) > unity)
    }

    // MARK: - A drag lands under the hand

    @Test func aHeightReadsBackAsTheLevelDrawnThere() {
        for level in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            for height: CGFloat in [84, 72, 36] {
                #expect(abs(gain(y(level, height), height) - level) < 0.0001, "\(level) at \(height)")
            }
        }
    }

    @Test func aDragPastEitherEndStopsThere() {
        #expect(gain(-20) == AudioLevel.loudestGain)
        #expect(gain(0) == AudioLevel.loudestGain)
        #expect(gain(84) == 0)
        #expect(gain(200) == 0)
    }

    @Test func aBarWithNoRoomReadsTheRecordedLevel() {
        #expect(gain(3, 0) == AudioLevel.unityGain)
        #expect(y(1, 0).isFinite)
    }
}
