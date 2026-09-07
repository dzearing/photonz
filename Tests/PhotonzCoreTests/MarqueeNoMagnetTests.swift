import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A synthetic gradient field, the same shape the analyzer hands `EdgeMap`.
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

    mutating func addHorizontalEdge(row: Int, x0: Int, x1: Int, magnitude: Double = 2) {
        for x in max(0, x0)...min(w - 1, x1) { gy[row * w + x] = magnitude }
    }

    mutating func addVerticalEdge(col: Int, y0: Int, y1: Int, magnitude: Double = 2) {
        for y in max(0, y0)...min(h - 1, y1) { gx[y * w + col] = magnitude }
    }

    var map: EdgeMap { EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy) }
}

/// A marquee is a rectangle you are choosing BY HAND, so both of its corners
/// are the pointer and nothing else. Reported by the user on 2026-09-07: a
/// selection dragged over a screenshot was pulled onto borders found in the
/// picture, whatever the grid or the snapping switch said, and a 67x27 sweep
/// came out 41x1. These tests hold the corners on the pointer, and each one
/// first proves the edge underneath is strong enough to have moved them.
@Suite("Marquee takes no magnet")
struct MarqueeNoMagnetTests {
    let canvas = CGSize(width: 800, height: 600)

    /// The edge map every test here drags across: a border down x=200 and one
    /// across y=100, both well inside the canvas.
    private var edges: EdgeMap {
        var f = Field(w: 800, h: 600)
        f.addVerticalEdge(col: 200, y0: 0, y1: 599)
        f.addHorizontalEdge(row: 100, x0: 0, x1: 799)
        return f.map
    }

    @Test func theEdgeIsStrongEnoughToPull() {
        // Guards the tests below from passing on a fixture nothing would catch:
        // a caliper foot at the same spot DOES land on both borders.
        let snap = EdgeSnapping.snap(CGPoint(x: 203, y: 104), edges: edges, zoom: 1,
                                     snapToPixelGrid: false)
        #expect(snap.point == CGPoint(x: 200, y: 100))
    }

    @Test func cornerStaysOnThePointerOverAnEdge() {
        #expect(MarqueeDrag.corner(at: CGPoint(x: 203, y: 104)) == CGPoint(x: 203, y: 104))
    }

    @Test func cornerStaysOnThePointerBetweenPixels() {
        // Half zoom means one step of the mouse is two image pixels, so a
        // corner lands off the pixel grid. That is where the pointer is.
        #expect(MarqueeDrag.corner(at: CGPoint(x: 203.5, y: 104.5))
                == CGPoint(x: 203.5, y: 104.5))
    }

    @Test func dragAcrossAnEdgeIsExactlyTheRectangleDrawn() {
        // The user's report in numbers: press just past a border, drag past a
        // second one, and get the rectangle you drew.
        var drag = MarqueeDrag(anchor: MarqueeDrag.corner(at: CGPoint(x: 203, y: 104)))
        drag.update(to: MarqueeDrag.corner(at: CGPoint(x: 270, y: 131)))
        #expect(drag.selectionRect(in: canvas) == CGRect(x: 203, y: 104, width: 67, height: 27))
    }
}
