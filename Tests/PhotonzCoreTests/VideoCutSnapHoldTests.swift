import Testing
import Foundation
import CoreGraphics
@testable import PhotonzCore

/// Holding the key that frees a trim handle from the cuts it would catch on.
///
/// The band this exists to reopen is eight points wide on each side of every
/// cut: while the magnet is on, those positions cannot be reached by dragging
/// at all, because anything the hand puts there is taken by the cut. Holding
/// the key turns the magnet off for as long as it is down, exactly the way ⌘
/// frees the canvas magnets.
///
/// The interesting half is what happens when the key comes UP mid-drag, which
/// the canvas never has to answer because it latches its magnets off for the
/// rest of the drag. Here catching comes back, so the cut after this one still
/// works, and the cuts the handle is standing next to are muted until the hand
/// has moved clearly away from them — otherwise letting go of the key would
/// yank the handle onto the very cut it was just freed from.
@Suite("A trim handle freed from the cuts")
struct VideoCutSnapHoldTests {

    /// One second is ten points, so every distance below reads straight off
    /// the screen: a point of travel is a tenth of a second.
    private let pointsPerSecond: CGFloat = 10

    /// An eighteen second recording cut in three: catchable at 0, 6, 12, 18.
    private let cuts: [TimeInterval] = [0, 6, 12, 18]

    /// Seconds at a number of points before the cut at six.
    private func shortOfSix(_ points: CGFloat) -> TimeInterval {
        6 - TimeInterval(points / pointsPerSecond)
    }

    private func drag(_ hold: inout VideoCutSnapHold, to seconds: TimeInterval,
                      freed: Bool = false) -> TimeInterval {
        hold.landing(for: seconds, catchingOn: cuts,
                     pointsPerSecond: pointsPerSecond, freed: freed)
    }

    // MARK: - The key is down

    @Test("With the key held the handle lands exactly where the hand put it")
    func freedHandleIgnoresTheCut() {
        var hold = VideoCutSnapHold()
        let landed = drag(&hold, to: shortOfSix(3), freed: true)
        #expect(abs(landed - shortOfSix(3)) < 1e-9)
        #expect(hold.caught == nil)
    }

    @Test("Three points short of a cut is reachable, which it is not without the key")
    func theBandIsReachableOnlyWhenFreed() {
        var caught = VideoCutSnapHold()
        #expect(drag(&caught, to: shortOfSix(3)) == 6)

        var freed = VideoCutSnapHold()
        #expect(abs(drag(&freed, to: shortOfSix(3), freed: true) - shortOfSix(3)) < 1e-9)
    }

    @Test("Pressing the key after the drag has started lets go of the cut already caught")
    func pressingTheKeyMidDragFreesAHeldCut() {
        var hold = VideoCutSnapHold()
        #expect(drag(&hold, to: shortOfSix(5)) == 6)
        #expect(hold.caught == 6)

        let landed = drag(&hold, to: shortOfSix(5), freed: true)
        #expect(abs(landed - shortOfSix(5)) < 1e-9)
        #expect(hold.caught == nil)
    }

    @Test("A freed drag passes every cut it crosses without catching one")
    func aFreedDragCrossesCutsUntouched() {
        var hold = VideoCutSnapHold()
        for points in stride(from: CGFloat(60), through: -60, by: -3) {
            let want = 6 - TimeInterval(points / pointsPerSecond)
            #expect(abs(drag(&hold, to: want, freed: true) - want) < 1e-9)
            #expect(hold.caught == nil)
        }
    }

    // MARK: - The key comes up

    @Test("Letting the key go beside a cut does not yank the handle onto it")
    func lettingGoOfTheKeyDoesNotJump() {
        var hold = VideoCutSnapHold()
        _ = drag(&hold, to: shortOfSix(3), freed: true)

        let landed = drag(&hold, to: shortOfSix(3))
        #expect(abs(landed - shortOfSix(3)) < 1e-9)
        #expect(hold.caught == nil)
    }

    @Test("A handle parked in the band stays there while the hand wobbles")
    func theParkedHandleSurvivesAWobble() {
        var hold = VideoCutSnapHold()
        _ = drag(&hold, to: shortOfSix(3), freed: true)
        for points in [CGFloat(3), 4, 2, 5, 3] {
            let landed = drag(&hold, to: shortOfSix(points))
            #expect(abs(landed - shortOfSix(points)) < 1e-9)
            #expect(hold.caught == nil)
        }
    }

    @Test("The cut comes back once the hand has moved clearly away from it")
    func theCutCatchesAgainAfterTheHandLeaves() {
        var hold = VideoCutSnapHold()
        _ = drag(&hold, to: shortOfSix(3), freed: true)
        _ = drag(&hold, to: shortOfSix(3))
        #expect(hold.caught == nil)

        // Twenty four points clear: past the sixteen it takes to let go.
        _ = drag(&hold, to: shortOfSix(24))
        // And back onto it.
        #expect(drag(&hold, to: shortOfSix(5)) == 6)
        #expect(hold.caught == 6)
    }

    @Test("A cut still inside the hold distance stays muted")
    func aCutStaysMutedInsideTheHoldDistance() {
        var hold = VideoCutSnapHold()
        _ = drag(&hold, to: shortOfSix(3), freed: true)
        _ = drag(&hold, to: shortOfSix(3))
        // Fourteen points away is outside the reach but inside the hold, so
        // the cut is not free to take the handle again yet.
        _ = drag(&hold, to: shortOfSix(14))
        #expect(abs(drag(&hold, to: shortOfSix(5)) - shortOfSix(5)) < 1e-9)
        #expect(hold.caught == nil)
    }

    @Test("The NEXT cut along still catches after the key comes up")
    func anotherCutCatchesStraightAway() {
        var hold = VideoCutSnapHold()
        _ = drag(&hold, to: shortOfSix(3), freed: true)
        _ = drag(&hold, to: shortOfSix(3))
        #expect(hold.caught == nil)

        // Onwards to the cut at twelve, five points short of it.
        #expect(drag(&hold, to: 12 - TimeInterval(5 / pointsPerSecond)) == 12)
        #expect(hold.caught == 12)
    }

    @Test("A cut the hand was never near is not muted by the key at all")
    func onlyCutsWithinReachAreMuted() {
        var hold = VideoCutSnapHold()
        // The key goes down and up well clear of everything.
        _ = drag(&hold, to: 9, freed: true)
        _ = drag(&hold, to: 9)
        #expect(drag(&hold, to: shortOfSix(5)) == 6)
        #expect(hold.caught == 6)
    }

    // MARK: - Nothing changed for a drag that never touches the key

    @Test("Without the key the hold behaves exactly as the magnet always did")
    func anUntouchedDragIsUnchanged() {
        var hold = VideoCutSnapHold()
        // Five points short: inside the reach, so it catches.
        #expect(drag(&hold, to: shortOfSix(5)) == 6)
        // Twelve points short: outside the reach, inside the hold, still caught.
        #expect(drag(&hold, to: shortOfSix(12)) == 6)
        // Twenty four points short: a deliberate move, so it lets go.
        #expect(abs(drag(&hold, to: shortOfSix(24)) - shortOfSix(24)) < 1e-9)
        #expect(hold.caught == nil)
    }

    @Test("A track with no width on screen catches nothing, key or no key")
    func noTrackWidthMeansNoMagnet() {
        var hold = VideoCutSnapHold()
        #expect(hold.landing(for: 5.99, catchingOn: cuts,
                             pointsPerSecond: 0, freed: false) == 5.99)
        #expect(hold.caught == nil)
        #expect(hold.landing(for: 5.99, catchingOn: cuts,
                             pointsPerSecond: 0, freed: true) == 5.99)
        #expect(hold.caught == nil)
    }

    @Test("The magnet's own numbers are untouched by any of this")
    func theNumbersAreUnchanged() {
        #expect(VideoCutSnapping.catchDistance == 8)
        #expect(VideoCutSnapping.releaseDistance == 16)
    }
}
