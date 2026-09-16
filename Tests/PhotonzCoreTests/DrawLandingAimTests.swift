import CoreGraphics
import Foundation
import PhotonzCore
import Testing

// When the aiming ring has something to say, and when it has nothing.
//
// The ring under the pointer (`CanvasDrawLanding`) is drawn exactly when a
// press would put the point somewhere the pointer is not. Until now that was
// read as "the grid is pulling", which left out the case this file is about: a
// plain screenshot with no grid on, where the drawing tools quietly pull the
// first point onto a border they found in the picture. The question the ring
// asks is now `EdgeSnapping.Snap.isPlaced` — did a LINE place this point —
// which covers a grid line, a pinned guide and a border in the picture alike.

/// Synthetic gradient fields, mirroring what the analyzer produces from a
/// screenshot: a picture with a couple of hard borders in it.
private struct Picture {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        gx = [Double](repeating: 0, count: w * h)
        gy = [Double](repeating: 0, count: w * h)
    }

    mutating func verticalBorder(atX col: Int) {
        for y in 0..<h { gx[y * w + col] = 2 }
    }

    mutating func horizontalBorder(atY row: Int) {
        for x in 0..<w { gy[row * w + x] = 2 }
    }

    var map: EdgeMap { EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy) }
}

@Suite("What the aiming ring has to say")
struct DrawLandingAimTests {

    /// A 400 by 300 capture with one border down it at x = 120 and one across
    /// it at y = 80.
    private static let screenshot: EdgeMap = {
        var p = Picture(w: 400, h: 300)
        p.verticalBorder(atX: 120)
        p.horizontalBorder(atY: 80)
        return p.map
    }()

    /// The first point of a shape, asked the way the hover asks it: no other
    /// end yet, no memory of a drag.
    private func aim(_ point: CGPoint, edges: EdgeMap = .empty,
                     gridSpacing: CGFloat? = nil,
                     guides: [CanvasGuide] = []) -> EdgeSnapping.Snap {
        AnnotationSnapping.snap(point, shape: .rectangle, opposite: nil, edges: edges,
                                zoom: 1, free: false, holding: .none, gridHolding: .none,
                                gridSpacing: gridSpacing, gridOrigin: .zero,
                                gridAxes: .columnsAndRows, guides: guides)
    }

    // MARK: A screenshot, with no grid at all

    @Test func aBorderInThePicturePlacesTheFirstPoint() {
        // Four points to the right of the border at x = 120, grid off.
        let snap = aim(CGPoint(x: 124, y: 200), edges: Self.screenshot)
        #expect(snap.isPlaced)
        #expect(snap.guideX == 120)
        #expect(snap.point.x == 120)
        // The other axis found nothing to catch on, so it stayed under the hand.
        #expect(snap.guideY == nil)
        #expect(snap.point.y == 200)
    }

    @Test func aCornerOfThePictureTakesBothAxes() {
        let snap = aim(CGPoint(x: 125, y: 84), edges: Self.screenshot)
        #expect(snap.isPlaced)
        #expect(snap.point == CGPoint(x: 120, y: 80))
    }

    @Test func nothingNearEnoughToCatchSaysNothing() {
        // Out in the middle of the picture, far from either border: the press
        // would land under the pointer, so the ring must not be drawn.
        let snap = aim(CGPoint(x: 250, y: 200), edges: Self.screenshot)
        #expect(!snap.isPlaced)
        #expect(snap.guideX == nil)
        #expect(snap.guideY == nil)
        #expect(snap.point == CGPoint(x: 250, y: 200))
    }

    @Test func roundingToWholePixelsIsNotWorthAMark() {
        // A fraction of a pixel of rounding is not news, and a ring that rode
        // the cursor everywhere on a plain picture would be exactly that.
        let snap = aim(CGPoint(x: 250.4, y: 200.4), edges: Self.screenshot)
        #expect(!snap.isPlaced)
        #expect(snap.point == CGPoint(x: 250, y: 200))
    }

    @Test func aCanvasWithNoPictureInItSaysNothing() {
        // A blank canvas, grid off: nothing anywhere can place a point.
        for x in stride(from: CGFloat(4), to: 400, by: 37) {
            #expect(!aim(CGPoint(x: x, y: 200)).isPlaced)
        }
    }

    // MARK: The cases that already had the ring, unchanged

    @Test func aGridAlwaysPlacesThePoint() {
        // With the grid pulling there is always a crossing to land on, so the
        // ring shows wherever the pointer is — the behaviour it shipped with.
        for x in stride(from: CGFloat(4), to: 400, by: 37) {
            let snap = aim(CGPoint(x: x, y: 200), edges: Self.screenshot, gridSpacing: 32)
            #expect(snap.isPlaced)
        }
    }

    @Test func aPinnedGuidePlacesThePointWithNoGridPulling() {
        let snap = aim(CGPoint(x: 252, y: 200), edges: .empty, gridSpacing: nil,
                       guides: [CanvasGuide(axis: .vertical, position: 250)])
        #expect(snap.isPlaced)
        #expect(snap.point.x == 250)
    }

    @Test func refusingTheMagnetPlacesNothing() {
        // ⌘ means exactly where the pointer is, everywhere on this canvas.
        let snap = AnnotationSnapping.snap(CGPoint(x: 124, y: 84), shape: .rectangle,
                                           opposite: nil, edges: Self.screenshot,
                                           zoom: 1, free: true, gridSpacing: 32)
        #expect(!snap.isPlaced)
        #expect(snap.point == CGPoint(x: 124, y: 84))
    }
}
