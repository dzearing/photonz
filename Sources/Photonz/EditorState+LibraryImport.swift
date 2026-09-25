import AppKit
import Foundation
import PhotonzCore
import PhotonzMedia
import UniformTypeIdentifiers

// Recordings and sounds put into the Library and nowhere else (`video.html`,
// onboarding step 2, "Fill the Library"): File ▸ Import Media… (⇧⌘I), the
// Library's own + menu, and a file let go on the shelf. The shelf is the
// document's bin; the timeline takes a tile when you drag it onto a track.
// What lands and what it says is `PhotonzDocument.bringIntoLibrary`.
extension EditorState {

    /// Whether this window has a Library to import into.
    var canImportMedia: Bool {
        Experiments.shared.libraryEnabled && Experiments.shared.droppingMedia && document != nil
    }

    /// What the Open panel lets you pick: recordings and sounds.
    static let importableTypes: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .audio, .mp3, .wav,
                                            .aiff, .mpeg4Audio]

    /// **Import Media…** Pick files; they go on the Library shelf, which
    /// opens to show them.
    func importMediaFromPanel() {
        guard canImportMedia else { return }
        #if PHOTONZ_PLAYTEST
        // Probe only: a walk cannot click inside an Open panel, so it names
        // the files the panel would have handed back.
        if let picked = playtestImportPicks {
            playtestImportPicks = nil
            Task { await importMedia(picked) }
            return
        }
        // ...and never a modal panel under a walk: nothing can answer it, so
        // it hangs the walk until its clock runs out. Nothing is imported,
        // which the walk's next check catches.
        if PlaytestHarness.isDrivingAWalk {
            NSLog("Import Media… under a walk with no importPicks step before it: no Open panel shown")
            return
        }
        #endif
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.importableTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose recordings and sounds to put in the Library"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { await importMedia(urls) }
    }

    /// Reads each file and puts the ones that play on the shelf, then shows
    /// the shelf on Media with the first of them in view. Anything that is
    /// not a recording or a sound is left alone.
    @discardableResult
    func importMedia(_ urls: [URL]) async -> LibraryImport? {
        guard canImportMedia else { return nil }
        var sources: [DocumentMediaSource] = []
        var unreadable: [String] = []
        for url in urls {
            switch MediaFiles.kind(of: url) {
            case .recording:
                if let movie = await MovieLibrary.shared.movie(at: url) {
                    sources.append(DocumentMediaSource(media: .recording(movie), name: url.lastPathComponent))
                } else {
                    unreadable.append(url.lastPathComponent)
                }
            case .sound:
                if let sound = await SoundLibrary.shared.sound(at: url) {
                    sources.append(DocumentMediaSource(media: .sound(sound), name: url.lastPathComponent))
                    SoundLibrary.shared.loadWaveform(for: sound)
                } else {
                    unreadable.append(url.lastPathComponent)
                }
            case nil:
                continue
            }
        }
        guard document != nil, !(sources.isEmpty && unreadable.isEmpty) else { return nil }
        var outcome = LibraryImport(unreadable: unreadable)
        if !sources.isEmpty {
            // Only a change when something is new, so importing a file the
            // shelf already has leaves nothing to undo.
            let isNew = sources.contains { source in !documentClipItems.contains { $0.id == source.id } }
            if isNew {
                perform { outcome = $0.bringIntoLibrary(sources, unreadable: unreadable) }
            } else if var copy = document {
                outcome = copy.bringIntoLibrary(sources, unreadable: unreadable)
            }
        }
        if outcome.revealID != nil { showMediaShelf(revealing: outcome.revealID) }
        raiseCanvasNotice(.broughtIntoLibrary(outcome))
        return outcome
    }

    /// Opens the Library on Media, with this tile scrolled into view.
    func showMediaShelf(revealing id: UUID?) {
        UserDefaults.standard.set(LibraryScope.media.rawValue, forKey: LibraryPanel.scopeKey)
        // Opens the dock too, and unfolds a folded Library: a header and
        // nothing else is not showing somebody what they just brought in.
        setLibraryVisible(true)
        pendingLibraryTileID = id?.uuidString
    }
}
