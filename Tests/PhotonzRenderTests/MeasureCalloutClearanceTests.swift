import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// The thumb test from UX-PATTERNS D14, run on the real capture the measure
/// audits are written against (`Fixtures/settings-pane-2x.png`): cover each
/// callout with your thumb and the picture must still show everything the
/// callout is claiming.
///
/// These are deliberately end-to-end — scan real edges, plan the readout the
/// way the app does, then check the readout's footprint against what it is
/// describing — because the bug this suite exists for only appeared once real
/// geometry met a real chip size.
@Suite("Callouts stay off their subjects on a real capture")
struct MeasureCalloutClearanceTests {

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image)
    }()

    private static let canvas = CGSize(width: 1440, height: 960)

    /// The measurement the app would commit for a guide drawn at `position`
    /// down `span`, with its readout already placed.
    private func alignmentCheck(position: CGFloat,
                                span: ClosedRange<CGFloat>) -> MeasureContent {
        let items = AlignmentScan.items(axis: .vertical, position: position, span: span,
                                        in: Self.analysis.edges)
        var content = MeasureContent(headOffset: 0, mode: .vertical, unit: .points)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        let reference = content.alignment?.verdict?.reference ?? position
        let start = CGPoint(x: reference, y: span.lowerBound)
        let end = CGPoint(x: reference, y: span.upperBound)
        var probe = content
        probe.start = start
        probe.end = end
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: Self.canvas)
        probe.labelPlacement = plan.placement
        probe.labelNudge = plan.nudge
        return probe
    }

    /// The left edge of a settings row, read off the capture rather than
    /// hard-coded, so the test still means something if the fixture is redrawn.
    private var rowLeftEdge: CGFloat {
        ElementBounds.candidates(at: CGPoint(x: 700, y: 192), in: Self.analysis.edges,
                                 luma: Self.analysis.luma).first?.minX ?? 0
    }

    @Test func theCaptureIsTheOneTheAuditsMeasured() {
        #expect(Self.analysis.edges.width == 1440)
        #expect(rowLeftEdge > 0)
    }

    /// A guide down the left edge of the three settings rows — the exact shape
    /// of the playtest that found the bug.
    @Test func anAlignmentVerdictNeverCoversTheRowsItJudges() {
        let check = alignmentCheck(position: rowLeftEdge, span: 150...410)
        #expect(check.alignment?.items.count ?? 0 >= 2, "the guide found edges to compare")
        let readout = check.labelRect(chipSize: check.estimatedLabelSize)
        for subject in check.subjectRects {
            #expect(!readout.intersects(subject),
                    "the verdict covers a row it is judging: \(readout) vs \(subject)")
        }
    }

    /// And it stays on the picture: a readout half off the image is not a
    /// readout.
    @Test func anAlignmentVerdictStaysOnTheCapture() {
        let check = alignmentCheck(position: rowLeftEdge, span: 150...410)
        let readout = check.labelRect(chipSize: check.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(readout))
    }

    /// A guide that runs the full height of the capture has no room past
    /// either end, so the verdict has to step sideways instead — and still
    /// clear everything.
    @Test func aFullHeightGuideStillFindsSomewhereClear() {
        let check = alignmentCheck(position: rowLeftEdge, span: 20...940)
        let readout = check.labelRect(chipSize: check.estimatedLabelSize)
        for subject in check.subjectRects {
            #expect(!readout.intersects(subject))
        }
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(readout))
    }

    /// Size mode drops a width and a height caliper on the same element; their
    /// readouts meet at a corner, so this is the likeliest stack in the app.
    @Test func theWidthAndHeightReadoutsOfOneElementDoNotStack() {
        // The "Save Changes" button: 248 x 60 image px at (171, 756).
        let rect = CGRect(x: 171, y: 756, width: 248, height: 60)
        var width = MeasureContent(mode: .horizontal, unit: .points)
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        width.headOffset = MeasureBuilder.clearingHeadOffset(content: width, from: widthFeet.0,
                                                             to: widthFeet.1, canvas: Self.canvas)
        var height = MeasureContent(mode: .vertical, unit: .points)
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        height.headOffset = MeasureBuilder.clearingHeadOffset(content: height, from: heightFeet.0,
                                                              to: heightFeet.1, canvas: Self.canvas)

        func placed(_ content: MeasureContent, _ feet: (CGPoint, CGPoint),
                    avoiding others: [CGRect]) -> MeasureContent {
            var probe = content
            probe.start = feet.0
            probe.end = feet.1
            let plan = MeasureLabelPlanner.plan(for: probe, canvas: Self.canvas, avoiding: others)
            probe.labelPlacement = plan.placement
            probe.labelNudge = plan.nudge
            return probe
        }
        let w = placed(width, widthFeet, avoiding: [])
        let wRect = w.labelRect(chipSize: w.estimatedLabelSize)
        let h = placed(height, heightFeet, avoiding: [wRect])
        let hRect = h.labelRect(chipSize: h.estimatedLabelSize)

        #expect(!wRect.intersects(hRect), "two readouts stacked: \(wRect) vs \(hRect)")
        // Neither covers the button they are measuring.
        #expect(!wRect.intersects(rect))
        #expect(!hRect.intersects(rect))
    }
}
