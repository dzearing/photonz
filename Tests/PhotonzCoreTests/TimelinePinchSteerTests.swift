import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// User 2026-09-28: fingers spreading up and down grow the rows, side to side
/// open out time, and on the slant both.
struct TimelinePinchSteerTests {

    // Two fingers on the trackpad, in its points, spread a given way from a
    // starting shape of one finger at (60, 40) and the other off to one side.
    private func fingers(dx: CGFloat, dy: CGFloat) -> [CGPoint] {
        [CGPoint(x: 60, y: 40), CGPoint(x: 60 + dx, y: 40 + dy)]
    }

    @Test func sidewaysSpreadIsHorizontal() {
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 30, dy: 10),
                                             to: fingers(dx: 45, dy: 12)) == .horizontal)
    }

    @Test func upAndDownSpreadIsVertical() {
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 10, dy: 30),
                                             to: fingers(dx: 11, dy: 44)) == .vertical)
    }

    @Test func aSlantedSpreadIsDiagonal() {
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 20, dy: 20),
                                             to: fingers(dx: 30, dy: 30)) == .diagonal)
    }

    @Test func aSqueezeReadsTheSameAsASpread() {
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 45, dy: 12),
                                             to: fingers(dx: 30, dy: 10)) == .horizontal)
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 10, dy: 44),
                                             to: fingers(dx: 10, dy: 30)) == .vertical)
    }

    /// The fingers' own slant says nothing: thumb low left and finger high
    /// right, pulled apart sideways, is still a sideways pinch.
    @Test func itIsTheChangeNotTheShapeThatCounts() {
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 30, dy: -30),
                                             to: fingers(dx: 42, dy: -31)) == .horizontal)
    }

    @Test func whichFingerIsFirstDoesNotMatter() {
        let start = fingers(dx: 30, dy: 10)
        let now = fingers(dx: 45, dy: 12)
        #expect(TimelinePinchSteer.direction(from: start, to: [now[1], now[0]]) == .horizontal)
    }

    @Test func aboutThirtyFiveDegreesIsTheEdgeOfEachWay() {
        // 30° off the horizontal is still sideways, 40° is on the slant.
        let thirty = CGPoint(x: 10 * cos(CGFloat.pi / 6), y: 10 * sin(CGFloat.pi / 6))
        let forty = CGPoint(x: 10 * cos(40 * CGFloat.pi / 180), y: 10 * sin(40 * CGFloat.pi / 180))
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 20, dy: 20),
                                             to: fingers(dx: 20 + thirty.x, dy: 20 + thirty.y)) == .horizontal)
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 20, dy: 20),
                                             to: fingers(dx: 20 + forty.x, dy: 20 + forty.y)) == .diagonal)
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 20, dy: 20),
                                             to: fingers(dx: 20 + thirty.y, dy: 20 + thirty.x)) == .vertical)
    }

    @Test func tooSmallAMoveHasNoDirectionYet() {
        #expect(TimelinePinchSteer.direction(from: fingers(dx: 30, dy: 10),
                                             to: fingers(dx: 32, dy: 10)) == nil)
        #expect(TimelinePinchSteer.direction(from: [CGPoint(x: 1, y: 1)], to: fingers(dx: 40, dy: 0)) == nil)
    }

    @Test func eachDirectionPicksItsAxes() {
        #expect(TimelinePinchDirection.horizontal.axes == .time)
        #expect(TimelinePinchDirection.vertical.axes == .rows)
        #expect(TimelinePinchDirection.diagonal.axes == .both)
    }

    @Test func optionAndShiftStillForceAnAxis() {
        #expect(TimelinePinchAxes.forced(option: true, shift: false) == .time)
        #expect(TimelinePinchAxes.forced(option: false, shift: true) == .rows)
        #expect(TimelinePinchAxes.forced(option: true, shift: true) == .both)
        #expect(TimelinePinchAxes.forced(option: false, shift: false) == nil)
    }

    // MARK: A pinch, start to finish

    @Test func holdsTheFirstNudgesUntilTheFingersSayWhichWayThenAppliesThemAll() {
        var steer = TimelinePinchSteer()
        steer.touched(fingers(dx: 30, dy: 10))
        steer.begin()
        #expect(steer.magnified(by: 1.01, forced: nil) == nil)
        steer.touched(fingers(dx: 33, dy: 10))
        #expect(steer.magnified(by: 1.01, forced: nil) == nil)
        steer.touched(fingers(dx: 37, dy: 10))
        let first = steer.magnified(by: 1.02, forced: nil)
        #expect(first?.axes == .time)
        #expect(abs((first?.factor ?? 0) - 1.01 * 1.01 * 1.02) < 1e-9)
        // From here on every nudge goes straight through.
        steer.touched(fingers(dx: 40, dy: 10))
        let next = steer.magnified(by: 1.03, forced: nil)
        #expect(next?.axes == .time)
        #expect(abs((next?.factor ?? 0) - 1.03) < 1e-9)
    }

    @Test func oncePickedItNeverFlipsUntilTheFingersLift() {
        var steer = TimelinePinchSteer()
        steer.touched(fingers(dx: 10, dy: 30))
        steer.begin()
        steer.touched(fingers(dx: 10, dy: 40))
        #expect(steer.magnified(by: 1.05, forced: nil)?.axes == .rows)
        // The fingers wander sideways, far: still rows.
        steer.touched(fingers(dx: 60, dy: 42))
        #expect(steer.magnified(by: 1.05, forced: nil)?.axes == .rows)
        #expect(steer.decided == .rows)
        steer.end()
        steer.touched([])
        #expect(steer.decided == nil)

        // The next pinch decides afresh.
        steer.touched(fingers(dx: 30, dy: 10))
        steer.begin()
        steer.touched(fingers(dx: 42, dy: 10))
        #expect(steer.magnified(by: 1.05, forced: nil)?.axes == .time)
    }

    @Test func withoutTouchesItFallsBackToBothAfterAFewPercent() {
        var steer = TimelinePinchSteer()
        steer.begin()
        #expect(steer.magnified(by: 1.02, forced: nil) == nil)
        #expect(steer.magnified(by: 1.02, forced: nil) == nil)
        let applied = steer.magnified(by: 1.02, forced: nil)
        #expect(applied?.axes == .both)
        #expect(abs((applied?.factor ?? 0) - 1.02 * 1.02 * 1.02) < 1e-9)
        #expect(steer.magnified(by: 1.02, forced: nil)?.axes == .both)
    }

    @Test func aSqueezeFallsBackTheSameWay() {
        var steer = TimelinePinchSteer()
        steer.begin()
        #expect(steer.magnified(by: 0.98, forced: nil) == nil)
        #expect(steer.magnified(by: 0.98, forced: nil) == nil)
        #expect(steer.magnified(by: 0.98, forced: nil)?.axes == .both)
    }

    @Test func aModifierGoesStraightThroughWithWhateverWasHeld() {
        var steer = TimelinePinchSteer()
        steer.begin()
        #expect(steer.magnified(by: 1.01, forced: nil) == nil)
        let applied = steer.magnified(by: 1.02, forced: .rows)
        #expect(applied?.axes == .rows)
        #expect(abs((applied?.factor ?? 0) - 1.01 * 1.02) < 1e-9)
        #expect(steer.magnified(by: 1.02, forced: .time)?.axes == .time)
    }

    @Test func aPinchTooSmallToDecideIsStillAppliedWhenTheFingersLift() {
        var steer = TimelinePinchSteer()
        steer.touched(fingers(dx: 30, dy: 10))
        steer.begin()
        steer.touched(fingers(dx: 32, dy: 10))
        #expect(steer.magnified(by: 1.01, forced: nil) == nil)
        let flushed = steer.end()
        #expect(flushed?.axes == .time)
        #expect(abs((flushed?.factor ?? 0) - 1.01) < 1e-9)
        #expect(steer.end() == nil)
    }

    @Test func aPinchWithNoHeldMovementFlushesNothing() {
        var steer = TimelinePinchSteer()
        steer.begin()
        #expect(steer.end() == nil)
    }

    @Test func aThirdFingerIsNotAPinchToRead() {
        var steer = TimelinePinchSteer()
        steer.touched(fingers(dx: 30, dy: 10) + [CGPoint(x: 90, y: 20)])
        steer.begin()
        steer.touched(fingers(dx: 45, dy: 10) + [CGPoint(x: 90, y: 20)])
        #expect(steer.magnified(by: 1.02, forced: nil) == nil)
        #expect(steer.magnified(by: 1.02, forced: nil) == nil)
        #expect(steer.magnified(by: 1.02, forced: nil)?.axes == .both)
    }

    /// A pinch that begins before any touch has been seen reads its start from
    /// the first two fingers it gets.
    @Test func touchesThatArriveAfterTheStartStillSteer() {
        var steer = TimelinePinchSteer()
        steer.begin()
        #expect(steer.magnified(by: 1.01, forced: nil) == nil)
        steer.touched(fingers(dx: 10, dy: 30))
        steer.touched(fingers(dx: 10, dy: 38))
        #expect(steer.magnified(by: 1.01, forced: nil)?.axes == .rows)
    }

    @Test func nonsenseFactorsAreIgnored() {
        var steer = TimelinePinchSteer()
        steer.begin()
        #expect(steer.magnified(by: 0, forced: nil) == nil)
        #expect(steer.magnified(by: .nan, forced: .time) == nil)
        #expect(steer.end() == nil)
    }
}
