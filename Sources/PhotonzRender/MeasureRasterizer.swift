import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Rasterizes a `MeasureContent` (dimension line, witness lines, end caps, and a
/// toggleable numeric label) into a transparent-background CGImage. Drawing
/// happens in the layer's local top-left space — the same space `start`/`end`
/// are stored in — and the label reads out in the unit chosen by the content,
/// divided by `pixelScale` for points.
public enum MeasureRasterizer {

    public static func rasterize(_ measure: MeasureContent, size: CGSize, pixelScale: CGFloat) -> CGImage? {
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
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(measure.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let geo = measure.geometry()

        // Witness/extension lines first (under the dimension line and caps).
        for seg in geo.extensions {
            context.move(to: seg.a)
            context.addLine(to: seg.b)
        }
        context.strokePath()

        // The dimension line.
        context.move(to: geo.dimension.a)
        context.addLine(to: geo.dimension.b)
        context.strokePath()

        // End caps at each end of the dimension line.
        drawCaps(measure: measure, dimension: geo.dimension, color: color, in: context)

        // Numeric label on a filled plate centered on the line.
        if measure.showLabel {
            drawLabel(measure.label(pixelScale: pixelScale), at: geo.labelAnchor,
                      plateColor: color, in: context)
        }

        return context.makeImage()
    }

    /// Perpendicular ticks (the redline convention) or inward arrowheads at the
    /// dimension line's ends.
    private static func drawCaps(measure: MeasureContent, dimension: MeasureSegment,
                                 color: CGColor, in context: CGContext) {
        let dx = dimension.b.x - dimension.a.x
        let dy = dimension.b.y - dimension.a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let ux = dx / length, uy = dy / length // along the line

        switch measure.capStyle {
        case .ticks:
            // A serif perpendicular to the line, centered on each endpoint.
            let nx = -uy, ny = ux // perpendicular unit
            let reach = measure.capExtent
            context.setLineWidth(measure.strokeWidth)
            for p in [dimension.a, dimension.b] {
                context.move(to: CGPoint(x: p.x - nx * reach, y: p.y - ny * reach))
                context.addLine(to: CGPoint(x: p.x + nx * reach, y: p.y + ny * reach))
            }
            context.strokePath()

        case .arrows:
            // Filled arrowheads pointing inward from each end.
            let head = max(measure.strokeWidth * 3, 8)
            let halfW = head * 0.45
            let nx = -uy, ny = ux
            func arrow(at tip: CGPoint, along ax: CGFloat, ay: CGFloat) {
                let baseX = tip.x + ax * head, baseY = tip.y + ay * head
                context.beginPath()
                context.move(to: tip)
                context.addLine(to: CGPoint(x: baseX + nx * halfW, y: baseY + ny * halfW))
                context.addLine(to: CGPoint(x: baseX - nx * halfW, y: baseY - ny * halfW))
                context.closePath()
                context.fillPath()
            }
            arrow(at: dimension.a, along: ux, ay: uy)   // points toward b
            arrow(at: dimension.b, along: -ux, ay: -uy) // points toward a
        }
    }

    /// Draws the readout centered at `anchor` on a rounded plate filled with the
    /// measure color. The glyphs come from `TextRasterizer` (the proven-upright
    /// path) as a transparent image that's blitted in — drawing CoreText directly
    /// into this already-flipped context renders the text upside down.
    private static func drawLabel(_ string: String, at anchor: CGPoint,
                                  plateColor: CGColor, in context: CGContext) {
        let text = TextContent(string: string, fontName: "SF Pro",
                               fontSize: MeasureContent.labelFontSize, colorHex: "#FFFFFF")
        let textSize = TextRasterizer.naturalSize(text)
        guard let glyphs = TextRasterizer.rasterize(text, size: textSize) else { return }

        let pad = MeasureContent.labelPadding
        let plateOrigin = CGPoint(x: anchor.x - textSize.width / 2 - pad,
                                  y: anchor.y - textSize.height / 2 - pad)
        let plateSize = CGSize(width: textSize.width + 2 * pad, height: textSize.height + 2 * pad)
        let plate = CGRect(origin: plateOrigin, size: plateSize)
        context.setFillColor(plateColor)
        context.addPath(CGPath(roundedRect: plate, cornerWidth: plate.height / 2,
                               cornerHeight: plate.height / 2, transform: nil))
        context.fillPath()

        // Blit the upright glyph image. The context is flipped (top-left), so
        // locally un-flip around the text rect to keep the image upright.
        let textRect = CGRect(x: anchor.x - textSize.width / 2, y: anchor.y - textSize.height / 2,
                              width: textSize.width, height: textSize.height)
        context.saveGState()
        context.translateBy(x: textRect.minX, y: textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(glyphs, in: CGRect(origin: .zero, size: textRect.size))
        context.restoreGState()
    }
}
