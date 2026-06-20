import AppKit
import Foundation
import PhotonzCore

/// The thin network/Info.plist shell around the testable version-compare logic
/// in `SemanticVersion` (phase 11.6). Fetches the published `version.json` the
/// release pipeline keeps in lockstep (see docs/design/release.md) and reports
/// whether the running build is behind. No Sparkle — a lightweight custom check.
enum UpdateChecker {
    /// Published manifest, served from GitHub Pages alongside the marketing site.
    static let versionURL = URL(string: "https://dzearing.github.io/photonz/version.json")!
    /// Where to send the user when an update exists. `releases/latest` always
    /// resolves to the newest DMG (release.md), so no per-release edit is needed.
    static let downloadPageURL = URL(string: "https://github.com/dzearing/photonz/releases/latest")!

    /// Just the field we need from `version.json`.
    private struct Manifest: Decodable { let version: String }

    enum Result {
        case upToDate(current: SemanticVersion)
        case updateAvailable(current: SemanticVersion, latest: SemanticVersion)
        case failed(String)
    }

    /// The running build's version, read from the bundle's Info.plist (stamped
    /// from the `VERSION` file by build-app.sh). Falls back to 0.0.0 for plain
    /// `swift build` dev runs with no bundle — which makes any release look newer.
    static var currentVersion: SemanticVersion {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return raw.flatMap(SemanticVersion.init) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    static func check() async -> Result {
        let current = currentVersion
        do {
            var request = URLRequest(url: versionURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData  // never compare against a stale cache
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed("The update server returned an unexpected response.")
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            guard let latest = SemanticVersion(manifest.version) else {
                return .failed("Couldn't read the latest version number.")
            }
            switch UpdateAvailability(current: current, latest: latest) {
            case .upToDate: return .upToDate(current: current)
            case .updateAvailable(let v): return .updateAvailable(current: current, latest: v)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
