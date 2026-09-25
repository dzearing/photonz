import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the Export sheet says about a GIF or a HEIC, which is the one pair it
/// could never say anything about.
///
/// A video's weight is arithmetic: the budget the encoder is asked for times
/// the length (`VideoExportRecipe`). An animated picture has no budget and no
/// formula — measured, sampling eight frames and multiplying was 100 to 400 per
/// cent out, because ImageIO spends far less on a frame that follows a frame
/// like it — so the only honest number comes from writing the file. The app
/// writes it into a scratch file while the sheet is open and hands the answer
/// back here, and Export saves that very file rather than writing another
/// (`AnimatedExportWeighTests` measures why: a GIF would come out the same
/// again, a HEIC on a busy machine would not).
///
/// These are the rules for what the line says on the way there and at the end.
@Suite("What the sheet says while a GIF is being weighed")
struct RecordingExportWeighingTests {

    private var whole: RecordingExport.Source {
        RecordingExport.Source(sourceDuration: 8, keptDuration: 8,
                               sourceSize: CGSize(width: 1280, height: 800),
                               cropSize: nil, fileBytes: 4_194_304, isEdited: false)
    }

    private func weighing(_ format: RecordingFormat, _ quality: VideoExportQuality,
                          fraction: Double, bytes: Int? = nil) -> RecordingExport.Weighing {
        RecordingExport.Weighing(format: format, quality: quality,
                                 fraction: fraction, bytes: bytes)
    }

    // MARK: - On the way there

    /// While it is being written the sheet says so, and says how far along it
    /// is, so a long recording is a wait somebody can see the end of rather
    /// than a line that never changes.
    @Test func aGifBeingWeighedSaysHowFarAlongItIs() {
        let running = weighing(.gif, .standard, fraction: 0.4)
        #expect(RecordingExport.weight(format: .gif, quality: .standard, source: whole,
                                       weighing: running) == .working(0.4))
        #expect(RecordingExport.sizeLine(format: .gif, quality: .standard, source: whole,
                                         weighing: running)
                == "Animated GIF · working out the size… 40%")
    }

    /// Nothing written yet is still the same line, at nought, rather than a
    /// blank where the number goes.
    @Test func aWeighThatHasJustStartedStillSaysWhatItIsDoing() {
        #expect(RecordingExport.sizeLine(format: .heic, quality: .high, source: whole,
                                         weighing: weighing(.heic, .high, fraction: 0))
                == "Animated HEIC · working out the size… 0%")
    }

    // MARK: - The answer

    /// The file was written, so this is not an estimate: it is what the file
    /// weighs, and the same file is what Export writes.
    @Test func aWeighedGifIsExactRatherThanAbout() {
        let done = weighing(.gif, .standard, fraction: 1, bytes: 1_258_291)
        #expect(RecordingExport.weight(format: .gif, quality: .standard, source: whole,
                                       weighing: done) == .exact(1_258_291))
        #expect(RecordingExport.sizeLine(format: .gif, quality: .standard, source: whole,
                                         weighing: done) == "Animated GIF · 1.2 MB")
    }

    /// A file that came back empty is not an answer. Something went wrong
    /// writing it, and the line says what it always said rather than claiming
    /// a GIF weighs nothing.
    @Test func aWeighThatLandedOnNothingIsNotAnAnswer() {
        let empty = weighing(.gif, .standard, fraction: 1, bytes: 0)
        #expect(RecordingExport.weight(format: .gif, quality: .standard, source: whole,
                                       weighing: empty) == .unknown)
    }

    // MARK: - Whose answer it is

    /// The answer belongs to the format and the preset it was written at.
    /// Pressing Small after reading the High number must not leave the High
    /// number sitting under Small: that is the number moving with the choice,
    /// which is the whole reason the preset row is on the sheet.
    @Test func ananswerForAnotherChoiceIsNotUsed() {
        let forHigh = weighing(.gif, .high, fraction: 1, bytes: 4_000_000)
        #expect(RecordingExport.weight(format: .gif, quality: .small, source: whole,
                                       weighing: forHigh) == .unknown)
        #expect(RecordingExport.weight(format: .heic, quality: .high, source: whole,
                                       weighing: forHigh) == .unknown)
    }

    /// With nothing being weighed at all the line is what it always was. That
    /// is the honest fallback when the writing fails: the words, not a number.
    @Test func withNothingBeingWeighedTheLineIsUnchanged() {
        #expect(RecordingExport.sizeLine(format: .gif, quality: .standard, source: whole)
                == "Animated GIF · size not known until it is written")
    }

    /// A video is never weighed by writing it: it has a real budget and answers
    /// instantly, and an hour of screen would be an hour of work for a number
    /// that is already on the sheet.
    @Test func avideoKeepsItsBudgetEstimate() {
        let stray = weighing(.mp4, .standard, fraction: 1, bytes: 99)
        #expect(RecordingExport.weight(format: .mp4, quality: .standard, source: whole,
                                       weighing: stray) == .about(2_457_600))
    }

    // MARK: - The same sheet, on a document

    /// The document's sheet reads the same sentences: a GIF of what plays in
    /// the window is written and weighed exactly the same way.
    @Test func thedocumentSheetSaysTheSame() {
        let running = weighing(.gif, .small, fraction: 0.75)
        #expect(RecordingExport.sizeLine(choice: .video(.gif), quality: .small, source: whole,
                                         weighing: running)
                == "Animated GIF · working out the size… 75%")
        let done = weighing(.gif, .small, fraction: 1, bytes: 524_288)
        #expect(RecordingExport.sizeLine(choice: .video(.gif), quality: .small, source: whole,
                                         weighing: done) == "Animated GIF · 512 KB")
    }

    /// One frame as a picture is weighed the way it always was, by making the
    /// picture. A weigh running for some other format never reaches it.
    @Test func theStillIsUnaffected() {
        let stray = weighing(.gif, .high, fraction: 1, bytes: 4_000_000)
        #expect(RecordingExport.sizeLine(choice: .still, quality: .high, source: whole,
                                         stillBytes: 12_288, weighing: stray)
                == "PNG picture · 12 KB")
    }

    // MARK: - The percentage

    /// A percentage a person reads: never past a hundred, never below nought,
    /// whatever the writer reports.
    @Test func thePercentageStaysInItsRange() {
        #expect(RecordingExport.weight(format: .gif, quality: .high, source: whole,
                                       weighing: weighing(.gif, .high, fraction: 1.4))
                == .working(1))
        #expect(RecordingExport.weight(format: .gif, quality: .high, source: whole,
                                       weighing: weighing(.gif, .high, fraction: -2))
                == .working(0))
    }
}
