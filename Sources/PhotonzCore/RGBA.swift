import Foundation

/// sRGB color components in 0...1, parsed from the hex strings stored in the
/// document model (`#RRGGBB` or `#RRGGBBAA`, leading `#` optional).
public struct RGBA: Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16) else { return nil }

        if digits.count == 8 {
            self.init(r: Double((value >> 24) & 0xFF) / 255,
                      g: Double((value >> 16) & 0xFF) / 255,
                      b: Double((value >> 8) & 0xFF) / 255,
                      a: Double(value & 0xFF) / 255)
        } else {
            self.init(r: Double((value >> 16) & 0xFF) / 255,
                      g: Double((value >> 8) & 0xFF) / 255,
                      b: Double(value & 0xFF) / 255)
        }
    }

    /// Perceived lightness in 0...1 (Rec. 709 weights on the gamma-encoded
    /// components — close enough for light-vs-dark decisions).
    public var relativeLuminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
