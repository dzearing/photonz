import CoreGraphics
import Foundation

/// How an arrow is DRAWN, as opposed to where it goes or what it ends in.
///
/// Every arrow used to be a ruler line with a geometric head, and the user
/// called it "extremely mechanical" on 2026-10-01, handing over four arrows
/// drawn by hand (`docs/design/references/arrows/user-ref-25…28.png`). Each of
/// the hand-made styles is one of those: a thin pen line with a hooked open
/// head, a bold marker with a loose one, a brush stroke that tapers from a
/// point and swells before a swept calligraphic head, and a rough outline
/// arrow sketched twice over in dry ink.
///
/// Five more came from the prototype the user picked from on 2026-10-31
/// (`docs/design/markup.md` section 5): a dashed line, a bold block arrow, a
/// glowing neon line, a line of dots and a right-angle elbow connector. Those
/// are drawn exactly, with no hand, so the same two ends always give the same
/// drawing and Reshuffle has nothing to do on them.
///
/// A style is how the arrow is PAINTED, never part of the drawing: the arrow
/// keeps its two ends, its colour, its thickness and its head size whichever
/// style it wears, so switching back and forth loses nothing
/// (`HandMadeArrow.swift` draws them, at render time).
public enum ArrowStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// The geometric arrow every arrow was before there was a choice.
    case clean
    /// A thin pen line, a little unsteady, with an open hooked head (ref 25).
    case handDrawn
    /// A bold rounded marker stroke with a loose two-stroke head (ref 27).
    case marker
    /// A brush stroke: a point at the tail, a swelling body and a swept
    /// calligraphic head (ref 28).
    case brush
    /// A rough outline arrow, stroked twice over and broken where the ink ran
    /// dry (ref 26).
    case sketch
    /// A dashed line with a solid head.
    case dashed
    /// A bold filled arrow whose shaft widens into a big head.
    case block
    /// A glowing line with a bright core and an open head.
    case neon
    /// A line of round dots, a bigger dot at the tail, and a chevron head.
    case dotted
    /// A right-angle connector with a rounded corner, a dot at the tail and a
    /// solid head, for diagrams.
    case elbow

    /// What a new arrow is drawn in, and what an arrow saved before styles
    /// existed opens as.
    public static let standard: ArrowStyle = .clean

    /// The tile's name. The tile itself is a picture of the style.
    public var title: String {
        switch self {
        case .clean: "Clean"
        case .handDrawn: "Hand-drawn"
        case .marker: "Marker"
        case .brush: "Brush"
        case .sketch: "Sketch"
        case .dashed: "Dashed"
        case .block: "Block"
        case .neon: "Neon"
        case .dotted: "Dotted"
        case .elbow: "Elbow"
        }
    }

    /// The submenu the styles are listed under, on the arrow's right-click
    /// menu and in the Layer menu.
    public static let menuTitle = "Arrow Style"
    /// The command that draws a hand-made arrow again with a new hand.
    public static let reshuffleTitle = "Reshuffle"

    /// Whether the arrow draws its OWN head and its own tail, from the pieces
    /// `HandMadeArrow` lays out, rather than the clean line and ending every
    /// arrow had before styles. True of every style but Clean, so the clean
    /// arrow's choice of ending and of line end do not reach any of them.
    public var drawsOwnInk: Bool { self != .clean }

    /// Whether the arrow is drawn by a HAND: a seeded wobble, a loose head, a
    /// broken line. These are the styles Reshuffle redraws; the exact ones
    /// (Dashed, Block, Neon, Dotted, Elbow) look the same whatever the seed.
    public var hasHand: Bool {
        switch self {
        case .handDrawn, .marker, .brush, .sketch: true
        case .clean, .dashed, .block, .neon, .dotted, .elbow: false
        }
    }

    /// Whether the line glows (Neon): a soft halo in its own colour round the
    /// line and head, drawn under them, with a bright core on top.
    public var glows: Bool { self == .neon }
}

extension AnnotationContent {
    /// Whether this arrow draws a head at all: every hand-made style does, and
    /// a clean arrow does unless it was told to end in nothing.
    public var drawsArrowhead: Bool {
        shape == .arrow && (arrowStyle.drawsOwnInk || arrowheadStyle != .plain)
    }
}
