import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Rasterizes a caliper (`MeasureContent`) into a transparent-background CGImage:
/// the squared-U outline (two legs + head bar) with lightly rounded corners, and
/// — only when `bakeLabel` is set — a flat glass-style label pill baked in.
///
/// The live editor draws the pill as a real Liquid-Glass overlay and passes
/// `bakeLabel: false`, so the caliper bitmap carries no label; export /
/// thumbnails / region-promote pass `bakeLabel: true` so flattened output still
/// shows the measurement. Either way, when the label is on the head line is
/// **split around the chip** (a gap), so a translucent pill never reveals a
/// stroke behind it.
///
/// Drawing happens in the layer's local top-left space — the same space
/// `start`/`end` are stored in — and the readout uses the content's unit,
/// divided by `pixelScale` for points.
public enum MeasureRasterizer {

    public static func rasterize(_ measure: MeasureContent, size: CGSize, pixelScale: CGFloat,
                                 bakeLabel: Bool = true) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Flip to top-left coordinates (matches AnnotationRasterizer/TextRasterizer).
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let rgba = RGBA(hex: measure.colorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        // Caliper lines are ACTUAL image pixels — a "1px" caliper is exactly one
        // image pixel (pixel-precise redlining), NOT scaled up by pixelScale.
        let lineWidth = measure.strokeWidth
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        // Round caps/joins so the corners read refined, not sharp.
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let g = measure.caliperGeometry()

        // Chip footprint + the head-line gap it needs (0 when the label is off).
        let labelText = measure.label(pixelScale: pixelScale)
        var chipSize = CGSize.zero
        var gapHalf: CGFloat = 0
        if measure.showLabel {
            chipSize = chipFootprint(for: labelText, fontSize: measure.labelPointSize,
                                     padding: measure.labelPadding)
            gapHalf = min(measure.chipAxisHalfExtent(chipSize: chipSize) + MeasureContent.chipLineGap,
                          measure.rawDistance / 2)
        }

        // Two rounded L legs; the head line is cut where the chip sits.
        let mid = g.labelAnchor
        func gapEdge(toward p: CGPoint) -> CGPoint {
            let dx = p.x - mid.x, dy = p.y - mid.y
            let len = hypot(dx, dy)
            guard len > 0, gapHalf > 0 else { return mid }
            return CGPoint(x: mid.x + dx / len * gapHalf, y: mid.y + dy / len * gapHalf)
        }
        drawLeg(foot: g.footA, head: g.headA, toward: gapEdge(toward: g.headA), in: context)
        drawLeg(foot: g.footB, head: g.headB, toward: gapEdge(toward: g.headB), in: context)

        // Flattened pill (export / thumbnails only). On-screen the live glass
        // overlay fills the same gap.
        if measure.showLabel, bakeLabel {
            drawPill(labelText, at: mid, chipSize: chipSize, fontSize: measure.labelPointSize,
                     borderWidth: lineWidth, colorHex: measure.colorHex, tint: color, in: context)
        }

        return context.makeImage()
    }

    /// The chip's footprint = measured text (at `fontSize`) + padding on all sides.
    private static func chipFootprint(for text: String, fontSize: CGFloat, padding: CGFloat) -> CGSize {
        let size = TextRasterizer.naturalSize(
            TextContent(string: text, fontName: "SF Pro", fontSize: fontSize))
        return CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
    }

    /// One caliper leg: `foot → (rounded corner at head) → toward` (the head-line
    /// cut edge, or the head midpoint when there's no chip gap).
    private static func drawLeg(foot: CGPoint, head: CGPoint, toward: CGPoint, in context: CGContext) {
        let legLen = hypot(head.x - foot.x, head.y - foot.y)
        let armLen = hypot(toward.x - head.x, toward.y - head.y)
        let radius = max(0, min(MeasureContent.cornerRadius, legLen / 2, armLen))
        let path = CGMutablePath()
        path.move(to: foot)
        if radius > 0.5, armLen > 0.5 {
            path.addArc(tangent1End: head, tangent2End: toward, radius: radius)
            path.addLine(to: toward)
        } else {
            path.addLine(to: head)
            if armLen > 0.5 { path.addLine(to: toward) }
        }
        context.addPath(path)
        context.strokePath()
    }

    /// Draws the flattened readout centered at `anchor`: a neutral translucent
    /// pill (the glass look minus live blur) with a hairline border in the
    /// caliper color and caliper-colored text. Glyphs come from `TextRasterizer`
    /// (the proven-upright path) and are blitted in — drawing CoreText directly
    /// into this already-flipped context renders the text upside down.
    private static func drawPill(_ string: String, at anchor: CGPoint, chipSize: CGSize,
                                 fontSize: CGFloat, borderWidth: CGFloat, colorHex: String,
                                 tint: CGColor, in context: CGContext) {
        let rect = CGRect(x: anchor.x - chipSize.width / 2, y: anchor.y - chipSize.height / 2,
                          width: chipSize.width, height: chipSize.height)
        let radius = chipSize.height / 2
        let pill = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // Neutral translucent fill.
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
        context.addPath(pill)
        context.fillPath()
        // Border in the caliper color, matched to the caliper's stroke width.
        context.setStrokeColor(tint.copy(alpha: 0.7) ?? tint)
        context.setLineWidth(max(1, borderWidth))
        context.addPath(pill)
        context.strokePath()

        // Caliper-colored text, blitted upright.
        let text = TextContent(string: string, fontName: "SF Pro",
                               fontSize: fontSize, colorHex: colorHex)
        let textSize = TextRasterizer.naturalSize(text)
        guard let glyphs = TextRasterizer.rasterize(text, size: textSize) else { return }
        let textRect = CGRect(x: anchor.x - textSize.width / 2, y: anchor.y - textSize.height / 2,
                              width: textSize.width, height: textSize.height)
        context.saveGState()
        context.translateBy(x: textRect.minX, y: textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(glyphs, in: CGRect(origin: .zero, size: textRect.size))
        context.restoreGState()
    }
}
