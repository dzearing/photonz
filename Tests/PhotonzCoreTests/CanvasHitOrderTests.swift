import CoreGraphics
import PhotonzCore
import Testing

/// One order for what a press over overlapping canvas chrome takes hold of.
///
/// The rule under test is the whole of it: among the marks drawn round and on
/// a picked layer, the NEAREST drawn mark takes the press, and a mark drawn on
/// the picture wins a tie against the box round it. See
/// `docs/design/canvas-hit-order.md`.
@Suite("What a press over overlapping canvas chrome takes")
struct CanvasHitOrderTests {
    /// A comfortable box, well clear of every cramped rule, at zoom 1 so a
    /// screen point and a document point are the same length.
    let box = CGRect(x: 100, y: 100, width: 200, height: 120)

    // MARK: How near the box is

    @Test func aPressNowhereNearTheBoxIsTakenByNothingOnIt() {
        #expect(CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 160, y: 160), frame: box,
                                               zoom: 1) == nil)
    }

    @Test func aPressOnACornerSquareIsTakenByIt() {
        let d = CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 100, y: 100), frame: box, zoom: 1)
        #expect(d == 0)
    }

    @Test func aPressJustPastACornerSquaresSlackIsTakenByNothing() {
        // Handles carry six screen points of slack; seven away is a miss.
        #expect(CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 93, y: 100), frame: box,
                                               zoom: 1) == nil)
    }

    @Test func theTurnKnobCountsAsSomethingTheBoxDraws() {
        let knob = CGPoint(x: 200, y: 82)
        let d = CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 200, y: 84), frame: box,
                                               zoom: 1, knob: knob)
        #expect(d == 2)
    }

    @Test func aRoundingDotCountsOnceTheShapeOffersThem() {
        // The top-left dot of a square-cornered box rests twelve points in.
        let dot = CGPoint(x: 112, y: 112)
        let bare = CanvasHitOrder.boxGrabDistance(at: dot, frame: box, zoom: 1)
        let rounded = CanvasHitOrder.boxGrabDistance(at: dot, frame: box, zoom: 1,
                                                    roundingDots: true)
        #expect(bare == nil)
        #expect(rounded == 0)
    }

    @Test func anEdgeCountsOnlyWhereTheEdgeItselfIsAGrab() {
        let onTheEdge = CGPoint(x: 200, y: 100)
        let square = CanvasHitOrder.boxGrabDistance(at: onTheEdge, frame: box, zoom: 1)
        // The top edge midpoint square is right there either way, so aim off it.
        let offTheMidpoint = CGPoint(x: 150, y: 100)
        #expect(square == 0)
        #expect(CanvasHitOrder.boxGrabDistance(at: offTheMidpoint, frame: box, zoom: 1) == nil)
        #expect(CanvasHitOrder.boxGrabDistance(at: offTheMidpoint, frame: box, zoom: 1,
                                               edgeGrab: true) == 0)
    }

    @Test func aBoxWithNoLiveFrameDrawsNothingToTakeAPress() {
        #expect(CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 100, y: 100), frame: nil,
                                               zoom: 1) == nil)
    }

    @Test func slackIsMeasuredOnScreenSoZoomDoesNotChangeTheAnswer() {
        // Five document points out at half zoom is two and a half on screen:
        // well within a handle's six.
        let d = CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 105, y: 100), frame: box, zoom: 0.5)
        #expect(d == 5)
        // The same five points at double zoom is ten on screen, which is a miss.
        #expect(CanvasHitOrder.boxGrabDistance(at: CGPoint(x: 105, y: 100), frame: box,
                                               zoom: 2) == nil)
    }

    // MARK: Which of two overlapping marks wins

    @Test func aMarkWithNothingNearItTakesThePress() {
        #expect(CanvasHitOrder.markTakesPress(at: CGPoint(x: 160, y: 160),
                                              mark: CGPoint(x: 160, y: 160),
                                              frame: box, zoom: 1))
    }

    @Test func aMarkParkedOnACornerTakesThePressAimedAtIt() {
        // The whole bug: a pivot parked on the corner used to be unreachable,
        // because the corner square answered first however near the crosshair
        // was drawn.
        #expect(CanvasHitOrder.markTakesPress(at: CGPoint(x: 100, y: 100),
                                              mark: CGPoint(x: 100, y: 100),
                                              frame: box, zoom: 1))
    }

    @Test func theCornerKeepsAPressAimedAtTheCorner() {
        // The crosshair is eight points inside the corner; the press is on the
        // corner square itself, which is nearer, so the resize still happens.
        #expect(!CanvasHitOrder.markTakesPress(at: CGPoint(x: 100, y: 100),
                                               mark: CGPoint(x: 108, y: 108),
                                               frame: box, zoom: 1))
    }

    @Test func theMarkKeepsAPressAimedAtTheMark() {
        // The same pair, with the press on the crosshair instead.
        #expect(CanvasHitOrder.markTakesPress(at: CGPoint(x: 108, y: 108),
                                              mark: CGPoint(x: 108, y: 108),
                                              frame: box, zoom: 1))
    }

    @Test func aMarkWinsAPressTheBoxWouldHaveRefusedAnyway() {
        // Nine points off the corner is past a handle's slack, so nothing on
        // the box would have taken this press: the mark keeps it even though
        // the corner is the nearer of the two.
        #expect(CanvasHitOrder.markTakesPress(at: CGPoint(x: 109, y: 100),
                                              mark: CGPoint(x: 120, y: 100),
                                              frame: box, zoom: 1))
    }

    @Test func theTurnKnobKeepsThePressWhenTheMarkSitsBelowIt() {
        // A pivot dragged to just above the top edge is the case this feature
        // exists for, and the turn knob floats eighteen points out from the
        // same edge. Aim at the knob and the knob answers.
        let knob = CGPoint(x: 200, y: 82)
        #expect(!CanvasHitOrder.markTakesPress(at: knob, mark: CGPoint(x: 200, y: 92),
                                               frame: box, zoom: 1, knob: knob))
        // Aim at the crosshair ten points below it and the crosshair answers.
        #expect(CanvasHitOrder.markTakesPress(at: CGPoint(x: 200, y: 92),
                                              mark: CGPoint(x: 200, y: 92),
                                              frame: box, zoom: 1, knob: knob))
    }

    @Test func aMarkOnAnEdgeWinsATieWithTheEdge() {
        #expect(CanvasHitOrder.markTakesPress(at: CGPoint(x: 150, y: 100),
                                              mark: CGPoint(x: 150, y: 100),
                                              frame: box, zoom: 1, edgeGrab: true))
    }

    @Test func anEdgeKeepsAPressAimedAtTheEdgeRatherThanAtTheMark() {
        // The crosshair is four points inside the top edge; the press is on
        // the edge itself.
        #expect(!CanvasHitOrder.markTakesPress(at: CGPoint(x: 150, y: 100),
                                               mark: CGPoint(x: 150, y: 104),
                                               frame: box, zoom: 1, edgeGrab: true))
    }
}
