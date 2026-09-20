import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Sweeping a box over a path's points instead of gathering them one ⇧ click
/// at a time. An icon of any real detail has thirty or forty points, so one
/// side of it used to be thirty clicks and one miss started over.
@Suite("Sweeping up the points of a path")
struct PathPointSweepTests {

    /// A square of four corners at (0,0), (100,0), (100,100), (0,100).
    static let square = PathContent(anchors: [
        PathAnchor(point: CGPoint(x: 0, y: 0)),
        PathAnchor(point: CGPoint(x: 100, y: 0)),
        PathAnchor(point: CGPoint(x: 100, y: 100)),
        PathAnchor(point: CGPoint(x: 0, y: 100)),
    ], isClosed: true)

    @Test func aBoxTakesEveryPointInsideIt() {
        // The whole top edge, and nothing below it.
        let caught = Self.square.anchorIndices(in: CGRect(x: -20, y: -20, width: 160, height: 60))
        #expect(caught == [0, 1])
    }

    @Test func aBoxRoundTheWholeShapeTakesAllOfIt() {
        let caught = Self.square.anchorIndices(in: CGRect(x: -10, y: -10, width: 130, height: 130))
        #expect(caught == [0, 1, 2, 3])
    }

    @Test func aBoxOverClearSpaceTakesNothing() {
        #expect(Self.square.anchorIndices(in: CGRect(x: 200, y: 200, width: 50, height: 50)).isEmpty)
    }

    /// A box crossing the outline without reaching a point takes nothing: it is
    /// the POINTS it gathers, not the runs between them.
    @Test func crossingTheOutlineIsNotCatchingAPoint() {
        #expect(Self.square.anchorIndices(in: CGRect(x: 40, y: -10, width: 20, height: 30)).isEmpty)
    }

    /// Nobody drags a box left to right and downwards every time.
    @Test func aBoxDrawnBackwardsCatchesTheSame() {
        let forwards = CGRect(x: -20, y: -20, width: 160, height: 60)
        let backwards = CGRect(x: 140, y: 40, width: -160, height: -60)
        #expect(Self.square.anchorIndices(in: backwards) == Self.square.anchorIndices(in: forwards))
    }

    /// A point exactly on the edge of the box is inside it: a sweep drawn to
    /// land on a point is a sweep meant to take it.
    @Test func aPointOnTheEdgeOfTheBoxIsCaught() {
        #expect(Self.square.anchorIndices(in: CGRect(x: 0, y: 0, width: 50, height: 50)) == [0])
    }

    /// A box with no width is a click, and it takes the point it lands on
    /// rather than nothing at all.
    @Test func aBoxOfNoSizeStillTakesWhatItLandsOn() {
        #expect(Self.square.anchorIndices(in: CGRect(x: 100, y: 100, width: 0, height: 0)) == [2])
    }

    // MARK: - What the sweep leaves picked

    @Test func aPlainSweepBecomesTheWholeSelection() {
        #expect(PathPointSweep.selection(caught: [2, 3], startingFrom: [0], adding: false)
                == [2, 3])
    }

    /// The one that makes a thirty point icon workable: three sweeps down one
    /// side, each adding to the last.
    @Test func holdingShiftAddsToWhatWasAlreadyPicked() {
        #expect(PathPointSweep.selection(caught: [2, 3], startingFrom: [0], adding: true)
                == [0, 2, 3])
    }

    /// Adding is adding and never toggling: sweeping back over a point that is
    /// already picked leaves it picked, exactly as ⇧ sweeping layers does.
    @Test func sweepingOverAPickedPointAgainLeavesItPicked() {
        #expect(PathPointSweep.selection(caught: [0, 1], startingFrom: [0], adding: true)
                == [0, 1])
    }

    /// A box thrown round empty space with nothing held means "none of them",
    /// which is the same thing a click in clear air has always meant here.
    @Test func aPlainSweepThatCatchesNothingLetsThePointsGo() {
        #expect(PathPointSweep.selection(caught: [], startingFrom: [0, 1], adding: false)
                .isEmpty)
    }

    /// ⇧ never takes anything away, so a ⇧ sweep that misses everything is the
    /// one sweep that changes nothing.
    @Test func aShiftSweepThatCatchesNothingChangesNothing() {
        #expect(PathPointSweep.selection(caught: [], startingFrom: [0, 1], adding: true)
                == [0, 1])
    }

    // MARK: - Levers stand down for a crowd

    /// Levers belong to ONE picked point. Thirty points swept up at once would
    /// otherwise put sixty arms and sixty more dots over the shape you are
    /// trying to see, which is the whole reason they are drawn per point.
    @Test func leversShowForOnePickedPointAndNoMore() {
        #expect(PathContent.leversShowing(for: [4]) == [4])
        #expect(PathContent.leversShowing(for: [4, 5]).isEmpty)
        #expect(PathContent.leversShowing(for: []).isEmpty)
    }

    /// A lever nobody can see is not a target either, or a press in clear air
    /// near a crowd of picked points would catch something invisible.
    @Test func aLeverThatIsNotDrawnCannotBeGrabbed() {
        let bend = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleIn: CGPoint(x: -30, y: 0),
                       handleOut: CGPoint(x: 30, y: 0), kind: .smooth),
            PathAnchor(point: CGPoint(x: 100, y: 100)),
        ], isClosed: true)
        let onTheLever = CGPoint(x: 130, y: 0)
        #expect(bend.editTarget(at: onTheLever, zoom: 1,
                                handlesShowing: PathContent.leversShowing(for: [1]))
                == .handle(anchor: 1, side: .handleOut))
        #expect(bend.editTarget(at: onTheLever, zoom: 1,
                                handlesShowing: PathContent.leversShowing(for: [1, 2])) == nil)
    }
}
