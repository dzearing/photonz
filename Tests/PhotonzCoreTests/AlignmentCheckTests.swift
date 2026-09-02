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

    private func alignedContent(edges: [CGFloat], tolerance: CGFloat = 1) -> MeasureContent {
        var content = MeasureContent(start: CGPoint(x: 100, y: 30),
                                     end: CGPoint(x: 100, y: 210),
                                     headOffset: 0, mode: .vertical)
        content.alignment = AlignmentCheck(
            items: edges.enumerated().map {
                AlignmentItem(edge: $0.element,
                              spanStart: CGFloat(40 + $0.offset * 70),
                              spanEnd: CGFloat(80 + $0.offset * 70))
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
