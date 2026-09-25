import PhotonzCore
import Testing

/// Where there is a timeline, the timeline is the layer list
/// (`TimelineIsTheLayerList.swift`, `docs/design/mocks/pages/video.html`).
///
/// Written before the rule. On a video the panel's top third was a Layers list
/// naming the same clips the timeline under it already named, and the mock
/// leaves it out so the panel opens on the picked clip.
@Suite("On a video, the timeline is the layer list")
struct TimelineIsTheLayerListTests {

    static let saved = ["layers", "speed", "sound", "keys", "text", "color", "effects", "library"]

    // MARK: - When the list goes

    @Test func aVideoWithItsTimelineOpenHasNoLayersList() {
        #expect(!TimelineIsTheLayerList.showsLayersList(isOn: true, documentHasTime: true,
                                                        isTimelineOpen: true))
    }

    @Test func foldingTheTimelineAwayBringsTheListBack() {
        #expect(TimelineIsTheLayerList.showsLayersList(isOn: true, documentHasTime: true,
                                                       isTimelineOpen: false))
    }

    @Test func aPictureWithNoTimeKeepsItsListWhateverTheWindowSays() {
        for open in [true, false] {
            #expect(TimelineIsTheLayerList.showsLayersList(isOn: true, documentHasTime: false,
                                                           isTimelineOpen: open))
        }
    }

    @Test func withTheFlagOffEveryDocumentKeepsItsList() {
        for time in [true, false] {
            for open in [true, false] {
                #expect(TimelineIsTheLayerList.showsLayersList(isOn: false, documentHasTime: time,
                                                               isTimelineOpen: open))
            }
        }
    }

    // MARK: - What the panel is left with

    @Test func thePickedClipLeadsThePanelOnceTheListHasGone() {
        let order = TimePanelOrder.arrange(Self.saved, for: .playing)
        let shown = TimelineIsTheLayerList.sections(order, isOn: true, documentHasTime: true,
                                                    isTimelineOpen: true)
        #expect(shown.first == "speed")
        #expect(!shown.contains("layers"))
    }

    @Test func onlyTheLayersListIsEverTakenOut() {
        let shown = TimelineIsTheLayerList.sections(Self.saved, isOn: true, documentHasTime: true,
                                                    isTimelineOpen: true)
        #expect(shown == Array(Self.saved.dropFirst()))
    }

    @Test func aFoldedTimelineLeavesTheSectionsExactlyAsTheyWere() {
        #expect(TimelineIsTheLayerList.sections(Self.saved, isOn: true, documentHasTime: true,
                                                isTimelineOpen: false) == Self.saved)
        #expect(TimelineIsTheLayerList.sections(Self.saved, isOn: true, documentHasTime: false,
                                                isTimelineOpen: true) == Self.saved)
    }

    // MARK: - It is not a mode

    /// A mode may never fold the layers list (`docs/design/modes.md` §2). This
    /// rule does not make it optional: it is the window showing a timeline.
    @Test func theLayersListIsStillNotSomethingAModeCanFold() {
        #expect(!PanelSectionVisibility.isOptional(TimelineIsTheLayerList.layersSection))
        var choices = PanelSectionVisibility.Choices()
        choices.set(TimelineIsTheLayerList.layersSection, shown: false)
        #expect(!choices.hasAnyCustom)
    }

    @Test func itShipsOnByDefaultInNextOnly() {
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .isEnabled(FeatureCatalog.timelineIsTheLayerListFlag))
        #expect(!FeatureCatalog.flags(for: .current)
            .contains { $0.name == FeatureCatalog.timelineIsTheLayerListFlag })
    }

    @Test func itNeedsTheRecordingToOpenInTheEditor() {
        #expect(FeatureCatalog.dependencies(of: FeatureCatalog.timelineIsTheLayerListFlag)
            .contains(FeatureCatalog.recordingIsADocumentFlag))
    }
}
