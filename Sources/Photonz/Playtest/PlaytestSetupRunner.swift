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
            // The lens's two memories are listed BY HAND because they are not
            // "which member of the family the button is wearing", which is all
            // `toolMemoryKeys` covers. They are what the lens will next DRAW:
            // the kind, and the numbers each adjustment was last set to.
            //
            // Left out, they turned every walk that draws a lens into a walk
            // whose answer depended on what ran before it. The probe's stored
            // kind was `magnify` on 2026-09-17, left behind by some earlier
            // run, so the blur guide's own walk drew a MAGNIFIER over the
            // address while its card said everything under the box goes soft.
            // Nothing in the app was wrong and nothing in the walk said so.
            EditorState.toolMemoryKeys
                + [EditorState.wandToleranceKey,
                   EditorState.lensToolKey, EditorState.lensToolKindKey,
                   // The timeline bar's Easing, the curve new keys are given:
                   // left behind, a walk's keys would ease however the last
                   // walk to touch it left them.
                   EditorState.newKeyEaseKey]
        case .groups:
            [EditorState.openGroupsKey]
        case .panel:
            [EditorState.inspectorVisibleKey, EditorState.libraryVisibleKey,
             EditorState.inspectorWidthKey, LibraryPanel.scopeKey,
             InspectorPanel.sectionOrderKey, InspectorPanel.sectionOrderVersionKey,
             InspectorPanel.collapsedKey,
             // The folds INSIDE sections, which last across launches the same
             // way the sections' own collapse does: the Measurement section's
             // Details. (The parts list no longer folds: a switched on part
             // shows its settings straight away.)
             MeasureInspector.detailsOpenKey,
             LayersListView.heightKey, LibraryPanel.heightKey,
             // ...and which of the optional sections have been pinned on or
             // turned off by hand, which decides what the dock draws at all
             // (`next-panel-sections`).
             PanelSectionVisibilityStore.defaultsKey(for: Experiments.shared.release),
             // ...and which MODE the window is in, which is a named bundle of
             // exactly those choices (`next-window-modes`). Forgetting the
             // choices without forgetting the mode would leave the chip naming
             // a mode whose arrangement had just been thrown away.
             WindowModeStore.defaultsKey(for: Experiments.shared.release)]
        case .grid:
            [EditorState.canvasGridKey]
        case .frames:
            [EditorState.lastFrameSizeKey, IconKeylinesStore.defaultsKey]
        case .tutorials:
            [TutorialController.progressKey]
        case .motion:
            // The playhead each recording was left on, too: a walk that opens
            // the sample recording must start it at the top, not wherever the
            // walk before it stopped watching (`RecordingPlaces`).
            // And which transition ⌘T puts on a cut: a walk that picked Push
            // as the default would otherwise hand every later walk a push.
            // And whether a recording's timeline was last left open, which is
            // what the next untouched recording opens with.
            [EditorState.motionStripOpenKey, EditorState.videoTimelineOpenKey, RecordingPlaceStore.defaultsKey,
             DefaultTransitionStore.defaultsKey]
        case .shelf:
            // Not a setting at all: the shared shelf is a file, emptied in
            // `perform` beside the settings it names.
            []
        case .questions:
            SilenceableQuestion.all.map(\.storageKey)
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
    /// The shared component shelf as it stood before step one. It is a file
    /// rather than a setting, so it is taken and put back by hand — same
    /// reason: a walk that shares a component must not leave it on the shelf
    /// of every walk that follows (`SharedComponentStore`).
    private var sharedShelfBefore: SharedComponentShelf?

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
        sharedShelfBefore = SharedComponentStore.shared.shelf
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
            if setup.forget.contains(.frames) { IconKeylinesStore.shared.reload() }
            if setup.forget.contains(.panel) {
                PanelSectionVisibilityStore.shared.reload()
                WindowModeStore.shared.reload()
            }
            if setup.forget.contains(.motion) {
                RecordingPlaceStore.shared.reload()
                DefaultTransitionStore.shared.reload()
            }
            if setup.forget.contains(.tutorials) { TutorialController.shared.forgetAllProgress() }
            // The shared shelf is a file rather than a setting, so it is
            // emptied here by hand. The shelf it had is already on record
            // above, so `restoreSharedShelf` still hands the machine back
            // exactly what it found.
            if setup.forget.contains(.shelf) {
                SharedComponentStore.shared.replace(with: SharedComponentShelf())
            }
            said.append("forgot \(setup.forget.map(\.rawValue).joined(separator: ", "))"
                        + " (\(keys.count) settings)")
        }
        // After the forgetting, so "forget all, and the tracks were last left
        // open" is one walk's word for a person who opens them every time.
        if let open = setup.timelineOpen {
            UserDefaults.standard.set(open, forKey: EditorState.videoTimelineOpenKey)
            said.append(open ? "a recording's timeline was last left open"
                             : "a recording's timeline was last put away")
        }
        if !setup.captures.isEmpty {
            let placed = try lend(setup.captures, besides: scriptURL)
            said.append("lent the capture folder \(placed.joined(separator: ", "))")
        }
        if !setup.scratch.isEmpty {
            let placed = try makeScratch(setup.scratch, besides: scriptURL)
            said.append("gave the walk its own copy of \(placed.joined(separator: ", "))")
        }
        // The features this walk named were switched before the app finished
        // launching, because the menu bar is built once and a feature switched
        // off after that still has its rows in it. All that is left here is to
        // say so in the log, and to fail the walk when they could not be set:
        // a walk running with the app exactly as it came, claiming otherwise,
        // is the thing this replaces.
        // Said whatever this walk asked for, because it is about the machine
        // rather than about the walk: a run before this one was killed with a
        // feature still switched, and the launch put it back.
        if let recovered = PlaytestFlagOverrides.recoveryNote { said.append(recovered) }
        if let recovered = PlaytestLentCaptures.recoveryNote { said.append(recovered) }
        if !setup.flags.isEmpty {
            if let problem = PlaytestFlagOverrides.problem {
                throw PlaytestSetupError(description: problem)
            }
            guard let report = PlaytestFlagOverrides.report else {
                throw PlaytestSetupError(
                    description: "setup names features to switch, and none were switched; the walk was "
                        + "started some way that does not read its script before the app is built")
            }
            said.append(report)
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
            // One name is not a file at all: it means the guides' own sample
            // recording, written fresh. A walk about history needs a RECORDING
            // in the capture folder, and the repo keeps no video fixture (the
            // sample is drawn in code so nothing binary is committed). It is
            // lent and taken away like every other capture, so it never
            // outlives the walk in somebody's Screenshots folder.
            let source = file == PlaytestSetup.sampleRecordingToken
                ? (TutorialSampleRecording.fresh() ?? URL(fileURLWithPath: "/nowhere"))
                : (file.hasPrefix("/")
                    ? URL(fileURLWithPath: file)
                    : scriptURL.deletingLastPathComponent().appendingPathComponent(file).standardizedFileURL)
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
            // Stamped NOW, in the order the walk listed them. A lent capture
            // stands in for something you just took, and history is ordered by
            // when a capture was made: without this the walk's answer depends
            // on what happens to be in the person's own folder, and a copy can
            // inherit the date of the file it replaced at that path, so the
            // thing a walk just lent can read as older than a screenshot from
            // last week. Found on 2026-09-21: a lent recording came last in a
            // folder whose newest picture was a day old.
            let stamp = Date().addingTimeInterval(Double(placed.count) * 0.001)
            try? FileManager.default.setAttributes(
                [.creationDate: stamp, .modificationDate: stamp], ofItemAtPath: destination.path)
            lentCaptures.append(destination)
            // Written down as it happens, so a kill between this lend and the
            // next leaves a record the next launch can act on
            // (`PlaytestLentCaptures`).
            PlaytestLentCaptures.remember(destination)
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
            let source = try Self.scratchSource(file, besides: scriptURL)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw PlaytestSetupError(
                    description: "setup asks for the scratch file \"\(file)\", and there is no such file at \(source.path)")
            }
            // A sample can be asked for under a name of the walk's own.
            let name = PlaytestSampleFile.copy(file)?.fileName ?? source.lastPathComponent
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
            placed.append(name)
        }
        return placed
    }

    /// Where a scratch file comes from.
    ///
    /// Two of them are not files on disk at all until somebody asks: the
    /// tutorial's own sample recording and sample music are written on demand,
    /// and a walk about dropping media needs one of each without depending on
    /// some earlier walk having made it. `sample:recording` and `sample:music`
    /// name those, and everything else is a path as it always was.
    private static func scratchSource(_ file: String, besides scriptURL: URL) throws -> URL {
        switch PlaytestSampleFile.copy(file)?.sample {
        case .recording:
            guard let url = TutorialSampleRecording.fresh() else {
                throw PlaytestSetupError(description: "the sample recording could not be written")
            }
            return url
        case .music:
            guard let url = TutorialSampleSound.fresh() else {
                throw PlaytestSetupError(description: "the sample music could not be written")
            }
            return url
        case nil:
            return file.hasPrefix("/")
                ? URL(fileURLWithPath: file)
                : scriptURL.deletingLastPathComponent().appendingPathComponent(file)
                    .standardizedFileURL
        }
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

    /// Puts every feature the walk switched back where it found it. Separate
    /// from `restoreSettings` because the flags are not one of the areas of
    /// memory a walk can forget: they were moved before the walk was even
    /// parsed, so they are put back by the code that moved them.
    func restoreFlags() -> String? { PlaytestFlagOverrides.restore() }

    /// Puts the shared component shelf back to what it was before step one.
    /// Says so only when the walk actually changed it.
    mutating func restoreSharedShelf() -> String? {
        guard let before = sharedShelfBefore else { return nil }
        sharedShelfBefore = nil
        guard SharedComponentStore.shared.shelf != before else { return nil }
        SharedComponentStore.shared.replace(with: before)
        return "put the shared component shelf back as it found it"
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
        PlaytestLentCaptures.forget()
        return "took back \(names.joined(separator: ", "))"
    }
}

struct PlaytestSetupError: Error, CustomStringConvertible {
    let description: String
}
#endif
