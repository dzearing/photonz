import CoreGraphics
import Foundation
import PhotonzCore

/// The paint bucket on a picture: flood the area of similar colour around the
/// click and fill only that, the way Photoshop's bucket does. The flood is the
/// magic wand's (`FloodFill`): similarity is measured against the pixel clicked,
/// so a gradient cannot be crept across step by step.
///
/// Anti-alias is what keeps a thin line from leaving a pale ring round the
/// fill. A pixel along an anti-aliased line is a blend of the colour clicked
/// and the line's colour; leaving it alone leaves a fringe of the old colour,
/// and filling it outright eats the line. So each pixel at the edge of the
/// flood is read as such a blend (the line's colour taken from the most unlike
/// pixel near it) and only its share of the old colour is swapped for the new
/// one. Exact for a line drawn over a flat colour, which is the case people
/// reach for the bucket in.
public enum BucketFill {

    /// The bucket's three settings, named as Photoshop names them.
    public struct Options: Sendable, Equatable {
        /// How far a colour may drift from the one clicked and still be filled:
        /// Euclidean RGBA distance in 0 to 255 units, as the wand measures it.
        public var tolerance: Double
        /// Off fills every pixel of that colour on the layer, joined or not.
        public var contiguous: Bool
        /// On blends the fill into the edge pixels instead of stopping hard.
        public var antiAlias: Bool

        public init(tolerance: Double, contiguous: Bool, antiAlias: Bool) {
            self.tolerance = tolerance
            self.contiguous = contiguous
            self.antiAlias = antiAlias
        }

        /// Photoshop's defaults: tolerance 32, contiguous, anti-aliased.
        public static let photoshop = Options(tolerance: 32, contiguous: true, antiAlias: true)
    }

    /// `image` with the area around `point` (bitmap pixels, top-left origin)
    /// filled with `hex`. Same size, same colour space where it can be kept, so
    /// the layer holding it never moves. Nil when the point is off the bitmap,
    /// the colour does not parse or the bitmap cannot be read.
    public static func filled(_ image: CGImage, at point: CGPoint, hex: String,
                              options: Options) -> CGImage? {
        let w = image.width, h = image.height
        let sx = Int(point.x.rounded(.down)), sy = Int(point.y.rounded(.down))
        guard w > 0, h > 0, sx >= 0, sy >= 0, sx < w, sy < h,
              let colour = RGBA(hex: hex),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // Work in the picture's own colour space when it is an RGB one, so a
        // Display P3 screenshot keeps its colours everywhere the fill is not.
        let ownSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var space = srgb
        let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            for candidate in [ownSpace, srgb].compactMap({ $0 }) {
                if let context = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                           bytesPerRow: w * 4, space: candidate, bitmapInfo: info) {
                    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                    space = candidate
                    return true
                }
            }
            return false
        }
        guard drew else { return nil }

        // The fill colour in that space, premultiplied, 0 to 255.
        let given = CGColor(srgbRed: colour.r, green: colour.g, blue: colour.b, alpha: colour.a)
        guard let inSpace = given.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = inSpace.components, parts.count >= 4 else { return nil }
        let alpha = Double(parts[3])
        let fill = (Double(parts[0]) * alpha * 255, Double(parts[1]) * alpha * 255,
                    Double(parts[2]) * alpha * 255, alpha * 255)

        let mask = rgba.withUnsafeBufferPointer {
            FloodFill.floodMask($0, width: w, height: h, seedX: sx, seedY: sy,
                                tolerance: options.tolerance, contiguous: options.contiguous)
        }
        var out = rgba
        let seedOffset = (sy * w + sx) * 4
        let seed = (Double(rgba[seedOffset]), Double(rgba[seedOffset + 1]),
                    Double(rgba[seedOffset + 2]), Double(rgba[seedOffset + 3]))
        let toleranceSquared = options.tolerance * options.tolerance

        rgba.withUnsafeBufferPointer { px in
            func pixel(_ i: Int) -> (Double, Double, Double, Double) {
                let o = i * 4
                return (Double(px[o]), Double(px[o + 1]), Double(px[o + 2]), Double(px[o + 3]))
            }
            func distanceFromSeed(_ p: (Double, Double, Double, Double)) -> Double {
                let r = p.0 - seed.0, g = p.1 - seed.1, b = p.2 - seed.2, a = p.3 - seed.3
                return r * r + g * g + b * b + a * a
            }
            func write(_ i: Int, _ p: (Double, Double, Double, Double)) {
                let o = i * 4
                let a = min(255, max(0, p.3))
                out[o] = UInt8(min(a, max(0, p.0)).rounded())
                out[o + 1] = UInt8(min(a, max(0, p.1)).rounded())
                out[o + 2] = UInt8(min(a, max(0, p.2)).rounded())
                out[o + 3] = UInt8(a.rounded())
            }
            /// The line's colour near pixel (x, y): the pixel outside the flood,
            /// within two pixels, most unlike the colour clicked. Nil when the
            /// flood covers the whole neighbourhood.
            func lineColour(nearX x: Int, y: Int) -> (Double, Double, Double, Double)? {
                var best: (Double, Double, Double, Double)?
                var bestDistance = -1.0
                for ny in max(0, y - 2)...min(h - 1, y + 2) {
                    for nx in max(0, x - 2)...min(w - 1, x + 2) where !mask[ny * w + nx] {
                        let candidate = pixel(ny * w + nx)
                        let d = distanceFromSeed(candidate)
                        if d > bestDistance { bestDistance = d; best = candidate }
                    }
                }
                return best
            }
            /// `p` read as a blend of the seed colour and `line`, with the
            /// seed's share swapped for the fill.
            func unblended(_ p: (Double, Double, Double, Double),
                           line: (Double, Double, Double, Double)) -> (Double, Double, Double, Double) {
                let v = (seed.0 - line.0, seed.1 - line.1, seed.2 - line.2, seed.3 - line.3)
                let length = v.0 * v.0 + v.1 * v.1 + v.2 * v.2 + v.3 * v.3
                guard length >= 1 else { return fill }
                let d = (p.0 - line.0, p.1 - line.1, p.2 - line.2, p.3 - line.3)
                let share = min(1, max(0, (d.0 * v.0 + d.1 * v.1 + d.2 * v.2 + d.3 * v.3) / length))
                return (p.0 + share * (fill.0 - seed.0), p.1 + share * (fill.1 - seed.1),
                        p.2 + share * (fill.2 - seed.2), p.3 + share * (fill.3 - seed.3))
            }
            func touchesFlood(_ x: Int, _ y: Int) -> Bool {
                (x > 0 && mask[y * w + x - 1]) || (x < w - 1 && mask[y * w + x + 1])
                    || (y > 0 && mask[(y - 1) * w + x]) || (y < h - 1 && mask[(y + 1) * w + x])
            }

            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    if mask[i] {
                        let p = pixel(i)
                        // The colour clicked exactly, or no softening asked
                        // for: the fill outright. That is nearly every pixel
                        // of a flat area, so the search below stays rare.
                        guard options.antiAlias, distanceFromSeed(p) > 0,
                              let line = lineColour(nearX: x, y: y) else {
                            write(i, fill)
                            continue
                        }
                        write(i, unblended(p, line: line))
                    } else if options.antiAlias, touchesFlood(x, y) {
                        let p = pixel(i)
                        // A pixel as like the seed as the flood's own, that the
                        // flood never reached, is a different area across a
                        // line one pixel wide: it is not this fill's to touch.
                        guard distanceFromSeed(p) > toleranceSquared,
                              let line = lineColour(nearX: x, y: y) else { continue }
                        write(i, unblended(p, line: line))
                    }
                }
            }
        }

        return out.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space, bitmapInfo: info)
            else { return nil }
            return context.makeImage()
        }
    }
}
