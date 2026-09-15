import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Reshaping a path that has already been drawn: picking a point up, pulling a
/// handle, turning a corner into a bend and back, adding a point on a run and
/// taking one out (`docs/design/vector-paths.md`).
@Suite("Reshaping a path")
struct PathEditingTests {

    /// A square with its right-hand side bowed out: two straight runs and one
    /// curve, which is the smallest shape that proves straight and curved live
    /// in the same outline.
    static func bowedSquare() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 30)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 40, y: -30)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: true)
    }

    /// A smooth anchor between two others, with its two handles already in
    /// line: what dragging a handle has to keep true.
    static func smoothMiddle() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 100)),
            PathAnchor(point: CGPoint(x: 100, y: 0),
                       handleIn: CGPoint(x: -30, y: 0), handleOut: CGPoint(x: 60, y: 0),
                       kind: .smooth),
            PathAnchor(point: CGPoint(x: 200, y: 100))
        ])
    }

    static func near(_ a: CGPoint, _ b: CGPoint, _ slack: CGFloat = 1e-9) -> Bool {
        abs(a.x - b.x) <= slack && abs(a.y - b.y) <= slack
    }

    /// Every run of a path sampled at the same places, so two paths can be
    /// compared as SHAPES rather than as lists of numbers.
    static func outline(_ path: PathContent, steps: Int = 64) -> [CGPoint] {
        path.segments.flatMap { run in
            (0...steps).map { run.point(at: CGFloat($0) / CGFloat(steps)) }
        }
    }

    // MARK: - Picking a point up

    @Test func draggingAnAnchorMovesItAndTheCurvesFollow() {
        var path = Self.bowedSquare()
        let handleWas = path.anchors[1].handleOut
        path.moveAnchors([1], by: CGPoint(x: 20, y: -10))
        #expect(Self.near(path.anchors[1].point, CGPoint(x: 120, y: -10)))
        // Handles are offsets from the anchor, so the curve travels with it
        // rather than being left behind.
        #expect(path.anchors[1].handleOut == handleWas)
        #expect(Self.near(path.anchors[1].controlOut, CGPoint(x: 160, y: 20)))
        // Nothing else moved.
        #expect(Self.near(path.anchors[0].point, .zero))
        #expect(Self.near(path.anchors[2].point, CGPoint(x: 100, y: 100)))
    }

    @Test func severalAnchorsMoveTogether() {
        var path = Self.bowedSquare()
        path.moveAnchors([0, 3], by: CGPoint(x: -5, y: 5))
        #expect(Self.near(path.anchors[0].point, CGPoint(x: -5, y: 5)))
        #expect(Self.near(path.anchors[3].point, CGPoint(x: -5, y: 105)))
        #expect(Self.near(path.anchors[1].point, CGPoint(x: 100, y: 0)))
    }

    @Test func movingAnAnchorThatIsNotThereChangesNothing() {
        var path = Self.bowedSquare()
        let was = path
        path.moveAnchors([9, -1], by: CGPoint(x: 10, y: 10))
        #expect(path == was)
    }

    // MARK: - Pulling a handle

    @Test func draggingAHandleOnASmoothAnchorSwingsTheFarOneRound() throws {
        var path = Self.smoothMiddle()
        path.setHandle(anchor: 1, side: .handleOut, control: CGPoint(x: 100, y: 60))
        #expect(path.anchors[1].handleOut == CGPoint(x: 0, y: 60))
        // The far handle keeps ITS OWN length (30) and takes the opposite
        // direction, which is what "smooth" promises.
        let far = try #require(path.anchors[1].handleIn)
        #expect(Self.near(far, CGPoint(x: 0, y: -30), 1e-9))
        #expect(path.anchors[1].kind == .smooth)
    }

    @Test func draggingAHandleOnACornerLeavesTheOtherSideAlone() {
        var path = Self.bowedSquare()
        path.setHandle(anchor: 1, side: .handleOut, control: CGPoint(x: 140, y: 80))
        #expect(path.anchors[1].handleOut == CGPoint(x: 40, y: 80))
        #expect(path.anchors[1].handleIn == nil)
    }

    @Test func breakingWhileDraggingAHandleFreesTheTwoSides() {
        var path = Self.smoothMiddle()
        path.setHandle(anchor: 1, side: .handleOut, control: CGPoint(x: 100, y: 60),
                       breaking: true)
        #expect(path.anchors[1].kind == .corner)
        #expect(path.anchors[1].handleOut == CGPoint(x: 0, y: 60))
        // The far handle held still.
        #expect(path.anchors[1].handleIn == CGPoint(x: -30, y: 0))
    }

    // MARK: - Corner, smooth, and half of each

    @Test func aCornerBecomesSmoothWithItsHandlesInLine() throws {
        var path = Self.bowedSquare()
        path.makeSmooth(at: 0)
        let anchor = path.anchors[0]
        #expect(anchor.kind == .smooth)
        #expect(Self.near(anchor.point, .zero))
        let inHandle = try #require(anchor.handleIn)
        let outHandle = try #require(anchor.handleOut)
        // In line means exactly opposite directions.
        let cross = inHandle.x * outHandle.y - inHandle.y * outHandle.x
        #expect(abs(cross) < 1e-9)
        #expect(inHandle.x * outHandle.x + inHandle.y * outHandle.y < 0)
    }

    @Test func aSmoothAnchorBecomesAHardCornerWithStraightSides() {
        var path = Self.smoothMiddle()
        path.makeCorner(at: 1)
        #expect(path.anchors[1].kind == .corner)
        #expect(path.anchors[1].handleIn == nil)
        #expect(path.anchors[1].handleOut == nil)
        let straight = path.segments.filter(\.isStraight).count
        #expect(straight == path.segments.count)
    }

    @Test func theSameGestureTurnsAPointOneWayAndThenBack() {
        var path = Self.bowedSquare()
        let smoothed = path.toggleAnchorKind(at: 0)
        #expect(smoothed == .smooth)
        #expect(path.anchors[0].handleOut != nil)
        let cornered = path.toggleAnchorKind(at: 0)
        #expect(cornered == .corner)
        #expect(path.anchors[0].handleOut == nil)
        #expect(path.anchors[0].handleIn == nil)
    }

    @Test func onlyOneSideOfAPointCanBeCurved() {
        var path = Self.smoothMiddle()
        path.clearHandle(anchor: 1, side: .handleIn)
        let anchor = path.anchors[1]
        #expect(anchor.isHalfSmooth)
        #expect(anchor.handleIn == nil)
        #expect(anchor.handleOut == CGPoint(x: 60, y: 0))
        #expect(anchor.kind == .corner)
        // The run arriving is straight; the run leaving still bends.
        #expect(path.segments[0].isStraight)
        #expect(!path.segments[1].isStraight)
    }

    @Test func aBrokenPointCanBeJoinedBackUp() throws {
        var path = Self.smoothMiddle()
        path.clearHandle(anchor: 1, side: .handleIn)
        let joined = path.toggleAnchorKind(at: 1)
        #expect(joined == .smooth)
        let anchor = path.anchors[1]
        #expect(!anchor.isHalfSmooth)
        let inHandle = try #require(anchor.handleIn)
        let outHandle = try #require(anchor.handleOut)
        let cross = inHandle.x * outHandle.y - inHandle.y * outHandle.x
        #expect(abs(cross) < 1e-9)
        // The side that was already curved keeps the length it had.
        #expect(abs(hypot(outHandle.x, outHandle.y) - 60) < 1e-9)
    }

    @Test func aPointWithNothingEitherSideOfItIsLeftAlone() {
        var path = PathContent(anchors: [PathAnchor(point: .zero)])
        path.makeSmooth(at: 0)
        #expect(path.anchors[0].handleIn == nil)
        #expect(path.anchors[0].handleOut == nil)
    }

    // MARK: - Adding a point

    @Test func aPointAddedOnAStraightRunLandsOnTheLine() {
        var path = Self.bowedSquare()
        let added = path.insertAnchor(onSegment: 0, at: 0.25)
        #expect(added == 1)
        #expect(path.anchors.count == 5)
        #expect(Self.near(path.anchors[1].point, CGPoint(x: 25, y: 0)))
        #expect(path.anchors[1].kind == .corner)
        #expect(path.segments[0].isStraight)
        #expect(path.segments[1].isStraight)
    }

    /// The one that is real work: splitting a cubic has an exact answer, and
    /// doing it approximately shows up as the outline twitching the moment you
    /// add a point.
    @Test func aPointAddedOnACurvedRunDoesNotChangeTheCurve() {
        let was = Self.bowedSquare()
        var path = was
        let t: CGFloat = 0.4
        let split = path.insertAnchor(onSegment: 1, at: t)
        #expect(split == 2)
        #expect(path.anchors.count == 5)
        // The two halves have to BE the old curve, written twice: the first
        // run at u is the old run at u*t, the second at t + u*(1-t). Compared
        // on the cubics themselves rather than on a flattened outline, because
        // flattening has an error of its own thousands of times larger than the
        // one this test exists to catch.
        let old = was.segments[1]
        let first = path.segments[1]
        let second = path.segments[2]
        for step in 0...64 {
            let u = CGFloat(step) / 64
            #expect(Self.near(first.point(at: u), old.point(at: u * t), 1e-9))
            #expect(Self.near(second.point(at: u), old.point(at: t + u * (1 - t)), 1e-9))
        }
        // And every other run is untouched.
        #expect(path.segments[0] == was.segments[0])
        #expect(path.segments[3] == was.segments[2])
    }

    @Test func addingAPointOnACurveLeavesTheCurveSmoothThroughIt() throws {
        var path = Self.bowedSquare()
        _ = path.insertAnchor(onSegment: 1, at: 0.5)
        let added = path.anchors[2]
        #expect(added.kind == .smooth)
        let inHandle = try #require(added.handleIn)
        let outHandle = try #require(added.handleOut)
        let cross = inHandle.x * outHandle.y - inHandle.y * outHandle.x
        #expect(abs(cross) < 1e-6)
    }

    @Test func aPointCanBeAddedOnTheRunThatClosesTheShape() {
        var path = Self.bowedSquare()
        let added = path.insertAnchor(onSegment: 3, at: 0.5)
        #expect(added == 4)
        #expect(path.anchors.count == 5)
        #expect(Self.near(path.anchors[4].point, CGPoint(x: 0, y: 50)))
    }

    @Test func aRunThatIsNotThereTakesNoPoint() {
        var path = Self.bowedSquare()
        let added = path.insertAnchor(onSegment: 9, at: 0.5)
        #expect(added == nil)
        #expect(path.anchors.count == 4)
    }

    // MARK: - Taking a point out

    @Test func takingOutAPointClosesTheCurveOverTheGap() {
        let was = Self.bowedSquare()
        var path = was
        _ = path.insertAnchor(onSegment: 1, at: 0.35)
        let removed = path.removeAnchors([2])
        #expect(removed)
        #expect(path.anchors.count == 4)
        // Adding a point and taking it away again puts the curve back exactly:
        // where a point sat is written in its own two handles, so the gap is
        // closed by undoing the split rather than by guessing at it.
        for (before, now) in zip(was.anchors, path.anchors) {
            #expect(Self.near(before.point, now.point, 1e-9))
            #expect(Self.near(before.controlIn, now.controlIn, 1e-9))
            #expect(Self.near(before.controlOut, now.controlOut, 1e-9))
        }
    }

    @Test func takingOutAPointOfAStraightLineLeavesTheLineStraight() {
        var path = Self.bowedSquare()
        _ = path.insertAnchor(onSegment: 0, at: 0.5)
        let removed = path.removeAnchors([1])
        #expect(removed)
        #expect(path.anchors.count == 4)
        #expect(path.segments[0].isStraight)
    }

    @Test func severalPointsComeOutAtOnce() {
        var path = PathContent(anchors: (0..<6).map {
            PathAnchor(point: CGPoint(x: $0 * 10, y: 0))
        })
        let removed = path.removeAnchors([1, 3])
        #expect(removed)
        #expect(path.anchors.count == 4)
        #expect(Self.near(path.anchors[1].point, CGPoint(x: 20, y: 0)))
    }

    @Test func aPathIsNeverLeftWithFewerThanTwoPoints() {
        var path = PathContent(anchors: [
            PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 10, y: 0))
        ])
        let removed = path.removeAnchors([0])
        #expect(!removed)
        #expect(path.anchors.count == 2)
    }

    @Test func takingOutTheEndOfAnOpenLineShortensIt() {
        var path = Self.smoothMiddle()
        let removed = path.removeAnchors([2])
        #expect(removed)
        #expect(path.anchors.count == 2)
        #expect(Self.near(path.anchors.last!.point, CGPoint(x: 100, y: 0)))
    }

    // MARK: - Hitting the right thing

    @Test func aClickOnAPointPicksThatPoint() {
        let path = Self.bowedSquare()
        #expect(path.editTarget(at: CGPoint(x: 102, y: 2), zoom: 1, handlesShowing: [])
                == .anchor(1))
    }

    @Test func aClickOnAHandlePicksTheHandleButOnlyWhileItIsShowing() {
        let path = Self.smoothMiddle()
        let onHandle = CGPoint(x: 160, y: 0)  // anchor 1 + its outgoing handle
        #expect(path.editTarget(at: onHandle, zoom: 1, handlesShowing: []) == nil)
        #expect(path.editTarget(at: onHandle, zoom: 1, handlesShowing: [1])
                == .handle(anchor: 1, side: .handleOut))
    }

    @Test func aClickOnTheOutlinePicksTheRunAndWhereAlongIt() {
        let path = Self.bowedSquare()
        guard case .segment(let run, let t)? = path.editTarget(at: CGPoint(x: 50, y: 1),
                                                               zoom: 1, handlesShowing: []) else {
            Issue.record("a click on the top edge did not land on a run")
            return
        }
        #expect(run == 0)
        #expect(abs(t - 0.5) < 0.05)
    }

    @Test func aClickOnNothingHitsNothing() {
        let path = Self.bowedSquare()
        #expect(path.editTarget(at: CGPoint(x: 50, y: 50), zoom: 1, handlesShowing: []) == nil)
    }

    @Test func targetsStayTheSameSizeOnScreenAtEveryZoom() {
        let path = Self.bowedSquare()
        // Six document points from the anchor: inside the eight point target at
        // 1x, well outside it at 8x.
        let near = CGPoint(x: 106, y: 0)
        #expect(path.editTarget(at: near, zoom: 1, handlesShowing: []) == .anchor(1))
        #expect(path.editTarget(at: near, zoom: 8, handlesShowing: []) != .anchor(1))
    }

    // MARK: - Round trips

    @Test func aReshapedPathSurvivesSaveAndLoad() throws {
        var path = Self.bowedSquare()
        path.moveAnchors([1], by: CGPoint(x: 7, y: -3))
        path.makeSmooth(at: 0)
        _ = path.insertAnchor(onSegment: 1, at: 0.5)
        path.clearHandle(anchor: 3, side: .handleIn)
        let data = try JSONEncoder().encode(path)
        let back = try JSONDecoder().decode(PathContent.self, from: data)
        #expect(back == path)
    }

    @Test func aRunCanSayWhereItIsAtAnyPointAlongIt() {
        let path = Self.bowedSquare()
        let run = path.segments[0]
        #expect(Self.near(run.point(at: 0), CGPoint(x: 0, y: 0)))
        #expect(Self.near(run.point(at: 1), CGPoint(x: 100, y: 0)))
        #expect(Self.near(run.point(at: 0.5), CGPoint(x: 50, y: 0)))
    }

    // MARK: The smallest shape reshapes like any other

    static func leaf() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 50), handleIn: CGPoint(x: -30, y: -40),
                       handleOut: CGPoint(x: 30, y: 40), kind: .smooth),
            PathAnchor(point: CGPoint(x: 100, y: 50), handleIn: CGPoint(x: 30, y: 40),
                       handleOut: CGPoint(x: -30, y: -40), kind: .smooth)
        ], isClosed: true)
    }

    @Test func bothPointsOfALeafCanBePickedUp() {
        let leaf = Self.leaf()
        #expect(leaf.editTarget(at: CGPoint(x: 1, y: 51), zoom: 1,
                                handlesShowing: []) == .anchor(0))
        #expect(leaf.editTarget(at: CGPoint(x: 99, y: 49), zoom: 1,
                                handlesShowing: []) == .anchor(1))
    }

    @Test func draggingALeafPointOpensItUp() {
        var leaf = Self.leaf()
        let before = leaf.enclosedArea.magnitude
        leaf.moveAnchors([1], by: CGPoint(x: 60, y: 0))
        #expect(leaf.anchors[1].point == CGPoint(x: 160, y: 50))
        // It is still a shape, and a bigger one: the handles travelled with
        // the point rather than being left behind.
        #expect(leaf.enclosesAnArea)
        #expect(leaf.enclosedArea.magnitude > before)
    }

    @Test func aPointCanBeAddedToEitherRunOfALeaf() {
        // Including the run HOME, which is the one a two point shape has that
        // an open path does not.
        var leaf = Self.leaf()
        #expect(leaf.insertAnchor(onSegment: 1, at: 0.5) == 2)
        #expect(leaf.anchors.count == 3)
        #expect(leaf.enclosesAnArea)
    }

    @Test func aLeafSurvivesBeingWrittenOutAndReadBack() {
        let leaf = Self.leaf()
        let data = try! JSONEncoder().encode(leaf)
        let back = try! JSONDecoder().decode(PathContent.self, from: data)
        #expect(back == leaf)
        #expect(back.isClosed)
        #expect(back.enclosesAnArea)
    }
}
