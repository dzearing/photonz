import Foundation

/// Where see-through paint is mixed into what is under it.
///
/// A shadow, a layer at half opacity, a soft edge: each is a colour laid over
/// another at some fraction, and the fraction can be applied to two different
/// sets of numbers. Mixed in LIGHT, the stored sRGB numbers are turned into the
/// light they stand for first, which is Core Image's own default and what
/// Photonz always did: half black over white leaves half the light, stored as
/// 188. Mixed in the STORED numbers, which is what a browser, CSS, Figma and
/// every SVG reader do, the same half black over white is 128.
///
/// A file can only ask a reader for the second, so a canvas mixing in light
/// drew every shadow lighter than the file it exported
/// (`docs/design/svg-export.md`, "Where see-through paint is mixed").
public enum CompositingSpace: String, Codable, Sendable, CaseIterable {
    /// In light. What Current draws.
    case linearLight
    /// In the numbers the colour was written in, the way the web draws.
    case sRGB

    /// What nothing asked for means: Photonz as people have it today.
    public static let standard: CompositingSpace = .linearLight

    /// One stored sRGB channel, 0…1, as the value that gets mixed.
    public func working(_ c: Double) -> Double {
        switch self {
        case .sRGB: return c
        case .linearLight: return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
    }

    /// A mixed value back into the stored sRGB channel it comes out as.
    public func encoded(_ w: Double) -> Double {
        switch self {
        case .sRGB: return w
        case .linearLight:
            return w <= 0.0031308 ? w * 12.92 : 1.055 * pow(max(w, 0), 1 / 2.4) - 0.055
        }
    }

    /// How fast the stored number moves when the mixed value does, at `w`:
    /// what turns an error worked out in working units into levels a person
    /// would see.
    public func slope(atWorking w: Double) -> Double {
        switch self {
        case .sRGB: return 1
        case .linearLight:
            return w <= 0.0031308 ? 12.92 : (1.055 / 2.4) * pow(max(w, 1e-6), 1 / 2.4 - 1)
        }
    }
}

extension CompositingSpace {
    /// The space a release's switches ask for: the way a browser mixes when
    /// `next-web-compositing` is on, light otherwise. Current has no such
    /// switch, so it always mixes in light.
    public static func chosen(by settings: FeatureFlagSettings) -> CompositingSpace {
        settings.isEnabled(FeatureCatalog.webCompositingFlag) ? .sRGB : .linearLight
    }
}
