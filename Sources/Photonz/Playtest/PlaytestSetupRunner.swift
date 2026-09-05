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
            [EditorState.recentColorsKey, EditorState.foregroundFillKey, EditorState.backgroundFillKey]
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
             InspectorPanel.collapsedKey]
        case .grid:
            [EditorState.canvasGridKey]
        }
    }
}

/// Carries out a walk's `setup` block and undoes the borrowing afterwards.
@MainActor
struct PlaytestSetupRunner {
    /// Files this run put into the capture folder, to take away again.
    private(set) var lentCaptures: [URL] = []

    /// Performs the setup, returning what to say about it in the log.
    ///
    /// Throws when something it was asked for cannot be done — a missing
    /// picture, or a name already taken in the capture folder — because a walk
    /// that starts anyway is a walk whose failure means nothing.
    mutating func perform(_ setup: PlaytestSetup, besides scriptURL: URL) throws -> String {
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
