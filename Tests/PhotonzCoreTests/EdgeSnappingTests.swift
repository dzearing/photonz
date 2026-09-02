import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Synthetic gradient fields, mirroring what the analyzer produces.
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

    var map: EdgeMap {
        EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy)
    }
}

@Suite("Edge snapping")
struct EdgeSnappingTests {

    @Test func horizontalLegSnapsToTextEdgeUnderItsSpan() {
        // A text-top edge spans cols 100...200 at y=50. Dragging the leg (whose
        // x-span covers the text) to y=53 snaps it onto the edge.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200)
        let snap = EdgeSnapping.snap(CGPoint(x: 205, y: 53), edges: f.map, zoom: 1,
                                     xSpan: 100...205, snapToPixelGrid: false)
        #expect(snap.point.y == 50)
        #expect(snap.guideY == 50)
    }

    @Test func legWhoseSpanMissesTheEdgeDoesNotSnapToIt() {
        // Same edge, but the leg lives entirely to the right of the text run — a
        // line that doesn't cross the edge must not magnetize to it.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200)
        let snap = EdgeSnapping.snap(CGPoint(x: 450, y: 53), edges: f.map, zoom: 1,
                                     xSpan: 400...500, snapToPixelGrid: false)
        #expect(snap.point.y == 53)
        #expect(snap.guideY == nil)
    }

    @Test func verticalLineSnapsToVerticalEdgeWithinItsYSpan() {
        var f = Field(w: 400, h: 800)
        f.addVerticalEdge(col: 80, y0: 100, y1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 84, y: 120), edges: f.map, zoom: 1,
                                     ySpan: 100...300, snapToPixelGrid: false)
        #expect(snap.point.x == 80)
        #expect(snap.guideX == 80)
    }

    @Test func axesSnapIndependently() {
        // y captures a horizontal edge; x has no vertical edge and rounds to grid.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200)
        let snap = EdgeSnapping.snap(CGPoint(x: 150.6, y: 47), edges: f.map, zoom: 1,
                                     xSpan: 100...200)
        #expect(snap.point.y == 50)
        #expect(snap.guideY == 50)
        #expect(snap.point.x == 151)
        #expect(snap.guideX == nil)
    }

    @Test func doesNotSnapBeyondTolerance() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200)
        // 20px away with an 8pt tolerance at zoom 1 — stays free.
        let snap = EdgeSnapping.snap(CGPoint(x: 150, y: 70), edges: f.map, zoom: 1,
                                     xSpan: 100...200, snapToPixelGrid: false)
        #expect(snap.point.y == 70)
        #expect(snap.guideY == nil)
    }

    @Test func toleranceScalesWithZoom() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200)
        // 6px away: zoom 1 (tol 8px) snaps; zoom 4 (tol 2px) doesn't.
        let out = EdgeSnapping.snap(CGPoint(x: 150, y: 56), edges: f.map, zoom: 1,
                                    xSpan: 100...200, snapToPixelGrid: false)
        #expect(out.point.y == 50)
        let zoomed = EdgeSnapping.snap(CGPoint(x: 150, y: 56), edges: f.map, zoom: 4,
                                       xSpan: 100...200, snapToPixelGrid: false)
        #expect(zoomed.point.y == 56)
    }

    @Test func nearestOfTwoEdgesWins() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200)
        f.addHorizontalEdge(row: 58, x0: 100, x1: 200)
        let snap = EdgeSnapping.snap(CGPoint(x: 150, y: 56), edges: f.map, zoom: 1,
                                     xSpan: 100...200, snapToPixelGrid: false)
        #expect(snap.point.y == 58) // 2px vs 6px away
    }

    @Test func defaultWindowIsAroundThePointWhenNoSpanGiven() {
        // No spans: a small neighborhood around the pointer still finds the edge.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 50, x0: 100, x1: 200, magnitude: 2)
        let snap = EdgeSnapping.snap(CGPoint(x: 150, y: 53), edges: f.map, zoom: 1,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 50)
    }

    @Test func faintHairlineDividerStillSnaps() {
        // Dark-mode card separators are faint (raw mean ~0.15, calibrated from the
        // user's real capture) — they must clear the floor and capture when
        // they're the only structure around.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 100, x0: 50, x1: 750, magnitude: 0.15)
        let snap = EdgeSnapping.snap(CGPoint(x: 400, y: 103), edges: f.map, zoom: 1,
                                     xSpan: 100...700, snapToPixelGrid: false)
        #expect(snap.point.y == 100)
        #expect(snap.guideY == 100)
    }

    @Test func strongBaselineBeatsANearerAntialiasingGhost() {
        // Text antialiasing leaves weak ghost rows near the real baseline. The
        // pick is strength-weighted: the strong baseline 4px away must beat the
        // faint ghost 2px away.
        var f = Field(w: 800, h: 800)
        f.addHorizontalEdge(row: 716, x0: 100, x1: 300, magnitude: 0.3)  // ghost
        f.addHorizontalEdge(row: 722, x0: 100, x1: 300, magnitude: 2.0)  // baseline
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 718), edges: f.map, zoom: 1,
                                     xSpan: 100...300, snapToPixelGrid: false)
        #expect(snap.point.y == 722)
    }

    @Test func pixelGridFallbackWhenNothingCaptures() {
        let snap = EdgeSnapping.snap(CGPoint(x: 42.7, y: 9.2),
                                     edges: Field(w: 100, h: 100).map, zoom: 1)
        #expect(snap.point == CGPoint(x: 43, y: 9))
        #expect(snap.guideX == nil)
        #expect(snap.guideY == nil)
    }

    @Test func toleranceNeverShrinksBelowFourImagePixels() {
        // Zoomed to 800%, screen tolerance ÷ zoom would be 1px — the magnet must
        // keep a 4px floor so high-zoom precision work still snaps.
        var f = Field(w: 200, h: 200)
        f.addHorizontalEdge(row: 50, x0: 0, x1: 199)
        let snap = EdgeSnapping.snap(CGPoint(x: 100, y: 53), edges: f.map, zoom: 8,
                                     xSpan: 0...199, snapToPixelGrid: false)
        #expect(snap.point.y == 50)
    }
}

// MARK: - Center candidates (`next-measure-center-snap`)

@Suite("Edge snapping centers")
struct EdgeSnappingCenterTests {

    @Test func midpointDoesNotCaptureWhenCentersAreOff() {
        // Element between rows 100 and 140; pointer 1px from its center. With
        // the default (edges only), nothing captures — both edges are far away.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 100, x0: 100, x1: 300)
        f.addHorizontalEdge(row: 140, x0: 100, x1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 121), edges: f.map, zoom: 1,
                                     xSpan: 100...300, snapToPixelGrid: false)
        #expect(snap.point.y == 121)
        #expect(snap.guideY == nil)
    }

    @Test func elementCenterCapturesWithCentersOn() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 100, x0: 100, x1: 300)
        f.addHorizontalEdge(row: 140, x0: 100, x1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 121), edges: f.map, zoom: 1,
                                     xSpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 120)
        #expect(snap.guideY == 120)
    }

    @Test func verticalCentersUseTheSameRule() {
        var f = Field(w: 400, h: 800)
        f.addVerticalEdge(col: 80, y0: 100, y1: 300)
        f.addVerticalEdge(col: 120, y0: 100, y1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 98, y: 200), edges: f.map, zoom: 1,
                                     ySpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.x == 100)
        #expect(snap.guideX == 100)
    }

    @Test func edgeBeatsCenterAtEqualDistance() {
        // Edges at 100 and 116 put the center at 108. Pointer at 104 is 4px from
        // both the edge and the center — the real edge must win the tie.
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 100, x0: 100, x1: 300)
        f.addHorizontalEdge(row: 116, x0: 100, x1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 104), edges: f.map, zoom: 1,
                                     xSpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 100)
    }

    @Test func gapCenterFallsOutOfTheSameRule() {
        // Two stacked elements (A: 40–60, B: 100–120). The midpoint between the
        // adjacent edges 60 and 100 IS the gap center — no special casing.
        var f = Field(w: 800, h: 400)
        for row in [40, 60, 100, 120] {
            f.addHorizontalEdge(row: row, x0: 100, x1: 300)
        }
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 78), edges: f.map, zoom: 1,
                                     xSpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 80)
        #expect(snap.guideY == 80)
    }

    @Test func smallElementCenterWinsAtItsExactMidpoint() {
        // A 12px-tall element keeps both edges inside tolerance from its center.
        // At the exact midpoint the center (distance 0, half strength) must beat
        // the edges (distance 6, full strength).
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 100, x0: 100, x1: 300)
        f.addHorizontalEdge(row: 112, x0: 100, x1: 300)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 106), edges: f.map, zoom: 1,
                                     xSpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 106)
        #expect(snap.guideY == 106)
    }

    @Test func centersRespectTolerance() {
        var f = Field(w: 800, h: 400)
        f.addHorizontalEdge(row: 100, x0: 100, x1: 300)
        f.addHorizontalEdge(row: 140, x0: 100, x1: 300)
        // 10px from the center (and both edges) with an 8px tolerance — free.
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 110), edges: f.map, zoom: 1,
                                     xSpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 110)
        #expect(snap.guideY == nil)
    }

    @Test func ghostPairMidpointStaysWeakerThanTheRealEdge() {
        // An antialiasing ghost near a baseline forms a pair whose midpoint must
        // not out-score the strong real edge: the FAINTER member sets the
        // midpoint's strength.
        var f = Field(w: 800, h: 800)
        f.addHorizontalEdge(row: 716, x0: 100, x1: 300, magnitude: 0.3)  // ghost
        f.addHorizontalEdge(row: 722, x0: 100, x1: 300, magnitude: 2.0)  // baseline
        // Pointer at 719: midpoint (719, distance 0) vs baseline (distance 3).
        // Midpoint score 0.5·0.3 = 0.15; baseline 2.0/1.75 ≈ 1.14 — edge wins.
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 719), edges: f.map, zoom: 1,
                                     xSpan: 100...300, includeCenters: true,
                                     snapToPixelGrid: false)
        #expect(snap.point.y == 722)
    }
}

// MARK: - Landing refinement & approach side

/// Builds a map from a 1-D luma row profile replicated across the width, with
/// |Gy| derived the way Sobel sees it (4 × the two-row luma delta) so gradient
/// and luma stay physically consistent. Values are perceptual (√linear), the
/// units the analyzer stores.
private func mapFromLumaRows(_ rows: [Double], w: Int = 400) -> EdgeMap {
    let h = rows.count
    var gy = [Double](repeating: 0, count: w * h)
    var luma = [Double](repeating: 0, count: w * h)
    for r in 0..<h {
        let g = 4 * abs(rows[min(r + 1, h - 1)] - rows[max(r - 1, 0)])
        for x in 0..<w {
            luma[r * w + x] = rows[r]
            gy[r * w + x] = g
        }
    }
    return EdgeMap(width: w, height: h,
                   gxMagnitude: [Double](repeating: 0, count: w * h),
                   gyMagnitude: gy, luma: luma)
}

@Suite("Edge snapping landings")
struct EdgeSnappingLandingTests {

    /// Rows mirroring the measured real capture: ink body, a dimming baseline
    /// row, an antialiasing glow row, then background.
    private func softBaselineRows() -> [Double] {
        var rows = [Double](repeating: 0.13, count: 120)
        for r in 30...61 { rows[r] = 0.36 }  // ink body
        rows[62] = 0.30                       // dimming baseline row
        rows[63] = 0.155                      // antialiasing glow
        rows[64] = 0.135                      // nearly clean
        return rows
    }

    @Test func softTextBottomLandsPastTheAntialiasingGlow() {
        let map = mapFromLumaRows(softBaselineRows())
        let candidates = map.horizontalEdges(inXRange: 0...399)
        let baseline = candidates.first { abs($0.position - 62) <= 1 }
        #expect(baseline != nil)
        // Approaching from below, the snap position is the first visually-clean
        // background row (64) — not the gradient peak (62) or the glow (63).
        #expect(baseline?.edgeAfter == 64)
    }

    @Test func approachingSoftBaselineFromBelowSnapsToTheCleanRow() {
        let map = mapFromLumaRows(softBaselineRows())
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 66), edges: map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false)
        #expect(snap.point.y == 64)
        #expect(snap.guideY == 64)
    }

    @Test func sparseDescendersDoNotPushTheBaselineLanding() {
        // Below the baseline, descenders ('p', 'y') keep a few percent of ink
        // coverage for several rows. The user measures from the BASELINE — the
        // landing must settle right past the glow, not walk past the descenders.
        var rows = [Double](repeating: 0.13, count: 120)
        for r in 30...61 { rows[r] = 0.36 }   // ink body
        rows[62] = 0.30                        // dimming baseline row
        rows[63] = 0.155                       // antialiasing glow
        // Sparse descender ink: a few percent above background, varying row to
        // row the way real glyph strokes do.
        for (i, level) in [0.144, 0.142, 0.143, 0.141, 0.142].enumerated() {
            rows[64 + i] = level
        }
        let map = mapFromLumaRows(rows)
        let baseline = map.horizontalEdges(inXRange: 0...399)
            .first { abs($0.position - 62) <= 1 }
        #expect(baseline?.edgeAfter == 64)
    }

    @Test func hardHairlineLandsOnItsOwnCleanRows() {
        // A hard 2px divider (no antialiasing): the peak candidates already sit
        // on clean background rows; landings must not walk away from them.
        var rows = [Double](repeating: 0.13, count: 200)
        rows[100] = 0.28; rows[101] = 0.28
        let map = mapFromLumaRows(rows)

        let above = EdgeSnapping.snap(CGPoint(x: 200, y: 96), edges: map, zoom: 1,
                                      xSpan: 0...399, snapToPixelGrid: false)
        #expect(above.point.y == 99) // last clean row above the divider

        let below = EdgeSnapping.snap(CGPoint(x: 200, y: 105), edges: map, zoom: 1,
                                      xSpan: 0...399, snapToPixelGrid: false)
        #expect(below.point.y == 102) // first clean row below it
    }

    @Test func textRunOnlyExposesTheApproachSideLines() {
        // Three parallel lines of one run (cap-top 950, x-top 960, baseline 973).
        // Pointer at 966 sits below the run's midpoint (961.5) — approaching from
        // below — so only the bottom-side line (973) may capture, even though the
        // x-top at 960 is nearer.
        var f = Field(w: 400, h: 1200)
        f.addHorizontalEdge(row: 950, x0: 0, x1: 399)
        f.addHorizontalEdge(row: 960, x0: 0, x1: 399)
        f.addHorizontalEdge(row: 973, x0: 0, x1: 399)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 966), edges: f.map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false)
        #expect(snap.point.y == 973)
    }

    @Test func faintBorderSurvivesAStrongEdgeInTheSameWindow() {
        // Regression from the user's horizontal-measure scenario: a faint vertical
        // hairline border (raw ~0.18) shares the window with a maximally strong
        // dark→white panel edge (raw ~3.4). Window-relative thresholding used to
        // discard the hairline; acceptance must be absolute-floor only.
        var f = Field(w: 2000, h: 1200)
        f.addVerticalEdge(col: 100, y0: 0, y1: 1199, magnitude: 0.18)  // hairline
        f.addVerticalEdge(col: 160, y0: 0, y1: 1199, magnitude: 3.4)   // panel edge
        let snap = EdgeSnapping.snap(CGPoint(x: 97, y: 900), edges: f.map, zoom: 1,
                                     ySpan: 820...990, snapToPixelGrid: false)
        #expect(snap.point.x == 100)
        #expect(snap.guideX == 100)
    }

    @Test func hairlinePairIsNotSideFiltered() {
        // A divider's two boundary candidates are a pair, not a text run — both
        // stay reachable from either side.
        var f = Field(w: 400, h: 400)
        f.addHorizontalEdge(row: 100, x0: 0, x1: 399)
        f.addHorizontalEdge(row: 103, x0: 0, x1: 399)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 106), edges: f.map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false)
        #expect(snap.point.y == 103)
    }

    // MARK: Guide lines from other measurements

    @Test func guideLineCapturesAnAxisWithNoDetectedEdge() {
        // Nothing in the picture here; the only candidate is a line another
        // measurement already put down at y = 300.
        let f = Field(w: 800, h: 600)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 304), edges: f.map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false,
                                     guides: EdgeSnapping.GuideLines(horizontal: [300]))
        #expect(snap.point.y == 300)
        #expect(snap.guideY == 300)
    }

    @Test func guideLineOutOfToleranceLeavesTheAxisAlone() {
        let f = Field(w: 800, h: 600)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 320), edges: f.map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false,
                                     guides: EdgeSnapping.GuideLines(horizontal: [300]))
        #expect(snap.point.y == 320)
        #expect(snap.guideY == nil)
    }

    @Test func guideLineBeatsADetectedEdgeAtTheSameDistance() {
        // A line the user has already established outranks a pixel edge the
        // same distance away: they put it there on purpose.
        var f = Field(w: 800, h: 600)
        f.addHorizontalEdge(row: 296, x0: 0, x1: 399)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 300), edges: f.map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false,
                                     guides: EdgeSnapping.GuideLines(horizontal: [304]))
        #expect(snap.point.y == 304)
        #expect(snap.guideY == 304)
    }

    @Test func detectedEdgeUnderThePointerBeatsADistantGuide() {
        var f = Field(w: 800, h: 600)
        f.addHorizontalEdge(row: 300, x0: 0, x1: 399)
        let snap = EdgeSnapping.snap(CGPoint(x: 200, y: 300), edges: f.map, zoom: 1,
                                     xSpan: 0...399, snapToPixelGrid: false,
                                     guides: EdgeSnapping.GuideLines(horizontal: [307]))
        #expect(snap.point.y == 300)
    }

    @Test func guideToleranceScalesWithZoomLikeEveryOtherSnap() {
        let f = Field(w: 800, h: 600)
        // Six screen points at 4x is 1.5 image px: a guide 6 image px away is
        // out of reach there, and well in reach at 1x.
        let far = EdgeSnapping.snap(CGPoint(x: 200, y: 306), edges: f.map, zoom: 4,
                                    snapToPixelGrid: false,
                                    guides: EdgeSnapping.GuideLines(horizontal: [300]))
        #expect(far.guideY == nil)
        let near = EdgeSnapping.snap(CGPoint(x: 200, y: 306), edges: f.map, zoom: 1,
                                     snapToPixelGrid: false,
                                     guides: EdgeSnapping.GuideLines(horizontal: [300]))
        #expect(near.guideY == 300)
    }

    @Test func guidesSnapEachAxisIndependently() {
        let f = Field(w: 800, h: 600)
        let snap = EdgeSnapping.snap(CGPoint(x: 103, y: 304), edges: f.map, zoom: 1,
                                     snapToPixelGrid: false,
                                     guides: EdgeSnapping.GuideLines(vertical: [100],
                                                                     horizontal: [300]))
        #expect(snap.point == CGPoint(x: 100, y: 300))
        #expect(snap.guideX == 100)
        #expect(snap.guideY == 300)
    }

    // MARK: One-axis snapping (the readout chip's cross-axis drag)

    @Test func snapValueLinesUpWithTheNearestGuideAndReportsIt() {
        let result = EdgeSnapping.snapValue(304, toGuides: [120, 300, 480], zoom: 1)
        #expect(result.value == 300)
        #expect(result.guide == 300)
    }

    @Test func snapValueFallsBackToThePixelGridWhenNothingIsInReach() {
        let result = EdgeSnapping.snapValue(304.4, toGuides: [120, 480], zoom: 1)
        #expect(result.value == 304)
        #expect(result.guide == nil)
    }

    @Test func snapValueLeavesTheValueFreeWhenTheGridIsOff() {
        let result = EdgeSnapping.snapValue(304.4, toGuides: [], zoom: 1,
                                            snapToPixelGrid: false)
        #expect(result.value == 304.4)
        #expect(result.guide == nil)
    }

    @Test func snapValuePrefersTheNearerOfTwoGuidesInReach() {
        let result = EdgeSnapping.snapValue(302, toGuides: [300, 306], zoom: 1)
        #expect(result.value == 300)
    }

    @Test func snapValueToleranceScalesWithZoom() {
        #expect(EdgeSnapping.snapValue(306, toGuides: [300], zoom: 4).guide == nil)
        #expect(EdgeSnapping.snapValue(306, toGuides: [300], zoom: 1).guide == 300)
    }
}
