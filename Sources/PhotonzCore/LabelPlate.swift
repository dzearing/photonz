import CoreGraphics
import Foundation

/// The plate a label sits on when it has to be read over a picture nobody
/// chose.
///
/// This is the app's one answer to that problem and it is older than this
/// file: the measure readout and the arrow caption have always been the same
/// capsule — a solid plate in the owning object's own colour, darkened until
/// white text reads on it, with white text on it (`PillRasterizer`,
/// `MeasureRoleColors.sizeDefault`: "red ink, solid darker-red chip, white
/// numbers"). The rule lived inside `AnnotationContent.captionChipColor`; it is
/// here now so the canvas name chips can be the same treatment rather than a
/// second one invented beside it.
///
/// **The legibility comes from the plate, not from a cleverer ink.** A label
/// hanging over a screenshot cannot know what is under it, so no choice of text
/// colour is safe; an opaque plate makes the question go away and the only
/// contrast left to get right is the one between the plate and its own words,
/// which is fixed and testable. See `LabelPlateTests`.
public enum LabelPlate {

    /// The lightest a plate gets: dark enough that white text reads on it.
    /// The shipped red pair (#8C201A) sits just under this.
    public static let maximumLuminance: Double = 0.24

    /// How much of its own colour a plate keeps before the cap is applied.
    /// Enough that a red caliper's chip is recognisably red and a component's
    /// chip is recognisably violet.
    public static let toneScale: Double = 0.55

    /// The words on a plate. One colour, because the plate is always dark.
    public static let inkHex = "#FFFFFF"

    /// The plate for something painted `color`: its own tone taken down until
    /// white sits on it.
    ///
    /// Light inks (white, a yellow accent) keep darkening rather than being
    /// refused, so the rule has no colour it cannot answer for.
    public static func tone(from color: RGBA) -> RGBA {
        var tone = RGBA(r: color.r * toneScale, g: color.g * toneScale, b: color.b * toneScale)
        let luminance = tone.relativeLuminance
        guard luminance > maximumLuminance else { return tone }
        let k = maximumLuminance / luminance
        tone = RGBA(r: tone.r * k, g: tone.g * k, b: tone.b * k)
        return tone
    }

    /// The same answer for a hex string, for the places that only hold one.
    /// An unreadable hex falls back to the plate for black, which is a plate.
    public static func toneHex(from hex: String) -> String {
        tone(from: RGBA(hex: hex) ?? RGBA(r: 0, g: 0, b: 0)).hexString
    }
}

/// The colour the app spends on "component", in one place both the pure model
/// and the drawing code can read.
///
/// A fixed colour, NOT the theme accent: the canvas mark sits on top of
/// whatever picture is open, and the accent is already spoken for by selection.
/// It is `--comp` from the design system's tokens
/// (`docs/design/mocks/shared/components/tokens.css`), the same violet in both
/// themes.
public enum ComponentPaint {
    public static let violetHex = "#9A5CFF"
}

/// The colour the app spends on "screen": a plain grey, because a screen has
/// no colour of its own.
///
/// A component's chip is violet, so the chip says which kind of thing it names
/// before you read a word of it. A screen is just a screen, so its chip is the
/// quietest plate the rule allows: `LabelPlate.tone` takes any grey lighter
/// than about #6F6F6F down to exactly `LabelPlate.maximumLuminance`, which is
/// the lightest a plate ever gets and still holds white text. That is
/// deliberate. A canvas can hold a dozen screens, and a dozen near-black pills
/// would be a heavier canvas than the names are worth.
public enum ScreenPaint {
    public static let greyHex = "#8A8A8E"
}
