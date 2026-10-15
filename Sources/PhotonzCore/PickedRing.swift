import CoreGraphics

/// The ring a picked thing wears on the canvas: one stroke of a colour, a
/// width, an opacity and maybe a dash, with an optional light casing drawn
/// under it.
///
/// Every mock draws a picked thing as ONE solid accent line
/// (`docs/design/mocks/shared/components/selection.css`: `.sel-ring` 1.5px,
/// `.mem-ring` 1px at 70% for each member of a multi-selection). The canvas
/// draws over arbitrary screenshots, though, and an accent line on a blue
/// screenshot vanishes, so a solid ring is cased in a faint white halo just
/// wider than itself: invisible on white, a hairline edge on blue and on dark,
/// and the line still reads as the mock's single stroke.
///
/// `solid: false` is the dotted blue line the app drew before
/// (`next-solid-picked-ring` off, and always in Current).
public struct PickedRing: Sendable, Equatable {
    public enum Ink: Sendable, Equatable {
        /// The system accent colour, as the mocks' `--accent`.
        case accent
        /// The system blue the dotted line has always worn.
        case systemBlue
    }

    /// The light halo drawn under the ring, the same path stroked wider.
    public struct Casing: Sendable, Equatable {
        public let width: CGFloat
        /// Grey level, 1 being white.
        public let white: CGFloat
        public let opacity: CGFloat
    }

    public let ink: Ink
    public let width: CGFloat
    public let opacity: CGFloat
    public let dash: [CGFloat]?
    public let casing: Casing?

    /// The ring on THE picked layer, and on a pushed-in recording's frame.
    public static func picked(solid: Bool) -> PickedRing {
        solid ? PickedRing(ink: .accent, width: 1.5, opacity: 1, dash: nil,
                           casing: Casing(width: 3, white: 1, opacity: 0.6))
              : dotted
    }

    /// The ring on each member of a multi-selection.
    public static func member(solid: Bool) -> PickedRing {
        solid ? PickedRing(ink: .accent, width: 1, opacity: 0.7, dash: nil,
                           casing: Casing(width: 2.5, white: 1, opacity: 0.5))
              : dotted
    }

    private static let dotted = PickedRing(ink: .systemBlue, width: 2, opacity: 0.6,
                                           dash: [2, 4], casing: nil)
}
