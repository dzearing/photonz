import CoreGraphics
import Foundation

/// What the Tracking and Leading boxes say, and what a number typed into them
/// means. Both are percents of the type size, the way a design tool says them
/// (Figma's letter spacing and line height): Tracking -2.8 is the -0.028em of
/// an Apple headline, Leading 106 is its 1.06 line. Leading left empty is the
/// face's own spacing, which Photoshop calls Auto.
public enum TextSpacing {

    /// What Leading says when the words are in their face's own spacing.
    public static let automatic = "Auto"

    /// The Tracking box for a reading in em.
    public static func trackingShowing(_ reading: StyleReading<CGFloat>) -> NumberBox.Showing {
        if reading.isMixed { return .standIn(MixedValue.text) }
        guard let em = reading.value else { return .nothing }
        return .number(spell(em * 100))
    }

    /// The Leading box for a reading of line heights, nil being Auto.
    public static func leadingShowing(_ reading: StyleReading<CGFloat?>) -> NumberBox.Showing {
        if reading.isMixed { return .standIn(MixedValue.text) }
        guard let height = reading.value else { return .nothing }
        guard let multiple = height else { return .standIn(automatic) }
        return .number(spell(multiple * 100))
    }

    /// The letter spacing, in em, a percent typed into Tracking means.
    public static func tracking(percent: CGFloat) -> CGFloat { percent / 100 }

    /// The line height, as a multiple of the size, a percent typed into
    /// Leading means.
    public static func lineHeight(percent: CGFloat) -> CGFloat { percent / 100 }

    /// A percent with at most one place after the point and no trailing
    /// nought: -2.8, 106, 102.5.
    public static func spell(_ percent: CGFloat) -> String {
        let tenths = (percent * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 { return String(Int(tenths / 10)) }
        return String(format: "%.1f", tenths / 10)
    }
}
