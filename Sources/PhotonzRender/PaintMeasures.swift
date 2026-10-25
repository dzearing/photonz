import CoreGraphics
import Foundation

/// Numbers read off a rendered straight stroke, so how a medium LOOKS is
/// measured rather than asserted (`docs/design/brushes.md`): the tests and the
/// stroke sheet in the audit read the same ones.
///
/// Each takes the picture, the stroke's two ends and its tip size in points,
/// and how many pixels a point is. The ends are kept out of every reading.
public enum PaintMeasures {

    /// The bar a dry medium's stroke must clear on `interiorGapFraction`, set
    /// where the foundation slice's soft round tip (0 per cent) fails it and
    /// all three dry media at their defaults pass it.
    public static let dryMediaGapBar = 0.12

    /// The share of the stroke's core (within a third of its radius of the
    /// line) that the paper left bare: pixels under half of the core's
    /// strongest coverage. A soft round tip covers its core solidly and
    /// scores 0; a medium that catches on a grain leaves the valleys open.
    public static func interiorGapFraction(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                           diameter: CGFloat, scale: CGFloat) -> Double {
        let core = samples(image, from: a, to: b, diameter: diameter, scale: scale)
            .filter { $0.across <= 1.0 / 3.0 }.map(\.alpha)
        guard !core.isEmpty else { return 0 }
        let strongest = core.sorted()[Int(Double(core.count - 1) * 0.95)]
        guard strongest > 0 else { return 0 }
        return Double(core.filter { $0 < strongest / 2 }.count) / Double(core.count)
    }

    /// How much of the radius the stroke takes to fade from strong to faint:
    /// the distance, as a fraction of the radius, between where the averaged
    /// coverage across the stroke drops to 80 per cent of its core and to 20
    /// per cent. Charcoal fades over much of its width; crayon stops at a line.
    public static func edgeSoftness(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                    diameter: CGFloat, scale: CGFloat) -> Double {
        let bins = 32
        var sum = [Double](repeating: 0, count: bins), count = [Int](repeating: 0, count: bins)
        for s in samples(image, from: a, to: b, diameter: diameter, scale: scale) {
            let bin = Int(s.across / 1.6 * Double(bins))
            guard bin < bins else { continue }
            sum[bin] += s.alpha
            count[bin] += 1
        }
        // Bins no pixel fell in (a thin stroke at 1x) are left out.
        var profile: [(at: Double, alpha: Double)] = []
        for k in 0..<bins where count[k] > 0 {
            let at = (Double(k) + 0.5) / Double(bins) * 1.6
            profile.append((at: at, alpha: sum[k] / Double(count[k])))
        }
        let core: [Double] = profile.filter { $0.at <= 0.25 }.map { $0.alpha }
        guard !core.isEmpty else { return 0 }
        let top = core.reduce(0, +) / Double(core.count)
        guard top > 0 else { return 0 }
        func crossing(_ level: Double) -> Double {
            profile.first { $0.alpha < top * level }?.at ?? 1.6
        }
        return crossing(0.2) - crossing(0.8)
    }

    /// The average coverage of the stroke's core, 0...1.
    public static func meanCoreAlpha(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                     diameter: CGFloat, scale: CGFloat) -> Double {
        let core = samples(image, from: a, to: b, diameter: diameter, scale: scale)
            .filter { $0.across <= 1.0 / 3.0 }.map(\.alpha)
        guard !core.isEmpty else { return 0 }
        return core.reduce(0, +) / Double(core.count)
    }

    /// Every pixel alongside the stroke's middle stretch: its coverage, and
    /// how far it is from the line as a fraction of the radius.
    private static func samples(_ image: CGImage, from a: CGPoint, to b: CGPoint,
                                diameter: CGFloat, scale: CGFloat) -> [(alpha: Double, across: Double)] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0, diameter > 0 else { return [] }
        let radius = diameter / 2
        var out: [(Double, Double)] = []
        for y in 0..<height {
            for x in 0..<width {
                let p = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (length * length)
                guard t >= 0.1, t <= 0.9 else { continue }
                let across = abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length / radius
                guard across <= 1.6 else { continue }
                out.append((Double(data[(y * width + x) * 4 + 3]) / 255, Double(across)))
            }
        }
        return out
    }
}
