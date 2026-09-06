import CoreGraphics
import Foundation
import PhotonzCore

/// Draws the shared label pill — the measure chip and the arrow caption are the
/// same capsule: a rounded fill, a border in the owning object's ink, and
/// upright text blitted from `TextRasterizer`. Extracted from
/// `MeasureRasterizer` so every tool's readout keeps one legibility treatment.
enum PillRasterizer {

    /// A drop shadow behind the pill's fill. `offset.height` is visual: positive
    /// moves the shadow DOWN in the flipped (top-left) space the rasterizers
    /// draw in.
    struct Shadow {
        var blur: CGFloat = 4
        var offset = CGSize(width: 0, height: 2)
        var color = CGColor(gray: 0, alpha: 0.35)
    }

    /// The pill's footprint = measured text (at `fontSize`) + padding all
    /// sides, never narrower than `minWidth`.
    ///
    /// The floor is what keeps a short readout a badge: the corner radius is
    /// half the short side, so without one a two character string draws a
    /// circle rather than the capsule the same pill draws around a longer one.
    /// The caller passes its own floor (`MeasureContent.labelMinPillWidth`)
    /// because whatever reserves the frame for the pill has to compute the
    /// identical number without measuring any glyphs, and each kind of pill
    /// derives it from its own font size and padding. The arrow caption keeps
    /// its floor in `AnnotationContent.captionPillSize` instead, which is why
    /// this argument defaults to none.
    static func footprint(for text: String, fontSize: CGFloat, padding: CGFloat,
                          minWidth: CGFloat = 0) -> CGSize {
        let size = TextRasterizer.naturalSize(content(text, fontSize: fontSize))
        return CGSize(width: max(size.width + 2 * padding, minWidth),
                      height: size.height + 2 * padding)
    }

    /// The face a pill sets its label in, and the ONE place a label with more
    /// than one line in it is decided to be centred: rows sitting ragged left
    /// inside a capsule read as a paragraph that lost its box. A single line is
    /// left alone — it is centred by its ink instead (see `draw`), which is a
    /// finer measurement than any alignment.
    static func content(_ string: String, fontSize: CGFloat,
                        colorHex: String = "#FFFFFF") -> TextContent {
        var text = TextContent(string: string, fontName: "SF Pro", fontSize: fontSize,
                               colorHex: colorHex)
        if string.contains(where: \.isNewline) { text.alignment = .center }
        return text
    }

    /// The pill's corner radius: half its short side, so a readout (always
    /// wider than it is tall) is a capsule with semicircular caps. Anything
    /// that has to MEET the pill's outline reads it from here, so the curve a
    /// line stops on is the same curve the pill is drawn with.
    static func cornerRadius(for chipSize: CGSize) -> CGFloat {
        min(chipSize.width, chipSize.height) / 2
    }

    /// How many pixels one point of `context` covers: 1 for a document-sized
    /// raster, more when a zoomed-in canvas is baking the pill at the
    /// resolution it is about to be shown at. The rasterizers scale their
    /// context and go on drawing in document points, so everything here is
    /// already the right SIZE — this is only for the two things that do not
    /// follow the transform: a bitmap of glyphs, which has to be made with the
    /// pixels it will be drawn with, and the shadow, whose offset and blur
    /// Core Graphics measures in device pixels.
    private static func pixelsPerPoint(of context: CGContext) -> CGFloat {
        let ctm = context.ctm
        let scale = (ctm.a * ctm.d - ctm.b * ctm.c).magnitude.squareRoot()
        return scale > 0 && scale.isFinite ? scale : 1
    }

    /// Draws the pill centered at `anchor`: the `fill`, a border in `border`,
    /// and text in `textColorHex` — each independently colorable. Glyphs come
    /// from `TextRasterizer` (the proven-upright path) and are blitted in —
    /// drawing CoreText directly into the already-flipped context renders the
    /// text upside down. An optional `shadow` sits behind the fill only, so the
    /// border and text stay crisp.
    /// `cornerRadius` overrides the capsule default, for the arrow caption
    /// whose corner the user can take from square through badge to full pill.
    /// Nil keeps the capsule every readout has always been.
    static func draw(_ string: String, at anchor: CGPoint, chipSize: CGSize,
                     fontSize: CGFloat, borderWidth: CGFloat, fill: CGColor,
                     border: CGColor, textColorHex: String, shadow: Shadow? = nil,
                     cornerRadius: CGFloat? = nil,
                     in context: CGContext) {
        let pixelsPerPoint = Self.pixelsPerPoint(of: context)
        let rect = CGRect(x: anchor.x - chipSize.width / 2, y: anchor.y - chipSize.height / 2,
                          width: chipSize.width, height: chipSize.height)
        let radius = min(max(cornerRadius ?? Self.cornerRadius(for: chipSize), 0),
                         min(chipSize.width, chipSize.height) / 2)
        let pill = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        if let shadow {
            // Shadow offsets ignore the CTM twice over: the flip to top-left
            // space negates the visual y direction, and the numbers are read as
            // device pixels, so a pill baked for a zoomed-in canvas has to ask
            // for a proportionally bigger shadow or it arrives with a hairline
            // of one.
            context.setShadow(offset: CGSize(width: shadow.offset.width * pixelsPerPoint,
                                             height: -shadow.offset.height * pixelsPerPoint),
                              blur: shadow.blur * pixelsPerPoint, color: shadow.color)
        }
        context.setFillColor(fill)
        context.addPath(pill)
        context.fillPath()
        context.restoreGState()
        // Border at the stroke color's FULL strength (it used to be softened to
        // 0.7α to sit politely under a hardcoded white chip). Now that the chip
        // can be any color — transparent included — the border is often the only
        // thing closing the head line's gap, so it must read as the same line as
        // the caliper it interrupts.
        context.setStrokeColor(border)
        context.setLineWidth(max(1, borderWidth))
        context.addPath(pill)
        context.strokePath()

        let text = content(string, fontSize: fontSize, colorHex: textColorHex)
        let textSize = TextRasterizer.naturalSize(text)
        // Made with the pixels it is about to be drawn with: a document-sized
        // bitmap stretched over a zoomed-in pill is exactly the soft readout
        // this whole path exists to avoid.
        guard let glyphs = TextRasterizer.rasterize(text, size: textSize,
                                                    scale: pixelsPerPoint) else { return }
        // Centre the INK, not the measured box: the box carries its rounding
        // and frame inset entirely to the right of the glyphs, so centring it
        // leaves the word about two points left of the middle of the pill.
        // Rounded to a whole device pixel so the glyph bitmap keeps landing on
        // the pixel grid it was baked for — a fractional slide would soften
        // every readout to fix a fraction of a point.
        let inkOffset = (TextRasterizer.inkOffset(text) * pixelsPerPoint).rounded() / pixelsPerPoint
        let textRect = CGRect(x: anchor.x - textSize.width / 2 - inkOffset,
                              y: anchor.y - textSize.height / 2,
                              width: textSize.width, height: textSize.height)
        context.saveGState()
        context.translateBy(x: textRect.minX, y: textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(glyphs, in: CGRect(origin: .zero, size: textRect.size))
        context.restoreGState()
    }
}
