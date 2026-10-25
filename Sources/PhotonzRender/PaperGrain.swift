import Foundation

/// The paper the dry media catch on (`docs/design/brushes.md`, decision 4): a
/// height for every point of a paint layer, from the low valleys (0) to the
/// high tooth (1).
///
/// It is laid in the layer's own POINTS, not pixels, so a stroke shows the same
/// tooth at every zoom and on every render, and two strokes over the same spot
/// catch the same tooth. Moving a painted layer carries its paper with it.
///
/// Procedural and seeded, never a stored picture: a pebbly cellular tooth, a few
/// octaves of tileable value noise (fine tooth, a slow swell, a faint run of
/// fibre), worked out once
/// into one tile that repeats every `period` points and then evened out so that
/// every height is as common as every other. That last step is what makes the
/// media predictable: pigment that settles on everything above height `t`
/// covers exactly `1 - t` of the paper.
public enum PaperGrain {

    /// How far the tile runs before it repeats, in points.
    public static let period: Double = 128

    /// Samples per point in the tile.
    static let density = 4
    static let side = 512

    /// The height of the paper at a point of the layer, 0...1. `coarseness`
    /// stretches the paper: 2 makes every bump twice the size (chalk's coarser
    /// pastel paper).
    public static func height(x: Double, y: Double, coarseness: Double = 1) -> Float {
        tile.withUnsafeBufferPointer { height($0, x: x, y: y, coarseness: coarseness) }
    }

    /// The same, read from the tile handed over (`tile.withUnsafeBufferPointer`),
    /// for the loops that ask it for every pixel of every dab.
    @inline(__always)
    static func height(_ t: UnsafeBufferPointer<Float>, x: Double, y: Double, coarseness: Double) -> Float {
        let spread = Double(density) / max(coarseness, 0.01)
        let u = x * spread, v = y * spread
        let fu = u.rounded(.down), fv = v.rounded(.down)
        let tx = Float(u - fu), ty = Float(v - fv)
        let mask = side - 1
        let x0 = Int(fu) & mask, y0 = Int(fv) & mask
        let x1 = (x0 + 1) & mask, y1 = (y0 + 1) & mask
        let top = t[y0 * side + x0] * (1 - tx) + t[y0 * side + x1] * tx
        let bottom = t[y1 * side + x0] * (1 - tx) + t[y1 * side + x1] * tx
        return top * (1 - ty) + bottom * ty
    }

    /// Works the tile out in the background if nothing has yet, so the first
    /// stroke that needs it does not wait (about a third of a second).
    public static func prepare() {
        Task.detached(priority: .userInitiated) { _ = tile.count }
    }

    /// The tile, worked out the first time anything asks for it.
    static let tile: [Float] = build()

    /// One octave: lattice cells across the tile on each axis, and its weight.
    private struct Octave {
        let cellsX: Int
        let cellsY: Int
        let weight: Float
    }

    private static let octaves: [Octave] = [
        Octave(cellsX: 20, cellsY: 20, weight: 0.08),    // a slow swell, about 6 points
        Octave(cellsX: 40, cellsY: 12, weight: 0.08),    // a faint run of fibre, side to side
        Octave(cellsX: 72, cellsY: 72, weight: 0.16),    // medium tooth, under 2 points
        Octave(cellsX: 160, cellsY: 160, weight: 0.12),  // fine tooth, under a point
    ]

    /// The dimples of the tooth: cells across the tile, and their weight. Each
    /// cell holds one shallow pit around its own seed point, and the ridges
    /// between pits join up into a network, the way pressed drawing paper is
    /// made. Pigment catches on the ridges first, so a light stroke shows a
    /// broken net and a firm one shows the pits as flecks of bare paper.
    private static let pebbleCells = 60
    private static let pebbleWeight: Float = 0.56

    private static func build() -> [Float] {
        var raw = pebbles()
        for (index, octave) in octaves.enumerated() {
            let sx = Float(octave.cellsX) / Float(side), sy = Float(octave.cellsY) / Float(side)
            for y in 0..<side {
                let v = Float(y) * sy
                let j0 = Int(v), fy = smooth(v - Float(j0))
                let ja = j0 % octave.cellsY, jb = (j0 + 1) % octave.cellsY
                for x in 0..<side {
                    let u = Float(x) * sx
                    let i0 = Int(u), fx = smooth(u - Float(i0))
                    let ia = i0 % octave.cellsX, ib = (i0 + 1) % octave.cellsX
                    let a = lattice(ia, ja, index), b = lattice(ib, ja, index)
                    let c = lattice(ia, jb, index), d = lattice(ib, jb, index)
                    let value = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
                    raw[y * side + x] += value * octave.weight
                }
            }
        }
        return equalized(raw)
    }

    /// A tileable cellular pattern: at each sample, how far it is from the
    /// nearest of one seed point per cell (0 in a pit, rising to the ridges).
    private static func pebbles() -> [Float] {
        let n = pebbleCells
        var seeds = [(Float, Float)](repeating: (0, 0), count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                seeds[j * n + i] = (Float(i) + lattice(i, j, 90), Float(j) + lattice(i, j, 91))
            }
        }
        var out = [Float](repeating: 0, count: side * side)
        let perSample = Float(n) / Float(side)
        for y in 0..<side {
            let v = (Float(y) + 0.5) * perSample
            let cj = Int(v)
            for x in 0..<side {
                let u = (Float(x) + 0.5) * perSample
                let ci = Int(u)
                var nearest: Float = 9
                for dj in -1...1 {
                    for di in -1...1 {
                        let i = ci + di, j = cj + dj
                        let seed = seeds[((j + n) % n) * n + ((i + n) % n)]
                        let sx = seed.0 + Float(i - ((i + n) % n)), sy = seed.1 + Float(j - ((j + n) % n))
                        let d = (sx - u) * (sx - u) + (sy - v) * (sy - v)
                        if d < nearest { nearest = d }
                    }
                }
                out[y * side + x] = min(1, nearest.squareRoot()) * pebbleWeight
            }
        }
        return out
    }

    /// Every height made as common as every other (a histogram's running
    /// total, read back through), so a threshold of `t` leaves `t` of the paper
    /// below it.
    private static func equalized(_ raw: [Float]) -> [Float] {
        guard let low = raw.min(), let high = raw.max(), high > low else { return raw }
        let bins = 4096
        let span = high - low
        var counts = [Int](repeating: 0, count: bins + 1)
        for value in raw { counts[min(bins - 1, Int((value - low) / span * Float(bins)))] += 1 }
        // below[k]: how many values fall in bins before k.
        var below = [Float](repeating: 0, count: bins + 1)
        var running = 0
        for k in 0..<bins {
            below[k] = Float(running)
            running += counts[k]
        }
        below[bins] = Float(running)
        let total = Float(raw.count)
        return raw.map { value in
            let position = (value - low) / span * Float(bins)
            let k = min(bins - 1, Int(position))
            let within = position - Float(k)
            return min(1, max(0, (below[k] + within * Float(counts[k])) / total))
        }
    }

    private static func smooth(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

    /// A fixed value in 0...1 for a lattice point of one octave.
    private static func lattice(_ i: Int, _ j: Int, _ octave: Int) -> Float {
        var h = UInt64(truncatingIfNeeded: i) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(truncatingIfNeeded: j) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(truncatingIfNeeded: octave + 1) &* 0x1656_67B1_9E37_79F9
        h ^= h >> 31
        h &*= 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        h &*= 0x94D0_49BB_1331_11EB
        h ^= h >> 32
        return Float(h >> 40) / Float(1 << 24)
    }
}
