import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Clean noise: the value on a segment, the cleaned sound the mix plays, and
/// where the noise is learned from (`docs/design/video-audio.md`, "Clean
/// noise").
///
/// Raising a quiet recording's gain raises its hiss, hum and fan with it, so
/// Normalize cleans the noise first by default, the way Premiere's DeNoise and
/// Descript's Studio Sound do. The document only ever says HOW MUCH; the
/// cleaned audio is a file the app renders beside the original.
@Suite("Clean noise")
struct NoiseCleaningTests {

    static func document(soundLengthMS: Int = 10_000) -> (PhotonzDocument, UUID, SoundRef) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        let sound = SoundRef(durationMS: soundLengthMS)
        let id = doc.addSound(sound, name: "voice", atMS: 0)
        return (doc, id, sound)
    }

    // MARK: - The value on the segment

    @Test("A segment is not cleaned until somebody asks, and asking is written down")
    func cleaningIsAValueOnTheSegment() throws {
        var level = AudioLevel()
        #expect(level.noiseReduction == nil)
        level.noiseReduction = .medium
        #expect(!level.isUntouched)
        let data = try JSONEncoder().encode(level)
        let back = try JSONDecoder().decode(AudioLevel.self, from: data)
        #expect(back.noiseReduction == .medium)
        #expect(back == level)
    }

    @Test("A level written before cleaning existed reads back uncleaned")
    func oldLevelsReadUncleaned() throws {
        let data = Data(#"{"clipGainDB":12}"#.utf8)
        let level = try JSONDecoder().decode(AudioLevel.self, from: data)
        #expect(level.noiseReduction == nil)
        #expect(level.clipGainDB == 12)
        // ...and one that is not cleaned writes nothing about cleaning.
        let written = String(decoding: try JSONEncoder().encode(level), as: UTF8.self)
        #expect(!written.contains("noise"))
    }

    @Test("Three strengths, Medium the default, each deeper than the last")
    func strengths() {
        #expect(NoiseReduction.allCases == [.light, .medium, .strong])
        #expect(NoiseReduction.standard == .medium)
        #expect(NoiseReduction.allCases.map(\.title) == ["Light", "Medium", "Strong"])
        #expect(NoiseReduction.light.floorDB > NoiseReduction.medium.floorDB)
        #expect(NoiseReduction.medium.floorDB > NoiseReduction.strong.floorDB)
        // Medium must take a steady noise down by the twelve decibels a
        // person can hear as "gone", with room to spare.
        #expect(NoiseReduction.medium.floorDB <= -18)
        // The panel's slider has a stop for each.
        for strength in NoiseReduction.allCases {
            #expect(NoiseReduction(step: strength.step) == strength)
        }
        #expect(NoiseReduction(step: -3) == .light)
        #expect(NoiseReduction(step: 9) == .strong)
    }

    // MARK: - What the mix plays

    @Test("An uncleaned segment plays its own sound")
    func uncleanedPlaysTheFile() throws {
        let (doc, _, sound) = Self.document()
        let mix = doc.audioMix()
        #expect(mix.count == 1)
        #expect(mix[0].sound == sound)
        #expect(mix[0].sound.cleaning == nil)
    }

    @Test("A cleaned segment plays a cleaned sound: same length, its own id, the file it came from")
    func cleanedPlaysTheCleanedSound() throws {
        var (doc, id, sound) = Self.document()
        doc.updateLayer(id: id) { layer in
            var level = AudioLevel()
            level.noiseReduction = .strong
            layer.setSoundLevel(level)
        }
        let mix = doc.audioMix()
        #expect(mix.count == 1)
        let played = mix[0].sound
        #expect(played.id != sound.id)
        #expect(played.durationMS == sound.durationMS)
        #expect(played.sourceID == sound.id)
        #expect(played.cleaning?.reduction == .strong)
        #expect(played.cleaning?.learnFromMS == [0..<10_000])
        // The layer says the same thing the mix does, so the timeline draws
        // the waveform of what plays.
        #expect(doc.layer(id: id)?.playedSound == played)
    }

    @Test("The cleaned sound's id is the same every time it is asked for, and differs by strength and stretch")
    func cleanedIDIsStable() {
        let sound = SoundRef(durationMS: 5_000)
        let a = sound.cleaned(.medium, learningFrom: [0..<5_000])
        let b = sound.cleaned(.medium, learningFrom: [0..<5_000])
        #expect(a.id == b.id)
        #expect(a == b)
        #expect(sound.cleaned(.light, learningFrom: [0..<5_000]).id != a.id)
        #expect(sound.cleaned(.medium, learningFrom: [0..<4_000]).id != a.id)
        #expect(SoundRef(durationMS: 5_000).cleaned(.medium, learningFrom: [0..<5_000]).id != a.id)
        // Cleaning a cleaned sound cleans the file, not the copy.
        let twice = a.cleaned(.strong, learningFrom: [0..<5_000])
        #expect(twice.sourceID == sound.id)
        #expect(twice == sound.cleaned(.strong, learningFrom: [0..<5_000]))
    }

    @Test("A trimmed segment learns its noise only from the stretch it plays")
    func trimmedLearnsFromWhatPlays() throws {
        var (doc, id, _) = Self.document()
        doc.updateLayer(id: id) { layer in
            var level = AudioLevel()
            level.noiseReduction = .medium
            layer.setSoundLevel(level)
            layer.time = LayerTime(inMS: 0, outMS: 4_000)
        }
        let played = try #require(doc.audioMix().first?.sound)
        #expect(played.cleaning?.learnFromMS == [0..<4_000])
    }

    @Test("Gain and cleaning ride together: gain still multiplies what the cleaned sound plays")
    func gainStillApplies() throws {
        var (doc, id, _) = Self.document()
        doc.updateLayer(id: id) { layer in
            var level = AudioLevel()
            level.noiseReduction = .medium
            level.clipGainDB = 20
            layer.setSoundLevel(level)
        }
        let segment = try #require(doc.audioMix().first)
        #expect(abs(segment.gain(atMS: 500) - 10) < 0.0001)
    }

    // MARK: - Where the noise is learned

    /// Speech-like bursts at 0.3 over a steady floor of 0.01 with a little
    /// wobble in it, the shape a voice over a fan draws.
    static func speechOverNoise() -> Waveform {
        var peaks: [Float] = []
        for bucket in 0..<500 {                     // ten seconds
            let inWord = (bucket / 25) % 2 == 1     // half a second on, half off
            let wobble = Float(bucket % 7) * 0.0005
            peaks.append(inWord ? 0.3 : 0.01 + wobble)
        }
        return Waveform(peaks: peaks)
    }

    @Test("The noise is learned from the pauses, never from the words")
    func quietStretchesAreThePauses() {
        let wave = Self.speechOverNoise()
        let quiet = NoiseReduction.quietStretchesMS(of: wave, within: [0..<10_000])
        #expect(!quiet.isEmpty)
        for stretch in quiet {
            #expect(wave.peak(fromSourceMS: stretch.lowerBound, toSourceMS: stretch.upperBound) < 0.05)
        }
        // Most of every pause counts: the floor wobbles, and the threshold
        // sits a little over the quietest of it so the wobble is still noise.
        let heard = quiet.reduce(0) { $0 + $1.count }
        #expect(heard >= 3_000)
    }

    @Test("Only the stretch a segment plays is listened to")
    func quietStretchesStayInsideTheRanges() {
        let wave = Self.speechOverNoise()
        let quiet = NoiseReduction.quietStretchesMS(of: wave, within: [2_000..<4_000])
        #expect(!quiet.isEmpty)
        for stretch in quiet {
            #expect(stretch.lowerBound >= 2_000)
            #expect(stretch.upperBound <= 4_000)
        }
    }

    @Test("Digital silence is not noise: a file that starts in nothing learns from its hiss")
    func digitalSilenceIsSkipped() {
        var peaks = [Float](repeating: 0, count: 100)       // two seconds of nothing
        peaks += Self.speechOverNoise().peaks
        let wave = Waveform(peaks: peaks)
        let quiet = NoiseReduction.quietStretchesMS(of: wave, within: [0..<wave.durationMS])
        #expect(!quiet.isEmpty)
        #expect(quiet.allSatisfy { $0.lowerBound >= 2_000 })
    }

    @Test("A stretch with nothing in it at all has nothing to learn")
    func silenceLearnsNothing() {
        let wave = Waveform(peaks: [Float](repeating: 0, count: 100))
        #expect(NoiseReduction.quietStretchesMS(of: wave, within: [0..<2_000]).isEmpty)
        #expect(NoiseReduction.quietStretchesMS(of: Self.speechOverNoise(), within: []).isEmpty)
    }
}
