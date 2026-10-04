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
