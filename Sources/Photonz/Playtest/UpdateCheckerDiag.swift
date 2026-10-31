#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

/// Probe-only answer to one question (`--update-check-diag`): against the REAL
/// servers, what does Check for Updates report, and what does a refused
/// download say? A walk cannot answer it, because the result is a modal alert
/// and the probe's own version is whatever `VERSION` says today.
///
///  * `--as-version 0.20.0` checks as if the running build were that version.
///  * `--version-url http://127.0.0.1:8000/version.json` reads a stub of the
///    website's version file instead of the published one (a release named
///    before its download exists).
///  * `--download-version 0.99.0` also asks for that version's DMG the way
///    Update & Restart does and reports the message a person would read. The
///    file goes to the scratch folder and is deleted; nothing is installed.
///
/// Writes /tmp/photonz-update-check-diag.txt and quits.
@MainActor
enum UpdateCheckerDiag {
    static let argument = "--update-check-diag"

    static func runIfRequested() {
        guard AppInfo.flavor == .probe, CommandLine.arguments.contains(argument) else { return }
        Task { await run() }
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func run() async {
        var out: [String] = []
        let current = value(after: "--as-version").flatMap(SemanticVersion.init) ?? UpdateChecker.currentVersion
        let versionURL = value(after: "--version-url").flatMap(URL.init(string:)) ?? UpdateChecker.versionURL
        out.append("running as: \(current)")
        out.append("version file: \(versionURL.absoluteString)")
        switch await UpdateChecker.check(current: current, versionURL: versionURL) {
        case .upToDate(let v): out.append("check: up to date (\(v))")
        case .updateAvailable(_, let latest): out.append("check: offers \(latest)")
        case .failed(let message): out.append("check: failed: \(message)")
        }
        if let raw = value(after: "--download-version"), let version = SemanticVersion(raw) {
            do {
                let dmg = try await SelfUpdater.download(version: version)
                try? FileManager.default.removeItem(at: dmg)
                out.append("download \(version): downloaded")
            } catch {
                out.append("download \(version): \(error.localizedDescription)")
            }
        }
        let text = out.joined(separator: "\n") + "\n"
        try? text.write(toFile: "/tmp/photonz-update-check-diag.txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
#endif
