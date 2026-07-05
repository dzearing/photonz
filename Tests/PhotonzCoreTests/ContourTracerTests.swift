import CoreGraphics
import PhotonzCore
import Testing

@Suite("ContourTracer")
struct ContourTracerTests {

    /// Builds a mask from an ASCII picture: '#' = filled, anything else empty.
    private func mask(_ rows: [String]) -> (mask: [Bool], width: Int, height: Int) {
        let width = rows.map(\.count).max() ?? 0
        var bits = [Bool]()
        for row in rows {
            let cells = Array(row)
            for x in 0..<width { bits.append(x < cells.count && cells[x] == "#") }
        }
        return (bits, width, rows.count)
    }

    private func contains(_ path: CGPath, _ x: CGFloat, _ y: CGFloat) -> Bool {
        path.contains(CGPoint(x: x, y: y), using: .evenOdd)
    }

    private func subpathCount(_ path: CGPath) -> Int {
        var moves = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { moves += 1 }
        }
        return moves
    }

    // MARK: Basics

    @Test func emptyMaskYieldsNoPath() {
        let m = mask(["...", "...", "..."])
        #expect(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height) == nil)
    }

    @Test func mismatchedMaskSizeYieldsNoPath() {
        #expect(ContourTracer.path(fromMask: [true, true], width: 3, height: 3) == nil)
    }

    @Test func singlePixelTracesItsUnitSquare() throws {
        let m = mask(["...", ".#.", "..."])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(path.boundingBoxOfPath == CGRect(x: 1, y: 1, width: 1, height: 1))
        #expect(contains(path, 1.5, 1.5))
        #expect(!contains(path, 0.5, 0.5))
        #expect(subpathCount(path) == 1)
    }

    @Test func fullFrameTracesTheWholeBounds() throws {
        let m = mask(["###", "###", "###"])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 3, height: 3))
        #expect(contains(path, 0.5, 0.5))
        #expect(contains(path, 2.5, 2.5))
        #expect(subpathCount(path) == 1)
    }

    @Test func rectangularBlobHasTightBounds() throws {
        let m = mask([
            ".....",
            ".###.",
            ".###.",
            ".....",
        ])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(path.boundingBoxOfPath == CGRect(x: 1, y: 1, width: 3, height: 2))
        #expect(contains(path, 2.5, 1.5))
        #expect(!contains(path, 0.5, 1.5))
        #expect(!contains(path, 4.5, 2.5))
    }

    // MARK: Multiple contours & holes

    @Test func twoBlobsProduceTwoSubpaths() throws {
        let m = mask([
            "##...",
            "##...",
            ".....",
            "...##",
            "...##",
        ])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(subpathCount(path) == 2)
        #expect(contains(path, 0.5, 0.5))
        #expect(contains(path, 4.5, 4.5))
        #expect(!contains(path, 2.5, 2.5))
    }

    @Test func holeIsExcludedByEvenOdd() throws {
        let m = mask([
            "#####",
            "#...#",
            "#.#.#",
            "#...#",
            "#####",
        ])
        // A ring with a floating pixel inside its hole: outer boundary, hole
        // boundary, and the island each get a contour.
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(subpathCount(path) == 3)
        #expect(contains(path, 0.5, 0.5))    // ring
        #expect(!contains(path, 1.5, 1.5))   // hole
        #expect(contains(path, 2.5, 2.5))    // island inside the hole
        #expect(!contains(path, 3.5, 2.5))   // hole, other side of the island
    }

    @Test func simpleDonutHole() throws {
        let m = mask([
            "###",
            "#.#",
            "###",
        ])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(subpathCount(path) == 2)
        #expect(!contains(path, 1.5, 1.5))
        #expect(contains(path, 0.5, 1.5))
        #expect(contains(path, 2.5, 1.5))
    }

    // MARK: Diagonal adjacency

    @Test func diagonallyTouchingPixelsStaySeparateBlobs() throws {
        let m = mask([
            "#.",
            ".#",
        ])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(subpathCount(path) == 2)
        #expect(contains(path, 0.5, 0.5))
        #expect(contains(path, 1.5, 1.5))
        #expect(!contains(path, 1.5, 0.5))
        #expect(!contains(path, 0.5, 1.5))
    }

    @Test func lShapeTracesOneContour() throws {
        let m = mask([
            "#..",
            "#..",
            "###",
        ])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        #expect(subpathCount(path) == 1)
        #expect(contains(path, 0.5, 0.5))
        #expect(contains(path, 2.5, 2.5))
        #expect(!contains(path, 1.5, 0.5))
        #expect(!contains(path, 2.5, 1.5))
    }

    // MARK: Composes with SelectionRegion

    @Test func tracedPathWrapsIntoASelectionRegion() throws {
        let m = mask([
            ".##",
            ".##",
        ])
        let path = try #require(ContourTracer.path(fromMask: m.mask, width: m.width, height: m.height))
        let region = try #require(SelectionRegion(path: path))
        #expect(region.bounds == CGRect(x: 1, y: 0, width: 2, height: 2))
        #expect(region.contains(CGPoint(x: 1.5, y: 0.5)))
        // And booleans work on it: subtract the right column.
        let cut = try #require(SelectionRegion.rect(CGRect(x: 2, y: 0, width: 1, height: 2)))
        let remaining = try #require(region.combining(cut, mode: .subtract))
        #expect(remaining.contains(CGPoint(x: 1.5, y: 1.5)))
        #expect(!remaining.contains(CGPoint(x: 2.5, y: 1.5)))
    }
}
