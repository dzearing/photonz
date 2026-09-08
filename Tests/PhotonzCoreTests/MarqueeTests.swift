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

    @Test func aPlainSweepThatCatchesNothingLeavesWhatWasPickedAlone() {
        // A band takes over the selection only when it CATCHES something.
        // Thrown round empty canvas it has said WHERE, not WHAT: the layer you
        // were working on stays picked, so ⌫, fill and copy still have it to
        // act on. Picking a layer and then drawing a box used to deselect it
        // and leave the obvious next keystroke with nothing to do
        // (reported 2026-09-07).
        #expect(BareCanvasPress(shift: false).selection(afterSweeping: [], startingFrom: [a, b])
                == [a, b])
    }

    @Test func aBandDecidesTheSelectionOnlyWhenItCatchesSomething() {
        #expect(!BareCanvasPress.sweepDecidesSelection(caught: []))
        #expect(BareCanvasPress.sweepDecidesSelection(caught: [a]))
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

@Suite("MarqueeIntent")
struct MarqueeIntentTests {
    let a = UUID(), b = UUID()

    // MARK: Mid-sweep

    @Test func aBandThatHasCaughtSomethingPicksLayers() {
        #expect(MarqueeIntent.sweeping(caught: [a]) == .picksLayers)
        #expect(MarqueeIntent.sweeping(caught: [a, b]) == .picksLayers)
    }

    @Test func aBandThatHasCaughtNothingPicksPixels() {
        // The band out over empty canvas has said WHERE and not WHAT, so it is
        // on its way to becoming a piece of the picture.
        #expect(MarqueeIntent.sweeping(caught: []) == .picksPixels)
    }

    @Test func theLookFollowsTheSameRuleTheSelectionDoes() {
        // The whole point: what the band looks like and what letting go of it
        // does are decided by one call, so they can never disagree.
        for caught in [[], [a], [a, b]] {
            #expect((MarqueeIntent.sweeping(caught: caught) == .picksLayers)
                    == BareCanvasPress.sweepDecidesSelection(caught: caught))
        }
    }

    @Test func shiftDoesNotChangeWhatTheBandIs() {
        // ⇧ decides whether the catch joins what was already picked, not
        // whether the band is picking layers at all.
        #expect(MarqueeIntent.sweeping(caught: []) == .picksPixels)
        #expect(MarqueeIntent.sweeping(caught: [b]) == .picksLayers)
    }

    // MARK: At rest

    @Test func aLandedBandKeepsTheLookItHadWhileItWasDrawn() {
        #expect(MarqueeIntent.resting(targetsPixels: false) == .picksLayers)
        #expect(MarqueeIntent.resting(targetsPixels: true) == .picksPixels)
    }

    // MARK: What each look is

    @Test func onlyThePixelBandMarches() {
        // Crawling ants are the picture-editing idiom, so the band that is not
        // choosing pixels must not wear them.
        #expect(MarqueeIntent.picksPixels.marches)
        #expect(!MarqueeIntent.picksLayers.marches)
    }

    @Test func onlyTheLayerBandIsFilledAndOnlyWhileYouDrawIt() {
        // The wash inside the band is the part you see without looking.
        #expect(MarqueeIntent.picksLayers.isFilled(whileDrawing: true))
        #expect(!MarqueeIntent.picksPixels.isFilled(whileDrawing: true))
    }

    @Test func theWashComesOffWhenYouLetGo() {
        // A wash left up would be a blue film over the picture until the next
        // click. The band that landed says what it is with its line instead.
        #expect(!MarqueeIntent.picksLayers.isFilled(whileDrawing: false))
        #expect(!MarqueeIntent.picksPixels.isFilled(whileDrawing: false))
    }

    @Test func theTwoLooksNeverAgreeOnAnything() {
        // Two bands that differed in only one small way would be two bands you
        // have to compare. Mid-sweep these differ in fill, in dash and in
        // motion; once landed the dash and the motion carry it on alone.
        #expect(MarqueeIntent.picksLayers.marches != MarqueeIntent.picksPixels.marches)
        #expect(MarqueeIntent.picksLayers.isFilled(whileDrawing: true)
                != MarqueeIntent.picksPixels.isFilled(whileDrawing: true))
        #expect(MarqueeIntent.picksLayers.isDashed != MarqueeIntent.picksPixels.isDashed)
    }
}
