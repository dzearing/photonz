import Foundation

/// Whether what a field shows is what a walk's `expect` step claimed.
///
/// Words are compared as words, ignoring case. A claim ending in `±<margin>`
/// ("-9.3 dB ±0.5") compares the number instead: the reading has to carry the
/// same unit and sit within the margin. A reading set by a drag a few points
/// long lands wherever inside a pixel the drag let go, so the exact words can
/// differ between two runs of the same walk while the drag did exactly what
/// it should.
public enum PlaytestReading {

    public static func matches(showing: String, claimed: String) -> Bool {
        let showing = showing.trimmingCharacters(in: .whitespaces)
        let claimed = claimed.trimmingCharacters(in: .whitespaces)
        guard let plusMinus = claimed.range(of: "±") else {
            return showing.caseInsensitiveCompare(claimed) == .orderedSame
        }
        let wanted = String(claimed[..<plusMinus.lowerBound])
        guard let margin = Double(claimed[plusMinus.upperBound...].trimmingCharacters(in: .whitespaces)),
              let target = number(in: wanted), let shown = number(in: showing),
              target.unit.caseInsensitiveCompare(shown.unit) == .orderedSame
        else { return false }
        return abs(target.value - shown.value) <= margin + 1e-9
    }

    /// The leading number of a reading and whatever follows it, the unit.
    private static func number(in text: String) -> (value: Double, unit: String)? {
        let text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{2212}", with: "-")
        let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
        guard let value = Double(digits) else { return nil }
        return (value, text.dropFirst(digits.count).trimmingCharacters(in: .whitespaces))
    }
}
