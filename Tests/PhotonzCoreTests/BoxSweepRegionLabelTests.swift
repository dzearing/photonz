import Foundation
@testable import PhotonzCore
import Testing

/// Every pixel's colour region, held against the slowest way there is to work
/// it out: a flood from each pixel over neighbours within `colorTolerance` of
/// each other. The labeller is the hot loop of every separation, so it gets
/// rewritten for speed; this is what says a rewrite still draws the same map.
///
/// A region is named by its first pixel in reading order, which is what the
/// labeller's union-find leaves behind (each union keeps the lower root).
@Suite("Colour regions match a plain flood")
struct BoxSweepRegionLabelTests {

    /// Bytes from a fixed seed: a few flat paints, each pixel nudged by up to
    /// `jitter`, so neighbours land either side of the tolerance.
    static func picture(width: Int, height: Int, seed: UInt64, jitter: Int) -> [UInt8] {
        var state = seed
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33)
        }
        let paints: [[Int]] = [[240, 240, 240, 255], [30, 30, 30, 255], [10, 120, 250, 255], [0, 0, 0, 0]]
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // Blocks of paint, so regions have size, with noise on top.
                let paint = paints[((x / 5) + (y / 4) * 3 + next() % 2) % paints.count]
                for c in 0..<4 {
                    let n = jitter == 0 ? 0 : next() % (2 * jitter + 1) - jitter
                    bytes[(y * width + x) * 4 + c] = UInt8(clamping: paint[c] + n)
                }
            }
        }
        return bytes
    }

    static func flood(_ px: [UInt8], _ w: Int, _ h: Int) -> [Int32] {
        let tol = BoxSweep.colorTolerance
        func same(_ i: Int, _ j: Int) -> Bool {
            (0..<4).allSatisfy { abs(Int(px[i * 4 + $0]) - Int(px[j * 4 + $0])) <= tol }
        }
        var label = [Int32](repeating: -1, count: w * h)
        for start in 0..<(w * h) where label[start] < 0 {
            label[start] = Int32(start)
            var stack = [start]
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let j = ny * w + nx
                    if label[j] < 0, same(i, j) {
                        label[j] = Int32(start)
                        stack.append(j)
                    }
                }
            }
        }
        return label
    }

    /// Islands by flood: every pixel off the backdrop, joined to its four
    /// neighbours, numbered in the order a reader meets them.
    static func floodIslands(_ backdrop: [UInt8], _ w: Int, _ h: Int) -> ([Int32], [BoxSweep.Island]) {
        var labels = [Int32](repeating: 0, count: w * h)
        var found: [BoxSweep.Island] = []
        for start in 0..<(w * h) where backdrop[start] != 1 && labels[start] == 0 {
            var island = BoxSweep.Island(id: Int32(found.count + 1))
            labels[start] = island.id
            var stack = [start]
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                island.x0 = min(island.x0, x); island.x1 = max(island.x1, x)
                island.y0 = min(island.y0, y); island.y1 = max(island.y1, y)
                island.area += 1
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { island.cut = true }
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let j = ny * w + nx
                    if backdrop[j] != 1, labels[j] == 0 {
                        labels[j] = island.id
                        stack.append(j)
                    }
                }
            }
            found.append(island)
        }
        return (labels, found)
    }

    static func same(_ a: [BoxSweep.Island], _ b: [BoxSweep.Island]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            ($0.id, $0.x0, $0.y0, $0.x1, $0.y1) == ($1.id, $1.x0, $1.y0, $1.x1, $1.y1)
                && ($0.area, $0.cut) == ($1.area, $1.cut)
        }
    }

    @Test("Islands off the backdrop are the pieces a flood finds, cut ones dropped only when asked",
          arguments: [(37, 23, UInt64(7)), (64, 48, UInt64(8)), (1, 9, UInt64(9)), (12, 12, UInt64(10))])
    func islandsMatchAFlood(width: Int, height: Int, seed: UInt64) {
        let px = Self.picture(width: width, height: height, seed: seed, jitter: 0)
        // Backdrop is the light paint; everything else is something on it.
        let backdrop = (0..<(width * height)).map { UInt8(px[$0 * 4] == 240 ? 1 : 0) }
        let (floodLabels, floodFound) = Self.floodIslands(backdrop, width, height)

        let (kept, keptFound) = BoxSweep.islands(notIn: backdrop, width: width, height: height,
                                                 droppingCut: false)
        #expect(kept == floodLabels)
        #expect(Self.same(keptFound, floodFound))

        let (labels, found) = BoxSweep.islands(notIn: backdrop, width: width, height: height)
        let cut = Set(floodFound.filter(\.cut).map(\.id))
        #expect(labels == floodLabels.map { cut.contains($0) ? 0 : $0 })
        var whole = floodFound.filter { !$0.cut }
        for i in whole.indices { whole[i].cut = false }
        #expect(Self.same(found, whole))
    }

    @Test("Each pixel lands in the region a flood from it reaches", arguments: [
        (37, 23, UInt64(1), 0), (37, 23, UInt64(2), 2), (64, 48, UInt64(3), 3), (19, 61, UInt64(4), 5),
        (1, 9, UInt64(5), 2), (9, 1, UInt64(6), 2),
    ])
    func matchesAFlood(width: Int, height: Int, seed: UInt64, jitter: Int) {
        let px = Self.picture(width: width, height: height, seed: seed, jitter: jitter)
        #expect(BoxSweep.labelRegions(px, width, height) == Self.flood(px, width, height))
    }
}
