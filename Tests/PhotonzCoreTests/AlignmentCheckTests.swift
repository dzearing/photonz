import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Synthetic gradient fields, built the same way `ElementBoundsTests` builds
/// them: a box is four edge responses spanning each other's extent. Boxes are
/// stacked with at least one clean 16px block row between them so the scan's
/// samples can see the gaps at the edge map's block resolution.
private struct Scene {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]

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

    mutating func addBox(_ r: CGRect, magnitude: Double = 2.0) {
        addHorizontalEdge(row: Int(r.minY), x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
        addHorizontalEdge(row: Int(r.maxY), x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
        addVerticalEdge(col: Int(r.minX), y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
        addVerticalEdge(col: Int(r.maxX), y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
    }

    /// Text-like ink filling `r`: a vertical stroke every 4px and a horizontal
    /// one every 4px, the way glyphs light up both gradient fields.
    mutating func addInk(_ r: CGRect, magnitude: Double = 1.0) {
        var x = Int(r.minX)
        while x <= Int(r.maxX) {
            addVerticalEdge(col: x, y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
            x += 4
        }
        var y = Int(r.minY)
        while y <= Int(r.maxY) {
            addHorizontalEdge(row: y, x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
            y += 4
        }
    }

    var map: EdgeMap {
        EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: nil)
    }
}

@Suite("Alignment scan")
struct AlignmentScanTests {

    /// Three stacked boxes sharing a left edge; block-clean gaps between them.
    private func stackedScene(middleX: CGFloat = 100) -> Scene {
        var s = Scene(w: 400, h: 300)
        s.addBox(CGRect(x: 100, y: 40, width: 120, height: 40))
        s.addBox(CGRect(x: middleX, y: 112, width: 120, height: 40))
        s.addBox(CGRect(x: 100, y: 184, width: 120, height: 40))
        return s
    }

    @Test func aVerticalGuideFindsOneItemPerStackedElement() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 36...228,
                                        in: stackedScene().map)
        #expect(items.count == 3)
        for item in items {
            #expect(abs(item.edge - 100) <= 1)
            #expect(item.spanEnd > item.spanStart)
        }
    }

    @Test func aMisalignedElementBecomesItsOwnItemAtItsOwnEdge() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 36...228,
                                        in: stackedScene(middleX: 104).map)
        #expect(items.count == 3)
        #expect(abs(items[0].edge - 100) <= 1)
        #expect(abs(items[1].edge - 104) <= 1)
        #expect(abs(items[2].edge - 100) <= 1)
    }

    @Test func anImpreciseGuideStillCapturesNearbyEdges() {
        // Drawn 6px off the real edge: everything within the capture radius
        // still counts, and the items report the REAL edge positions.
        let items = AlignmentScan.items(axis: .vertical, position: 94, span: 36...228,
                                        in: stackedScene().map)
        #expect(items.count == 3)
        for item in items { #expect(abs(item.edge - 100) <= 1) }
    }

    @Test func aGuideFarFromAnyEdgeFindsNothing() {
        let items = AlignmentScan.items(axis: .vertical, position: 320, span: 36...228,
                                        in: stackedScene().map)
        #expect(items.isEmpty)
    }

    @Test func aHorizontalGuideChecksTopEdgesOfSideBySideElements() {
        var s = Scene(w: 400, h: 300)
        s.addBox(CGRect(x: 40, y: 60, width: 80, height: 50))
        s.addBox(CGRect(x: 152, y: 60, width: 80, height: 50))
        let items = AlignmentScan.items(axis: .horizontal, position: 60, span: 36...236,
                                        in: s.map)
        #expect(items.count == 2)
        for item in items { #expect(abs(item.edge - 60) <= 1) }
    }

    /// A bordered button beside a filled one, tops level. The border is two
    /// boundaries 3px apart: the outer edge, and the fainter inner edge where
    /// the border meets the fill, which the rounded corners do not reach. A
    /// guide drawn on the INNER edge (the anchor snap can land there) has to
    /// report each button once, at the edge they share: the two flanks of one
    /// border are one boundary read twice, exactly as `ElementBounds` treats
    /// them, and only the bolder one may be the element's edge.
    private func borderedAndFilledButtons() -> Scene {
        var s = Scene(w: 400, h: 300)
        // Bordered: outer box at y 60, inner top flank at y 63 stopping short
        // of the corners, 70% as bold.
        s.addBox(CGRect(x: 40, y: 60, width: 80, height: 50))
        s.addHorizontalEdge(row: 63, x0: 48, x1: 112, magnitude: 1.4)
        // Filled: one boundary only.
        s.addBox(CGRect(x: 152, y: 60, width: 80, height: 50))
        return s
    }

    @Test func aGuideOnTheInnerFlankOfABorderStillFindsTheOuterEdge() {
        let items = AlignmentScan.items(axis: .horizontal, position: 63, span: 36...236,
                                        in: borderedAndFilledButtons().map)
        #expect(items.count == 2)
        for item in items { #expect(abs(item.edge - 60) <= 1) }
        #expect(AlignmentCheck(items: items, tolerance: 1).verdict?.isAligned == true)
    }

    /// The same drag started in the middle of the bordered button, where the
    /// inner flank is the first thing the guide sees: the answer may not
    /// depend on which sample came first.
    @Test func aGuideStartedOnTheInnerFlankAgrees() {
        let items = AlignmentScan.items(axis: .horizontal, position: 63, span: 80...236,
                                        in: borderedAndFilledButtons().map)
        #expect(items.count == 2)
        for item in items { #expect(abs(item.edge - 60) <= 1) }
    }

    /// A row of toggles with their left ends level, one of them switched off.
    ///
    /// A switched-on toggle is a filled pill, so its left end is bold. The off
    /// one is a pale track on white with its knob at that same end, and the
    /// knob's edge — 4 px inside the track's, well within `pairSeparation` —
    /// is three times as bold. The row's label ink is bolder in the lower half
    /// of each row than the upper, so the pale track reads 0.28 of its window
    /// at the top of the toggle and 0.19 at the bottom: the same two-thirds
    /// fade a real capture shows, straddling the element floor.
    ///
    /// The toggles line up, and the guide has to say so. It used to report the
    /// off one 4 px out: the samples where the track dipped under the floor
    /// were dropped, and the fragment left behind was short enough to look
    /// like the inner flank of the knob's edge, so the guide measured the knob.
    private func togglesWithOneSwitchedOff(offTrackCol: Int = 100) -> Scene {
        var s = Scene(w: 400, h: 480)
        for (index, y) in [80, 144, 208, 272].enumerated() {
            let off = index == 2
            let col = off ? offTrackCol : 100
            if off {
                s.addVerticalEdge(col: col, y0: y, y1: y + 31, magnitude: 0.56)
                s.addVerticalEdge(col: col + 4, y0: y, y1: y + 31, magnitude: 1.6)
            } else {
                s.addVerticalEdge(col: col, y0: y, y1: y + 31, magnitude: 2.0)
            }
            let ends = off ? 0.56 : 2.0
            s.addHorizontalEdge(row: y, x0: col, x1: col + 60, magnitude: ends)
            s.addHorizontalEdge(row: y + 31, x0: col, x1: col + 60, magnitude: ends)
            // The row's label, bolder in its lower half than its upper.
            s.addVerticalEdge(col: 40, y0: y, y1: y + 15, magnitude: 2.0)
            s.addVerticalEdge(col: 40, y0: y + 16, y1: y + 31, magnitude: 2.95)
        }
        return s
    }

    @Test func aPaleToggleTrackBeatsTheBolderKnobInsideIt() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 70...320,
                                        in: togglesWithOneSwitchedOff().map)
        #expect(items.count == 4)
        for item in items { #expect(abs(item.edge - 100) <= 1) }
        #expect(AlignmentCheck(items: items, tolerance: 1).verdict?.isAligned == true)
    }

    /// And an off toggle that really is out of line still says so, at its real
    /// size: the track wins because it is the track, not because the answer
    /// was nudged onto the majority.
    @Test func aPaleToggleTrackOutOfLineIsStillReported() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 70...320,
                                        in: togglesWithOneSwitchedOff(offTrackCol: 106).map)
        #expect(items.count == 4)
        guard let verdict = AlignmentCheck(items: items, tolerance: 1).verdict else {
            Issue.record("no verdict")
            return
        }
        #expect(abs(verdict.maxDelta - 6) <= 1)
        #expect(verdict.outlierIndex == 2)
    }

    /// Two boundaries further apart than a border is thick are two elements,
    /// and the one the guide was drawn on is the one it means.
    @Test func aRealNeighbourSixPixelsAwayIsNotAbsorbed() {
        var s = Scene(w: 400, h: 300)
        s.addBox(CGRect(x: 40, y: 60, width: 80, height: 50))
        s.addHorizontalEdge(row: 66, x0: 40, x1: 120, magnitude: 1.4)
        let items = AlignmentScan.items(axis: .horizontal, position: 66, span: 36...124,
                                        in: s.map)
        #expect(items.count == 1)
        #expect(abs((items.first?.edge ?? 0) - 66) <= 1)
    }

    @Test func anEmptyMapFindsNothing() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 0...200,
                                        in: EdgeMap.empty)
        #expect(items.isEmpty)
    }

    /// Three stacked boxes, the middle one 4px out, plus a faint stub a couple
    /// of pixels beyond that middle box and just below it — the shape the
    /// block-summed edge map takes on under a line of text. Nothing is there,
    /// so the guide must not report anything there.
    private func sceneWithAGhostUnderTheMiddleBox() -> Scene {
        var s = Scene(w: 400, h: 420)
        s.addBox(CGRect(x: 100, y: 48, width: 120, height: 48))
        s.addBox(CGRect(x: 104, y: 160, width: 120, height: 48))
        s.addBox(CGRect(x: 100, y: 288, width: 120, height: 48))
        // The ghost: a seventh as bold as a real edge, and 4px further out again.
        s.addVerticalEdge(col: 108, y0: 226, y1: 238, magnitude: 0.3)
        // Something bold elsewhere in the same band, so the ghost is measured
        // against a real edge the way it would be on a screenshot.
        s.addVerticalEdge(col: 300, y0: 226, y1: 238, magnitude: 2.0)
        return s
    }

    @Test func aFaintGhostBesideTheRealEdgeNeverBecomesAnItem() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 40...344,
                                        in: sceneWithAGhostUnderTheMiddleBox().map)
        #expect(items.count == 3)
        #expect(items.allSatisfy { abs($0.edge - 108) > 2 })
    }

    /// And the number that reaches the chip is the real offset, not the ghost's.
    @Test func theGhostDoesNotInflateTheReportedOffset() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 40...344,
                                        in: sceneWithAGhostUnderTheMiddleBox().map)
        guard let verdict = AlignmentCheck(items: items, tolerance: 1).verdict else {
            Issue.record("no verdict")
            return
        }
        #expect(abs(verdict.maxDelta - 4) <= 1)
    }

    /// The floor is relative to what each window offers, so a capture whose
    /// every boundary is faint still gets checked — quiet is not the same as
    /// absent.
    /// Three labels whose text starts at x=100: ink to the RIGHT of every edge,
    /// so the guide is running down their left edges.
    private func labelsScene() -> Scene {
        var s = Scene(w: 400, h: 300)
        for y in [40, 112, 184] {
            s.addInk(CGRect(x: 100, y: y, width: 90, height: 24))
        }
        return s
    }

    @Test func inkToTheRightOfTheEdgeMeansALeftEdge() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 36...212,
                                        in: labelsScene().map)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.elementSide == .after })
        var content = MeasureContent(headOffset: 0, mode: .vertical)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        #expect(content.alignedEdge == .left)
    }

    @Test func inkToTheLeftOfTheEdgeMeansARightEdge() {
        var s = Scene(w: 400, h: 300)
        for y in [40, 112, 184] {
            s.addInk(CGRect(x: 110, y: y, width: 90, height: 24))
        }
        let items = AlignmentScan.items(axis: .vertical, position: 200, span: 36...212, in: s.map)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.elementSide == .before })
        var content = MeasureContent(headOffset: 0, mode: .vertical)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        #expect(content.alignedEdge == .right)
    }

    @Test func aHorizontalGuideAlongTextTopsReadsATopEdge() {
        var s = Scene(w: 400, h: 200)
        for x in [20, 140, 260] {
            s.addInk(CGRect(x: x, y: 60, width: 80, height: 24))
        }
        let items = AlignmentScan.items(axis: .horizontal, position: 60, span: 16...344, in: s.map)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.elementSide == .after })
        var content = MeasureContent(headOffset: 0, mode: .horizontal)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        #expect(content.alignedEdge == .top)
    }

    /// A bare box outline has nothing near either side of its edge, so the scan
    /// says so instead of guessing; the name then says "Vertical edges".
    @Test func anEdgeWithNothingNearEitherSideHasNoSide() {
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 36...228,
                                        in: stackedScene().map)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.elementSide == nil })
        var content = MeasureContent(headOffset: 0, mode: .vertical)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        #expect(content.alignedEdge == nil)
    }

    @Test func aUniformlyFaintSceneIsStillScanned() {
        var s = Scene(w: 400, h: 300)
        s.addBox(CGRect(x: 100, y: 40, width: 120, height: 40), magnitude: 0.2)
        s.addBox(CGRect(x: 100, y: 112, width: 120, height: 40), magnitude: 0.2)
        s.addBox(CGRect(x: 100, y: 184, width: 120, height: 40), magnitude: 0.2)
        let items = AlignmentScan.items(axis: .vertical, position: 100, span: 36...228,
                                        in: s.map)
        #expect(items.count == 3)
    }
}

@Suite("Alignment verdict")
struct AlignmentVerdictTests {

    private func item(_ edge: CGFloat, span: ClosedRange<CGFloat> = 0...10) -> AlignmentItem {
        AlignmentItem(edge: edge, spanStart: span.lowerBound, spanEnd: span.upperBound)
    }

    @Test func edgesWithinToleranceReadAligned() {
        let check = AlignmentCheck(items: [item(100), item(100.5), item(99.6)], tolerance: 1)
        let v = check.verdict
        #expect(v != nil)
        #expect(v?.isAligned == true)
        #expect(v?.outlierIndex == nil)
    }

    @Test func theWorstOffenderBeyondToleranceIsTheOutlier() {
        let check = AlignmentCheck(items: [item(100), item(104), item(100)], tolerance: 1)
        let v = check.verdict
        #expect(v?.isAligned == false)
        #expect(v?.outlierIndex == 1)
        #expect(v.map { abs($0.maxDelta - 4) < 0.001 } == true)
    }

    @Test func theMedianKeepsTheReferenceOnTheMajority() {
        // Three aligned + one off: the reference sits on the trio, not the mean.
        let check = AlignmentCheck(items: [item(100), item(100), item(110), item(100)], tolerance: 1)
        let v = check.verdict
        #expect(v.map { abs($0.reference - 100) < 0.001 } == true)
        #expect(v?.outlierIndex == 2)
    }

    @Test func fewerThanTwoItemsHaveNoVerdict() {
        #expect(AlignmentCheck(items: [], tolerance: 1).verdict == nil)
        #expect(AlignmentCheck(items: [item(100)], tolerance: 1).verdict == nil)
    }

    @Test func theHeaviestClusterDefinesTheReferenceWhenTheCountIsEven() {
        // Two edges agree at 100, two disagree at 106 and 108: a plain median
        // would average the two middle values and settle the guide at 103 —
        // a line no element sits on. The agreeing pair is the majority.
        let check = AlignmentCheck(items: [item(100), item(100), item(106), item(108)],
                                   tolerance: 1)
        let v = check.verdict
        #expect(v.map { abs($0.reference - 100) < 0.001 } == true)
        #expect(v?.isAligned == false)
        #expect(v?.outlierIndex == 3)
        #expect(v.map { abs($0.maxDelta - 8) < 0.001 } == true)
    }

    @Test func aLongCrossingOutweighsTwoGrazes() {
        // One element the guide runs down for 100px against two it clips for
        // 8px each: the long one is what the guide is measuring against, even
        // though the short pair outnumbers it.
        let check = AlignmentCheck(items: [item(100, span: 0...100),
                                           item(104, span: 0...8),
                                           item(107, span: 0...8)],
                                   tolerance: 1)
        #expect(check.verdict.map { abs($0.reference - 100) < 0.001 } == true)
    }

    private func item(_ edge: CGFloat, side: EdgeSide?, span: ClosedRange<CGFloat> = 0...10) -> AlignmentItem {
        AlignmentItem(edge: edge, spanStart: span.lowerBound, spanEnd: span.upperBound,
                      elementSide: side)
    }

    /// The side the guide settles on is the side of the items that DEFINE the
    /// reference, weighed by guide length like the reference itself: an
    /// outlier with the opposite side does not get a vote.
    @Test func theReferenceSideFollowsTheItemsOnTheReference() {
        let check = AlignmentCheck(items: [item(100, side: .after, span: 0...40),
                                           item(100, side: .after, span: 50...90),
                                           item(110, side: .before, span: 100...120)],
                                   tolerance: 1)
        #expect(check.referenceSide == .after)
    }

    @Test func aSplitVoteOnTheReferenceHasNoSide() {
        let check = AlignmentCheck(items: [item(100, side: .after, span: 0...40),
                                           item(100, side: .before, span: 50...90)],
                                   tolerance: 1)
        #expect(check.referenceSide == nil)
        #expect(AlignmentCheck(items: [item(100, side: nil), item(100, side: nil)],
                               tolerance: 1).referenceSide == nil)
    }

    @Test func itemsThatDoNotKnowTheirSideAbstain() {
        let check = AlignmentCheck(items: [item(100, side: nil, span: 0...100),
                                           item(100, side: .after, span: 0...8)],
                                   tolerance: 1)
        #expect(check.referenceSide == .after)
    }

    /// The Experiments window's tolerance is a LOGICAL px number (every readout
    /// is in points), so on a Retina capture it covers twice as many device px;
    /// a one device px wobble on a 2x capture is half a point, not a
    /// misalignment.
    @Test func toleranceIsGivenInLogicalPixels() {
        #expect(AlignmentCheck.deviceTolerance(logical: 1, pixelScale: 2) == 2)
        #expect(AlignmentCheck.deviceTolerance(logical: 1, pixelScale: 1) == 1)
        #expect(AlignmentCheck.deviceTolerance(logical: 0.5, pixelScale: 3) == 1.5)
        // A capture with no scale recorded is a 1x capture, never a zero.
        #expect(AlignmentCheck.deviceTolerance(logical: 1, pixelScale: 0) == 1)
    }

    @Test func twoItemsSplitTheDifference() {
        let check = AlignmentCheck(items: [item(100), item(104)], tolerance: 1)
        let v = check.verdict
        #expect(v?.isAligned == false)
        #expect(v.map { abs($0.reference - 102) < 0.001 } == true)
        #expect(v.map { abs($0.maxDelta - 2) < 0.001 } == true)
    }
}

@Suite("Alignment content")
struct AlignmentContentTests {

    private func alignedContent(edges: [CGFloat], tolerance: CGFloat = 1,
                                mode: MeasureMode = .vertical,
                                side: EdgeSide? = nil) -> MeasureContent {
        var content = MeasureContent(start: CGPoint(x: 100, y: 30),
                                     end: CGPoint(x: 100, y: 210),
                                     headOffset: 0, mode: mode)
        content.alignment = AlignmentCheck(
            items: edges.enumerated().map {
                AlignmentItem(edge: $0.element,
                              spanStart: CGFloat(40 + $0.offset * 70),
                              spanEnd: CGFloat(80 + $0.offset * 70),
                              elementSide: side)
            },
            tolerance: tolerance)
        return content
    }

    @Test func alignmentPayloadRoundTripsThroughCodable() throws {
        let content = alignedContent(edges: [100, 104, 100])
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(decoded == content)
        #expect(decoded.alignment?.items.count == 3)
    }

    /// Items written before the side existed carry no key for it and must
    /// still decode; the guide simply does not know its side.
    @Test func itemsWithoutASideDecodeToNil() throws {
        let json = #"{"edge":100,"spanStart":10,"spanEnd":30}"#
        let item = try JSONDecoder().decode(AlignmentItem.self, from: Data(json.utf8))
        #expect(item.elementSide == nil)
        #expect(item.edge == 100)
    }

    @Test func alignedEdgeMapsSideThroughTheGuideAxis() {
        func content(_ mode: MeasureMode, _ side: EdgeSide) -> MeasureContent {
            var c = MeasureContent(headOffset: 0, mode: mode)
            c.alignment = AlignmentCheck(items: [
                AlignmentItem(edge: 100, spanStart: 0, spanEnd: 10, elementSide: side),
                AlignmentItem(edge: 100, spanStart: 20, spanEnd: 30, elementSide: side),
            ], tolerance: 1)
            return c
        }
        #expect(content(.vertical, .after).alignedEdge == .left)
        #expect(content(.vertical, .before).alignedEdge == .right)
        #expect(content(.horizontal, .after).alignedEdge == .top)
        #expect(content(.horizontal, .before).alignedEdge == .bottom)
        #expect(MeasureContent(headOffset: 0, mode: .vertical).alignedEdge == nil)
    }

    @Test func payloadWithoutAlignmentDecodesToNil() throws {
        let data = try JSONEncoder().encode(MeasureContent(start: .zero, end: CGPoint(x: 50, y: 0)))
        let decoded = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(decoded.alignment == nil)
    }

    @Test func alignedGuideLabelReadsAligned() {
        let content = alignedContent(edges: [100, 100, 100])
        #expect(content.label(pixelScale: 1) == "aligned")
    }

    @Test func misalignedGuideLabelReportsTheDelta() {
        let content = alignedContent(edges: [100, 104, 100])
        #expect(content.label(pixelScale: 1) == "off 4 px")
    }

    @Test func deltaLabelRespectsLogicalUnits() {
        var content = alignedContent(edges: [100, 104, 100])
        content.unit = .points
        #expect(content.label(pixelScale: 2) == "off 2 px")
    }

    @Test func aGuideWithNothingToCheckSaysSo() {
        let content = alignedContent(edges: [])
        #expect(content.label(pixelScale: 1) == "no edges")
    }

    // MARK: - The chip on the canvas names its edge

    /// The exported picture carries nothing but the chip, so the chip has to
    /// say what the guide judged: the same edge words the panel row uses.
    @Test func theChipNamesTheEdgeItChecked() {
        #expect(alignedContent(edges: [100, 100, 100], side: .after).chipText(pixelScale: 1)
                == "Left edges aligned")
        #expect(alignedContent(edges: [100, 104, 100], side: .after).chipText(pixelScale: 1)
                == "Left edges, off 4 px")
        #expect(alignedContent(edges: [100, 100], side: .before).chipText(pixelScale: 1)
                == "Right edges aligned")
        #expect(alignedContent(edges: [100, 100], mode: .horizontal, side: .after).chipText(pixelScale: 1)
                == "Top edges aligned")
        #expect(alignedContent(edges: [100, 103, 100], mode: .horizontal, side: .before).chipText(pixelScale: 1)
                == "Bottom edges, off 3 px")
    }

    /// When the scan could not tell which side the elements sit on, the chip
    /// names the guide's axis, exactly as the row does, rather than guess.
    @Test func theChipFallsBackToTheAxisWhenTheSideIsUnknown() {
        #expect(alignedContent(edges: [100, 104, 100]).chipText(pixelScale: 1)
                == "Vertical edges, off 4 px")
        #expect(alignedContent(edges: [100, 100], mode: .horizontal).chipText(pixelScale: 1)
                == "Horizontal edges aligned")
    }

    @Test func theChipDeltaRespectsLogicalUnits() {
        var content = alignedContent(edges: [100, 104, 100], side: .after)
        content.unit = .points
        #expect(content.chipText(pixelScale: 2) == "Left edges, off 2 px")
    }

    /// Fewer than two edges is nothing to compare, so there is no edge to name.
    @Test func theChipWithNothingToCheckSaysSo() {
        #expect(alignedContent(edges: []).chipText(pixelScale: 1) == "No edges")
        #expect(alignedContent(edges: [100], side: .after).chipText(pixelScale: 1) == "No edges")
    }

    /// The spec line is pinned by `MeasureSpecListTests` and already carries
    /// the edge in the row name, so the short verdict stays as it was.
    @Test func theSpecVerdictIsUnchangedByTheChipWording() {
        let content = alignedContent(edges: [100, 104, 100], side: .after)
        #expect(content.label(pixelScale: 1) == "off 4 px")
    }

    @Test func aCaliperChipIsItsReadout() {
        let caliper = MeasureContent(start: CGPoint(x: 0, y: 10), end: CGPoint(x: 120, y: 10),
                                     headOffset: 20, mode: .horizontal)
        #expect(caliper.chipText(pixelScale: 1) == caliper.label(pixelScale: 1))
    }
}

@Suite("Alignment builder")
struct AlignmentBuilderTests {

    /// Doc-space content for a vertical guide at x=100 spanning y 30…210 with a
    /// 4px outlier in the middle.
    private func docContent() -> MeasureContent {
        var content = MeasureContent(headOffset: 0, mode: .vertical)
        content.alignment = AlignmentCheck(
            items: [AlignmentItem(edge: 100, spanStart: 40, spanEnd: 80),
                    AlignmentItem(edge: 104, spanStart: 112, spanEnd: 152),
                    AlignmentItem(edge: 100, spanStart: 184, spanEnd: 224)],
            tolerance: 1)
        return content
    }

    @Test func builtLayerReExpressesItemsLayerLocal() {
        let layer = MeasureBuilder.layer(content: docContent(),
                                         from: CGPoint(x: 100, y: 30), to: CGPoint(x: 100, y: 210))
        let m = layer.measure
        #expect(m?.alignment?.items.count == 3)
        guard let items = m?.alignment?.items else { return }
        // Doc-space edge 104 must map back to 104 through the frame origin.
        for (i, docEdge) in [CGFloat(100), 104, 100].enumerated() {
            #expect(abs(items[i].edge + layer.frame.minX - docEdge) < 0.001)
        }
        #expect(abs(items[0].spanStart + layer.frame.minY - 40) < 0.001)
    }

    @Test func builtFrameCoversGuideItemsAndChip() {
        let layer = MeasureBuilder.layer(content: docContent(),
                                         from: CGPoint(x: 100, y: 30), to: CGPoint(x: 100, y: 210))
        // The outlier's actual edge (x=104) and the full guide span must be inside.
        #expect(layer.frame.minX < 100)
        #expect(layer.frame.maxX > 104)
        #expect(layer.frame.minY < 30)
        #expect(layer.frame.maxY > 210)
    }

    @Test func wholeDocumentResizeScalesItemsWithTheFrame() {
        let layer = MeasureBuilder.layer(content: docContent(),
                                         from: CGPoint(x: 100, y: 30), to: CGPoint(x: 100, y: 210))
        let doubled = CGRect(x: layer.frame.minX * 2, y: layer.frame.minY * 2,
                             width: layer.frame.width * 2, height: layer.frame.height * 2)
        let resized = MeasureBuilder.resized(layer, to: doubled)
        guard let items = resized.measure?.alignment?.items else {
            Issue.record("resized layer lost its alignment payload")
            return
        }
        // Doc-space edges double: 100 → 200, 104 → 208.
        #expect(abs(items[1].edge + resized.frame.minX - 208) < 0.5)
        #expect(abs(items[0].edge + resized.frame.minX - 200) < 0.5)
        #expect(abs(items[0].spanStart + resized.frame.minY - 80) < 0.5)
    }

    @Test func alignmentGuidesExposeNoEndpointOrFrameHandles() {
        let layer = MeasureBuilder.layer(content: docContent(),
                                         from: CGPoint(x: 100, y: 30), to: CGPoint(x: 100, y: 210))
        #expect(layer.hasEndpointHandles == false)
        #expect(layer.allowsFrameResize == false)
        // A plain caliper keeps its endpoint handles.
        let caliper = MeasureBuilder.layer(content: MeasureContent(),
                                           from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0))
        #expect(caliper.hasEndpointHandles == true)
    }
}

// MARK: - Counting the way a person would

/// The scan counts ELEMENTS, not edge runs. The edge map is block-summed, so a
/// curved first letter, the cap-and-x-height tops of a line of text, a rounded
/// pill end, or a faint card edge next to bold text all come back as several
/// runs, while two things stacked closer than a block come back as one. These
/// scenes are painted pictures (`PaintedCapture`), because the fix reads the
/// pixels: anything joined by a continuing boundary or by ink on its own side
/// is one item, and only visible whitespace along the guide separates two.
@Suite("Alignment scan counts elements")
struct AlignmentElementCountTests {

    private func scan(_ c: PaintedCapture, axis: MeasureMode, position: CGFloat,
                      span: ClosedRange<CGFloat>, pixelScale: CGFloat = 1,
                      luma: LumaField? = nil) -> [AlignmentItem] {
        AlignmentScan.items(axis: axis, position: position, span: span, in: c.map,
                            luma: luma ?? c.luma, pixelScale: pixelScale)
    }

    /// A label whose first letter is a big C: the stroke bulges 6 px to the
    /// right for the top and bottom sixteen rows, so the block-summed map
    /// reads three different left edges down one letter.
    private func curvedLabel(x: Int, y: Int, in c: inout PaintedCapture) {
        c.fill(CGRect(x: x + 6, y: y, width: 4, height: 16), 40)
        c.fill(CGRect(x: x, y: y + 16, width: 4, height: 32), 40)
        c.fill(CGRect(x: x + 6, y: y + 48, width: 4, height: 16), 40)
        c.text(x: x + 14, y: y, glyphs: 6, height: 64)
    }

    @Test func aCurvedFirstLetterCountsOnce() {
        var c = PaintedCapture(w: 400, h: 300)
        curvedLabel(x: 100, y: 32, in: &c)
        c.text(x: 100, y: 140, glyphs: 8, height: 30)
        let items = scan(c, axis: .vertical, position: 100, span: 20...190)
        #expect(items.count == 2)
        for item in items { #expect(abs(item.edge - 100) <= 1.5) }
        #expect(AlignmentCheck(items: items, tolerance: 1).verdict?.isAligned == true)
    }

    /// Without pixels to read, runs a sample apart still join, so a curved
    /// letter counts once even for a check built from the edge map alone.
    @Test func withoutPixelsAdjacentRunsStillJoin() {
        var c = PaintedCapture(w: 400, h: 300)
        curvedLabel(x: 100, y: 32, in: &c)
        c.text(x: 100, y: 140, glyphs: 8, height: 30)
        let items = scan(c, axis: .vertical, position: 100, span: 20...190, luma: .empty)
        #expect(items.count == 2)
    }

    /// Three words of stand-in text: tall glyphs at word starts, short ones
    /// after, with word spaces narrower than a visible gap. Along its top the
    /// map alternates between the cap line and the x-height line.
    private func wordyLabel(x: Int, y: Int, words: [(tall: Int, short: Int)] = [(2, 6), (1, 5), (0, 6)],
                            in c: inout PaintedCapture) {
        var left = x
        for (tall, short) in words {
            for i in 0..<(tall + short) {
                let top = i < tall ? y : y + 6
                let height = i < tall ? 20 : 14
                c.fill(CGRect(x: left, y: top, width: 4, height: height), 40)
                left += 8
            }
            left += 2
        }
    }

    @Test func aLineOfTextUnderATopGuideCountsOnce() {
        var c = PaintedCapture(w: 480, h: 200)
        wordyLabel(x: 40, y: 60, in: &c)
        let items = scan(c, axis: .horizontal, position: 60, span: 30...230)
        #expect(items.count == 1)
        #expect(items.first?.elementSide == .after)
    }

    @Test func twoLabelsAlongTheirTopsCountTwice() {
        var c = PaintedCapture(w: 480, h: 200)
        wordyLabel(x: 40, y: 60, in: &c)
        wordyLabel(x: 248, y: 60, in: &c)
        let items = scan(c, axis: .horizontal, position: 60, span: 30...430)
        #expect(items.count == 2)
        #expect(AlignmentCheck(items: items, tolerance: 1).verdict?.isAligned == true)
    }

    /// A shorter second label 4 px lower: still two items, and the verdict is
    /// the real offset, not the cap-to-x-height distance. (Shorter so the
    /// longer label is the majority; two equal labels would tie and split the
    /// difference, as `twoItemsSplitTheDifference` pins.)
    @Test func aLowerLabelIsStillOneItemAtItsRealOffset() {
        var c = PaintedCapture(w: 480, h: 200)
        wordyLabel(x: 40, y: 60, in: &c)
        wordyLabel(x: 248, y: 64, words: [(2, 6), (1, 5)], in: &c)
        let items = scan(c, axis: .horizontal, position: 60, span: 30...430)
        #expect(items.count == 2)
        guard let verdict = AlignmentCheck(items: items, tolerance: 1).verdict else {
            Issue.record("no verdict")
            return
        }
        #expect(abs(verdict.maxDelta - 4) <= 1.5)
        #expect(verdict.outlierIndex == 1)
    }

    @Test func stackedElementsWithAVisibleGapCountTwice() {
        var c = PaintedCapture(w: 400, h: 200)
        c.fill(CGRect(x: 100, y: 40, width: 120, height: 20), 120)
        c.fill(CGRect(x: 100, y: 72, width: 120, height: 20), 120)
        let items = scan(c, axis: .vertical, position: 100, span: 30...100)
        #expect(items.count == 2)
        guard items.count == 2 else { return }
        #expect(abs(items[0].spanStart - 40) <= 2 && abs(items[0].spanEnd - 60) <= 2)
        #expect(abs(items[1].spanStart - 72) <= 2 && abs(items[1].spanEnd - 92) <= 2)
    }

    /// Closer than a visible gap, two things read as one: that is the honest
    /// limit, and it is measured in LOGICAL px, so a 2x capture needs twice the
    /// device pixels of whitespace.
    @Test func theVisibleGapIsInLogicalPixels() {
        var c = PaintedCapture(w: 400, h: 200)
        c.fill(CGRect(x: 100, y: 40, width: 120, height: 20), 120)
        c.fill(CGRect(x: 100, y: 72, width: 120, height: 20), 120)
        #expect(scan(c, axis: .vertical, position: 100, span: 30...100, pixelScale: 2).count == 1)
        var tight = PaintedCapture(w: 400, h: 200)
        tight.fill(CGRect(x: 100, y: 40, width: 120, height: 20), 120)
        tight.fill(CGRect(x: 100, y: 64, width: 120, height: 20), 120)
        #expect(scan(tight, axis: .vertical, position: 100, span: 30...100).count == 1)
    }

    /// A white card on a light background, with dark text inside it near the
    /// edge. Wherever the text shares a block row with the edge, the edge is a
    /// fraction as bold and the strength floor drops it, so the map reads the
    /// card as two or three runs. The pixels say the edge never stops.
    @Test func aFaintCardEdgeBesideBoldTextCountsOnce() {
        var c = PaintedCapture(w: 480, h: 480)
        c.fill(CGRect(x: 64, y: 100, width: 340, height: 200), 255)
        for y in [128, 176, 240] { c.text(x: 96, y: y, glyphs: 8) }
        c.fill(CGRect(x: 64, y: 320, width: 340, height: 100), 255)
        c.text(x: 96, y: 336, glyphs: 8)
        let items = scan(c, axis: .vertical, position: 64, span: 90...430)
        #expect(items.count == 2)
        guard items.count == 2 else { return }
        for item in items { #expect(abs(item.edge - 64) <= 1.5) }
        #expect(item(items[0], covers: 104...296))
        #expect(item(items[1], covers: 324...416))
    }

    private func item(_ item: AlignmentItem, covers range: ClosedRange<CGFloat>) -> Bool {
        item.spanStart <= range.lowerBound && item.spanEnd >= range.upperBound
    }

    /// A pill whose left end is a half circle: the map smears that end across
    /// a dozen columns and reads it as its own run above and below the straight
    /// part.
    private func pill(x: Int, y: Int, width: Int, in c: inout PaintedCapture) {
        let radius = 15
        for row in y..<(y + 2 * radius) {
            let dy = Double(row - y - radius) + 0.5
            let inset = Double(radius) - (Double(radius * radius) - dy * dy).squareRoot()
            c.fill(CGRect(x: x + Int(inset.rounded()), y: row,
                          width: width - Int(inset.rounded()), height: 1), 120)
        }
    }

    @Test func aRoundedEndCountsOnce() {
        var c = PaintedCapture(w: 400, h: 200)
        pill(x: 100, y: 40, width: 60, in: &c)
        pill(x: 100, y: 100, width: 60, in: &c)
        let items = scan(c, axis: .vertical, position: 100, span: 30...140)
        #expect(items.count == 2)
        for item in items { #expect(abs(item.edge - 100) <= 2) }
        #expect(AlignmentCheck(items: items, tolerance: 1).verdict?.isAligned == true)
    }

    /// A guide drawn a little above a line of text, near enough to catch only
    /// its ascenders: five scattered hits are still one label, because the
    /// text's own ink runs under the guide the whole way.
    @Test func scatteredAscenderHitsAreOneLabel() {
        var c = PaintedCapture(w: 480, h: 200)
        wordyLabel(x: 40, y: 70, in: &c)
        let items = scan(c, axis: .horizontal, position: 62, span: 30...230)
        #expect(items.count == 1)
    }
}

@Suite("Alignment count honesty")
struct AlignmentCountHonestyTests {

    private func guide(itemsAreElements: Bool) -> MeasureContent {
        var c = MeasureContent(headOffset: 0, mode: .vertical)
        c.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 40, spanStart: 0, spanEnd: 20, elementSide: .after),
            AlignmentItem(edge: 40, spanStart: 40, spanEnd: 60, elementSide: .after),
            AlignmentItem(edge: 44, spanStart: 80, spanEnd: 100, elementSide: .after),
        ], tolerance: 1, itemsAreElements: itemsAreElements)
        return c
    }

    /// A check whose items are raw edge runs (no pixels were read) does not
    /// print a count it cannot stand behind.
    @Test func aCheckBuiltWithoutPixelsDropsTheCount() {
        #expect(MeasureSpecList.derivedName(for: guide(itemsAreElements: true)) == "Left edges, 3 items")
        #expect(MeasureSpecList.derivedName(for: guide(itemsAreElements: false)) == "Left edges")
    }

    /// Guides saved before the scan read pixels counted runs, so they decode
    /// as not-counted rather than keep a number that was already wrong.
    @Test func olderChecksDecodeAsNotCounted() throws {
        let json = #"{"items":[{"edge":100,"spanStart":10,"spanEnd":30}],"tolerance":1}"#
        let check = try JSONDecoder().decode(AlignmentCheck.self, from: Data(json.utf8))
        #expect(check.itemsAreElements == false)
        #expect(check.items.count == 1)
    }

    @Test func theFlagRoundTripsThroughCodable() throws {
        let content = guide(itemsAreElements: true)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(decoded.alignment?.itemsAreElements == true)
        #expect(decoded == content)
    }
}

