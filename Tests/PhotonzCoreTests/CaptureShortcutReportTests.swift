import Testing
@testable import PhotonzCore

@Suite("What Photonz says about its capture shortcuts")
struct CaptureShortcutReportTests {

    private typealias Report = CaptureShortcutReport

    private func state(_ rows: [Report.Row], _ hotkey: CaptureHotkey) -> CaptureShortcutReport.State? {
        rows.first { $0.hotkey == hotkey }?.state
    }

    @Test func everyShortcutHasARowWithItsKeys() {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [])
        #expect(rows.map(\.hotkey) == [.captureFullScreen, .captureRegion, .record, .editLastCapture,
                                       .stopRecording, .toggleHistory])
        #expect(rows.map(\.keys) == ["⇧⌘3", "⇧⌘4", "⇧⌘5", "⇧⌘6", "⌃⇧F5", "⇧⌘H"])
        #expect(rows.allSatisfy { $0.state == .ready })
    }

    @Test func macOSHoldingAKeyReadsAsThatOnItsOwnRow() {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [.fullScreen, .region, .toolbar, .touchBar])
        #expect(state(rows, .captureFullScreen) == .heldByMacOS)
        #expect(state(rows, .captureRegion) == .heldByMacOS)
        #expect(state(rows, .record) == .heldByMacOS)
        #expect(state(rows, .editLastCapture) == .heldByMacOS)
        #expect(state(rows, .toggleHistory) == .ready)
    }

    @Test func aRegistrationThatFailedReadsAsThat() {
        let rows = Report.rows(answersHere: true, failed: [.toggleHistory], macOSHolds: [])
        #expect(state(rows, .toggleHistory) == .notRegistered)
        #expect(state(rows, .captureRegion) == .ready)
    }

    @Test func anotherCopyAnsweringIsNotAProblem() {
        let rows = Report.rows(answersHere: false, failed: [], macOSHolds: [])
        #expect(rows.allSatisfy { $0.state == .anotherPhotonz })
        #expect(Report.problems(in: rows).isEmpty)
        #expect(Report.notice(for: rows, alreadyTold: []) == nil)
    }

    @Test func nothingWrongSaysNothing() {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [])
        #expect(Report.notice(for: rows, alreadyTold: []) == nil)
    }

    @Test func aProblemIsSaidOnceAndNotAgain() {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [.region])
        let notice = Report.notice(for: rows, alreadyTold: [])
        #expect(notice != nil)
        #expect(Report.notice(for: rows, alreadyTold: Report.problems(in: rows)) == nil)
    }

    @Test func aNewProblemIsSaidEvenWithAnOldOneStanding() {
        let before = Report.rows(answersHere: true, failed: [], macOSHolds: [.region])
        let now = Report.rows(answersHere: true, failed: [], macOSHolds: [.region, .fullScreen])
        #expect(Report.notice(for: now, alreadyTold: Report.problems(in: before)) != nil)
    }

    @Test func screenshotKeysHeldByMacOSSayThePictureMissesTheClipboard() throws {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [.fullScreen, .region])
        let notice = try #require(Report.notice(for: rows, alreadyTold: []))
        #expect(notice.title == "macOS holds ⇧⌘3, ⇧⌘4")
        #expect(notice.detail == "Those shots skip the clipboard")
    }

    @Test func oneScreenshotKeyIsSaidInTheSingular() throws {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [.region])
        let notice = try #require(Report.notice(for: rows, alreadyTold: []))
        #expect(notice.title == "macOS holds ⇧⌘4")
        #expect(notice.detail == "That shot skips the clipboard")
    }

    @Test func aKeyThatTakesNoPictureDoesNotMentionTheClipboard() throws {
        let rows = Report.rows(answersHere: true, failed: [], macOSHolds: [.toolbar])
        let notice = try #require(Report.notice(for: rows, alreadyTold: []))
        #expect(!notice.detail.contains("clipboard"))
    }

    @Test func aFailedRegistrationNamesTheKeys() throws {
        let rows = Report.rows(answersHere: true, failed: [.captureRegion], macOSHolds: [])
        let notice = try #require(Report.notice(for: rows, alreadyTold: []))
        #expect(notice.title == "⇧⌘4 didn't register")
        #expect(notice.detail == "Another app may hold it")
    }

    /// The chrome budget: a toast line is a label of 30 characters at most.
    @Test func noNoticeRunsPastTheChromeBudget() throws {
        let everyMacKey = SystemScreenshotShortcuts.Shortcut.allCases
        let cases: [[Report.Row]] = [
            Report.rows(answersHere: true, failed: [], macOSHolds: everyMacKey),
            Report.rows(answersHere: true, failed: Set(CaptureHotkey.allCases), macOSHolds: []),
            Report.rows(answersHere: true, failed: [.record, .toggleHistory], macOSHolds: []),
            Report.rows(answersHere: true, failed: [.toggleHistory], macOSHolds: [.toolbar, .touchBar]),
        ]
        for rows in cases {
            let notice = try #require(Report.notice(for: rows, alreadyTold: []))
            #expect(notice.title.count <= 30, "\(notice.title)")
            #expect(notice.detail.count <= 30, "\(notice.detail)")
            #expect(notice.action.count <= 30)
        }
    }

    @Test func everyStateReadsInPlainWords() {
        for state in [Report.State.ready, .heldByMacOS, .notRegistered, .anotherPhotonz] {
            #expect(!state.label.isEmpty && state.label.count <= 30)
        }
    }
}
