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

@Suite("The count of what stayed a picture is the way to them")
struct StillPicturesAreFindableTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 4_000)

    // MARK: - The line splits where the count starts

    @Test func theLineHandsBackItsCountAsAPieceOfItsOwn() {
        // The count is the only part of the sentence a person can be sent to,
        // so the line has to say where it starts. The two halves put back
        // together are the sentence that was always there.
        let batch = TextReading.Batch(read: 7, stillPictures: 3, family: "SF Pro")
        #expect(batch.detailLead == "7 labels, set in SF Pro.")
        #expect(batch.stillPicturesTail == "3 stayed pictures")
        #expect(batch.detail == "7 labels, set in SF Pro. 3 stayed pictures")
    }

    @Test func oneThatStayedSplitsInTheSingular() {
        let batch = TextReading.Batch(read: 7, stillPictures: 1, family: "SF Pro")
        #expect(batch.detailLead == "7 labels, set in SF Pro.")
        #expect(batch.stillPicturesTail == "1 stayed a picture")
    }

    @Test func aReadingThatLeftNothingBehindHasNoTail() {
        // Nothing stayed a picture, so there is nothing to be sent to and the
        // line is a plain report.
        let batch = TextReading.Batch(read: 9, stillPictures: 0, family: "SF Pro")
        #expect(batch.stillPicturesTail == nil)
        #expect(batch.detailLead == batch.detail)
    }

    @Test func aReadingThatLandedNothingHasNoTailEither() {
        // "None of the 12 labels could be read" is one sentence about the whole
        // ask, not a report with a count on the end of it. There is no fragment
        // to pick out, and nothing to pick out FROM: every label is still a
        // picture, so finding them is not the problem.
        let batch = TextReading.Batch(read: 0, stillPictures: 12, family: nil)
        #expect(batch.stillPicturesTail == nil)
        #expect(batch.detailLead == "None of the 12 labels could be read")
    }

    // MARK: - The action wears the same words

    @Test func theActionSaysExactlyWhatTheLineSays() {
        // The words in the line and the thing that gets pressed are ONE thing.
        // Built from one place so they cannot drift into saying two different
        // numbers about the same labels.
        let labels = [UUID(), UUID(), UUID()]
        let action = CanvasNoticeAction.findStillPictures(labels: labels)
        let batch = TextReading.Batch(read: 7, stillPictures: labels.count, family: "SF Pro")
        #expect(action.label == batch.stillPicturesTail)
        #expect(action.label == "3 stayed pictures")
        #expect(CanvasNoticeAction.findStillPictures(labels: [UUID()]).label == "1 stayed a picture")
    }

    @Test func theActionRemembersTheLabelsItCounted() {
        // Selection changes the instant anybody clicks the canvas. The press
        // picks the labels the READING left behind, never whatever is picked
        // now, for the same reason the offer beside it reads the runs the
        // separation made.
        let labels = [UUID(), UUID(), UUID()]
        let action = CanvasNoticeAction.findStillPictures(labels: labels)
        #expect(action.layerIDs == labels)
        #expect(action != .findStillPictures(labels: Array(labels.dropLast())))
    }

    @Test func theCountHasNoKeyToTeach() {
        #expect(CanvasNoticeAction.findStillPictures(labels: [UUID()]).shortcutHint == nil)
    }

    // MARK: - Where it sits in the pill

    @Test func theCountIsPressedInTheLineAndNotAsAButtonOnTheEnd() {
        // A button bolted on the end would read as a second thing to do. This
        // one IS the report: the words that count them are the way to them.
        #expect(CanvasNoticeAction.findStillPictures(labels: [UUID()]).presentation
                == .wordsInTheLine)
        #expect(CanvasNoticeAction.readTheWords(runs: [UUID()]).presentation == .button)
        #expect(CanvasNoticeAction.turnIntoPicture(layer: UUID()).presentation == .button)
    }

    @Test func thePillSplitsItsLineWhereTheCountStarts() {
        let labels = [UUID(), UUID(), UUID()]
        let batch = TextReading.Batch(read: 7, stillPictures: 3, family: "SF Pro")
        let notice = CopyConfirmation(subject: .turnedIntoTextInBatch(batch), shownAt: t0,
                                      action: .findStillPictures(labels: labels))
        #expect(notice.line.lead == "7 labels, set in SF Pro.")
        #expect(notice.line.pressable == "3 stayed pictures")
        // And the whole sentence is still one sentence, for anything that reads
        // the line rather than drawing it.
        #expect(notice.detail == "7 labels, set in SF Pro. 3 stayed pictures")
    }

    @Test func aPillWithNothingToPointAtIsAPlainReport() {
        // Nothing stayed a picture: no action, nothing picked, nothing scrolled.
        let batch = TextReading.Batch(read: 9, stillPictures: 0, family: "SF Pro")
        let notice = CopyConfirmation(subject: .turnedIntoTextInBatch(batch), shownAt: t0)
        #expect(notice.action == nil)
        #expect(notice.line.lead == notice.detail)
        #expect(notice.line.pressable == nil)
    }

    @Test func everyOtherPillKeepsItsWholeLineUnpressable() {
        // The words of a notice are read, never pressed: that is what stops a
        // pill turning up under a pointer and swallowing a click meant for the
        // canvas. Only the one that counts something findable opts out.
        let refusal = RegionSliceRefusal(action: .erase, reason: .canBecomeAPicture)
        let withButton = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0,
                                          action: .turnIntoPicture(layer: UUID()))
        #expect(withButton.line.pressable == nil)
        #expect(withButton.line.lead == withButton.detail)

        let copied = CopyConfirmation(subject: .specList(measurements: 3), shownAt: t0)
        #expect(copied.line.pressable == nil)
        #expect(copied.line.lead == copied.detail)
    }

    @Test func aPillYouAreMeantToPressStaysUpLongEnoughToReachIt() {
        // Six seconds rather than three: reading a sentence, deciding the three
        // strays matter, and travelling to the words does not fit in three.
        let batch = TextReading.Batch(read: 7, stillPictures: 3, family: "SF Pro")
        let notice = CopyConfirmation(subject: .turnedIntoTextInBatch(batch), shownAt: t0,
                                      action: .findStillPictures(labels: [UUID(), UUID(), UUID()]))
        #expect(notice.lifetime == CopyConfirmation.actionLifetime)
    }
}
