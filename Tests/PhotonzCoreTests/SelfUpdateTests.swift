import Foundation
import PhotonzCore
import Testing

@Suite("Self-update verification")
struct SelfUpdateTests {

    // Representative `codesign -dvv` output (it arrives on stderr).
    private let releaseOutput = """
    Executable=/Volumes/Photonz/Photonz.app/Contents/MacOS/Photonz
    Identifier=com.dzearing.photonz
    Format=app bundle with Mach-O thin (arm64)
    CodeDirectory v=20500 size=12345 flags=0x10000(runtime) hashes=100+7 location=embedded
    Signature size=8996
    Authority=Developer ID Application: David Zearing (ABCDE12345)
    Authority=Developer ID Certification Authority
    Authority=Apple Root CA
    Timestamp=Jul 6, 2026 at 3:41:00 PM
    Info.plist entries=23
    TeamIdentifier=ABCDE12345
    Runtime Version=26.0.0
    Sealed Resources version=2 rules=13 files=42
    Internal requirements count=1 size=180
    """

    private let devOutput = """
    Executable=/Users/x/git/photonz/dist/Photonz.app/Contents/MacOS/Photonz
    Identifier=com.dzearing.photonz
    Format=app bundle with Mach-O thin (arm64)
    Signature=adhoc
    TeamIdentifier=not set
    """

    // MARK: - CodesignInfo parsing

    @Test func parsesIdentifierAndTeam() {
        #expect(CodesignInfo.identifier(in: releaseOutput) == "com.dzearing.photonz")
        #expect(CodesignInfo.teamIdentifier(in: releaseOutput) == "ABCDE12345")
    }

    @Test func adhocTeamReadsAsNil() {
        #expect(CodesignInfo.identifier(in: devOutput) == "com.dzearing.photonz")
        #expect(CodesignInfo.teamIdentifier(in: devOutput) == nil)
    }

    @Test func missingFieldsReadAsNil() {
        #expect(CodesignInfo.identifier(in: "") == nil)
        #expect(CodesignInfo.teamIdentifier(in: "code object is not signed at all") == nil)
    }

    @Test func fieldPrefixesMustStartTheLine() {
        // "TeamIdentifier" appearing mid-line (e.g. in an Authority name) must
        // not be picked up.
        let tricky = "Authority=TeamIdentifier=EVIL\nTeamIdentifier=GOOD456789"
        #expect(CodesignInfo.teamIdentifier(in: tricky) == "GOOD456789")
    }

    // MARK: - Acceptance policy

    private let expected = "com.dzearing.photonz"

    @Test func acceptsMatchingIdentifierAndTeam() {
        let verdict = SelfUpdatePolicy.verdict(expectedIdentifier: expected,
                                               currentTeam: "ABCDE12345",
                                               newIdentifier: "com.dzearing.photonz",
                                               newTeam: "ABCDE12345")
        #expect(verdict == .accepted)
    }

    @Test func rejectsWrongBundleIdentifier() {
        let verdict = SelfUpdatePolicy.verdict(expectedIdentifier: expected,
                                               currentTeam: "ABCDE12345",
                                               newIdentifier: "com.evil.other",
                                               newTeam: "ABCDE12345")
        #expect(verdict != .accepted)
    }

    @Test func rejectsUnsignedOrAdhocDownload() {
        let verdict = SelfUpdatePolicy.verdict(expectedIdentifier: expected,
                                               currentTeam: "ABCDE12345",
                                               newIdentifier: "com.dzearing.photonz",
                                               newTeam: nil)
        #expect(verdict != .accepted)
    }

    @Test func rejectsTeamMismatch() {
        let verdict = SelfUpdatePolicy.verdict(expectedIdentifier: expected,
                                               currentTeam: "ABCDE12345",
                                               newIdentifier: "com.dzearing.photonz",
                                               newTeam: "ZZZZZ99999")
        #expect(verdict != .accepted)
    }

    @Test func devSignedCurrentBuildAcceptsAnyProperlySignedDownload() {
        // A self-signed dev build has no team to pin against; the download must
        // still be real-team signed (plus spctl notarization app-side).
        let verdict = SelfUpdatePolicy.verdict(expectedIdentifier: expected,
                                               currentTeam: nil,
                                               newIdentifier: "com.dzearing.photonz",
                                               newTeam: "ABCDE12345")
        #expect(verdict == .accepted)
    }
}
