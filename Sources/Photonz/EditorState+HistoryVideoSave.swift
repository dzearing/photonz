import Foundation
import PhotonzCore
import PhotonzRender

// Command S on a recording that lives in history (`HistoryVideoSave`).
//
// History is what gets pasted into a chat, so saving an edit of a recording
// there makes the tile the finished video: the edit is kept beside it as a
// project, the recording as made is kept in the hidden originals folder, and
// the video is written over the tile's file in the background while the window
// is free to close. Opening the tile again opens the project, so the edit is
// never baked into something that cannot be taken apart.
extension EditorState {

    /// The tile this window's recording is, when it is in history and has
    /// landed there.
    var historyVideoURL: URL? {
        guard let recordingURL, let store = captureCenter?.store,
              Self.isInHistory(recordingURL, store: store) else { return nil }
        return recordingURL
    }

    static func isInHistory(_ url: URL, store: CaptureStore) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path
            == store.directory.standardizedFileURL.path
    }

    /// Command S on a recording window. False when the recording is not one
    /// history holds, which leaves the save box to ask where, as before.
    func saveRecordingIntoHistory() -> Bool {
        guard let document, let video = recordingURL, let captureStore = captureCenter?.store else {
            return false
        }
        let situation = HistoryVideoSave.Situation(
            inHistory: Self.isInHistory(video, store: captureStore),
            fileThere: FileManager.default.fileExists(atPath: video.path) && !recordingStillLanding,
            untouched: document.untouchedRecording != nil,
            originalKept: VideoOriginals.exists(for: video),
            playsTheHistoryFile: MovieLibrary.shared.plays(video, in: document))
        switch HistoryVideoSave.plan(situation) {
        case .askWhere:
            return false
        case .nothingToDo:
            markSaved()
        case .putTheRecordingBack:
            do {
                try captureStore.putRecordingBack(video)
                markSaved()
            } catch {
                presentError("Couldn't put the recording back.", error)
            }
        case .writeTheEdit(let keepOriginal):
            do {
                if keepOriginal { try captureStore.keepOriginal(of: video) }
                let project = HistoryVideoSave.projectURL(for: video)
                let media = ProjectMedia.table(for: document, project: project) {
                    SoundLibrary.shared.url(forID: $0)
                }
                try PackageIO.write(document, store: store, media: media, to: project)
                markSaved()
            } catch {
                presentError("Couldn't save the video.", error)
                return true
            }
            captureStore.writeEditedVideo(video, document: document, pictures: store.snapshot())
            onSavedIntoHistory?(video)
        }
        return true
    }

    /// The tile's edit, opened as the project kept beside it rather than as
    /// the finished video, so it can be edited again and saved over the same
    /// tile. False when the tile has no current project, which opens the
    /// file itself as before.
    func openHistoryVideoProject(at video: URL) -> Bool {
        guard let captureStore = captureCenter?.store, Self.isInHistory(video, store: captureStore),
              VideoOriginals.exists(for: video) else { return false }
        let project = HistoryVideoSave.projectURL(for: video)
        let modified = { (url: URL) in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        guard HistoryVideoSave.projectIsCurrent(projectModified: modified(project),
                                                videoModified: modified(video)),
              let opened = try? PackageIO.read(from: project, into: store) else { return false }
        let missing = Self.fileProjectMedia(of: opened, project: project)
        installDocument(opened, url: nil)
        missingMediaNames = missing
        // Still the recording's window: Save writes the tile again, the
        // title is the recording's name, and Revert to Original goes back to
        // the recording as it was made.
        recordingURL = video
        openedFileURL = video
        let original = VideoOriginals.url(for: video).standardizedFileURL
        if let movie = opened.allLayers.lazy.compactMap(\.movie)
            .first(where: { MovieLibrary.shared.url(for: $0) == original }) {
            recordingAsOpened = PhotonzDocument.recording(movie, name: video.deletingPathExtension().lastPathComponent)
        }
        markSaved()
        documentTimeMS = 0
        documentMomentChanged()
        restoreTimelineView()
        openInItsMode(opened, forAGuide: false)
        tellAboutMissingMedia()
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.register(self)
        #endif
        return true
    }
}
