import Foundation
import Testing

@testable import PhotonzCore

@Suite("What Save means for one window")
struct SaveAffordanceTests {

    // THE INVARIANT the 2026-09-18 report is about. Whenever closing would stop
    // and ask whether to save, Save itself has to be live. One place saying
    // "there is nothing to save" while the other says "there are unsaved
    // changes" is the contradiction the user hit, and this walks every
    // combination of the facts a window can be in rather than the handful
    // somebody thought of.
    @Test("Closing never asks about changes that Save cannot write")
    func askingToSaveAlwaysMeansSaveIsLive() {
        for isLoaded in [true, false] {
            for hasChanges in [true, false] {
                for isSaving in [true, false] {
                    for isUnsavedRecording in [true, false] {
                        let affordance = SaveAffordance.forDocument(isLoaded: isLoaded,
                                                                   hasChanges: hasChanges,
                                                                   isSaving: isSaving,
                                                                   isUnsavedRecording: isUnsavedRecording)
                        if affordance.asksBeforeClosing {
                            // A close that asks always offers Save, and Save is
                            // live and has something to write.
                            #expect(affordance.closingOffersSave,
                                    "\(affordance) asks before closing but does not offer Save")
                            #expect(affordance.isSaveEnabled,
                                    "\(affordance) offers Save on the way out but dims Save")
                            #expect(affordance.savesSomething,
                                    "\(affordance) offers Save on the way out but Save has nothing to do")
                        } else {
                            #expect(!affordance.closingOffersSave && !affordance.closingOffersExport)
                        }
                        // Export on the way out is only ever offered BESIDE Save.
                        if affordance.closingOffersExport {
                            #expect(affordance.closingOffersSave)
                        }
                    }
                }
            }
        }
    }

    // The other half of the same promise: a dimmed Save has to mean there is
    // genuinely nothing to lose, so nothing is ever dropped quietly.
    @Test("A dimmed Save never lets work go without a word")
    func dimmedSaveMeansNothingToLose() {
        for affordance in SaveAffordance.allCases where !affordance.isSaveEnabled {
            #expect(affordance == .nothingToSave)
            #expect(!affordance.asksBeforeClosing)
        }
    }

    @Test("An empty window has nothing to save whatever else is true of it")
    func anEmptyWindowHasNothingToSave() {
        #expect(SaveAffordance.forDocument(isLoaded: false, hasChanges: true, isSaving: true)
            == .nothingToSave)
        #expect(SaveAffordance.forDocument(isLoaded: false, hasChanges: false, isSaving: false)
            == .nothingToSave)
    }

    @Test("A loaded document with no edits keeps Save live and closes without asking")
    func anUnchangedDocumentStillOffersSave() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: false, isSaving: false)
        #expect(affordance == .upToDate)
        #expect(affordance.isSaveEnabled)
        #expect(!affordance.asksBeforeClosing)
        #expect(!affordance.savesSomething)
    }

    @Test("A loaded document with edits asks before closing and Save writes them")
    func editsAskBeforeClosing() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: true, isSaving: false)
        #expect(affordance == .unsavedChanges)
        #expect(affordance.isSaveEnabled)
        #expect(affordance.asksBeforeClosing)
        #expect(affordance.savesSomething)
    }

    // A commit takes seconds on a real recording. Dimming Save for those
    // seconds is what let the menu and the close sheet drift apart, so a save
    // in flight keeps Save live and both routes wait on it.
    @Test("A save already running keeps Save live and still guards the close")
    func aSaveInFlightKeepsSaveLive() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: true, isSaving: true)
        #expect(affordance == .saving)
        #expect(affordance.isSaveEnabled)
        #expect(affordance.asksBeforeClosing)
        #expect(affordance.savesSomething)
    }

    // Saving the last of the edits still counts as a save in flight: the file
    // on disk is not the edited file until the commit lands.
    @Test("A save running with nothing left changed is still a save running")
    func aSaveInFlightWinsOverUpToDate() {
        #expect(SaveAffordance.forDocument(isLoaded: true, hasChanges: false, isSaving: true)
            == .saving)
    }

    // Command S on a video saves the project (the card answered 2026-09-25):
    // the recordings are never written over, and a recording that has never
    // been saved anywhere gets the save box, exactly as an untitled document
    // does in any Mac app and an untitled project does in Premiere. Closing an
    // edited one asks with Save, and Export beside it, so trim and send is
    // still two steps from the sheet.
    @Test("An edited recording never saved keeps Save live and offers Export beside it")
    func anEditedRecordingSavesAProject() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: true,
                                                   isSaving: false, isUnsavedRecording: true)
        #expect(affordance == .unsavedRecording)
        #expect(affordance.isSaveEnabled)
        #expect(affordance.savesSomething)
        #expect(affordance.asksBeforeClosing)
        #expect(affordance.closingOffersSave)
        #expect(affordance.closingOffersExport)
    }

    // Untouched, it is exactly an untitled document: Save live (it opens the
    // save box), and closing asks nothing because nothing would be lost.
    @Test("An untouched recording keeps Save live and closes without asking")
    func anUntouchedRecordingStillOffersSave() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: false,
                                                   isSaving: false, isUnsavedRecording: true)
        #expect(affordance == .upToDate)
        #expect(affordance.isSaveEnabled)
        #expect(!affordance.asksBeforeClosing)
    }

    @Test("A recording still loading has nothing to save")
    func aLoadingRecordingHasNothingToSave() {
        #expect(SaveAffordance.forDocument(isLoaded: false, hasChanges: true, isSaving: false,
                                           isUnsavedRecording: true) == .nothingToSave)
    }

    @Test("Export is offered on the way out only for a recording never saved")
    func exportIsOfferedOnlyForAnUnsavedRecording() {
        for affordance in SaveAffordance.allCases where affordance != .unsavedRecording {
            #expect(!affordance.closingOffersExport, "\(affordance) offers Export on close")
        }
    }
}
