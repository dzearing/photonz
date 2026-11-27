import Foundation
import PhotonzCore
import Testing

/// The level each voice of the player is held at, a moment at a time.
///
/// A voice with nothing sounding was held at nought, and its next piece was
/// only turned up on the first tick after it started, so a sound clip that
/// met another on the timeline came in after a hole of 18 to 26 ms
/// (`sound-clips-that-meet-play-straight-through-walk`, 2026-11-26).
@Suite("Each voice is at its level before its sound arrives")
struct AudioVoiceLevelsTests {

    static func piece(_ layer: UUID, at startMS: Int, length: Int, from: Double = 1, to: Double = 1,
                      voice: Int = 0) -> AudioMixSegment {
        AudioMixSegment(layerID: layer, sound: SoundRef(durationMS: length), startMS: startMS,
                        lengthMS: length, sourceInMS: 0, sourceLengthMS: length, speedPercent: 100,
                        ramps: [AudioGainRamp(fromMS: startMS, toMS: startMS + length,
                                              fromGain: from, toGain: to)], voice: voice)
    }

    @Test("A piece playing now sets its voice to its level now")
    func playingNow() {
        let layer = UUID()
        let levels = AudioVoiceLevels.at(ms: 1000, in: [Self.piece(layer, at: 0, length: 2000, from: 0, to: 1)])
        #expect(abs((levels[AudioVoiceLevels.Key(layerID: layer, voice: 0)] ?? -1) - 0.5) < 0.001)
    }

    @Test("A clip starting just after this moment is already at its opening level")
    func comingUpIsTurnedUpAhead() {
        let first = UUID(), second = UUID()
        let mix = [Self.piece(first, at: 0, length: 5000), Self.piece(second, at: 5000, length: 3000, from: 0.8, to: 0.8)]
        let levels = AudioVoiceLevels.at(ms: 4980, in: mix)
        #expect(levels[AudioVoiceLevels.Key(layerID: first, voice: 0)] == 1)
        #expect(levels[AudioVoiceLevels.Key(layerID: second, voice: 0)] == 0.8)
    }

    @Test("A fade in from silence that is coming up waits at silence")
    func fadeInWaitsAtSilence() {
        let layer = UUID()
        let levels = AudioVoiceLevels.at(ms: 900, in: [Self.piece(layer, at: 1000, length: 2000, from: 0, to: 1)])
        #expect(levels[AudioVoiceLevels.Key(layerID: layer, voice: 0)] == 0)
    }

    @Test("A voice with nothing playing or coming up soon is silent")
    func farOffIsSilent() {
        let layer = UUID()
        let levels = AudioVoiceLevels.at(ms: 1000, in: [Self.piece(layer, at: 5000, length: 1000)])
        #expect(levels[AudioVoiceLevels.Key(layerID: layer, voice: 0)] == nil)
    }

    @Test("The two voices of one layer are kept apart")
    func voicesApart() {
        let layer = UUID()
        let mix = [Self.piece(layer, at: 0, length: 2000, from: 0.25, to: 0.25),
                   Self.piece(layer, at: 1500, length: 2000, from: 0.75, to: 0.75, voice: 1)]
        let levels = AudioVoiceLevels.at(ms: 1000, in: mix, aheadMS: 250)
        #expect(levels[AudioVoiceLevels.Key(layerID: layer, voice: 0)] == 0.25)
        #expect(levels[AudioVoiceLevels.Key(layerID: layer, voice: 1)] == nil)
        let later = AudioVoiceLevels.at(ms: 1300, in: mix, aheadMS: 250)
        #expect(later[AudioVoiceLevels.Key(layerID: layer, voice: 1)] == 0.75)
    }

    @Test("What is playing now wins over what comes next on the same voice")
    func nowWinsOverNext() {
        let layer = UUID()
        let mix = [Self.piece(layer, at: 0, length: 1000, from: 1, to: 1),
                   Self.piece(layer, at: 1000, length: 1000, from: 0, to: 1)]
        #expect(AudioVoiceLevels.at(ms: 950, in: mix)[AudioVoiceLevels.Key(layerID: layer, voice: 0)] == 1)
    }
}
