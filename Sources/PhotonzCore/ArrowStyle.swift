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
        }
    }

    /// The submenu the styles are listed under, on the arrow's right-click
    /// menu and in the Layer menu.
    public static let menuTitle = "Arrow Style"
    /// The command that draws a hand-made arrow again with a new hand.
    public static let reshuffleTitle = "Reshuffle"

    /// Whether the arrow is drawn by hand rather than with a ruler. A hand-made
    /// arrow draws its OWN head and its own tail, so the clean arrow's choice
    /// of ending and of line end do not reach it.
    public var isHandMade: Bool { self != .clean }
}

extension AnnotationContent {
    /// Whether this arrow draws a head at all: every hand-made style does, and
    /// a clean arrow does unless it was told to end in nothing.
    public var drawsArrowhead: Bool {
        shape == .arrow && (arrowStyle.isHandMade || arrowheadStyle != .plain)
    }
}
