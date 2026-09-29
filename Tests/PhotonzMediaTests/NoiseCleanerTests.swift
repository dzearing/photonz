import AVFoundation
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzMedia

/// Clean noise, measured off real files (`docs/design/video-audio.md`, "Clean
/// noise").
///
/// What a person hears as "the noise went away" is the level of the pauses
/// dropping while the words stay as loud as they were, so that is exactly what
/// these measure: the level of a stretch with no voice in it, and the level of
/// a stretch that is mostly voice, before and after.
@Suite("Clean noise, on real files")
struct NoiseCleanerTests {

    static let rate: Double = 48_000

    /// A voice-like sound (a 180 Hz buzz with its harmonics, swelling and
    /// falling like a syllable) in `words`, over a fan's steady hiss and a
    /// 60 Hz hum the whole way through.
    static func noisyVoice(seconds: Double, words: [ClosedRange<Double>],
                           voice: Double = 0.2, hiss: Double = 0.004, hum: Double = 0.003) -> [Float] {
        var state: UInt32 = 12_345
        func random() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
        let count = Int(seconds * rate)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / rate
            var value = hiss * random() * 1.7 + hum * sin(2 * .pi * 60 * t)
            if let word = words.first(where: { $0.contains(t) }) {
                let through = (t - word.lowerBound) / (word.upperBound - word.lowerBound)
                let swell = sin(.pi * through)
                var buzz = 0.0
                for harmonic in 1...8 { buzz += sin(2 * .pi * 180 * Double(harmonic) * t) / Double(harmonic) }
                value += voice * swell * buzz / 2
            }
            samples[index] = Float(value)
        }
        return samples
    }

    static func writeWAV(_ samples: [Float], to url: URL, channels: Int = 1) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate,
                                                channels: AVAudioChannelCount(channels)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format,
                                                   frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<channels {
            // The second channel a touch quieter, so the channels are not one.
            let scale: Float = channel == 0 ? 1 : 0.8
            for index in samples.indices { buffer.floatChannelData?[channel][index] = samples[index] * scale }
        }
        try file.write(from: buffer)
    }

    /// Every sample of a file's first channel.
    static func read(_ url: URL) throws -> (samples: [Float], rate: Double, channels: Int) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384))
        var samples: [Float] = []
        // A read hands back what it has to hand, not always all that was asked.
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            samples += UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        }
        return (samples, file.processingFormat.sampleRate, Int(file.processingFormat.channelCount))
    }

    static func rmsDB(_ samples: [Float], from: Double, to: Double) -> Double {
        let lo = Int(from * rate), hi = min(samples.count, Int(to * rate))
        guard hi > lo else { return -.infinity }
        var sum = 0.0
        for index in lo..<hi { sum += Double(samples[index]) * Double(samples[index]) }
        return 10 * log10(sum / Double(hi - lo))
    }

    static func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-noise-\(UUID().uuidString)-\(name)")
    }

    static let words: [ClosedRange<Double>] = [0.8...1.6, 2.4...3.4, 4.2...4.9]

    /// Clean a file the way the app does: learn where it is quiet off its
    /// own waveform, then clean.
    static func clean(_ source: URL, _ reduction: NoiseReduction) async throws -> (URL, NoiseCleaner.Result) {
        let reading = try #require(await SoundFile.read(at: source))
        let quiet = NoiseReduction.quietStretchesMS(of: reading.waveform,
                                                    within: [0..<reading.durationMS])
        let out = temporary("clean.caf")
        let result = try await NoiseCleaner.write(from: source, reduction: reduction,
                                                  quietMS: quiet, to: out)
        return (out, result)
    }

    // MARK: -

    @Test("Frames are about forty milliseconds, a power of two long")
    func frameLengths() {
        #expect(NoiseCleaner.frameLength(sampleRate: 48_000) == 2048)
        #expect(NoiseCleaner.frameLength(sampleRate: 44_100) == 2048)
        #expect(NoiseCleaner.frameLength(sampleRate: 22_050) == 1024)
    }

    @Test("With no noise learned, cleaning gives back exactly what went in, in step")
    func noNoiseIsTransparent() throws {
        let input = Self.noisyVoice(seconds: 1, words: [0.2...0.7])
        let cleaner = try #require(NoiseCleaner.ChannelCleaner(
            sampleRate: Self.rate, noise: [], reduction: .strong))
        var output: [Float] = []
        // Fed in uneven chunks, the way a decoder hands them over.
        var at = 0
        for size in [100, 4096, 1, 3000, 777] + Array(repeating: 5000, count: 20) where at < input.count {
            let end = min(input.count, at + size)
            output += cleaner.push(Array(input[at..<end]))
            at = end
        }
        output += cleaner.finish()
        output = Array(output.prefix(input.count))
        #expect(output.count == input.count)
        var worst: Float = 0
        for index in input.indices { worst = max(worst, abs(output[index] - input[index])) }
        #expect(worst < 0.0005)
    }

    @Test("Medium takes the pauses down by well over twelve decibels and keeps the words as loud")
    func mediumCleansThePauses() async throws {
        let source = Self.temporary("noisy.wav")
        defer { try? FileManager.default.removeItem(at: source) }
        try Self.writeWAV(Self.noisyVoice(seconds: 5.5, words: Self.words), to: source)
        let (cleaned, result) = try await Self.clean(source, .medium)
        defer { try? FileManager.default.removeItem(at: cleaned) }
        #expect(result.framesLearned >= 4)

        let before = try Self.read(source).samples
        let after = try Self.read(cleaned)
        // Same rate, same length, sample for sample.
        #expect(after.rate == Self.rate)
        #expect(after.samples.count == before.count)

        let pauseBefore = Self.rmsDB(before, from: 1.8, to: 2.2)
        let pauseAfter = Self.rmsDB(after.samples, from: 1.8, to: 2.2)
        #expect(pauseBefore - pauseAfter >= 12, "pause \(pauseBefore) -> \(pauseAfter)")
        print("clean-noise medium: pause \(pauseBefore) -> \(pauseAfter) dB")

        let wordBefore = Self.rmsDB(before, from: 2.6, to: 3.2)
        let wordAfter = Self.rmsDB(after.samples, from: 2.6, to: 3.2)
        #expect(abs(wordBefore - wordAfter) < 1, "word \(wordBefore) -> \(wordAfter)")
        print("clean-noise medium: word \(wordBefore) -> \(wordAfter) dB")
    }

    @Test("Stronger takes more out: Light, then Medium, then Strong")
    func strengthsOrder() async throws {
        let source = Self.temporary("noisy.wav")
        defer { try? FileManager.default.removeItem(at: source) }
        try Self.writeWAV(Self.noisyVoice(seconds: 5.5, words: Self.words), to: source)
        var pauses: [Double] = []
        for reduction in NoiseReduction.allCases {
            let (cleaned, _) = try await Self.clean(source, reduction)
            pauses.append(Self.rmsDB(try Self.read(cleaned).samples, from: 1.8, to: 2.2))
            try? FileManager.default.removeItem(at: cleaned)
        }
        #expect(pauses[0] > pauses[1] + 3)
        #expect(pauses[1] > pauses[2] + 3)
    }

    @Test("A word starts where it started: the cleaned copy is in step with the file")
    func staysInStep() async throws {
        let source = Self.temporary("noisy.wav")
        defer { try? FileManager.default.removeItem(at: source) }
        let input = Self.noisyVoice(seconds: 5.5, words: Self.words, hiss: 0.001, hum: 0)
        try Self.writeWAV(input, to: source)
        let (cleaned, _) = try await Self.clean(source, .medium)
        defer { try? FileManager.default.removeItem(at: cleaned) }
        let output = try Self.read(cleaned).samples
        // Cross-correlate around the second word: the best lag is nought.
        let lo = Int(2.5 * Self.rate), hi = Int(3.3 * Self.rate)
        var best = (lag: 99, score: -Double.infinity)
        for lag in -8...8 {
            var score = 0.0
            for index in lo..<hi { score += Double(input[index]) * Double(output[index + lag]) }
            if score > best.score { best = (lag, score) }
        }
        #expect(best.lag == 0)
    }

    @Test("Stereo stays stereo, each side cleaned")
    func stereo() async throws {
        let source = Self.temporary("noisy-stereo.wav")
        defer { try? FileManager.default.removeItem(at: source) }
        try Self.writeWAV(Self.noisyVoice(seconds: 5.5, words: Self.words), to: source, channels: 2)
        let (cleaned, result) = try await Self.clean(source, .medium)
        defer { try? FileManager.default.removeItem(at: cleaned) }
        #expect(result.channels == 2)
        let file = try AVAudioFile(forReading: cleaned)
        #expect(file.processingFormat.channelCount == 2)
    }

    @Test("A file with no sound in it is refused, and nothing is left behind")
    func noSoundIsRefused() async throws {
        let source = Self.temporary("empty.txt")
        try Data("not a sound".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let out = Self.temporary("never.caf")
        await #expect(throws: (any Error).self) {
            try await NoiseCleaner.write(from: source, reduction: .medium, quietMS: [], to: out)
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    // MARK: - The walk's recording

    /// The recording the walk opens: spoken words over a fan and a mains
    /// hum, at the level system audio lands in a screen recording.
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Scripts/playtest/fixtures/Noisy voice recording 1280x800.mp4")

    @Test("On the noisy recording, Normalize with Clean noise leaves the pauses 12 dB quieter than Normalize alone, the voice as loud")
    func fixtureMeasures() async throws {
        let reading = try #require(await SoundFile.read(at: Self.fixture))
        let whole = [0..<reading.durationMS]
        let quiet = NoiseReduction.quietStretchesMS(of: reading.waveform, within: whole)
        let out = ProcessInfo.processInfo.environment["PHOTONZ_CLEANED_OUT"].map(URL.init(fileURLWithPath:))
            ?? Self.temporary("fixture-clean.caf")
        let result = try await NoiseCleaner.write(from: Self.fixture, reduction: .medium,
                                                  quietMS: quiet, to: out)
        defer { if ProcessInfo.processInfo.environment["PHOTONZ_CLEANED_OUT"] == nil {
            try? FileManager.default.removeItem(at: out) } }
        #expect(result.framesLearned >= 4)

        let cleanedShape = try #require(await SoundFile.read(at: out)).waveform
        func peakDB(_ wave: Waveform) -> Double {
            20 * log10(Double(wave.peak(fromSourceMS: 0, toSourceMS: wave.durationMS)))
        }
        let gainAlone = AudioNormalize.gainDB(toPeak: AudioNormalize.peakTargetDBFS, fromPeakDBFS: peakDB(reading.waveform))
        let gainCleaned = AudioNormalize.gainDB(toPeak: AudioNormalize.peakTargetDBFS, fromPeakDBFS: peakDB(cleanedShape))

        let before = try Self.read(Self.fixture).samples
        let after = try Self.read(out).samples
        // The lead-in before the first word: nothing but the fan and the hum.
        let floorAlone = Self.rmsDB(before, from: 0.1, to: 0.7) + gainAlone
        let floorCleaned = Self.rmsDB(after, from: 0.1, to: 0.7) + gainCleaned
        // The voice: every 50 ms window of the original within 20 dB of its
        // loudest, measured in both at their Normalize gains. Whole-file
        // loudness is the wrong ruler here: it gates the pauses out once they
        // are quiet enough, and so reads the cleaned file louder for having
        // less noise in it.
        let window = Int(0.05 * Self.rate)
        var windows: [(Double, Double)] = []
        for start in stride(from: 0, to: before.count - window, by: window) {
            windows.append((Self.rmsDB(before, from: Double(start) / Self.rate, to: Double(start + window) / Self.rate),
                            Self.rmsDB(after, from: Double(start) / Self.rate, to: Double(start + window) / Self.rate)))
        }
        let loudest = windows.map(\.0).max() ?? 0
        let voiced = windows.filter { $0.0 > loudest - 20 }
        func mean(_ values: [Double]) -> Double {
            10 * log10(values.map { pow(10, $0 / 10) }.reduce(0, +) / Double(max(1, values.count)))
        }
        let voiceAlone = mean(voiced.map(\.0)) + gainAlone
        let voiceCleaned = mean(voiced.map(\.1)) + gainCleaned
        print(String(format: "clean-noise fixture: gain alone %+.1f dB, with clean %+.1f dB", gainAlone, gainCleaned))
        print(String(format: "clean-noise fixture: noise floor after Normalize alone %.1f dBFS, with Clean noise %.1f dBFS (%.1f dB lower)",
                     floorAlone, floorCleaned, floorAlone - floorCleaned))
        print(String(format: "clean-noise fixture: voice after Normalize alone %.1f dBFS RMS, with Clean noise %.1f dBFS RMS (%d windows)",
                     voiceAlone, voiceCleaned, voiced.count))
        #expect(floorAlone - floorCleaned >= 12)
        #expect(abs(voiceAlone - voiceCleaned) < 1.5)
    }
}
