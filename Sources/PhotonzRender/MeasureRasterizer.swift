import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Rasterizes a caliper (`MeasureContent`) into a transparent-background CGImage:
/// the squared-U outline (two legs + head bar) with lightly rounded corners, plus
/// the label pill. When the label is on, the head line is **split around the
/// chip** (a gap), so a translucent pill never reveals a stroke behind it.
///
/// The pill used to be omitted here and drawn as an AppKit overlay on the live
/// canvas instead (a Liquid-Glass capsule). That made the chip unreachable by
/// everything that acts on a LAYER — opacity, shadow, blend mode, transform —
/// so the canvas and the export disagreed. The caliper is one object; it is one
/// raster.
///
/// Drawing happens in the layer's local top-left space — the same space
/// `start`/`end` are stored in — and the readout uses the content's unit,
/// divided by `pixelScale` for points.
public enum MeasureRasterizer {

    public static func rasterize(_ measure: MeasureContent, size: CGSize,
                                 pixelScale: CGFloat) -> CGImage? {
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

        let rgba = RGBA(hex: measure.strokeColorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        // The chip's fill is its own color; its alpha comes from `chipOpacity`
        // (the hex never carries alpha — see MeasureContent.chipColorHex).
        let chip = RGBA(hex: measure.chipColorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let chipColor = CGColor(srgbRed: chip.r, green: chip.g, blue: chip.b,
                                alpha: min(max(measure.chipOpacity, 0), 1))
        // Caliper lines are ACTUAL image pixels — a "1px" caliper is exactly one
        // image pixel (pixel-precise redlining), NOT scaled up by pixelScale.
        let lineWidth = measure.strokeWidth
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        // Round caps/joins so the corners read refined, not sharp.
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let g = measure.caliperGeometry()

        // An alignment check draws a dashed guide with tick marks and a verdict
        // chip instead of the squared-U caliper.
        if measure.alignment != nil {
            drawAlignmentCheck(measure, geometry: g, pixelScale: pixelScale,
                               color: color, chipColor: chipColor, in: context)
            return context.makeImage()
        }

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

        if measure.showLabel {
            drawPill(labelText, at: mid, chipSize: chipSize, fontSize: measure.labelPointSize,
                     borderWidth: lineWidth, fill: chipColor, border: color,
                     textColorHex: measure.textColorHex, in: context)
        }

        return context.makeImage()
    }

    /// An alignment check (§9, decision D1): a dashed guide along the feet
    /// line, a short solid tick where each aligned element crosses it, the
    /// outlier's ACTUAL edge drawn beside the guide with a connector showing
    /// the gap, and the verdict chip ("aligned" / "off 4 px") at the midpoint.
    private static func drawAlignmentCheck(_ measure: MeasureContent, geometry g: CaliperGeometry,
                                           pixelScale: CGFloat, color: CGColor,
                                           chipColor: CGColor, in context: CGContext) {
        guard let check = measure.alignment else { return }
        let labelText = measure.label(pixelScale: pixelScale)
        var chipSize = CGSize.zero
        var gapHalf: CGFloat = 0
        if measure.showLabel {
            chipSize = chipFootprint(for: labelText, fontSize: measure.labelPointSize,
                                     padding: measure.labelPadding)
            gapHalf = min(measure.chipAxisHalfExtent(chipSize: chipSize) + MeasureContent.chipLineGap,
                          measure.rawDistance / 2)
        }

        // Dashed guide, split around the chip. `labelAnchor` is the feet-line
        // midpoint (alignment guides carry headOffset 0).
        let mid = g.labelAnchor
        func gapEdge(toward p: CGPoint) -> CGPoint {
            let dx = p.x - mid.x, dy = p.y - mid.y
            let len = hypot(dx, dy)
            guard len > 0, gapHalf > 0 else { return mid }
            return CGPoint(x: mid.x + dx / len * gapHalf, y: mid.y + dy / len * gapHalf)
        }
        context.setLineDash(phase: 0, lengths: [6, 4])
        for foot in [g.footA, g.footB] {
            let inner = gapEdge(toward: foot)
            context.move(to: foot)
            context.addLine(to: inner)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])

        let vertical = measure.mode == .vertical
        let guidePos = vertical ? g.footA.x : g.footA.y
        let outlier = check.verdict?.outlierIndex
        let tick = MeasureBuilder.alignmentTickHalf
        for (index, item) in check.items.enumerated() {
            let spanMid = (item.spanStart + item.spanEnd) / 2
            if index == outlier {
                // The outlier's real edge across its span, plus a connector
                // from the guide so the gap itself is visible.
                context.move(to: point(cross: item.edge, along: item.spanStart, vertical: vertical))
                context.addLine(to: point(cross: item.edge, along: item.spanEnd, vertical: vertical))
                context.strokePath()
                context.move(to: point(cross: guidePos, along: spanMid, vertical: vertical))
                context.addLine(to: point(cross: item.edge, along: spanMid, vertical: vertical))
                context.strokePath()
            } else {
                // A short perpendicular tick where the element crosses the guide.
                context.move(to: point(cross: guidePos - tick, along: spanMid, vertical: vertical))
                context.addLine(to: point(cross: guidePos + tick, along: spanMid, vertical: vertical))
                context.strokePath()
            }
        }

        if measure.showLabel {
            drawPill(labelText, at: mid, chipSize: chipSize, fontSize: measure.labelPointSize,
                     borderWidth: measure.strokeWidth, fill: chipColor, border: color,
                     textColorHex: measure.textColorHex, in: context)
        }
    }

    /// A point from guide-relative coordinates: `cross` is the guide's own axis
    /// position (x for a vertical guide), `along` the span axis.
    private static func point(cross: CGFloat, along: CGFloat, vertical: Bool) -> CGPoint {
        vertical ? CGPoint(x: cross, y: along) : CGPoint(x: along, y: cross)
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

    /// Draws the flattened readout centered at `anchor`: the chip `fill`, a
    /// border in the caliper's stroke color, and text in the readout color — the
    /// three independently editable measure colors. Glyphs come from
    /// `TextRasterizer` (the proven-upright path) and are blitted in — drawing
    /// CoreText directly into this already-flipped context renders the text
    /// upside down.
    private static func drawPill(_ string: String, at anchor: CGPoint, chipSize: CGSize,
                                 fontSize: CGFloat, borderWidth: CGFloat, fill: CGColor,
                                 border: CGColor, textColorHex: String, in context: CGContext) {
        let rect = CGRect(x: anchor.x - chipSize.width / 2, y: anchor.y - chipSize.height / 2,
                          width: chipSize.width, height: chipSize.height)
        let radius = chipSize.height / 2
        let pill = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.setFillColor(fill)
        context.addPath(pill)
        context.fillPath()
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
