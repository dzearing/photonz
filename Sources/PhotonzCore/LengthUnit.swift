import CoreGraphics
import Foundation

/// What a length on this picture is read and typed in.
///
/// Nearly every picture counts in points, the app's one unit word. A picture
/// that is 24 units across at 512 points does not: the tag above a shape, the
/// keylines and the file it writes all say units, so a panel row saying points
/// beside them turned a typed 1.75 into a hairline (2026-11-07). The document
/// goes on holding points, as every layer does. This is only what a number
/// means where a person meets it.
public struct LengthUnit: Hashable, Sendable {

    /// How many canvas points one of this unit is.
    public let points: CGFloat

    public init(points: CGFloat) {
        self.points = points.isFinite && points > 0 ? points : 1
    }

    /// The ordinary unit.
    public static let point = LengthUnit(points: 1)

    public var isPoint: Bool { points == 1 }

    /// The word after the number. An icon's units go without one, as its tag
    /// and the icon mock's Stroke section do.
    public var word: String? { isPoint ? DocumentUnit.word : nil }

    /// A stored length as a person reads it. Two places in units, the most an
    /// icon's numbers ever need; points are handed back exactly as they are,
    /// because each row has its own rule for rounding them.
    public func reading(_ stored: CGFloat) -> CGFloat {
        isPoint ? stored : Self.hundredths(stored / points)
    }

    /// A number a person typed, as the length to store.
    public func stored(_ number: CGFloat) -> CGFloat { number * points }

    /// How a number in this unit is written: whole points, or units to two
    /// places with the zeros run out.
    public func spell(_ number: CGFloat) -> String {
        isPoint ? String(Int(number.rounded())) : Self.spellUnits(number)
    }

    /// A number in units, to two places with the zeros run out.
    public static func spellUnits(_ number: CGFloat) -> String { fractions.spell(number) }

    /// How a length row's number is typed.
    public var length: SliderNumber { isPoint ? .points : number }

    /// How a line's width is typed.
    public var lineWidth: SliderNumber { isPoint ? .lineWidth : number }

    /// Where Width runs, in stored points. The ordinary range tops out at 40
    /// points, under two units here, which would hold a typed 2 at 1.88.
    public var strokeWidthRange: ClosedRange<CGFloat> {
        guard !isPoint else { return AnnotationStyles.strokeWidthRange }
        return Self.leastStroke * points...Self.mostStroke * points
    }

    /// Where a length row with these ends runs on this picture, in stored
    /// points. Those ends were chosen in points, and 40 of them is under two
    /// units, so a row left alone would hold a 2 unit edge at 1.88 and read
    /// differently from Width above it.
    public func reach(of range: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        guard !isPoint else { return range }
        return range.lowerBound...max(range.upperBound, strokeWidthRange.upperBound)
    }

    /// A stored length a pull on a knob landed on: whole points, or quarters of
    /// a unit, which is as finely as a knob can aim at an icon's weights.
    public func pulled(_ stored: CGFloat) -> CGFloat {
        isPoint ? stored.rounded() : (stored / points * 4).rounded() / 4 * points
    }

    /// A stored length a typed number landed on: two places in this unit, so
    /// 1.75 goes in as 1.75 units and never as a rounded number of points.
    public func typedLength(_ stored: CGFloat) -> CGFloat {
        Self.hundredths(stored / points) * points
    }

    private var number: SliderNumber {
        SliderNumber(scale: 1 / points, decimals: 2, dropsTrailingZeros: true)
    }

    private static let fractions = SliderNumber(decimals: 2, dropsTrailingZeros: true)
    private static let leastStroke: CGFloat = 0.25
    private static let mostStroke: CGFloat = 12

    private static func hundredths(_ value: CGFloat) -> CGFloat { (value * 100).rounded() / 100 }
}

extension PhotonzDocument {

    /// What this picture's lengths read in.
    public var lengthUnit: LengthUnit {
        pictureIconUnit.map(LengthUnit.init(points:)) ?? .point
    }
}
