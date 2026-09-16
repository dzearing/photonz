import CoreGraphics
import Foundation
import PhotonzCore

/// Draws a `PathContent` into a transparent-background CGImage.
///
/// Drawing happens in the layer's own top-left coordinate space, the space the
/// anchors are stored in, exactly like `AnnotationRasterizer`. This is the ONLY
/// place a path becomes pixels: the model itself knows nothing about drawing.
public enum PathRasterizer {

    /// Draws `content` inside `size` (the layer's box, in document points).
    ///
    /// `scale` is how many pixels the result gets per document point, so a
    /// zoomed-in canvas can bake the shape at the resolution it is about to be
    /// seen at. It scales the DRAWING and never the geometry: the line width
    /// is stated in the same points at every scale, so a sharper copy of a
    /// shape is the same shape.
    public static func rasterize(_ content: PathContent, size: CGSize,
                                 scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite, content.anchors.count >= 2 else { return nil }
        // A line that sits on or past the shape's edge needs somewhere to be
        // drawn, so the bitmap grows by that reach on EVERY side and the
        // drawing starts that far in: a symmetric pad, which is what lets the
        // composite go on centring the picture on the frame
        // (`DocumentRenderer.ciImage`, and `BorderPosition.swift`).
        let pad = content.strokeOutset
        let width = Int(((size.width + 2 * pad) * scale).rounded())
        let height = Int(((size.height + 2 * pad) * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Flip so the drawing below works in top-left coordinates, scale so it
        // can go on stating everything in document points, and shift so it can
        // go on stating itself in the shape's own box.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        if pad != 0 { context.translateBy(x: pad, y: pad) }

        let shape = cgPath(content)
        let rule: CGPathFillRule = content.fillRule == .evenOdd ? .evenOdd : .winding

        // The inside first, the edge over it: a line straddling the outline has
        // to sit ON the fill rather than under it, which is what every drawing
        // app does and what makes an inside line read as inset.
        if content.paintsAnInside, let fill = content.fill {
            paint(fill, inside: shape, rule: rule, in: context)
        }
        strokeEdge(content, shape: shape, rule: rule, size: size, in: context)
        return context.makeImage()
    }

    /// The outline as a CGPath, in the layer's own coordinates. The model
    /// itself answers this now (`PathContent.cgPath`), because an area
    /// operation needs the same path and lives in PhotonzCore.
    public static func cgPath(_ content: PathContent) -> CGPath { content.cgPath }

    // MARK: - The two paints

    private static func paint(_ fill: Paint, inside shape: CGPath, rule: CGPathFillRule,
                              in context: CGContext) {
        // A flat fill is filled outright, which is one call and the cleanest
        // edge there is. A ramp is poured through the shape, which needs the
        // shape as a clip — and the clip has to honour the fill rule, or a
        // gradient icon would lose the hole a flat one keeps.
        if !fill.isGradient, let rgba = RGBA(hex: fill.hex) {
            context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g,
                                         blue: rgba.b, alpha: rgba.a))
            context.addPath(shape)
            context.fillPath(using: rule)
            return
        }
        context.saveGState()
        context.addPath(shape)
        context.clip(using: rule)
        GradientPainter.fill(path: CGPath(rect: shape.boundingBoxOfPath, transform: nil),
                             with: fill, in: context)
        context.restoreGState()
    }

    private static func strokeEdge(_ content: PathContent, shape: CGPath, rule: CGPathFillRule,
                                   size: CGSize, in context: CGContext) {
        let width = content.strokeWidth
        guard width > 0 else { return }
        // What KIND of line this is, which the shape itself now answers
        // (`PathLineStyle.swift`). The defaults are what the rasterizer always
        // drew: corners carried out to a point, because a corner anchor exists
        // to be sharp and a round join would quietly curve every one of them,
        // and round ends, which is what every other stroke in the app ends in.
        let join = content.lineCorner.lineJoin
        let cap = content.lineEnd.lineCap
        // The dashes are measured off the width the line is WORN at, never the
        // doubled width an inside or outside line is drawn with below: doubling
        // the pattern too would make an inside dashed line's dashes twice as
        // long as a centred one's.
        let dash = content.dashPattern

        switch content.effectiveStrokePosition {
        case .center:
            GradientPainter.stroke(path: shape, with: content.paint, width: width,
                                   lineJoin: join, lineCap: cap, dash: dash,
                                   miterLimit: pathMiterLimit, in: context)
        case .inside, .outside:
            // There is no such thing as a path inset by half a line width when
            // the path is an arbitrary outline, so the line is drawn DOUBLE
            // width and the half that should not be there is clipped off. The
            // survivor is exactly a line of `width` on the chosen side, and it
            // follows every curve for free.
            context.saveGState()
            if content.effectiveStrokePosition == .inside {
                context.addPath(shape)
                context.clip(using: rule)
            } else {
                // Everything the shape does NOT cover: the whole sheet with the
                // shape punched out of it. Generous enough to cover the line's
                // full reach past the box.
                let sheet = CGRect(x: -width * 2, y: -width * 2,
                                   width: size.width + width * 4,
                                   height: size.height + width * 4)
                let punched = CGMutablePath()
                punched.addRect(sheet)
                punched.addPath(shape)
                context.addPath(punched)
                // Even-odd whatever the shape's own rule is: one rectangle with
                // one outline inside it, so odd crossings are exactly the space
                // outside the shape.
                context.clip(using: .evenOdd)
            }
            GradientPainter.stroke(path: shape, with: content.paint, width: width * 2,
                                   lineJoin: join, lineCap: cap, dash: dash,
                                   miterLimit: pathMiterLimit, in: context)
            context.restoreGState()
        }
    }
}
