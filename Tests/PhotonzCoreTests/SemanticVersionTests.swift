import Testing
@testable import PhotonzCore

/// Version parsing + comparison for the updater (phase 11.6). The fetch/UI is a
/// thin app shell; all the ordering logic lives here so it's testable.
@Suite("SemanticVersion")
struct SemanticVersionTests {

    @Test func parsesDottedTriple() {
        let v = SemanticVersion("1.2.3")
        #expect(v == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func toleratesLeadingVAndWhitespace() {
        #expect(SemanticVersion(" v0.2.0 ") == SemanticVersion(major: 0, minor: 2, patch: 0))
        #expect(SemanticVersion("V10.20.30") == SemanticVersion(major: 10, minor: 20, patch: 30))
    }

    @Test func missingPatchOrMinorDefaultsToZero() {
        #expect(SemanticVersion("1") == SemanticVersion(major: 1, minor: 0, patch: 0))
        #expect(SemanticVersion("1.4") == SemanticVersion(major: 1, minor: 4, patch: 0))
    }

    @Test func rejectsGarbage() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("abc") == nil)
        #expect(SemanticVersion("1.x.3") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
    }

    @Test func ordersByComponentSignificance() {
        #expect(SemanticVersion("1.0.0")! < SemanticVersion("2.0.0")!)
        #expect(SemanticVersion("1.2.0")! < SemanticVersion("1.10.0")!) // numeric, not lexical
        #expect(SemanticVersion("1.2.3")! < SemanticVersion("1.2.4")!)
        #expect(SemanticVersion("1.2.3")! == SemanticVersion("1.2.3")!)
        #expect(!(SemanticVersion("2.0.0")! < SemanticVersion("1.9.9")!))
    }

    @Test func descriptionRoundTrips() {
        #expect(SemanticVersion("0.2.0")!.description == "0.2.0")
        #expect(String(describing: SemanticVersion("v3.4")!) == "3.4.0")
    }
}

@Suite("UpdateAvailability")
struct UpdateAvailabilityTests {

    @Test func newerLatestMeansUpdateAvailable() {
        let r = UpdateAvailability(current: SemanticVersion("0.2.0")!, latest: SemanticVersion("0.3.0")!)
        #expect(r == .updateAvailable(SemanticVersion("0.3.0")!))
    }

    @Test func equalVersionsAreUpToDate() {
        let r = UpdateAvailability(current: SemanticVersion("0.2.0")!, latest: SemanticVersion("0.2.0")!)
        #expect(r == .upToDate)
    }

    @Test func olderLatestIsUpToDate() {
        // A dev build ahead of the published release shouldn't nag.
        let r = UpdateAvailability(current: SemanticVersion("0.3.0")!, latest: SemanticVersion("0.2.0")!)
        #expect(r == .upToDate)
    }
}
