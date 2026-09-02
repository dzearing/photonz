import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The one scorer every label on the picture goes through: a measurement's
/// readout, an arrow's caption, the roles legend. Each surface describes its
/// own candidate spots and what it has to keep off; the ranking rules live
/// here, so "never cover the subject" is one rule rather than three.
@Suite("One placer for every label")
struct LabelPlacerTests {

    private func candidate(_ rect: CGRect, _ name: String,
                           cost: CGFloat = 0) -> LabelCandidate<String> {
        LabelCandidate(rect: rect, payload: name, cost: cost)
    }
    private let pill = CGSize(width: 100, height: 40)
    private func box(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: pill)
    }

    @Test func noCandidatesMeansNoAnswer() {
        #expect(LabelPlacer.best(among: [LabelCandidate<String>](), avoiding: []) == nil)
    }

    /// Nothing in the way: the surface's own first choice wins, since a surface
    /// lists its candidates in the order it prefers them and prices that order
    /// into their costs.
    @Test func theSurfacesFirstChoiceWinsWhenNothingIsInTheWay() {
        #expect(LabelPlacer.best(among: [candidate(box(0, 0), "first", cost: 0),
                                         candidate(box(200, 0), "second", cost: 4)],
                                 avoiding: []) == "first")
    }

    /// The rule this whole placer exists for: a spot that covers what the label
    /// is describing loses to any spot that does not, however far down the
    /// preference order that spot sits.
    @Test func aSpotThatCoversTheSubjectLosesToOneThatDoesNot() {
        let subject = LabelAvoidance(rects: [box(0, 0)], weight: .flat(LabelPlacer.subjectCost))
        #expect(LabelPlacer.best(among: [candidate(box(0, 0), "on the subject", cost: 0),
                                         candidate(box(400, 400), "clear", cost: 32)],
                                 avoiding: [subject]) == "clear")
    }

    /// Covering two subjects is no worse than covering one. That is the user's
    /// own answer for a caliper boxed in between two rows: when every spot is
    /// on something, the label stays where you look for it instead of hopping
    /// to whichever spot happens to cover the least.
    @Test func coveringTwoSubjectsCostsNoMoreThanCoveringOne() {
        let subjects = LabelAvoidance(rects: [box(0, 0), box(90, 0)],
                                      weight: .flat(LabelPlacer.subjectCost))
        #expect(LabelPlacer.best(among: [candidate(box(80, 0), "on both", cost: 0),
                                         candidate(box(-50, 0), "on one", cost: 4)],
                                 avoiding: [subjects]) == "on both")
    }

    /// A softer neighbour is charged in proportion to how far the label reaches
    /// into it, so a label that clips a corner is not priced as if it had
    /// parked in the middle of the row.
    @Test func aNeighbourCostsInProportionToHowFarTheLabelReachesIn() {
        let row = CGRect(x: 0, y: 40, width: 400, height: 200)
        let soft = LabelAvoidance(rects: [row],
                                  weight: .depth(LabelPlacer.overlapCost, horizontal: true))
        let clear = candidate(box(0, -200), "clear", cost: 40)
        // A quarter of the pill's height into the row is a quarter of the price.
        #expect(LabelPlacer.best(among: [candidate(box(0, 10), "shallow"), clear],
                                 avoiding: [soft]) == "shallow")
        // Three quarters in is not.
        #expect(LabelPlacer.best(among: [candidate(box(0, 30), "deep"), clear],
                                 avoiding: [soft]) == "clear")
    }

    /// Depth across the line, not area: a neighbour half the label's width
    /// costs exactly what a wide one at the same depth costs, because what
    /// decides whether a number reads as the next row's is how far into that
    /// row it hangs, not how much of it it happens to shade.
    @Test func aNarrowNeighbourCostsTheSameAsAWideOneAtTheSameDepth() {
        func winner(rowWidth: CGFloat) -> String? {
            let row = CGRect(x: 0, y: 40, width: rowWidth, height: 200)
            let soft = LabelAvoidance(rects: [row],
                                      weight: .depth(LabelPlacer.overlapCost, horizontal: true))
            return LabelPlacer.best(among: [candidate(box(0, 10), "dipping"),
                                            candidate(box(0, -200), "clear", cost: 35)],
                                    avoiding: [soft])
        }
        // A quarter-depth dip costs 30, which beats a 35 detour either way.
        #expect(winner(rowWidth: 400) == "dipping")
        #expect(winner(rowWidth: 50) == "dipping")
    }

    /// Chrome drawn on top of the label is not a cost, it is a veto: a panel
    /// behind the tool bar is simply invisible.
    @Test func aForbiddenRectTakesTheSpotOutOfTheRunningAltogether() {
        let chrome = LabelAvoidance(rects: [box(0, 0)], weight: .forbidden)
        #expect(LabelPlacer.best(among: [candidate(box(0, 0), "under the bar"),
                                         candidate(box(400, 400), "visible", cost: 1000)],
                                 avoiding: [chrome]) == "visible")
    }

    /// And when every spot is vetoed there is no answer at all, so the surface
    /// falls back to whatever it wants rather than being handed an invisible
    /// spot as if it were a good one.
    @Test func everySpotVetoedMeansNoAnswer() {
        let chrome = LabelAvoidance(rects: [CGRect(x: -1000, y: -1000, width: 4000, height: 4000)],
                                    weight: .forbidden)
        #expect(LabelPlacer.best(among: [candidate(box(0, 0), "a"), candidate(box(400, 0), "b")],
                                 avoiding: [chrome]) == nil)
    }

    /// Running off the picture is the worst thing a label can do: a number you
    /// cannot read is not a measurement, so it outranks even covering the
    /// subject.
    @Test func fallingOffThePictureCostsMoreThanCoveringTheSubject() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let subject = LabelAvoidance(rects: [box(100, 100)], weight: .flat(LabelPlacer.subjectCost))
        #expect(LabelPlacer.best(among: [candidate(box(460, 100), "half off"),
                                         candidate(box(100, 100), "on the subject", cost: 4)],
                                 avoiding: [subject], within: bounds) == "on the subject")
    }

    /// Of two otherwise equal spots the nearer one wins, so a label never
    /// wanders further than it had to.
    @Test func theNearerOfTwoEqualSpotsWins() {
        #expect(LabelPlacer.best(among: [candidate(box(1000, 0), "far"),
                                         candidate(box(50, 0), "near")],
                                 avoiding: [], anchoredAt: .zero) == "near")
    }

    /// And travel is only ever a nudge: it can break a tie, never send a label
    /// onto its subject.
    @Test func travelNeverOutweighsTheSubjectRule() {
        let subject = LabelAvoidance(rects: [box(0, 0)], weight: .flat(LabelPlacer.subjectCost))
        #expect(LabelPlacer.best(among: [candidate(box(0, 0), "near but covering"),
                                         candidate(box(9000, 9000), "far and clear")],
                                 avoiding: [subject], anchoredAt: .zero) == "far and clear")
    }

    /// The leader test both the measure readout and the arrow caption need:
    /// does the straight run from A to B pass through this box? Solved rather
    /// than sampled, so a short diagonal through a corner is caught too.
    @Test func aRunThroughABoxIsSeenIncludingADiagonalThroughACorner() {
        let target = CGRect(x: 100, y: 100, width: 200, height: 200)
        #expect(LabelPlacer.segment(from: CGPoint(x: 0, y: 200), to: CGPoint(x: 400, y: 200),
                                    crosses: [target]))
        #expect(!LabelPlacer.segment(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 0),
                                     crosses: [target]))
        #expect(LabelPlacer.segment(from: CGPoint(x: 0, y: 250), to: CGPoint(x: 250, y: 0),
                                    crosses: [target]))
        // A run that stops short of the box is not a crossing.
        #expect(!LabelPlacer.segment(from: CGPoint(x: 0, y: 200), to: CGPoint(x: 90, y: 200),
                                     crosses: [target]))
        // And a run of no length is not a run.
        #expect(!LabelPlacer.segment(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 200, y: 200),
                                     crosses: [target]))
    }
}
