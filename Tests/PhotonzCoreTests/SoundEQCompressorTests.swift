import Foundation
import PhotonzCore
import Testing

/// EQ and Compressor on a picked sound (`pages/video-audio.html`, `#gEffects`:
/// "EQ  low cut 80", "Compressor  off"), and the on switch every row of the
/// list wears.
///
/// Written before either existed. What is checked here is the model: what a
/// row reads, what switching it off keeps, what plays, and that the copy the
/// mix plays under a new id is the same id every time for the same settings.
@Suite("EQ and Compressor on a picked sound")
struct SoundEQCompressorTests {

    // MARK: Adding

    @Test func anEQGoesOnReadingTheMocksLowCut() {
        var level = AudioLevel()
        #expect(level.canAddEffect(.eq))
        let added = level.addEffect(.eq)
        #expect(added)
        #expect(level.eq == SoundEQ.standard)
        #expect(level.effectRows == [SoundEffectRow(kind: .eq, reading: "low cut 80", isOn: true)])
        #expect(!level.canAddEffect(.eq))
        let again = level.addEffect(.eq)
        #expect(!again)
    }

    @Test func aCompressorGoesOnReadingItsRatio() {
        var level = AudioLevel()
        level.addEffect(.compressor)
        #expect(level.compressor == SoundCompressor.standard)
        #expect(level.effectRows == [SoundEffectRow(kind: .compressor, reading: "3:1", isOn: true)])
    }

    /// The rows read top down in the order the sound passes through them:
    /// cleaned first, so the compressor does not lift the noise it is about
    /// to have taken out, then shaped, then evened out.
    @Test func theRowsReadInTheOrderTheSoundPassesThroughThem() {
        var level = AudioLevel()
        level.addEffect(.compressor)
        level.addEffect(.eq)
        level.addEffect(.noiseReduction)
        #expect(level.effectRows.map(\.kind) == [.noiseReduction, .eq, .compressor])
    }

    // MARK: The switch

    /// The mock's Compressor row: its dot off and its reading "off". The
    /// settings stay, so switching it back on is the sound you had.
    @Test func switchingAnEffectOffKeepsItsSettingsAndReadsOff() {
        var level = AudioLevel()
        level.addEffect(.compressor)
        level.compressor?.ratio = 6
        let changed = level.setEffect(.compressor, on: false)
        #expect(changed)
        #expect(!level.isEffectOn(.compressor))
        #expect(level.compressor?.ratio == 6)
        #expect(level.activeCompressor == nil)
        #expect(level.effectRows == [SoundEffectRow(kind: .compressor, reading: "off", isOn: false)])
        let unchanged = level.setEffect(.compressor, on: false)
        #expect(!unchanged)
        level.setEffect(.compressor, on: true)
        #expect(level.activeCompressor?.ratio == 6)
    }

    @Test func noiseReductionHasTheSameSwitch() {
        var level = AudioLevel(noiseReduction: .strong)
        level.setEffect(.noiseReduction, on: false)
        #expect(level.noiseReduction == .strong)
        #expect(level.activeNoiseReduction == nil)
        #expect(level.effectRows == [SoundEffectRow(kind: .noiseReduction, reading: "off", isOn: false)])
    }

    @Test func anEffectThatIsNotOnCannotBeSwitched() {
        var level = AudioLevel()
        let changed = level.setEffect(.eq, on: false)
        #expect(!changed)
        #expect(level == AudioLevel())
    }

    /// Taken off and put on again, it comes back on: the switch is a
    /// setting of the row, and the row went.
    @Test func removingAnEffectForgetsItsSwitch() {
        var level = AudioLevel()
        level.addEffect(.eq)
        level.setEffect(.eq, on: false)
        let removed = level.removeEffect(.eq)
        #expect(removed)
        #expect(level.eq == nil)
        #expect(level == AudioLevel())
        level.addEffect(.eq)
        #expect(level.isEffectOn(.eq))
    }

    // MARK: The settings

    @Test func theEQHoldsItsSettingsInsideTheirRanges() {
        var eq = SoundEQ.standard
        eq.lowCutHz = 5
        #expect(eq.lowCutHz == SoundEQ.lowCutRangeHz.lowerBound)
        eq.lowCutHz = 9_000
        #expect(eq.lowCutHz == SoundEQ.lowCutRangeHz.upperBound)
        eq.lowDB = -40
        #expect(eq.lowDB == SoundEQ.shelfRangeDB.lowerBound)
        eq.highDB = .nan
        #expect(eq.highDB == 0)
        eq.lowCutHz = 120
        #expect(eq.reading == "low cut 120")
    }

    @Test func theCompressorHoldsItsSettingsInsideTheirRanges() {
        var compressor = SoundCompressor.standard
        compressor.ratio = 0.5
        #expect(compressor.ratio == SoundCompressor.ratioRange.lowerBound)
        compressor.thresholdDB = 10
        #expect(compressor.thresholdDB == SoundCompressor.thresholdRangeDB.upperBound)
        compressor.ratio = 2.5
        #expect(compressor.reading == "2.5:1")
    }

    /// A compressor only ever turns the loud parts down, so on its own it
    /// leaves the voice quieter than it was. It makes half of what it takes
    /// off a full scale peak back up, the way Final Cut's Auto gain does, so
    /// putting one on never leaves the voice noticeably quieter and a peak
    /// at full scale still comes out under it.
    @Test func theCompressorMakesUpHalfWhatItTakesOffAFullPeak() {
        let compressor = SoundCompressor(thresholdDB: -18, ratio: 3)
        #expect(abs(compressor.makeupDB - 6) < 0.000_1)
        #expect(abs(compressor.outputDB(forInputDB: 0) - -6) < 0.000_1)
        #expect(abs(compressor.outputDB(forInputDB: -30) - -24) < 0.000_1)
        #expect(SoundCompressor(thresholdDB: -18, ratio: 1).makeupDB == 0)
    }

    // MARK: Saved

    @Test func aLevelWithEffectsSavesAndReadsBackTheSame() throws {
        var level = AudioLevel(noiseReduction: .light)
        level.addEffect(.eq)
        level.eq?.highDB = 3
        level.addEffect(.compressor)
        level.setEffect(.compressor, on: false)
        level.setEffect(.noiseReduction, on: false)
        #expect(!level.isUntouched)
        let data = try JSONEncoder().encode(level)
        let back = try JSONDecoder().decode(AudioLevel.self, from: data)
        #expect(back == level)
    }

    @Test func anUntouchedLevelStillWritesNothing() throws {
        let data = try JSONEncoder().encode(AudioLevel())
        #expect(String(decoding: data, as: UTF8.self) == "{}")
    }

    // MARK: What plays

    static func document(_ level: AudioLevel) -> (PhotonzDocument, UUID, SoundRef) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        let sound = SoundRef(durationMS: 10_000)
        let id = doc.addSound(sound, name: "voice", atMS: 0)
        doc.updateLayer(id: id) { $0.setSoundLevel(level) }
        return (doc, id, sound)
    }

    @Test func anEQedSoundPlaysAShapedCopyThatSaysHowItWasShaped() throws {
        var level = AudioLevel()
        level.addEffect(.eq)
        let (doc, id, sound) = Self.document(level)
        let played = try #require(doc.layer(id: id)?.playedSound)
        #expect(played.id != sound.id)
        #expect(played.sourceID == sound.id)
        #expect(played.cleaning?.reduction == nil)
        #expect(played.cleaning?.eq == SoundEQ.standard)
        #expect(played.cleaning?.compressor == nil)
        #expect(doc.audioMix().first?.sound == played)
    }

    @Test func everyEffectSwitchedOffPlaysTheFile() throws {
        var level = AudioLevel(noiseReduction: .medium)
        level.addEffect(.eq)
        level.addEffect(.compressor)
        for kind in SoundEffectKind.allCases { level.setEffect(kind, on: false) }
        let (doc, id, sound) = Self.document(level)
        #expect(doc.layer(id: id)?.playedSound == sound)
    }

    @Test func onlyTheEffectsThatAreOnShapeWhatPlays() throws {
        var level = AudioLevel(noiseReduction: .medium)
        level.addEffect(.eq)
        level.addEffect(.compressor)
        level.setEffect(.eq, on: false)
        let (doc, id, _) = Self.document(level)
        let played = try #require(doc.layer(id: id)?.playedSound)
        #expect(played.cleaning?.reduction == .medium)
        #expect(played.cleaning?.eq == nil)
        #expect(played.cleaning?.compressor == SoundCompressor.standard)
    }

    /// An EQ or a compressor learns nothing from the stretch a segment plays,
    /// so trimming a segment that is only EQ'd keeps the copy it has.
    @Test func aTrimDoesNotRemakeACopyNothingWasLearnedFor() throws {
        var level = AudioLevel()
        level.addEffect(.eq)
        var (doc, id, _) = Self.document(level)
        let before = try #require(doc.layer(id: id)?.playedSound)
        doc.updateLayer(id: id) { $0.time = LayerTime(inMS: 0, outMS: 4_000) }
        let after = try #require(doc.layer(id: id)?.playedSound)
        #expect(before.id == after.id)
        #expect(after.cleaning?.learnFromMS == [])
    }

    @Test func theCopysIDFollowsEverySetting() {
        let sound = SoundRef(durationMS: 5_000)
        func id(_ eq: SoundEQ?, _ compressor: SoundCompressor?, _ reduction: NoiseReduction? = nil) -> UUID {
            sound.shaped(reduction: reduction, learningFrom: reduction == nil ? [] : [0..<5_000],
                         eq: eq, compressor: compressor).id
        }
        let base = id(.standard, nil)
        #expect(base == id(.standard, nil))
        var lower = SoundEQ.standard
        lower.lowCutHz = 120
        #expect(id(lower, nil) != base)
        var bright = SoundEQ.standard
        bright.highDB = 2
        #expect(id(bright, nil) != base)
        #expect(id(.standard, .standard) != base)
        var harder = SoundCompressor.standard
        harder.ratio = 4
        #expect(id(.standard, harder) != id(.standard, .standard))
        #expect(id(.standard, nil, .medium) != base)
        // Noise alone is the very copy Clean noise has always made, so a
        // copy already on disk is still found.
        #expect(id(nil, nil, .medium) == sound.cleaned(.medium, learningFrom: [0..<5_000]).id)
    }
}
