import CoreGraphics
import Foundation
import PhotonzCore

/// Rasterizes `AnnotationContent` into a transparent-background CGImage.
/// Drawing happens in the layer's local top-left coordinate space (the same
/// space `AnnotationContent.start`/`end` are stored in).
public enum AnnotationRasterizer {

    public static func rasterize(_ annotation: AnnotationContent, size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Flip so the drawing code below works in top-left coordinates.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let rgba = RGBA(hex: annotation.colorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        // Rectangles join with miters so a thick stroke doesn't fake a corner
        // radius the inspector doesn't show — `cornerRadius` alone rounds them
        // (it curves the path itself). Open strokes keep soft round joins.
        context.setLineJoin(annotation.shape == .rectangle ? .miter : .round)

        let box = CGRect(x: min(annotation.start.x, annotation.end.x),
                         y: min(annotation.start.y, annotation.end.y),
                         width: abs(annotation.end.x - annotation.start.x),
                         height: abs(annotation.end.y - annotation.start.y))

        switch annotation.shape {
        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()

        case .arrow:
            let head = Geometry.arrowhead(start: annotation.start, end: annotation.end,
                                          strokeWidth: annotation.strokeWidth,
                                          scale: annotation.arrowheadScale)
            // Stop the shaft inside the head so its round cap can't poke past the tip.
            let shaftEnd = Geometry.arrowShaftEnd(start: annotation.start, end: annotation.end,
                                                  strokeWidth: annotation.strokeWidth,
                                                  scale: annotation.arrowheadScale)
            context.move(to: annotation.start)
            context.addLine(to: shaftEnd)
            context.strokePath()
            context.beginPath()
            context.addLines(between: head)
            context.closePath()
            context.fillPath()

        case .rectangle:
            // Inset by half the stroke so the outline stays inside start..end.
            let inset = box.insetBy(dx: annotation.strokeWidth / 2, dy: annotation.strokeWidth / 2)
            if annotation.cornerRadius > 0, !inset.isEmpty {
                // Round the stroke itself (clamped to a capsule at most), so the
                // border follows the corners rather than being clipped off.
                let radius = min(annotation.cornerRadius, min(inset.width, inset.height) / 2)
                let path = CGPath(roundedRect: inset, cornerWidth: radius,
                                  cornerHeight: radius, transform: nil)
                if let fill = fillColor(annotation) {
                    context.setFillColor(fill)
                    context.addPath(path)
                    context.fillPath()
                }
                context.addPath(path)
                context.strokePath()
            } else {
                if let fill = fillColor(annotation) {
                    context.setFillColor(fill)
                    context.fill(inset)
                }
                context.stroke(inset)
            }

        case .ellipse:
            let inset = box.insetBy(dx: annotation.strokeWidth / 2, dy: annotation.strokeWidth / 2)
            if let fill = fillColor(annotation) {
                context.setFillColor(fill)
                context.fillEllipse(in: inset)
            }
            context.strokeEllipse(in: inset)

        case .highlight:
            // A filled box; the renderer composites it with multiply blend.
            context.fill(box)
        }

        return context.makeImage()
    }

    /// The interior fill for box shapes, nil when the shape is outline-only.
    private static func fillColor(_ annotation: AnnotationContent) -> CGColor? {
        guard let hex = annotation.fillColorHex, let rgba = RGBA(hex: hex) else { return nil }
        return CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}
