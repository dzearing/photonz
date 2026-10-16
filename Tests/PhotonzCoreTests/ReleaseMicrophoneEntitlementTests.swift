import Foundation
import Testing

/// v0.17.0 shipped signed with the hardened runtime and no entitlements, so
/// macOS refused the microphone without a prompt and never listed Photonz under
/// Privacy & Security > Microphone: recording with sound was impossible in the
/// app people download. These pin the three pieces that keep it fixed.
@Suite("Release microphone entitlement")
struct ReleaseMicrophoneEntitlementTests {

    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // Tests/PhotonzCoreTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // repo root

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func entitlementsFileGrantsAudioInput() throws {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("Resources/Photonz.entitlements"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["com.apple.security.device.audio-input"] as? Bool == true)
    }

    @Test func developerIDSigningPassesTheEntitlements() throws {
        let script = try Self.text("Scripts/build-app.sh")
        let hardened = script.split(separator: "\n").filter { $0.contains("--options runtime") }
        #expect(!hardened.isEmpty)
        for line in hardened {
            #expect(line.contains("--entitlements"), "hardened runtime signing without entitlements: \(line)")
        }
        #expect(script.contains("check-entitlements.sh"))
    }

    @Test func releaseWorkflowChecksThePublishedBundle() throws {
        let workflow = try Self.text(".github/workflows/release.yml")
        #expect(workflow.contains("Scripts/check-entitlements.sh dist/Photonz.app"))
    }
}
