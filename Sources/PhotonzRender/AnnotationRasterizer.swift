import CoreGraphics
import Foundation
import PhotonzCore

/// Rasterizes `AnnotationContent` into a transparent-background CGImage.
/// Drawing happens in the layer's local top-left coordinate space (the same
/// space `AnnotationContent.start`/`end` are stored in).
public enum AnnotationRasterizer {

    /// Draws `annotation` inside `size` (the layer's box, in document points).
    ///
    /// `scale` is how many pixels the result gets per document point, so a
    /// zoomed-in canvas can bake a stroke, an arrowhead and a caption pill at
    /// the resolution they are about to be seen at instead of blowing a
    /// document-sized picture of them up afterwards. It scales the DRAWING,
    /// never the geometry: the stroke width, the arrowhead and the pill are
    /// stated in the same points at every scale, so a shape does not move or
    /// change weight when a sharper copy of it arrives.
    public static func rasterize(_ annotation: AnnotationContent, size: CGSize,
                                 scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        // An outline that sits on or past the shape's edge needs somewhere to
        // be drawn, and the shape's own box is exactly the wrong size for it.
        // So the bitmap grows by that reach on EVERY side and the drawing
        // starts that far in: a symmetric pad, which is what lets the composite
        // go on centring the picture on the frame
        // (`DocumentRenderer.ciImage`, and `BorderPosition.swift`).
        let pad = annotation.strokeOutset
        let width = Int(((size.width + 2 * pad) * scale).rounded())
        let height = Int(((size.height + 2 * pad) * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Flip so the drawing code below works in top-left coordinates, and
        // scale so it can go on stating everything in document points.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        // ...and everything below goes on stating itself in the shape's own
        // box, unaware that the paper under it got bigger.
        if pad != 0 { context.translateBy(x: pad, y: pad) }

        // The ink's flat stand-in: what a caption pill is toned from, and what
        // a paint that is not a gradient draws with.
        let rgba = RGBA(hex: annotation.colorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        let ink = annotation.paint
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        // Rectangles join with miters so a thick stroke doesn't fake a corner
        // radius the inspector doesn't show — `cornerRadius` alone rounds them
        // (it curves the path itself). Open strokes keep soft round joins.
        let join: CGLineJoin = annotation.shape == .rectangle ? .miter : .round
        context.setLineJoin(join)

        /// Every outline in here goes through one call, so a gradient reaches
        /// a line, an arrow's shaft and a box's border by the same route.
        func strokeInk(_ path: CGPath, cap: CGLineCap = .round) {
            GradientPainter.stroke(path: path, with: ink, width: annotation.strokeWidth,
                                   lineJoin: join, lineCap: cap, in: context)
        }
        /// And so does every solid piece of ink: an arrowhead, a highlight.
        func fillInk(_ path: CGPath) {
            GradientPainter.fill(path: path, with: ink, in: context)
        }

        let box = CGRect(x: min(annotation.start.x, annotation.end.x),
                         y: min(annotation.start.y, annotation.end.y),
                         width: abs(annotation.end.x - annotation.start.x),
                         height: abs(annotation.end.y - annotation.start.y))

        switch annotation.shape {
        case .line:
            let path = CGMutablePath()
            path.move(to: annotation.start)
            path.addLine(to: annotation.end)
            strokeInk(path)

        case .arrow:
            let style = annotation.arrowheadStyle
            // Where the shaft stops depends on what it runs into: inside a
            // solid head, at the tip of an open one, on the near edge of a
            // hollow dot so the dot stays hollow.
            let shaftEnd = Geometry.arrowShaftEnd(start: annotation.start, end: annotation.end,
                                                  strokeWidth: annotation.strokeWidth,
                                                  scale: annotation.arrowheadScale, style: style)
            let shaft = CGMutablePath()
            shaft.move(to: annotation.start)
            shaft.addLine(to: shaftEnd)
            strokeInk(shaft)
            if let circle = Geometry.arrowheadCircle(at: annotation.end,
                                                     strokeWidth: annotation.strokeWidth,
                                                     scale: annotation.arrowheadScale, style: style) {
                let dot = CGPath(ellipseIn: CGRect(x: circle.center.x - circle.radius,
                                                   y: circle.center.y - circle.radius,
                                                   width: 2 * circle.radius,
                                                   height: 2 * circle.radius), transform: nil)
                if style == .dot { fillInk(dot) } else { strokeInk(dot) }
            } else {
                let head = Geometry.arrowhead(start: annotation.start, end: annotation.end,
                                              strokeWidth: annotation.strokeWidth,
                                              scale: annotation.arrowheadScale, style: style)
                if head.count == 3 {
                    let tip = CGMutablePath()
                    if style == .open {
                        // Two fine strokes through the tip, not a filled body:
                        // wing, tip, wing, left open at the back.
                        tip.move(to: head[1])
                        tip.addLine(to: head[0])
                        tip.addLine(to: head[2])
                        strokeInk(tip)
                    } else {
                        tip.addLines(between: head)
                        tip.closeSubpath()
                        fillInk(tip)
                    }
                }
            }
            if annotation.hasCaption {
                drawCaption(annotation, border: color, in: context)
            }

        case .rectangle:
            // The line the stroke rides: inset by half its width for an inside
            // outline (so the outline's outer edge lands on start..end, which
            // is what every shape drawn before there was a choice does), on the
            // box itself for a centred one, and half a width OUTSIDE it for an
            // outside one.
            let stroke = box.insetBy(dx: annotation.strokeWidth / 2 - pad,
                                     dy: annotation.strokeWidth / 2 - pad)
            let inside = fillBox(annotation, box: box, pad: pad)
            let path: CGPath
            let fillPath: CGPath
            if annotation.cornerRadius > 0, !stroke.isEmpty {
                // Round the stroke itself (clamped to a capsule at most), so the
                // border follows the corners rather than being clipped off.
                let radius = min(annotation.cornerRadius, min(stroke.width, stroke.height) / 2)
                path = CGPath(roundedRect: stroke, cornerWidth: radius,
                              cornerHeight: radius, transform: nil)
                fillPath = roundedFill(inside, sameShapeAs: stroke, radius: radius)
            } else {
                path = CGPath(rect: stroke, transform: nil)
                fillPath = CGPath(rect: inside, transform: nil)
            }
            if let fill = annotation.fill {
                GradientPainter.fill(path: fillPath, with: fill, in: context)
            }
            if annotation.strokeWidth > 0 { strokeInk(path) }   // 0 = no border (fill only)

        case .ellipse:
            let stroke = box.insetBy(dx: annotation.strokeWidth / 2 - pad,
                                     dy: annotation.strokeWidth / 2 - pad)
            let path = CGPath(ellipseIn: stroke, transform: nil)
            if let fill = annotation.fill {
                GradientPainter.fill(path: CGPath(ellipseIn: fillBox(annotation, box: box, pad: pad),
                                                  transform: nil),
                                     with: fill, in: context)
            }
            if annotation.strokeWidth > 0 { strokeInk(path) }   // 0 = no border

        case .highlight:
            // A filled box; the renderer composites it with multiply blend.
            fillInk(CGPath(rect: box, transform: nil))
        }

        return context.makeImage()
    }

    /// How far the inside of the shape is painted.
    ///
    /// For an INSIDE outline this is the stroke's own path, exactly as it has
    /// always been: the fill stops half a width short and the stroke covers the
    /// rest, so a translucent line never shows a seam. For a centred or an
    /// outside one the fill is the whole box, because the line no longer eats
    /// into it and a shape that kept the old inset would show a hairline of
    /// canvas between its fill and its line.
    private static func fillBox(_ annotation: AnnotationContent, box: CGRect,
                                pad: CGFloat) -> CGRect {
        let inset = max(0, annotation.strokeWidth / 2 - pad)
        return box.insetBy(dx: inset, dy: inset)
    }

    /// The fill's rounded path, curved so it sits concentric with the stroke
    /// rather than parallel to it: a corner half a width in from another corner
    /// is half a width tighter.
    private static func roundedFill(_ rect: CGRect, sameShapeAs stroke: CGRect,
                                    radius: CGFloat) -> CGPath {
        guard !rect.isEmpty else { return CGPath(rect: rect, transform: nil) }
        let difference = (rect.width - stroke.width) / 2
        let fillRadius = max(0, min(radius + difference, min(rect.width, rect.height) / 2))
        guard fillRadius > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: fillRadius,
                      cornerHeight: fillRadius, transform: nil)
    }

    /// JUST the caption pill, on its own transparent bitmap, for chrome that
    /// has to show a live label the composite cannot: the vector preview held
    /// over an endpoint drag draws the arrow but has no way to draw type, so
    /// the pill it shows is this bitmap, moved. Baked once at the start of a
    /// drag — the words and their size do not change while an endpoint moves,
    /// only where the pill lands.
    ///
    /// Returns the image and the bitmap's size in DOCUMENT POINTS. The pill is
    /// centred in it with `captionShadowPadding` of room all round, so the drop
    /// shadow is inside the picture rather than clipped at its edge.
    public static func captionPill(_ annotation: AnnotationContent,
                                   scale: CGFloat = 1) -> (image: CGImage, size: CGSize)? {
        guard annotation.hasCaption, scale > 0, scale.isFinite else { return nil }
        let text = CaptionMetrics.committedText(annotation.caption ?? "")
        guard !text.isEmpty else { return nil }
        let chip = CaptionMetrics.pillSize(for: text, in: annotation)
        let slack = AnnotationContent.captionShadowPadding
        let size = CGSize(width: chip.width + 2 * slack, height: chip.height + 2 * slack)
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let rgba = RGBA(hex: annotation.colorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let border = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        let tone = annotation.captionChipColor
        let fill = CGColor(srgbRed: tone.r, green: tone.g, blue: tone.b,
                           alpha: AnnotationContent.captionChipOpacity)
        PillRasterizer.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2),
                            chipSize: chip, fontSize: annotation.captionFontSize,
                            borderWidth: annotation.captionBorderWidth,
                            fill: fill, border: border,
                            textColorHex: AnnotationContent.captionTextColorHex,
                            shadow: PillRasterizer.Shadow(),
                            cornerRadius: annotation.captionCornerRadius(pillHeight: chip.height),
                            in: context)
        return context.makeImage().map { ($0, size) }
    }

    /// The caption pill at the arrow's tail: the measure chip's legibility
    /// treatment (dark tone of the arrow's ink, white text, bordered capsule)
    /// plus a soft drop shadow so the label reads over any screenshot. Baked
    /// into the layer raster like the measure chip, so exports carry it and
    /// layer effects reach it. Every number here comes off `AnnotationContent`,
    /// because the on-canvas caption field draws the same bubble from the same
    /// values: what you type in is what lands.
    private static func drawCaption(_ annotation: AnnotationContent, border: CGColor,
                                    in context: CGContext) {
        let text = CaptionMetrics.committedText(annotation.caption ?? "")
        guard !text.isEmpty else { return }
        let chipSize = CaptionMetrics.pillSize(for: text, in: annotation)
        let tone = annotation.captionChipColor
        let fill = CGColor(srgbRed: tone.r, green: tone.g, blue: tone.b,
                           alpha: AnnotationContent.captionChipOpacity)
        // Hung from the attachment at the arrow's tail, measured pill and all:
        // a longer caption reaches further away from the arrow instead of
        // sliding the whole bubble off it.
        let center = annotation.captionPillCenter(forPillSize: chipSize)
        PillRasterizer.draw(text, at: center, chipSize: chipSize,
                            fontSize: annotation.captionFontSize,
                            borderWidth: annotation.captionBorderWidth,
                            fill: fill, border: border,
                            textColorHex: AnnotationContent.captionTextColorHex,
                            shadow: PillRasterizer.Shadow(),
                            cornerRadius: annotation.captionCornerRadius(pillHeight: chipSize.height),
                            in: context)
    }
}
