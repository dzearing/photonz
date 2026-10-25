import CoreGraphics
import Foundation
import PhotonzCore

/// Oil paint's numbers, read off rendered strokes the way `PaintMeasures`
/// reads the other media's (`OilRenderingTests`, the oil sheet in the audit).
extension PaintMeasures {

    /// Oil paint's bars, read off straight strokes at Size 24, 2x
    /// (`OilRenderingTests`). Inside a stroke the bristles leave ridges and
    /// grooves, lit, so the lightness across its core varies by at least this
    /// much (`ridgeContrast`); the plain round is one flat colour there, 0...
    public static let oilRidgeBar = 0.025
    /// ...and a stroke dragged across an earlier one carries at least this
    /// share of the earlier colour on past it, over the two brush widths after
    /// it leaves the earlier stroke (`carriedShare`); the plain round lays only
    /// its own colour there, 0.
    public static let oilCarryBar = 0.1

    /// How much the lightness varies across a stroke's core: across short
    /// stretches of its middle length (`stretch` points long, averaged along,
    /// so only marks that run WITH the stroke survive), the standard
    /// deviation of lightness over the middle 60 per cent of its width, as if
    /// on white paper. The median of those.
    public static func ridgeContrast(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                     scale: CGFloat, stretch: CGFloat? = nil) -> Double {
        guard let plane = ColourPlane(image) else { return 0 }
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0, diameter > 0, scale > 0 else { return 0 }
        let along = CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let step = 1 / scale
        let core = Int((diameter / 2 * 0.6 * scale).rounded(.down))
        let run = max(1, Int(((stretch ?? diameter / 2) * scale).rounded()))
        var spreads: [Double] = []
        var t = length * 0.15
        while t + CGFloat(run) * step <= length * 0.85 {
            var profile: [Double] = []
            for j in -core...core {
                var sum = 0.0
                for i in 0..<run {
                    let d = t + CGFloat(i) * step, s = CGFloat(j) * step
                    let p = CGPoint(x: a.x + along.dx * d + across.dx * s, y: a.y + along.dy * d + across.dy * s)
                    sum += plane.lightnessOnWhite(at: p, scale: scale)
                }
                profile.append(sum / Double(run))
            }
            let mean = profile.reduce(0, +) / Double(profile.count)
            let variance = profile.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(profile.count)
            spreads.append(variance.squareRoot())
            t += CGFloat(run) * step
        }
        guard !spreads.isEmpty else { return 0 }
        return spreads.sorted()[spreads.count / 2]
    }

    /// How much of `foreign` a stroke from `a` to `b` carries between `start`
    /// and `end` points along it: over its core (the middle half of its
    /// width), where it covers at least a quarter, each pixel's colour placed
    /// on the line from `own` (0) to `foreign` (1), averaged. Colours are
    /// compared by their proportions (each channel over their sum), so the
    /// light and shade on the paint's ridges are not read as another colour.
    /// A stroke that lays only its own colour there reads 0.
    public static func carriedShare(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                    scale: CGFloat, own: RGBA, foreign: RGBA,
                                    start: CGFloat, end: CGFloat) -> Double {
        guard let plane = ColourPlane(image) else { return 0 }
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0, diameter > 0, scale > 0, end > start else { return 0 }
        let along = CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let own = proportions(own), foreign = proportions(foreign)
        let dr = foreign.r - own.r, dg = foreign.g - own.g, db = foreign.b - own.b
        let span = dr * dr + dg * dg + db * db
        guard span > 0 else { return 0 }
        let step = 1 / scale
        let core = Int((diameter / 4 * scale).rounded(.down))
        var total = 0.0, count = 0
        var d = start
        while d <= end {
            for j in -core...core {
                let s = CGFloat(j) * step
                let p = CGPoint(x: a.x + along.dx * d + across.dx * s, y: a.y + along.dy * d + across.dy * s)
                guard let found = plane.colour(at: p, scale: scale), found.a >= 0.25 else { continue }
                let c = proportions(found)
                let t = ((c.r - own.r) * dr + (c.g - own.g) * dg + (c.b - own.b) * db) / span
                total += min(1, max(0, t))
                count += 1
            }
            d += step
        }
        return count == 0 ? 0 : total / Double(count)
    }

    private static func proportions(_ c: RGBA) -> RGBA {
        let sum = max(c.r + c.g + c.b, 0.001)
        return RGBA(r: c.r / sum, g: c.g / sum, b: c.b / sum, a: c.a)
    }

    /// How far along a stroke from `a` to `b` it still covers its core: the
    /// distance, in points from `a`, at which the mean coverage over the
    /// middle half of its width, in windows half a radius long, first falls
    /// under a half. The whole length when it never does.
    public static func reachBeforeDry(_ image: CGImage, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                                      scale: CGFloat) -> Double {
        guard let plane = ColourPlane(image) else { return 0 }
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0, diameter > 0, scale > 0 else { return 0 }
        let along = CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
        let across = CGVector(dx: -along.dy, dy: along.dx)
        let step = 1 / scale
        let core = Int((diameter / 4 * scale).rounded(.down))
        let window = diameter / 4
        var d = diameter / 2
        while d + window <= length {
            var sum = 0.0, count = 0
            var e = d
            while e < d + window {
                for j in -core...core {
                    let s = CGFloat(j) * step
                    let p = CGPoint(x: a.x + along.dx * e + across.dx * s, y: a.y + along.dy * e + across.dy * s)
                    sum += plane.colour(at: p, scale: scale)?.a ?? 0
                    count += 1
                }
                e += step
            }
            if count > 0, sum / Double(count) < 0.5 { return Double(d) }
            d += window
        }
        return Double(length)
    }

    /// An image's pixels, unpremultiplied, read at points.
    private struct ColourPlane {
        let data: [UInt8]
        let width: Int
        let height: Int

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            data = bytes
        }

        private func offset(_ p: CGPoint, _ scale: CGFloat) -> Int? {
            let x = Int((p.x * scale).rounded(.down)), y = Int((p.y * scale).rounded(.down))
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return (y * width + x) * 4
        }

        func colour(at p: CGPoint, scale: CGFloat) -> RGBA? {
            guard let o = offset(p, scale) else { return nil }
            let a = Double(data[o + 3]) / 255
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            return RGBA(r: Double(data[o]) / 255 / a, g: Double(data[o + 1]) / 255 / a,
                        b: Double(data[o + 2]) / 255 / a, a: a)
        }

        /// Lightness (Rec. 709 weights on the sRGB values) of the pixel laid
        /// over white.
        func lightnessOnWhite(at p: CGPoint, scale: CGFloat) -> Double {
            guard let o = offset(p, scale) else { return 1 }
            let keep = 1 - Double(data[o + 3]) / 255
            let r = Double(data[o]) / 255 + keep, g = Double(data[o + 1]) / 255 + keep
            let b = Double(data[o + 2]) / 255 + keep
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
    }
}
