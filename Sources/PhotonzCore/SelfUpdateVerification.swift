import Foundation

/// Pure parsing/decision logic for the in-app self-updater. The updater
/// (app-side `SelfUpdater`) downloads the published DMG and verifies the app
/// inside with `codesign`/`spctl`; these helpers keep the *judgment* testable:
/// what the codesign output says, and whether that's acceptable to install.
public enum CodesignInfo {
    /// The `Identifier=` field of `codesign -dvv` output (nil when absent).
    public static func identifier(in output: String) -> String? {
        field("Identifier", in: output)
    }

    /// The `TeamIdentifier=` field, nil for ad-hoc/unsigned code (codesign
    /// prints `TeamIdentifier=not set`).
    public static func teamIdentifier(in output: String) -> String? {
        guard let team = field("TeamIdentifier", in: output), team != "not set" else { return nil }
        return team
    }

    /// First line starting exactly `key=`; prefix-anchored so the key appearing
    /// inside another field's value can't spoof it.
    private static func field(_ key: String, in output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("\(key)=") {
                let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

/// Whether a downloaded app bundle may replace the running one. Signature
/// *validity* is established app-side (`codesign --verify`, `spctl --assess`);
/// this rules on identity: same bundle id, and — when the running build has a
/// real signing team — the same team, so a valid-but-foreign signature can
/// never be installed over Photonz.
public enum SelfUpdatePolicy {
    public enum Verdict: Equatable, Sendable {
        case accepted
        case rejected(String)
    }

    public static func verdict(expectedIdentifier: String,
                               currentTeam: String?,
                               newIdentifier: String?,
                               newTeam: String?) -> Verdict {
        guard newIdentifier == expectedIdentifier else {
            return .rejected("The downloaded app identifies as \(newIdentifier ?? "nothing"), expected \(expectedIdentifier).")
        }
        guard let newTeam else {
            return .rejected("The downloaded app is not signed by a Developer ID team.")
        }
        if let currentTeam, newTeam != currentTeam {
            return .rejected("The downloaded app is signed by team \(newTeam), but this build is signed by \(currentTeam).")
        }
        return .accepted
    }
}
