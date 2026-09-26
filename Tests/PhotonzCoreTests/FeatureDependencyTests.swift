import Foundation
import Testing

@testable import PhotonzCore

/// A flag that only does anything inside something another flag opens is a
/// feature nobody can reach while that other flag is off. On 2026-09-23 about
/// twenty video features were on by default in Next and every one of them lived
/// in the editor `next-a-recording-is-a-document` opens, which was OFF by
/// default, so a person opening a recording got none of them. Walks set the
/// flag themselves, so nothing noticed. These tests are what notices now.
@Suite("What a flag needs to be reachable")
struct FeatureDependencyTests {

    @Test("A flag on by default never needs a flag that is off by default")
    func onByDefaultNeverNeedsSomethingOff() {
        for release in Release.allCases {
            let settings = FeatureCatalog.defaultSettings(for: release)
            for flag in FeatureCatalog.flags(for: release) where flag.isEnabled {
                for needed in FeatureCatalog.dependencies(of: flag.name) {
                    #expect(settings.isEnabled(needed),
                            "\(flag.name) is on by default in \(release) but needs \(needed), which is off")
                }
            }
        }
    }

    @Test("A flag only ever needs flags the catalog knows")
    func dependenciesNameRealFlags() {
        let every = Set(Release.allCases.flatMap { FeatureCatalog.flags(for: $0).map(\.name) })
        for name in every {
            for needed in FeatureCatalog.dependencies(of: name) {
                #expect(every.contains(needed), "\(name) needs \(needed), which is not a flag")
                #expect(needed != name, "\(name) needs itself")
            }
        }
    }

    @Test("A recording has one way in: no switch brings the old window back")
    func theRecordingWindowSwitchIsGone() {
        // Until 2026-09-26 `next-a-recording-is-a-document` chose between the
        // editor and the small recording window, and everything on the
        // timeline needed it. Next opens every recording in the editor now,
        // so nothing may ask for it and no release may offer it.
        for release in Release.allCases {
            #expect(!FeatureCatalog.flags(for: release).contains { $0.name == "next-a-recording-is-a-document" })
        }
        for flag in Release.allCases.flatMap({ FeatureCatalog.flags(for: $0) }) {
            #expect(!FeatureCatalog.dependencies(of: flag.name).contains("next-a-recording-is-a-document"),
                    "\(flag.name)")
        }
    }

    @Test("An unknown flag needs nothing")
    func unknownFlagNeedsNothing() {
        #expect(FeatureCatalog.dependencies(of: "no-such-flag").isEmpty)
    }
}
