import CoreGraphics
import PhotonzCore
import Testing

/// What the capsule above the floating tool bar carries for the tool in hand.
///
/// The rule this pins down is the one the task was written around: only
/// SETTINGS live here, and only the ones that have nowhere else to go with the
/// right hand panel hidden. A mode (Crop's aspect, Measure's mode) already
/// survives a hidden panel inside its own tool button, so it is not repeated
/// here and does not widen the capsule for nothing.
@Suite("ToolSettingsBar")
struct ToolSettingsBarTests {

    @Test func aToolWithNothingToSetGetsNoCapsuleAtAll() {
        // The acceptance the user wrote: picking the arrow must not leave an
        // empty bar hanging over the picture.
        for tool in [Tool.select, .arrow, .line, .rectangle, .ellipse,
                     .highlight, .text, .fill, .rectSelect, .ellipseSelect,
                     .frame, .crop] {
            #expect(ToolSettingsBar.settings(for: tool, availability: .all).isEmpty,
                    "\(tool) should carry no capsule")
        }
    }

    @Test func theZoomCalloutCarriesItsShape() {
        #expect(ToolSettingsBar.settings(for: .zoomCallout, availability: .all) == [.calloutShape])
    }

    @Test func theWandCarriesItsTolerance() {
        #expect(ToolSettingsBar.settings(for: .wand, availability: .all) == [.wandTolerance])
    }

    @Test func measureCarriesSnapAndShowInThatOrder() {
        #expect(ToolSettingsBar.settings(for: .measure, availability: .all)
                == [.measureSnap, .measureShow])
    }

    @Test func aSettingItsFlagHasTurnedOffIsNotShown() {
        let noSnap = ToolSettingsBar.Availability(calloutShape: true,
                                                  measureSnap: false, measureShow: true)
        #expect(ToolSettingsBar.settings(for: .measure, availability: noSnap) == [.measureShow])
        #expect(ToolSettingsBar.settings(for: .zoomCallout, availability: .none).isEmpty)
        // The wand's tolerance answers to no flag of its own: it is the wand.
        #expect(ToolSettingsBar.settings(for: .wand, availability: .none) == [.wandTolerance])
    }

    @Test func everySettingHasAWordOnIt() {
        for setting in ToolSetting.allCases {
            #expect(!setting.title.isEmpty)
        }
        #expect(ToolSetting.calloutShape.title == "Shape")
        #expect(ToolSetting.wandTolerance.title == "Tolerance")
        #expect(ToolSetting.measureSnap.title == "Snap")
        #expect(ToolSetting.measureShow.title == "Show")
    }

    // MARK: Wrapping on a narrow window

    @Test func settingsThatFitStayOnOneRow() {
        #expect(ToolSettingsBar.rows(ofWidths: [120, 160], spacing: 18, within: 400)
                == [[0, 1]])
    }

    @Test func settingsThatDoNotFitStackRatherThanDisappear() {
        // 120 + 18 + 160 is 298, so at 280 the second one moves down. Nothing
        // is dropped: a setting that vanishes on a narrow window is the exact
        // disappearance this feature exists to end.
        #expect(ToolSettingsBar.rows(ofWidths: [120, 160], spacing: 18, within: 280)
                == [[0], [1]])
    }

    @Test func aRowFillsUpBeforeTheNextOneStarts() {
        #expect(ToolSettingsBar.rows(ofWidths: [100, 100, 100], spacing: 10, within: 210)
                == [[0, 1], [2]])
    }

    @Test func oneSettingTooWideForTheRoomStillGetsItsOwnRow() {
        // There is nowhere narrower to put it, and taking it away is worse
        // than letting it be snug.
        #expect(ToolSettingsBar.rows(ofWidths: [500], spacing: 18, within: 200) == [[0]])
        #expect(ToolSettingsBar.rows(ofWidths: [100, 500], spacing: 18, within: 200)
                == [[0], [1]])
    }

    @Test func nothingToPackIsNoRows() {
        #expect(ToolSettingsBar.rows(ofWidths: [], spacing: 18, within: 400).isEmpty)
    }
}
