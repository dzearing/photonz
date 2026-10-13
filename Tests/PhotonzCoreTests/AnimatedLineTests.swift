import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// One rule for every animated line on the timeline (the user, 2026-10-13):
/// a click on a dot picks it, a click on the line between two dots picks that
/// segment, a Command-click on the line adds a dot, and a plain click never
/// adds one. Shift adds to the pick. Written before `AnimatedLine`.
@Suite("Animated line")
struct AnimatedLineTests {

    /// Three dots on a straight line across, 100 points apart, with the line
    /// running on before the first and after the last.
    static func line() -> AnimatedLine {
        AnimatedLine(dots: [CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 20), CGPoint(x: 300, y: 50)],
                     segments: [[CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 20)],
                                [CGPoint(x: 200, y: 20), CGPoint(x: 300, y: 50)]],
                     before: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)],
                     after: [CGPoint(x: 300, y: 50), CGPoint(x: 400, y: 50)])
    }

    // MARK: - What is under the pointer

    @Test func aDotWinsOverTheLineItSitsOn() {
        let line = Self.line()
        #expect(line.hit(CGPoint(x: 101, y: 51)) == .dot(0))
        #expect(line.hit(CGPoint(x: 200, y: 22)) == .dot(1))
    }

    @Test func thePointerOnTheLineBetweenTwoDotsIsThatSegment() {
        let line = Self.line()
        // Half way along the first segment, a couple of points off it.
        #expect(line.hit(CGPoint(x: 150, y: 37)) == .segment(0))
        #expect(line.hit(CGPoint(x: 250, y: 33)) == .segment(1))
    }

    @Test func theLineBeforeTheFirstDotAndAfterTheLastIsNotASegment() {
        let line = Self.line()
        #expect(line.hit(CGPoint(x: 40, y: 51)) == .beyond)
        #expect(line.hit(CGPoint(x: 360, y: 49)) == .beyond)
    }

    @Test func emptyLaneIsNothing() {
        let line = Self.line()
        #expect(line.hit(CGPoint(x: 150, y: 80)) == nil)
        #expect(line.hit(CGPoint(x: 360, y: 10)) == nil)
    }

    @Test func whereOnTheLineAPressLandsIsTheNearestPointOnIt() {
        let line = Self.line()
        let landed = line.nearestPoint(to: CGPoint(x: 150, y: 30))
        #expect(abs(landed.x - 150) < 6)
        #expect(abs(landed.y - 35) < 3)
    }

    // MARK: - What a click does

    @Test func aPlainClickPicksAndNeverAdds() {
        #expect(AnimatedLine.action(for: .dot(1), command: false, shift: false) == .pickDot(1, extending: false))
        #expect(AnimatedLine.action(for: .segment(0), command: false, shift: false)
                == .pickSegment(0, extending: false))
        #expect(AnimatedLine.action(for: .beyond, command: false, shift: false) == .clear)
        #expect(AnimatedLine.action(for: nil, command: false, shift: false) == .clear)
    }

    @Test func shiftAddsToThePick() {
        #expect(AnimatedLine.action(for: .dot(1), command: false, shift: true) == .pickDot(1, extending: true))
        #expect(AnimatedLine.action(for: .segment(1), command: false, shift: true)
                == .pickSegment(1, extending: true))
    }

    @Test func commandClickOnTheLineAddsADot() {
        #expect(AnimatedLine.action(for: .segment(0), command: true, shift: false) == .addDot)
        #expect(AnimatedLine.action(for: .beyond, command: true, shift: false) == .addDot)
        // Off the line it adds nothing.
        #expect(AnimatedLine.action(for: nil, command: true, shift: false) == .clear)
    }

    @Test func commandClickOnADotAddsItToThePickRatherThanAddingADotOnTopOfIt() {
        #expect(AnimatedLine.action(for: .dot(2), command: true, shift: false) == .pickDot(2, extending: true))
    }

    // MARK: - The pick

    @Test func aPlainPickReplacesDotsAndSegmentsAlike() {
        var pick = AnimatedLinePick<Int>(dots: [1, 2], segments: [0])
        pick.pick(dot: 3, extending: false)
        #expect(pick == AnimatedLinePick(dots: [3], segments: []))
        pick.pick(segment: 1, extending: false)
        #expect(pick == AnimatedLinePick(dots: [], segments: [1]))
    }

    @Test func anExtendingPickTogglesOneThingAndKeepsTheRest() {
        var pick = AnimatedLinePick<Int>(dots: [1], segments: [])
        pick.pick(segment: 0, extending: true)
        #expect(pick == AnimatedLinePick(dots: [1], segments: [0]))
        pick.pick(dot: 2, extending: true)
        #expect(pick == AnimatedLinePick(dots: [1, 2], segments: [0]))
        pick.pick(dot: 1, extending: true)
        #expect(pick == AnimatedLinePick(dots: [2], segments: [0]))
        pick.pick(segment: 0, extending: true)
        #expect(pick == AnimatedLinePick(dots: [2], segments: []))
        #expect(!pick.isEmpty)
        pick.pick(dot: 2, extending: true)
        #expect(pick.isEmpty)
    }

    // MARK: - A closed key lane

    /// A key lane drawn shut is the same kind of line, flat: its diamonds
    /// along the middle and a straight segment between each pair, with no
    /// line either side (the lane's own click takes that).
    @Test func aClosedLaneIsAFlatLineOfItsKeys() {
        let line = AnimatedLine(flatThrough: [300, 100, 200], atY: 9)
        #expect(line.dots == [CGPoint(x: 100, y: 9), CGPoint(x: 200, y: 9), CGPoint(x: 300, y: 9)])
        #expect(line.segments.count == 2)
        #expect(line.before.isEmpty && line.after.isEmpty)
        #expect(line.hit(CGPoint(x: 150, y: 11)) == .segment(0))
        #expect(line.hit(CGPoint(x: 203, y: 9)) == .dot(1))
        #expect(line.hit(CGPoint(x: 50, y: 9)) == nil)
        #expect(AnimatedLine(flatThrough: [40], atY: 9).segments.isEmpty)
    }
}
