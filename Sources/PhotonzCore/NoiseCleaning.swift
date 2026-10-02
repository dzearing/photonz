import Foundation

// Clean noise (`docs/design/video-audio.md`, "Clean noise").
//
// Normalize raises a quiet recording's gain, and the hiss, hum, fan and room
// tone under the voice rise with it. So Normalize cleans the noise first by
// default, the way Premiere's DeNoise and Descript's Studio Sound do: it
// learns what the noise sounds like from the pauses and takes that much out of
// every moment.
//
// The document only ever says HOW MUCH (`AudioLevel.noiseReduction`). The
// cleaned audio is a file the app renders beside the original, and the mix
// plays it under its own `SoundRef`: the same length, an id worked out from
// the file it came from, how hard it was cleaned and which stretches taught it
// the noise. So the player, the exporter, the meter and the waveform all key
// on `sound.id` exactly as they always have, and none of them needs a special
// case to hear the cleaned copy.

/// How hard noise is taken out: the three stops of the panel's Noise slider.
public enum NoiseReduction: String, Codable, CaseIterable, Sendable {
    case light, medium, strong

    /// What Normalize cleans with when nobody has picked a strength.
    public static let standard: NoiseReduction = .medium

    public var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    /// The most a moment of pure noise is turned down, in decibels. A floor
    /// rather than silence on purpose: taking noise all the way out leaves
    /// words hanging in a vacuum and turns what is left of it watery.
    public var floorDB: Double {
        switch self {
        case .light: -12
        case .medium: -20
        case .strong: -30
        }
    }

    /// How many times the learned noise is taken out: more than once reaches
    /// the noise that rises a little over its average.
    public var oversubtraction: Double {
        switch self {
        case .light: 1.0
        case .medium: 1.5
        case .strong: 2.0
        }
    }

    /// Where it sits on the slider, nought to two.
    public var step: Int {
        switch self {
        case .light: 0
        case .medium: 1
        case .strong: 2
        }
    }

    /// The stop nearest a slider position.
    public init(step: Int) {
        switch step {
        case ..<1: self = .light
        case 1: self = .medium
        default: self = .strong
        }
    }
}

/// What a cleaned sound is a cleaned copy OF, and how it was made: the
/// noise taken out, then the EQ, then the compressor (`SoundEffects.swift`),
/// whichever of them are on. The name says cleaning because that is the one
/// it began with; an EQ'd copy is made, kept and played exactly the same way.
public struct SoundCleaning: Hashable, Codable, Sendable {
    /// The file the cleaned copy is made from.
    public let sourceID: UUID
    /// How hard the noise is taken out, nil where it is not.
    public let reduction: NoiseReduction?
    /// The stretches of the file, in its own milliseconds, the noise is
    /// learned from: the ones the segment plays. Empty where no noise is
    /// taken out, since nothing else learns from them.
    public let learnFromMS: [Range<Int>]
    public let eq: SoundEQ?
    public let compressor: SoundCompressor?

    public init(sourceID: UUID, reduction: NoiseReduction?, learnFromMS: [Range<Int>],
                eq: SoundEQ? = nil, compressor: SoundCompressor? = nil) {
        self.sourceID = sourceID
        self.reduction = reduction
        self.learnFromMS = reduction == nil ? [] : learnFromMS
        self.eq = eq
        self.compressor = compressor
    }

    /// Bumped whenever the cleaning itself changes, so a copy cleaned the old
    /// way is never played as if it were cleaned the new way.
    public static let version = 1
    /// The same, for the EQ and the compressor.
    public static let shapingVersion = 1

    /// The id the cleaned copy goes by: the same every time for the same
    /// file, strength, stretches and settings, and different for any other.
    /// A copy with only noise taken out keeps the id it has always had, so
    /// copies already made are found again.
    public var cleanedID: UUID {
        var text = "clean-noise/v\(Self.version)/\(sourceID.uuidString)/\(reduction?.rawValue ?? "none")"
        for range in learnFromMS { text += "/\(range.lowerBound)-\(range.upperBound)" }
        if eq != nil || compressor != nil { text += "/shape-v\(Self.shapingVersion)" }
        if let eq {
            text += String(format: "/eq/%.2f/%.2f/%.2f", eq.lowCutHz, eq.lowDB, eq.highDB)
        }
        if let compressor {
            text += String(format: "/comp/%.2f/%.2f", compressor.thresholdDB, compressor.ratio)
        }
        let bytes = Array(text.utf8)
        let high = Self.fnv1a(bytes, basis: 0xcbf2_9ce4_8422_2325)
        let low = Self.fnv1a(bytes, basis: 0x8422_2325_cbf2_9ce4)
        var uuid = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            uuid[index] = UInt8(truncatingIfNeeded: high >> (8 * UInt64(index)))
            uuid[8 + index] = UInt8(truncatingIfNeeded: low >> (8 * UInt64(index)))
        }
        // Stamped as a name-based id so it can never be mistaken for a
        // random one a file was given.
        uuid[6] = (uuid[6] & 0x0f) | 0x50
        uuid[8] = (uuid[8] & 0x3f) | 0x80
        return UUID(uuid: (uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6], uuid[7],
                           uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15]))
    }

    private static func fnv1a(_ bytes: [UInt8], basis: UInt64) -> UInt64 {
        var hash = basis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

extension SoundRef {

    /// The cleaned copy of this sound, learning its noise from `ranges`.
    /// Cleaning a cleaned copy cleans the file it came from.
    public func cleaned(_ reduction: NoiseReduction, learningFrom ranges: [Range<Int>]) -> SoundRef {
        shaped(reduction: reduction, learningFrom: ranges, eq: nil, compressor: nil)
    }

    /// The copy of this sound made with every effect given, in the order the
    /// list reads: the file itself where none is given.
    public func shaped(reduction: NoiseReduction?, learningFrom ranges: [Range<Int>],
                       eq: SoundEQ?, compressor: SoundCompressor?) -> SoundRef {
        guard reduction != nil || eq != nil || compressor != nil else { return source }
        let cleaning = SoundCleaning(sourceID: sourceID, reduction: reduction, learnFromMS: ranges,
                                     eq: eq, compressor: compressor)
        return SoundRef(id: cleaning.cleanedID, durationMS: durationMS, cleaning: cleaning)
    }

    /// The file this sound is read from: itself, or the one it is a cleaned
    /// copy of.
    public var sourceID: UUID { cleaning?.sourceID ?? id }

    /// The original this is a cleaned copy of, or itself.
    public var source: SoundRef {
        cleaning == nil ? self : SoundRef(id: sourceID, durationMS: durationMS)
    }
}

extension Layer {

    /// What this layer's sound plays as: its file, or the copy of it made
    /// with the effects switched on in its list. The mix and the timeline's
    /// waveform both read this, so the waveform is a picture of what plays.
    public var playedSound: SoundRef? {
        guard let sound else { return nil }
        guard let level = soundLevel, let pieces = clipPieces else { return sound }
        let reduction = level.activeNoiseReduction
        let eq = level.activeEQ, compressor = level.activeCompressor
        guard reduction != nil || eq != nil || compressor != nil else { return sound }
        return sound.shaped(reduction: reduction,
                            learningFrom: reduction == nil ? [] : AudioNormalize.sourceRangesMS(playedBy: pieces),
                            eq: eq, compressor: compressor)
    }
}

extension NoiseReduction {

    /// Below this a bucket is digital silence, which says nothing about the
    /// noise: a recording that starts in nothing learns from its hiss.
    static let silencePeak: Float = 0.000_01

    /// How far over the quietest tenth of a sound a bucket may be and still
    /// count as noise: three decibels, which takes in a fan's wobble and
    /// stays well under the quietest word.
    static let quietSlack: Float = 1.41

    /// The stretches of a sound, inside `ranges`, that are only noise: the
    /// pauses between words, where a voice over a fan draws its floor.
    ///
    /// The quietest tenth of what is heard is taken as the noise's level, and
    /// every stretch within three decibels of it counts. A tenth because
    /// speech pauses far more often than that, and a talk with no pause at
    /// all still gives its quietest syllables rather than nothing.
    public static func quietStretchesMS(of wave: Waveform, within ranges: [Range<Int>]) -> [Range<Int>] {
        let bucket = Waveform.bucketMS
        var heard: [Int] = []
        for range in ranges {
            let first = max(0, range.lowerBound / bucket)
            let last = min(wave.peaks.count, (range.upperBound + bucket - 1) / bucket)
            guard first < last else { continue }
            for index in first..<last where wave.peaks[index] > silencePeak {
                heard.append(index)
            }
        }
        guard !heard.isEmpty else { return [] }
        let sorted = heard.map { wave.peaks[$0] }.sorted()
        let threshold = sorted[sorted.count / 10] * quietSlack

        var stretches: [Range<Int>] = []
        for index in heard.sorted() where wave.peaks[index] <= threshold {
            let from = index * bucket, to = from + bucket
            if let last = stretches.last, last.upperBound == from {
                stretches[stretches.count - 1] = last.lowerBound..<to
            } else {
                stretches.append(from..<to)
            }
        }
        // Held to the ranges themselves, so a bucket straddling a trim does
        // not reach past it.
        return stretches.compactMap { stretch in
            for range in ranges where range.overlaps(stretch) {
                let clamped = max(range.lowerBound, stretch.lowerBound)..<min(range.upperBound, stretch.upperBound)
                if !clamped.isEmpty { return clamped }
            }
            return nil
        }
    }
}
