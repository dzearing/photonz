import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A path's sharp corners can be rounded without moving a single point: each
/// corner carries a radius, and everything that DRAWS the path reads an outline
/// with that corner cut back and bridged by an arc (`PathCornerRounding.swift`).
@Suite("Rounding a path's corners")
struct PathCornerRoundingTests {

    static func square(side: CGFloat = 100, radius: CGFloat = 0) -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0), cornerRadius: radius),
            PathAnchor(point: CGPoint(x: side, y: 0), cornerRadius: radius),
            PathAnchor(point: CGPoint(x: side, y: side), cornerRadius: radius),
            PathAnchor(point: CGPoint(x: 0, y: side), cornerRadius: radius)
        ], isClosed: true, strokeWidth: 0)
    }

    /// A regular pentagon of side `side`, point up, the shape the user asked
    /// about ("when I make a polygon with the pen tool").
    static func pentagon(side: CGFloat = 100) -> PathContent {
        let circumradius = side / (2 * sin(.pi / 5))
        let centre = CGPoint(x: 200, y: 200)
        let anchors = (0..<5).map { k -> PathAnchor in
            let angle = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 5
            return PathAnchor(point: CGPoint(x: centre.x + circumradius * cos(angle),
                                             y: centre.y + circumradius * sin(angle)))
        }
        return PathContent(anchors: anchors, isClosed: true)
    }

    /// Every point the drawn outline passes through, sampled finely.
    static func samples(_ content: PathContent) -> [CGPoint] {
        content.drawnOutline.flattenedRings(steps: 64).flatMap { $0 }
    }

    static func near(_ a: CGPoint, _ b: CGPoint, within: CGFloat = 0.01) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= within
    }

    // MARK: On disk

    @Test func anAnchorStartsSquare() {
        #expect(PathAnchor(point: .zero).cornerRadius == 0)
    }

    @Test func aFileWrittenBeforeRoundingOpensSquare() throws {
        let old = #"{"point":[10,20],"kind":"corner"}"#
        let anchor = try JSONDecoder().decode(PathAnchor.self, from: Data(old.utf8))
        #expect(anchor.point == CGPoint(x: 10, y: 20))
        #expect(anchor.cornerRadius == 0)
    }

    @Test func aSquareAnchorWritesNothingNew() throws {
        let data = try JSONEncoder().encode(PathAnchor(point: CGPoint(x: 1, y: 2)))
        #expect(!String(decoding: data, as: UTF8.self).contains("cornerRadius"))
    }

    @Test func aRoundedAnchorKeepsItsRadiusThroughAFile() throws {
        let anchor = PathAnchor(point: CGPoint(x: 1, y: 2), handleIn: CGPoint(x: 3, y: 4),
                                cornerRadius: 12)
        let back = try JSONDecoder().decode(PathAnchor.self,
                                            from: JSONEncoder().encode(anchor))
        #expect(back == anchor)
    }

    // MARK: Which corners round

    @Test func everyCornerOfAClosedPolygonRounds() {
        #expect(Self.pentagon().roundableCorners == [0, 1, 2, 3, 4])
    }

    @Test func theEndsOfAnOpenLineDoNotRound() {
        let line = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100))
        ])
        #expect(line.roundableCorners == [1])
    }

    @Test func aSmoothBendDoesNotRound() {
        var path = Self.square()
        path.anchors[1] = PathAnchor(point: CGPoint(x: 100, y: 0),
                                     handleIn: CGPoint(x: -30, y: 0),
                                     handleOut: CGPoint(x: 30, y: 0), kind: .smooth)
        #expect(!path.roundableCorners.contains(1))
    }

    @Test func aPointInTheMiddleOfAStraightRunDoesNotRound() {
        let path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 50, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 50, y: 80))
        ], isClosed: true)
        #expect(!path.roundableCorners.contains(1))
    }

    // MARK: The drawn outline

    @Test func aSquarePathIsDrawnExactlyAsItIsStored() {
        let path = Self.square()
        #expect(path.drawnOutline == path)
    }

    @Test func aRoundedCornerStartsAndEndsWhereTheArcMeetsTheEdges() {
        let drawn = Self.square(radius: 20).drawnOutline
        let points = drawn.anchors.map(\.point)
        // Corner 0 at the origin, rounded by 20: the arc leaves the left edge
        // at (0, 20) and lands on the top edge at (20, 0).
        #expect(points.contains { Self.near($0, CGPoint(x: 0, y: 20)) })
        #expect(points.contains { Self.near($0, CGPoint(x: 20, y: 0)) })
        // ...and no point of the drawing sits on the sharp corner any more.
        #expect(!points.contains { Self.near($0, .zero, within: 1) })
        // The points themselves are untouched.
        #expect(Self.square(radius: 20).anchors.map(\.point)
                == Self.square().anchors.map(\.point))
    }

    @Test func theArcIsACircleOfTheRadiusAsked() {
        let samples = Self.samples(Self.square(radius: 20))
        // Every sample inside the top-left 20 x 20 is on the arc struck from
        // (20, 20), to within a hundredth of a point at radius twenty.
        let corner = samples.filter { $0.x < 20 - 1e-6 && $0.y < 20 - 1e-6 }
        #expect(corner.count > 4)
        for p in corner {
            #expect(abs(hypot(p.x - 20, p.y - 20) - 20) < 0.01)
        }
    }

    @Test func aRoundedSquareStaysInsideItsPoints() {
        let box = Self.square(radius: 30).drawnOutline.bounds
        #expect(abs(box.minX) < 1e-6 && abs(box.minY) < 1e-6)
        #expect(abs(box.maxX - 100) < 1e-6 && abs(box.maxY - 100) < 1e-6)
    }

    @Test func theCornerNeverOvershootsItsEdges() {
        // Asked for 80 on a 100 square: two corners share every edge, so each
        // can take half of it, and the square comes out a circle of 50.
        let path = Self.square(radius: 80)
        for i in 0..<4 { #expect(abs(path.drawnCornerRadius(at: i) - 50) < 1e-6) }
        for p in Self.samples(path) {
            #expect(abs(hypot(p.x - 50, p.y - 50) - 50) < 0.05)
        }
        // Where two arcs meet in the middle of an edge they are one point,
        // not two with a run of no length between them.
        #expect(path.drawnOutline.anchors.count == 4)
    }

    @Test func aCornerAloneCanTakeTheWholeOfItsShorterEdge() {
        let line = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 40, y: 0), cornerRadius: 500),
            PathAnchor(point: CGPoint(x: 40, y: 100))
        ])
        // A right angle cuts back by its radius, and the shorter edge is 40.
        #expect(abs(line.drawnCornerRadius(at: 1) - 40) < 1e-6)
        let drawn = line.drawnOutline
        #expect(Self.near(drawn.anchors.first?.point ?? .zero, .zero))
        #expect(Self.near(drawn.anchors.last?.point ?? .zero, CGPoint(x: 40, y: 100)))
    }

    @Test func aRoundedOpenLineKeepsItsEnds() {
        let line = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), cornerRadius: 30),
            PathAnchor(point: CGPoint(x: 100, y: 100))
        ])
        let drawn = line.drawnOutline
        #expect(!drawn.isClosed)
        #expect(drawn.anchors.count == 4)
        #expect(Self.near(drawn.anchors[1].point, CGPoint(x: 70, y: 0)))
        #expect(Self.near(drawn.anchors[2].point, CGPoint(x: 100, y: 30)))
    }

    @Test func aCornerBetweenTwoCurvesRoundsAndStaysOnBothCurves() {
        // A corner where a curve arrives and a curve leaves: the arc is cut
        // into both curves rather than into their straight chords.
        let path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 100), handleOut: CGPoint(x: 20, y: -60)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleIn: CGPoint(x: -40, y: 0),
                       handleOut: CGPoint(x: 0, y: 40), cornerRadius: 20),
            PathAnchor(point: CGPoint(x: 200, y: 100), handleIn: CGPoint(x: -60, y: -20))
        ])
        #expect(path.roundableCorners == [1])
        let drawn = path.drawnOutline
        #expect(drawn.anchors.count == 4)
        // The cut points lie on the original curves.
        let original = path.flattenedRings(steps: 400).flatMap { $0 }
        for cut in [drawn.anchors[1].point, drawn.anchors[2].point] {
            let gap = original.map { hypot($0.x - cut.x, $0.y - cut.y) }.min() ?? .infinity
            #expect(gap < 0.5)
        }
    }

    @Test func aPathWithAHoleRoundsEachRingOnItsOwn() {
        var outer = Self.square(radius: 10)
        let hole = [CGPoint(x: 30, y: 30), CGPoint(x: 30, y: 70),
                    CGPoint(x: 70, y: 70), CGPoint(x: 70, y: 30)]
            .map { PathAnchor(point: $0, cornerRadius: 5) }
        outer.anchors += hole
        outer.ringStarts = [4]
        let drawn = outer.drawnOutline
        #expect(drawn.ringCount == 2)
        #expect(drawn.anchors.count == 16)
        #expect(drawn.ringStarts == [8])
    }

    // MARK: Everything that draws reads the rounded outline

    @Test func theCoreGraphicsOutlineIsTheRoundedOne() {
        let box = Self.square(radius: 30).cgPath.boundingBoxOfPath
        #expect(abs(box.width - 100) < 1e-6)
        var curves = 0
        Self.square(radius: 30).cgPath.applyWithBlock {
            if $0.pointee.type == .addCurveToPoint { curves += 1 }
        }
        #expect(curves == 4)
    }

    @Test func theSVGOutlineCarriesARealCurveAtEveryRoundedCorner() {
        let data = SVGExport.pathData(Self.square(radius: 20))
        #expect(data.components(separatedBy: "C").count - 1 == 4)
        #expect(data.hasPrefix("M0 20"))
        #expect(!SVGExport.pathData(Self.square()).contains("C"))
    }

    @Test func aPressOnTheCutAwayCornerMissesTheShape() {
        let rounded = Self.square(radius: 40)
        #expect(!rounded.isHit(at: CGPoint(x: 3, y: 3)))
        #expect(rounded.isHit(at: CGPoint(x: 50, y: 50)))
        #expect(Self.square().isHit(at: CGPoint(x: 3, y: 3)))
    }

    @Test func combiningShapesKeepsTheRoundedOutline() throws {
        let other = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 200, y: 0)), PathAnchor(point: CGPoint(x: 300, y: 0)),
            PathAnchor(point: CGPoint(x: 300, y: 100)), PathAnchor(point: CGPoint(x: 200, y: 100))
        ], isClosed: true)
        let joined = try #require(PathCombine.combine([Self.square(radius: 20), other], .join))
        #expect(joined.anchors.contains { $0.handleIn != nil || $0.handleOut != nil })
    }

    // MARK: How far a corner can go

    @Test func everyCornerOfAPentagonStopsWhereItBecomesACircle() {
        // Rounded together, a regular polygon's corners meet in the middle of
        // every edge at the radius of the circle that touches all five sides.
        let pentagon = Self.pentagon(side: 100)
        let apothem = 100 / (2 * tan(CGFloat.pi / 5))
        for i in 0..<5 {
            #expect(abs(pentagon.cornerRadiusLimit(at: i, allCorners: true) - apothem) < 1e-6)
        }
    }

    @Test func aCornerAloneStopsShortOfItsRoundedNeighbour() {
        var square = Self.square()
        square.anchors[1].cornerRadius = 30
        // Its edge to corner 1 is 100 long and 30 of it is already spent; its
        // edge to corner 3 is all its own.
        #expect(abs(square.cornerRadiusLimit(at: 0, allCorners: false) - 70) < 1e-6)
    }

    @Test func aRadiusSetOnEveryCornerTouchesOnlyCorners() {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100))
        ])
        path.setCornerRadius(12)
        #expect(path.anchors.map(\.cornerRadius) == [0, 12, 0])
        path.setCornerRadius(4, at: 1)
        #expect(path.anchors[1].cornerRadius == 4)
        path.setCornerRadius(4, at: 0)
        #expect(path.anchors[0].cornerRadius == 0)
    }

    @Test func theReadingIsOneNumberOrMixed() {
        var path = Self.square(radius: 8)
        #expect(path.cornerRadiusReading == PathCornerRadiusReading(radius: 8, isMixed: false))
        path.anchors[2].cornerRadius = 20
        #expect(path.cornerRadiusReading?.isMixed == true)
        #expect(path.cornerRadiusReading?.radius == 20)
        let line = PathContent(anchors: [PathAnchor(point: .zero),
                                         PathAnchor(point: CGPoint(x: 9, y: 9))])
        #expect(line.cornerRadiusReading == nil)
    }

    // MARK: The rounding survives the edits a path already has

    @Test func movingAPointKeepsItsRounding() {
        var path = Self.square(radius: 10)
        path.moveAnchors([2], by: CGPoint(x: 20, y: 20))
        #expect(path.anchors[2].cornerRadius == 10)
    }

    @Test func turningAPathRoundKeepsItsRounding() {
        var path = Self.square()
        path.anchors[1].cornerRadius = 7
        #expect(path.reversed().anchors.map(\.cornerRadius) == [0, 0, 7, 0])
    }

    @Test func resizingAShapeKeepsItsRadiusInPoints() {
        let grown = Self.square(radius: 10).scaled(x: 2, y: 3)
        #expect(grown.anchors.allSatisfy { $0.cornerRadius == 10 })
    }

    // MARK: The knob

    @Test func aSquareCornersKnobRestsAShortWayInAlongTheBisector() throws {
        let knob = try #require(Self.square().cornerKnob(at: 0, zoom: 2))
        let rest = PathContent.cornerKnobRest / 2
        #expect(Self.near(knob.point, CGPoint(x: rest / sqrt(2), y: rest / sqrt(2))))
    }

    @Test func aRoundedCornersKnobRidesTheCentreOfItsCurve() throws {
        let knob = try #require(Self.square(radius: 20).cornerKnob(at: 0, zoom: 1))
        let rest = PathContent.cornerKnobRest
        #expect(Self.near(knob.point, CGPoint(x: 20 + rest / sqrt(2), y: 20 + rest / sqrt(2))))
    }

    @Test func pullingTheKnobToWhereItIsAsksForTheRadiusItHas() throws {
        let pentagon = { () -> PathContent in
            var p = Self.pentagon(); p.setCornerRadius(17); return p
        }()
        for i in 0..<5 {
            let knob = try #require(pentagon.cornerKnob(at: i, zoom: 3))
            #expect(abs(pentagon.cornerRadius(draggingKnobAt: i, to: knob.point, zoom: 3) - 17) < 1e-6)
        }
    }

    @Test func pushingTheKnobBackOutSquaresTheCorner() {
        let square = Self.square(radius: 20)
        #expect(square.cornerRadius(draggingKnobAt: 0, to: CGPoint(x: -10, y: -10), zoom: 1) == 0)
    }

    @Test func aKnobIsCaughtNearItAndNowhereElse() throws {
        let square = Self.square()
        let knob = try #require(square.cornerKnob(at: 2, zoom: 1))
        #expect(square.cornerKnobHit(at: CGPoint(x: knob.point.x + 3, y: knob.point.y), zoom: 1) == 2)
        #expect(square.cornerKnobHit(at: CGPoint(x: 50, y: 50), zoom: 1) == nil)
    }

    @Test func aPullLandsOnWholeGridStepsWhileTheGridPulls() {
        #expect(PathContent.landedCornerRadius(5.4, gridSpacing: 2, zoom: 1) == 6)
        #expect(PathContent.landedCornerRadius(5.4, gridSpacing: nil, zoom: 1) == 5)
        #expect(PathContent.landedCornerRadius(5.4, gridSpacing: nil, zoom: 8) == 5.5)
        #expect(PathContent.landedCornerRadius(-3, gridSpacing: nil, zoom: 1) == 0)
    }

    @Test func aCornerTooSmallOnScreenHidesItsKnob() {
        let tiny = Self.square(side: 10)
        #expect(tiny.cornerKnobs(zoom: 1).isEmpty)
        #expect(tiny.cornerKnobs(zoom: 8).count == 4)
    }
}

/// The one Corner Radius row in Appearance speaks for a picked path's corners:
/// the same number the knob on the canvas pulls.
@Suite("The Corner Radius row over a path")
struct PathCornerRadiusRowTests {

    static func document(_ content: PathContent) -> (PhotonzDocument, UUID) {
        let layer = PathBuilder.layer(content, at: CGPoint(x: 40, y: 40))
        return (PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [layer]),
                layer.id)
    }

    @Test func aPathWithCornersBringsTheRow() {
        let (doc, id) = Self.document(PathCornerRoundingTests.square(radius: 12))
        let row = doc.cornerRadiusSelection(layerIDs: [id], cornersOnly: true,
                                            readingWhatShows: true)
        #expect(row.count == 1)
        #expect(row.reading.value == 12)
        #expect(!row.hasUnevenCorners)
        #expect(row.roundsPathPoints)
        // Fully round for a square is half its side.
        #expect(abs(row.limit - 50) < 1e-6)
    }

    @Test func cornersRoundedApartReadMixed() {
        var square = PathCornerRoundingTests.square(radius: 12)
        square.anchors[3].cornerRadius = 30
        let (doc, id) = Self.document(square)
        let row = doc.cornerRadiusSelection(layerIDs: [id], cornersOnly: true,
                                            readingWhatShows: true)
        #expect(row.hasUnevenCorners)
        #expect(row.reading.value == 30)
    }

    @Test func aLineWithNoCornerBringsNoRow() {
        let line = PathContent(anchors: [PathAnchor(point: .zero),
                                         PathAnchor(point: CGPoint(x: 90, y: 40))])
        let (doc, id) = Self.document(line)
        #expect(doc.cornerRadiusSelection(layerIDs: [id], cornersOnly: true,
                                          readingWhatShows: true).isEmpty)
    }

    @Test func theRowRoundsThePointsNotTheBox() {
        var (doc, id) = Self.document(PathCornerRoundingTests.square())
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(9), onlyWhatShows: true)
        let layer = doc.layer(id: id)
        #expect(layer?.path?.anchors.map(\.cornerRadius) == [9, 9, 9, 9])
        #expect(layer?.style.cornerRadii == CornerRadii.none)
        // The points did not move and neither did the box.
        #expect(layer?.path?.anchors.map(\.point) == PathCornerRoundingTests.square().anchors.map(\.point))
    }

    @Test func theReleaseBeforeNextLeavesAPathAsItWas() {
        let (doc, id) = Self.document(PathCornerRoundingTests.square())
        #expect(doc.cornerRadiusSelection(layerIDs: [id], cornersOnly: true).isEmpty)
    }
}
