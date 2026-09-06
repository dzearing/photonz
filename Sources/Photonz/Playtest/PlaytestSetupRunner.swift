// Putting the machine right before a walk starts, and putting it back after.
//
// The probe keeps its settings between runs on purpose: that is what a person's
// app does, and a walk that assumed a fresh state would be lying about what the
// app is like. The cost showed up on 2026-09-04, when two walks turned out to
// pass only the first time they were ever run on a machine. One changed the
// remembered text size from 24 to 48 and then, next run, went looking for a 24
// that was no longer there. The other needed a picture copied into the
// Screenshots folder first and said so only in a note a person had to read.
//
// So a walk SAYS what it needs, in its `setup` block, and this performs it:
// forgetting the settings it names, and lending it the pictures it names for
// the length of the run. Everything lent is taken away again when the run ends,
// pass or fail, so a walk never leaves anything behind in someone's folder.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

/// The `UserDefaults` keys behind each area of memory a walk can forget.
///
/// The keys are read from the types that own them rather than spelled again
/// here, so a renamed setting cannot leave a walk quietly forgetting nothing.
@MainActor
extension PlaytestMemory {
    var defaultsKeys: [String] {
        switch self {
        case .text:
            [EditorState.textStylesKey]
        case .color:
            [EditorState.recentColorsKey, EditorState.foregroundFillKey, EditorState.backgroundFillKey,
             DesignedColorPicker.scopeKey]
        case .shapes:
            [EditorState.annotationStylesKey, EditorState.calloutStylesKey]
        case .measure:
            [EditorState.measureModeKey, EditorState.measureStylesKey]
        case .tools:
            EditorState.toolMemoryKeys + [EditorState.wandToleranceKey]
        case .groups:
            [EditorState.openGroupsKey]
        case .panel:
            [EditorState.inspectorVisibleKey, EditorState.libraryVisibleKey,
             EditorState.inspectorWidthKey, LibraryPanel.scopeKey,
             InspectorPanel.sectionOrderKey, InspectorPanel.sectionOrderVersionKey,
             InspectorPanel.collapsedKey,
             LayersListView.heightKey, LibraryPanel.heightKey]
        case .grid:
            [EditorState.canvasGridKey]
        case .frames:
            [EditorState.lastFrameSizeKey]
        }
    }
}

/// Carries out a walk's `setup` block and undoes the borrowing afterwards.
@MainActor
struct PlaytestSetupRunner {
    /// Files this run put into the capture folder, to take away again.
    private(set) var lentCaptures: [URL] = []
    /// The walk's own empty folder, made fresh for this run and thrown away
    /// at the end. A walk names a file in it as "scratch/<name>".
    private(set) var scratchDirectory: URL?
    /// Every remembered setting as it stood before step one, so the machine can
    /// be put back exactly as the walk found it. Taken for ALL of them, not
    /// only the ones a walk declared, because the walk that poisons the next
    /// one is by definition the walk that did not know it was changing
    /// anything.
    private var settingsBefore: [String: Data] = [:]
    /// What this walk declared, kept so the log can say what it changed on top
    /// of that.
    private var declared: [PlaytestMemory] = []
    /// Whether a reading was ever taken. A script that does not even parse
    /// fails before setup runs, and putting settings "back" from a reading
    /// that was never taken would wipe every one of them.
    private var tookReading = false

    /// Which keys belong to which area of memory, read from the memories
    /// themselves so a renamed setting cannot slip out of the net.
    private static var allKeys: [PlaytestMemory: [String]] {
        Dictionary(uniqueKeysWithValues: PlaytestMemory.allCases.map { ($0, $0.defaultsKeys) })
    }

    /// Performs the setup, returning what to say about it in the log.
    ///
    /// Throws when something it was asked for cannot be done — a missing
    /// picture, or a name already taken in the capture folder — because a walk
    /// that starts anyway is a walk whose failure means nothing.
    mutating func perform(_ setup: PlaytestSetup, besides scriptURL: URL) throws -> String {
        settingsBefore = Self.readSettings()
        tookReading = true
        declared = setup.forget
        var said: [String] = []
        if !setup.forget.isEmpty {
            let keys = setup.forget.flatMap(\.defaultsKeys)
            for key in keys { UserDefaults.standard.removeObject(forKey: key) }
            UserDefaults.standard.synchronize()
            // Anything the app holds in memory rather than reading fresh has to
            // be told, or it goes on drawing what was just thrown away.
            if setup.forget.contains(.grid) { CanvasGridStore.shared.reload() }
            said.append("forgot \(setup.forget.map(\.rawValue).joined(separator: ", "))"
                        + " (\(keys.count) settings)")
        }
        if !setup.captures.isEmpty {
            let placed = try lend(setup.captures, besides: scriptURL)
            said.append("lent the capture folder \(placed.joined(separator: ", "))")
        }
        if !setup.scratch.isEmpty {
            let placed = try makeScratch(setup.scratch, besides: scriptURL)
            said.append("gave the walk its own copy of \(placed.joined(separator: ", "))")
        }
        return said.isEmpty ? "nothing asked for" : said.joined(separator: "; ")
    }

    /// Copies each picture into the capture folder the Media shelf reads, and
    /// remembers it so `returnCaptures` can take it away again.
    private mutating func lend(_ files: [String], besides scriptURL: URL) throws -> [String] {
        let folder = CaptureStore.defaultDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var placed: [String] = []
        for file in files {
            let source = file.hasPrefix("/")
                ? URL(fileURLWithPath: file)
                : scriptURL.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw PlaytestSetupError(
                    description: "setup asks for the capture \"\(file)\", and there is no such file at \(source.path)")
            }
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            // Never write over what is already there: the capture folder is a
            // person's own Screenshots folder, and the tidying up at the end
            // would then delete a picture this walk never put there.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw PlaytestSetupError(
                    description: "setup would lend \"\(source.lastPathComponent)\" to \(folder.path), "
                        + "but a file of that name is already there; move it aside or rename the fixture")
            }
            try FileManager.default.copyItem(at: source, to: destination)
            lentCaptures.append(destination)
            placed.append(source.lastPathComponent)
        }
        return placed
    }

    /// Makes the walk an empty folder of its own and copies its files into it.
    ///
    /// Fresh every run, so a walk that writes beside the picture it opened —
    /// keeping layers next to it, say — starts from the same nothing every
    /// time instead of finding what it wrote last time.
    private mutating func makeScratch(_ files: [String], besides scriptURL: URL) throws -> [String] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-playtest-scratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        scratchDirectory = folder
        var placed: [String] = []
        for file in files {
            let source = file.hasPrefix("/")
                ? URL(fileURLWithPath: file)
                : scriptURL.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw PlaytestSetupError(
                    description: "setup asks for the scratch file \"\(file)\", and there is no such file at \(source.path)")
            }
            try FileManager.default.copyItem(
                at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            placed.append(source.lastPathComponent)
        }
        return placed
    }

    /// Throws the walk's own folder away, with everything it wrote in it.
    mutating func clearScratch() -> String? {
        guard let folder = scratchDirectory else { return nil }
        try? FileManager.default.removeItem(at: folder)
        scratchDirectory = nil
        return "threw away the walk's own folder"
    }

    /// Puts every remembered setting back to what it was before step one, and
    /// says what had to be put back.
    ///
    /// This is what stops the ORDER of the walks changing their answers. A walk
    /// runs against a machine that remembers things, the way a person's does,
    /// and hands the next walk the machine it started with. Called however the
    /// run ends, so a walk that failed halfway still leaves nothing behind.
    mutating func restoreSettings() -> String {
        guard tookReading else { return "the walk never started, so nothing was touched" }
        let ledger = PlaytestMemoryLedger(before: settingsBefore,
                                          after: Self.readSettings(),
                                          keys: Self.allKeys)
        for (key, value) in ledger.restore {
            if let value, let restored = Self.decode(value) {
                UserDefaults.standard.set(restored, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if !ledger.restore.isEmpty { UserDefaults.standard.synchronize() }
        let quiet = ledger.undeclared(given: declared)
        guard !quiet.isEmpty else { return ledger.report }
        // Not a failure: the machine is already back. It is the line whoever
        // writes the next walk wants, because a setting this walk changed
        // without saying so is one it may be reading later without saying so.
        return ledger.report + "; changed without saying so: "
            + quiet.map(\.rawValue).joined(separator: ", ")
    }

    /// Every remembered setting, encoded so two readings can be compared and
    /// one of them handed back. A property list of one element takes whatever
    /// `UserDefaults` holds — a flag, a word, a number, a blob — without this
    /// having to know which.
    private static func readSettings() -> [String: Data] {
        var reading: [String: Data] = [:]
        for key in PlaytestMemory.allCases.flatMap(\.defaultsKeys) {
            guard let value = UserDefaults.standard.object(forKey: key),
                  let data = try? PropertyListSerialization.data(
                    fromPropertyList: [value], format: .binary, options: 0) else { continue }
            reading[key] = data
        }
        return reading
    }

    private static func decode(_ data: Data) -> Any? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any])??.first
    }

    /// Takes back everything this run lent the capture folder. Called however
    /// the run ends, so a failure halfway through still tidies up.
    mutating func returnCaptures() -> String? {
        guard !lentCaptures.isEmpty else { return nil }
        let names = lentCaptures.map(\.lastPathComponent)
        for url in lentCaptures { try? FileManager.default.removeItem(at: url) }
        lentCaptures = []
        return "took back \(names.joined(separator: ", "))"
    }
}

struct PlaytestSetupError: Error, CustomStringConvertible {
    let description: String
}
#endif
