import CoreGraphics
import Foundation
import PhotonzCore

/// The ONE place a `Paint` becomes pixels.
///
/// A shape's inside, a shape's outline and a screen's surface all go through
/// here, so a gradient looks the same wherever it is painted and there is one
/// place to fix when it does not. Everything draws in the layer's own top-left
/// space, which is the space the rasterizers already work in.
///
/// Core Graphics knows how to draw the straight and the spreading kinds. It has
/// no sweep at all, so the sweeping one is worked out a pixel at a time from
/// the angle each pixel sits at.
public enum GradientPainter {

    /// Fills `path` with `paint`, whatever kind it is. Flat paints take the
    /// plain fill they always did, so nothing that never asked for a gradient
    /// pays for one.
    public static func fill(path: CGPath, with paint: Paint, in context: CGContext) {
        guard paint.isGradient else {
            guard let rgba = RGBA(hex: paint.hex) else { return }
            context.setFillColor(cgColor(rgba))
            context.addPath(path)
            context.fillPath()
            return
        }
        context.saveGState()
        context.addPath(path)
        context.clip()
        draw(paint, in: path.boundingBoxOfPath, in: context)
        context.restoreGState()
    }

    /// Strokes `path` with `paint`. A gradient outline is the ramp poured
    /// through the stroke's own shape, which is why the line width and the
    /// joins still come off the shape rather than being approximated.
    public static func stroke(path: CGPath, with paint: Paint, width: CGFloat,
                              lineJoin: CGLineJoin, lineCap: CGLineCap,
                              in context: CGContext) {
        guard width > 0 else { return }
        guard paint.isGradient else {
            guard let rgba = RGBA(hex: paint.hex) else { return }
            context.setStrokeColor(cgColor(rgba))
            context.setLineWidth(width)
            context.addPath(path)
            context.strokePath()
            return
        }
        context.saveGState()
        context.setLineWidth(width)
        context.setLineJoin(lineJoin)
        context.setLineCap(lineCap)
        context.addPath(path)
        // Turns the pen stroke into an outline the ramp can be poured into.
        context.replacePathWithStrokedPath()
        let outline = context.path?.boundingBoxOfPath ?? path.boundingBoxOfPath
        context.clip()
        draw(paint, in: outline, in: context)
        context.restoreGState()
    }

    /// A gradient as its own image, for the places that composite pictures
    /// rather than draw paths — a frame's surface, and the picker's previews.
    /// Nil for a flat paint, which has an easier way to be a color.
    public static func image(_ paint: Paint, size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard paint.isGradient, width >= 1, height >= 1,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Flip, so the gradient is aimed in the same top-left space every
        // rasterizer draws in.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(paint, in: CGRect(origin: .zero, size: CGSize(width: CGFloat(width),
                                                          height: CGFloat(height))),
             in: context)
        return context.makeImage()
    }

    // MARK: - Laying the ramp down

    /// Draws `paint` across `box`, inside whatever clip the caller set up.
    private static func draw(_ paint: Paint, in box: CGRect, in context: CGContext) {
        guard !box.isEmpty, let gradient = gradient(for: paint) else { return }
        switch paint.kind {
        case .solid:
            return
        case .linear:
            let ends = paint.linearEnds(in: box)
            context.drawLinearGradient(gradient, start: ends.start, end: ends.end,
                                       options: [.drawsBeforeStartLocation,
                                                 .drawsAfterEndLocation])
        case .radial:
            let middle = paint.centerPoint(in: box)
            context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0,
                                       endCenter: middle,
                                       endRadius: paint.radialRadius(in: box),
                                       options: [.drawsBeforeStartLocation,
                                                 .drawsAfterEndLocation])
        case .angular:
            drawSweep(paint, in: box, in: context)
        }
    }

    /// The sweep, drawn a pixel at a time.
    ///
    /// Core Graphics has no sweep of its own, and a fan of wedges — the obvious
    /// stand-in — leaves faint rings where the wedges meet, which showed up the
    /// first time a swept box was looked at full size. Asking each pixel what
    /// angle it is at has no seams to leave, and a shape's raster is small
    /// enough that the loop costs nothing worth measuring.
    private static func drawSweep(_ paint: Paint, in box: CGRect, in context: CGContext) {
        guard let image = sweepImage(paint, size: box.size) else { return }
        // The context is flipped into top-left space and so is the image, so
        // the two cancel out with one local flip over the box.
        context.saveGState()
        context.translateBy(x: 0, y: box.minY + box.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: box)
        context.restoreGState()
    }

    /// The sweep as its own picture, in top-left space: row 0 is the top.
    private static func sweepImage(_ paint: Paint, size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        // The ramp, sampled once into a table, so the per-pixel work is a
        // lookup rather than a walk down the stops.
        let steps = 1024
        var table = [UInt8](repeating: 0, count: steps * 4)
        for step in 0..<steps {
            guard let rgba = paint.color(at: Double(step) / Double(steps - 1)) else { continue }
            let alpha = min(max(rgba.a, 0), 1)
            // Premultiplied, which is what the bitmap below is.
            table[step * 4] = byte(rgba.r * alpha)
            table[step * 4 + 1] = byte(rgba.g * alpha)
            table[step * 4 + 2] = byte(rgba.b * alpha)
            table[step * 4 + 3] = byte(alpha)
        }

        let cx = size.width * paint.center.x, cy = size.height * paint.center.y
        let start = paint.angle * .pi / 180
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let dy = Double(y) + 0.5 - cy
            for x in 0..<width {
                let dx = Double(x) + 0.5 - cx
                // Zero degrees points at the top of the box, which is up the
                // screen and so DOWN the y axis here; the sweep runs clockwise.
                var turn = (atan2(dx, -dy) - start) / (2 * .pi)
                turn -= turn.rounded(.down)
                let step = min(Int(turn * Double(steps)), steps - 1)
                let to = (y * width + x) * 4, from = step * 4
                pixels[to] = table[from]
                pixels[to + 1] = table[from + 1]
                pixels[to + 2] = table[from + 2]
                pixels[to + 3] = table[from + 3]
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    private static func gradient(for paint: Paint) -> CGGradient? {
        let stops = paint.orderedStops.compactMap { stop -> (CGFloat, RGBA)? in
            guard let rgba = RGBA(hex: stop.hex) else { return nil }
            return (CGFloat(stop.position), rgba)
        }
        guard stops.count >= 2 else { return nil }
        let colors = stops.map { cgColor($0.1) } as CFArray
        var locations = stops.map(\.0)
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                          locations: &locations)
    }

    private static func cgColor(_ rgba: RGBA) -> CGColor {
        CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}
