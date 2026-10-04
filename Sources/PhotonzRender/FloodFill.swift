import CoreGraphics
import Foundation
import PhotonzCore

/// Magic-wand flood fill: selects the contiguous run of similar color around a
/// seed point in a bitmap (normally the rendered composite — what the user
/// sees). Render-side because it needs pixels; the resulting mask feeds
/// `ContourTracer` so the wand's output is an ordinary `SelectionRegion` path.
public enum FloodFill {

    /// A row-major boolean mask over the image, top-left origin.
    public struct Mask: Sendable {
        public let mask: [Bool]
        public let width: Int
        public let height: Int
    }

    /// Floods from `point` (image pixel coordinates, top-left origin) over all
    /// 4-connected pixels within `tolerance` of the SEED pixel's color —
    /// Photoshop semantics: similarity is measured against the seed, never the
    /// neighbor, so a gradient can't be crept across step by step. Distance is
    /// Euclidean over RGBA in 0–255 units (alpha included so transparent and
    /// opaque black don't merge). Returns `nil` when the seed is outside the
    /// image or the bitmap can't be read.
    public static func mask(in image: CGImage, from point: CGPoint, tolerance: Double) -> Mask? {
        let w = image.width, h = image.height
        let sx = Int(point.x.rounded(.down)), sy = Int(point.y.rounded(.down))
        guard w > 0, h > 0, sx >= 0, sy >= 0, sx < w, sy < h,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // Decode to RGBA8. Bitmap-context rows are top-down in memory, so the
        // buffer is already in top-left row order (same as EdgeMapAnalyzer).
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let cg = CGContext(data: base, width: w, height: h,
                                     bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            cg.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        let result = rgba.withUnsafeBufferPointer { px in
            floodMask(px, width: w, height: h, seedX: sx, seedY: sy,
                      tolerance: tolerance, contiguous: true)
        }
        return Mask(mask: result, width: w, height: h)
    }

    /// The flood itself, over premultiplied RGBA8 already in top-left row
    /// order. `contiguous` false takes every similar pixel in the image rather
    /// than only the ones joined to the seed (the paint bucket's Contiguous
    /// switch, off).
    static func floodMask(_ px: UnsafeBufferPointer<UInt8>, width w: Int, height h: Int,
                          seedX sx: Int, seedY sy: Int, tolerance: Double,
                          contiguous: Bool) -> [Bool] {
        var result = [Bool](repeating: false, count: w * h)
        let seed = (sy * w + sx) * 4
        let sr = Int(px[seed]), sg = Int(px[seed + 1])
        let sb = Int(px[seed + 2]), sa = Int(px[seed + 3])
        let limit = Int((tolerance * tolerance).rounded(.down))

        func similar(_ i: Int) -> Bool {
            let o = i * 4
            let dr = Int(px[o]) - sr, dg = Int(px[o + 1]) - sg
            let db = Int(px[o + 2]) - sb, da = Int(px[o + 3]) - sa
            return dr * dr + dg * dg + db * db + da * da <= limit
        }

        guard contiguous else {
            for i in 0..<(w * h) where similar(i) { result[i] = true }
            return result
        }

        // Scanline fill: flood a whole horizontal run at once, then seed
        // the rows above and below from each similar sub-run.
        var stack = [(x: sx, y: sy)]
        while let (x, y) = stack.popLast() {
            let row = y * w
            if result[row + x] || !similar(row + x) { continue }
            var lx = x
            while lx > 0 && !result[row + lx - 1] && similar(row + lx - 1) { lx -= 1 }
            var rx = x
            while rx < w - 1 && !result[row + rx + 1] && similar(row + rx + 1) { rx += 1 }
            for i in lx...rx { result[row + i] = true }
            for ny in [y - 1, y + 1] where ny >= 0 && ny < h {
                let nrow = ny * w
                var runStarted = false
                for i in lx...rx {
                    let candidate = !result[nrow + i] && similar(nrow + i)
                    if candidate && !runStarted { stack.append((i, ny)) }
                    runStarted = candidate
                }
            }
        }
        return result
    }

    /// The flooded region as a boundary path (via `ContourTracer`), ready to
    /// wrap in a `SelectionRegion`. `nil` if the seed is invalid.
    public static func path(in image: CGImage, from point: CGPoint, tolerance: Double) -> CGPath? {
        guard let m = mask(in: image, from: point, tolerance: tolerance) else { return nil }
        return ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height)
    }
}
