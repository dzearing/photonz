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

    /// How much of pixel (x, y) a shape covers, from a 4 x 4 grid of samples:
    /// the antialiasing a real capture puts on every curved edge.
    private func coverage(_ x: Int, _ y: Int, _ inside: (Double, Double) -> Bool) -> Double {
        var hits = 0
        for sy in 0..<4 {
            for sx in 0..<4 where inside(Double(x) + (Double(sx) + 0.5) / 4,
                                         Double(y) + (Double(sy) + 0.5) / 4) {
                hits += 1
            }
        }
        return Double(hits) / 16
    }

    /// Paints a shape whose tone at each point is `tone(x, y)`, blended over
    /// what is there by how much of each pixel the shape covers.
    mutating func paint(within rect: CGRect, inside: (Double, Double) -> Bool,
                        tone: (Double, Double) -> Double) {
        let x0 = max(0, Int(rect.minX) - 1), x1 = min(w - 1, Int(rect.maxX) + 1)
        let y0 = max(0, Int(rect.minY) - 1), y1 = min(h - 1, Int(rect.maxY) + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let a = coverage(x, y, inside)
                guard a > 0 else { continue }
                let under = Double(pixels[y * w + x])
                let over = tone(Double(x) + 0.5, Double(y) + 0.5)
                pixels[y * w + x] = UInt8(max(0, min(255, (under * (1 - a) + over * a).rounded())))
            }
        }
    }

    /// An antialiased disc filling `rect` (a circle when it is square).
    mutating func disc(_ rect: CGRect, _ tone: UInt8) {
        disc(rect) { _, _ in Double(tone) }
    }

    mutating func disc(_ rect: CGRect, tone: (Double, Double) -> Double) {
        let cx = Double(rect.midX), cy = Double(rect.midY)
        let rx = Double(rect.width) / 2, ry = Double(rect.height) / 2
        paint(within: rect, inside: { x, y in
            let dx = (x - cx) / rx, dy = (y - cy) / ry
            return dx * dx + dy * dy <= 1
        }, tone: tone)
    }

    /// An antialiased rounded rectangle (a capsule when `radius` is half its
    /// height).
    mutating func roundedRect(_ rect: CGRect, radius: Double, _ tone: UInt8) {
        let x0 = Double(rect.minX), x1 = Double(rect.maxX)
        let y0 = Double(rect.minY), y1 = Double(rect.maxY)
        paint(within: rect, inside: { x, y in
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { return false }
            let cx = min(max(x, x0 + radius), x1 - radius)
            let cy = min(max(y, y0 + radius), y1 - radius)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius
        }, tone: { _, _ in Double(tone) })
    }

    /// A head-and-shoulders "photo" clipped to a disc: a diagonal backdrop
    /// gradient, a face, hair and a shirt, so its insides are full of edges.
    mutating func portrait(_ rect: CGRect, backdrop: (Double, Double) = (200, 110),
                           skin: Double = 205, hair: Double = 45, shirt: Double = 70) {
        let x0 = Double(rect.minX), y0 = Double(rect.minY), u = Double(rect.width)
        func inEllipse(_ x: Double, _ y: Double, _ ex: Double, _ ey: Double,
                       _ ew: Double, _ eh: Double) -> Bool {
            let cx = x0 + (ex + ew / 2) * u, cy = y0 + (ey + eh / 2) * u
            let dx = (x - cx) / (ew * u / 2), dy = (y - cy) / (eh * u / 2)
            return dx * dx + dy * dy <= 1
        }
        disc(rect) { x, y in
            if inEllipse(x, y, 0.27, 0.12, 0.46, 0.22) { return hair }
            if inEllipse(x, y, 0.3, 0.18, 0.4, 0.48) { return skin }
            if inEllipse(x, y, 0.12, 0.66, 0.76, 0.6) { return shirt }
            let t = ((x - x0) + (y - y0)) / (2 * u)
            return backdrop.0 + (backdrop.1 - backdrop.0) * t
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
