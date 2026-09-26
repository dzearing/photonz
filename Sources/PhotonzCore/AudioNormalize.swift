import Foundation

// Normalize, and how loud a sound is (`docs/design/video-audio.md`, "Gain and
// Normalize").
//
// A screen recording takes system audio at the level the app playing it
// produced, before the Mac's own volume, and that is routinely thirty or forty
// decibels under full scale: the user's own recordings on 2026-09-25 peaked
// at -27 dBFS and measured -40 LUFS. Normalize is Premiere's answer (Audio
// Gain > Normalize Max Peak), and loudness normalization is what the web and
// podcast apps do to everything they play anyway. Both write the same thing:
// a number of decibels of gain on the segment (`AudioLevel.clipGainDB`),
// never a changed file.

public enum AudioNormalize {

    /// Where Normalize puts the loudest peak: a decibel under full scale, the
    /// headroom Premiere and every loudness spec leave for the encoder.
    public static let peakTargetDBFS: Double = -1

    /// The loudness a sound can be normalized to.
    public enum Target: String, CaseIterable, Sendable {
        /// What YouTube and most web players turn everything to.
        case web
        /// What Apple Podcasts and spoken-word apps ask for.
        case podcast

        public var lufs: Double {
            switch self {
            case .web: -14
            case .podcast: -16
            }
        }

        /// The row in the menu.
        public var title: String {
            switch self {
            case .web: "Loudness for Web, -14 LUFS"
            case .podcast: "Loudness for Podcast, -16 LUFS"
            }
        }
    }

    /// The stretches of the file a clip's pieces play, in file milliseconds,
    /// in order. A held frame and a piece too fast to carry sound play none.
    public static func sourceRangesMS(playedBy pieces: ClipPieces) -> [Range<Int>] {
        pieces.playback.compactMap { piece in
            guard piece.playsSound, piece.sourceLengthMS > 0 else { return nil }
            return piece.sourceInMS..<(piece.sourceInMS + piece.sourceLengthMS)
        }
    }

    /// The loudest peak the pieces play, in dBFS, or nil where they play
    /// nothing but silence.
    public static func peakDBFS(of wave: Waveform, playedBy pieces: ClipPieces) -> Double? {
        var loudest: Float = 0
        for range in sourceRangesMS(playedBy: pieces) {
            loudest = max(loudest, wave.peak(fromSourceMS: range.lowerBound, toSourceMS: range.upperBound))
        }
        guard loudest > 0 else { return nil }
        return 20 * log10(Double(loudest))
    }

    /// The gain that puts a peak at `target`.
    public static func gainDB(toPeak target: Double, fromPeakDBFS peak: Double) -> Double {
        AudioLevel.boundedClipGainDB(target - peak)
    }

    /// The gain that puts a sound measured at `lufs` at `target`, held so the
    /// loudest peak never passes `peakTargetDBFS`: normalizing never clips.
    public static func gainDB(toLoudness target: Double, fromLUFS lufs: Double,
                              peakDBFS peak: Double?) -> Double {
        var gain = target - lufs
        if let peak { gain = min(gain, peakTargetDBFS - peak) }
        return AudioLevel.boundedClipGainDB(gain)
    }
}

/// Integrated loudness, as ITU-R BS.1770-4 and EBU R 128 define it: K-weighted,
/// in 400 ms blocks overlapping by three quarters, gated at -70 LUFS and then
/// at ten below the loudness of what passed. Fed a sound in whatever chunks it
/// is read in; the answer does not depend on how it was cut up.
public struct LoudnessMeter: Sendable {
    public let sampleRate: Double
    public let channels: Int

    /// Two biquads per channel: the head's shelf, then the high pass.
    private var shelf: [Biquad]
    private var highPass: [Biquad]
    /// Frames in each 100 ms sub-block, four of which make a block.
    private let subBlockFrames: Int
    private var framesInSubBlock = 0
    private var sumInSubBlock: Double = 0
    /// The K-weighted energy of every finished sub-block, summed over channels.
    private var subBlocks: [Double] = []

    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        let (shelfStage, passStage) = Self.kWeighting(sampleRate: sampleRate)
        shelf = Array(repeating: shelfStage, count: self.channels)
        highPass = Array(repeating: passStage, count: self.channels)
        subBlockFrames = max(1, Int((sampleRate / 10).rounded()))
    }

    /// Add frames, channels interleaved. A trailing part of a frame is ignored.
    public mutating func add(interleaved samples: [Float]) {
        samples.withUnsafeBufferPointer { add(interleaved: $0) }
    }

    public mutating func add(interleaved samples: UnsafeBufferPointer<Float>) {
        let frames = samples.count / channels
        var index = 0
        for _ in 0..<frames {
            for channel in 0..<channels {
                let x = Double(samples[index])
                index += 1
                let y = highPass[channel].process(shelf[channel].process(x))
                sumInSubBlock += y * y
            }
            framesInSubBlock += 1
            if framesInSubBlock == subBlockFrames {
                subBlocks.append(sumInSubBlock)
                sumInSubBlock = 0
                framesInSubBlock = 0
            }
        }
    }

    /// The loudness in LUFS, or nil where nothing lasted a whole block or
    /// nothing passed the gates (silence).
    public var integratedLUFS: Double? {
        guard subBlocks.count >= 4 else { return nil }
        let blockFrames = Double(subBlockFrames * 4)
        var powers: [Double] = []
        powers.reserveCapacity(subBlocks.count - 3)
        var running = subBlocks[0] + subBlocks[1] + subBlocks[2]
        for end in 3..<subBlocks.count {
            running += subBlocks[end]
            powers.append(running / blockFrames)
            running -= subBlocks[end - 3]
        }
        let absolute = powers.filter { Self.lufs(ofPower: $0) > Self.absoluteGateLUFS }
        guard !absolute.isEmpty else { return nil }
        let relativeGate = Self.lufs(ofPower: absolute.reduce(0, +) / Double(absolute.count))
            + Self.relativeGateLU
        let gated = absolute.filter { Self.lufs(ofPower: $0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        return Self.lufs(ofPower: gated.reduce(0, +) / Double(gated.count))
    }

    static let absoluteGateLUFS: Double = -70
    static let relativeGateLU: Double = -10

    static func lufs(ofPower power: Double) -> Double {
        guard power > 0 else { return -.infinity }
        return -0.691 + 10 * log10(power)
    }

    /// One second-order filter, direct form I.
    struct Biquad: Sendable {
        let b0, b1, b2, a1, a2: Double
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
            (self.b0, self.b1, self.b2, self.a1, self.a2) = (b0, b1, b2, a1, a2)
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }

    /// The K-weighting pair designed for any sample rate, as libebur128 does,
    /// which gives exactly BS.1770's published coefficients at 48 kHz.
    static func kWeighting(sampleRate fs: Double) -> (Biquad, Biquad) {
        var f0 = 1681.974450955533
        let gainDB = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(Double.pi * f0 / fs)
        let vh = pow(10, gainDB / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0,
                           b1: 2 * (k * k - vh) / a0,
                           b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2 * (k * k - 1) / a0,
                           a2: (1 - k / q + k * k) / a0)
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / fs)
        a0 = 1 + k / q + k * k
        let pass = Biquad(b0: 1, b1: -2, b2: 1,
                          a1: 2 * (k * k - 1) / a0,
                          a2: (1 - k / q + k * k) / a0)
        return (shelf, pass)
    }
}

extension Waveform {

    /// How far down a waveform is drawn before it reads as flat. Fifty four
    /// decibels keeps room hiss off the lane and puts a -30 dBFS voice at
    /// nearly half height, where a straight scale drew it at three per cent.
    public static let drawnFloorDB: Double = -54

    /// How tall a peak draws, nought to one, in decibels rather than straight
    /// amplitude, the way Premiere's logarithmic waveforms draw: quiet speech
    /// and system audio are visible, and a doubling reads the same size
    /// anywhere on the lane. `gainDB` is the segment's gain, so the drawing
    /// follows a Normalize.
    public static func drawnHeight(ofPeak peak: Float, gainDB: Double = 0) -> Float {
        guard peak > 0, peak.isFinite else { return 0 }
        let dB = 20 * log10(Double(peak)) + gainDB
        let through = (dB - drawnFloorDB) / -drawnFloorDB
        return Float(min(max(0, through), 1))
    }
}
