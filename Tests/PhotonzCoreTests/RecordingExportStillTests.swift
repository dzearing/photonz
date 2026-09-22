import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One frame of a recording leaving as a picture, on the same Export sheet the
/// video leaves through.
///
/// The video sheet took the still PNG with it when it replaced the picture
/// sheet for a document with time, so somebody wanting a frame for a bug report
/// had to export the whole video and photograph it. The picture is a fourth
/// answer on the same row, and everything the sheet says about it is here so
/// the sheet, the walk and these tests read the same sentences.
@Suite("A frame of a video, as a picture")
struct RecordingExportStillTests {

    /// Eight seconds of 1280 × 800, paused four seconds in.
    private var paused: RecordingExport.Source {
        RecordingExport.Source(sourceDuration: 8, keptDuration: 8,
                               sourceSize: CGSize(width: 1280, height: 800),
                               fileBytes: 4_194_304, isEdited: false,
                               playheadTime: 4)
    }

    // MARK: - What the row offers

    /// Four answers, the video's three in the order they were in and the
    /// picture last: a sheet on a recording is about the recording first.
    @Test func thePictureIsTheFourthAnswerOnTheSameRow() {
        #expect(RecordingExport.choices == [.video(.mp4), .video(.gif), .video(.heic), .still])
    }

    /// Named the way the other three are named, by what the file IS.
    @Test func thePictureIsNamedAfterTheFileItWrites() {
        #expect(RecordingExport.shortName(.still) == "PNG")
        #expect(RecordingExport.shortName(.video(.mp4)) == "MP4")
    }

    /// The size presets cap how big a video's picture is and how many frames a
    /// second it runs at. One frame has neither question in it, so the row goes
    /// away rather than standing there meaning nothing.
    @Test func onePictureHasNoSizePresetToChoose() {
        #expect(RecordingExport.offersQuality(.still) == false)
        #expect(RecordingExport.offersQuality(.video(.gif)))
    }

    // MARK: - What it says the file will be

    /// The same line the video writes, answering the same two things: how big
    /// the picture is, and how much of the recording is in it — which for one
    /// frame is the moment it was taken at.
    @Test func itSaysThePixelSizeAndTheMomentItIsOf() {
        #expect(RecordingExport.shapeLine(choice: .still, quality: .standard, source: paused)
                == "1280 × 800 px · the frame at 0:04")
    }

    /// A crop is what the document is now, so the frame that leaves is the
    /// cropped one and the line says so.
    @Test func aCroppedRecordingWritesTheCroppedFrame() {
        var cropped = paused
        cropped.cropSize = CGSize(width: 640, height: 400)
        #expect(RecordingExport.shapeLine(choice: .still, quality: .standard, source: cropped)
                == "640 × 400 px · the frame at 0:04")
    }

    /// Nothing is scaled: a frame leaves at the size the document is, whatever
    /// the last video preset was set to.
    @Test func thePresetNeverResizesTheFrame() {
        for quality in VideoExportQuality.allCases {
            #expect(RecordingExport.outputSize(choice: .still, quality: quality, source: paused)
                    == CGSize(width: 1280, height: 800))
        }
    }

    // MARK: - What it says the file will weigh

    /// A GIF cannot be weighed without writing it. One frame can: it is a
    /// render and an encode, so the sheet says the real number.
    @Test func aWeighedFrameSaysWhatItReallyWeighs() {
        #expect(RecordingExport.sizeLine(choice: .still, quality: .standard,
                                         source: paused, stillBytes: 421_888)
                == "PNG picture · 412 KB")
    }

    /// Before the number lands, the sheet says what every format that cannot be
    /// weighed says, in the same words, rather than a zero or a blank.
    @Test func anUnweighedFrameSaysSoInTheSameWordsAsAGIF() {
        #expect(RecordingExport.sizeLine(choice: .still, quality: .standard,
                                         source: paused, stillBytes: nil)
                == "PNG picture · size not known until it is written")
    }

    /// The video's own lines are untouched by the picture being on the sheet.
    @Test func theVideoLinesAreExactlyWhatTheyWere() {
        #expect(RecordingExport.sizeLine(choice: .video(.mp4), quality: .high, source: paused)
                == RecordingExport.sizeLine(format: .mp4, quality: .high, source: paused))
        #expect(RecordingExport.shapeLine(choice: .video(.gif), quality: .small, source: paused)
                == RecordingExport.shapeLine(format: .gif, quality: .small, source: paused))
    }

    // MARK: - What it is for

    /// The sentence under the row, where a video says who its preset is for.
    /// Without it, PNG sitting beside three video formats reads as though it
    /// might turn the whole recording into pictures.
    @Test func itSaysWhatOnePictureIsForInOneSentence() {
        let said = RecordingExport.purposeLine(choice: .still, quality: .standard)
        #expect(said.contains("frame"))
        #expect(said.contains("playhead"))
    }

    // MARK: - What the save box opens on

    /// The document's own name wearing the extension of the answer picked, the
    /// same rule the three video formats follow.
    @Test func theSaveBoxOpensOnTheDocumentsNameAsAPNG() {
        #expect(RecordingExport.suggestedFileName(recording: "Screen Recording.mov", choice: .still)
                == "Screen Recording.png")
        #expect(RecordingExport.suggestedFileName(recording: "Screen Recording.mov",
                                                  choice: .video(.gif))
                == "Screen Recording.gif")
    }

    /// What a walk and the save panel ask for when they need the extension.
    @Test func thePictureKnowsItsOwnExtension() {
        #expect(RecordingExport.Choice.still.fileExtension == "png")
        #expect(RecordingExport.Choice.video(.heic).fileExtension == "heic")
    }
}
