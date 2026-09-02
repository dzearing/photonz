import Foundation
import PhotonzCore
import Testing

@Suite("Copy confirmation")
struct CopyConfirmationTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func aFreshNoticeIsLiveAndFadesWithinAboutTwoSeconds() {
        // A glance, not a banner: it closes the loop on the key and gets out
        // of the way before the next thing you do.
        let notice = CopyConfirmation(subject: .specList(measurements: 3), shownAt: t0)
        #expect(notice.isLive(at: t0))
        #expect(notice.isLive(at: t0.addingTimeInterval(1.0)))
        #expect(!notice.isLive(at: t0.addingTimeInterval(CopyConfirmation.lifetime)))
        #expect(!notice.isLive(at: t0.addingTimeInterval(60)))
        #expect(CopyConfirmation.lifetime >= 1 && CopyConfirmation.lifetime <= 2)
    }

    @Test func aNoticeShownBeforeItsClockIsNotLiveYet() {
        // A clock that runs backwards (sleep, NTP) must not pin it on screen.
        let notice = CopyConfirmation(subject: .measurements(count: 1), shownAt: t0)
        #expect(!notice.isLive(at: t0.addingTimeInterval(-5)))
    }

    @Test func reshowingRestartsTheClock() {
        // Two quick copies keep one pill up that fades from the LAST copy,
        // and its line follows the latest copy.
        let first = CopyConfirmation(subject: .measurements(count: 1), shownAt: t0)
        let second = first.reshown(as: .specList(measurements: 2), at: t0.addingTimeInterval(1.2))
        #expect(second.subject == .specList(measurements: 2))
        #expect(second.isLive(at: t0.addingTimeInterval(2.0)))
        #expect(!first.isLive(at: t0.addingTimeInterval(2.0)))
        #expect(second != first)
    }

    @Test func theTitleIsOneWordAndTheLineSaysWhatWasCopied() {
        // The lead is the verdict; the line says what landed on the clipboard
        // so a spec list and a single row read differently.
        #expect(CopyConfirmation(subject: .specList(measurements: 3), shownAt: t0).title == "Copied")
        #expect(CopyConfirmation(subject: .measurements(count: 1), shownAt: t0).title == "Copied")
        #expect(CopyConfirmation(subject: .specList(measurements: 3), shownAt: t0).detail
                == "Spec list with 3 measurements")
        #expect(CopyConfirmation(subject: .specList(measurements: 1), shownAt: t0).detail
                == "Spec list with 1 measurement")
        #expect(CopyConfirmation(subject: .measurements(count: 1), shownAt: t0).detail
                == "1 measurement")
        #expect(CopyConfirmation(subject: .measurements(count: 2), shownAt: t0).detail
                == "2 measurements")
    }

    @Test func aSpecListWithEveryRowHiddenSaysSo() {
        // The panel menu can copy a list whose rows are all hidden: the header
        // still lands, so the copy did something, and the line must not lie
        // about a count.
        let notice = CopyConfirmation(subject: .specList(measurements: 0), shownAt: t0)
        #expect(notice.detail == "Spec list with no visible measurements")
    }

    @Test func noLineCarriesAnEmDash() {
        for subject in [CopyConfirmation.Subject.specList(measurements: 0),
                        .specList(measurements: 4), .measurements(count: 1), .measurements(count: 5)] {
            let notice = CopyConfirmation(subject: subject, shownAt: t0)
            #expect(!notice.detail.contains("—"))
            #expect(!notice.detail.isEmpty)
        }
    }
}
