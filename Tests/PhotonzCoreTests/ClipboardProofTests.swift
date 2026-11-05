import Testing
@testable import PhotonzCore

@Suite("Checking a copy reached the clipboard")
struct ClipboardProofTests {

    @Test func aReadablePictureIsHeld() {
        #expect(ClipboardProof.verdict(wrote: 7, now: 7, pictureReadable: true, elapsed: 0.1) == .held)
    }

    @Test func aPictureNotReadableYetIsWaitedForUntilTheLimit() {
        #expect(ClipboardProof.verdict(wrote: 7, now: 7, pictureReadable: false, elapsed: 1.9) == .keepWaiting)
        #expect(ClipboardProof.verdict(wrote: 7, now: 7, pictureReadable: false, elapsed: 2.0) == .missed)
    }

    @Test func aPictureThatTurnsUpLateStillCounts() {
        #expect(ClipboardProof.verdict(wrote: 7, now: 7, pictureReadable: true, elapsed: 9) == .held)
    }

    /// A newer copy, here or in any other app, is the person moving on. Nothing
    /// is wrong and saying so would be a false alarm.
    @Test func aClipboardThatHasMovedOnIsNeverAMiss() {
        #expect(ClipboardProof.verdict(wrote: 7, now: 8, pictureReadable: false, elapsed: 5) == .movedOn)
        #expect(ClipboardProof.verdict(wrote: 7, now: 8, pictureReadable: true, elapsed: 0) == .movedOn)
    }

    @Test func theNoticeFitsTheChromeBudget() {
        #expect(ClipboardProof.noticeTitle.count <= 30)
        #expect(ClipboardProof.noticeDetail.count <= 30)
        #expect(ClipboardProof.noticeAction == "Copy Again")
    }
}
