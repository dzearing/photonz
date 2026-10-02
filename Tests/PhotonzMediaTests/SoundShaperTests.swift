import AVFoundation
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzMedia

/// EQ and Compressor, measured off the samples they make
/// (`SoundEffects.swift`, `SoundShaper.swift`).
///
/// What a person hears from a low cut is the rumble going and the voice
/// staying, and from a compressor the loud words coming down toward the quiet
/// ones, so those are what these measure.
@Suite("EQ and Compressor, on samples and files")
struct SoundShaperTests {

    static let rate: Double = 48_000

    static func tone(_ hz: Double, amplitude: Double, seconds: Double = 1) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(amplitude * sin(2 * .pi * hz * Double($0) / rate)) }
    }

    /// The level of the last half of a run, past anything a filter does as
    /// it starts.
    static func settledDB(_ samples: [Float]) -> Double {
        let tail = samples[(samples.count / 2)...]
        let sum = tail.reduce(0.0) { $0 + Double($1) * Double($1) }
        return 10 * log10(sum / Double(tail.count))
    }

    static func shaped(_ samples: [Float], eq: SoundEQ?, compressor: SoundCompressor?,
                       chunk: Int = 4_000) throws -> [Float] {
        let shaper = try #require(SoundShaper(sampleRate: rate, channels: 1, eq: eq, compressor: compressor))
        var out: [Float] = []
        var at = 0
        while at < samples.count {
            var piece = [Array(samples[at..<min(samples.count, at + chunk)])]
            shaper.process(&piece)
            out += piece[0]
            at += chunk
        }
        return out
    }

    @Test("Nothing to do is no shaper at all")
    func nothingIsNil() {
        #expect(SoundShaper(sampleRate: Self.rate, channels: 1, eq: nil, compressor: nil) == nil)
    }

    @Test("The low cut takes a 30 Hz rumble down and leaves a 1 kHz voice where it was")
    func lowCut() throws {
        let rumble = Self.tone(30, amplitude: 0.3)
        let voice = Self.tone(1_000, amplitude: 0.3)
        let rumbleDrop = Self.settledDB(rumble) - Self.settledDB(try Self.shaped(rumble, eq: .standard, compressor: nil))
        let voiceDrop = Self.settledDB(voice) - Self.settledDB(try Self.shaped(voice, eq: .standard, compressor: nil))
        #expect(rumbleDrop > 12)
        #expect(abs(voiceDrop) < 0.2)
    }

    @Test("A higher low cut takes more of the low end")
    func higherLowCut() throws {
        let low = Self.tone(120, amplitude: 0.3)
        var high = SoundEQ.standard
        high.lowCutHz = 300
        let at80 = Self.settledDB(try Self.shaped(low, eq: .standard, compressor: nil))
        let at300 = Self.settledDB(try Self.shaped(low, eq: high, compressor: nil))
        #expect(at80 - at300 > 6)
    }

    @Test("The shelves raise and lower their ends and leave the middle")
    func shelves() throws {
        var eq = SoundEQ.standard
        eq.lowCutHz = 20
        eq.lowDB = 6
        eq.highDB = -6
        let body = Self.tone(80, amplitude: 0.1)
        let air = Self.tone(12_000, amplitude: 0.1)
        let middle = Self.tone(1_000, amplitude: 0.1)
        let bodyGain = Self.settledDB(try Self.shaped(body, eq: eq, compressor: nil)) - Self.settledDB(body)
        let airGain = Self.settledDB(try Self.shaped(air, eq: eq, compressor: nil)) - Self.settledDB(air)
        let middleGain = Self.settledDB(try Self.shaped(middle, eq: eq, compressor: nil)) - Self.settledDB(middle)
        #expect(bodyGain > 4.5 && bodyGain < 6.5)
        #expect(airGain < -4.5 && airGain > -6.5)
        #expect(abs(middleGain) < 1)
    }

    @Test("The compressor brings a loud tone and a quiet one closer together")
    func compressorNarrowsTheGap() throws {
        let compressor = SoundCompressor(thresholdDB: -18, ratio: 3)
        let loud = Self.tone(440, amplitude: 0.9)
        let quiet = Self.tone(440, amplitude: 0.03)
        let loudOut = Self.settledDB(try Self.shaped(loud, eq: nil, compressor: compressor))
        let quietOut = Self.settledDB(try Self.shaped(quiet, eq: nil, compressor: compressor))
        let gapIn = Self.settledDB(loud) - Self.settledDB(quiet)
        let gapOut = loudOut - quietOut
        #expect(gapIn - gapOut > 10)
        // Under the threshold it is only the make-up.
        #expect(abs(quietOut - Self.settledDB(quiet) - compressor.makeupDB) < 0.5)
        // Nothing comes out past -1 dBFS, not even the start of a loud
        // word before the envelope has caught it.
        let peakOut = try Self.shaped(loud, eq: nil, compressor: compressor).map { abs($0) }.max() ?? 1
        #expect(peakOut <= Float(SoundShaper.ceiling) + 0.000_1)
    }

    @Test("Chunks of any size make the same sound")
    func chunking() throws {
        let input = Self.tone(200, amplitude: 0.5, seconds: 0.5)
        let a = try Self.shaped(input, eq: .standard, compressor: .standard, chunk: 333)
        let b = try Self.shaped(input, eq: .standard, compressor: .standard, chunk: 10_000)
        #expect(a.count == b.count)
        var worst: Float = 0
        for index in a.indices { worst = max(worst, abs(a[index] - b[index])) }
        #expect(worst < 0.000_01)
    }

    @Test("A file EQ'd and compressed with no noise taken out is written whole and in step")
    func writesAFile() async throws {
        let source = NoiseCleanerTests.temporary("shape-in.wav")
        let samples = Self.tone(30, amplitude: 0.3, seconds: 1.5)
        try NoiseCleanerTests.writeWAV(samples, to: source, channels: 2)
        let out = NoiseCleanerTests.temporary("shape-out.caf")
        try await NoiseCleaner.write(from: source, reduction: nil, quietMS: [], eq: .standard,
                                     compressor: .standard, to: out)
        let read = try NoiseCleanerTests.read(out)
        #expect(read.samples.count == samples.count)
        #expect(read.channels == 2)
        #expect(Self.settledDB(samples) - Self.settledDB(read.samples) > 6)
    }
}
