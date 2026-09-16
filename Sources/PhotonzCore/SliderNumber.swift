import CoreGraphics
import Foundation

/// The number a slider's readout is typed as.
///
/// A slider's own value and the number a person types beside it are not always
/// the same thing. Opacity slides from 0 to 1 and is typed as 0 to 100,
/// because nobody thinks of a shadow as being 0.35 opaque; an arrowhead is a
/// multiple rather than a measurement, so it wears a sign in front instead of
/// a unit word behind and keeps a decimal place the lengths do not.
///
/// One of these is all a slider row has to say for its readout to become a box
/// you can type in (`SliderReadout`). Everything else — what Return does, what
/// an arrow key does, what the word Mixed looks like — is `NumberBox`, and is
/// the same wherever a number is typed into a panel.
public struct SliderNumber: Hashable, Sendable {
    /// The mark after the box, where the number means nothing without one.
    public let suffix: String?
    /// The mark BEFORE it, for a number that is a multiple rather than a
    /// measurement.
    public let leading: String?
    /// What the box shows, over what the slider holds.
    public let scale: CGFloat
    /// How many places the box spells. Nought for the numbers counted in whole
    /// units, which is nearly all of them.
    public let decimals: Int

    public init(suffix: String? = nil, leading: String? = nil,
                scale: CGFloat = 1, decimals: Int = 0) {
        self.suffix = suffix
        self.leading = leading
        self.scale = scale
        self.decimals = decimals
    }

    /// Whether the box counts in whole units, which is what decides how a
    /// typed fraction and an arrow key land.
    public var wholeNumbers: Bool { decimals == 0 }

    /// The slider's number, as the box shows it.
    public func shown(_ sliderValue: CGFloat) -> CGFloat { sliderValue * scale }

    /// The box's number, as the slider holds it.
    public func slid(_ shown: CGFloat) -> CGFloat { shown / scale }

    /// How this panel spells the number in the box.
    public func spell(_ shown: CGFloat) -> String {
        guard decimals > 0 else { return String(Int(shown.rounded())) }
        return String(format: "%.\(decimals)f", Double(shown))
    }

    /// The number as a PERSON reads it, mark and unit word and all.
    ///
    /// The box holds the digits and the unit is drawn beside it, which is how
    /// every other typed number in the panel is built; this puts the two back
    /// together for anything that has to report what is on screen rather than
    /// what is in the box.
    public func readout(_ shown: CGFloat) -> String {
        (leading ?? "") + spell(shown) + (suffix.map { " " + $0 } ?? "")
    }

    /// A length, in the app's one unit word.
    public static var points: SliderNumber { SliderNumber(suffix: DocumentUnit.word) }
    /// A strength: a slider running 0 to 1, typed as a percentage.
    public static let percent = SliderNumber(suffix: "%", scale: 100)
    /// A turn.
    public static let degrees = SliderNumber(suffix: "\u{00B0}")
    /// A multiple, to one decimal place.
    public static let times = SliderNumber(leading: "\u{00D7}", decimals: 1)
}
