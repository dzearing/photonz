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

    /// The pill's footprint = measured text (at `fontSize`) + padding all sides.
    static func footprint(for text: String, fontSize: CGFloat, padding: CGFloat) -> CGSize {
        let size = TextRasterizer.naturalSize(
            TextContent(string: text, fontName: "SF Pro", fontSize: fontSize))
        return CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
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
    static func draw(_ string: String, at anchor: CGPoint, chipSize: CGSize,
                     fontSize: CGFloat, borderWidth: CGFloat, fill: CGColor,
                     border: CGColor, textColorHex: String, shadow: Shadow? = nil,
                     in context: CGContext) {
        let pixelsPerPoint = Self.pixelsPerPoint(of: context)
        let rect = CGRect(x: anchor.x - chipSize.width / 2, y: anchor.y - chipSize.height / 2,
                          width: chipSize.width, height: chipSize.height)
        let radius = chipSize.height / 2
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

        let text = TextContent(string: string, fontName: "SF Pro",
                               fontSize: fontSize, colorHex: textColorHex)
        let textSize = TextRasterizer.naturalSize(text)
        // Made with the pixels it is about to be drawn with: a document-sized
        // bitmap stretched over a zoomed-in pill is exactly the soft readout
        // this whole path exists to avoid.
        guard let glyphs = TextRasterizer.rasterize(text, size: textSize,
                                                    scale: pixelsPerPoint) else { return }
        let textRect = CGRect(x: anchor.x - textSize.width / 2, y: anchor.y - textSize.height / 2,
                              width: textSize.width, height: textSize.height)
        context.saveGState()
        context.translateBy(x: textRect.minX, y: textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(glyphs, in: CGRect(origin: .zero, size: textRect.size))
        context.restoreGState()
    }
}
