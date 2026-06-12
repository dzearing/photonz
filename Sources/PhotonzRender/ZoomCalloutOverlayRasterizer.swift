import CoreGraphics
import Foundation
import PhotonzCore

/// Rasterizes the canvas-space chrome of a zoom callout: the outline around the
/// magnified source region plus the leader lines tying it to the callout box.
/// The callout box's own border/shadow/radius come from `LayerStyle` in
/// `DocumentRenderer`; this draws only what lies *outside* the layer frame.
public enum ZoomCalloutOverlayRasterizer {

    /// Returns the overlay image and its top-left origin in canvas coordinates,
    /// or nil when the source region is degenerate. The outline matches the
    /// callout's border style; its corner radius is the callout's divided by
    /// `magnification` so both boxes read as the same shape at different scales.
    public static func rasterize(source: CGRect, callout: CGRect,
                                 style: LayerStyle, magnification: CGFloat,
                                 shape: ZoomCalloutShape = .rectangle) -> (image: CGImage, origin: CGPoint)? {
        let source = source.standardized
        guard source.width >= 1, source.height >= 1 else { return nil }

        let outlineWidth = max(1, style.borderWidth)
        let bounds = source.union(callout).insetBy(dx: -outlineWidth, dy: -outlineWidth).integral
        let width = Int(bounds.width.rounded())
        let height = Int(bounds.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Flip to top-left coordinates, then shift canvas space into the image.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)

        let rgba = RGBA(hex: style.borderColorHex) ?? RGBA(r: 0, g: 0, b: 0)
        let opacity = max(0, min(1, style.opacity))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Leader lines first (under the outline), translucent so they read as
        // connectors, not annotations.
        context.setStrokeColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b,
                                       alpha: rgba.a * opacity * 0.6))
        context.setLineWidth(outlineWidth)
        for line in Geometry.leaderLines(source: source, callout: callout) {
            context.move(to: line.from)
            context.addLine(to: line.to)
            context.strokePath()
        }

        // Source outline, stroke centered on the region boundary.
        context.setStrokeColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b,
                                       alpha: rgba.a * opacity))
        context.setLineWidth(outlineWidth)
        let scaledStyleRadius = magnification > 0
            ? min(style.cornerRadius / magnification, min(source.width, source.height) / 2)
            : 0
        let radius = ZoomCalloutContent(sourceRect: source, shape: shape)
            .effectiveCornerRadius(boxSize: source.size, styleRadius: scaledStyleRadius)
        if radius > 0 {
            context.addPath(CGPath(roundedRect: source, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
        } else {
            context.stroke(source)
        }

        guard let image = context.makeImage() else { return nil }
        return (image, bounds.origin)
    }
}
