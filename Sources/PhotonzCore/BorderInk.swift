import CoreGraphics
import Foundation

/// What a border is painted the moment it is born, and why a shape never
/// arrives as nothing.
///
/// Until 2026-09-14 a freshly drawn box came out with a Border already in its
/// Effects list, painted the exact colour of the fill. The panel said Border,
/// 4 pt, and the picture had no line in it: drag the width up and on an inside
/// border nothing happened, on an outside border the box simply grew. The only
/// road to a line you could see was the Border colour well.
///
/// The user settled it on the decision card "When you draw a shape, what
/// should its border look like before you have picked a colour for it?": **no
/// edge until you ask for one**. A fresh box is its fill and nothing else, the
/// Effects list is empty, and the border you add is one you asked for — so it
/// arrives in a colour that stands out from the fill rather than a copy of it.
///
/// ## The two rules that follow
///
/// * **A new ring is drawn in an ink that reads.** Not a darker shade of the
///   fill (that was another option on the card and it lost), and not a fixed
///   black either: black is as invisible on a near-black fill as red is on red.
///   The ink follows the fill's brightness — graphite on a light fill, white on
///   a dark one.
/// * **A shape never becomes nothing.** Turning a box's Fill off used to leave
///   an outline box in the shape's colour, because the edge was always there
///   wearing the fill's colour. With no edge to fall back on, taking the fill
///   away would leave an invisible layer, so a shape losing its last paint
///   gains the outline that carries it.
public enum BorderInk {

    /// The ink for a ring sitting against something light.
    ///
    /// Graphite rather than pure black: it is the same near-black the app's
    /// text and chrome use, and on a white canvas a pure black ring reads as
    /// heavier than anything else on screen.
    public static let onLight = "#1C1C1E"

    /// The ink for a ring sitting against something dark.
    public static let onDark = "#FFFFFF"

    /// The ink a NEW border takes on a shape whose inside is `fill`.
    ///
    /// Nil fill means there is nothing behind the ring but the canvas, and a
    /// canvas is light far more often than not, so the ring goes graphite.
    public static func standingOut(from fill: Paint?) -> Paint {
        Paint(hex: standingOutHex(from: fill))
    }

    /// The same answer as one flat colour, for the places that can only hold
    /// one.
    ///
    /// The choice is made on CONTRAST and not on a lightness threshold, which
    /// is the difference between a ring you can see and a ring you cannot: the
    /// red every shape arrives in sits at 0.39 lightness, just under halfway,
    /// so "dark fill, light ring" would put a white ring on it at 2.4:1 where
    /// the graphite one reads at 7.1:1. Whichever ink stands further off the
    /// fill wins.
    public static func standingOutHex(from fill: Paint?) -> String {
        guard let fill, let behind = luminance(of: fill) else { return onLight }
        return contrast(behind, against: onDark) > contrast(behind, against: onLight)
            ? onDark
            : onLight
    }

    /// How far apart a lightness and an ink read, as the ratio every contrast
    /// rule in the app uses.
    private static func contrast(_ behind: Double, against ink: String) -> Double {
        let front = RGBA(hex: ink)?.relativeLuminance ?? 0
        let lighter = max(behind, front) + 0.05
        let darker = min(behind, front) + 0.05
        return lighter / darker
    }

    /// Whether a ring in `ink` would be LOST against `fill` — the test for
    /// "this border is the fill wearing a different name".
    ///
    /// Two paints that draw the same thing are the case this exists for; near
    /// misses are left alone, because a colour somebody deliberately nudged is
    /// theirs to keep.
    public static func isLost(_ ink: Paint, against fill: Paint?) -> Bool {
        guard let fill else { return false }
        return ink.draws(sameAs: fill)
    }

    /// The line a shape falls back on when it would otherwise paint nothing.
    public static let fallbackWidth = AnnotationContent.defaultStrokeWidth

    /// How light a paint reads, averaged across its ramp when it has one so a
    /// gradient answers the question its flat colour cannot.
    static func luminance(of paint: Paint) -> Double? {
        if paint.isGradient {
            let lights = paint.orderedStops.compactMap { RGBA(hex: $0.hex)?.relativeLuminance }
            guard !lights.isEmpty else { return RGBA(hex: paint.hex)?.relativeLuminance }
            return lights.reduce(0, +) / Double(lights.count)
        }
        return RGBA(hex: paint.hex)?.relativeLuminance
    }
}

extension Layer {

    /// Whether this shape would paint NOTHING AT ALL: no inside, and no ring
    /// round it either, so the canvas shows a layer you can only find in the
    /// layers list.
    ///
    /// Only a box or an oval can land here. A line and an arrow ARE their
    /// stroke, a label is its letters, and a picture is its pixels.
    var paintsNothingAtAll: Bool {
        guard let annotation, annotation.drawsARingRatherThanBeingOne else { return false }
        return annotation.fill == nil && style.borderEffects.isEmpty
    }

    /// Gives this shape the outline that carries it when taking its inside
    /// away would otherwise leave nothing on the canvas.
    ///
    /// Switching Fill off has always left an outline box in the shape's
    /// colour, because the edge was there all along wearing the fill's colour.
    /// Now that a shape arrives with no edge, that outline has to come from
    /// somewhere, and this is it. Does nothing to a shape that still paints
    /// something, so it is safe to call after any edit.
    mutating func gainingItsOutlineIfNothingWouldPaint() {
        guard paintsNothingAtAll, let annotation else { return }
        var ring = BorderEffect(width: BorderInk.fallbackWidth, position: annotation.strokePosition)
        ring.paint = annotation.paint
        style.effects.append(.border(ring))
    }
}
