import CoreGraphics
import Foundation

/// The arithmetic behind the one color picker: the two ways a color is
/// described to a person, the rows of colors derived from the one they are on,
/// what they can type into the field, and whether what they picked can be read.
///
/// It lives here, away from any view, because every one of these is a rule
/// rather than a layout: nine shades of a blue are the same nine shades whoever
/// is drawing them, and "does this pass" has one right answer.

// MARK: - The two descriptions of a color

/// Hue, saturation and lightness — the numbers a person types, and what CSS
/// writes. Hue is degrees (0..<360), the other two 0...1.
public struct HSL: Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var lightness: Double

    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }
}

/// Hue, saturation and value — what the picker's square really is: across is
/// saturation, down is value.
public struct HSV: Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var value: Double

    public init(hue: Double, saturation: Double, value: Double) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }
}

extension RGBA {

    public var hsl: HSL {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        guard d > 0 else { return HSL(hue: 0, saturation: 0, lightness: l) }
        let s = d / (1 - abs(2 * l - 1))
        return HSL(hue: Self.hueDegrees(r: r, g: g, b: b, mx: mx, d: d),
                   saturation: min(s, 1), lightness: l)
    }

    public var hsv: HSV {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return HSV(hue: 0, saturation: 0, value: mx) }
        return HSV(hue: Self.hueDegrees(r: r, g: g, b: b, mx: mx, d: d),
                   saturation: d / mx, value: mx)
    }

    public init(hsl: HSL, alpha: Double = 1) {
        let s = min(max(hsl.saturation, 0), 1)
        let l = min(max(hsl.lightness, 0), 1)
        let c = (1 - abs(2 * l - 1)) * s
        let (r, g, b) = RGBA.wheel(hue: hsl.hue, chroma: c, base: l - c / 2)
        self.init(r: r, g: g, b: b, a: alpha)
    }

    public init(hsv: HSV, alpha: Double = 1) {
        let s = min(max(hsv.saturation, 0), 1)
        let v = min(max(hsv.value, 0), 1)
        let c = v * s
        let (r, g, b) = RGBA.wheel(hue: hsv.hue, chroma: c, base: v - c)
        self.init(r: r, g: g, b: b, a: alpha)
    }

    /// `#RRGGBB` while the color is opaque, `#RRGGBBAA` once it is not, so a
    /// document that never used transparency keeps writing the strings it
    /// always wrote.
    public var hexStringWithAlpha: String {
        guard a < 1 else { return hexString }
        let byte = Int((min(max(a, 0), 1) * 255).rounded())
        return hexString + String(format: "%02X", byte)
    }

    /// WCAG relative luminance, on light-linear components. Distinct from
    /// `relativeLuminance`, which weights the gamma-encoded ones and is only
    /// ever asked whether a color is light or dark.
    public var wcagLuminance: Double {
        func linear(_ c: Double) -> Double {
            let x = min(max(c, 0), 1)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// This color laid over another one, which is what a translucent color
    /// actually looks like on screen.
    public func composited(over backdrop: RGBA) -> RGBA {
        let alpha = min(max(a, 0), 1)
        return RGBA(r: r * alpha + backdrop.r * (1 - alpha),
                    g: g * alpha + backdrop.g * (1 - alpha),
                    b: b * alpha + backdrop.b * (1 - alpha),
                    a: 1)
    }

    private static func hueDegrees(r: Double, g: Double, b: Double,
                                   mx: Double, d: Double) -> Double {
        let h: Double
        if mx == r { h = 60 * (((g - b) / d).truncatingRemainder(dividingBy: 6)) }
        else if mx == g { h = 60 * ((b - r) / d + 2) }
        else { h = 60 * ((r - g) / d + 4) }
        return (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The shared six-sector walk both HSL and HSV take round the color wheel.
    private static func wheel(hue: Double, chroma: Double,
                              base: Double) -> (Double, Double, Double) {
        let h = ((hue.truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360)) / 60
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let parts: (Double, Double, Double)
        switch Int(h) {
        case 0: parts = (chroma, x, 0)
        case 1: parts = (x, chroma, 0)
        case 2: parts = (0, chroma, x)
        case 3: parts = (0, x, chroma)
        case 4: parts = (x, 0, chroma)
        default: parts = (chroma, 0, x)
        }
        return (parts.0 + base, parts.1 + base, parts.2 + base)
    }
}

// MARK: - What the picker is holding

/// The color the picker is on, kept as hue, saturation, value and opacity
/// rather than as red, green and blue.
///
/// It is kept this way for one reason: dragging to the bottom of the square
/// makes black, and black has no hue to read back. Holding the hue separately
/// is what lets the square be dragged back up to the color you started from
/// instead of to a shade of red.
public struct PickerColor: Hashable, Sendable {
    /// 0..<360, kept even when the color itself cannot express it.
    public var hue: Double
    /// HSV saturation, 0...1: across the square.
    public var saturation: Double
    /// HSV value, 0...1: up the square.
    public var value: Double
    /// 0...1.
    public var alpha: Double

    public init(hue: Double = 0, saturation: Double = 1,
                value: Double = 1, alpha: Double = 1) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.alpha = alpha
    }

    public init(_ rgba: RGBA) {
        let hsv = rgba.hsv
        self.init(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value, alpha: rgba.a)
    }

    /// The color a hex string names, or nil when it names nothing.
    public init?(hex: String) {
        guard let rgba = RGBA(hex: hex) else { return nil }
        self.init(rgba)
    }

    public var rgba: RGBA { RGBA(hsv: HSV(hue: hue, saturation: saturation, value: value), alpha: alpha) }
    public var hex: String { rgba.hexString }
    public var hexWithAlpha: String { rgba.hexStringWithAlpha }
    public var hsl: HSL { rgba.hsl }
    public var isOpaque: Bool { alpha >= 1 }

    /// The number a channel's field shows, already rounded to what the field
    /// accepts, so the readout and the value can never disagree by a digit.
    public func value(of channel: ColorChannel) -> Double {
        let color = rgba
        switch channel {
        case .hue: return (hsl.saturation == 0 ? hue : hsl.hue).rounded()
        case .saturation: return (hsl.saturation * 100).rounded()
        case .lightness: return (hsl.lightness * 100).rounded()
        case .red: return (color.r * 255).rounded()
        case .green: return (color.g * 255).rounded()
        case .blue: return (color.b * 255).rounded()
        case .alpha: return (alpha * 100).rounded()
        }
    }

    /// This color with one channel moved and everything else held where it is.
    /// Out-of-range numbers clamp rather than wrap, because a field you typed
    /// 400 into meant the top, not 40.
    public func setting(_ channel: ColorChannel, to number: Double) -> PickerColor {
        let n = min(max(number, 0), channel.maximum)
        switch channel {
        case .alpha:
            var moved = self
            moved.alpha = n / 100
            return moved
        case .red, .green, .blue:
            var color = rgba
            switch channel {
            case .red: color.r = n / 255
            case .green: color.g = n / 255
            default: color.b = n / 255
            }
            return keepingHue(color)
        case .hue, .saturation, .lightness:
            let current = hsl
            let moved = HSL(hue: channel == .hue ? n : current.hue,
                            saturation: channel == .saturation ? n / 100 : current.saturation,
                            lightness: channel == .lightness ? n / 100 : current.lightness)
            var next = PickerColor(RGBA(hsl: moved, alpha: alpha))
            // A shade with no color left in it still remembers which hue it was,
            // so sliding lightness back up returns the color rather than a gray.
            if moved.saturation == 0 || moved.lightness == 0 || moved.lightness == 1 {
                next.hue = moved.hue
            }
            return next
        }
    }

    /// Adopts a color outright (a swatch, a sample, a pasted string) while
    /// holding on to the hue when the new color has none of its own.
    public func adopting(_ color: RGBA) -> PickerColor {
        keepingHue(color)
    }

    private func keepingHue(_ color: RGBA) -> PickerColor {
        var next = PickerColor(color)
        if color.hsv.saturation == 0 || color.hsv.value == 0 { next.hue = hue }
        next.alpha = color.a
        return next
    }
}

// MARK: - Channels and formats

/// One number the picker can slide. Each is a channel of a description a person
/// already thinks in, never a second way to show one that is already there.
public enum ColorChannel: String, Hashable, Sendable, CaseIterable {
    case hue, saturation, lightness, red, green, blue, alpha

    /// The one letter beside the track.
    public var label: String {
        switch self {
        case .hue: return "H"
        case .saturation: return "S"
        case .lightness: return "L"
        case .red: return "R"
        case .green: return "G"
        case .blue: return "B"
        case .alpha: return "A"
        }
    }

    /// What the whole track means, for the tooltip and for voice over.
    public var title: String {
        switch self {
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .lightness: return "Lightness"
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .alpha: return "Opacity"
        }
    }

    public var maximum: Double {
        switch self {
        case .hue: return 360
        case .saturation, .lightness, .alpha: return 100
        case .red, .green, .blue: return 255
        }
    }

    public var unit: String {
        switch self {
        case .saturation, .lightness, .alpha: return "%"
        default: return ""
        }
    }
}

/// Which numbers the picker is showing. It picks WHICH channels you are
/// sliding, not a second way to see the same ones.
public enum ColorFormat: String, Hashable, Sendable, CaseIterable {
    case hsl, rgb, hex

    public var title: String {
        switch self {
        case .hsl: return "HSL"
        case .rgb: return "RGB"
        case .hex: return "HEX"
        }
    }

    /// Hex has no channels to slide, so it keeps the hue and opacity tracks
    /// and adds a field, which is also where a pasted color lands.
    public var channels: [ColorChannel] {
        switch self {
        case .hsl: return [.hue, .saturation, .lightness, .alpha]
        case .rgb: return [.red, .green, .blue, .alpha]
        case .hex: return [.hue, .alpha]
        }
    }
}

// MARK: - Typing a color

/// Reading the ways a color arrives as text. Paste is how a color usually
/// arrives, and it arrives in whatever the place it came from wrote.
public enum ColorText {

    /// `#7C4DFF`, `7c4dff`, `#F0C`, `#7C4DFF80`, `rgb(124, 77, 255)`,
    /// `rgba(124 77 255 / 50%)`, `hsl(258 100% 65%)`. Nil for anything else.
    public static func parse(_ text: String) -> RGBA? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("rgb") { return parseFunction(lower, name: "rgb", isHSL: false) }
        if lower.hasPrefix("hsl") { return parseFunction(lower, name: "hsl", isHSL: true) }
        return parseHex(trimmed)
    }

    private static func parseHex(_ text: String) -> RGBA? {
        var digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 || digits.count == 4 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        return RGBA(hex: digits)
    }

    private static func parseFunction(_ text: String, name: String, isHSL: Bool) -> RGBA? {
        // Both `rgb(…)` and `rgba(…)` are the same four numbers, and both
        // comma and space separated forms are written in the wild, so the
        // separators are all treated alike and the count decides the meaning.
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let head = text[text.startIndex..<open]
        guard head == name[...] || head == (name + "a")[...] else { return nil }
        let body = text[text.index(after: open)..<text.index(before: text.endIndex)]
        let fields = body.split(whereSeparator: { ",/ ".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard fields.count == 3 || fields.count == 4 else { return nil }
        var numbers: [Double] = []
        for field in fields {
            let isPercent = field.hasSuffix("%")
            let digits = isPercent ? String(field.dropLast()) : field
            guard let n = Double(digits) else { return nil }
            numbers.append(isPercent ? n / 100 : n)
        }
        // An alpha given as a bare number is already 0...1; as a percent it was
        // divided above, so both arrive the same way.
        let alpha = numbers.count == 4 ? min(max(numbers[3], 0), 1) : 1
        if isHSL {
            // Saturation and lightness are percentages whether or not the sign
            // was typed, which is what CSS means by `hsl(258 100% 65%)`.
            let s = numbers[1] > 1 ? numbers[1] / 100 : numbers[1]
            let l = numbers[2] > 1 ? numbers[2] / 100 : numbers[2]
            return RGBA(hsl: HSL(hue: numbers[0], saturation: s, lightness: l), alpha: alpha)
        }
        func channel(_ n: Double) -> Double { min(max(n <= 1 && n > 0 ? n * 255 : n, 0), 255) / 255 }
        return RGBA(r: channel(numbers[0]), g: channel(numbers[1]), b: channel(numbers[2]), a: alpha)
    }
}

// MARK: - The rows of colors derived from this one

/// Shades and relatives. Both are DERIVED, never authored, so they are right
/// for whatever color the picker is on and there is nothing to keep up to date.
public enum ColorRamp {

    /// The nine steps a shade ramp takes, light to dark. The same nine for any
    /// base, which is what makes "one step darker" mean the same thing twice.
    public static let shadeLightnesses: [Double] = [0.94, 0.86, 0.76, 0.65, 0.54, 0.44, 0.34, 0.24, 0.14]

    /// How far round the wheel a relative sits: the neighbours either side,
    /// then the thirds, then the opposite.
    public static let relatedHueOffsets: [Double] = [-60, -30, 30, 60, 120, 180]

    public static func shades(of color: RGBA) -> [String] {
        let hsl = color.hsl
        return shadeLightnesses.map {
            RGBA(hsl: HSL(hue: hsl.hue, saturation: hsl.saturation, lightness: $0)).hexString
        }
    }

    public static func related(to color: RGBA) -> [String] {
        let hsl = color.hsl
        return relatedHueOffsets.map {
            RGBA(hsl: HSL(hue: hsl.hue + $0, saturation: hsl.saturation, lightness: hsl.lightness)).hexString
        }
    }

    /// Which step of its own ramp a color is nearest, so the row can say where
    /// you are standing. Nil for a color with no lightness to compare.
    public static func nearestShadeIndex(of color: RGBA) -> Int? {
        let l = color.hsl.lightness
        return shadeLightnesses.indices.min { abs(shadeLightnesses[$0] - l) < abs(shadeLightnesses[$1] - l) }
    }
}

// MARK: - Can it be read

/// How far apart two colors are, and what the accessibility guidelines call
/// that distance.
public struct ContrastReading: Hashable, Sendable {

    public enum Grade: String, Hashable, Sendable {
        /// 7:1 and over: readable at any size.
        case aaa
        /// 4.5:1 and over: readable as body text.
        case aa
        /// 3:1 and over: readable only as large or heavy text.
        case aaLarge
        /// Under 3:1.
        case fail

        public var title: String {
            switch self {
            case .aaa: return "AAA"
            case .aa: return "AA"
            case .aaLarge: return "AA Large"
            case .fail: return "Fail"
            }
        }

        /// Whether text in this color can be read at all on that background.
        public var passes: Bool { self != .fail }
    }

    public let ratio: Double
    public let grade: Grade

    /// A translucent color is read as what it looks like over that background,
    /// because that is what is actually on the screen.
    public init(of color: RGBA, on background: RGBA) {
        let front = color.a < 1 ? color.composited(over: background) : color
        let a = front.wcagLuminance, b = background.wcagLuminance
        let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        self.ratio = ratio
        if ratio >= 7 { grade = .aaa }
        else if ratio >= 4.5 { grade = .aa }
        else if ratio >= 3 { grade = .aaLarge }
        else { grade = .fail }
    }

    public var passes: Bool { grade.passes }

    /// "4.5:1", the way the readout writes it.
    public var ratioText: String {
        String(format: "%.1f:1", (ratio * 10).rounded() / 10)
    }
}
