import Foundation

// The Effects list on a picked sound (`pages/video-audio.html`, `#gEffects`,
// and the plus on its header, `#efxMenu`).
//
// The mock's add menu offers EQ, Compressor and Noise reduction. Noise
// reduction is the one with sound behind it today, and it is not a new
// setting: it is `AudioLevel.noiseReduction`, the very value Normalize's Clean
// noise writes and the segment's Remove Noise Cleaning clears. So the list is
// a way of reading and writing what the level already holds, and every route
// to the cleaning stays one setting.

/// One kind of thing a sound's Effects list can hold, in the add menu's order.
public enum SoundEffectKind: String, CaseIterable, Sendable, Identifiable {
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

    /// Whether the app can put this on a sound yet. EQ and Compressor are on
    /// the mock's menu with no sound processing behind them so far, so they
    /// are listed and cannot be picked.
    public var isBuilt: Bool { self == .noiseReduction }
}

/// One row of the list: what it is and the value at its end.
public struct SoundEffectRow: Hashable, Sendable, Identifiable {
    public let kind: SoundEffectKind
    /// The mock's `.emeta`: the strength for Noise reduction.
    public let reading: String

    public var id: String { kind.rawValue }

    public init(kind: SoundEffectKind, reading: String) {
        self.kind = kind
        self.reading = reading
    }
}

extension AudioLevel {

    /// The effects on this sound, top down.
    public var effectRows: [SoundEffectRow] {
        var rows: [SoundEffectRow] = []
        if let noiseReduction {
            rows.append(SoundEffectRow(kind: .noiseReduction, reading: noiseReduction.title))
        }
        return rows
    }

    /// Whether the add menu offers this: built, and not already on.
    public func canAddEffect(_ kind: SoundEffectKind) -> Bool {
        kind.isBuilt && !effectRows.contains { $0.kind == kind }
    }

    /// Put an effect on, at the strength Normalize's Clean noise uses. False
    /// where nothing changed.
    @discardableResult
    public mutating func addEffect(_ kind: SoundEffectKind) -> Bool {
        guard canAddEffect(kind) else { return false }
        switch kind {
        case .noiseReduction: noiseReduction = .standard
        case .eq, .compressor: return false
        }
        return true
    }

    /// Take an effect off. False where it was not on.
    @discardableResult
    public mutating func removeEffect(_ kind: SoundEffectKind) -> Bool {
        switch kind {
        case .noiseReduction:
            guard noiseReduction != nil else { return false }
            noiseReduction = nil
            return true
        case .eq, .compressor:
            return false
        }
    }
}
