import Testing
@testable import PhotonzCore

/// Putting a transition on a cut while a video plays leaves it playing, the
/// way Final Cut's Add Transition (Command T) does, and the rule the blade
/// follows (`next-blade-keeps-playing`): an edit that does not mean stop
/// leaves play running. Stopping cost the edit a pause nobody asked for, a
/// jump of the playhead back to the cut and the cut's panel built in the same
/// beat: on the 6 minute reference edit the longest main thread pass of adding
/// a dissolve while it played read 39 to 57 ms
/// (`picking-letting-go-of-and-cutting-a-clip-while-a`, 2026-11-23).
@Suite("A transition put on while playing keeps playing")
struct TransitionKeepsPlayingFlagTests {

    @Test func theSwitchIsNextOnlyAndOnByDefault() throws {
        let name = FeatureCatalog.transitionKeepsPlayingFlag
        let next = try #require(FeatureCatalog.flags(for: .next).first { $0.name == name })
        #expect(next.isEnabled)
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == name })
    }
}
