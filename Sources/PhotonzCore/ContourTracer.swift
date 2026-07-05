import CoreGraphics
import Foundation

/// Traces the boundary of a bitmap mask into a `CGPath` of axis-aligned
/// contours (document coordinates, top-left origin: mask pixel (x, y) covers
/// the unit square from (x, y) to (x+1, y+1)). Disjoint blobs become separate
/// subpaths; holes are excluded under the even-odd rule — the same convention
/// `SelectionRegion` uses, so magic-wand masks compose with path booleans.
public enum ContourTracer {

    /// `mask` is row-major, `width * height` entries. Returns `nil` for an
    /// all-empty or mis-sized mask.
    public static func path(fromMask mask: [Bool], width: Int, height: Int) -> CGPath? {
        guard width > 0, height > 0, mask.count == width * height else { return nil }

        func filled(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x]
        }

        // Every filled pixel emits a directed edge along each side that faces
        // an empty neighbor, wound clockwise around the pixel (screen coords,
        // y down). Directions: 0 = +x, 1 = +y, 2 = −x, 3 = −y. An edge is
        // keyed by (start vertex, direction) — that pair is unique because a
        // side is only emitted from one of its two adjacent pixels.
        let vw = width + 1 // vertex grid is (width+1) × (height+1)
        var edgeTo = [Int: Int]() // startVertex * 4 + direction → endVertex
        for y in 0..<height {
            for x in 0..<width where filled(x, y) {
                let tl = y * vw + x, tr = tl + 1, bl = tl + vw, br = bl + 1
                if !filled(x, y - 1) { edgeTo[tl * 4 + 0] = tr }
                if !filled(x + 1, y) { edgeTo[tr * 4 + 1] = br }
                if !filled(x, y + 1) { edgeTo[br * 4 + 2] = bl }
                if !filled(x - 1, y) { edgeTo[bl * 4 + 3] = tl }
            }
        }
        guard !edgeTo.isEmpty else { return nil }

        func point(_ vertex: Int) -> CGPoint {
            CGPoint(x: CGFloat(vertex % vw), y: CGFloat(vertex / vw))
        }

        let result = CGMutablePath()
        while let (startKey, firstEnd) = edgeTo.first {
            edgeTo.removeValue(forKey: startKey)
            let loopStart = startKey / 4
            let initialDir = startKey % 4
            var corners = [loopStart] // vertices where the direction changes
            var current = firstEnd
            var dir = initialDir
            while true {
                // At a saddle vertex two out-edges exist; preferring the
                // right turn keeps diagonally touching blobs as separate
                // contours. A U-turn is geometrically impossible (it would
                // need interior on both sides of one segment), so three
                // candidates suffice.
                var next: (to: Int, dir: Int)?
                var closed = false
                for candidate in [(dir + 1) % 4, dir, (dir + 3) % 4] {
                    if current == loopStart && candidate == initialDir {
                        closed = true // the rule chose the (consumed) first edge
                        break
                    }
                    if let to = edgeTo[current * 4 + candidate] {
                        next = (to, candidate)
                        break
                    }
                }
                guard !closed, let (to, chosenDir) = next else { break }
                if chosenDir != dir { corners.append(current) }
                edgeTo.removeValue(forKey: current * 4 + chosenDir)
                current = to
                dir = chosenDir
            }
            guard let first = corners.first else { continue }
            result.move(to: point(first))
            for corner in corners.dropFirst() { result.addLine(to: point(corner)) }
            result.closeSubpath()
        }
        return result.copy()
    }
}
