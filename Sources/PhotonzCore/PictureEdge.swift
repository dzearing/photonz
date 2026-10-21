import CoreGraphics
import Foundation

/// The visible edge of a picture, traced out of its transparency.
///
/// A sticker, a cut-out or a PNG with a see-through background has a shape
/// that is not its box, and a Border that follows the shape goes round that
/// shape (`ShapeOutline.swift`), the way Photoshop's Stroke goes round a
/// layer's pixels. Core has no pixels, so whoever does hands the alpha in.
///
/// The edge is the half-way line of the alpha, found between pixels rather
/// than along their sides (marching squares): where one pixel is a quarter
/// solid and its neighbour three quarters, the edge runs between them, a
/// little nearer the solid one. That is where the picture's own anti-aliased
/// edge reads as being, so a ring laid on it sits flush. Tracing whole pixels
/// instead left a staircase that every ring swept round it showed as a wobble
/// (seen on a star sticker, 2026-10-21). The points that then lie on a
/// straight run are dropped, so a ring is swept round a handful of corners
/// rather than one point per pixel.
public enum PictureEdge {

    /// How see-through a pixel has to be before it counts as outside the
    /// picture, out of 255. Half way, so a soft edge is cut down its middle.
    public static let threshold: UInt8 = 128

    /// How far off a straight run a point may sit and still be dropped, in
    /// pixels of the mask.
    static let flatness: CGFloat = 0.2

    /// The edge of `alpha` (row-major, top row first, `width * height` values)
    /// in FRACTIONS of the picture, top-left origin, or nil when there is no
    /// see-through edge to follow: every pixel solid, or nothing solid at all.
    ///
    /// Loops that sit inside other loops are holes, and the path comes back
    /// already merged so it fills correctly under the winding rule.
    public static func outline(alpha: [UInt8], width: Int, height: Int) -> CGPath? {
        guard width > 0, height > 0, alpha.count == width * height else { return nil }
        // A picture solid to its edges is its box, and the box ring is the
        // better answer for it: square corners stay square however far out the
        // ring is pushed.
        guard alpha.contains(where: { $0 < threshold }),
              alpha.contains(where: { $0 >= threshold }) else { return nil }
        let result = CGMutablePath()
        for ring in loops(alpha: alpha, width: width, height: height) {
            let smooth = simplified(ring)
            guard smooth.count >= 3 else { continue }
            result.addLines(between: smooth.map {
                CGPoint(x: $0.x / CGFloat(width), y: $0.y / CGFloat(height))
            })
            result.closeSubpath()
        }
        return result.isEmpty ? nil : result.normalized(using: .evenOdd)
    }

    /// Every closed loop of the half-way line, in pixels from the top-left
    /// corner, a pixel's value standing at its middle. The picture is read as
    /// clear past its edges, so every loop closes.
    static func loops(alpha: [UInt8], width: Int, height: Int) -> [[CGPoint]] {
        let iso = CGFloat(threshold) - 0.5
        func value(_ x: Int, _ y: Int) -> CGFloat {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return CGFloat(alpha[y * width + x])
        }
        // A crossing sits on the line between two neighbouring pixel middles,
        // and is named by that line: across (to the right) or down.
        let stride = width + 2
        func across(_ x: Int, _ y: Int) -> Int { ((y + 1) * stride + (x + 1)) * 2 }
        func down(_ x: Int, _ y: Int) -> Int { ((y + 1) * stride + (x + 1)) * 2 + 1 }
        var points: [Int: CGPoint] = [:]
        var links: [Int: [Int]] = [:]
        func crossing(_ key: Int, from a: (Int, Int), to b: (Int, Int)) -> Int {
            if points[key] == nil {
                let va = value(a.0, a.1), vb = value(b.0, b.1)
                let t = vb == va ? 0.5 : min(1, max(0, (iso - va) / (vb - va)))
                points[key] = CGPoint(x: CGFloat(a.0) + 0.5 + t * CGFloat(b.0 - a.0),
                                      y: CGFloat(a.1) + 0.5 + t * CGFloat(b.1 - a.1))
            }
            return key
        }
        func link(_ a: Int, _ b: Int) {
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        for y in -1..<height {
            for x in -1..<width {
                let tl = value(x, y) > iso, tr = value(x + 1, y) > iso
                let br = value(x + 1, y + 1) > iso, bl = value(x, y + 1) > iso
                let index = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
                guard index != 0, index != 15 else { continue }
                let top = { crossing(across(x, y), from: (x, y), to: (x + 1, y)) }
                let bottom = { crossing(across(x, y + 1), from: (x, y + 1), to: (x + 1, y + 1)) }
                let left = { crossing(down(x, y), from: (x, y), to: (x, y + 1)) }
                let right = { crossing(down(x + 1, y), from: (x + 1, y), to: (x + 1, y + 1)) }
                // Where two solid corners face each other across the cell, its
                // middle decides whether they join.
                let middle = (value(x, y) + value(x + 1, y) + value(x + 1, y + 1) + value(x, y + 1)) / 4 > iso
                switch index {
                case 1, 14: link(left(), bottom())
                case 2, 13: link(bottom(), right())
                case 3, 12: link(left(), right())
                case 4, 11: link(top(), right())
                case 6, 9: link(top(), bottom())
                case 7, 8: link(left(), top())
                case 5:
                    if middle { link(left(), top()); link(bottom(), right()) }
                    else { link(top(), right()); link(left(), bottom()) }
                case 10:
                    if middle { link(top(), right()); link(left(), bottom()) }
                    else { link(left(), top()); link(bottom(), right()) }
                default: break
                }
            }
        }
        var loops: [[CGPoint]] = []
        var seen = Set<Int>()
        for start in links.keys where !seen.contains(start) {
            var loop: [CGPoint] = []
            var previous = -1
            var current = start
            while !seen.contains(current), let point = points[current] {
                seen.insert(current)
                loop.append(point)
                guard let next = links[current]?.first(where: { $0 != previous && !seen.contains($0) })
                    ?? links[current]?.first(where: { $0 != previous }) else { break }
                previous = current
                current = next
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Each closed loop of a traced path as its corner points.
    static func rings(of path: CGPath) -> [[CGPoint]] {
        var rings: [[CGPoint]] = []
        var ring: [CGPoint] = []
        path.applyWithBlock { element in
            let piece = element.pointee
            switch piece.type {
            case .moveToPoint:
                if ring.count >= 3 { rings.append(ring) }
                ring = [piece.points[0]]
            case .addLineToPoint:
                ring.append(piece.points[0])
            case .closeSubpath:
                if ring.count >= 3 { rings.append(ring) }
                ring = []
            default:
                break
            }
        }
        if ring.count >= 3 { rings.append(ring) }
        return rings.map { loop in
            // A loop that comes back to where it started says so twice.
            if let first = loop.first, let last = loop.last, loop.count > 3,
               abs(first.x - last.x) < 0.001, abs(first.y - last.y) < 0.001 {
                return Array(loop.dropLast())
            }
            return loop
        }
    }

    /// The loop with the points that sit on a straight run dropped
    /// (Douglas-Peucker, closed): what is left is the corners that matter.
    static func simplified(_ ring: [CGPoint]) -> [CGPoint] {
        guard ring.count > 4 else { return ring }
        // Split the loop at its first point and the point furthest from it,
        // and simplify each half as an open run.
        let start = ring[0]
        var far = 0
        var farthest: CGFloat = -1
        for (index, point) in ring.enumerated() {
            let d = hypot(point.x - start.x, point.y - start.y)
            if d > farthest { farthest = d; far = index }
        }
        guard far > 0 else { return ring }
        let first = Array(ring[0...far])
        let second = Array(ring[far...]) + [start]
        let a = douglasPeucker(first)
        let b = douglasPeucker(second)
        return Array(a.dropLast()) + Array(b.dropLast())
    }

    private static func douglasPeucker(_ run: [CGPoint]) -> [CGPoint] {
        guard run.count > 2 else { return run }
        var keep = [Bool](repeating: false, count: run.count)
        keep[0] = true
        keep[run.count - 1] = true
        var stack: [(Int, Int)] = [(0, run.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            let a = run[lo], b = run[hi]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            var worst = lo
            var worstDistance: CGFloat = 0
            for index in (lo + 1)..<hi {
                let p = run[index]
                let d = length > 0
                    ? abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
                    : hypot(p.x - a.x, p.y - a.y)
                if d > worstDistance { worstDistance = d; worst = index }
            }
            if worstDistance > flatness {
                keep[worst] = true
                stack.append((lo, worst))
                stack.append((worst, hi))
            }
        }
        return run.indices.filter { keep[$0] }.map { run[$0] }
    }
}
