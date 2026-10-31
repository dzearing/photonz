import CoreGraphics
import Foundation
import PhotonzCore

/// Draws a caption's chip in one of the ten chip styles (`ChipStyle.swift`):
/// its shadows, plate, tab, swipe, inner light, rim, edge, accent, marker and
/// words, in that order, from a `ChipLook` that already knows every colour.
///
/// The same drawing serves the canvas, the export and the style tiles, so a
/// chip is pixel for pixel the same wherever it shows. Glass is drawn as a
/// see-through plate with a lit rim rather than a live blur of the picture,
/// because the layer is rasterised on its own and an export has to match it.
enum ChipRasterizer {

    /// Draws the chip centred at `anchor`.
    ///
    /// `edgeWidth` overrides the style's own edge width; the Today style passes
    /// the caption's arrow-matched border width, exactly as the old pill drew.
    static func draw(_ string: String, look: ChipLook, at anchor: CGPoint, chipSize: CGSize,
                     fontSize: CGFloat, padding: CGFloat, fontName: String,
                     typeSize: CGFloat? = nil, weight: TextWeight = .semibold,
                     cornerRadius: CGFloat, edgeWidth: CGFloat? = nil,
                     in context: CGContext) {
        let ppp = PillRasterizer.pixelsPerPoint(of: context)
        let u = ChipLook.unit(fontSize: fontSize)
        let rect = CGRect(x: anchor.x - chipSize.width / 2, y: anchor.y - chipSize.height / 2,
                          width: chipSize.width, height: chipSize.height)
        let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
        let plate = look.continuousCorners
            ? continuousRoundedRect(rect, radius: radius)
            : CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let layout = look.layout(in: rect, fontSize: fontSize, padding: padding)

        // Shadows and ring sit outside the plate, under it.
        if let solidish = look.fillTop ?? look.fillBottom {
            for shadow in look.shadows {
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -shadow.y * u * ppp),
                                  blur: shadow.blur * u * ppp,
                                  color: CGColor(gray: 0, alpha: shadow.alpha))
                context.setFillColor(cg(solidish, alpha: max(solidish.a, 0.01)))
                context.addPath(plate)
                context.fillPath()
                context.restoreGState()
            }
        }
        if look.ringAlpha > 0 {
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 0, alpha: look.ringAlpha))
            context.setLineWidth(1 * u)
            context.addPath(plate)
            context.strokePath()
            context.restoreGState()
        }

        // The plate.
        context.saveGState()
        context.addPath(plate)
        context.clip()
        if let top = look.fillTop, let bottom = look.fillBottom {
            // Cleared first so a see-through plate shows the picture, not its
            // own shadow, through itself.
            if top.a < 1 || bottom.a < 1 { context.clear(rect.insetBy(dx: -1, dy: -1)) }
            if top == bottom {
                context.setFillColor(cg(top))
                context.fill(rect)
            } else if let gradient = CGGradient(colorsSpace: sRGB, colors: [cg(top), cg(bottom)] as CFArray,
                                                locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                                           end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
            }
        }
        if let tab = layout.tab, let colour = look.tab {
            context.setFillColor(cg(colour))
            context.fill(tab)
        }
        if let swipe = layout.swipe, let colour = look.swipe, let first = swipe.first {
            context.setFillColor(cg(colour))
            context.move(to: first)
            for point in swipe.dropFirst() { context.addLine(to: point) }
            context.closePath()
            context.fillPath()
        }
        if look.innerHighlight > 0 {
            // A one pixel band of light along the top, following the corners:
            // the plate less itself moved down a pixel.
            context.setFillColor(CGColor(gray: 1, alpha: look.innerHighlight))
            context.addPath(plate)
            var down = CGAffineTransform(translationX: 0, y: max(1 * u, 1 / ppp))
            if let moved = plate.copy(using: &down) { context.addPath(moved) }
            context.fillPath(using: .evenOdd)
        }
        if let rim = look.rim {
            context.addPath(plate)
            context.setLineWidth(2 * u)
            context.replacePathWithStrokedPath()
            context.clip()
            let stops: [(CGFloat, Double)] = rim.diagonal
                ? [(0, rim.start), (0.35, 0.14), (0.55, 0), (0.8, 0.2), (1, rim.end)]
                : [(0, rim.start), (0.6, 0.10), (1, rim.end)]
            if let gradient = CGGradient(colorsSpace: sRGB,
                                         colors: stops.map { CGColor(gray: 1, alpha: $0.1) } as CFArray,
                                         locations: stops.map(\.0)) {
                let end = rim.diagonal ? CGPoint(x: rect.maxX, y: rect.maxY) : CGPoint(x: rect.minX, y: rect.maxY)
                context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: end,
                                           options: [])
            }
        }
        context.restoreGState()

        // The edge.
        if let edge = look.edge {
            let width = edgeWidth ?? look.edgeWidth * u
            if width > 0 {
                context.saveGState()
                context.setStrokeColor(cg(edge))
                context.setLineWidth(width)
                context.addPath(plate)
                context.strokePath()
                context.restoreGState()
            }
        }

        // The accent and the marker.
        if let stripe = layout.stripe, case .stripe(let colour)? = look.accent {
            context.setFillColor(cg(colour))
            context.addPath(CGPath(roundedRect: stripe, cornerWidth: stripe.width / 2,
                                   cornerHeight: stripe.width / 2, transform: nil))
            context.fillPath()
        }
        if let dot = layout.dot, case .dot(let colour)? = look.accent {
            context.setFillColor(cg(colour))
            context.fillEllipse(in: dot)
        }
        if let box = layout.icon, let marker = look.marker {
            drawMarker(marker, in: box, context: context)
        }

        // The words.
        let hex = look.text.hexString
        let text = PillRasterizer.content(string, fontSize: typeSize ?? fontSize, colorHex: hex,
                                          fontName: fontName, weight: weight)
        let textSize = TextRasterizer.naturalSize(text)
        guard let glyphs = TextRasterizer.rasterize(text, size: textSize, scale: ppp) else { return }
        let inkOffset = (TextRasterizer.inkOffset(text) * ppp).rounded() / ppp
        let x = ((layout.wordsCenterX - textSize.width / 2 - inkOffset) * ppp).rounded() / ppp
        let textRect = CGRect(x: x, y: anchor.y - textSize.height / 2,
                              width: textSize.width, height: textSize.height)
        context.saveGState()
        if look.textShadow {
            context.setShadow(offset: CGSize(width: 0, height: -1 * u * ppp),
                              blur: (look.textShadowIsLight ? 1 : 2) * u * ppp,
                              color: look.textShadowIsLight ? CGColor(gray: 1, alpha: 0.35)
                                  : CGColor(gray: 0, alpha: 0.45))
        }
        context.translateBy(x: textRect.minX, y: textRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(glyphs, in: CGRect(origin: .zero, size: textRect.size))
        context.restoreGState()
    }

    // MARK: Pieces

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func cg(_ c: RGBA, alpha: Double? = nil) -> CGColor {
        CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha ?? c.a)
    }

    /// A rounded rectangle whose corners ease into the sides instead of
    /// meeting them at a circle's end, the way the Mac's own squircles do.
    static func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard radius > 0 else {
            path.addRect(rect)
            return path
        }
        // The curve starts further along each side than a circle's would and
        // pulls in tighter at the corner itself.
        let reach = min(radius * 1.28, min(rect.width, rect.height) / 2)
        let pull = reach * 0.36
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        path.move(to: CGPoint(x: x0 + reach, y: y0))
        path.addLine(to: CGPoint(x: x1 - reach, y: y0))
        path.addCurve(to: CGPoint(x: x1, y: y0 + reach), control1: CGPoint(x: x1 - pull, y: y0),
                      control2: CGPoint(x: x1, y: y0 + pull))
        path.addLine(to: CGPoint(x: x1, y: y1 - reach))
        path.addCurve(to: CGPoint(x: x1 - reach, y: y1), control1: CGPoint(x: x1, y: y1 - pull),
                      control2: CGPoint(x: x1 - pull, y: y1))
        path.addLine(to: CGPoint(x: x0 + reach, y: y1))
        path.addCurve(to: CGPoint(x: x0, y: y1 - reach), control1: CGPoint(x: x0 + pull, y: y1),
                      control2: CGPoint(x: x0, y: y1 - pull))
        path.addLine(to: CGPoint(x: x0, y: y0 + reach))
        path.addCurve(to: CGPoint(x: x0 + reach, y: y0), control1: CGPoint(x: x0, y: y0 + pull),
                      control2: CGPoint(x: x0 + pull, y: y0))
        path.closeSubpath()
        return path
    }

    /// A status icon drawn into `box`, from the design system's 20 by 20
    /// drawings (`markup.js` `icon`).
    private static func drawMarker(_ marker: ChipLook.Marker, in box: CGRect, context: CGContext) {
        let s = box.width / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * s, y: box.minY + y * s) }
        context.saveGState()
        context.setFillColor(cg(marker.disc))
        if marker.kind == .warning {
            context.setStrokeColor(cg(marker.disc))
            context.setLineWidth(1.6 * s)
            context.setLineJoin(.round)
            context.move(to: p(10, 2.2))
            context.addLine(to: p(18.4, 17.2))
            context.addLine(to: p(1.6, 17.2))
            context.closePath()
            context.drawPath(using: .fillStroke)
        } else {
            context.fillEllipse(in: CGRect(origin: p(1, 1), size: CGSize(width: 18 * s, height: 18 * s)))
        }
        context.setStrokeColor(cg(marker.glyph))
        context.setFillColor(cg(marker.glyph))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch marker.kind {
        case .error:
            context.setLineWidth(2.2 * s)
            context.move(to: p(6.6, 6.6)); context.addLine(to: p(13.4, 13.4))
            context.move(to: p(13.4, 6.6)); context.addLine(to: p(6.6, 13.4))
            context.strokePath()
        case .success:
            context.setLineWidth(2.2 * s)
            context.move(to: p(5.7, 10.4)); context.addLine(to: p(8.7, 13.3)); context.addLine(to: p(14.4, 7.3))
            context.strokePath()
        case .info:
            context.setLineWidth(2.2 * s)
            context.move(to: p(10, 9.2)); context.addLine(to: p(10, 14.3))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: p(10, 6.2).x - 1.35 * s, y: p(10, 6.2).y - 1.35 * s,
                                           width: 2.7 * s, height: 2.7 * s))
        case .warning:
            context.setLineWidth(2.1 * s)
            context.move(to: p(10, 7.6)); context.addLine(to: p(10, 11.6))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: p(10, 14.4).x - 1.25 * s, y: p(10, 14.4).y - 1.25 * s,
                                           width: 2.5 * s, height: 2.5 * s))
        case .none, .accent:
            break
        }
        context.restoreGState()
    }
}
