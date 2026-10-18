import Foundation

// A number that counts up to its value (task
// `animated-charts-you-can-drop-into-a-video`).
//
// A big number on an explainer video does not simply appear: it runs up from
// nought and settles on its value. **The value is the words themselves.** The
// text says "$1,240" or "+18%", and the count only says when: from which moment
// of the text's own clock, for how long, on which curve. At each moment drawn
// the number in the words is replaced by where the count has got to, written
// the way the words write it (the same prefix, thousands and decimals), so
// retyping the words retargets the count and nothing else needs to change.
// Like a reveal, the counting string is set only on the frame drawn at a
// moment; the document keeps the words as typed.

/// When a text's number counts up from nought to the value its words hold.
public struct TextCount: Hashable, Codable, Sendable {
    /// When it starts, on the clock the text's keys are read on.
    public var startMS: Int
    public var lengthMS: Int
    public var curve: EasingCurve

    public init(startMS: Int, lengthMS: Int, curve: EasingCurve = .easeOut) {
        self.startMS = startMS
        self.lengthMS = max(1, lengthMS)
        self.curve = curve
    }

    /// How far the count has got at `ms`, nought to one.
    public func progress(atMS ms: Int) -> Double {
        let t = min(max(Double(ms - startMS) / Double(max(1, lengthMS)), 0), 1)
        return t >= 1 ? 1 : curve.value(at: t)
    }

    /// `string` as drawn at `ms`: its number at the count's progress, or the
    /// words as they are where they hold no number.
    public func string(for string: String, atMS ms: Int) -> String {
        guard let number = CountedNumber(parsing: string) else { return string }
        return number.written(number.value * progress(atMS: ms))
    }
}

/// The first number in some words, and how they write it: what is before and
/// after it, whether it groups thousands and how many decimals it shows.
public struct CountedNumber: Hashable, Sendable {
    public var prefix: String
    public var value: Double
    public var decimals: Int
    public var groups: Bool
    public var suffix: String

    /// The first run of digits (with its sign, thousands commas and one
    /// decimal point), nil where there is none.
    public init?(parsing string: String) {
        let characters = Array(string)
        guard let first = characters.firstIndex(where: \.isNumber) else { return nil }
        var start = first
        var end = first
        var sawPoint = false
        var decimals = 0
        var groups = false
        var index = first
        while index < characters.count {
            let c = characters[index]
            if c.isNumber {
                if sawPoint { decimals += 1 }
                end = index
            } else if c == ",", !sawPoint, index + 1 < characters.count, characters[index + 1].isNumber {
                groups = true
            } else if c == ".", !sawPoint, index + 1 < characters.count, characters[index + 1].isNumber {
                sawPoint = true
            } else {
                break
            }
            index += 1
        }
        // A leading point ("0.5" written ".5") belongs to the number.
        if start > 0, characters[start - 1] == ".", !sawPoint {
            start -= 1
            decimals = end - first + 1
        }
        let digits = String(characters[start...end]).replacingOccurrences(of: ",", with: "")
        guard var value = Double(digits) else { return nil }
        var prefixEnd = start
        // A minus sign right before the digits is part of the value; a plus
        // stays in the words, so "+18%" counts up through "+9%".
        if prefixEnd > 0, characters[prefixEnd - 1] == "-" || characters[prefixEnd - 1] == "\u{2212}" {
            value = -value
            prefixEnd -= 1
        }
        prefix = String(characters[..<prefixEnd])
        suffix = end + 1 < characters.count ? String(characters[(end + 1)...]) : ""
        self.value = value
        self.decimals = decimals
        self.groups = groups
    }

    /// `value` written the way these words write their number.
    public func written(_ value: Double) -> String {
        prefix + ChartNumberFormat.digits(value, decimals: decimals, groups: groups) + suffix
    }
}

extension Layer {

    /// This text as drawn at `ms` of its own motion clock: its number where
    /// its count has got to. Everything else comes back as it was.
    func withTextCountShown(atMotionMS ms: Int) -> Layer {
        guard case .text(var text) = content, let count = text.count else { return self }
        text.string = count.string(for: text.string, atMS: ms)
        var shown = self
        shown.content = .text(text)
        return shown
    }
}
