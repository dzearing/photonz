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
        #expect(!hint.isLive(at: t0.addingTimeInterval(MeasureModeHint.lifetime)))
        #expect(!hint.isLive(at: t0.addingTimeInterval(60)))
        #expect(MeasureModeHint.lifetime >= 1.5 && MeasureModeHint.lifetime <= 3)
    }

    @Test func everyModeFadesOnTheSameSchedule() {
        // Every line is now one short line, so no mode earns a longer stay:
        // the Size pill used to hang around 3.5 seconds while the others left
        // at 2, which read as the app being slow rather than the line long.
        for mode in MeasureToolMode.allCases {
            let hint = MeasureModeHint(mode: mode, shownAt: t0)
            #expect(hint.isLive(at: t0.addingTimeInterval(MeasureModeHint.lifetime - 0.1)))
            #expect(!hint.isLive(at: t0.addingTimeInterval(MeasureModeHint.lifetime)))
        }
    }

    @Test func thePillReservesRoomForItsWidestLineAndStillFitsTheSmallestWindow() {
        // The legend keeps out of this box while the pill may be up, so it
        // must cover the widest of the four pills and still leave the corners
        // of the narrowest canvas free (480 pt less two 10 pt insets).
        let size = MeasureModeHint.reservedSize
        #expect(size.width >= 300 && size.width <= 420)
        #expect(size.height >= 28 && size.height <= 48)
        #expect(size.width < EditorChromeLayout.minWindowWidth - 2 * 10)
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
