import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Builds synthetic |Gx| / |Gy| magnitude fields (top-left row order) the way the
/// analyzer would produce them, so core windowed-query logic is tested without CI.
private struct Field {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        gx = [Double](repeating: 0, count: w * h)
        gy = [Double](repeating: 0, count: w * h)
    }

    /// A horizontal boundary (like a text top/baseline or a divider): |Gy| response
    /// at `row`, spanning columns `x0...x1`.
    mutating func addHorizontalEdge(row: Int, x0: Int, x1: Int, magnitude: Double) {
        for x in max(0, x0)...min(w - 1, x1) { gy[row * w + x] = magnitude }
    }

    /// A vertical boundary (container border, start of a text run): |Gx| response
    /// at `col`, spanning rows `y0...y1`.
    mutating func addVerticalEdge(col: Int, y0: Int, y1: Int, magnitude: Double) {
        for y in max(0, y0)...min(h - 1, y1) { gx[y * w + col] = magnitude }
    }

    var map: EdgeMap {
        EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy)
    }
}

@Suite("EdgeMap windowed queries")
struct EdgeMapWindowTests {

    @Test func findsLocalTextEdgeInsideItsWindowOnly() {
        // A text-top-like edge spanning cols 100...200 at row 50, in a big image.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200, magnitude: 2.0)
        let map = f.map

        let inWindow = map.horizontalEdges(inXRange: 100...200)
        #expect(inWindow.map(\.position) == [50])

        // A window elsewhere sees nothing — locality is the whole point.
        #expect(map.horizontalEdges(inXRange: 400...500).isEmpty)
    }

    @Test func fullWidthDividerDoesNotDrownALocalTextEdge() {
        // The failure of the global approach: a strong divider must not suppress a
        // weaker text top inside the same window. Acceptance is floor-based.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 10, x0: 0, x1: 799, magnitude: 4.0)   // divider
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200, magnitude: 1.2) // text top
        let map = f.map

        let found = map.horizontalEdges(inXRange: 100...200).map(\.position)
        #expect(found.contains(10))
        #expect(found.contains(50))
    }

    @Test func verticalEdgesQueryIsTheXAxisAnalog() {
        var f = Field(w: 400, h: 800)
        f.addVerticalEdge(col: 80, y0: 20, y1: 60, magnitude: 2.0)
        let map = f.map

        #expect(map.verticalEdges(inYRange: 20...60).map(\.position) == [80])
        #expect(map.verticalEdges(inYRange: 300...400).isEmpty)
    }

    @Test func faintNoiseStaysBelowTheAbsoluteFloor() {
        // A uniform faint gradient field (background noise) yields no candidates,
        // even though relative-to-window-max thresholding alone would pass it.
        var f = Field(w: 200, h: 200)
        for i in 0..<(200 * 200) { f.gy[i] = 0.05 }
        #expect(f.map.horizontalEdges(inXRange: 50...150).isEmpty)
    }

    @Test func partialCoverageEdgeStillClearsTheFloor() {
        // Glyph tops don't cover every column of the window. 40% coverage at
        // magnitude 1.5 → windowed mean 0.6, above the floor.
        var f = Field(w: 400, h: 200)
        var x = 100
        while x < 200 { // ink every 2nd/3rd column band
            f.addHorizontalEdge(row: 80, x0: x, x1: x + 3, magnitude: 1.5)
            x += 10
        }
        let found = f.map.horizontalEdges(inXRange: 100...200).map(\.position)
        #expect(found == [80])
    }

    @Test func adjacentAntialiasedRowsDedupeToOne() {
        // Antialiasing spreads a boundary over 2 rows; the stronger one wins.
        var f = Field(w: 300, h: 200)
        f.addHorizontalEdge(row: 60, x0: 50, x1: 250, magnitude: 2.0)
        f.addHorizontalEdge(row: 61, x0: 50, x1: 250, magnitude: 1.1)
        let found = f.map.horizontalEdges(inXRange: 50...250)
        #expect(found.map(\.position) == [60])
    }

    @Test func outOfBoundsWindowsAreClampedNotCrashing() {
        var f = Field(w: 100, h: 100)
        f.addHorizontalEdge(row: 40, x0: 0, x1: 99, magnitude: 2.0)
        let map = f.map
        #expect(map.horizontalEdges(inXRange: -50...500).map(\.position) == [40])
        #expect(map.verticalEdges(inYRange: -10...(-5)).isEmpty)
    }

    @Test func emptyMapIsEmptyAndReturnsNothing() {
        #expect(EdgeMap.empty.isEmpty)
        #expect(EdgeMap.empty.horizontalEdges(inXRange: 0...100).isEmpty)
        #expect(EdgeMap.empty.verticalEdges(inYRange: 0...100).isEmpty)
    }
}

/// The band-energy queries an alignment guide uses to learn which side of an
/// edge the element is on: mean gradient per pixel over a rectangle, rounded
/// outward to the map's blocks along the guide's axis.
@Suite("EdgeMap band energy")
struct EdgeMapBandEnergyTests {

    @Test func verticalEnergyReadsInkOnlyWhereItIs() {
        var f = Field(w: 400, h: 200)
        // A text run to the right of x=100: many vertical strokes, rows 40..60.
        var x = 104
        while x < 150 {
            f.addVerticalEdge(col: x, y0: 40, y1: 60, magnitude: 1.0)
            x += 4
        }
        let map = f.map
        let right = map.verticalGradientEnergy(xRange: 103...120, inYRange: 40...60)
        let left = map.verticalGradientEnergy(xRange: 80...97, inYRange: 40...60)
        #expect(right > 0.1)
        #expect(left == 0)
        // Elsewhere along the axis the same columns are empty.
        #expect(map.verticalGradientEnergy(xRange: 103...120, inYRange: 120...140) == 0)
    }

    @Test func horizontalEnergyIsTheYAxisAnalog() {
        var f = Field(w: 400, h: 200)
        var y = 64
        while y < 90 {
            f.addHorizontalEdge(row: y, x0: 20, x1: 120, magnitude: 1.0)
            y += 4
        }
        let map = f.map
        #expect(map.horizontalGradientEnergy(yRange: 63...80, inXRange: 20...120) > 0.1)
        #expect(map.horizontalGradientEnergy(yRange: 40...57, inXRange: 20...120) == 0)
    }

    @Test func energyOutsideTheImageOrOnAnEmptyMapIsZero() {
        #expect(EdgeMap.empty.verticalGradientEnergy(xRange: 0...10, inYRange: 0...10) == 0)
        let f = Field(w: 50, h: 50)
        #expect(f.map.verticalGradientEnergy(xRange: 60...80, inYRange: 0...10) == 0)
        #expect(f.map.horizontalGradientEnergy(yRange: -20...(-5), inXRange: 0...10) == 0)
    }
}

