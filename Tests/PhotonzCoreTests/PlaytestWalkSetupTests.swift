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
                // One name is not a file: it means the guides' sample
                // recording, written fresh by the runner.
                if capture == PlaytestSetup.sampleRecordingToken { continue }
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
                // The two samples are written on demand rather than kept in the
                // repo, so there is no file to look for: what is checked is
                // that the walk names its copy by the name it will land under.
                if let sample = PlaytestSampleFile.copy(scratch) {
                    copies.insert(sample.fileName)
                    continue
                }
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

    /// Menus that are a list of ACTIONS rather than a value: the plus on the
    /// Effects header is a button that always says "+", so what you pick from
    /// it is a thing to do and never a word some menu is now wearing. Picking
    /// Shadow from it and then opening the Shadow row's own menu is the normal
    /// flow, not the mistake the rule below is about.
    private static let actionMenus: Set<String> = ["Add Effect"]

    /// A menu in the dock wears its own value, so a walk that names one by the
    /// words on it is naming something that changes the moment the walk uses
    /// it. The row it sits on holds still; that is its name.
    @Test("No walk names a menu by a value that walk is about to change")
    func menusAreNamedByTheirRowNotTheirValue() throws {
        for file in try Self.walkFiles() {
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            var opened: [String] = []
            for step in script.steps {
                guard case .panelMenu(let menu, _, _, let choose, _) = step else { continue }
                guard !Self.actionMenus.contains(menu) else { continue }
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

    /// The other half of the same promise, and the one 252 of the 497 walks in
    /// this folder were quietly missing on 2026-09-16: a walk that names
    /// nothing in `forget` starts from whatever the last thing to use this
    /// machine happened to leave behind.
    ///
    /// Measured on that date, the probe's own settings held a remembered text
    /// face of Georgia, a tutorial stopped six steps in, three layer groups
    /// left open on a fixture, and a dock section order one migration out of
    /// date. Every walk that did not say `forget` inherited all four, so it was
    /// passing or failing on the history of the machine rather than on the app,
    /// and two walks were reported as disagreeing with themselves about one run
    /// in thirty.
    ///
    /// So the line is not optional. `"forget": ["all"]` is the whole of it for
    /// a walk with no opinion, and a walk that names areas is saying it wants
    /// the rest inherited on purpose.
    @Test("Every walk says what it wants forgotten")
    func everyWalkNamesWhatItForgets() throws {
        let files = try Self.walkFiles()
        try #require(!files.isEmpty, "no walks found in \(Self.walkDirectory.path)")

        var silent: [String] = []
        for file in files {
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            if script.setup.forget.isEmpty { silent.append(file.lastPathComponent) }
        }
        #expect(silent.isEmpty, """
            \(silent.count) walk(s) never say what they want forgotten, so each one starts \
            from whatever the last run on the machine left behind and means something \
            different on every machine: \(silent.prefix(12).joined(separator: ", "))\
            \(silent.count > 12 ? ", and \(silent.count - 12) more" : ""). Give each a \
            setup block with "forget": ["all"], or name the areas it wants cleared.
            """)
    }
}

/// A walk about the tracks starts with them showing, the way a person who
/// last left a recording's timeline open finds it; a walk about opening a
/// recording to watch says nothing and gets the tucked-away default.
@Suite("A walk says how the timeline was last left")
struct PlaytestTimelineSetupTests {

    @Test("it reads open or put away")
    func reads() throws {
        let open = try PlaytestScript.decode(Data("""
        { "setup": { "forget": ["all"], "timelineOpen": true }, "steps": [ { "do": "wait", "seconds": 0 } ] }
        """.utf8))
        #expect(open.setup.timelineOpen == true)
        #expect(open.setup.isEmpty == false)
        let away = try PlaytestScript.decode(Data("""
        { "setup": { "timelineOpen": false }, "steps": [ { "do": "wait", "seconds": 0 } ] }
        """.utf8))
        #expect(away.setup.timelineOpen == false)
    }

    @Test("saying nothing leaves it to the app")
    func unsaid() throws {
        let script = try PlaytestScript.decode(Data("""
        { "setup": { "forget": ["all"] }, "steps": [ { "do": "wait", "seconds": 0 } ] }
        """.utf8))
        #expect(script.setup.timelineOpen == nil)
    }

    @Test("it is a yes or a no")
    func onlyABool() {
        #expect(throws: PlaytestScriptError.self) {
            try PlaytestScript.decode(Data("""
            { "setup": { "timelineOpen": "yes" }, "steps": [ { "do": "wait", "seconds": 0 } ] }
            """.utf8))
        }
    }
}
