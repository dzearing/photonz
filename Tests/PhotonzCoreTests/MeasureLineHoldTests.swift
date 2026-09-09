import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Holding ⇧ while dragging one end of a measurement.
///
/// The rule under test: the key holds the caliper on the line it is on, so the
/// foot you have hold of slides along that line and nothing else moves. The
/// pointer may wander anywhere; only where it lands ALONG the line is taken.
@Suite("Measure line hold")
struct MeasureLineHoldTests {

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.0001) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    // MARK: The line a caliper is on

    @Test func aHorizontalCaliperIsHeldOnTheRowItsFeetSitOn() {
        let line = MeasureLineHold(mode: .horizontal, through: CGPoint(x: 300, y: 200))
        // The pointer has wandered 60px down while pulling the foot right.
        #expect(close(line.project(CGPoint(x: 450, y: 260)), CGPoint(x: 450, y: 200)))
    }

    @Test func aVerticalCaliperIsHeldOnTheColumnItsFeetSitOn() {
        let line = MeasureLineHold(mode: .vertical, through: CGPoint(x: 200, y: 300))
        #expect(close(line.project(CGPoint(x: 260, y: 450)), CGPoint(x: 200, y: 450)))
    }

    @Test func aPointAlreadyOnTheLineIsLeftExactlyWhereItIs() {
        let line = MeasureLineHold(mode: .horizontal, through: CGPoint(x: 300, y: 200))
        let p = CGPoint(x: 512, y: 200)
        #expect(close(line.project(p), p))
    }

    /// The two readings of "the line it is on" — the line through both feet,
    /// and the mode's own axis — can never disagree for a caliper this app can
    /// draw, because its feet are always level. This pins that down.
    @Test func theLineThroughBothFeetIsTheModesOwnAxis() {
        let a = CGPoint(x: 120, y: 200), b = CGPoint(x: 480, y: 200)
        let throughFeet = MeasureLineHold(mode: .horizontal, through: a, and: b)
        let modeAxis = MeasureLineHold(mode: .horizontal, through: b)
        let p = CGPoint(x: 300, y: 999)
        #expect(close(throughFeet.project(p), modeAxis.project(p)))
    }

    /// Written for the caliper this app cannot draw yet: if a measurement is
    /// ever free to sit at an angle, holding it straight has to mean sliding
    /// along THAT angle, not along the nearest axis.
    @Test func aDiagonalLineIsHeldAtItsOwnAngle() {
        let line = MeasureLineHold(mode: .horizontal,
                                   through: CGPoint(x: 100, y: 100), and: CGPoint(x: 300, y: 300))
        // A point 100 off the 45° line, square to it: the foot of the
        // perpendicular is the midpoint between where it is and the line.
        #expect(close(line.project(CGPoint(x: 300, y: 100)), CGPoint(x: 200, y: 200)))
        #expect(close(line.project(CGPoint(x: 500, y: 500)), CGPoint(x: 500, y: 500)))
    }

    /// A measurement whose feet are on top of each other has no direction of
    /// its own, so the mode's axis has to answer for it rather than the maths
    /// dividing by nothing.
    @Test func twoFeetInTheSamePlaceFallBackToTheModesAxis() {
        let p = CGPoint(x: 240, y: 180)
        let line = MeasureLineHold(mode: .vertical, through: p, and: p)
        #expect(close(line.project(CGPoint(x: 999, y: 400)), CGPoint(x: 240, y: 400)))
    }

    // MARK: Pressing and letting go of the key mid drag

    @Test func withoutTheKeyThereIsNoHeldLine() {
        #expect(MeasureLineHold.holding(nil, shiftDown: false, mode: .horizontal,
                                        fixedFoot: CGPoint(x: 300, y: 200)) == nil)
    }

    @Test func pressingTheKeyTakesTheLineTheCaliperIsOnAtThatMoment() throws {
        // The caliper was placed on row 200 but the free drag has already
        // carried it to row 213; the key must take 213, not 200.
        let held = try #require(MeasureLineHold.holding(nil, shiftDown: true, mode: .horizontal,
                                                        fixedFoot: CGPoint(x: 300, y: 213)))
        #expect(close(held.project(CGPoint(x: 600, y: 500)), CGPoint(x: 600, y: 213)))
    }

    @Test func aHeldLineDoesNotDriftWhileTheKeyStaysDown() throws {
        let first = try #require(MeasureLineHold.holding(nil, shiftDown: true, mode: .horizontal,
                                                         fixedFoot: CGPoint(x: 300, y: 213)))
        // The pointer keeps moving, so the foot the caller reads keeps moving
        // too; the line it latched must not follow it.
        let still = try #require(MeasureLineHold.holding(first, shiftDown: true, mode: .horizontal,
                                                         fixedFoot: CGPoint(x: 300, y: 400)))
        #expect(still == first)
    }

    @Test func lettingTheKeyGoHandsTheDragBack() {
        let held = MeasureLineHold(mode: .horizontal, through: CGPoint(x: 300, y: 213))
        #expect(MeasureLineHold.holding(held, shiftDown: false, mode: .horizontal,
                                        fixedFoot: CGPoint(x: 300, y: 213)) == nil)
    }

    @Test func pressingTheKeyAgainAfterLettingItGoTakesTheNewLine() throws {
        let again = try #require(MeasureLineHold.holding(nil, shiftDown: true, mode: .horizontal,
                                                         fixedFoot: CGPoint(x: 300, y: 460)))
        #expect(close(again.project(CGPoint(x: 120, y: 20)), CGPoint(x: 120, y: 460)))
    }

    // MARK: What the magnets are still allowed to do

    @Test func aMagnetAlongTheHeldLineIsKeptAndStaysLit() {
        let line = MeasureLineHold(mode: .horizontal, through: CGPoint(x: 100, y: 200))
        // The pointer was at x 452 and caught a vertical edge at x 448.
        let landing = MeasureLineHold.landing(snapped: CGPoint(x: 448, y: 201),
                                              guideX: 448, guideY: nil, on: line)
        #expect(close(landing.point, CGPoint(x: 448, y: 200)))
        #expect(landing.guideX == 448)
        #expect(landing.guideY == nil)
    }

    @Test func aMagnetThatWouldPullTheFootOffTheHeldLineIsNotTakenOrLit() {
        let line = MeasureLineHold(mode: .horizontal, through: CGPoint(x: 100, y: 200))
        // A horizontal edge at y 240 caught the foot: off the held line, so it
        // is dropped, and the yellow guide must not claim a landing that is
        // not drawn.
        let landing = MeasureLineHold.landing(snapped: CGPoint(x: 452, y: 240),
                                              guideX: nil, guideY: 240, on: line)
        #expect(close(landing.point, CGPoint(x: 452, y: 200)))
        #expect(landing.guideY == nil)
    }

    @Test func aMagnetExactlyOnTheHeldLineKeepsItsGuide() {
        let line = MeasureLineHold(mode: .horizontal, through: CGPoint(x: 100, y: 200))
        let landing = MeasureLineHold.landing(snapped: CGPoint(x: 452, y: 200),
                                              guideX: nil, guideY: 200, on: line)
        #expect(close(landing.point, CGPoint(x: 452, y: 200)))
        #expect(landing.guideY == 200)
    }

    @Test func withNoHeldLineTheLandingIsWhateverTheMagnetsSaid() {
        let landing = MeasureLineHold.landing(snapped: CGPoint(x: 452, y: 240),
                                              guideX: 452, guideY: 240, on: nil)
        #expect(close(landing.point, CGPoint(x: 452, y: 240)))
        #expect(landing.guideX == 452)
        #expect(landing.guideY == 240)
    }

    // MARK: Which direction a held line names

    @Test func aHeldLineNamesTheDirectionItRunsIn() {
        #expect(MeasureLineHold(mode: .horizontal, through: CGPoint(x: 300, y: 200)).axis == .horizontal)
        #expect(MeasureLineHold(mode: .vertical, through: CGPoint(x: 300, y: 200)).axis == .vertical)
    }

    /// The direction has to come off the line that is DRAWN, not off whatever
    /// mode happened to be passed in when it was built: while a caliper is
    /// being placed the mode is exactly the thing being decided.
    @Test func theDirectionIsReadFromTheLineNotTheModeItWasBuiltWith() {
        let line = MeasureLineHold(mode: .horizontal,
                                   through: CGPoint(x: 200, y: 100), and: CGPoint(x: 200, y: 400))
        #expect(line.axis == .vertical)
    }

    // MARK: Placing a caliper — the key holds the direction it is going in

    @Test func withoutTheKeyPlacingKeepsChoosingTheDirectionFromThePointer() {
        let footA = CGPoint(x: 300, y: 200)
        let across = MeasureLineHold.placing(nil, shiftDown: false, from: footA,
                                             toward: CGPoint(x: 500, y: 240))
        #expect(across.mode == .horizontal)
        #expect(close(across.foot2, CGPoint(x: 500, y: 200)))
        #expect(across.hold == nil)

        let down = MeasureLineHold.placing(nil, shiftDown: false, from: footA,
                                           toward: CGPoint(x: 320, y: 600))
        #expect(down.mode == .vertical)
        #expect(close(down.foot2, CGPoint(x: 300, y: 600)))
    }

    /// The user's case: a baseline, then the top of a line of text that is off
    /// to one side. Free, the caliper flips to measuring across the moment the
    /// pointer leaves the column; held, it keeps measuring down and only takes
    /// how far down the pointer got.
    @Test func theHeldDirectionSurvivesThePointerCrossingIntoTheOther() {
        let footA = CGPoint(x: 300, y: 200)
        // Pressed while the caliper is measuring DOWN.
        let locked = MeasureLineHold.placing(nil, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 320, y: 600))
        #expect(locked.mode == .vertical)

        // Now travel well past the crossover: 700 across against 300 down, so a
        // free placement would call this horizontal twice over.
        let travelled = MeasureLineHold.placing(locked.hold, shiftDown: true, from: footA,
                                                toward: CGPoint(x: 1000, y: 500))
        #expect(MeasureContent.dominantAxis(from: footA, to: CGPoint(x: 1000, y: 500)) == .horizontal)
        #expect(travelled.mode == .vertical)
        #expect(close(travelled.foot2, CGPoint(x: 300, y: 500)))
        #expect(travelled.hold == locked.hold)
    }

    @Test func theHeldDirectionDoesNotDriftWhileTheKeyStaysDown() throws {
        let footA = CGPoint(x: 300, y: 200)
        let first = MeasureLineHold.placing(nil, shiftDown: true, from: footA,
                                            toward: CGPoint(x: 500, y: 240))
        let held = try #require(first.hold)
        for pointer in [CGPoint(x: 310, y: 900), CGPoint(x: 299, y: -400), CGPoint(x: 800, y: 800)] {
            let next = MeasureLineHold.placing(held, shiftDown: true, from: footA, toward: pointer)
            #expect(next.hold == held)
            #expect(next.mode == .horizontal)
            #expect(close(next.foot2, CGPoint(x: pointer.x, y: 200)))
        }
    }

    /// Pressing the key partway takes what is on SCREEN at that moment, not
    /// what the placement started out as.
    @Test func pressingTheKeyAfterTheCrossoverLocksWhatIsOnScreenThen() {
        let footA = CGPoint(x: 300, y: 200)
        // Free so far, and the pointer has already crossed into measuring down.
        let free = MeasureLineHold.placing(nil, shiftDown: false, from: footA,
                                           toward: CGPoint(x: 340, y: 700))
        #expect(free.mode == .vertical)
        // Key goes down here.
        let locked = MeasureLineHold.placing(free.hold, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 340, y: 700))
        #expect(locked.mode == .vertical)
        // And it stays down as the pointer walks a long way across.
        let travelled = MeasureLineHold.placing(locked.hold, shiftDown: true, from: footA,
                                                toward: CGPoint(x: 1200, y: 420))
        #expect(travelled.mode == .vertical)
        #expect(close(travelled.foot2, CGPoint(x: 300, y: 420)))
    }

    @Test func lettingTheKeyGoChoosesFromThePointerAgainWithNoJump() {
        let footA = CGPoint(x: 300, y: 200)
        let locked = MeasureLineHold.placing(nil, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 500, y: 240))
        let pointer = CGPoint(x: 320, y: 900)
        let released = MeasureLineHold.placing(locked.hold, shiftDown: false, from: footA,
                                               toward: pointer)
        #expect(released.hold == nil)
        // Exactly what a placement that had never been held would do with the
        // pointer where it actually is: no lag, nothing carried over.
        let neverHeld = MeasureLineHold.placing(nil, shiftDown: false, from: footA, toward: pointer)
        #expect(released.mode == neverHeld.mode)
        #expect(close(released.foot2, neverHeld.foot2))
    }

    @Test func theKeyBeforeTheDirectionExistsHoldsTheDirectionThePointerIsAlreadyGivingIt() {
        // Foot A and the pointer in the same place name no direction at all;
        // the rule must still answer, and answer the same way a free placement
        // does, rather than dividing by nothing.
        let footA = CGPoint(x: 300, y: 200)
        let stationary = MeasureLineHold.placing(nil, shiftDown: true, from: footA, toward: footA)
        #expect(stationary.mode == MeasureContent.dominantAxis(from: footA, to: footA))
        #expect(close(stationary.foot2, footA))
    }

    // MARK: What the magnets are still allowed to do while placing

    @Test func aMagnetAlongTheHeldDirectionStillCatchesWhilePlacing() {
        let footA = CGPoint(x: 300, y: 200)
        let locked = MeasureLineHold.placing(nil, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 500, y: 240))
        // The pointer went off to the side and caught a vertical edge at x 448.
        let caught = MeasureLineHold.placing(locked.hold, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 448, y: 620),
                                             guideX: 448, guideY: nil)
        #expect(close(caught.foot2, CGPoint(x: 448, y: 200)))
        #expect(caught.guideX == 448)
        #expect(caught.guideY == nil)
    }

    @Test func aMagnetAcrossTheHeldDirectionIsNotTakenOrLitWhilePlacing() {
        let footA = CGPoint(x: 300, y: 200)
        let locked = MeasureLineHold.placing(nil, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 500, y: 240))
        let caught = MeasureLineHold.placing(locked.hold, shiftDown: true, from: footA,
                                             toward: CGPoint(x: 520, y: 620),
                                             guideX: nil, guideY: 620)
        #expect(close(caught.foot2, CGPoint(x: 520, y: 200)))
        #expect(caught.guideY == nil)
    }

    /// Free placement is untouched by any of this: it flattens the far foot the
    /// way it always did and hands the magnets’ guides straight back.
    @Test func withoutTheKeyPlacingHandsTheMagnetsGuidesStraightBack() {
        let placed = MeasureLineHold.placing(nil, shiftDown: false, from: CGPoint(x: 300, y: 200),
                                             toward: CGPoint(x: 448, y: 240),
                                             guideX: 448, guideY: 240)
        #expect(close(placed.foot2, CGPoint(x: 448, y: 200)))
        #expect(placed.guideX == 448)
        #expect(placed.guideY == 240)
    }
}
