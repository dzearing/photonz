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
                    for canSaveInPlace in [true, false] {
                        let affordance = SaveAffordance.forDocument(isLoaded: isLoaded,
                                                                   hasChanges: hasChanges,
                                                                   isSaving: isSaving,
                                                                   canSaveInPlace: canSaveInPlace)
                        if affordance.closingOffersSave {
                            #expect(affordance.isSaveEnabled,
                                    "\(affordance) offers Save on the way out but dims Save")
                            #expect(affordance.savesSomething,
                                    "\(affordance) offers Save on the way out but Save has nothing to do")
                        }
                        // A close that asks offers exactly one way to keep the
                        // work: Save, or Export where Save cannot write it.
                        if affordance.asksBeforeClosing {
                            #expect(affordance.closingOffersSave != affordance.closingOffersExport,
                                    "\(affordance) asks before closing but offers no one way to keep it")
                        } else {
                            #expect(!affordance.closingOffersSave && !affordance.closingOffersExport)
                        }
                    }
                }
            }
        }
    }

    // The other half of the same promise: a dimmed Save has to mean there is
    // genuinely nothing to lose, or that closing stops and says how to keep it,
    // so nothing is ever dropped quietly.
    @Test("A dimmed Save never lets work go without a word")
    func dimmedSaveMeansNothingToLose() {
        for affordance in SaveAffordance.allCases where !affordance.isSaveEnabled {
            if affordance == .nothingToSave {
                #expect(!affordance.asksBeforeClosing)
            } else {
                #expect(affordance.asksBeforeClosing && affordance.closingOffersExport,
                        "\(affordance) dims Save and would close without asking")
            }
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

    // A recording opened as a document has nowhere to be saved TO until the
    // Command S question is answered: writing it back would throw away the
    // video, and a package would hold a clip whose frames it cannot find. The
    // edits are still work, so closing asks, says they will not be kept, and
    // offers Export, the one door that does keep them (2026-09-23).
    @Test("Edits nothing can save in place ask before closing and offer Export")
    func editsOnlyExportKeepsAskAndOfferExport() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: true,
                                                   isSaving: false, canSaveInPlace: false)
        #expect(affordance == .changesOnlyExportKeeps)
        #expect(!affordance.isSaveEnabled)
        #expect(affordance.asksBeforeClosing)
        #expect(affordance.closingOffersExport)
        #expect(!affordance.closingOffersSave)
        #expect(!affordance.savesSomething)
    }

    @Test("An untouched window with nowhere to save closes without asking")
    func untouchedWithNowhereToSaveClosesQuietly() {
        let affordance = SaveAffordance.forDocument(isLoaded: true, hasChanges: false,
                                                   isSaving: false, canSaveInPlace: false)
        #expect(affordance == .nothingToSave)
        #expect(!affordance.asksBeforeClosing)
    }
}
