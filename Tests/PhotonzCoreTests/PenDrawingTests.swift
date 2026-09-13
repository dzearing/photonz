import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Laying a path down with the Pen: click a corner, press and drag a curve,
/// close it or finish it open (`docs/design/vector-paths.md`).
///
/// Everything the gesture DECIDES lives here, so the canvas only has to hand
/// over points and modifier keys.
@Suite("Drawing with the Pen")
struct PenDrawingTests {

    // Every test drives the session the way the canvas does: press, maybe
    // drag, release. These two keep that readable.
    private func click(_ session: inout PenSession, _ x: CGFloat, _ y: CGFloat,
                       constrained: Bool = false) -> PenSession.Outcome {
        session.press(at: CGPoint(x: x, y: y), constrained: constrained, zoom: 1)
        return session.release()
    }

    @discardableResult
    private func dragOut(_ session: inout PenSession, from: CGPoint, to: CGPoint,
                         constrained: Bool = false) -> PenSession.Outcome {
        session.press(at: from, constrained: constrained, zoom: 1)
        session.drag(to: to, constrained: constrained, zoom: 1)
        return session.release()
    }

    // MARK: A click drops a corner

    @Test func aFreshSessionHasDrawnNothing() {
        let session = PenSession()
        #expect(session.anchors.isEmpty)
        #expect(!session.isDrawing)
        #expect(session.livePath == nil)
    }

    @Test func aClickDropsACornerWithNoHandles() {
        var session = PenSession()
        let outcome = click(&session, 10, 20)
        #expect(outcome == .placed)
        #expect(session.anchors.count == 1)
        #expect(session.anchors[0].point == CGPoint(x: 10, y: 20))
        #expect(session.anchors[0].kind == .corner)
        #expect(session.anchors[0].handleIn == nil)
        #expect(session.anchors[0].handleOut == nil)
        #expect(session.isDrawing)
    }

    @Test func threeClicksAreThreeCorners() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        #expect(session.anchors.count == 3)
        #expect(session.anchors.allSatisfy { $0.kind == .corner })
    }

    // MARK: A press and drag pulls handles

    @Test func aDragPastTheThresholdPullsMirroredHandles() {
        var session = PenSession()
        let outcome = dragOut(&session, from: CGPoint(x: 100, y: 100),
                              to: CGPoint(x: 140, y: 100))
        #expect(outcome == .placed)
        let anchor = session.anchors[0]
        // The anchor stays where the press landed: the drag shapes the curve,
        // it does not move the point.
        #expect(anchor.point == CGPoint(x: 100, y: 100))
        #expect(anchor.kind == .smooth)
        #expect(anchor.handleOut == CGPoint(x: 40, y: 0))
        // The other side mirrors, which is what makes the curve run THROUGH
        // the anchor instead of kinking at it.
        #expect(anchor.handleIn == CGPoint(x: -40, y: 0))
    }

    @Test func aTinyWobbleIsStillAClick() {
        var session = PenSession()
        // Two points of travel: what a press on a trackpad does on its own.
        _ = dragOut(&session, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 52, y: 51))
        #expect(session.anchors[0].kind == .corner)
        #expect(session.anchors[0].handleOut == nil)
    }

    @Test func theThresholdIsMeasuredOnScreenNotInTheDocument() {
        // Zoomed 8x in, three document points is 24 on screen, which is a
        // deliberate drag. Zoomed out the same three points is nothing.
        var zoomedIn = PenSession()
        zoomedIn.press(at: .zero, constrained: false, zoom: 8)
        zoomedIn.drag(to: CGPoint(x: 3, y: 0), constrained: false, zoom: 8)
        _ = zoomedIn.release()
        #expect(zoomedIn.anchors[0].kind == .smooth)

        var zoomedOut = PenSession()
        zoomedOut.press(at: .zero, constrained: false, zoom: 0.25)
        zoomedOut.drag(to: CGPoint(x: 3, y: 0), constrained: false, zoom: 0.25)
        _ = zoomedOut.release()
        #expect(zoomedOut.anchors[0].kind == .corner)
    }

    @Test func aDragThatComesBackStaysADrag() {
        // Past the threshold and back to the press point. Letting the anchor
        // flip back to a corner would make it flicker between a corner and a
        // curve while the button is still down.
        var session = PenSession()
        session.press(at: CGPoint(x: 10, y: 10), constrained: false, zoom: 1)
        session.drag(to: CGPoint(x: 60, y: 10), constrained: false, zoom: 1)
        session.drag(to: CGPoint(x: 10, y: 10), constrained: false, zoom: 1)
        _ = session.release()
        #expect(session.anchors[0].kind == .smooth)
    }

    // MARK: The curve you are about to commit

    @Test func theRunToThePointerIsPreviewedFromTheLastAnchor() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        session.pointer = CGPoint(x: 100, y: 0)
        let preview = session.previewPath
        #expect(preview?.anchors.count == 2)
        #expect(preview?.anchors.last?.point == CGPoint(x: 100, y: 0))
        // Nothing is committed by looking at it.
        #expect(session.anchors.count == 1)
    }

    @Test func thePreviewRunCurvesOutOfTheLastAnchorsHandle() {
        var session = PenSession()
        _ = dragOut(&session, from: .zero, to: CGPoint(x: 0, y: 40))
        session.pointer = CGPoint(x: 100, y: 0)
        let run = session.previewPath?.segments.first
        #expect(run?.isStraight == false)
        #expect(run?.control1 == CGPoint(x: 0, y: 40))
        // The pointer end arrives straight: there is no handle there until
        // somebody drags one out.
        #expect(run?.control2 == CGPoint(x: 100, y: 0))
    }

    @Test func theAnchorBeingPlacedIsInThePathWhileTheButtonIsDown() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, zoom: 1)
        session.drag(to: CGPoint(x: 140, y: 40), constrained: false, zoom: 1)
        // Mid-drag the live path already shows the curve the release will
        // commit, which is the whole point of dragging one out.
        let live = session.livePath
        #expect(live?.anchors.count == 2)
        #expect(live?.anchors.last?.handleOut == CGPoint(x: 40, y: 40))
        #expect(live?.segments.first?.isStraight == false)
    }

    @Test func aPathOfOneAnchorHasNothingToPreviewUntilThePointerMoves() {
        var session = PenSession()
        _ = click(&session, 10, 10)
        session.pointer = nil
        #expect(session.previewPath?.anchors.count == 1)
    }

    // MARK: Closing

    @Test func theFirstAnchorIsACloseTargetOnceThereAreThreeOfThem() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        #expect(!session.wouldClose(at: CGPoint(x: 2, y: 2), zoom: 1))
        _ = click(&session, 50, 80)
        #expect(session.wouldClose(at: CGPoint(x: 2, y: 2), zoom: 1))
        #expect(!session.wouldClose(at: CGPoint(x: 40, y: 40), zoom: 1))
    }

    @Test func clickingTheFirstAnchorClosesThePath() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        // Near it, not on it: the click lands on the anchor, not on the pixel.
        session.press(at: CGPoint(x: 3, y: 3), constrained: false, zoom: 1)
        let outcome = session.release()
        guard case .closed(let content) = outcome else {
            Issue.record("clicking the first anchor should close the path, got \(outcome)")
            return
        }
        #expect(content.isClosed)
        #expect(content.anchors.count == 3)
        // No fourth anchor on top of the first one.
        #expect(content.anchors[0].point == CGPoint(x: 0, y: 0))
        #expect(content.fill != nil)
        // The session is spent: it drew its path and has nothing left.
        #expect(!session.isDrawing)
    }

    @Test func draggingOnTheCloseCurvesIntoTheFirstAnchor() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        session.press(at: CGPoint(x: 1, y: 1), constrained: false, zoom: 1)
        session.drag(to: CGPoint(x: 40, y: 0), constrained: false, zoom: 1)
        let outcome = session.release()
        guard case .closed(let content) = outcome else {
            Issue.record("a drag on the first anchor still closes, got \(outcome)")
            return
        }
        // The drag shapes the run ARRIVING back at the start, so the closing
        // run curves in rather than snapping straight.
        #expect(content.anchors[0].handleIn == CGPoint(x: -40, y: 0))
        // Its other side is the run to the second anchor, drawn three clicks
        // ago and left exactly as it was: arriving curved and leaving straight
        // is a half-smooth corner.
        #expect(content.anchors[0].handleOut == nil)
        #expect(content.anchors[0].isHalfSmooth)
    }

    @Test func twoAnchorsCannotClose() {
        // A closed path needs three corners to have an inside.
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        #expect(!session.wouldClose(at: .zero, zoom: 1))
        let outcome = click(&session, 0, 0)
        #expect(outcome == .placed)
        #expect(session.anchors.count == 3)
    }

    // MARK: Finishing an open path

    @Test func returnFinishesAnOpenPath() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 100, 100)
        let content = session.finish()
        #expect(content?.isClosed == false)
        #expect(content?.anchors.count == 3)
        // An open path is a line, so nothing is painted inside it.
        #expect(content?.fill == nil)
        #expect(!session.isDrawing)
    }

    @Test func onePointIsNotAPathSoFinishingLeavesNothing() {
        var session = PenSession()
        _ = click(&session, 10, 10)
        #expect(session.finish() == nil)
        #expect(!session.isDrawing)
    }

    @Test func clickingTheLastAnchorAgainFinishesTheOpenPath() {
        // For anyone who never thinks to press Return.
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 100, 100)
        #expect(session.wouldFinish(at: CGPoint(x: 101, y: 99), zoom: 1))
        session.press(at: CGPoint(x: 101, y: 99), constrained: false, zoom: 1)
        guard case .finished(let content) = session.release() else {
            Issue.record("clicking the last anchor should finish the open path")
            return
        }
        #expect(content.isClosed == false)
        #expect(content.anchors.count == 3)
        #expect(!session.isDrawing)
    }

    @Test func closingBeatsFinishingWhenTheTwoTargetsOverlap() {
        // Two anchors on top of each other: the first one wins, because
        // closing is the thing somebody circling back is trying to do.
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 1, 1)
        #expect(session.wouldClose(at: .zero, zoom: 1))
        #expect(!session.wouldFinish(at: .zero, zoom: 1))
    }

    @Test func discardingThrowsTheWholePathAway() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        session.discard()
        #expect(session.anchors.isEmpty)
        #expect(!session.isDrawing)
    }

    // MARK: Option, the one that makes an icon drawable

    @Test func optionWhileDraggingLeavesTheRunArrivingStraight() {
        // The half-smooth anchor: a straight edge arrives, a curve leaves. The
        // commonest thing in a real icon, and impossible without this.
        var session = PenSession()
        _ = click(&session, 0, 0)
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, breaking: true, zoom: 1)
        session.drag(to: CGPoint(x: 140, y: 0), constrained: false, zoom: 1)
        _ = session.release()
        let anchor = session.anchors[1]
        #expect(anchor.handleOut == CGPoint(x: 40, y: 0))
        #expect(anchor.handleIn == nil)
        #expect(anchor.isHalfSmooth)
        // The run behind it is a plain line, because neither end shapes it.
        #expect(session.livePath?.segments.first?.isStraight == true)
    }

    @Test func optionOnTheLastAnchorRetractsItsHandleInsteadOfFinishing() {
        // The other half of the same rule: the curve arrived here, and the
        // next edge leaves straight.
        var session = PenSession()
        _ = click(&session, 0, 0)
        dragOut(&session, from: CGPoint(x: 100, y: 0), to: CGPoint(x: 140, y: 0))
        session.press(at: CGPoint(x: 101, y: 1), constrained: false, breaking: true, zoom: 1)
        let outcome = session.release()
        #expect(outcome == .retracted)
        #expect(session.anchors[1].handleIn == CGPoint(x: -40, y: 0))
        #expect(session.anchors[1].handleOut == nil)
        #expect(session.anchors[1].kind == .corner)
        // Still drawing: retracting a handle is not a way to end a path.
        #expect(session.isDrawing)
        #expect(session.anchors.count == 2)
    }

    @Test func optionOnAnAnchorWithNothingToRetractLeavesItAlone() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        session.press(at: CGPoint(x: 100, y: 0), constrained: false, breaking: true, zoom: 1)
        let outcome = session.release()
        #expect(outcome == .retracted)
        #expect(session.anchors.count == 2)
        #expect(session.anchors[1].handleOut == nil)
        #expect(session.isDrawing)
    }

    @Test func aRoundedCornerComesOutWithAStraightEdgeOnEachSide() {
        // The shape the whole Option rule exists for: line, quarter round,
        // line. Both straight runs have to be actually straight.
        var session = PenSession()
        _ = click(&session, 0, 100)                                  // start of the top edge
        // The corner's arc starts here, so the edge arriving stays straight.
        session.press(at: CGPoint(x: 70, y: 100), constrained: false, breaking: true, zoom: 1)
        session.drag(to: CGPoint(x: 100, y: 100), constrained: false, zoom: 1)
        _ = session.release()
        // The arc ends here; the edge leaving has to be straight too.
        dragOut(&session, from: CGPoint(x: 100, y: 130), to: CGPoint(x: 100, y: 160))
        session.press(at: CGPoint(x: 100, y: 130), constrained: false, breaking: true, zoom: 1)
        _ = session.release()
        _ = click(&session, 100, 240)                                // down the right edge
        let runs = session.livePath?.segments ?? []
        #expect(runs.count == 3)
        #expect(runs.first?.isStraight == true)
        #expect(runs.dropFirst().first?.isStraight == false)
        #expect(runs.last?.isStraight == true)
    }

    // MARK: Shift

    @Test func shiftConstrainsTheNextPointToTheUsualAngles() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        // Nearly horizontal, a little low: shift flattens it onto the axis and
        // keeps the distance travelled, the way every constrained drag in the
        // app does.
        _ = click(&session, 100, 12, constrained: true)
        #expect(session.anchors[1].point.y == 0)
        #expect(abs(session.anchors[1].point.x - hypot(100, 12)) < 0.001)
    }

    @Test func shiftSnapsToTheNearestFortyFive() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 90, constrained: true)
        let placed = session.anchors[1].point
        #expect(abs(placed.x - placed.y) < 0.001)
        #expect(placed.x > 0)
    }

    @Test func theFirstPointHasNothingToConstrainAgainst() {
        var session = PenSession()
        _ = click(&session, 37, 91, constrained: true)
        #expect(session.anchors[0].point == CGPoint(x: 37, y: 91))
    }

    @Test func shiftAlsoStraightensTheHandleYouArePulling() {
        var session = PenSession()
        session.press(at: .zero, constrained: true, zoom: 1)
        session.drag(to: CGPoint(x: 100, y: 12), constrained: true, zoom: 1)
        _ = session.release()
        #expect(session.anchors[0].handleOut?.y == 0)
        #expect(abs((session.anchors[0].handleOut?.x ?? 0) - hypot(100, 12)) < 0.001)
    }

    // MARK: Undo while drawing

    @Test func undoStepsBackOnePointAtATime() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        var stepped = session.undoLastAnchor()
        #expect(stepped)
        #expect(session.anchors.count == 2)
        stepped = session.undoLastAnchor()
        #expect(stepped)
        #expect(session.anchors.count == 1)
        #expect(session.isDrawing)
    }

    @Test func undoingTheLastPointEndsTheSessionRatherThanLeavingItEmpty() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        let stepped = session.undoLastAnchor()
        #expect(stepped)
        #expect(session.anchors.isEmpty)
        #expect(!session.isDrawing)
        // With nothing left to step back through, the pen stops answering and
        // Command Z means what it always means.
        let again = session.undoLastAnchor()
        #expect(!again)
    }

    // MARK: What the canvas draws

    @Test func theClosingRunIsPreviewedWhileThePointerIsOverTheFirstAnchor() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        session.pointer = CGPoint(x: 2, y: 2)
        let preview = session.previewPath
        // Not a fourth anchor at the pointer: the run shown is the one that
        // would close, drawn back to the anchor it would land on.
        #expect(preview?.anchors.count == 3)
        #expect(preview?.isClosed == true)
    }

    @Test func aPathBeingDrawnIsNotFilledUntilItCloses() {
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        session.pointer = CGPoint(x: 50, y: 80)
        #expect(session.previewPath?.isClosed == false)
    }

    // MARK: The words on screen

    @Test func theHintSaysWhatToDoNext() {
        var session = PenSession()
        #expect(PenSession.hint(for: session).contains("Click"))
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        let hint = PenSession.hint(for: session)
        // The two keys that end a path have to be told apart, and this is
        // where they are: Return keeps what you drew, Escape throws it away.
        #expect(hint.contains("Return"))
        #expect(hint.contains("Esc"))
        #expect(hint.contains("close"))
    }

    /// The Pen stays in hand after a shape lands, so the opening line is also
    /// the line you read BETWEEN shapes — and it is the only place that says
    /// how to put the tool down. Without that, a person who has finished their
    /// icon has to hunt for the way out of a tool that no longer hands itself
    /// back.
    @Test func theOpeningLineSaysHowToPutThePenDown() {
        let opening = PenSession.hint(for: PenSession())
        #expect(opening.contains("Esc"))
        #expect(opening.contains("puts the Pen down"))

        // A closed shape empties the session, so that same opening line is
        // what the chip says while you are between the shapes of an icon.
        var session = PenSession()
        _ = click(&session, 0, 0)
        _ = click(&session, 100, 0)
        _ = click(&session, 50, 80)
        session.press(at: CGPoint(x: 0, y: 0), constrained: false, zoom: 1)
        guard case .closed = session.release() else {
            Issue.record("the click back on the first anchor should have closed the path")
            return
        }
        #expect(!session.isDrawing)
        #expect(PenSession.hint(for: session) == opening)
    }
}
