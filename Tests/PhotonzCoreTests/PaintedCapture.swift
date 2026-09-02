import CoreGraphics
import Foundation
import PhotonzCore

/// A painted screenshot, in brightness only. Element detection reads BOTH the
/// edge map and the pixels behind it, so a test scene has to be a picture rather
/// than a set of hand-placed gradient responses: the gradients are derived from
/// the paint the same way `EdgeMapAnalyzer` derives them from a real capture, so
/// what these tests exercise is the shipping path.
struct PaintedCapture {
    var w: Int, h: Int
    /// Brightness 0…255, top-left row order.
    var pixels: [UInt8]

    init(w: Int, h: Int, background: UInt8 = 242) {
        self.w = w
        self.h = h
        pixels = [UInt8](repeating: background, count: w * h)
    }

    mutating func fill(_ rect: CGRect, _ tone: UInt8) {
        for y in Int(rect.minY)..<Int(rect.maxY) where y >= 0 && y < h {
            for x in Int(rect.minX)..<Int(rect.maxX) where x >= 0 && x < w {
                pixels[y * w + x] = tone
            }
        }
    }

    /// A bordered element: `width` px of `border` tone around an `inside` fill.
    mutating func box(_ rect: CGRect, border: UInt8, inside: UInt8 = 255, width: Int = 2) {
        fill(rect, border)
        fill(rect.insetBy(dx: CGFloat(width), dy: CGFloat(width)), inside)
    }

    /// A horizontal rule of `thickness` px whose TOP is `y` — a settings-row
    /// divider, which has no left or right edge of its own.
    mutating func rule(y: Int, x0: Int, x1: Int, tone: UInt8, thickness: Int = 2) {
        fill(CGRect(x: x0, y: y, width: x1 - x0, height: thickness), tone)
    }

    /// Stand-in text: a run of dark strokes on a shared baseline, the thing that
    /// used to win every directional walk inside a button.
    mutating func text(x: Int, y: Int, glyphs: Int, tone: UInt8 = 40,
                       glyphWidth: Int = 4, gap: Int = 4, height: Int = 14) {
        for i in 0..<glyphs {
            let left = x + i * (glyphWidth + gap)
            fill(CGRect(x: left, y: y, width: glyphWidth, height: height), tone)
        }
    }

    var luma: LumaField { LumaField(width: w, height: h, samples: pixels) }

    /// The same Sobel pass `EdgeMapAnalyzer` runs, on 0…1 brightness so the
    /// map's absolute floor means what it means on a real capture.
    var map: EdgeMap {
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        func at(_ x: Int, _ y: Int) -> Double {
            let cx = min(max(x, 0), w - 1), cy = min(max(y, 0), h - 1)
            return Double(pixels[cy * w + cx]) / 255
        }
        for y in 0..<h {
            for x in 0..<w {
                let sx = -at(x - 1, y - 1) + at(x + 1, y - 1)
                    - 2 * at(x - 1, y) + 2 * at(x + 1, y)
                    - at(x - 1, y + 1) + at(x + 1, y + 1)
                let sy = -at(x - 1, y - 1) - 2 * at(x, y - 1) - at(x + 1, y - 1)
                    + at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1)
                gx[y * w + x] = abs(sx)
                gy[y * w + x] = abs(sy)
            }
        }
        var flat = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) { flat[i] = Double(pixels[i]) / 255 }
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: flat)
    }
}
