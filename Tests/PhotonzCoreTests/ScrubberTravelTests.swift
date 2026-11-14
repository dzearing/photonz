import CoreGraphics
import Testing
@testable import PhotonzCore

/// Where a scrub bar's knob sits for a moment, and which moment a press on
/// the bar means (`ScrubberTravel`): the knob travels half a knob in from each
/// end, the way a Mac slider's does, so it never hangs over the times beside
/// the bar (the user, 2026-11-14: "the slider covers up the time label").
@Suite struct ScrubberTravelTests {
    private let bar = ScrubberTravel(width: 400, knobWidth: 26)

    @Test func theKnobRestsInsideTheBarAtBothEnds() {
        #expect(bar.x(at: 0) == 13)
        #expect(bar.x(at: 1) == 387)
        #expect(bar.x(at: 0) - 13 >= 0)
        #expect(bar.x(at: 1) + 13 <= 400)
    }

    @Test func theMiddleIsTheMiddle() {
        #expect(bar.x(at: 0.5) == 200)
    }

    @Test func aMomentOutsideTheVideoSitsAtTheEnd() {
        #expect(bar.x(at: -0.2) == bar.x(at: 0))
        #expect(bar.x(at: 1.4) == bar.x(at: 1))
    }

    /// A press lands exactly where the knob would be drawn for it, so a click
    /// on the bar never jumps half a knob.
    @Test func aPressMeansTheMomentTheKnobWouldShowThere() {
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(abs(bar.fraction(atX: bar.x(at: fraction)) - fraction) < 1e-9)
        }
    }

    @Test func aPressPastTheTravelIsTheEnd() {
        #expect(bar.fraction(atX: 0) == 0)
        #expect(bar.fraction(atX: 12) == 0)
        #expect(bar.fraction(atX: 390) == 1)
        #expect(bar.fraction(atX: 400) == 1)
    }

    @Test func theTravelIsTheBarLessAKnob() {
        #expect(bar.travel == 374)
    }

    /// A bar narrower than its knob still answers, and never divides by nothing.
    @Test func aBarNarrowerThanItsKnobStaysSane() {
        let tiny = ScrubberTravel(width: 10, knobWidth: 26)
        #expect(tiny.travel == 0)
        #expect(tiny.x(at: 0.7) == 5)
        let fraction = tiny.fraction(atX: 8)
        #expect(fraction >= 0 && fraction <= 1)
    }
}
