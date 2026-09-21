import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the Export sheet is allowed to say about a recording before it is
/// written.
///
/// The picture sheet can be exact because it really encodes the picture. A
/// recording cannot: weighing a GIF IS writing the GIF. So these rules decide
/// where an honest number exists and where the sheet has to say what it knows
/// instead of guessing.
@Suite("What a recording export says it will weigh")
struct RecordingExportTests {

    /// Eight seconds of 1280 × 800, four megabytes on disk, nothing edited.
    private var whole: RecordingExport.Source {
        RecordingExport.Source(sourceDuration: 8, keptDuration: 8,
                               sourceSize: CGSize(width: 1280, height: 800),
                               cropSize: nil, fileBytes: 4_194_304, isEdited: false)
    }

    /// The same recording trimmed to its middle four seconds.
    private var trimmed: RecordingExport.Source {
        RecordingExport.Source(sourceDuration: 8, keptDuration: 4,
                               sourceSize: CGSize(width: 1280, height: 800),
                               cropSize: nil, fileBytes: 4_194_304, isEdited: true)
    }

    // MARK: - What it weighs

    /// An untouched recording saved as MP4 at the top choice is a verbatim file
    /// copy, so the number is not an estimate at all: it is the file that is
    /// already there.
    @Test func anUntouchedVideoAtTheTopChoiceIsWeighedExactly() {
        #expect(RecordingExport.weight(format: .mp4, quality: .high, source: whole)
                == .exact(4_194_304))
    }

    /// The two choices below it are asking for a SMALLER file than the one on
    /// disk, which cannot be done without encoding, so even an untouched
    /// recording is re-encoded there and the number falls with the choice. That
    /// is the whole point of the row: the commonest reason to export a
    /// recording nobody has touched is that the one on disk is too big to send.
    @Test func theChoicesBelowTheTopMakeAnUntouchedRecordingSmaller() {
        let high = RecordingExport.weight(format: .mp4, quality: .high, source: whole)
        let standard = RecordingExport.weight(format: .mp4, quality: .standard, source: whole)
        let small = RecordingExport.weight(format: .mp4, quality: .small, source: whole)
        #expect(high == .exact(4_194_304))
        #expect(standard == .about(2_457_600))
        #expect(small == .about(864_000))
    }

    /// A trimmed one is re-encoded whichever choice is showing: half the
    /// seconds, about half the budget.
    @Test func atrimmedVideoIsWeighedFromTheBudgetItIsGiven() {
        #expect(RecordingExport.weight(format: .mp4, quality: .standard, source: trimmed)
                == .about(1_228_800))
    }

    /// A crop takes pixels out of every frame, so the budget comes down with
    /// the pixel count. Quarter the pixels of a 1280 × 800: 640 × 400.
    @Test func aCropBringsTheEstimateDownWithThePixels() {
        var cropped = trimmed
        cropped.cropSize = CGSize(width: 640, height: 400)
        #expect(RecordingExport.weight(format: .mp4, quality: .standard, source: cropped)
                == .about(307_200))
    }

    /// The other half of the estimate: a budget is a ceiling, and an encoder
    /// never pads. A recording of a still screen costs a fraction of any
    /// budget, and what the sheet says is what the recording itself already
    /// costs per second and per pixel rather than the ceiling.
    @Test func anEasyRecordingIsWeighedByWhatItCostsNotByTheCeiling() {
        var easy = trimmed
        easy.fileBytes = 40_000
        // Half the seconds of a 40 KB recording, nowhere near the 1.2 MB the
        // Standard budget would have allowed.
        #expect(RecordingExport.weight(format: .mp4, quality: .standard, source: easy)
                == .about(20_000))
    }

    /// A GIF or a HEIC is re-encoded frame by frame into a different container
    /// entirely. Nothing about the MP4 on disk predicts that, so the sheet says
    /// it does not know rather than showing a number it made up.
    @Test func anAnimatedPictureIsNotWeighedAtAll() {
        #expect(RecordingExport.weight(format: .gif, quality: .standard, source: whole) == .unknown)
        #expect(RecordingExport.weight(format: .heic, quality: .high, source: trimmed) == .unknown)
    }

    /// A recording with nothing left in it has nothing to weigh.
    @Test func aRecordingWithNothingKeptHasNoEstimate() {
        var empty = trimmed
        empty.keptDuration = 0
        #expect(RecordingExport.weight(format: .mp4, quality: .standard, source: empty) == .unknown)
    }

    /// A recording whose length on disk has not loaded yet still has an
    /// estimate, because the budget does not need it: what we are about to ASK
    /// the encoder for is known whether or not the source has been measured.
    /// This is what gives a document assembled out of nothing a number too.
    @Test func aRecordingWithNoMeasuredSourceStillHasTheBudget() {
        var unmeasured = trimmed
        unmeasured.sourceDuration = 0
        unmeasured.fileBytes = 0
        #expect(RecordingExport.weight(format: .mp4, quality: .standard, source: unmeasured)
                == .about(1_228_800))
    }

    /// A recording the app has not managed to measure on disk cannot be claimed
    /// as an exact copy, so the top choice says nothing rather than nought.
    @Test func aRecordingWithNoFileSizeHasNoExactAnswer() {
        var weightless = whole
        weightless.fileBytes = 0
        #expect(RecordingExport.weight(format: .mp4, quality: .high, source: weightless)
                == .unknown)
    }

    // MARK: - The size line

    /// The same shape of line the picture sheet uses: what the file is called,
    /// then what it costs.
    @Test func theSizeLineNamesTheFormatAndThenTheSize() {
        #expect(RecordingExport.sizeLine(format: .mp4, quality: .high, source: whole)
                == "MP4 Video · 4.0 MB")
    }

    /// An estimate says so out loud. A number presented as a fact and then
    /// missed by a megabyte is worse than one that admitted what it was.
    @Test func anEstimateSaysAbout() {
        #expect(RecordingExport.sizeLine(format: .mp4, quality: .standard, source: trimmed)
                == "MP4 Video · about 1.2 MB")
    }

    /// Where there is no honest number the line says that in plain words, in
    /// the same place, rather than going blank or spinning forever.
    @Test func noHonestNumberIsSaidInWords() {
        #expect(RecordingExport.sizeLine(format: .gif, quality: .standard, source: whole)
                == "Animated GIF · size not known until it is written")
        #expect(RecordingExport.sizeLine(format: .heic, quality: .standard, source: whole)
                == "Animated HEIC · size not known until it is written")
    }

    // MARK: - The shape line

    /// Where the picture sheet writes the pixel size, a recording writes its
    /// pixel size and how long it runs.
    @Test func theShapeLineSaysPixelsAndLength() {
        #expect(RecordingExport.shapeLine(format: .mp4, quality: .high, source: whole)
                == "1280 × 800 px · 0:08")
    }

    /// A choice that re-encodes says the frame rate too, because the choice is
    /// about to change it. A copy says nothing about frame rate, because
    /// nothing touched it.
    @Test func aReEncodedVideoSaysItsFrameRateAndACopyDoesNot() {
        #expect(RecordingExport.shapeLine(format: .mp4, quality: .standard, source: whole)
                == "1280 × 800 px · 30 fps · 0:08")
        #expect(RecordingExport.shapeLine(format: .mp4, quality: .small, source: whole)
                == "960 × 600 px · 30 fps · 0:08")
    }

    /// Trimmed, it says what is kept OF what there is, so the trim is legible
    /// on the sheet that is about to write it.
    @Test func aTrimmedRecordingSaysWhatIsKeptOfWhatThereIs() {
        #expect(RecordingExport.shapeLine(format: .mp4, quality: .standard, source: trimmed)
                == "1280 × 800 px · 30 fps · 0:04 of 0:08")
    }

    /// A cropped MP4 goes out at the crop's size, which is what the line says.
    @Test func aCroppedVideoSaysTheCropsSize() {
        var cropped = whole
        cropped.cropSize = CGSize(width: 640, height: 400)
        cropped.isEdited = true
        #expect(RecordingExport.shapeLine(format: .mp4, quality: .standard, source: cropped)
                == "640 × 400 px · 30 fps · 0:08")
    }

    /// A GIF is capped by the quality preset, so the line moves when the preset
    /// does. That is the whole visible consequence of the Quality row, so it
    /// has to be on the sheet.
    @Test func ananimatedPictureSaysTheSizeAndRateThePresetGivesIt() {
        #expect(RecordingExport.shapeLine(format: .gif, quality: .standard, source: whole)
                == "800 × 500 px · 15 fps · 0:08")
        #expect(RecordingExport.shapeLine(format: .gif, quality: .small, source: whole)
                == "480 × 300 px · 10 fps · 0:08")
        #expect(RecordingExport.shapeLine(format: .heic, quality: .high, source: whole)
                == "1280 × 800 px · 24 fps · 0:08")
    }

    /// A recording smaller than the cap is never blown up to reach it.
    @Test func asmallRecordingIsNotUpscaledToTheCap() {
        var small = whole
        small.sourceSize = CGSize(width: 400, height: 300)
        #expect(RecordingExport.shapeLine(format: .gif, quality: .high, source: small)
                == "400 × 300 px · 24 fps · 0:08")
    }

    /// Nothing measured yet: the line says the length it knows and leaves the
    /// pixels out rather than writing "0 × 0 px".
    @Test func aRecordingWithNoPixelsYetLeavesThePixelsOut() {
        var unmeasured = whole
        unmeasured.sourceSize = .zero
        #expect(RecordingExport.shapeLine(format: .mp4, quality: .standard, source: unmeasured)
                == "0:08")
    }

    // MARK: - Which formats carry which controls

    /// All three formats have a preset worth choosing. MP4 joined the day its
    /// export stopped asking for "highest quality, whatever that comes to" and
    /// started asking for a number of bits per second.
    @Test func everyFormatOffersAQuality() {
        #expect(RecordingExport.offersQuality(.mp4))
        #expect(RecordingExport.offersQuality(.gif))
        #expect(RecordingExport.offersQuality(.heic))
    }

    /// And each choice says who it is for, in words about where the file is
    /// going rather than about the encoder.
    @Test func eachChoiceSaysWhoItIsFor() {
        #expect(RecordingExport.purposeLine(format: .mp4, quality: .small)
                == VideoExportQuality.small.purpose(for: .mp4))
        #expect(RecordingExport.purposeLine(format: .mp4, quality: .high)
                != RecordingExport.purposeLine(format: .gif, quality: .high))
    }

    /// The order the formats sit in on the sheet: the one nearly everybody
    /// wants first.
    @Test func theFormatsAreOfferedVideoFirst() {
        #expect(RecordingExport.formats == [.mp4, .gif, .heic])
    }

    /// Short names for the segmented row, full names for the size line, so the
    /// row stays narrow and the line stays readable.
    @Test func eachFormatHasAShortNameForTheRow() {
        #expect(RecordingExport.shortName(.mp4) == "MP4")
        #expect(RecordingExport.shortName(.gif) == "GIF")
        #expect(RecordingExport.shortName(.heic) == "HEIC")
    }

    /// The presets get short names for the segmented row. The numbers they
    /// stand for are not lost: they are written live on the line underneath, so
    /// the preset shows what it does instead of spelling it.
    @Test func eachPresetHasAShortNameForTheRow() {
        #expect(VideoExportQuality.high.shortLabel == "High")
        #expect(VideoExportQuality.standard.shortLabel == "Standard")
        #expect(VideoExportQuality.small.shortLabel == "Small")
        // The long labels stay, for the menu that predates the sheet.
        #expect(VideoExportQuality.standard.label.contains("15 fps"))
    }

    /// The fast path: an MP4 of an unedited recording is a file copy, so it is
    /// instant and byte-identical. Anything else is a re-encode, and the sheet
    /// knows which it is about to ask for.
    @Test func onlyAnUneditedVideoAtTheTopChoiceCopiesInsteadOfReEncoding() {
        #expect(RecordingExport.copiesVerbatim(format: .mp4, quality: .high, source: whole))
        #expect(!RecordingExport.copiesVerbatim(format: .mp4, quality: .standard, source: whole))
        #expect(!RecordingExport.copiesVerbatim(format: .mp4, quality: .small, source: whole))
        #expect(!RecordingExport.copiesVerbatim(format: .mp4, quality: .high, source: trimmed))
        #expect(!RecordingExport.copiesVerbatim(format: .gif, quality: .high, source: whole))
    }

    /// What the file is called when the save box opens: the recording's own
    /// name with the chosen format's extension, never the extension it had.
    @Test func theSuggestedNameTakesTheChosenFormatsExtension() {
        #expect(RecordingExport.suggestedFileName(recording: "Recording 2026-09-19.mp4",
                                                  format: .gif) == "Recording 2026-09-19.gif")
        #expect(RecordingExport.suggestedFileName(recording: "Recording 2026-09-19.mp4",
                                                  format: .mp4) == "Recording 2026-09-19.mp4")
        #expect(RecordingExport.suggestedFileName(recording: "clip", format: .heic) == "clip.heic")
    }
}
