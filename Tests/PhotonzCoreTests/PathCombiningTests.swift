import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Two shapes become one: join them, cut one out of the other, keep only the
/// overlap, or keep everything but the overlap (`PathCombining.swift`).
///
/// The arithmetic is Core Graphics' and is not what these test. What they test
/// is the thing the app has to get right on top of it: that what comes back is
/// the app's OWN outline, with real anchors and real curves, and that a shape
/// with a hole in it and a shape in several pieces both fit in one path.
@Suite("Two shapes become one")
struct PathCombiningTests {

    // MARK: Helpers

    private func circle(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) -> PathContent {
        PathContent.ellipse(in: CGRect(x: x, y: y, width: size, height: size))
    }

    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> PathContent {
        PathContent.rectangle(in: CGRect(x: x, y: y, width: w, height: h))
    }

    /// A pair that overlaps in the middle, the shapes the audit uses.
    private var left: PathContent { circle(0, 0, 100) }
    private var right: PathContent { circle(60, 0, 100) }

    private func near(_ a: CGFloat, _ b: CGFloat, within: CGFloat = 0.5) -> Bool {
        abs(a - b) <= within
    }

    // MARK: The four operations

    @Test("Join keeps every bit either shape covered, as one loop")
    func joinMakesOneLoop() throws {
        let joined = try #require(PathCombine.combine([left, right], .join))
        #expect(joined.ringCount == 1)
        #expect(joined.isClosed)
        #expect(near(joined.bounds.width, 160))
        #expect(near(joined.bounds.height, 100))
        // Bigger than either shape on its own, smaller than both added up,
        // because the overlap is only counted once.
        let area = abs(joined.enclosedArea)
        #expect(area > abs(left.enclosedArea))
        #expect(area < abs(left.enclosedArea) + abs(right.enclosedArea))
    }

    @Test("Cut Out punches a hole, and the hole is really empty")
    func cutOutMakesAHole() throws {
        let rim = circle(0, 0, 100)
        let hole = circle(25, 25, 50)
        let ring = try #require(PathCombine.combine([rim, hole], .cutOut))
        #expect(ring.ringCount == 2)
        #expect(ring.hasSeveralRings)
        // The middle is outside the shape and the rim is inside it. That is
        // the whole difference between a ring and a disc.
        #expect(ring.containsInside(CGPoint(x: 50, y: 50)) == false)
        #expect(ring.containsInside(CGPoint(x: 50, y: 6)))
        #expect(ring.containsInside(CGPoint(x: -5, y: 50)) == false)
    }

    @Test("Keep Overlap keeps only where the two shapes meet")
    func keepOverlapKeepsTheLens() throws {
        let lens = try #require(PathCombine.combine([left, right], .keepOverlap))
        #expect(lens.ringCount == 1)
        #expect(near(lens.bounds.minX, 60))
        #expect(near(lens.bounds.maxX, 100))
        #expect(abs(lens.enclosedArea) < abs(left.enclosedArea))
    }

    @Test("Drop Overlap leaves the two crescents, in one path of two pieces")
    func dropOverlapLeavesTwoPieces() throws {
        let both = try #require(PathCombine.combine([left, right], .dropOverlap))
        #expect(both.ringCount == 2)
        #expect(near(both.bounds.width, 160))
        // The overlap is gone: the point squarely in the middle of it is out.
        #expect(both.containsInside(CGPoint(x: 80, y: 50)) == false)
        #expect(both.containsInside(CGPoint(x: 10, y: 50)))
        #expect(both.containsInside(CGPoint(x: 150, y: 50)))
    }

    // MARK: A result in several unconnected pieces

    @Test("Joining two shapes that never touch gives one path of two pieces")
    func joinOfStrangersIsTwoPieces() throws {
        let apart = try #require(PathCombine.combine([circle(0, 0, 40), circle(200, 0, 40)], .join))
        #expect(apart.ringCount == 2)
        #expect(near(apart.bounds.width, 240))
        #expect(apart.containsInside(CGPoint(x: 20, y: 20)))
        #expect(apart.containsInside(CGPoint(x: 220, y: 20)))
        #expect(apart.containsInside(CGPoint(x: 120, y: 20)) == false)
    }

    // MARK: When the answer is nothing at all

    @Test("Keeping the overlap of shapes that do not touch answers nothing")
    func overlapOfStrangersIsEmpty() {
        #expect(PathCombine.combine([circle(0, 0, 40), circle(200, 0, 40)], .keepOverlap) == nil)
    }

    @Test("A shape cut out of itself answers nothing")
    func cutOutOfItselfIsEmpty() {
        #expect(PathCombine.combine([left, left], .cutOut) == nil)
    }

    @Test("A cut that swallows the whole shape answers nothing")
    func cutThatLeavesNothingIsEmpty() {
        #expect(PathCombine.combine([circle(20, 20, 20), circle(0, 0, 100)], .cutOut) == nil)
    }

    // MARK: Nothing is flattened on the way through

    @Test("Joining a circle with itself gives back the same circle, curves and all")
    func aNoOpJoinIsLossless() throws {
        let one = circle(0, 0, 100)
        let again = try #require(PathCombine.combine([one, one], .join))
        #expect(again.anchors.count == one.anchors.count)
        // Not one run turned into a line, which is what a naive walk of the
        // element list does to every curve it meets.
        #expect(again.segments.allSatisfy { !$0.isStraight })
        #expect(one.segments.allSatisfy { !$0.isStraight })
        #expect(near(again.bounds.width, one.bounds.width, within: 0.001))
        #expect(near(again.bounds.height, one.bounds.height, within: 0.001))
        #expect(near(abs(again.enclosedArea), abs(one.enclosedArea), within: 0.01))
    }

    @Test("A square keeps its straight edges and grows no handles")
    func squaresStayStraight() throws {
        let wide = try #require(PathCombine.combine([box(0, 0, 50, 50), box(25, 25, 50, 50)], .join))
        #expect(wide.segments.allSatisfy { $0.isStraight })
        #expect(wide.anchors.allSatisfy { $0.handleIn == nil && $0.handleOut == nil })
        #expect(near(abs(wide.enclosedArea), 50 * 50 * 2 - 25 * 25))
    }

    @Test("The anchors that come back can be picked up and dragged")
    func theResultIsEditable() throws {
        var ring = try #require(PathCombine.combine([circle(0, 0, 100), circle(25, 25, 50)], .cutOut))
        let was = ring.anchors[0].point
        ring.moveAnchors([0], by: CGPoint(x: -10, y: 0))
        #expect(ring.anchors[0].point.x == was.x - 10)
        // ...and a point on the HOLE is as much an anchor as one on the rim.
        let hole = try #require(ring.ringStarts.first)
        let holePoint = ring.anchors[hole].point
        ring.moveAnchors([hole], by: CGPoint(x: 0, y: 3))
        #expect(ring.anchors[hole].point.y == holePoint.y + 3)
    }

    // MARK: What cannot take part

    @Test("An open path encloses nothing, so it cannot take part")
    func openPathsAreNotShapes() {
        var line = PathContent.line(from: .zero, to: CGPoint(x: 100, y: 100))
        #expect(PathCombine.canTakePart(line) == false)
        line.isClosed = true
        #expect(PathCombine.canTakePart(line) == false, "three points on one line enclose nothing")
        #expect(PathCombine.canTakePart(circle(0, 0, 10)))
    }

    @Test("One shape on its own is not a combination")
    func oneShapeIsNothingToCombine() {
        #expect(PathCombine.combine([left], .join) == nil)
        #expect(PathCombine.combine([], .join) == nil)
    }

    @Test("A line picked alongside two circles is simply left out")
    func openPathsAreLeftOut() throws {
        let line = PathContent.line(from: .zero, to: CGPoint(x: 400, y: 400))
        let joined = try #require(PathCombine.combine([left, line, right], .join))
        #expect(near(joined.bounds.width, 160), "the line took no part in the area")
    }

    // MARK: The look it comes out wearing

    @Test("The result wears the bottom shape's fill and outline")
    func theBottomShapeIsTheKeeper() throws {
        var bottom = circle(0, 0, 100)
        bottom.colorHex = "#112233"
        bottom.fillColorHex = "#445566"
        bottom.strokeWidth = 7
        bottom.lineCorner = .round
        var top = circle(60, 0, 100)
        top.colorHex = "#FFFFFF"
        top.fillColorHex = "#000000"
        top.strokeWidth = 1
        let joined = try #require(PathCombine.combine([bottom, top], .join))
        #expect(joined.colorHex == "#112233")
        #expect(joined.fillColorHex == "#445566")
        #expect(joined.strokeWidth == 7)
        #expect(joined.lineCorner == .round)
    }

    // MARK: The hole holds through everything a layer does to a shape

    @Test("A hole survives moving, resizing and turning")
    func theHoleHoldsUnderEveryTransform() throws {
        let ring = try #require(PathCombine.combine([circle(0, 0, 100), circle(25, 25, 50)], .cutOut))
        let moved = ring.offsetBy(dx: 40, dy: -12)
        #expect(moved.ringCount == 2)
        #expect(moved.containsInside(CGPoint(x: 90, y: 38)) == false)
        let bigger = ring.scaled(x: 2, y: 2)
        #expect(bigger.ringCount == 2)
        #expect(bigger.containsInside(CGPoint(x: 100, y: 100)) == false)
        #expect(bigger.containsInside(CGPoint(x: 100, y: 12)))
        let turned = ring.transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
        #expect(turned.ringCount == 2)
        #expect(turned.containsInside(CGPoint(x: 0, y: 0)) == false, "the middle is still empty")
    }

    @Test("A hole survives being saved and opened again")
    func theHoleSurvivesTheDisk() throws {
        let ring = try #require(PathCombine.combine([circle(0, 0, 100), circle(25, 25, 50)], .cutOut))
        let data = try JSONEncoder().encode(ring)
        let back = try JSONDecoder().decode(PathContent.self, from: data)
        #expect(back.ringStarts == ring.ringStarts)
        #expect(back.anchors == ring.anchors)
        #expect(back.containsInside(CGPoint(x: 50, y: 50)) == false)
        #expect(back.containsInside(CGPoint(x: 50, y: 6)))
    }

    @Test("A path written before rings existed comes back as one ring")
    func oldFilesStillOpen() throws {
        let json = #"{"anchors":[{"point":[0,0],"kind":"corner"},"#
            + #"{"point":[10,0],"kind":"corner"},"#
            + #"{"point":[10,10],"kind":"corner"}],"closed":true}"#
        let back = try JSONDecoder().decode(PathContent.self, from: Data(json.utf8))
        #expect(back.ringStarts.isEmpty)
        #expect(back.ringCount == 1)
        #expect(back.segments.count == 3)
    }

    // MARK: What each command is called

    @Test("Every operation has a plain name and says what it does")
    func everyOperationIsNamed() {
        #expect(PathCombine.Operation.allCases.count == 4)
        #expect(PathCombine.Operation.join.title == "Join")
        #expect(PathCombine.Operation.cutOut.title == "Cut Out")
        #expect(PathCombine.Operation.keepOverlap.title == "Keep Overlap")
        #expect(PathCombine.Operation.dropOverlap.title == "Drop Overlap")
        for operation in PathCombine.Operation.allCases {
            #expect(!operation.title.isEmpty)
            #expect(!operation.title.contains("—"))
        }
    }
}
