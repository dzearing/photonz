import CoreGraphics
import Foundation
import PhotonzCore

/// Rasterizes the canvas-space chrome of a zoom callout: the outline around the
/// magnified source region, the leader lines tying it to the callout box, and
/// the band between those lines tinted with the line colour (`fillOpacity`).
/// The callout box's own border/shadow/radius come from `LayerStyle` in
/// `DocumentRenderer`; this draws only what lies *outside* the layer frame.
public enum ZoomCalloutOverlayRasterizer {

    /// Returns the overlay image and its top-left origin in canvas coordinates,
    /// or nil when the source region is degenerate. The outline matches the
    /// callout's border style; its corner radius is the callout's divided by
    /// `magnification` so both boxes read as the same shape at different scales.
    public static func rasterize(source: CGRect, callout: CGRect,
                                 style: LayerStyle, magnification: CGFloat,
                                 shape: ZoomCalloutShape = .rectangle,
                                 fillOpacity: CGFloat = 0) -> (image: CGImage, origin: CGPoint)? {
        rasterize(source: source, calloutCorners: Geometry.corners(of: callout),
                  style: style, magnification: magnification, shape: shape,
                  fillOpacity: fillOpacity)
    }

    /// The same overlay for a callout box that has been TURNED.
    /// `calloutCorners` are the corners of the box as it is DRAWN
    /// (`Layer.transformedCorners`), so the leader lines meet the magnifier a
    /// person can see instead of aiming at the upright box it is stored as.
    public static func rasterize(source: CGRect, calloutCorners: [CGPoint],
                                 style: LayerStyle, magnification: CGFloat,
                                 shape: ZoomCalloutShape = .rectangle,
                                 fillOpacity: CGFloat = 0) -> (image: CGImage, origin: CGPoint)? {
        let source = source.standardized
        guard source.width >= 1, source.height >= 1 else { return nil }

        let outlineWidth = max(1, style.borderWidth)
        // Room for the box wherever the turn has put it, so a leader line
        // running out to a swung corner is not cropped away.
        var reach = source
        for corner in calloutCorners {
            reach = reach.union(CGRect(origin: corner, size: .zero))
        }
        let bounds = reach.insetBy(dx: -outlineWidth, dy: -outlineWidth).integral
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

        let scaledStyleRadius = magnification > 0
            ? min(style.cornerRadius / magnification, min(source.width, source.height) / 2)
            : 0
        let radius = ZoomCalloutContent(sourceRect: source, shape: shape)
            .effectiveCornerRadius(boxSize: source.size, styleRadius: scaledStyleRadius)
        let sourcePath = CGPath(roundedRect: source, cornerWidth: max(0, radius),
                                cornerHeight: max(0, radius), transform: nil)
        let lines = Geometry.leaderLines(source: source, calloutCorners: calloutCorners, shape: shape)

        // The band first, under everything: the line colour, faint, filling
        // the space between the two lines. Both shapes are cut out of it, so
        // it reaches their facing edges and never tints either picture.
        let fill = ZoomCalloutContent.clampedFillOpacity(fillOpacity)
        if fill > 0, lines.count == 2 {
            context.saveGState()
            context.addRect(bounds)
            context.addPath(sourcePath)
            context.clip(using: .evenOdd)
            if let box = calloutPath(corners: calloutCorners, style: style, shape: shape) {
                context.addRect(bounds)
                context.addPath(box)
                context.clip(using: .evenOdd)
            }
            context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b,
                                         alpha: rgba.a * opacity * fill))
            context.addLines(between: [lines[0].from, lines[0].to, lines[1].to, lines[1].from])
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }

        // Leader lines next (under the outline), translucent so they read as
        // connectors, not annotations.
        context.setStrokeColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b,
                                       alpha: rgba.a * opacity * 0.6))
        context.setLineWidth(outlineWidth)
        for line in lines {
            context.move(to: line.from)
            context.addLine(to: line.to)
            context.strokePath()
        }

        // Source outline, stroke centered on the region boundary.
        context.setStrokeColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b,
                                       alpha: rgba.a * opacity))
        context.setLineWidth(outlineWidth)
        context.addPath(sourcePath)
        context.strokePath()

        guard let image = context.makeImage() else { return nil }
        return (image, bounds.origin)
    }

    /// The callout box's own silhouette as it is drawn, turned with it: what
    /// the band is cut back to so it stops at the box's edge.
    static func calloutPath(corners: [CGPoint], style: LayerStyle,
                            shape: ZoomCalloutShape) -> CGPath? {
        guard let placed = Geometry.boxPlacement(corners: corners) else { return nil }
        let size = placed.size
        let radius = min(ZoomCalloutContent(sourceRect: .zero, shape: shape)
            .effectiveCornerRadius(boxSize: size, styleRadius: max(0, style.cornerRadius)),
                         min(size.width, size.height) / 2)
        var transform = placed.transform
        return CGPath(roundedRect: CGRect(origin: .zero, size: size),
                      cornerWidth: radius, cornerHeight: radius, transform: &transform)
    }
}
