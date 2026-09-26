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

    @Test("Everything that lives on the timeline needs the recording to open in the editor")
    func timelineFeaturesNeedTheEditor() {
        let timeline = [
            FeatureCatalog.videoExportFlag,
            FeatureCatalog.timelineZoomFlag,
            FeatureCatalog.transitionsAtACutFlag,
            FeatureCatalog.punchInFlag,
            FeatureCatalog.titleOnTheTimelineFlag,
            FeatureCatalog.captionsFromTheSoundFlag,
            FeatureCatalog.componentOnTheTimelineFlag,
            FeatureCatalog.drawnOnTheTimelineFlag,
            FeatureCatalog.soundOnTheTimelineFlag,
            FeatureCatalog.scrubAuditionFlag,
            FeatureCatalog.mixLoudnessFlag,
        ]
        for name in timeline {
            #expect(FeatureCatalog.dependencies(of: name).contains(FeatureCatalog.recordingIsADocumentFlag),
                    "\(name) lives on the timeline but does not say it needs the editor")
        }
    }

    @Test("A recording opens in the editor by default in Next")
    func aRecordingIsADocumentInNext() {
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .isEnabled(FeatureCatalog.recordingIsADocumentFlag))
    }

    @Test("An unknown flag needs nothing")
    func unknownFlagNeedsNothing() {
        #expect(FeatureCatalog.dependencies(of: "no-such-flag").isEmpty)
    }
}
