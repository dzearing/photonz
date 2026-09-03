import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("MarqueeDrag")
struct MarqueeTests {
    let canvas = CGSize(width: 800, height: 600)

    // MARK: Rect construction

    @Test func dragDownRightProducesThatRect() {
        var drag = MarqueeDrag(anchor: CGPoint(x: 100, y: 50))
        drag.update(to: CGPoint(x: 300, y: 250))
        #expect(drag.selectionRect(in: canvas) == CGRect(x: 100, y: 50, width: 200, height: 200))
    }

    @Test func dragUpLeftStandardizes() {
        // Dragging from bottom-right to top-left yields the same rect as the reverse drag.
        var drag = MarqueeDrag(anchor: CGPoint(x: 300, y: 250))
        drag.update(to: CGPoint(x: 100, y: 50))
        #expect(drag.selectionRect(in: canvas) == CGRect(x: 100, y: 50, width: 200, height: 200))
    }

    @Test func freshDragIsEmpty() {
        let drag = MarqueeDrag(anchor: CGPoint(x: 10, y: 10))
        #expect(drag.selectionRect(in: canvas) == nil)
    }

    // MARK: Square constraint (⇧)

    @Test func squareConstraintUsesTheLongerAxis() {
        var drag = MarqueeDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 300, y: 150)) // dx 200, dy 50 → 200×200
        #expect(drag.selectionRect(constrainSquare: true, in: canvas)
                == CGRect(x: 100, y: 100, width: 200, height: 200))
    }

    @Test func squareConstraintFollowsTheDragDirection() {
        // Dragging up-left keeps the square on the up-left side of the anchor.
        var drag = MarqueeDrag(anchor: CGPoint(x: 400, y: 400))
        drag.update(to: CGPoint(x: 350, y: 250)) // dx -50, dy -150 → 150×150 up-left
        #expect(drag.selectionRect(constrainSquare: true, in: canvas)
                == CGRect(x: 250, y: 250, width: 150, height: 150))
    }

    // MARK: Canvas clamping

    @Test func selectionIsClampedToTheCanvas() {
        var drag = MarqueeDrag(anchor: CGPoint(x: 700, y: 500))
        drag.update(to: CGPoint(x: 2000, y: 2000)) // way past the bottom-right corner
        #expect(drag.selectionRect(in: canvas) == CGRect(x: 700, y: 500, width: 100, height: 100))
    }

    @Test func anchorOutsideTheCanvasStillClampsIn() {
        var drag = MarqueeDrag(anchor: CGPoint(x: -50, y: -50))
        drag.update(to: CGPoint(x: 100, y: 100))
        #expect(drag.selectionRect(in: canvas) == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func dragEntirelyOutsideTheCanvasIsNoSelection() {
        var drag = MarqueeDrag(anchor: CGPoint(x: -200, y: -200))
        drag.update(to: CGPoint(x: -10, y: -10))
        #expect(drag.selectionRect(in: canvas) == nil)
    }

    // MARK: Click vs drag (zoom-aware: the tolerance lives in view points)

    @Test func tinyMovementIsAClick() {
        var drag = MarqueeDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 102, y: 101)) // ~2.2 view pts at 1×
        #expect(drag.isClick(atZoom: 1))
    }

    @Test func theSameDocumentMovementIsADragWhenZoomedIn() {
        // 2 doc points at 8× is 16 view points — clearly an intentional drag.
        var drag = MarqueeDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 102, y: 101))
        #expect(!drag.isClick(atZoom: 8))
    }

    @Test func aLargeDocumentMovementIsAClickWhenZoomedFarOut() {
        // 10 doc points at 1/4× is 2.5 view points — finger jitter, not a marquee.
        var drag = MarqueeDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 110, y: 100))
        #expect(drag.isClick(atZoom: 0.25))
    }

    // MARK: Pixel alignment

    @Test func pixelAlignedRoundsEdgesToTheNearestInteger() {
        let r = Geometry.pixelAligned(CGRect(x: 10.6, y: 19.4, width: 99.8, height: 50.0))
        // Edges round independently: x 10.6→11, y 19.4→19, maxX 110.4→110, maxY 69.4→69.
        #expect(r == CGRect(x: 11, y: 19, width: 99, height: 50))
    }

    @Test func pixelAlignedNeverCollapsesANonEmptyRect() {
        let r = Geometry.pixelAligned(CGRect(x: 5.4, y: 5.4, width: 0.3, height: 0.3))
        #expect(r.width >= 1 && r.height >= 1)
    }
}

@Suite("BareCanvasPress")
struct BareCanvasPressTests {
    @Test func plainPressLetsGoOfTheSelection() {
        let press = BareCanvasPress(shift: false)
        #expect(press == .replaces)
        #expect(press.clearsSelectionOnPress)
    }

    @Test func shiftPressKeepsTheSelection() {
        // A ⇧-click is aimed at a layer. Missing it by a few pixels must not
        // throw away the selection it was about to be added to.
        let press = BareCanvasPress(shift: true)
        #expect(press == .spares)
        #expect(!press.clearsSelectionOnPress)
    }

    @Test func plainClickOnNothingDeselects() {
        #expect(BareCanvasPress(shift: false).commitsOnRelease(isClick: true))
    }

    @Test func shiftClickOnNothingChangesNothing() {
        #expect(!BareCanvasPress(shift: true).commitsOnRelease(isClick: true))
    }

    @Test func aSweepAlwaysDecidesTheSelection() {
        // Only the click that never moved is spared: a rubber band that was
        // actually dragged still says what is picked, ⇧ or not.
        #expect(BareCanvasPress(shift: false).commitsOnRelease(isClick: false))
        #expect(BareCanvasPress(shift: true).commitsOnRelease(isClick: false))
    }

    // MARK: What a finished sweep leaves picked

    let a = UUID(), b = UUID(), c = UUID()

    @Test func aPlainSweepReplacesWhateverWasPicked() {
        let press = BareCanvasPress(shift: false)
        #expect(!press.sweepAddsToSelection)
        #expect(press.selection(afterSweeping: [b, c], startingFrom: [a]) == [b, c])
    }

    @Test func aShiftSweepAddsWhatItTookInToWhatWasPicked() {
        let press = BareCanvasPress(shift: true)
        #expect(press.sweepAddsToSelection)
        #expect(press.selection(afterSweeping: [b, c], startingFrom: [a]) == [a, b, c])
    }

    @Test func aShiftSweepThatCatchesNothingChangesNothing() {
        // Sweeping empty canvas with ⇧ is a miss, and a miss costs nothing.
        #expect(BareCanvasPress(shift: true).selection(afterSweeping: [], startingFrom: [a, b])
                == [a, b])
    }

    @Test func aPlainSweepThatCatchesNothingPicksNothing() {
        #expect(BareCanvasPress(shift: false).selection(afterSweeping: [], startingFrom: [a, b])
                == [])
    }

    @Test func sweepingSomethingAlreadyPickedLeavesItPicked() {
        // Adding is adding, not toggling: sweeping back over a layer you
        // already have must not drop it out from under you.
        #expect(BareCanvasPress(shift: true).selection(afterSweeping: [a, b], startingFrom: [a])
                == [a, b])
    }

    @Test func aShiftSweepBuildsUpOverThreeSweeps() {
        let press = BareCanvasPress(shift: true)
        var picked = press.selection(afterSweeping: [a], startingFrom: [])
        picked = press.selection(afterSweeping: [b], startingFrom: picked)
        picked = press.selection(afterSweeping: [c], startingFrom: picked)
        #expect(picked == [a, b, c])
    }
}
