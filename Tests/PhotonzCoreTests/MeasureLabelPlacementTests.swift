import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// D14: a callout never covers what it is talking about. These pin the
/// placement model (where the readout sits) and the planner (which side it
/// picks), both pure geometry in PhotonzCore.
struct MeasureLabelPlacementTests {

    /// A horizontal caliper 200 px wide with its head 40 px below the feet.
    private func caliper(headOffset: CGFloat = 40) -> MeasureContent {
        MeasureContent(start: CGPoint(x: 100, y: 300), end: CGPoint(x: 300, y: 300),
                       headOffset: headOffset, mode: .horizontal)
    }

    /// A vertical alignment guide at x = 100 running y 200…400, checking three
    /// left edges, one of which is `outlier` px to the right of the others.
    private func alignment(outlier: CGFloat = 5) -> MeasureContent {
        var m = MeasureContent(start: CGPoint(x: 100, y: 200), end: CGPoint(x: 100, y: 400),
                               headOffset: 0, mode: .vertical)
        m.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 100, spanStart: 200, spanEnd: 260),
            AlignmentItem(edge: 100 + outlier, spanStart: 270, spanEnd: 330),
            AlignmentItem(edge: 100, spanStart: 340, spanEnd: 400),
        ], tolerance: 1)
        return m
    }

    private let chip = CGSize(width: 90, height: 34)

    // MARK: - The placement model

    @Test func onLineKeepsTheReadoutOnTheAnchor() {
        var m = caliper()
        m.labelPlacement = .onLine
        #expect(m.labelPosition(chipSize: chip) == m.labelAnchor)
    }

    @Test func afterEndPutsTheChipEntirelyPastThePositiveEnd() {
        var m = caliper()
        m.labelPlacement = .afterEnd
        let rect = m.labelRect(chipSize: chip)
        // Fully clear of the caliper's own span, in the +x direction.
        #expect(rect.minX > 300)
        // Still centred on the head line, so it reads as its continuation.
        #expect(rect.midY == m.labelAnchor.y)
    }

    @Test func beforeStartMirrorsAfterEnd() {
        var m = caliper()
        m.labelPlacement = .beforeStart
        #expect(m.labelRect(chipSize: chip).maxX < 100)
    }

    /// The inner edge of an end-placed chip lands the same distance past the
    /// end whatever size the chip is — a bigger readout grows outward, so the
    /// clearance can never go stale.
    @Test func endPlacementClearanceIsIndependentOfChipSize() {
        var m = caliper()
        m.labelPlacement = .afterEnd
        let small = m.labelRect(chipSize: CGSize(width: 40, height: 20)).minX
        let large = m.labelRect(chipSize: CGSize(width: 200, height: 60)).minX
        #expect(abs(small - large) < 0.001)
    }

    @Test func clearPushesPerpendicularPastTheFurthestCheckedEdge() {
        var m = alignment(outlier: 30)
        m.labelPlacement = .clearPositive
        let rect = m.labelRect(chipSize: chip)
        // Past the outlier's edge (x = 130), not just past the guide (x = 100).
        #expect(rect.minX > 130)
    }

    @Test func clearNeverPullsAChipInTowardWhatItMeasures() {
        var m = caliper(headOffset: 40)
        m.labelPlacement = .clearPositive
        // The head already stands 40 px clear: nothing to gain, nothing moves.
        #expect(m.labelPosition(chipSize: chip) == m.labelAnchor)
    }

    @Test func clearRescuesAChipWhoseHeadSitsOnTheMeasuredLine() {
        var m = caliper(headOffset: 4)
        m.labelPlacement = .clearPositive
        let rect = m.labelRect(chipSize: chip)
        #expect(rect.minY > 300)
    }

    @Test func nudgeShiftsAlongTheAxisOnly() {
        var m = caliper()
        m.labelPlacement = .onLine
        m.labelNudge = 25
        let p = m.labelPosition(chipSize: chip)
        #expect(p.x == m.labelAnchor.x + 25)
        #expect(p.y == m.labelAnchor.y)
    }

    // MARK: - What a measurement is describing

    @Test func aCaliperSubjectIsTheLineBetweenItsFeet() {
        let rects = caliper().subjectRects
        #expect(rects.count == 1)
        #expect(rects[0].minX <= 100)
        #expect(rects[0].maxX >= 300)
        #expect(rects[0].contains(CGPoint(x: 200, y: 300)))
    }

    @Test func anAlignmentSubjectCoversEveryCheckedRunAndReachesTheOutlier() {
        let rects = alignment(outlier: 30).subjectRects
        #expect(rects.count == 3)
        // Every checked run is protected…
        #expect(rects.contains { $0.contains(CGPoint(x: 100, y: 230)) })
        #expect(rects.contains { $0.contains(CGPoint(x: 100, y: 370)) })
        // …and the outlier's real edge, out at x = 130, is inside its own rect.
        #expect(rects.contains { $0.contains(CGPoint(x: 130, y: 300)) })
    }

    // MARK: - The planner

    /// The bug this task exists for: the verdict must not land on the rows.
    @Test func plannerMovesTheAlignmentVerdictOffTheCheckedRows() {
        let m = alignment()
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        var placed = m
        placed.labelPlacement = plan.placement
        placed.labelNudge = plan.nudge
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        for subject in m.subjectRects {
            #expect(!rect.intersects(subject))
        }
    }

    @Test func plannerKeepsTheVerdictOnTheCanvas() {
        // The guide runs to the bottom edge, so "past the end" would fall off.
        var m = MeasureContent(start: CGPoint(x: 100, y: 40), end: CGPoint(x: 100, y: 396),
                               headOffset: 0, mode: .vertical)
        m.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 100, spanStart: 40, spanEnd: 200),
            AlignmentItem(edge: 105, spanStart: 210, spanEnd: 396),
        ], tolerance: 1)
        let canvas = CGSize(width: 400, height: 400)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas)
        var placed = m
        placed.labelPlacement = plan.placement
        placed.labelNudge = plan.nudge
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: canvas).contains(rect))
        for subject in m.subjectRects { #expect(!rect.intersects(subject)) }
    }

    /// A caliper whose head already stands clear keeps the classic look: the
    /// fix must not shove labels that were never in the way.
    @Test func plannerLeavesAClearCaliperOnItsHeadLine() {
        let m = caliper(headOffset: 40)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        #expect(plan.placement == .onLine)
        #expect(plan.nudge == 0)
    }

    @Test func plannerRescuesACaliperWhoseReadoutSitsOnWhatItMeasures() {
        let m = caliper(headOffset: 3)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        var placed = m
        placed.labelPlacement = plan.placement
        placed.labelNudge = plan.nudge
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        for subject in m.subjectRects { #expect(!rect.intersects(subject)) }
    }

    @Test func plannerNudgesTwoNearbyReadoutsApart() {
        let first = caliper(headOffset: 40)
        let firstRect = first.labelRect(chipSize: first.estimatedLabelSize)
        // A second caliper 6 px below the first: its readout would stack.
        var second = caliper(headOffset: 40)
        second.start.y += 6
        second.end.y += 6
        let plan = MeasureLabelPlanner.plan(for: second, canvas: CGSize(width: 800, height: 800),
                                            avoiding: [firstRect])
        var placed = second
        placed.labelPlacement = plan.placement
        placed.labelNudge = plan.nudge
        let rect = placed.labelRect(chipSize: second.estimatedLabelSize)
        #expect(!rect.intersects(firstRect))
    }

    // MARK: - Moving a label never moves the measurement (D14 rule 5)

    @Test func relocatingTheReadoutLeavesTheGeometryUntouched() {
        let base = alignment(outlier: 30)
        for placement in MeasureLabelPlacement.allCases {
            var moved = base
            moved.labelPlacement = placement
            moved.labelNudge = 17
            #expect(moved.caliperGeometry() == base.caliperGeometry(),
                    "\(placement) moved the guide")
            #expect(moved.alignment?.items == base.alignment?.items,
                    "\(placement) moved the ticks")
            #expect(moved.subjectRects == base.subjectRects,
                    "\(placement) moved what is being checked")
        }
    }

    @Test func rebuildingALayerAroundAMovedReadoutKeepsTheFeetWhereTheyWere() {
        var m = alignment()
        m.labelPlacement = .afterEnd
        let start = CGPoint(x: 100, y: 200), end = CGPoint(x: 100, y: 400)
        let layer = MeasureBuilder.layer(content: m, from: start, to: end)
        guard let built = layer.measure else { Issue.record("no measure"); return }
        #expect(abs(built.start.x + layer.frame.minX - start.x) < 0.001)
        #expect(abs(built.start.y + layer.frame.minY - start.y) < 0.001)
        #expect(abs(built.end.y + layer.frame.minY - end.y) < 0.001)
    }

    // MARK: - Persistence

    @Test func placementSurvivesACodableRoundTrip() throws {
        var m = alignment()
        m.labelPlacement = .afterEnd
        m.labelNudge = 12
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back.labelPlacement == .afterEnd)
        #expect(back.labelNudge == 12)
    }

    /// A document written before this feature has no placement key; it must
    /// come back looking exactly as it did, on the line.
    @Test func legacyDocumentsDecodeOnTheLine() throws {
        let json = """
        {"start":[10,10],"end":[110,10],"headOffset":40,"mode":"horizontal",
         "strokeWidth":2,"showLabel":true,"unit":"points","decimals":0}
        """
        let back = try JSONDecoder().decode(MeasureContent.self, from: Data(json.utf8))
        #expect(back.labelPlacement == .onLine)
        #expect(back.labelNudge == 0)
    }

    // MARK: - The frame reserves room where the chip actually lands

    @Test func theLayerFrameHoldsARelocatedReadout() {
        var m = alignment()
        m.labelPlacement = .afterEnd
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 100, y: 200),
                                         to: CGPoint(x: 100, y: 400))
        guard let built = layer.measure else { Issue.record("no measure"); return }
        let rect = built.labelRect(chipSize: built.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: layer.frame.size).contains(rect))
    }
}
