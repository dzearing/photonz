import AppKit
import PhotonzCore

/// In-place self-update: download the published DMG for a version, verify the
/// app inside (codesign integrity, notarization via spctl, and identity via
/// `SelfUpdatePolicy` — same bundle id, same signing team as the running
/// build), stage a copy, swap it over the installed bundle, and let the
/// coordinator relaunch. The old bundle goes to the Trash, so even a botched
/// update is recoverable. No Sparkle — the release pipeline already publishes
/// everything this needs (a stapled DMG at a stable per-version URL).
enum SelfUpdater {

    enum UpdateError: LocalizedError {
        case notInstalledAsBundle
        case downloadFailed(String)
        case mountFailed(String)
        case appMissingFromDMG
        case verificationFailed(String)
        case swapFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalledAsBundle:
                return "This build isn't running from an app bundle, so it can't update itself."
            case .downloadFailed(let detail):
                return "Couldn't download the update: \(detail)"
            case .mountFailed(let detail):
                return "Couldn't open the downloaded disk image: \(detail)"
            case .appMissingFromDMG:
                return "The downloaded disk image doesn't contain Photonz.app."
            case .verificationFailed(let detail):
                return "The downloaded app failed verification and was NOT installed: \(detail)"
            case .swapFailed(let detail):
                return "Couldn't replace the installed app: \(detail)"
            }
        }
    }

    /// The release pipeline's stable per-version asset URL (release.md).
    static func dmgURL(for version: SemanticVersion) -> URL {
        URL(string: "https://github.com/dzearing/photonz/releases/download/v\(version)/Photonz.dmg")!
    }

    /// Download → mount → verify → stage → swap. On return the new version sits
    /// at `bundleURL` and the old one is in the Trash; the caller terminates +
    /// relaunches. `progress` receives short user-facing phase strings.
    static func install(version: SemanticVersion, over bundleURL: URL,
                        progress: @MainActor (String) -> Void) async throws {
        guard bundleURL.pathExtension == "app" else { throw UpdateError.notInstalledAsBundle }

        await progress("Downloading v\(version)…")
        let dmg: URL
        do {
            let (temp, response) = try await URLSession.shared.download(from: dmgURL(for: version))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.downloadFailed("the server returned an unexpected response")
            }
            // Give it a stable name + extension in our own scratch dir.
            dmg = scratchDirectory().appendingPathComponent("Photonz-v\(version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            try FileManager.default.moveItem(at: temp, to: dmg)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }

        await progress("Verifying…")
        let mountPoint = scratchDirectory().appendingPathComponent("mount", isDirectory: true)
        _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])  // stale mount from a failed run
        let attach = try await run("/usr/bin/hdiutil",
                                   ["attach", dmg.path, "-nobrowse", "-readonly",
                                    "-mountpoint", mountPoint.path])
        guard attach.status == 0 else { throw UpdateError.mountFailed(attach.output.suffix(200).description) }

        do {
            let mountedApp = mountPoint.appendingPathComponent("Photonz.app")
            guard FileManager.default.fileExists(atPath: mountedApp.path) else {
                throw UpdateError.appMissingFromDMG
            }
            try await verify(candidate: mountedApp, against: bundleURL)

            await progress("Installing…")
            // Copy off the read-only image before detaching. `ditto` preserves
            // the signature-relevant metadata a plain copy can drop.
            let staged = scratchDirectory().appendingPathComponent("staged/Photonz.app")
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let copy = try await run("/usr/bin/ditto", [mountedApp.path, staged.path])
            guard copy.status == 0 else { throw UpdateError.swapFailed("couldn't stage the new app") }
            _ = try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
            _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path])

            try swap(staged: staged, over: bundleURL)
        } catch {
            _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            throw error
        }
    }

    /// Integrity (codesign --verify), notarized Developer ID (spctl), and
    /// identity (bundle id + team pin) — the identity ruling is the tested
    /// `SelfUpdatePolicy`.
    private static func verify(candidate: URL, against currentBundle: URL) async throws {
        let integrity = try await run("/usr/bin/codesign",
                                      ["--verify", "--deep", "--strict", candidate.path])
        guard integrity.status == 0 else {
            throw UpdateError.verificationFailed("code signature is invalid")
        }
        let gatekeeper = try await run("/usr/sbin/spctl", ["--assess", "--type", "exec", candidate.path])
        guard gatekeeper.status == 0 else {
            throw UpdateError.verificationFailed("Gatekeeper did not accept the app (not notarized?)")
        }
        let newInfo = try await run("/usr/bin/codesign", ["-dvv", candidate.path])
        let currentInfo = try await run("/usr/bin/codesign", ["-dvv", currentBundle.path])
        let expected = Bundle.main.bundleIdentifier ?? "com.dzearing.photonz"
        let verdict = SelfUpdatePolicy.verdict(
            expectedIdentifier: expected,
            currentTeam: CodesignInfo.teamIdentifier(in: currentInfo.output),
            newIdentifier: CodesignInfo.identifier(in: newInfo.output),
            newTeam: CodesignInfo.teamIdentifier(in: newInfo.output))
        if case .rejected(let reason) = verdict {
            throw UpdateError.verificationFailed(reason)
        }
    }

    /// Trash the running bundle (its open files keep their inode, so the
    /// process is unaffected) and move the staged app into its place.
    private static func swap(staged: URL, over bundleURL: URL) throws {
        do {
            try FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
        } catch {
            // Trash can fail across volumes/permissions; fall back to a
            // sideways rename so the destination is still freed.
            let aside = bundleURL.deletingLastPathComponent()
                .appendingPathComponent("Photonz-previous.app")
            try? FileManager.default.removeItem(at: aside)
            do {
                try FileManager.default.moveItem(at: bundleURL, to: aside)
            } catch {
                throw UpdateError.swapFailed(error.localizedDescription)
            }
        }
        do {
            try FileManager.default.moveItem(at: staged, to: bundleURL)
        } catch {
            throw UpdateError.swapFailed(error.localizedDescription)
        }
    }

    private static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotonzUpdate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Run a tool to completion off the main actor, capturing stdout+stderr
    /// combined (codesign reports on stderr).
    private static func run(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (finished.terminationStatus, output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
