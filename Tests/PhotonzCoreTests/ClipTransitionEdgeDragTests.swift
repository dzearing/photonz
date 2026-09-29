import Foundation
import PhotonzCore
import Testing

/// One end of a transition's band in a hand (user report 2026-09-29: the band
/// only changed size when the mouse came up).
///
/// What these pin down is the one promise a drag makes: **the end you took
/// hold of stays under the pointer** until the spare media or the shortest
/// length stops it, and then it stops, with the pointer moving on.
@Suite("A transition's end follows the hand")
struct ClipTransitionEdgeDragTests {

    static func drag(_ alignment: ClipTransitionAlignment, leading: Bool,
                     from ms: Int = 400, longest: Int = 2000) -> ClipTransitionEdgeDrag {
        ClipTransitionEdgeDrag(startedAtMS: ms, grabbedLeadingEdge: leading,
                               alignment: alignment, longestMS: longest)
    }

    // MARK: Which ends can be held

    @Test("Across the cut both ends are grips")
    func acrossHasTwoGrips() {
        let t = ClipTransition(kind: .dissolve, alignment: .across)
        #expect(ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: t))
        #expect(ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: t))
    }

    @Test("A band sitting to one side of its cut has one grip, the end away from the cut")
    func oneSidedHasOneGrip() {
        let before = ClipTransition(kind: .dissolve, alignment: .before)
        #expect(ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: before))
        #expect(!ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: before))
        let after = ClipTransition(kind: .dissolve, alignment: .after)
        #expect(!ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: after))
        #expect(ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: after))
    }

    @Test("A dip is drawn across its cut whatever it remembers, so both ends are grips")
    func dipHasTwoGrips() {
        let dip = ClipTransition(kind: .dipToBlack, alignment: .after)
        #expect(ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: dip))
        #expect(ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: dip))
    }

    // MARK: The end stays under the hand

    @Test("Across the cut, the end moves exactly as far as the hand, so the band grows by twice that")
    func acrossEndFollows() {
        let right = Self.drag(.across, leading: false)
        #expect(right.landing(travelledMS: 100).lengthMS == 600)
        #expect(right.landing(travelledMS: -100).lengthMS == 200)
        let left = Self.drag(.across, leading: true)
        #expect(left.landing(travelledMS: -100).lengthMS == 600)
        #expect(left.landing(travelledMS: 100).lengthMS == 200)
    }

    @Test("To one side of the cut, the far end moves as far as the hand and the band grows by that")
    func oneSidedEndFollows() {
        let after = Self.drag(.after, leading: false)
        #expect(after.landing(travelledMS: 150).lengthMS == 550)
        let before = Self.drag(.before, leading: true)
        #expect(before.landing(travelledMS: -150).lengthMS == 550)
        #expect(before.landing(travelledMS: 150).lengthMS == 250)
    }

    @Test("The end is drawn where the hand is, travelled for travelled, while nothing stops it")
    func edgeOffsetTracksHand() {
        for alignment in ClipTransitionAlignment.allCases {
            for leading in [true, false] {
                let t = ClipTransition(kind: .dissolve, lengthMS: 400, alignment: alignment)
                guard ClipTransitionEdgeDrag.canGrab(leadingEdge: leading, of: t) else { continue }
                let drag = Self.drag(alignment, leading: leading)
                let was = ClipTransitionEdgeDrag.edgeOffsetMS(of: t, leadingEdge: leading)
                for travelled in [-120, -40, 60, 140] {
                    let landing = drag.landing(travelledMS: travelled)
                    guard landing.stop == nil else { continue }
                    let now = t.withLength(landing.lengthMS)
                    let moved = ClipTransitionEdgeDrag.edgeOffsetMS(of: now, leadingEdge: leading) - was
                    #expect(abs(moved - travelled) <= 1,
                            "\(alignment) \(leading ? "start" : "end") moved \(moved) for \(travelled)")
                }
            }
        }
    }

    @Test("The end's offset from the cut counts the hold a dip spends on its colour")
    func edgeOffsetCountsHold() {
        let dip = ClipTransition(kind: .dipToBlack, lengthMS: 400, holdMS: 1000)
        #expect(ClipTransitionEdgeDrag.edgeOffsetMS(of: dip, leadingEdge: true) == -200)
        #expect(ClipTransitionEdgeDrag.edgeOffsetMS(of: dip, leadingEdge: false) == 1200)
    }

    // MARK: Where it stops

    @Test("The spare media stops it at the longest the cut can pay for, and says so")
    func stopsAtLongest() {
        let drag = Self.drag(.across, leading: false, longest: 1000)
        let landing = drag.landing(travelledMS: 5000)
        #expect(landing.lengthMS == 1000)
        #expect(landing.stop == .longest)
        #expect(drag.landing(travelledMS: 200).stop == nil)
    }

    @Test("The shortest worth having stops it the other way, and says so")
    func stopsAtShortest() {
        let landing = Self.drag(.across, leading: false).landing(travelledMS: -5000)
        #expect(landing.lengthMS == ClipTransition.shortestMS)
        #expect(landing.stop == .shortest)
    }

    @Test("Coming back from the stop, the end picks up again at the hand rather than lagging behind it")
    func noHysteresis() {
        let drag = Self.drag(.across, leading: false, longest: 1000)
        _ = drag.landing(travelledMS: 5000)
        #expect(drag.landing(travelledMS: 100).lengthMS == 600)
    }

    @Test("Where the band was already past what the cut can pay for, grabbing it does not make it jump")
    func startBeyondLongest() {
        let drag = Self.drag(.across, leading: false, from: 1200, longest: 1000)
        #expect(drag.landing(travelledMS: 0).lengthMS == 1000)
    }

    // MARK: What the bubble says

    @Test("The bubble says the length in seconds, to the ruler's own precision")
    func readoutWords() {
        #expect(ClipTransitionCopy.dragReadout(620, stop: nil, fine: false) == "0.6s")
        #expect(ClipTransitionCopy.dragReadout(620, stop: nil, fine: true) == "0.62s")
        #expect(ClipTransitionCopy.dragReadout(2000, stop: .longest, fine: false) == "2.0s max")
        #expect(ClipTransitionCopy.dragReadout(100, stop: .shortest, fine: false) == "0.1s min")
    }

    @Test("The ruler says when it is counting in hundredths, so a readout can match it")
    func rulerPrecision() {
        #expect(!MotionStripRuler(documentMS: 13_000).readsHundredths)
        #expect(MotionStripRuler(documentMS: 300).readsHundredths)
        #expect(!MotionStripRuler(cycleMS: 400).readsHundredths)
    }
}
