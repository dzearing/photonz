import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The edges near one line, found without reading the whole row: what an
/// alignment guide asks on every move. They must be EXACTLY the edges the
/// whole-row query finds inside that band, strengths included, since a
/// strength is measured against the strongest edge anywhere in the row.
@Suite("Edges near a line")
struct EdgeMapNearTests {

    /// A noisy field with real structure: boxes, a text-like comb, and a
    /// deterministic scatter of weak responses, so peaks crowd each other.
    private static func busyMap(withLuma: Bool) -> EdgeMap {
        let w = 640, h = 400
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        var luma = [Double](repeating: 0.9, count: w * h)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for i in 0..<(w * h) {
            gx[i] = random() * 0.3
            gy[i] = random() * 0.3
        }
        for (x, y0, y1, m) in [(40, 20, 300, 3.0), (44, 20, 300, 1.0), (300, 50, 390, 2.0),
                               (303, 60, 200, 2.5), (600, 0, 399, 4.0)] {
            for y in y0...y1 { gx[y * w + x] += m }
        }
        for (y, x0, x1, m) in [(30, 10, 630, 3.0), (33, 100, 400, 1.5), (250, 0, 639, 2.0)] {
            for x in x0...x1 { gy[y * w + x] += m }
        }
        for x in stride(from: 120, to: 260, by: 4) {
            for y in 140...170 { gx[y * w + x] += 1.2; luma[y * w + x] = 0.2 }
        }
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy,
                       luma: withLuma ? luma : nil)
    }

    @Test(arguments: [false, true])
    func verticalEdgesNearALineMatchTheWholeRow(withLuma: Bool) {
        let map = Self.busyMap(withLuma: withLuma)
        for y in stride(from: 0.0, through: 400, by: 7) {
            let window = (y - 4)...(y + 4)
            let all = map.verticalEdges(inYRange: window)
            for x in stride(from: 0.0, through: 640, by: 11) {
                let band = (x - 12)...(x + 12)
                let near = map.verticalEdges(inYRange: window, near: band)
                #expect(near == all.filter { band.contains($0.position) },
                        "y \(y), x \(x)")
            }
        }
    }

    @Test(arguments: [false, true])
    func horizontalEdgesNearALineMatchTheWholeColumn(withLuma: Bool) {
        let map = Self.busyMap(withLuma: withLuma)
        for x in stride(from: 0.0, through: 640, by: 9) {
            let window = (x - 4)...(x + 4)
            let all = map.horizontalEdges(inXRange: window)
            for y in stride(from: 0.0, through: 400, by: 13) {
                let band = (y - 12)...(y + 12)
                let near = map.horizontalEdges(inXRange: window, near: band)
                #expect(near == all.filter { band.contains($0.position) },
                        "x \(x), y \(y)")
            }
        }
    }

    @Test func aWideWindowStillMatches() {
        // More than two blocks: no stored maximum covers it, so it is summed.
        let map = Self.busyMap(withLuma: true)
        let window = 20.0...200.0
        let band = 290.0...310.0
        #expect(map.verticalEdges(inYRange: window, near: band)
                == map.verticalEdges(inYRange: window).filter { band.contains($0.position) })
    }

    @Test func anEmptyMapFindsNothingNearAnything() {
        #expect(EdgeMap.empty.verticalEdges(inYRange: 0...10, near: 0...10).isEmpty)
        #expect(EdgeMap.empty.horizontalEdges(inXRange: 0...10, near: 0...10).isEmpty)
    }
}
