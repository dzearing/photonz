import AVFoundation
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzMedia

/// The whoosh and tick a title plays as it builds, made rather than shipped
/// (`TitleSoundSynth.swift`, `TitleSounds.swift`).
///
/// What a person hears is soft air swelling up as the words come in and a
/// short bright click as an accent lands, nothing before, nothing after, and
/// never loud, so those are what these measure off the samples.
@Suite("A title's whoosh and tick, made and written")
struct TitleSoundSynthTests {

    static let rate = Double(TitleSoundSynth.sampleRate)

    static func level(_ samples: [Float], fromMS: Int, toMS: Int) -> Double {
        let lo = max(0, Int(Double(fromMS) * rate / 1000)), hi = min(samples.count, Int(Double(toMS) * rate / 1000))
        guard hi > lo else { return 0 }
        let sum = samples[lo..<hi].reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(hi - lo)).squareRoot()
    }

    static let score = TitleSoundScore(cues: [TitleSoundCue(.whoosh, atMS: 100, lengthMS: 600),
                                              TitleSoundCue(.tick, atMS: 900, lengthMS: 90)],
                                       energy: .normal)

    @Test("It runs exactly as long as the score, and is silent where nothing sounds")
    func lengthAndSilence() {
        let samples = TitleSoundSynth.samples(for: Self.score)
        #expect(samples.count == Int(Double(Self.score.lengthMS) * Self.rate / 1000))
        #expect(Self.level(samples, fromMS: 0, toMS: 95) == 0)
        #expect(Self.level(samples, fromMS: 760, toMS: 895) < 0.0005)
    }

    @Test("The whoosh swells and falls away, loudest past its middle")
    func whooshSwells() {
        let samples = TitleSoundSynth.samples(for: Self.score)
        let start = Self.level(samples, fromMS: 100, toMS: 160)
        let swell = Self.level(samples, fromMS: 400, toMS: 500)
        let tail = Self.level(samples, fromMS: 640, toMS: 700)
        #expect(swell > start * 3)
        #expect(swell > tail * 2)
    }

    @Test("The tick is short: loud at its moment, gone within its length")
    func tickIsShort() {
        let samples = TitleSoundSynth.samples(for: Self.score)
        let hit = Self.level(samples, fromMS: 900, toMS: 915)
        let after = Self.level(samples, fromMS: 960, toMS: 990)
        #expect(hit > 0.02)
        #expect(after < hit / 10)
    }

    @Test("Nothing in it is loud: a soft bed under somebody's recording", arguments: TitleEnergy.allCases)
    func neverLoud(_ energy: TitleEnergy) {
        let score = TitleSoundScore(cues: Self.score.cues, energy: energy)
        let samples = TitleSoundSynth.samples(for: score)
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.1)
        #expect(peak <= TitleSoundSynth.peak + 0.0001)
    }

    @Test("Made twice, it is the same sound")
    func deterministic() {
        #expect(TitleSoundSynth.samples(for: Self.score) == TitleSoundSynth.samples(for: Self.score))
    }

    @Test("Written as a WAV the Mac reads back at the score's length")
    func writesAWav() throws {
        let url = TestTone.scratch().appendingPathComponent("title-sound.wav")
        try TitleSoundSynth.wav(for: Self.score).write(to: url)
        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == Self.rate)
        let ms = Double(file.length) / Self.rate * 1000
        #expect(abs(ms - Double(Self.score.lengthMS)) < 2)
    }

    @Test("A title with its sounds on exports with its whoosh where the title comes in")
    func exportsWithTheTitle() async throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 6_000, sourceInMS: 0, sourceLengthMS: 6_000)
        doc.layers = [clip]
        doc.durationMS = 6_000
        let landed = doc.insertTitle(BuiltInTitle.keynote, atTimeMS: 2_000)
        let title = try #require(landed).layerID
        let turned = doc.setTitleSounds(layerID: title, on: true)
        #expect(turned)

        var urls: [UUID: URL] = [:]
        for (id, score) in doc.titleSoundScores {
            let url = TestTone.scratch().appendingPathComponent("\(id).wav")
            try TitleSoundSynth.wav(for: score).write(to: url)
            urls[id] = url
        }
        let mix = doc.audioMix()
        #expect(mix.count == 1)
        let out = TestTone.scratch().appendingPathComponent("title-sounds-export.m4a")
        _ = try await AudioMixdown.write(mix, urls: urls, to: out)
        let reading = try #require(await SoundFile.read(at: out))
        let peaks = reading.waveform.peaks
        func loudest(_ from: Int, _ to: Int) -> Float {
            peaks[(from / Waveform.bucketMS)..<min(peaks.count, to / Waveform.bucketMS)].max() ?? 0
        }
        #expect(loudest(2_100, 2_800) > 0.05)
    }
}
