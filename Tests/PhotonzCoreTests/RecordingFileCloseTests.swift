import Foundation
import PhotonzCore
import Testing

/// A stopped recording's file goes into history only once it is finished.
///
/// Measured 2026-10-10 on the probe: with sound from the Mac and the
/// microphone together, macOS takes about 0.45 s per recorded second to close
/// the file (1.8 s for 3 s, 20 s for 45 s). The recorder used to stop waiting
/// 400 ms after the stream stopped and hand the file over anyway, so history
/// listed a file with no recording in it yet: its tile went blank and opening
/// it said it could not be opened, or was still being saved.
@Suite("A recording's file is handed over only once it is finished")
struct RecordingFileCloseTests {
    private let unfinished = RecordingFileFacts(exists: true, byteCount: 4_000_000)
    private func finished(_ bytes: Int = 4_200_000) -> RecordingFileFacts {
        RecordingFileFacts(exists: true, byteCount: bytes, durationMS: 3_000)
    }

    @Test func aWriterThatHasSaidNothingIsNotFinishedHoweverLongItTakes() {
        var close = RecordingFileClose(recordedSeconds: 3)
        for second in stride(from: 0.4, through: 30, by: 0.5) {
            close.looked(at: unfinished, after: second)
        }
        #expect(close.verdict == nil)
    }

    @Test func theWriterSayingItIsDoneFinishesIt() {
        var close = RecordingFileClose(recordedSeconds: 45)
        close.looked(at: unfinished, after: 0.5)
        close.writerFinished()
        #expect(close.verdict == .finished)
    }

    @Test func theWriterFailingEndsTheWait() {
        var close = RecordingFileClose(recordedSeconds: 10)
        close.writerFailed()
        #expect(close.verdict == .failed)
    }

    @Test func aFileThatReadsCompleteTwiceInARowIsFinished() {
        // The writer's own word can go missing; a file that plays and has
        // stopped changing is finished whatever it said.
        var close = RecordingFileClose(recordedSeconds: 10)
        close.looked(at: finished(), after: 1)
        #expect(close.verdict == nil)
        close.looked(at: finished(), after: 1.5)
        #expect(close.verdict == .finished)
    }

    @Test func aFileStillGrowingIsNotFinishedEvenWhenItReads() {
        var close = RecordingFileClose(recordedSeconds: 10)
        close.looked(at: finished(4_000_000), after: 1)
        close.looked(at: finished(4_100_000), after: 1.5)
        #expect(close.verdict == nil)
        close.looked(at: finished(4_100_000), after: 2)
        #expect(close.verdict == .finished)
    }

    @Test func aFileThatGoesAwayIsNotFinished() {
        var close = RecordingFileClose(recordedSeconds: 3)
        close.looked(at: finished(), after: 1)
        close.looked(at: RecordingFileFacts(exists: false), after: 1.5)
        close.looked(at: finished(), after: 2)
        #expect(close.verdict == nil)
    }

    @Test func theWaitIsGivenUpOnlyLongAfterTheFileStoppedChanging() {
        var close = RecordingFileClose(recordedSeconds: 3)
        let patience = RecordingFileClose.patience(recordedSeconds: 3)
        close.looked(at: unfinished, after: 1)
        close.looked(at: unfinished, after: 1 + patience - 1)
        #expect(close.verdict == nil)
        close.looked(at: unfinished, after: 1 + patience + 1)
        #expect(close.verdict == .gaveUp)
    }

    @Test func aFileStillBeingWrittenIsWaitedForPastThePatience() {
        var close = RecordingFileClose(recordedSeconds: 3)
        let patience = RecordingFileClose.patience(recordedSeconds: 3)
        var bytes = 1_000
        var at = 0.5
        while at < patience * 3 {
            bytes += 1_000
            close.looked(at: RecordingFileFacts(exists: true, byteCount: bytes), after: at)
            at += 0.5
        }
        #expect(close.verdict == nil)
    }

    @Test func patienceGrowsWithTheRecordingAndCoversWhatMacOSWasMeasuredTaking() {
        // 0.45 s per recorded second was measured; patience is never less than
        // the recording itself on top of a minute.
        #expect(RecordingFileClose.patience(recordedSeconds: 0) >= 60)
        #expect(RecordingFileClose.patience(recordedSeconds: 45) >= 45 * 0.45 + 60)
        #expect(RecordingFileClose.patience(recordedSeconds: 600) > RecordingFileClose.patience(recordedSeconds: 45))
    }

    @Test func theFirstVerdictStands() {
        var close = RecordingFileClose(recordedSeconds: 3)
        close.writerFailed()
        close.writerFinished()
        close.looked(at: finished(), after: 1)
        close.looked(at: finished(), after: 2)
        #expect(close.verdict == .failed)
    }
}
