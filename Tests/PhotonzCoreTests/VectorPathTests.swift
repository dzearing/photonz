import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A path is a shape made of as many anchors as you like, each a corner or a
/// smooth bend, open or closed (`docs/design/vector-paths.md`).
@Suite("A path shape")
struct VectorPathTests {

    // A square with one side bowed out: two straight runs, one curve. The
    // shape every test here reasons about, because it is the smallest thing
    // that proves straight and curved live in one outline.
    static func bowedSquare() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            // The right-hand side bows out: this anchor leaves curving and the
            // next one arrives curving.
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 30)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 40, y: -30)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
    }

    // MARK: The model

    @Test func anAnchorWithNoHandlesIsACorner() {
        let anchor = PathAnchor(point: CGPoint(x: 10, y: 10))
        #expect(anchor.kind == .corner)
        #expect(anchor.handleIn == nil)
        #expect(anchor.handleOut == nil)
    }

    @Test func aPathCanHoldAsManyAnchorsAsYouLike() {
        let many = (0..<64).map { PathAnchor(point: CGPoint(x: $0 * 3, y: $0 % 7)) }
        #expect(PathContent(anchors: many).anchors.count == 64)
    }

    @Test func aPathIsOpenUntilItIsClosed() {
        var path = PathContent(anchors: Self.bowedSquare().anchors)
        #expect(!path.isClosed)
        path.isClosed = true
        #expect(path.isClosed)
    }

    /// The case the notes single out as the one a weaker model cannot say: an
    /// anchor curved on one side and straight on the other.
    @Test func anAnchorCanBeCurvedOnOneSideAndStraightOnTheOther() {
        let half = PathAnchor(point: .zero, handleOut: CGPoint(x: 20, y: 0))
        #expect(half.handleIn == nil, "arrives straight")
        #expect(half.handleOut != nil, "leaves curving")
        #expect(half.isHalfSmooth)
    }

    /// Smooth is a CONSTRAINT the editor keeps, and the model can state it and
    /// enforce it on demand.
    @Test func smoothingAnAnchorPutsItsHandlesInLine() {
        var anchor = PathAnchor(point: CGPoint(x: 50, y: 50),
                                handleIn: CGPoint(x: -20, y: 0),
                                handleOut: CGPoint(x: 9, y: 12),
                                kind: .smooth)
        anchor.alignHandles(keeping: .handleIn)
        let out = anchor.handleOut!
        // Opposite direction, its own length (15) kept.
        #expect(abs(out.x - 15) < 0.001 && abs(out.y) < 0.001, "got \(out)")
        #expect(anchor.handleIn == CGPoint(x: -20, y: 0), "the side you dragged is untouched")
    }

    @Test func makingAnAnchorACornerLeavesItsHandlesAlone() {
        var anchor = PathAnchor(point: .zero, handleIn: CGPoint(x: -10, y: -10),
                                handleOut: CGPoint(x: 3, y: 40), kind: .corner)
        anchor.alignHandles(keeping: .handleIn)
        #expect(anchor.handleOut == CGPoint(x: 3, y: 40))
    }

    // MARK: Segments

    @Test func aRunWithNoHandlesOnEitherEndIsStraight() {
        let path = Self.bowedSquare()
        let segments = path.segments
        #expect(segments.count == 4, "a closed four-anchor path has four runs")
        #expect(segments[0].isStraight, "top edge")
        #expect(!segments[1].isStraight, "the bowed right-hand side")
        #expect(segments[2].isStraight, "bottom edge")
        #expect(segments[3].isStraight, "the closing run back up the left")
    }

    @Test func anOpenPathHasOneFewerRunThanItHasAnchors() {
        var path = Self.bowedSquare()
        path.isClosed = false
        #expect(path.segments.count == 3)
    }

    @Test func aPathOfOneAnchorHasNoRuns() {
        #expect(PathContent(anchors: [PathAnchor(point: .zero)]).segments.isEmpty)
    }

    /// Handles are stored RELATIVE to their anchor, so a segment's control
    /// points are the anchor plus the handle.
    @Test func handlesAreOffsetsFromTheirAnchor() {
        let segment = Self.bowedSquare().segments[1]
        #expect(segment.start == CGPoint(x: 100, y: 0))
        #expect(segment.control1 == CGPoint(x: 140, y: 30))
        #expect(segment.control2 == CGPoint(x: 140, y: 70))
        #expect(segment.end == CGPoint(x: 100, y: 100))
    }

    // MARK: Bounds

    @Test func boundsCoverHowFarTheCurveActuallyBulges() {
        let box = Self.bowedSquare().bounds
        #expect(box.minX == 0)
        #expect(box.minY == 0)
        #expect(box.maxY == 100)
        // The bulge reaches 3/4 of the way out along a handle of 40, which is
        // 130, NOT the 140 the control point sits at.
        #expect(abs(box.maxX - 130) < 0.01, "got \(box.maxX)")
    }

    @Test func boundsOfAStraightShapeAreTheBoxThroughItsAnchors() {
        let triangle = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 60, y: 80)),
            PathAnchor(point: CGPoint(x: -20, y: 40))
        ], isClosed: true)
        #expect(triangle.bounds == CGRect(x: -20, y: 0, width: 80, height: 80))
    }

    @Test func anEmptyPathHasNoBounds() {
        #expect(PathContent(anchors: []).bounds == .zero)
    }

    // MARK: On disk

    @Test func aPathSurvivesASaveAndAReloadExactly() throws {
        var path = Self.bowedSquare()
        path.fill = Paint(hex: "#3366FF")
        path.paint = Paint(hex: "#101010")
        path.strokeWidth = 6
        path.anchors[1].kind = .smooth
        let data = try JSONEncoder().encode(path)
        let back = try JSONDecoder().decode(PathContent.self, from: data)
        #expect(back == path)
        #expect(back.anchors[1].handleOut == CGPoint(x: 40, y: 30), "handle positions survive")
        #expect(back.anchors[1].kind == .smooth)
    }

    @Test func aPathLayerSurvivesASaveAndAReloadExactly() throws {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 20, y: 30))
        let data = try JSONEncoder().encode(layer)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.path == layer.path)
        #expect(back.frame == layer.frame)
    }

    // MARK: A layer made of one

    @Test func aPathLayerIsBoxedRoundTheShapeItActuallyCovers() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 20, y: 30))
        // 130 wide because of the bulge, not the 100 through the anchors.
        #expect(abs(layer.frame.width - 130) < 0.01)
        #expect(abs(layer.frame.height - 100) < 0.01)
        #expect(layer.frame.origin == CGPoint(x: 20, y: 30))
        // ...and the anchors are re-stated against that box's own corner.
        #expect(layer.path?.bounds.origin == .zero)
    }

    @Test func theSelectionBoxCoversTheOutlineAsWellAsTheShape() {
        var content = Self.bowedSquare()
        content.strokeWidth = 10
        content.strokePosition = .center
        let layer = PathBuilder.layer(content, at: CGPoint(x: 20, y: 30))
        let drawn = layer.drawnBounds()
        // A centred 10pt line reaches 5 past the shape on every side.
        #expect(abs(drawn.minX - 15) < 0.01, "got \(drawn.minX)")
        #expect(abs(drawn.minY - 25) < 0.01)
        #expect(abs(drawn.width - 140) < 0.01)
        #expect(abs(drawn.height - 110) < 0.01)
    }

    @Test func anInsideOutlineStaysWithinTheShapesOwnBox() {
        var content = Self.bowedSquare()
        content.strokeWidth = 10
        content.strokePosition = .inside
        let layer = PathBuilder.layer(content, at: .zero)
        #expect(layer.contentOutset == 0)
        #expect(layer.drawnBounds() == layer.frame)
    }

    @Test func aPathLayerNamesItselfPath() {
        #expect(PathBuilder.layer(Self.bowedSquare(), at: .zero).name == "Path")
    }

    // MARK: Moving and resizing

    @Test func resizingScalesTheCurvesWithTheBox() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: CGPoint(x: 20, y: 30))
        let wider = layer.resized(to: CGRect(x: 20, y: 30,
                                             width: layer.frame.width * 2,
                                             height: layer.frame.height * 3))
        let path = wider.path!
        #expect(path.anchors[1].point == CGPoint(x: 200, y: 0))
        #expect(path.anchors[1].handleOut == CGPoint(x: 80, y: 90), "the handle scales too")
        // The shape still fills its new box exactly.
        #expect(abs(path.bounds.width - wider.frame.width) < 0.01)
        #expect(abs(path.bounds.height - wider.frame.height) < 0.01)
    }

    @Test func resizingKeepsTheLineWidthInPoints() {
        var content = Self.bowedSquare()
        content.strokeWidth = 4
        let layer = PathBuilder.layer(content, at: .zero)
        let bigger = layer.resized(to: CGRect(x: 0, y: 0, width: 520, height: 400))
        #expect(bigger.path?.strokeWidth == 4)
    }

    @Test func movingAPathLeavesItsAnchorsAlone() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        var moved = layer
        moved.frame = layer.frame.offsetBy(dx: 140, dy: -12)
        #expect(moved.path == layer.path)
    }

    @Test func aPathTakesTheEightResizeHandlesLikeAnyOtherShape() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        #expect(layer.allowsFrameResize)
        #expect(!layer.hasEndpointHandles)
        #expect(!layer.resizeWidthOnly)
    }

    // MARK: Colour, through the machinery every other shape uses

    @Test func aClosedPathOffersAFillAndAnOutline() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        #expect(layer.colorSlots.contains(.fill))
        #expect(layer.colorSlots.contains(.stroke))
    }

    @Test func anOpenPathOffersNoFill() {
        var content = Self.bowedSquare()
        content.isClosed = false
        let layer = PathBuilder.layer(content, at: .zero)
        #expect(!layer.colorSlots.contains(.fill))
        #expect(layer.colorSlots.contains(.stroke))
    }

    @Test func aPathArrivesWithAFillAndAnOutlineAlready() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        #expect(layer.path?.fill != nil, "a closed path arrives painted")
        #expect((layer.path?.strokeWidth ?? 0) > 0, "and with a line round it")
    }

    @Test func paintingAPathAColourGoesThroughTheUsualSlots() {
        var layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        layer.setPaint(Paint(hex: "#FF0000"), for: .stroke)
        layer.setPaint(Paint(hex: "#00FF00"), for: .fill)
        #expect(layer.colorHex(for: .stroke) == "#FF0000")
        #expect(layer.colorHex(for: .fill) == "#00FF00")
    }

    @Test func aPathTakesAGradientInEitherSlot() {
        var layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        var ramp = Paint(hex: "#FF0000")
        ramp.becoming(.linear)
        layer.setPaint(ramp, for: .fill)
        #expect(layer.paint(for: .fill)?.isGradient == true)
        layer.setPaint(ramp, for: .stroke)
        #expect(layer.paint(for: .stroke)?.isGradient == true)
    }

    /// The edge of a path is the path's OWN stroke, not a Border laid round
    /// its box, so nothing moves it into the Effects list on the way in.
    @Test func aPathKeepsItsOwnOutlineRatherThanGainingABorder() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        #expect(layer.style.effects.isEmpty)
        #expect((layer.path?.strokeWidth ?? 0) > 0)
    }

    @Test func duplicatingAPathCopiesEveryAnchor() {
        let layer = PathBuilder.layer(Self.bowedSquare(), at: .zero)
        let copy = layer.duplicated(offsetBy: CGPoint(x: 8, y: 8))
        #expect(copy.path == layer.path)
        #expect(copy.id != layer.id)
    }
}

/// Clicking a path picks it where the SHAPE is, not where its box is.
@Suite("Clicking a path")
struct VectorPathHitTests {

    private func triangle() -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 60, y: 0)),
            PathAnchor(point: CGPoint(x: 120, y: 100)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
        path.strokeWidth = 0
        return path
    }

    private func squiggle() -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 80), handleOut: CGPoint(x: 30, y: -50)),
            PathAnchor(point: CGPoint(x: 120, y: 80), handleIn: CGPoint(x: -30, y: -50))
        ])
        path.fill = nil
        path.strokeWidth = 8
        return path
    }

    @Test func aFilledPathTakesAClickInsideIt() {
        let layer = PathBuilder.layer(triangle(), at: CGPoint(x: 100, y: 100))
        #expect(layer.contains(canvasPoint: CGPoint(x: 160, y: 180)))
    }

    @Test func aFilledPathIgnoresAClickInTheCornerOfItsBox() {
        let layer = PathBuilder.layer(triangle(), at: CGPoint(x: 100, y: 100))
        // Top-left of the box, well outside the triangle.
        #expect(!layer.contains(canvasPoint: CGPoint(x: 104, y: 104)))
    }

    @Test func anOpenPathIsOnlyHitNearItsLine() {
        let layer = PathBuilder.layer(squiggle(), at: CGPoint(x: 100, y: 100))
        let box = layer.frame
        // The curve's peak is at the top edge of the box, halfway across.
        #expect(layer.contains(canvasPoint: CGPoint(x: box.midX, y: box.minY + 2)))
        // ...and the bottom corner of the box is empty air.
        #expect(!layer.contains(canvasPoint: CGPoint(x: box.minX + 40, y: box.maxY - 2)))
    }

    @Test func aHollowPathIsHitOnItsLineRatherThanInItsMiddle() {
        var path = triangle()
        path.fill = nil
        path.strokeWidth = 6
        let layer = PathBuilder.layer(path, at: .zero)
        #expect(layer.contains(canvasPoint: CGPoint(x: 60, y: 98)), "on the bottom edge")
        #expect(!layer.contains(canvasPoint: CGPoint(x: 60, y: 60)), "the hollow middle is not the shape")
    }

    @Test func aThinLineIsStillEasyToHit() {
        var path = squiggle()
        path.strokeWidth = 1
        let layer = PathBuilder.layer(path, at: .zero)
        // Four points off the line still lands, the same slop a thin arrow gets.
        #expect(layer.contains(canvasPoint: CGPoint(x: layer.frame.midX,
                                                    y: layer.frame.minY + 4)))
    }

    @Test func aPathIsHitThroughItsOwnTurn() {
        let upright = PathBuilder.layer(triangle(), at: CGPoint(x: 100, y: 100))
        var turned = upright
        turned.transform.rotation = .pi / 2
        let centre = CGPoint(x: upright.frame.midX, y: upright.frame.midY)
        // The apex points UP to start with and RIGHT after a quarter turn, so
        // the two points swap which of them is on the shape.
        let above = CGPoint(x: centre.x, y: centre.y - 40)
        let beside = CGPoint(x: centre.x + 40, y: centre.y)
        #expect(upright.contains(canvasPoint: above))
        #expect(!upright.contains(canvasPoint: beside))
        #expect(!turned.contains(canvasPoint: above))
        #expect(turned.contains(canvasPoint: beside))
    }

    // MARK: Whether an outline has an inside

    @Test func aSquareEnclosesItsOwnArea() {
        let square = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 10, y: 0)),
            PathAnchor(point: CGPoint(x: 10, y: 10)),
            PathAnchor(point: CGPoint(x: 0, y: 10))
        ], isClosed: true)
        #expect(abs(square.enclosedArea.magnitude - 100) < 1e-9)
        #expect(square.enclosesAnArea)
    }

    @Test func aCircleDrawnWithFourAnchorsEnclosesAboutPiRSquared() {
        // The usual four-anchor circle: handles 0.5523 of the radius long.
        // It is a hair under a true circle, which is exactly what the number
        // has to show for the maths to be the real integral rather than the
        // box round the control points.
        let r: CGFloat = 50
        let k = r * 0.552284749831
        let circle = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: -r), handleIn: CGPoint(x: -k, y: 0),
                       handleOut: CGPoint(x: k, y: 0), kind: .smooth),
            PathAnchor(point: CGPoint(x: r, y: 0), handleIn: CGPoint(x: 0, y: -k),
                       handleOut: CGPoint(x: 0, y: k), kind: .smooth),
            PathAnchor(point: CGPoint(x: 0, y: r), handleIn: CGPoint(x: k, y: 0),
                       handleOut: CGPoint(x: -k, y: 0), kind: .smooth),
            PathAnchor(point: CGPoint(x: -r, y: 0), handleIn: CGPoint(x: 0, y: k),
                       handleOut: CGPoint(x: 0, y: -k), kind: .smooth)
        ], isClosed: true)
        let exact = CGFloat.pi * r * r
        #expect(abs(circle.enclosedArea.magnitude - exact) / exact < 0.001)
    }

    @Test func anOpenPathEnclosesNothingBecauseItHasNoInside() {
        var line = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 10, y: 0)),
            PathAnchor(point: CGPoint(x: 10, y: 10))
        ], isClosed: false)
        #expect(!line.enclosesAnArea)
        line.isClosed = true
        #expect(line.enclosesAnArea)
    }

    @Test func twoPointsJoinedWithStraightRunsEncloseNothing() {
        // There and back along the same line. It is closed, and it still has
        // no inside, which is the whole reason the Pen cannot close it.
        let flat = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0))
        ], isClosed: true)
        #expect(flat.enclosedArea == 0)
        #expect(!flat.enclosesAnArea)
    }

    @Test func threePointsOnOneStraightLineAlsoEncloseNothing() {
        let flat = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 50, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0))
        ], isClosed: true)
        #expect(!flat.enclosesAnArea)
    }

    @Test func twoPointsWithCurvesOnThemEncloseALeaf() {
        // A lens: one run bows above the line between the two points and the
        // other bows below it by the same amount, so the inside is real and
        // the two halves are the same size.
        let leaf = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0), handleIn: CGPoint(x: -30, y: -40),
                       handleOut: CGPoint(x: 30, y: 40), kind: .smooth),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleIn: CGPoint(x: -30, y: 40),
                       handleOut: CGPoint(x: 30, y: -40), kind: .smooth)
        ], isClosed: true)
        #expect(leaf.enclosesAnArea)
        #expect(leaf.enclosedArea.magnitude > 100)
    }

    @Test func oneCurvedPointAndOneCornerStillEncloseALens() {
        // Only the FIRST point was dragged. Its two handles mirror each other,
        // so the run out bows one way and the run home bows the other: the
        // cheapest two point shape there is.
        let lens = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0), handleIn: CGPoint(x: 0, y: -40),
                       handleOut: CGPoint(x: 0, y: 40), kind: .smooth),
            PathAnchor(point: CGPoint(x: 100, y: 0))
        ], isClosed: true)
        #expect(lens.enclosesAnArea)
    }
}
