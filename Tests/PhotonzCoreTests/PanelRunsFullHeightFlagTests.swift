import CoreGraphics
import Testing
@testable import PhotonzCore

/// On a document with time the right hand panel runs from the top of the
/// window to the bottom and the timeline sits under the picture only
/// (decision on the-panel-keeps-its-promise-on-a-video-document, option a,
/// 2026-10-20). Before it, the timeline ran under the panel too and took its
/// whole height off it, so Appearance and Effects were below the bottom edge
/// of a laptop window whatever was picked.
@Suite("The panel runs the full height on a video")
struct PanelRunsFullHeightFlagTests {

    @Test func theSwitchIsNextOnlyAndOnByDefault() throws {
        let name = FeatureCatalog.panelRunsFullHeightFlag
        let next = try #require(FeatureCatalog.flags(for: .next).first { $0.name == name })
        #expect(next.isEnabled)
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == name })
    }

    /// The panel's height is the window's whatever the timeline does, once
    /// the timeline sits beside it rather than under it.
    @Test func theTimelineTakesNothingOffThePanelBesideIt() {
        #expect(PanelColumn.height(window: 720, timeline: 337, timelineUnderPanel: false) == 720)
        #expect(PanelColumn.height(window: 720, timeline: 0, timelineUnderPanel: false) == 720)
    }

    /// ...and the whole of it when it runs under the panel too, the layout
    /// a still picture's motion strip keeps.
    @Test func aTimelineUnderThePanelTakesItsHeightOff() {
        #expect(PanelColumn.height(window: 720, timeline: 235, timelineUnderPanel: true) == 485)
        #expect(PanelColumn.height(window: 100, timeline: 235, timelineUnderPanel: true) == 0)
    }

    /// Which documents get it: one with time, with the switch on. An icon's
    /// one-lap strip keeps running under both columns, because a lag is read
    /// against every bar on one ruler.
    @Test func onlyADocumentWithTimeMovesTheTimeline() {
        #expect(PanelColumn.timelineUnderPictureOnly(documentHasTime: true, switchOn: true))
        #expect(!PanelColumn.timelineUnderPictureOnly(documentHasTime: false, switchOn: true))
        #expect(!PanelColumn.timelineUnderPictureOnly(documentHasTime: true, switchOn: false))
    }
}
