import Foundation
import PhotonzCore
import Testing

/// The Effects list on a picked sound (`pages/video-audio.html`, `#gEffects`
/// and its add menu `#efxMenu`): EQ, Compressor and Noise reduction.
///
/// Written before the list. Noise reduction is the one the app can do today,
/// and it is the very same setting Normalize's Clean noise writes, so the list
/// reads and writes `AudioLevel.noiseReduction` rather than a second copy of it.
@Suite("The Effects list on a picked sound")
struct SoundEffectsTests {

    @Test func theAddMenuListsWhatTheMockDrawsInItsOrder() {
        #expect(SoundEffectKind.allCases == [.eq, .compressor, .noiseReduction])
        #expect(SoundEffectKind.allCases.map(\.title) == ["EQ", "Compressor", "Noise reduction"])
    }

    @Test func onlyNoiseReductionHasSoundBehindItYet() {
        #expect(SoundEffectKind.noiseReduction.isBuilt)
        #expect(!SoundEffectKind.eq.isBuilt)
        #expect(!SoundEffectKind.compressor.isBuilt)
    }

    @Test func aSoundNobodyHasTouchedHasNoEffects() {
        #expect(AudioLevel().effectRows.isEmpty)
    }

    @Test func aCleanedSoundShowsNoiseReductionAtItsStrength() {
        for reduction in NoiseReduction.allCases {
            let level = AudioLevel(noiseReduction: reduction)
            #expect(level.effectRows == [SoundEffectRow(kind: .noiseReduction, reading: reduction.title)])
        }
    }

    /// Added from the list, it cleans at the strength Normalize's Clean noise
    /// cleans at, so the two routes leave the sound the same.
    @Test func addingNoiseReductionCleansAtTheStrengthNormalizeUses() {
        var level = AudioLevel()
        let changed1 = level.addEffect(.noiseReduction)
        #expect(changed1)
        #expect(level.noiseReduction == NoiseReduction.standard)
        #expect(level.effectRows.map(\.kind) == [.noiseReduction])
    }

    @Test func noiseReductionIsOfferedOnceAndOnlyUntilItIsOn() {
        var level = AudioLevel()
        #expect(level.canAddEffect(.noiseReduction))
        level.addEffect(.noiseReduction)
        #expect(!level.canAddEffect(.noiseReduction))
        // Adding it again changes nothing, strength included.
        level.noiseReduction = .strong
        let changed2 = level.addEffect(.noiseReduction)
        #expect(!changed2)
        #expect(level.noiseReduction == .strong)
    }

    @Test func anEffectWithNoSoundBehindItIsNeverAdded() {
        var level = AudioLevel()
        #expect(!level.canAddEffect(.eq))
        #expect(!level.canAddEffect(.compressor))
        let changed3 = level.addEffect(.eq)
        #expect(!changed3)
        let changed4 = level.addEffect(.compressor)
        #expect(!changed4)
        #expect(level == AudioLevel())
    }

    /// Removing it from the list is removing the cleaning: the same nil the
    /// segment's Remove Noise Cleaning writes.
    @Test func removingNoiseReductionStopsTheCleaning() {
        var level = AudioLevel(clipGainDB: 12, noiseReduction: .medium)
        let changed5 = level.removeEffect(.noiseReduction)
        #expect(changed5)
        #expect(level.noiseReduction == nil)
        #expect(level.clipGainDB == 12)
        #expect(level.effectRows.isEmpty)
        let changed6 = level.removeEffect(.noiseReduction)
        #expect(!changed6)
    }
}
