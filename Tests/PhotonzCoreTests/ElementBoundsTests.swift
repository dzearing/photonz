import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Synthetic gradient fields for hover-to-measure detection, built the same way
/// `EdgeMapTests` builds them: a box is four edge responses (two |Gy| rows, two
/// |Gx| columns) spanning each other's extent, exactly the structure a button or
/// settings row leaves in a screenshot.
private struct Scene {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]
    var luma: [Double]?

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        gx = [Double](repeating: 0, count: w * h)
        gy = [Double](repeating: 0, count: w * h)
    }

    mutating func addHorizontalEdge(row: Int, x0: Int, x1: Int, magnitude: Double = 2.0) {
        for x in max(0, x0)...min(w - 1, x1) { gy[row * w + x] = magnitude }
    }

    mutating func addVerticalEdge(col: Int, y0: Int, y1: Int, magnitude: Double = 2.0) {
        for y in max(0, y0)...min(h - 1, y1) { gx[y * w + col] = magnitude }
    }

    /// A rectangular element outline: edges on all four sides.
    mutating func addBox(_ r: CGRect, magnitude: Double = 2.0) {
        addHorizontalEdge(row: Int(r.minY), x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
        addHorizontalEdge(row: Int(r.maxY), x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
        addVerticalEdge(col: Int(r.minX), y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
        addVerticalEdge(col: Int(r.maxX), y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
    }

    var map: EdgeMap {
        EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: luma)
    }
}

@Suite("ElementBounds hover detection")
struct ElementBoundsTests {

    @Test func findsTheBoxAroundTheProbe() {
        var s = Scene(w: 400, h: 300)
        s.addBox(CGRect(x: 60, y: 50, width: 140, height: 70))
        let rect = ElementBounds.detect(at: CGPoint(x: 130, y: 80), in: s.map)
        #expect(rect == CGRect(x: 60, y: 50, width: 140, height: 70))
    }

    @Test func anyMissingSideIsAQuietMiss() {
        // Same box minus its right edge: rather than guess a wrong rect, report
        // nothing at all.
        var s = Scene(w: 400, h: 300)
        let r = CGRect(x: 60, y: 50, width: 140, height: 70)
        s.addHorizontalEdge(row: Int(r.minY), x0: Int(r.minX), x1: Int(r.maxX))
        s.addHorizontalEdge(row: Int(r.maxY), x0: Int(r.minX), x1: Int(r.maxX))
        s.addVerticalEdge(col: Int(r.minX), y0: Int(r.minY), y1: Int(r.maxY))
        #expect(ElementBounds.detect(at: CGPoint(x: 130, y: 80), in: s.map) == nil)
    }

    @Test func flatRegionShowsNothing() {
        let s = Scene(w: 400, h: 300)
        #expect(ElementBounds.detect(at: CGPoint(x: 200, y: 150), in: s.map) == nil)
    }

    @Test func nestedElementsResolveToTheInnermost() {
        // A button inside a card: the probe sits in the button, so the nearest
        // edge in every direction is the button's, never the card's.
        var s = Scene(w: 500, h: 400)
        s.addBox(CGRect(x: 20, y: 20, width: 440, height: 330))   // card
        s.addBox(CGRect(x: 100, y: 100, width: 200, height: 100)) // button
        let rect = ElementBounds.detect(at: CGPoint(x: 150, y: 150), in: s.map)
        #expect(rect == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func probeInTheCardGutterFindsTheCardNotTheButton() {
        // Between the button and the card wall, the card's edges are nearest on
        // the outer sides and the detection spans the card, not the button.
        var s = Scene(w: 500, h: 400)
        s.addBox(CGRect(x: 20, y: 20, width: 440, height: 330))
        s.addBox(CGRect(x: 100, y: 100, width: 200, height: 100))
        let rect = ElementBounds.detect(at: CGPoint(x: 150, y: 40), in: s.map)
        #expect(rect?.minY == 20)
        #expect(rect?.minX == 20)
    }

    @Test func sidesBeyondMaxRadiusDoNotCount() {
        // A very wide box: within the default radius it reads fine, but with a
        // tight radius the left/right walls are out of reach and the whole
        // readout stays quiet.
        var s = Scene(w: 1200, h: 300)
        s.addBox(CGRect(x: 10, y: 40, width: 1090, height: 80))
        let probe = CGPoint(x: 550, y: 80)
        #expect(ElementBounds.detect(at: probe, in: s.map) != nil)
        #expect(ElementBounds.detect(at: probe, in: s.map, maxRadius: 300) == nil)
    }

    @Test func emptyMapMissesQuietly() {
        #expect(ElementBounds.detect(at: CGPoint(x: 50, y: 50), in: .empty) == nil)
    }

    @Test func detectionStaysWellInsideTheMouseMoveBudget() {
        // Spec budget: under 1 ms per mouse move on a 12-megapixel document.
        // Asserted with generous slack so the test never flakes on a busy
        // machine while still catching a regression to full-image scans.
        var s = Scene(w: 4000, h: 3000)
        s.addBox(CGRect(x: 1800, y: 1400, width: 400, height: 200))
        let map = s.map
        let start = ContinuousClock.now
        for i in 0..<200 {
            _ = ElementBounds.detect(at: CGPoint(x: 1900 + i % 50, y: 1450), in: map)
        }
        let average = (ContinuousClock.now - start) / 200
        #expect(average < .milliseconds(5))
    }

    @Test func sidesLandOnTheProbeSideLumaLanding() {
        // The top edge has an antialiasing glow: the peak sits at row 50, the
        // visually clean element side starts at row 52. The rect's top must use
        // the probe-side landing (the same rule snapping uses), not the raw peak.
        var s = Scene(w: 400, h: 300)
        s.addBox(CGRect(x: 60, y: 50, width: 140, height: 70))
        var luma = [Double](repeating: 0.4, count: 400 * 300)
        for row in 0..<50 { for col in 0..<400 { luma[row * 400 + col] = 1.0 } }
        for col in 0..<400 {
            luma[50 * 400 + col] = 0.6  // the peak straddles the transition
            luma[51 * 400 + col] = 0.45 // glow row, still off background
        }
        s.luma = luma
        let rect = ElementBounds.detect(at: CGPoint(x: 130, y: 90), in: s.map)
        #expect(rect?.minY == 52)
        #expect(rect?.maxY == 120)
    }
}
