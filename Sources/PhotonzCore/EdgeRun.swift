import Foundation

/// How far a boundary actually reaches.
///
/// `EdgeMap` says "there is a horizontal boundary at row 235 somewhere under
/// this window"; it cannot say whether that boundary is the hairline under one
/// settings row (624 px wide) or the card border 16 px wider on each side,
/// because its gradients are summed into 16 px blocks. That distinction IS the
/// element's width, so it is read straight off the pixels: start where the
/// boundary is known to exist and walk along it until it stops.
///
/// The walk lets the boundary wander a pixel per step, which is what a rounded
/// corner looks like from the side, and bridges a few dead pixels so
/// antialiasing does not cut a run in half. It stops for good when the
/// brightness step that defines the boundary fades below a fraction of its own
/// strength where the walk began — relative, so a hairline divider is followed
/// as faithfully as a hard button border.
///
/// This runs on every mouse move, so it reads the brightness buffer directly
/// rather than through per-pixel accessors.
public enum EdgeRun {

    /// How far the walk reaches from its seed in each direction. Generous enough
    /// to cross a full-width divider on a large capture, bounded so a mouse-move
    /// never pays for a whole image row.
    public static let defaultReach = 1200

    /// The step must stay at least this much of its seed strength to count as
    /// the same boundary.
    private static let keepFraction = 0.35

    /// Absolute brightness-step floor, in 0…255 units, so a flat region never
    /// reads as a boundary that runs forever.
    private static let floor = 5

    /// How many consecutive dead columns/rows the walk bridges before giving up.
    private static let maxGap = 3

    /// How far around the seed coordinate to look for the boundary before
    /// walking. The caller seeds with the pointer's own column, which can land
    /// between two glyphs or on the inside of a corner radius.
    private static let seedSearch = 8

    /// The columns a horizontal boundary at `row` covers, found by walking out
    /// from `seedX`. Nil when no boundary reads near the seed.
    public static func horizontal(row: Int, seedX: Int, in luma: LumaField,
                                  reach: Int = defaultReach) -> ClosedRange<Int>? {
        guard !luma.isEmpty else { return nil }
        return luma.samples.withUnsafeBufferPointer { buffer in
            walk(seed: seedX, cross: row, alongStride: 1, crossStride: luma.width,
                 alongCount: luma.width, crossCount: luma.height,
                 reach: reach, samples: buffer)
        }
    }

    /// The rows a vertical boundary at `column` covers — the mirror of
    /// `horizontal`.
    public static func vertical(column: Int, seedY: Int, in luma: LumaField,
                                reach: Int = defaultReach) -> ClosedRange<Int>? {
        guard !luma.isEmpty else { return nil }
        return luma.samples.withUnsafeBufferPointer { buffer in
            walk(seed: seedY, cross: column, alongStride: luma.width, crossStride: 1,
                 alongCount: luma.height, crossCount: luma.width,
                 reach: reach, samples: buffer)
        }
    }

    /// One axis-agnostic walk: `along` is the direction the boundary runs,
    /// `cross` the coordinate it sits at and is allowed to drift on.
    private static func walk(seed: Int, cross: Int, alongStride: Int, crossStride: Int,
                             alongCount: Int, crossCount: Int, reach: Int,
                             samples: UnsafeBufferPointer<UInt8>) -> ClosedRange<Int>? {
        guard alongCount > 0, crossCount > 0, reach > 0 else { return nil }

        /// The brightness step across the boundary at one point, searched over a
        /// one-pixel band so a boundary that wanders still answers. A 1 px rule
        /// drawn on white reads here even though the rows either side of it are
        /// identical, because the difference is taken ACROSS the rule.
        func response(_ along: Int, _ c: Int) -> Int {
            let base = along * alongStride
            var best = 0
            for band in -1...1 {
                let low = c + band - 1, high = c + band + 1
                guard low >= 0, high < crossCount else { continue }
                let step = abs(Int(samples[base + high * crossStride])
                               - Int(samples[base + low * crossStride]))
                if step > best { best = step }
            }
            return best
        }

        // Seed on the strongest reading near the pointer: a boundary can be
        // missing at the exact column probed (between two glyphs, or on the
        // inside of a corner radius) and still be the right boundary.
        var seedAt = min(max(seed, 0), alongCount - 1)
        var seedCross = min(max(cross, 0), crossCount - 1)
        var seedStrength = 0
        let searchFrom = seedAt, searchCross = seedCross
        // Nearest offsets first, so a tie keeps the pointer's own column: the
        // walk's reach is measured from wherever it starts.
        for offset in (0...seedSearch).flatMap({ $0 == 0 ? [0] : [-$0, $0] }) {
            let along = searchFrom + offset
            guard along >= 0, along < alongCount else { continue }
            for band in -1...1 {
                let c = searchCross + band
                guard c >= 0, c < crossCount else { continue }
                let r = response(along, c)
                if r > seedStrength { seedStrength = r; seedAt = along; seedCross = c }
            }
        }
        guard seedStrength >= floor else { return nil }
        let threshold = max(Int(Double(seedStrength) * keepFraction), floor)

        var lower = seedAt, upper = seedAt
        for direction in [-1, 1] {
            var c = seedCross
            var gap = 0
            var last = seedAt
            var along = seedAt
            for _ in 0..<reach {
                along += direction
                guard along >= 0, along < alongCount else { break }
                // Only look for drift once the boundary has stopped reading
                // where it was: the response already covers a pixel either side,
                // so a straight border costs one reading per step.
                var best = response(along, c)
                if best < threshold {
                    var drifted = c
                    for band in [-1, 1] {
                        let candidate = c + band
                        guard candidate >= 0, candidate < crossCount else { continue }
                        let r = response(along, candidate)
                        if r > best { best = r; drifted = candidate }
                    }
                    c = drifted
                }
                if best >= threshold {
                    gap = 0
                    last = along
                } else {
                    gap += 1
                    if gap > maxGap { break }
                }
            }
            if direction < 0 { lower = last } else { upper = last }
        }
        return lower...upper
    }
}
