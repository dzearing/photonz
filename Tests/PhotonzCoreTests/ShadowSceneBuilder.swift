import CoreGraphics
import Foundation
import PhotonzCore

/// A small painted scene, built pixel by pixel, so a test can say exactly what
/// a shadow was drawn with and then ask what the app reads back off it.
///
/// The shadow is drawn the way every renderer draws one: the caster's coverage
/// mask, blurred by a gaussian of a known sigma, shifted by a known offset,
/// multiplied by a known opacity, composited under the caster. That makes the
/// numbers in the test the GROUND TRUTH rather than another implementation of
/// the same guess.
struct ShadowScene {
    let width: Int
    let height: Int
    private(set) var samples: [UInt8]

    init(width: Int, height: Int, page: (Double, Double, Double)) {
        self.width = width
        self.height = height
        self.samples = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: samples.count, by: 4) {
            samples[i] = UInt8(page.0.rounded())
            samples[i + 1] = UInt8(page.1.rounded())
            samples[i + 2] = UInt8(page.2.rounded())
            samples[i + 3] = 255
        }
    }

    var field: PixelField { PixelField(width: width, height: height, samples: samples) }

    /// How much of the pixel at (x, y) a rounded rectangle covers, 0…1.
    static func coverage(_ rect: CGRect, radius: Double, _ x: Int, _ y: Int) -> Double {
        let r = min(radius, min(Double(rect.width), Double(rect.height)) / 2)
        let hx = Double(rect.width) / 2 - r, hy = Double(rect.height) / 2 - r
        let ax = abs(Double(x) + 0.5 - Double(rect.midX)) - hx
        let ay = abs(Double(y) + 0.5 - Double(rect.midY)) - hy
        let d = sqrt(max(ax, 0) * max(ax, 0) + max(ay, 0) * max(ay, 0))
            + min(max(ax, ay), 0) - r
        return min(max(0.5 - d, 0), 1)
    }

    /// Lay `color` over the scene at `alpha` per pixel, IN LINEAR LIGHT, which
    /// is where a renderer lays paint down — and therefore the only blend that
    /// makes the numbers in a test the numbers the app would have to read back.
    mutating func composite(_ color: (Double, Double, Double), alpha: [Double]) {
        let ink = [color.0, color.1, color.2].map { Self.linear($0 / 255) }
        for i in 0..<(width * height) {
            let a = min(max(alpha[i], 0), 1)
            guard a > 0 else { continue }
            for c in 0..<3 {
                let was = Self.linear(Double(samples[i * 4 + c]) / 255)
                let now = was * (1 - a) + ink[c] * a
                samples[i * 4 + c] = UInt8((Self.srgb(now) * 255).rounded())
            }
        }
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func srgb(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(max(l, 0), 1 / 2.4) - 0.055
    }

    /// A rounded rectangle in one flat colour.
    mutating func paint(_ rect: CGRect, radius: Double, _ color: (Double, Double, Double)) {
        var alpha = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { alpha[y * width + x] = Self.coverage(rect, radius: radius, x, y) }
        }
        composite(color, alpha: alpha)
    }

    /// The shadow `rect` throws: its coverage mask blurred by `sigma`, moved by
    /// `offset` (y down), at `opacity`.
    mutating func castShadow(_ rect: CGRect, radius: Double, sigma: Double,
                             offset: CGSize, opacity: Double,
                             color: (Double, Double, Double) = (0, 0, 0)) {
        let shifted = rect.offsetBy(dx: offset.width, dy: offset.height)
        var mask = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { mask[y * width + x] = Self.coverage(shifted, radius: radius, x, y) }
        }
        composite(color, alpha: Self.blur(mask, width: width, height: height, sigma: sigma)
            .map { $0 * opacity })
    }

    /// A separable gaussian, normalised, so a fully covered pixel well inside
    /// the mask stays exactly 1.
    static func blur(_ mask: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        guard sigma > 0 else { return mask }
        let reach = max(1, Int((sigma * 4).rounded(.up)))
        var kernel = (-reach...reach).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        var pass = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var total = 0.0
                for (k, weight) in kernel.enumerated() {
                    let sx = min(max(x + k - reach, 0), width - 1)
                    total += mask[y * width + sx] * weight
                }
                pass[y * width + x] = total
            }
        }
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var total = 0.0
                for (k, weight) in kernel.enumerated() {
                    let sy = min(max(y + k - reach, 0), height - 1)
                    total += pass[sy * width + x] * weight
                }
                out[y * width + x] = total
            }
        }
        return out
    }
}
