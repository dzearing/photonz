import Foundation

// The Effects list on a picked sound (`pages/video-audio.html`, `#gEffects`,
// and the plus on its header, `#efxMenu`).
//
// The mock's add menu offers EQ, Compressor and Noise reduction. Noise
// reduction is not a new setting: it is `AudioLevel.noiseReduction`, the very
// value Normalize's Clean noise writes and the segment's Remove Noise Cleaning
// clears. EQ and Compressor sit beside it on the level (`eq`, `compressor`),
// and all three are heard the same way: the mix plays a copy of the file made
// with them (`SoundCleaning`), so the player, the exporter, the meter and
// Normalize all hear exactly what the list says.
//
// Each row has an on switch (the mock's `.en` dot). Off keeps every setting
// and stops the effect, which is how you compare with and without: the
// switch is `AudioLevel.effectsOff`, and taking a row off forgets it.

/// One kind of thing a sound's Effects list can hold, in the add menu's order.
public enum SoundEffectKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case eq, compressor, noiseReduction

    public var id: String { rawValue }

    /// The name on the menu row and the list row, as the mock prints it.
    public var title: String {
        switch self {
        case .eq: "EQ"
        case .compressor: "Compressor"
        case .noiseReduction: "Noise reduction"
        }
    }

    /// Whether the app can put this on a sound. Every kind on the menu can.
    public var isBuilt: Bool { true }

    /// The order the sound passes through them, which is the order the list
    /// reads top down: cleaned first, so the compressor never lifts the noise
    /// about to be taken out, then shaped, then evened out.
    public static let processingOrder: [SoundEffectKind] = [.noiseReduction, .eq, .compressor]
}

/// One row of the list: what it is, the value at its end, and its switch.
public struct SoundEffectRow: Hashable, Sendable, Identifiable {
    public let kind: SoundEffectKind
    /// The mock's `.emeta`: "low cut 80", "3:1", the strength, or "off".
    public let reading: String
    /// The mock's `.en` dot: whether the effect is heard.
    public let isOn: Bool

    public var id: String { kind.rawValue }

    public init(kind: SoundEffectKind, reading: String, isOn: Bool) {
        self.kind = kind
        self.reading = reading
        self.isOn = isOn
    }
}

// MARK: - EQ

/// The EQ a sound can take: a low cut, and a shelf at each end. What
/// Premiere's dialogue EQ presets come down to for a voice: take the rumble
/// out under it, warm or thin the body, and brighten or soften the top.
public struct SoundEQ: Hashable, Codable, Sendable {

    /// Where the low cut starts. Eighty hertz is under the lowest voice and
    /// over most desk thumps and fan rumble, which is why the mock reads it.
    public var lowCutHz: Double {
        didSet { lowCutHz = Self.held(lowCutHz, in: Self.lowCutRangeHz, else: Self.standard.lowCutHz) }
    }
    /// The body of the sound, under `lowShelfHz`: a boost or cut in decibels.
    public var lowDB: Double {
        didSet { lowDB = Self.held(lowDB, in: Self.shelfRangeDB, else: 0) }
    }
    /// The top of the sound, over `highShelfHz`: a boost or cut in decibels.
    public var highDB: Double {
        didSet { highDB = Self.held(highDB, in: Self.shelfRangeDB, else: 0) }
    }

    public static let lowCutRangeHz: ClosedRange<Double> = 20...400
    public static let shelfRangeDB: ClosedRange<Double> = -12...12
    /// Where the two shelves turn: the chest of a voice, and its air.
    public static let lowShelfHz: Double = 150
    public static let highShelfHz: Double = 5_000

    /// What the plus puts on: the mock's low cut at 80, nothing else moved.
    public static let standard = SoundEQ(lowCutHz: 80, lowDB: 0, highDB: 0)

    public init(lowCutHz: Double, lowDB: Double, highDB: Double) {
        self.lowCutHz = Self.held(lowCutHz, in: Self.lowCutRangeHz, else: 80)
        self.lowDB = Self.held(lowDB, in: Self.shelfRangeDB, else: 0)
        self.highDB = Self.held(highDB, in: Self.shelfRangeDB, else: 0)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(lowCutHz: try c.decodeIfPresent(Double.self, forKey: .lowCutHz) ?? 80,
                  lowDB: try c.decodeIfPresent(Double.self, forKey: .lowDB) ?? 0,
                  highDB: try c.decodeIfPresent(Double.self, forKey: .highDB) ?? 0)
    }

    /// The mock's `.emeta`: "low cut 80".
    public var reading: String { "low cut \(Int(lowCutHz.rounded()))" }

    static func held(_ value: Double, in range: ClosedRange<Double>, else fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(range.lowerBound, value), range.upperBound)
    }
}

// MARK: - Compressor

/// A compressor: everything louder than the threshold is turned down by the
/// ratio, so the loud words and the quiet ones sit closer together.
///
/// It also turns the whole sound back up by half of what it takes off a
/// full scale peak (`makeupDB`), the way Final Cut's Auto gain does. A
/// compressor that only turns things down leaves the voice quieter than
/// before you put it on, which reads as the effect doing the wrong thing;
/// half keeps a full scale peak under where it was, so nothing clips.
public struct SoundCompressor: Hashable, Codable, Sendable {

    /// Where turning down starts, in decibels under full scale.
    public var thresholdDB: Double {
        didSet { thresholdDB = SoundEQ.held(thresholdDB, in: Self.thresholdRangeDB, else: -18) }
    }
    /// How much a sound over the threshold is turned down: at three, three
    /// decibels over comes out one over.
    public var ratio: Double {
        didSet { ratio = SoundEQ.held(ratio, in: Self.ratioRange, else: 3) }
    }

    public static let thresholdRangeDB: ClosedRange<Double> = -60...0
    public static let ratioRange: ClosedRange<Double> = 1...20
    /// How fast it turns down and lets go: quick enough to catch a word,
    /// slow enough not to ride the waveform and buzz.
    public static let attackMS: Double = 10
    public static let releaseMS: Double = 150

    /// What the plus puts on: a voice evened out without sounding squashed.
    public static let standard = SoundCompressor(thresholdDB: -18, ratio: 3)

    public init(thresholdDB: Double, ratio: Double) {
        self.thresholdDB = SoundEQ.held(thresholdDB, in: Self.thresholdRangeDB, else: -18)
        self.ratio = SoundEQ.held(ratio, in: Self.ratioRange, else: 3)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(thresholdDB: try c.decodeIfPresent(Double.self, forKey: .thresholdDB) ?? -18,
                  ratio: try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 3)
    }

    /// Half of what a full scale peak loses.
    public var makeupDB: Double { -thresholdDB * (1 - 1 / ratio) / 2 }

    /// The level that comes out for a steady level going in, make-up
    /// included.
    public func outputDB(forInputDB input: Double) -> Double {
        let over = input - thresholdDB
        let squeezed = over > 0 ? thresholdDB + over / ratio : input
        return squeezed + makeupDB
    }

    /// The mock's `.emeta`: the ratio, "3:1".
    public var reading: String { "\(Self.spell(ratio)):1" }

    /// What the panel prints for a ratio: whole where it is whole.
    public static func spell(_ ratio: Double) -> String {
        let tenths = (ratio * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
    }
}

// MARK: - The list on a level

extension AudioLevel {

    /// The effects on this sound, top down in the order it passes through
    /// them, switched off ones included.
    public var effectRows: [SoundEffectRow] {
        SoundEffectKind.processingOrder.compactMap { kind in
            guard let reading = reading(of: kind) else { return nil }
            let on = isEffectOn(kind)
            return SoundEffectRow(kind: kind, reading: on ? reading : "off", isOn: on)
        }
    }

    private func reading(of kind: SoundEffectKind) -> String? {
        switch kind {
        case .noiseReduction: noiseReduction?.title
        case .eq: eq?.reading
        case .compressor: compressor?.reading
        }
    }

    /// Whether this sound has the effect on its list, on or off.
    public func hasEffect(_ kind: SoundEffectKind) -> Bool { reading(of: kind) != nil }

    /// Whether the effect is on the list AND heard.
    public func isEffectOn(_ kind: SoundEffectKind) -> Bool {
        hasEffect(kind) && !effectsOff.contains(kind)
    }

    /// What is heard: each effect where it is on, nil where it is off or
    /// not there.
    public var activeNoiseReduction: NoiseReduction? { isEffectOn(.noiseReduction) ? noiseReduction : nil }
    public var activeEQ: SoundEQ? { isEffectOn(.eq) ? eq : nil }
    public var activeCompressor: SoundCompressor? { isEffectOn(.compressor) ? compressor : nil }

    /// Whether the add menu offers this: not already on the list.
    public func canAddEffect(_ kind: SoundEffectKind) -> Bool {
        kind.isBuilt && !hasEffect(kind)
    }

    /// Put an effect on, at its standard settings: the strength Normalize's
    /// Clean noise uses, the mock's low cut at 80, a gentle 3:1. False where
    /// nothing changed.
    @discardableResult
    public mutating func addEffect(_ kind: SoundEffectKind) -> Bool {
        guard canAddEffect(kind) else { return false }
        switch kind {
        case .noiseReduction: noiseReduction = .standard
        case .eq: eq = .standard
        case .compressor: compressor = .standard
        }
        effectsOff.remove(kind)
        return true
    }

    /// Take an effect off the list, its switch with it. False where it was
    /// not on the list.
    @discardableResult
    public mutating func removeEffect(_ kind: SoundEffectKind) -> Bool {
        guard hasEffect(kind) else { return false }
        switch kind {
        case .noiseReduction: noiseReduction = nil
        case .eq: eq = nil
        case .compressor: compressor = nil
        }
        effectsOff.remove(kind)
        return true
    }

    /// The row's switch: stop hearing the effect and keep its settings, or
    /// hear it again. False where nothing changed.
    @discardableResult
    public mutating func setEffect(_ kind: SoundEffectKind, on: Bool) -> Bool {
        guard hasEffect(kind), isEffectOn(kind) != on else { return false }
        if on { effectsOff.remove(kind) } else { effectsOff.insert(kind) }
        return true
    }
}
