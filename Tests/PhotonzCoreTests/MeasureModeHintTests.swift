import Foundation
import PhotonzCore
import Testing

@Suite("Measure mode hint")
struct MeasureModeHintTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func aFreshHintIsLiveAndThenFadesAfterAboutTwoSeconds() {
        // The chip is a toast, not a banner: long enough to read one line,
        // short enough that a fluent user never waits for it.
        let hint = MeasureModeHint(mode: .distance, shownAt: t0)
        #expect(hint.isLive(at: t0))
        #expect(hint.isLive(at: t0.addingTimeInterval(1.9)))
        #expect(!hint.isLive(at: t0.addingTimeInterval(hint.lifetime)))
        #expect(!hint.isLive(at: t0.addingTimeInterval(60)))
        #expect(hint.lifetime == MeasureModeHint.lifetime)
        #expect(MeasureModeHint.lifetime >= 1.5 && MeasureModeHint.lifetime <= 3)
    }

    @Test func aLongerLineStaysALittleLongerButNeverBecomesABanner() {
        // Size's line carries the [ and ] tip and is the longest; it gets a
        // little longer than the base stay. Distance's line needs no more.
        let size = MeasureModeHint(mode: .size, shownAt: t0)
        let distance = MeasureModeHint(mode: .distance, shownAt: t0)
        #expect(size.lifetime > distance.lifetime)
        #expect(size.lifetime <= MeasureModeHint.longestLifetime)
        #expect(size.isLive(at: t0.addingTimeInterval(2.1)))
        #expect(!size.isLive(at: t0.addingTimeInterval(MeasureModeHint.longestLifetime)))
        for mode in MeasureToolMode.allCases {
            let hint = MeasureModeHint(mode: mode, shownAt: t0)
            #expect(hint.lifetime >= MeasureModeHint.lifetime)
            #expect(hint.lifetime <= MeasureModeHint.longestLifetime)
        }
    }

    @Test func aHintShownBeforeItsClockIsNotLiveYet() {
        // Defensive: a clock that runs backwards (sleep, NTP) must not pin the
        // chip on screen forever.
        let hint = MeasureModeHint(mode: .size, shownAt: t0)
        #expect(!hint.isLive(at: t0.addingTimeInterval(-5)))
    }

    @Test func reshowingReplacesTheHintAndRestartsItsClock() {
        // Press I three times quickly: the chip should stay up, naming the mode
        // you landed on, and only start fading from the LAST press.
        let first = MeasureModeHint(mode: .distance, shownAt: t0)
        let second = first.reshown(as: .size, at: t0.addingTimeInterval(1.5))
        #expect(second.mode == .size)
        #expect(second.isLive(at: t0.addingTimeInterval(3.0)))
        #expect(!first.isLive(at: t0.addingTimeInterval(3.0)))
        #expect(second != first)
    }

    @Test func everyModeNamesItselfAndSaysWhatAClickDoes() {
        for mode in MeasureToolMode.allCases {
            let hint = MeasureModeHint(mode: mode, shownAt: t0)
            #expect(hint.title == mode.title)
            #expect(!hint.detail.isEmpty)
            // The title is set in its own weight, so the detail must not repeat it.
            #expect(!hint.detail.hasPrefix(mode.title))
            #expect(!hint.detail.contains("—"))
            #expect(!hint.title.contains("—"))
        }
    }
}
