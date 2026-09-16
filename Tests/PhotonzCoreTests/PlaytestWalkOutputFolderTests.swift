import Foundation
import PhotonzCore
import Testing

/// A walk writes megabytes: a render and a window capture per picture, plus a
/// log and a report. None of that belongs in the working copy, and once it is
/// there a `git add -A` sweeps it into a commit. `panel-says-less-walk.json`
/// named no `out` at all, so it fell into the old default of a folder beside
/// its own script, which is inside the repository, and left 2.6MB of pictures
/// in `Scripts/playtest/out` every time it ran.
///
/// The default now lands in the scratch folder, so silence is safe. This holds
/// the folder to the other half of the rule: a walk that DOES name an `out`
/// must not name one inside the repository either.
@Suite("Playtest walks write outside the repository")
struct PlaytestWalkOutputFolderTests {

    /// The repo root, found from this file rather than from the working
    /// directory, which `swift test` does not promise anything about.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/PhotonzCoreTests/…
            .deletingLastPathComponent()      // Tests/PhotonzCoreTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .standardizedFileURL
    }

    private static var walkDirectory: URL {
        repositoryRoot.appendingPathComponent("Scripts/playtest")
    }

    private static func walkFiles() throws -> [URL] {
        let directory = walkDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("No walk's pictures land inside the repository")
    func noWalkWritesIntoTheWorkingCopy() throws {
        let files = try Self.walkFiles()
        try #require(!files.isEmpty, "no walks found in \(Self.walkDirectory.path)")

        let root = Self.repositoryRoot.path + "/"
        for file in files {
            let out = PlaytestScript
                .outputDirectory(besides: file, in: try Data(contentsOf: file))
                .standardizedFileURL.path
            #expect(!out.hasPrefix(root),
                    """
                    \(file.lastPathComponent) writes to \(out), which is inside \
                    the repository. Give it an "out" under \
                    \(PlaytestScript.scratchRoot), or drop the key and take the \
                    default.
                    """)
        }
    }
}
