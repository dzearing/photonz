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

    // MARK: Candidate list (explicit Size mode: [ and ] grow/shrink the pick)

    @Test func candidatesGrowOutwardFromTheInnermost() {
        var s = Scene(w: 500, h: 400)
        s.addBox(CGRect(x: 20, y: 20, width: 440, height: 330))   // card
        s.addBox(CGRect(x: 100, y: 100, width: 200, height: 100)) // button
        let list = ElementBounds.candidates(at: CGPoint(x: 150, y: 150), in: s.map)
        #expect(list.first == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(list.contains(CGRect(x: 20, y: 20, width: 440, height: 330)))
        // Strictly nested, innermost first.
        for (inner, outer) in zip(list, list.dropFirst()) {
            #expect(outer.contains(inner))
        }
    }

    @Test func detectIsTheFirstCandidate() {
        var s = Scene(w: 500, h: 400)
        s.addBox(CGRect(x: 20, y: 20, width: 440, height: 330))
        s.addBox(CGRect(x: 100, y: 100, width: 200, height: 100))
        let probe = CGPoint(x: 150, y: 150)
        #expect(ElementBounds.detect(at: probe, in: s.map)
                == ElementBounds.candidates(at: probe, in: s.map).first)
    }

    @Test func aProbeOverTextStillReachesTheButtonByGrowing() {
        // The exact failure the last audit measured: two glyph strokes inside a
        // button win the nearest-edge walk, so the first guess is a sliver of
        // text. Growing the pick must reach the button itself.
        var s = Scene(w: 500, h: 400)
        let button = CGRect(x: 100, y: 100, width: 200, height: 60)
        s.addBox(button)
        s.addVerticalEdge(col: 190, y0: 120, y1: 140)
        s.addVerticalEdge(col: 200, y0: 120, y1: 140)
        let list = ElementBounds.candidates(at: CGPoint(x: 195, y: 130), in: s.map)
        #expect(list.first != button)      // the sliver is still the first guess
        #expect(list.contains(button))     // but the button is one press away
    }

    @Test func flatBackgroundOffersNoCandidates() {
        let s = Scene(w: 400, h: 300)
        #expect(ElementBounds.candidates(at: CGPoint(x: 200, y: 150), in: s.map).isEmpty)
    }

    @Test func candidateListStaysShort() {
        // Deeply nested boxes must not hand the UI an endless ladder.
        var s = Scene(w: 900, h: 900)
        for i in 0..<12 {
            let inset = CGFloat(i) * 30
            s.addBox(CGRect(x: 20 + inset, y: 20 + inset,
                            width: 860 - inset * 2, height: 860 - inset * 2))
        }
        let list = ElementBounds.candidates(at: CGPoint(x: 450, y: 450), in: s.map)
        #expect(!list.isEmpty)
        #expect(list.count <= ElementBounds.candidateLimit)
    }

    // MARK: Gap mode (click in the space between two elements)

    @Test func gapReadsTheShorterSpanThroughTheClick() {
        // Two buttons side by side inside a tall card: clicking between them
        // must measure the 40 px horizontal gap, not the card's height.
        var s = Scene(w: 600, h: 500)
        s.addBox(CGRect(x: 20, y: 20, width: 560, height: 440))
        s.addBox(CGRect(x: 100, y: 150, width: 120, height: 60))
        s.addBox(CGRect(x: 260, y: 150, width: 120, height: 60))
        let gap = ElementBounds.gap(at: CGPoint(x: 240, y: 180), in: s.map)
        #expect(gap?.axis == .horizontal)
        #expect(gap?.length == 40)
        #expect(gap?.start == CGPoint(x: 220, y: 180))
        #expect(gap?.end == CGPoint(x: 260, y: 180))
    }

    @Test func gapReadsAVerticalStackToo() {
        var s = Scene(w: 600, h: 500)
        s.addBox(CGRect(x: 20, y: 20, width: 560, height: 440))
        s.addBox(CGRect(x: 100, y: 100, width: 400, height: 60))
        s.addBox(CGRect(x: 100, y: 184, width: 400, height: 60))
        let gap = ElementBounds.gap(at: CGPoint(x: 300, y: 172), in: s.map)
        #expect(gap?.axis == .vertical)
        #expect(gap?.length == 24)
        #expect(gap?.start == CGPoint(x: 300, y: 160))
        #expect(gap?.end == CGPoint(x: 300, y: 184))
    }

    @Test func gapOnFlatBackgroundIsAQuietMiss() {
        let s = Scene(w: 400, h: 300)
        #expect(ElementBounds.gap(at: CGPoint(x: 200, y: 150), in: s.map) == nil)
    }

    @Test func gapNeedsOnlyTheAxisItMeasures() {
        // Two stacked cards with nothing to their left or right: the space
        // between them has a top and a bottom and no sides at all. Refusing to
        // measure it would fail the most ordinary gap there is.
        var s = Scene(w: 600, h: 500)
        s.addHorizontalEdge(row: 200, x0: 0, x1: 599)
        s.addHorizontalEdge(row: 240, x0: 0, x1: 599)
        let gap = ElementBounds.gap(at: CGPoint(x: 300, y: 220), in: s.map)
        #expect(gap?.axis == .vertical)
        #expect(gap?.length == 40)
        // The element reading still needs all four sides, so it stays quiet.
        #expect(ElementBounds.detect(at: CGPoint(x: 300, y: 220), in: s.map) == nil)
    }
}
