import Foundation
import PhotonzCore

// The whoosh and tick a title plays as it builds (`TitleSounds.swift`), made
// here rather than shipped as files.
//
// Nothing about them needs a recording: a whoosh is air, which is noise passed
// through a band that sweeps up as it swells, and a tick is two short bright
// tones that die away inside a few hundredths of a second. Making them means
// the app carries no sound files, the person never has one to find, and every
// score sounds exactly as long as its title's builds. The same score always
// makes the same samples (the noise is seeded), so a file made in one run is
// the file the next one would have made.

public enum TitleSoundSynth {

    public static let sampleRate = 48_000
    /// The loudest any sample gets: about 14 dB under full scale, a soft bed
    /// under somebody's own recording rather than a sound effect over it.
    public static let peak: Float = 0.2

    /// The score as mono samples, `score.lengthMS` long.
    public static func samples(for score: TitleSoundScore) -> [Float] {
        let count = Int(Double(score.lengthMS) * Double(sampleRate) / 1000)
        var out = [Float](repeating: 0, count: max(0, count))
        for cue in score.cues {
            let start = Int(Double(cue.atMS) * Double(sampleRate) / 1000)
            let made: [Float]
            switch cue.kind {
            case .whoosh: made = whoosh(lengthMS: cue.lengthMS, energy: score.energy, seed: UInt64(cue.atMS) &+ 1)
            case .tick: made = tick(lengthMS: cue.lengthMS, energy: score.energy, seed: UInt64(cue.atMS) &+ 7)
            }
            for (index, sample) in made.enumerated() where start + index < out.count {
                out[start + index] += sample
            }
        }
        // Two sounds landing together are held under the same ceiling.
        let loudest = out.map { abs($0) }.max() ?? 0
        if loudest > peak {
            let scale = peak / loudest
            for index in out.indices { out[index] *= scale }
        }
        return out
    }

    /// The score as a 16 bit mono WAV file.
    public static func wav(for score: TitleSoundScore) -> Data {
        let samples = samples(for: score)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))                       // PCM
        append(UInt16(1))                       // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))          // bytes a second
        append(UInt16(2))                       // bytes a frame
        append(UInt16(16))                      // bits a sample
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        data.reserveCapacity(data.count + samples.count * 2)
        for sample in samples {
            append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
        }
        return data
    }

    // MARK: The sounds

    /// Noise through a band that sweeps up as it swells and settles as it
    /// falls away, loudest about three fifths of the way through: the sound
    /// of something passing close. Calm is lower and softer, Punchy higher
    /// and brighter.
    static func whoosh(lengthMS: Int, energy: TitleEnergy, seed: UInt64) -> [Float] {
        let count = lengthMS * sampleRate / 1000
        guard count > 0 else { return [] }
        let (low, high): (Double, Double) = switch energy {
        case .calm: (260, 1_500)
        case .normal: (360, 2_300)
        case .punchy: (520, 3_600)
        }
        var noise = Noise(seed: seed)
        // A state variable filter, band output, its centre moved every sample.
        var lowpass = 0.0, band = 0.0
        let damping = 1 / 1.4
        let crest = 0.6
        var made = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / Double(count)
            let swell = t < crest ? pow(sin(.pi / 2 * t / crest), 2)
                                  : pow(cos(.pi / 2 * (t - crest) / (1 - crest)), 2)
            let sweep = t < crest ? t / crest : 1 - 0.35 * (t - crest) / (1 - crest)
            let centre = low * pow(high / low, sweep)
            let f = 2 * sin(.pi * min(centre, Double(sampleRate) / 6) / Double(sampleRate))
            let input = noise.next()
            let highpass = input - lowpass - damping * band
            band += f * highpass
            lowpass += f * band
            made[index] = Float(band * swell)
        }
        return normalized(made, to: peak * 0.9)
    }

    /// Two bright tones and a breath of noise, gone in a few hundredths of a
    /// second: a small thing landing.
    static func tick(lengthMS: Int, energy: TitleEnergy, seed: UInt64) -> [Float] {
        let count = lengthMS * sampleRate / 1000
        guard count > 0 else { return [] }
        let (first, second): (Double, Double) = switch energy {
        case .calm: (1_900, 4_100)
        case .normal: (2_500, 5_300)
        case .punchy: (3_100, 6_500)
        }
        var noise = Noise(seed: seed)
        let rate = Double(sampleRate)
        var made = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let seconds = Double(index) / rate
            // Half a millisecond up, so it clicks rather than pops.
            let onset = min(1, seconds / 0.0005)
            let tone = 0.7 * sin(2 * .pi * first * seconds) * exp(-seconds / 0.012)
                + 0.35 * sin(2 * .pi * second * seconds) * exp(-seconds / 0.006)
            let breath = 0.25 * noise.next() * exp(-seconds / 0.002)
            made[index] = Float(onset * (tone + breath))
        }
        // The last millisecond brought down to nothing, so it ends clean.
        let fade = min(count, sampleRate / 1000)
        for step in 0..<fade { made[count - 1 - step] *= Float(step) / Float(fade) }
        return normalized(made, to: peak * 0.8)
    }

    static func normalized(_ samples: [Float], to level: Float) -> [Float] {
        let loudest = samples.map { abs($0) }.max() ?? 0
        guard loudest > 0 else { return samples }
        let scale = level / loudest
        return samples.map { $0 * scale }
    }

    /// White noise from a seed, -1 to 1: the same seed, the same air.
    struct Noise {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }
}
