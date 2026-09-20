import Foundation
import Testing

@testable import PhotonzCore

@Suite("What a save says while it runs and when it lands")
struct SaveFeedbackTests {

    @Test("A save that lands inside the quiet window never shows progress")
    func shortSavesStayQuiet() {
        #expect(!SaveFeedback.showsProgress(afterRunningFor: 0))
        #expect(!SaveFeedback.showsProgress(afterRunningFor: 0.2))
        #expect(!SaveFeedback.showsProgress(afterRunningFor: SaveFeedback.quietWindow - 0.01))
    }

    @Test("A save still running past the quiet window shows progress")
    func longSavesShowProgress() {
        #expect(SaveFeedback.showsProgress(afterRunningFor: SaveFeedback.quietWindow))
        #expect(SaveFeedback.showsProgress(afterRunningFor: 4))
    }

    // Half a second is the threshold the task asked for, and the number is the
    // whole behaviour, so it is pinned rather than left to drift.
    @Test("The quiet window is about half a second")
    func quietWindowIsHalfASecond() {
        #expect(SaveFeedback.quietWindow == 0.5)
    }

    @Test("Both lines name the recording")
    func bothLinesNameTheRecording() {
        #expect(SaveFeedback.progressTitle(for: "Clip.mov") == "Saving Clip.mov\u{2026}")
        #expect(SaveFeedback.savedMessage(for: "Clip.mov") == "Clip.mov saved")
    }

    // A recording's real name is a date and a time and runs to about forty
    // characters. The toast is a small panel, so a long name is shortened from
    // the MIDDLE: the front says which recording and the tail keeps the
    // extension, which is the part that says what kind of file was written.
    @Test("A long name is shortened from the middle, keeping both ends")
    func longNamesShortenInTheMiddle() {
        let long = "Screen Recording 2026-09-19 at 10.14.22.mov"
        let short = SaveFeedback.shortName(long)
        #expect(short.count <= SaveFeedback.nameLimit)
        #expect(short.hasPrefix("Screen Recording"))
        #expect(short.hasSuffix(".mov"))
        #expect(short.contains("\u{2026}"))
    }

    @Test("A name that already fits is left exactly alone")
    func shortNamesAreUntouched() {
        #expect(SaveFeedback.shortName("Clip.mov") == "Clip.mov")
        let exactly = String(repeating: "a", count: SaveFeedback.nameLimit)
        #expect(SaveFeedback.shortName(exactly) == exactly)
    }

    @Test("The messages shorten the name they are given")
    func messagesShortenTheName() {
        let long = "Screen Recording 2026-09-19 at 10.14.22.mov"
        #expect(SaveFeedback.savedMessage(for: long).contains("\u{2026}"))
        #expect(SaveFeedback.savedMessage(for: long).hasSuffix(".mov saved"))
        #expect(SaveFeedback.progressTitle(for: long).hasPrefix("Saving Screen Recording"))
    }

    // The encoder is only part of a commit: the bytes still have to be
    // preserved and swapped in afterwards. A bar that reaches 100% and then
    // sits there is the same silence this whole change is about, so the
    // encoder's own progress is scaled to leave the tail for that work.
    @Test("Encoder progress leaves room for the work after the encode")
    func encodeProgressLeavesRoomForTheSwap() {
        #expect(SaveFeedback.commitFraction(encoded: 0) == 0)
        #expect(SaveFeedback.commitFraction(encoded: 1) < 1)
        #expect(SaveFeedback.commitFraction(encoded: 1) >= 0.9)
        #expect(SaveFeedback.commitFraction(encoded: 0.5) < SaveFeedback.commitFraction(encoded: 0.9))
    }

    @Test("Nonsense from the encoder is clamped rather than drawn")
    func encoderNonsenseIsClamped() {
        #expect(SaveFeedback.commitFraction(encoded: -3) == 0)
        #expect(SaveFeedback.commitFraction(encoded: 12) == SaveFeedback.commitFraction(encoded: 1))
        #expect(SaveFeedback.commitFraction(encoded: .nan) == 0)
    }
}
