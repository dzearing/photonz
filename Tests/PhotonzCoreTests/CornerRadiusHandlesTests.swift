import CoreGraphics
import PhotonzCore
import Testing

/// The four dots just inside a shape's corners: where they sit, what they
/// answer to a press, and what a pull on one of them asks for.
@Suite("Dragging a corner to round it")
struct CornerRadiusHandlesTests {
    /// A comfortable box, well clear of every cramped rule.
    let box = CGRect(x: 100, y: 100, width: 200, height: 120)

    // MARK: Where they sit

    @Test func aSquareCornerRestsAFixedDistanceInFromIt() {
        let p = CornerRadiusHandles.point(for: .topLeft, in: box, radii: .none, zoom: 1)
        let rest = CornerRadiusHandles.restInset
        #expect(p == CGPoint(x: box.minX + rest, y: box.minY + rest))
    }

    @Test func theRestingDistanceIsMeasuredOnScreenSoZoomDoesNotMoveIt() {
        let far = CornerRadiusHandles.point(for: .topLeft, in: box, radii: .none, zoom: 0.5)
        // Half the zoom, twice as far in document units: the same gap on screen.
        #expect(far.x == box.minX + CornerRadiusHandles.restInset * 2)
        #expect(far.y == box.minY + CornerRadiusHandles.restInset * 2)
    }

    @Test func aRoundedCornerPutsItsHandleWhereTheCurveIs() {
        let p = CornerRadiusHandles.point(for: .bottomRight, in: box, radii: CornerRadii(40),
                                          zoom: 1)
        #expect(p == CGPoint(x: box.maxX - 40, y: box.maxY - 40))
    }

    @Test func everyCornerAnswersItsOwnSideOfTheBox() {
        let radii = CornerRadii(topLeft: 20, topRight: 30, bottomRight: 40, bottomLeft: 50)
        let points = CornerRadii.Corner.allCases.map {
            CornerRadiusHandles.point(for: $0, in: box, radii: radii, zoom: 1)
        }
        #expect(points[0] == CGPoint(x: 120, y: 120))
        #expect(points[1] == CGPoint(x: 270, y: 130))
        #expect(points[2] == CGPoint(x: 260, y: 180))
        #expect(points[3] == CGPoint(x: 150, y: 170))
    }

    @Test func aCornerRoundedPastWhatFitsSitsWhereItActuallyDraws() {
        // 200 on a 120 tall box cannot be drawn; the shape is fully round, and
        // the handle has to sit on the curve rather than off in the middle.
        let p = CornerRadiusHandles.point(for: .topLeft, in: box, radii: CornerRadii(200), zoom: 1)
        #expect(p == CGPoint(x: box.minX + 60, y: box.minY + 60))
    }

    // MARK: Which shapes get them

    @Test func aRoomyShapeOffersThem() {
        #expect(CornerRadiusHandles.offered(in: box, zoom: 1))
    }

    @Test func aShapeTooSmallForItsEdgeHandlesIsTooSmallForTheseToo() {
        let tiny = CGRect(x: 0, y: 0, width: 30, height: 200)
        #expect(!CornerRadiusHandles.offered(in: tiny, zoom: 1))
        #expect(Handles.layout(in: tiny, zoom: 1).handles == ResizeHandle.allCases.filter(\.isCorner))
    }

    @Test func zoomingInGivesASmallShapeItsHandlesBack() {
        let small = CGRect(x: 0, y: 0, width: 30, height: 30)
        #expect(!CornerRadiusHandles.offered(in: small, zoom: 1))
        #expect(CornerRadiusHandles.offered(in: small, zoom: 4))
    }

    // MARK: What a press finds

    @Test func aPressOnADotFindsItsCorner() {
        for corner in CornerRadii.Corner.allCases {
            let p = CornerRadiusHandles.point(for: corner, in: box, radii: .none, zoom: 1)
            #expect(CornerRadiusHandles.hit(at: p, frame: box, radii: .none, zoom: 1) == corner,
                    "\(corner)")
        }
    }

    @Test func aPressInTheMiddleOfTheShapeFindsNothing() {
        let middle = CGPoint(x: box.midX, y: box.midY)
        #expect(CornerRadiusHandles.hit(at: middle, frame: box, radii: .none, zoom: 1) == nil)
    }

    @Test func aPressOnTheCornerItselfBelongsToTheResizeHandleNotToThis() {
        // The two must never both answer, or a resize would become a rounding.
        let corner = CGPoint(x: box.minX, y: box.minY)
        #expect(CornerRadiusHandles.hit(at: corner, frame: box, radii: .none, zoom: 1) == nil)
        #expect(Handles.hit(at: corner, frame: box, zoom: 1) == .topLeft)
    }

    @Test func neitherHandleReachesIntoTheOthersTarget() {
        // The gap between the two, on screen, is wider than both tolerances.
        let dot = CornerRadiusHandles.point(for: .topLeft, in: box, radii: .none, zoom: 1)
        let square = Handles.point(for: .topLeft, in: box)
        let gap = hypot(dot.x - square.x, dot.y - square.y)
        #expect(gap > CornerRadiusHandles.tolerance + 6)
        #expect(Handles.hit(at: dot, frame: box, zoom: 1) == nil)
    }

    @Test func aShapeThatOffersNoHandlesAnswersNoPress() {
        let tiny = CGRect(x: 0, y: 0, width: 20, height: 20)
        let p = CornerRadiusHandles.point(for: .topLeft, in: tiny, radii: .none, zoom: 1)
        #expect(CornerRadiusHandles.hit(at: p, frame: tiny, radii: .none, zoom: 1) == nil)
    }

    // MARK: What a pull asks for

    @Test func pullingInwardsAlongTheDiagonalIsTheRadius() {
        let r = CornerRadiusHandles.radius(draggingTo: CGPoint(x: box.minX + 30,
                                                               y: box.minY + 30),
                                           corner: .topLeft, in: box)
        #expect(r == 30)
    }

    @Test func aPullOffTheDiagonalAveragesTheTwoSidesSoItStillFollowsTheHand() {
        let r = CornerRadiusHandles.radius(draggingTo: CGPoint(x: box.minX + 40,
                                                               y: box.minY + 20),
                                           corner: .topLeft, in: box)
        #expect(r == 30)
    }

    @Test func everyCornerPullsInwardsFromItsOwnSide() {
        let r = CornerRadiusHandles.radius(draggingTo: CGPoint(x: box.maxX - 25,
                                                               y: box.maxY - 25),
                                           corner: .bottomRight, in: box)
        #expect(r == 25)
    }

    @Test func pullingBackOutPastTheCornerSquaresItRatherThanGoingNegative() {
        let r = CornerRadiusHandles.radius(draggingTo: CGPoint(x: box.minX - 80,
                                                               y: box.minY - 80),
                                           corner: .topLeft, in: box)
        #expect(r == 0)
    }

    @Test func pullingPastFullyRoundStopsAtFullyRound() {
        let r = CornerRadiusHandles.radius(draggingTo: CGPoint(x: box.midX, y: box.midY),
                                           corner: .topLeft, in: box)
        #expect(r == 60)  // half the short edge
    }

    @Test func theRadiusComesBackInWholePointsBecauseThatIsWhatThePanelShows() {
        let r = CornerRadiusHandles.radius(draggingTo: CGPoint(x: box.minX + 30.4,
                                                               y: box.minY + 30.4),
                                           corner: .topLeft, in: box)
        #expect(r == 30)
    }

    // MARK: The whole gesture

    @Test func aPullOnOneHandleLeavesTheOtherThreeAlone() {
        let start = CornerRadii(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        let after = CornerRadiusHandles.radii(start, corner: .topRight, to: 24, allCorners: false)
        #expect(after == CornerRadii(topLeft: 8, topRight: 24, bottomRight: 8, bottomLeft: 8))
    }

    @Test func holdingTheModifierTakesAllFourTogether() {
        let start = CornerRadii(topLeft: 8, topRight: 2, bottomRight: 0, bottomLeft: 40)
        let after = CornerRadiusHandles.radii(start, corner: .topRight, to: 24, allCorners: true)
        #expect(after == CornerRadii(24))
    }

    // MARK: Which layers wear them at all

    private func layer(_ content: LayerContent, locked: Bool = false) -> Layer {
        var made = Layer(name: "Thing", content: content,
                         frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        made.isLocked = locked
        return made
    }

    @Test func aRectangleWearsThem() {
        let rect = AnnotationContent(shape: .rectangle, start: .zero,
                                     end: CGPoint(x: 200, y: 120), fillColorHex: "#FF0000")
        #expect(layer(.annotation(rect)).offersCornerRadiusHandles)
    }

    @Test func aShapeWithNoCornersDoesNot() {
        let ellipse = AnnotationContent(shape: .ellipse, start: .zero,
                                        end: CGPoint(x: 200, y: 120), fillColorHex: "#FF0000")
        #expect(!layer(.annotation(ellipse)).offersCornerRadiusHandles)
    }

    @Test func aLockedShapeOffersNothing() {
        let rect = AnnotationContent(shape: .rectangle, start: .zero,
                                     end: CGPoint(x: 200, y: 120), fillColorHex: "#FF0000")
        #expect(!layer(.annotation(rect), locked: true).offersCornerRadiusHandles)
    }

    @Test func aPictureRoundsFromThePanelRatherThanWearingFourMoreDots() {
        #expect(!layer(.text(TextContent(string: "Hi"))).offersCornerRadiusHandles)
    }

    // MARK: A shape rounded from the canvas is the shape the panel reads

    @Test func theLayerFollowsTheDragBeforeItIsCommitted() {
        let annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 200, y: 120),
                                           cornerRadii: CornerRadii(4), fillColorHex: "#FF0000")
        let shape = Layer(name: "Box", content: .annotation(annotation),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let rounded = shape.rounded(CornerRadii(topLeft: 30, topRight: 4,
                                                bottomRight: 4, bottomLeft: 4))
        #expect(rounded.roundedCornerRadii.topLeft == 30)
        // The original is untouched: this is a picture of the drag, not the drag.
        #expect(shape.roundedCornerRadii == CornerRadii(4))
    }
}
