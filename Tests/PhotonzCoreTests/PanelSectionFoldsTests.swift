import Foundation
import Testing
@testable import PhotonzCore

/// Which sections of the right hand panel are folded, as the one stored
/// setting keeps it ("a,b,c"), and the test a stored setting uses to tell a
/// real change of its own value from a write to some other setting.
///
/// Folding a section used to re-evaluate the whole panel and the whole editor,
/// 20 to 100ms a click (`section-fold-motion-walk`, 2026-10-04). A fold now
/// reaches only its own section, which needs to know exactly which sections a
/// change of the setting flipped, and nothing else.
@Suite("Panel section folds")
struct PanelSectionFoldsTests {

    @Test("Nothing stored means nothing folded")
    func nothingStored() {
        #expect(PanelSectionFolds(stored: nil).folded.isEmpty)
        #expect(PanelSectionFolds(stored: "").folded.isEmpty)
    }

    @Test("The stored list is read as the sections it names")
    func readsTheList() {
        let folds = PanelSectionFolds(stored: "time,captions")
        #expect(folds.contains("time"))
        #expect(folds.contains("captions"))
        #expect(!folds.contains("transitions"))
    }

    @Test("Written back sorted, so the same folds always store the same words")
    func storesSorted() {
        var folds = PanelSectionFolds(stored: nil)
        folds.toggle("time")
        folds.toggle("audio")
        #expect(folds.stored == "audio,time")
        #expect(PanelSectionFolds(stored: "time,audio") == PanelSectionFolds(stored: "audio,time"))
    }

    @Test("A toggle folds an open section and opens a folded one")
    func toggleFlips() {
        var folds = PanelSectionFolds(stored: "time")
        folds.toggle("time")
        #expect(!folds.contains("time"))
        folds.toggle("time")
        #expect(folds.contains("time"))
    }

    @Test("Opening a section says whether it was folded at all")
    func openReportsWhetherItChanged() {
        var folds = PanelSectionFolds(stored: "time")
        let first = folds.open("time")
        #expect(first)
        #expect(!folds.contains("time"))
        let second = folds.open("time")
        #expect(!second)
    }

    @Test("A name the app no longer has is kept, so it survives a round trip")
    func unknownNamesSurvive() {
        var folds = PanelSectionFolds(stored: "retired,time")
        folds.toggle("time")
        #expect(folds.stored == "retired")
    }

    @Test("Only the sections a change flipped are named")
    func flippedNamesOnlyTheChange() {
        let before = PanelSectionFolds(stored: "time,captions")
        let after = PanelSectionFolds(stored: "captions,audio")
        #expect(after.flipped(from: before) == ["time", "audio"])
        #expect(before.flipped(from: before).isEmpty)
    }

    // MARK: A section that starts folded

    // The Library shows itself in a video without being asked, folded, so the
    // media pool costs one row until it is opened (the decision on
    // `a-video-document-shows-the-library-in-its-dock`, 2026-10-19, and the
    // user's own complaint on 2026-10-18 that the Library "was expanded by
    // default"). Folded is where it starts, not a fold anybody made, so it
    // has to be remembered the other way round: by the person OPENING it.

    @Test("The Library starts folded with nothing stored")
    func libraryStartsFolded() {
        #expect(PanelSectionFolds.startFolded == ["library"])
        let folds = PanelSectionFolds(stored: nil)
        #expect(folds.contains("library"))
        #expect(!folds.contains("time"))
        #expect(folds.stored == "")
    }

    @Test("Opening the Library is remembered, and survives a round trip")
    func openingTheLibraryIsKept() {
        var folds = PanelSectionFolds(stored: "time")
        let opened = folds.open("library")
        #expect(opened)
        #expect(!folds.contains("library"))
        #expect(folds.stored == "+library,time")
        let read = PanelSectionFolds(stored: folds.stored)
        #expect(!read.contains("library"))
        #expect(read.contains("time"))
        #expect(read == folds)
    }

    @Test("Folding the Library again goes back to where it starts, storing nothing")
    func foldingTheLibraryAgain() {
        var folds = PanelSectionFolds(stored: "+library")
        folds.toggle("library")
        #expect(folds.contains("library"))
        #expect(folds.stored == "")
        folds.toggle("library")
        #expect(!folds.contains("library"))
        #expect(folds.stored == "+library")
    }

    @Test("An older build's folded Library stays folded")
    func olderFoldedLibrary() {
        let folds = PanelSectionFolds(stored: "library,time")
        #expect(folds.contains("library"))
        #expect(folds == PanelSectionFolds(stored: "time"))
    }

    @Test("Opening the Library is a flip of the Library and nothing else")
    func openingFlipsTheLibrary() {
        let before = PanelSectionFolds(stored: "time")
        var after = before
        after.open("library")
        #expect(after.flipped(from: before) == ["library"])
        #expect(before.flipped(from: after) == ["library"])
    }

    // MARK: Telling a stored setting's own change from anybody else's

    @Test("The same stored value read twice is not a change")
    func sameValueIsNoChange() {
        #expect(!StoredSettingValue.differs(264.0 as NSNumber, 264.0 as NSNumber))
        #expect(!StoredSettingValue.differs("a,b" as NSString, "a,b" as NSString))
        #expect(!StoredSettingValue.differs(nil, nil))
    }

    @Test("A new value, or one appearing or going away, is a change")
    func newValueIsAChange() {
        #expect(StoredSettingValue.differs(264.0 as NSNumber, 300.0 as NSNumber))
        #expect(StoredSettingValue.differs(nil, "a" as NSString))
        #expect(StoredSettingValue.differs("a" as NSString, nil))
    }
}
