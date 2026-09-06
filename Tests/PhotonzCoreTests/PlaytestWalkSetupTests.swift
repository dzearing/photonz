import Foundation
import PhotonzCore
import Testing

/// A walk that only passes the first time it is ever run on a machine is worse
/// than no walk: it hands back a failure that is not real, and a set of walks
/// with one of those in it stops being worth reading.
///
/// Two ways in were found on 2026-09-04. One walk needed a picture copied into
/// the Screenshots folder first and said so only in prose, so it failed for
/// anyone who had not read the note. Another changed the remembered text size
/// and then went looking for the old size next time round.
///
/// Both are now one line of the walk — a `setup` block the runner performs —
/// and this holds every walk in the folder to it, so neither can come back.
@Suite("Playtest walks say what they need set up")
struct PlaytestWalkSetupTests {

    /// The walk folder, found from this file rather than from the working
    /// directory, which `swift test` does not promise anything about.
    private static var walkDirectory: URL {
        URL(fileURLWithPath: #filePath)          // Tests/PhotonzCoreTests/…
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Scripts/playtest")
    }

    private static func walkFiles() throws -> [URL] {
        let directory = walkDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A `seed` note says what a walk IS, for whoever reads it. The moment it
    /// starts saying what to DO first, it is setup, and only a person can carry
    /// it out. These are the words a walk's prose uses when that has happened.
    private static let instructionMarkers = [
        "before running", "before you run", "beforehand", "first run",
        "cp \"", "cp ", "mkdir", "~/",
    ]

    @Test("No walk hides setup in a note only a person can carry out")
    func setupIsNeverLeftInProse() throws {
        let files = try Self.walkFiles()
        try #require(!files.isEmpty, "no walks found in \(Self.walkDirectory.path)")

        for file in files {
            let top = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            guard let seed = top?["seed"] as? String else { continue }
            let lowered = seed.lowercased()
            let found = Self.instructionMarkers.filter { lowered.contains($0) }
            #expect(found.isEmpty, """
                \(file.lastPathComponent) tells the reader to do something first \
                ("\(found.joined(separator: "\", \""))"), which nothing enforces, so \
                the walk fails for anyone who did not read the note. Say it in the \
                walk's "setup" block instead — "forget" for a remembered setting, \
                "captures" for a picture the Library shelf needs — and the runner \
                does it, and undoes it, every time.
                """)
        }
    }

    /// A walk naming a fixture that is not there would fail at run time with a
    /// puzzle rather than an answer, and the failure would only show on the
    /// machine that ran it.
    @Test("Every picture a walk borrows for the capture folder exists")
    func lentCapturesExist() throws {
        for file in try Self.walkFiles() {
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            for capture in script.setup.captures {
                let url = capture.hasPrefix("/")
                    ? URL(fileURLWithPath: capture)
                    : file.deletingLastPathComponent().appendingPathComponent(capture).standardizedFileURL
                #expect(FileManager.default.fileExists(atPath: url.path), """
                    \(file.lastPathComponent) borrows the capture "\(capture)", and there \
                    is no such file at \(url.path).
                    """)
            }
        }
    }

    /// Same again for the walk's own working copies, and for the other half of
    /// it: a step that names "scratch/..." in a walk that never asked for a
    /// folder would fail at run time on a machine nobody is watching.
    @Test("Every file a walk works on a copy of exists, and nothing names a folder it never asked for")
    func scratchFilesExistAndAreAskedFor() throws {
        for file in try Self.walkFiles() {
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            var copies: Set<String> = []
            for scratch in script.setup.scratch {
                let url = scratch.hasPrefix("/")
                    ? URL(fileURLWithPath: scratch)
                    : file.deletingLastPathComponent().appendingPathComponent(scratch).standardizedFileURL
                #expect(FileManager.default.fileExists(atPath: url.path), """
                    \(file.lastPathComponent) works on a copy of "\(scratch)", and there \
                    is no such file at \(url.path).
                    """)
                copies.insert(url.lastPathComponent)
            }
            let text = try String(decoding: Data(contentsOf: file), as: UTF8.self)
            for named in Self.scratchPaths(in: text) {
                #expect(copies.contains(named), """
                    \(file.lastPathComponent) names "scratch/\(named)", and its setup block never \
                    asked for a copy of it. Add the file to "scratch" in setup, or the walk fails \
                    the moment it runs anywhere.
                    """)
            }
        }
    }

    /// The names a walk uses after `scratch/`, read out of the text so a step
    /// that takes a file in some future shape is covered without being listed.
    private static func scratchPaths(in text: String) -> [String] {
        text.components(separatedBy: "\"scratch/").dropFirst().compactMap { rest in
            rest.firstIndex(of: "\"").map { String(rest[rest.startIndex..<$0]) }
        }
    }

    /// A menu in the dock wears its own value, so a walk that names one by the
    /// words on it is naming something that changes the moment the walk uses
    /// it. The row it sits on holds still; that is its name.
    @Test("No walk names a menu by a value that walk is about to change")
    func menusAreNamedByTheirRowNotTheirValue() throws {
        for file in try Self.walkFiles() {
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            var opened: [String] = []
            for step in script.steps {
                guard case .panelMenu(let menu, _, let choose) = step else { continue }
                #expect(!opened.contains(menu), """
                    \(file.lastPathComponent) opens a menu called "\(menu)" after an \
                    earlier step already chose that value from one, so the second run \
                    of this walk finds a menu saying something else. Name the menu by \
                    the row it sits on ("Size", "Vertical") rather than by the words \
                    it happens to be showing.
                    """)
                if let choose { opened.append(choose) }
            }
        }
    }
}
