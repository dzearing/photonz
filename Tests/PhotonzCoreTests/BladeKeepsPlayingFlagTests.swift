import Testing
@testable import PhotonzCore

/// Cutting at the playhead while a video plays leaves it playing, the way
/// Final Cut's Blade (Command B) and Premiere's Add Edit do
/// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 28). Stopping
/// cost every blade a pause the person did not ask for, and on the 6 minute
/// reference edit a 20 ms pass of the main thread waiting on the window server
/// as play stopped.
@Suite("A blade while playing keeps playing")
struct BladeKeepsPlayingFlagTests {

    @Test func theSwitchIsNextOnlyAndOnByDefault() throws {
        let name = FeatureCatalog.bladeKeepsPlayingFlag
        let next = try #require(FeatureCatalog.flags(for: .next).first { $0.name == name })
        #expect(next.isEnabled)
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == name })
    }
}
