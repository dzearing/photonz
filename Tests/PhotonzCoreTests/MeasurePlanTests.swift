import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Where a measurement's readout lands and what its own line does about it.
///
/// This used to live inside `MeasureRasterizer`, where only the picture could
/// see it. It is here because the SVG writer draws the same caliper now, and
/// two copies of "where does the line stop" would be two answers.
@Suite("Where a measurement's readout lands")
struct MeasurePlanTests {

    static func caliper(placement: MeasureLabelPlacement = .onLine,
                        reach: CGFloat = 0) -> MeasureContent {
        var content = MeasureContent(start: CGPoint(x: 40, y: 120),
                                     end: CGPoint(x: 210, y: 120), mode: .horizontal)
        content.labelPlacement = placement
        content.labelCrossReach = reach
        content.labelPinned = true
        return content
    }

    static let chip = CGSize(width: 54, height: 26)

    @Test func aReadoutOnTheLineSplitsItAndNeedsNoLeader() {
        let content = Self.caliper()
        let plan = MeasurePlan.make(content, geometry: content.caliperGeometry(),
                                    chipSize: Self.chip)
        #expect(plan.pill != nil)
        #expect(plan.leader == nil)
        #expect(plan.center == content.labelPosition(chipSize: Self.chip))
    }

    @Test func aReadoutPushedClearOfTheLineGetsALeaderBackToIt() {
        let content = Self.caliper(placement: .clearNegative, reach: 60)
        let plan = MeasurePlan.make(content, geometry: content.caliperGeometry(),
                                    chipSize: Self.chip)
        #expect(plan.pill == nil, "the line draws whole once the readout has moved off it")
        #expect(plan.leader != nil, "a readout this far off its line has to be tied back to it")
        // It runs from the caliper's own strokes to the plate's outline, never
        // to the middle of it.
        if let leader = plan.leader {
            #expect(!LabelCapsule(center: plan.center, size: Self.chip).contains(leader.from))
            #expect(leader.to != plan.center)
        }
    }

    @Test func aReadoutThatIsNotDrawnPlansNothing() {
        var content = Self.caliper()
        content.showLabel = false
        let plan = MeasurePlan.make(content, geometry: content.caliperGeometry(),
                                    chipSize: .zero)
        #expect(plan.pill == nil)
        #expect(plan.leader == nil)
        #expect(plan.size == .zero)
    }

    // MARK: - The plate as a shape to run into

    @Test func aLineStopsOnTheRoundCapRatherThanOnACornerThatIsNotThere() {
        let capsule = LabelCapsule(center: CGPoint(x: 100, y: 100),
                                   size: CGSize(width: 60, height: 20))
        // Straight in from the left: it stops on the flat end of the core,
        // which for a capsule is the leftmost point of the cap.
        let entry = capsule.entry(from: CGPoint(x: 0, y: 100), toward: capsule.center)
        #expect(entry != nil)
        #expect(abs((entry?.x ?? 0) - 70) < 0.01)
        // The corner of the bounding box is OUTSIDE a capsule, so a run that
        // aimed there would find no crossing at all.
        #expect(!capsule.contains(CGPoint(x: 70.5, y: 90.5)))
        #expect(capsule.contains(capsule.center))
    }

    @Test func aRunThatStartsInsideHasNoCrossingToFind() {
        let capsule = LabelCapsule(center: CGPoint(x: 100, y: 100),
                                   size: CGSize(width: 60, height: 20))
        #expect(capsule.entry(from: CGPoint(x: 98, y: 100), toward: capsule.center) == nil)
    }

    // MARK: - An alignment check's guide

    @Test func theGuideLeavesTheStretchThePlateIsSittingOnAlone() {
        let content = Self.caliper()
        let plan = MeasurePlan.make(content, geometry: content.caliperGeometry(),
                                    chipSize: Self.chip)
        let gap = plan.guideGap(vertical: false)
        #expect(gap != nil)
        #expect(gap?.lowerBound == plan.center.x - Self.chip.width / 2)
        #expect(gap?.upperBound == plan.center.x + Self.chip.width / 2)
        // A run crossing it comes back in two pieces, and one clear of it comes
        // back whole.
        #expect(MeasurePlan.clip(40...210, around: gap).count == 2)
        #expect(MeasurePlan.clip(40...50, around: gap) == [40...50])
    }
}
