import Foundation
import Testing

@testable import PhotonzCore

/// The queue refuses to call a task done when the only walks it names switch
/// on a feature that is off for a person running Next (2026-09-23: about
/// twenty video features were audited as ready while a switch that was off by
/// default hid every one). The queue is node, so it reads which switches start
/// on out of this catalog's source with `queue/bin/flag-defaults.mjs`. This
/// runs that reader and holds it to the catalog itself, so a new shape of
/// definition it cannot read fails here instead of quietly reading as off.
@Suite("Done needs the feature reachable at defaults")
struct FlagDefaultsReaderTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // Tests/PhotonzCoreTests/…
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
    }

    /// The loop runs on node, so it is on this Mac; where depends on how it
    /// was installed, and `swift test` does not promise the shell's PATH.
    private static func findNode() -> URL? {
        let fm = FileManager.default
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/node" }
        candidates += ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        let nvm = fm.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(atPath: nvm.path) {
            candidates += versions.sorted().reversed().map { nvm.appendingPathComponent("\($0)/bin/node").path }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Runs one of the queue's scripts with node: its exit status, what it
    /// printed and what it complained about.
    private static func runQueueScript(_ script: String, _ arguments: [String] = []) throws
        -> (status: Int32, out: Data, err: String) {
        let node = try #require(findNode(), "no node on this Mac, and the queue cannot run without it")
        let process = Process()
        process.executableURL = node
        process.arguments = [repoRoot.appendingPathComponent("queue/bin/\(script)").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        // The drill runs the queue CLI as a child, so node has to be findable.
        environment["PATH"] = node.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let problem = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, data, problem)
    }

    private static func readerSays() throws -> [String: [String: Bool]] {
        let run = try runQueueScript("flag-defaults.mjs", ["--json"])
        #expect(run.status == 0, "flag-defaults.mjs could not read the catalog: \(run.err)")
        return try JSONDecoder().decode([String: [String: Bool]].self, from: run.out)
    }

    @Test("A task whose only walk switches on a feature that is off by default is refused done")
    func theQueueRefusesDoneBehindASwitch() throws {
        // queue/bin/reach-drill.mjs builds a throwaway queue and switch list,
        // marks such a task done through the queue's own command, and checks
        // it is refused with the switch named, along with the cases that must
        // be let through.
        let run = try Self.runQueueScript("reach-drill.mjs")
        let printed = String(decoding: run.out, as: UTF8.self)
        #expect(run.status == 0, "reach-drill.mjs failed:\n\(printed)\(run.err)")
        #expect(printed.contains("PASS  done is refused when every walk turns on a switch that is off in Next"))
    }

    @Test("Every release's switches and where each starts match the catalog")
    func readerMatchesTheCatalog() throws {
        let said = try Self.readerSays()
        for release in Release.allCases {
            let reader = try #require(said[release.rawValue], "the reader says nothing about \(release)")
            let catalog = Dictionary(uniqueKeysWithValues:
                FeatureCatalog.flags(for: release).map { ($0.name, $0.isEnabled) })
            #expect(Set(reader.keys) == Set(catalog.keys),
                    "\(release): the reader and the catalog list different switches")
            for (name, on) in catalog {
                #expect(reader[name] == on, "\(release): \(name) starts \(on ? "on" : "off") but the reader says otherwise")
            }
        }
    }
}
