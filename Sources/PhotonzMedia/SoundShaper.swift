import Foundation
import PhotonzCore

/// EQ and Compressor: what a sound's Effects list does to it after its noise
/// is taken out (`SoundEffects.swift`).
///
/// The EQ is three biquad filters from the Audio EQ Cookbook (Robert
/// Bristow-Johnson): a twelve decibel an octave high-pass for the low cut, and
/// a shelf at each end. A filter whose shelf is flat is left out rather than
/// run as a no-op. The compressor is feed-forward and linked across channels,
/// so a stereo image never leans toward whichever side was louder: one
/// envelope follows the loudest channel, rising in `attackMS` and falling in
/// `releaseMS`, and every channel gets the same gain.
///
/// It streams: `process` takes chunks of any size and keeps its state between
/// them, so the result is the same however the decoder hands the file over.
public final class SoundShaper {

    private let channels: Int
    private var filters: [[Biquad]]
    private let compressor: SoundCompressor?
    private let attack: Double
    private let release: Double
    private var envelope: Double = 0
    /// -1 dBFS.
    static let ceiling = pow(10, -1.0 / 20)

    /// Nil where there is nothing to do.
    public init?(sampleRate: Double, channels: Int, eq: SoundEQ?, compressor: SoundCompressor?) {
        guard sampleRate > 0, channels > 0, eq != nil || compressor != nil else { return nil }
        self.channels = channels
        var chain: [Biquad] = []
        if let eq {
            chain.append(.highPass(hz: eq.lowCutHz, sampleRate: sampleRate))
            if eq.lowDB != 0 { chain.append(.lowShelf(hz: SoundEQ.lowShelfHz, dB: eq.lowDB, sampleRate: sampleRate)) }
            if eq.highDB != 0 { chain.append(.highShelf(hz: SoundEQ.highShelfHz, dB: eq.highDB, sampleRate: sampleRate)) }
        }
        filters = Array(repeating: chain, count: channels)
        self.compressor = compressor
        attack = exp(-1 / (SoundCompressor.attackMS / 1000 * sampleRate))
        release = exp(-1 / (SoundCompressor.releaseMS / 1000 * sampleRate))
    }

    /// Shape one chunk in place, a channel per array, all the same length.
    public func process(_ chunk: inout [[Float]]) {
        let count = min(channels, chunk.count)
        for channel in 0..<count where !filters[channel].isEmpty {
            for index in filters[channel].indices {
                filters[channel][index].run(&chunk[channel])
            }
        }
        guard let compressor, count > 0 else { return }
        let frames = chunk[0].count
        for frame in 0..<frames {
            var loudest = 0.0
            for channel in 0..<count where frame < chunk[channel].count {
                loudest = max(loudest, Double(abs(chunk[channel][frame])))
            }
            let coefficient = loudest > envelope ? attack : release
            envelope = coefficient * envelope + (1 - coefficient) * loudest
            let levelDB = 20 * log10(max(envelope, 1e-9))
            var gain = pow(10, (compressor.outputDB(forInputDB: levelDB) - levelDB) / 20)
            // The envelope takes `attackMS` to catch a word that starts
            // loud, and until it does the make-up alone would lift that
            // word past full scale. Never past -1 dBFS, the ceiling
            // Normalize keeps to.
            if loudest * gain > Self.ceiling { gain = Self.ceiling / loudest }
            let applied = Float(gain)
            for channel in 0..<count where frame < chunk[channel].count {
                chunk[channel][frame] *= applied
            }
        }
    }

    // MARK: - One filter

    /// A second order section in transposed direct form II, which keeps the
    /// least state and loses the least precision in Float.
    struct Biquad {
        let b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0

        mutating func run(_ samples: inout [Float]) {
            for index in samples.indices {
                let x = Double(samples[index])
                let y = b0 * x + z1
                z1 = b1 * x - a1 * y + z2
                z2 = b2 * x - a2 * y
                samples[index] = Float(y)
            }
        }

        /// Normalised by a0, the way the cookbook leaves it.
        private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
            self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0
            self.a1 = a1 / a0; self.a2 = a2 / a0
        }

        private static func angle(_ hz: Double, _ sampleRate: Double) -> (cos: Double, sin: Double) {
            let w = 2 * Double.pi * min(hz, sampleRate * 0.45) / sampleRate
            return (Foundation.cos(w), Foundation.sin(w))
        }

        /// Butterworth: flat to the corner, then twelve decibels an octave.
        static func highPass(hz: Double, sampleRate: Double) -> Biquad {
            let (c, s) = angle(hz, sampleRate)
            let alpha = s / (2 * 0.707_106_781)
            return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2,
                          a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
        }

        /// A shelf with a slope of one, the gentlest that does not bump.
        static func lowShelf(hz: Double, dB: Double, sampleRate: Double) -> Biquad {
            let a = pow(10, dB / 40)
            let (c, s) = angle(hz, sampleRate)
            let alpha = s / 2 * 2.squareRoot()
            let root = 2 * a.squareRoot() * alpha
            return Biquad(b0: a * ((a + 1) - (a - 1) * c + root),
                          b1: 2 * a * ((a - 1) - (a + 1) * c),
                          b2: a * ((a + 1) - (a - 1) * c - root),
                          a0: (a + 1) + (a - 1) * c + root,
                          a1: -2 * ((a - 1) + (a + 1) * c),
                          a2: (a + 1) + (a - 1) * c - root)
        }

        static func highShelf(hz: Double, dB: Double, sampleRate: Double) -> Biquad {
            let a = pow(10, dB / 40)
            let (c, s) = angle(hz, sampleRate)
            let alpha = s / 2 * 2.squareRoot()
            let root = 2 * a.squareRoot() * alpha
            return Biquad(b0: a * ((a + 1) + (a - 1) * c + root),
                          b1: -2 * a * ((a - 1) + (a + 1) * c),
                          b2: a * ((a + 1) + (a - 1) * c - root),
                          a0: (a + 1) - (a - 1) * c + root,
                          a1: 2 * ((a - 1) - (a + 1) * c),
                          a2: (a + 1) - (a - 1) * c - root)
        }
    }
}
