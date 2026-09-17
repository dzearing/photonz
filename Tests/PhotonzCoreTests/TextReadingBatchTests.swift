import Foundation
import Testing
@testable import PhotonzCore

@Suite("Reading a whole picture's labels")
struct TextReadingBatchTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 3_000)

    // MARK: - What the line says

    @Test func everyLabelReadIsCountedAndTheFaceIsNamedOnce() {
        // Nine labels came back and they are all in one family, which is the
        // whole reason for reading them together. The face is named ONCE, for
        // the page, rather than nine times for nine labels.
        let batch = TextReading.Batch(read: 9, stillPictures: 0, family: "SF Pro")
        #expect(batch.title == "Turned into text")
        #expect(batch.detail == "9 labels, set in SF Pro")
    }

    @Test func oneLabelStillReadsAsOne() {
        // The batch path is for several, but the sentence must not say
        // "1 labels" if it ever gets one.
        let batch = TextReading.Batch(read: 1, stillPictures: 0, family: "SF Pro")
        #expect(batch.detail == "1 label, set in SF Pro")
    }

    @Test func aPageWithNoVoteNamesNoFace() {
        // Nothing voted, so nothing is claimed. Naming a face the app did not
        // settle on would be the one thing this feature exists to avoid.
        let batch = TextReading.Batch(read: 4, stillPictures: 0, family: nil)
        #expect(batch.detail == "4 labels")
    }

    @Test func whatStayedAPictureIsSaidOutLoud() {
        // The half of the command nobody would otherwise find out about: three
        // labels are still pictures and look exactly like the ones that are
        // not. Saying how many is what lets somebody go and look.
        let batch = TextReading.Batch(read: 7, stillPictures: 3, family: "SF Pro")
        #expect(batch.detail == "7 labels, set in SF Pro. 3 stayed pictures")
    }

    @Test func oneThatStayedAPictureSaysSoInTheSingular() {
        let batch = TextReading.Batch(read: 7, stillPictures: 1, family: "SF Pro")
        #expect(batch.detail == "7 labels, set in SF Pro. 1 stayed a picture")
    }

    @Test func nothingReadIsARefusalAndSaysHowManyItAsked() {
        // The verdict changes, because nothing happened to the document. A
        // person who pressed the button and got "Turned into text" over a
        // canvas that did not change would think the app was lying.
        let batch = TextReading.Batch(read: 0, stillPictures: 12, family: nil)
        #expect(batch.title == "Still pictures")
        #expect(batch.detail == "None of the 12 labels could be read")
    }

    @Test func nothingReadOfOneIsStillSingular() {
        let batch = TextReading.Batch(read: 0, stillPictures: 1, family: nil)
        #expect(batch.title == "Still a picture")
        #expect(batch.detail == "It could not be read")
    }

    @Test func itCountsWhatItWasAsked() {
        let batch = TextReading.Batch(read: 7, stillPictures: 3, family: "SF Pro")
        #expect(batch.asked == 10)
        #expect(batch.landed)
        #expect(!TextReading.Batch(read: 0, stillPictures: 3, family: nil).landed)
    }

    // MARK: - In the pill

    @Test func thePillCarriesTheWholeSentence() {
        let batch = TextReading.Batch(read: 9, stillPictures: 0, family: "SF Pro")
        let notice = CopyConfirmation(subject: .turnedIntoTextInBatch(batch), shownAt: t0)
        #expect(notice.title == batch.title)
        #expect(notice.detail == batch.detail)
    }

    @Test func thePillStaysUpAsLongAsTheSingularOneDoes() {
        // It is a result you might want to undo, and one undo press takes the
        // whole lot back: the same reason the singular reading gets the longer
        // clock.
        let batch = TextReading.Batch(read: 9, stillPictures: 2, family: "SF Pro")
        let notice = CopyConfirmation(subject: .turnedIntoTextInBatch(batch), shownAt: t0)
        #expect(notice.lifetime == CopyConfirmation.breakLifetime)
    }

    // MARK: - While it is working

    @Test func theProgressLineSaysHowManyItIsReading() {
        // Reading a dense page is about two seconds. Without a word on screen
        // the press looks like it did nothing at all.
        let notice = CopyConfirmation(subject: .readingTheWords(labels: 142), shownAt: t0)
        #expect(notice.title == "Reading the words")
        #expect(notice.detail == "142 labels")
    }

    @Test func theProgressLineWaitsForItsAnswerRatherThanFading() {
        // It is not a glance, it is a thing in progress: it must still be there
        // when the reading lands, and the result replaces it. It still has a
        // ceiling, because nothing on screen may live forever.
        let notice = CopyConfirmation(subject: .readingTheWords(labels: 142), shownAt: t0)
        #expect(notice.lifetime == CopyConfirmation.workingLifetime)
        #expect(notice.lifetime > CopyConfirmation.actionLifetime)
        #expect(notice.isLive(at: t0.addingTimeInterval(10)))
        #expect(!notice.isLive(at: t0.addingTimeInterval(CopyConfirmation.workingLifetime)))
    }

    // MARK: - The offer on the separation's own pill

    @Test func theSeparationsOfferNamesWhatItWouldDo() {
        // A person who has just separated a screenshot is looking at pieces,
        // not at a menu. The button says what pressing it gets them.
        let runs = [UUID(), UUID()]
        let action = CanvasNoticeAction.readTheWords(runs: runs)
        #expect(action.label == "Read the Words")
        #expect(action.layerIDs == runs)
    }

    @Test func theOfferHasNoKeyToTeach() {
        // Turn into Text has no keyboard shortcut, and a button that shows a
        // key that does not exist teaches something false.
        #expect(CanvasNoticeAction.readTheWords(runs: [UUID()]).shortcutHint == nil)
        #expect(CanvasNoticeAction.turnIntoPicture(layer: UUID()).shortcutHint != nil)
    }

    @Test func theOfferRemembersTheRunsItWasRaisedOver() {
        // Selection changes the instant somebody clicks the canvas. The button
        // reads the runs the separation MADE, never whatever is picked now.
        let runs = [UUID(), UUID(), UUID()]
        let action = CanvasNoticeAction.readTheWords(runs: runs)
        #expect(action != .readTheWords(runs: Array(runs.dropLast())))
    }

    @Test func aSeparationPillCarryingTheOfferStaysUpLongEnoughToReachIt() {
        let notice = CopyConfirmation(
            subject: .separatedIntoLayers(runs: 9, boxes: 1, skipped: 0),
            shownAt: t0, action: .readTheWords(runs: [UUID()]))
        #expect(notice.lifetime == CopyConfirmation.actionLifetime)
    }
}
