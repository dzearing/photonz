import Testing
@testable import PhotonzCore

/// While a video plays, the sections and rows a pick brings into the right
/// hand panel wait for play to stop, or for the pointer to come into the
/// panel to use it. Each piece that landed while it played held the window
/// for a frame or two: picking a clip from nothing on the 6 minute reference
/// edit landed eight sections and six sets of rows over 0.7 s, in passes of
/// 16 to 61 ms (`picking-letting-go-of-and-cutting-a-clip-while-a`, pass 2).
@Suite("The panel waits for play to stop")
struct PanelWaitsForPlayToStopTests {

    @Test func theSwitchIsNextOnlyAndOnByDefault() throws {
        let name = FeatureCatalog.panelWaitsForPlayToStopFlag
        let next = try #require(FeatureCatalog.flags(for: .next).first { $0.name == name })
        #expect(next.isEnabled)
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == name })
    }

    @Test func piecesWaitWhileAVideoPlays() {
        #expect(PanelPlayHold.waits(hasTime: true, playing: true, pointerInPanel: false))
    }

    @Test func piecesLandOnceItStops() {
        #expect(!PanelPlayHold.waits(hasTime: true, playing: false, pointerInPanel: false))
    }

    @Test func thePointerInThePanelBringsThemIn() {
        // Somebody who comes to the panel while it plays has come to use it.
        #expect(!PanelPlayHold.waits(hasTime: true, playing: true, pointerInPanel: true))
    }

    @Test func aPictureNeverWaits() {
        #expect(!PanelPlayHold.waits(hasTime: false, playing: true, pointerInPanel: false))
    }
}
