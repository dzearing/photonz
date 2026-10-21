import CoreGraphics
import Foundation

// Colour for illustrations: values measured as a painter squints (CIE
// lightness, 0 black to 1 white), colours re-lit to the value the value pass
// planned, and the palettes each time of day is painted in.

enum IllustrationColor {

    /// Lightness 0 to 1, the way a value study reads it.
    static func value(_ hex: String) -> CGFloat {
        guard let rgba = RGBA(hex: hex) else { return 0 }
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let y = 0.2126 * linear(rgba.r) + 0.7152 * linear(rgba.g) + 0.0722 * linear(rgba.b)
        let l = y > 0.008856 ? 116 * pow(y, 1.0 / 3.0) - 16 : 903.3 * y
        return CGFloat(min(max(l / 100, 0), 1))
    }

    /// The grey that reads at `value`.
    static func grey(_ value: CGFloat) -> String {
        let l = Double(min(max(value, 0), 1)) * 100
        let y = l > 8 ? pow((l + 16) / 116, 3) : l / 903.3
        let srgb = y <= 0.0031308 ? 12.92 * y : 1.055 * pow(y, 1 / 2.4) - 0.055
        let channel = min(max(srgb, 0), 1)
        return RGBA(r: channel, g: channel, b: channel).hexString
    }

    static func mix(_ a: String, _ b: String, _ t: CGFloat) -> String {
        guard let x = RGBA(hex: a), let y = RGBA(hex: b) else { return a }
        let u = Double(min(max(t, 0), 1))
        return RGBA(r: x.r + (y.r - x.r) * u, g: x.g + (y.g - x.g) * u, b: x.b + (y.b - x.b) * u).hexString
    }

    /// `hex` lightened toward white or darkened toward black until it reads
    /// at `value`, keeping its hue.
    static func relit(_ hex: String, to target: CGFloat) -> String {
        let now = value(hex)
        if abs(now - target) < 0.005 { return hex }
        let toward = now < target ? "#FFFFFF" : "#000000"
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<24 {
            let middle = (low + high) / 2
            let tried = value(mix(hex, toward, middle))
            if (now < target) == (tried < target) { low = middle } else { high = middle }
        }
        return mix(hex, toward, (low + high) / 2)
    }

    /// `hex` at an alpha, as `#RRGGBBAA`.
    static func alpha(_ hex: String, _ amount: CGFloat) -> String {
        let byte = Int((min(max(amount, 0), 1) * 255).rounded())
        return String(hex.prefix(7)) + String(format: "%02X", byte)
    }
}

/// What a time of day is painted in.
struct IllustrationPalette {
    /// Top of the sky to the horizon.
    var sky: [GradientStop]
    /// The sun or moon's face and the glow round it.
    var light: String
    var glow: String
    /// Land at the back and at the front; between is a mix, re-lit to the plan.
    var far: String
    var near: String
    /// Laid over a form's side away from the light.
    var shadow: String
    /// The rim the light catches.
    var highlight: String
    var snow: String
    /// Lamps and windows.
    var lamp: String
    /// The sea or a lake, top to bottom.
    var water: [GradientStop]
    /// Hills and meadows lean this way.
    var grass: String
    var cloud: String
    /// The haze that settles in valleys and between rows of trees.
    var mist: String
    /// The paper line art and silhouettes are drawn on, and their ink.
    static let paper = "#FFFFFF"
    static let ink = "#1E2026"

    /// Planned lightness for the far and near planes.
    var farValue: CGFloat
    var nearValue: CGFloat

    static func `for`(_ time: IllustrationTime) -> IllustrationPalette {
        func stops(_ pairs: [(String, Double)]) -> [GradientStop] { pairs.map { GradientStop(hex: $0.0, position: $0.1) } }
        switch time {
        case .day:
            return IllustrationPalette(
                sky: stops([("#4F9BE0", 0), ("#8CC3EE", 0.55), ("#DCEFF8", 1)]),
                light: "#FFF4C2", glow: "#FFF8DD", far: "#9DB8D6", near: "#23443F",
                shadow: "#1D3157", highlight: "#FFFFFF", snow: "#F7FAFD", lamp: "#FFD35A",
                water: stops([("#9CCBE8", 0), ("#4C86B5", 1)]), grass: "#4E8A4F", cloud: "#FFFFFF", mist: "#D3E6F3",
                farValue: 0.74, nearValue: 0.24)
        case .golden:
            return IllustrationPalette(
                sky: stops([("#33427F", 0), ("#9A5B8E", 0.38), ("#EE8D63", 0.72), ("#FFD48C", 1)]),
                light: "#FFF3D1", glow: "#FFD9A0", far: "#A69BCB", near: "#2C1D40",
                shadow: "#2B1446", highlight: "#FFD7A6", snow: "#FFE9DC", lamp: "#FFD27A",
                water: stops([("#E9A27E", 0), ("#6E4A79", 0.55), ("#2C2346", 1)]), grass: "#6B6A55", cloud: "#F7B3A0", mist: "#D9A0B4",
                farValue: 0.68, nearValue: 0.12)
        case .dusk:
            return IllustrationPalette(
                sky: stops([("#1C2452", 0), ("#4E3F80", 0.42), ("#C2708A", 0.76), ("#F5A97A", 1)]),
                light: "#FFD9A6", glow: "#F7A07A", far: "#8C7EB4", near: "#121530",
                shadow: "#0C0E2A", highlight: "#F7C4A6", snow: "#E9E2F4", lamp: "#FFD98A",
                water: stops([("#C98C97", 0), ("#3D3A6E", 0.5), ("#15183A", 1)]), grass: "#48566A", cloud: "#C98AA5", mist: "#B68DB2",
                farValue: 0.58, nearValue: 0.11)
        case .night:
            return IllustrationPalette(
                sky: stops([("#050A20", 0), ("#111C45", 0.55), ("#34477E", 1)]),
                light: "#F4F1DE", glow: "#9DB0E6", far: "#3B4B7C", near: "#060A1A",
                shadow: "#02040F", highlight: "#BFCDF2", snow: "#CBD5EF", lamp: "#FFD37A",
                water: stops([("#22325F", 0), ("#0A1230", 1)]), grass: "#1B2742", cloud: "#2E3D6A", mist: "#34477E",
                farValue: 0.22, nearValue: 0.04)
        }
    }

    /// The sky's lightest point, at the horizon.
    var horizonValue: CGFloat { IllustrationColor.value(sky.last?.hex ?? "#FFFFFF") }
}
