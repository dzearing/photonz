import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// The alignment guide measured against a REAL screenshot whose true geometry
/// is known, for the same reason `ElementDetectionFixtureTests` exists: a
/// synthetic scene draws exactly the boundaries the scan is looking for, and
/// every bug this feature has shipped came from the ones a screenshot brings —
/// antialiased glyph edges, block-summed bleed under a line of text, two local
/// peaks either side of a curved letter.
///
/// The fixture is `Fixtures/settings-pane-2x.png`, the capture the measure
/// audit of 2026-08-23 was written against. Its second card holds three labels
/// whose left edges are at logical x 48, **52** and 48 — the middle one is
/// deliberately 4 logical px out. At 2x that is device x 96, 104, 96.
@Suite("Alignment guide on a real capture")
struct AlignmentFixtureTests {

    private static let edges: EdgeMap = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyze(image)
    }()

    /// The drag the audit describes: down the left edge of the three labels in
    /// the second card. The press anchor snaps to the edge before the scan sees
    /// it, so device x 96 is what the shipping path hands over.
    private static let guideX: CGFloat = 96
    private static let guideSpan: ClosedRange<CGFloat> = 470...680

    /// The capture is stamped 144 DPI, so Photonz opens it at pixelScale 2 and
    /// every readout is in logical points.
    private static let pixelScale: CGFloat = 2

    private func scan(at position: CGFloat = AlignmentFixtureTests.guideX,
                      span: ClosedRange<CGFloat> = AlignmentFixtureTests.guideSpan) -> [AlignmentItem] {
        AlignmentScan.items(axis: .vertical, position: position, span: span, in: Self.edges)
    }

    /// The committed guide, built the way `EditorState.addAlignmentCheck` builds
    /// it: scan, settle onto the reference edge, plan where the readout lands.
    private func committed(_ items: [AlignmentItem]) -> (content: MeasureContent,
                                                         start: CGPoint, end: CGPoint) {
        var content = MeasureContent(headOffset: 0, mode: .vertical, unit: .points)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        let reference = content.alignment?.verdict?.reference ?? Self.guideX
        let start = CGPoint(x: reference, y: Self.guideSpan.lowerBound)
        let end = CGPoint(x: reference, y: Self.guideSpan.upperBound)
        content.start = start
        content.end = end
        let plan = MeasureLabelPlanner.plan(for: content,
                                            canvas: CGSize(width: Self.edges.width,
                                                           height: Self.edges.height))
        content.labelPlacement = plan.placement
        content.labelNudge = plan.nudge
        return (content, start, end)
    }

    @Test func theCaptureIsTheOneTheAuditMeasured() {
        #expect(Self.edges.width == 1440)
        #expect(Self.edges.height == 960)
    }

    /// One item per label, and nothing else. The bug this pins: the block-summed
    /// edge map keeps bleeding a faint ghost of the middle label's edge for a
    /// sample or two BELOW the text, at x≈108. That ghost used to become a
    /// fourth item and, being further out than the real edge at x≈106, used to
    /// win the worst-offender vote.
    @Test func theGuideFindsExactlyOneEdgePerLabel() {
        let items = scan()
        #expect(items.count == 3)
        guard items.count == 3 else { return }
        // Two labels agree near device x 96; the middle one sits ~8 device px out.
        #expect(abs(items[0].edge - 96) <= 2.5)
        #expect(abs(items[1].edge - 104) <= 2.5)
        #expect(abs(items[2].edge - 96) <= 2.5)
        // Every run has to be long enough to be a line of text, not a ghost.
        for item in items { #expect(item.spanEnd - item.spanStart >= 16) }
    }

    /// The labels' text runs to the RIGHT of the guide, so this is their left
    /// edge, and the row can say so: "Left edges, 3 items".
    @Test func theGuideKnowsItIsRunningDownLeftEdges() {
        let items = scan()
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.elementSide == .after })
        let (content, _, _) = committed(items)
        #expect(content.alignedEdge == .left)
        #expect(MeasureSpecList.derivedName(for: content) == "Left edges, 3 items")
    }

    /// The headline number. The true offset is 4 logical px; the chip used to
    /// say 5.
    @Test func theVerdictReadsTheRealOffset() {
        let (content, _, _) = committed(scan())
        #expect(content.label(pixelScale: Self.pixelScale) == "off 4 px")
    }

    /// And it accuses the right row: the middle label, not the ghost under it.
    @Test func theOutlierIsTheMiddleLabel() {
        let items = scan()
        guard let verdict = AlignmentCheck(items: items, tolerance: 1).verdict,
              let outlier = verdict.outlierIndex else {
            Issue.record("no outlier on a capture with a 4px offender")
            return
        }
        let item = items[outlier]
        // The middle label's text band.
        #expect(item.spanStart >= 540 && item.spanEnd <= 610)
        #expect(abs(item.edge - 104) <= 2.5)
        // The guide settles on the two that agree, not between them and the outlier.
        #expect(abs(verdict.reference - 96) <= 2.5)
    }

    /// Whatever else the readout does, it may not sit on a row it is judging —
    /// the one thing you need to see is the thing it would be hiding.
    @Test func theVerdictPillClearsEveryRowItJudges() {
        let (content, _, _) = committed(scan())
        let pill = content.labelRect(chipSize: content.estimatedLabelSize)
        for (index, subject) in content.subjectRects.enumerated() {
            #expect(!subject.intersects(pill), "pill covers item \(index)")
        }
        // And it stays on the picture.
        #expect(pill.minX >= 0)
        #expect(pill.minY >= 0)
        #expect(pill.maxX <= CGFloat(Self.edges.width))
        #expect(pill.maxY <= CGFloat(Self.edges.height))
    }

    /// The whole guide — dashed line, ticks, the outlier's bracket and the
    /// readout — has to fit inside the layer the builder reserves for it, or the
    /// export clips something.
    @Test func theBuiltLayerHoldsEveryMarkTheGuideDraws() {
        let (content, start, end) = committed(scan())
        let layer = MeasureBuilder.layer(content: content, from: start, to: end)
        guard let local = layer.measure, let check = local.alignment else {
            Issue.record("built layer lost its alignment payload")
            return
        }
        let frame = CGRect(origin: .zero, size: layer.frame.size)
        #expect(frame.contains(local.labelRect(chipSize: local.estimatedLabelSize)))
        // Everything a guide inks for one item: the tick either side of the
        // guide, the bracket out to the element's real edge, and the stroke's
        // own overhang at every end.
        let guideX = local.start.x
        let over = local.renderPadding
        for item in check.items {
            let lo = min(guideX, item.edge) - MeasureBuilder.alignmentTickHalf - over
            let hi = max(guideX, item.edge) + MeasureBuilder.alignmentTickHalf + over
            let mark = CGRect(x: lo, y: item.spanStart - over,
                              width: hi - lo, height: item.spanEnd - item.spanStart + over * 2)
            #expect(frame.contains(mark))
        }
    }

    /// A guide is drawn by hand, so the answer must not depend on hitting one
    /// exact pixel. Every press that snaps onto this edge has to agree.
    @Test func everyReasonableDragDownTheseLabelsAgrees() {
        for position in [CGFloat(94), 96, 98] {
            let (content, _, _) = committed(scan(at: position))
            #expect(content.label(pixelScale: Self.pixelScale) == "off 4 px",
                    "guide at x \(position)")
        }
    }
}
