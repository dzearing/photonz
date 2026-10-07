import Foundation
import Observation
import PhotonzCore
import PhotonzMedia
import PhotonzRender

// Writing an edited recording's finished video over its file in history
// (`HistoryVideoSave`).
//
// Command S in the window keeps the edit as a project beside the tile and hands
// the write to the history, which owns it from then on: the window can close at
// once, a tile shows how far along it is, a copy or a drag of that tile waits
// for it, and a write cut short by quitting is finished on the next launch.

/// How far along one video's write is, observed by its tile alone.
@MainActor
@Observable
final class VideoSaveProgress {
    var fraction: Double = 0
    /// How long the edit being written runs, which is what the tile says
    /// while the file on disk is still the longer recording.
    var seconds: TimeInterval?
}

extension CaptureStore {

    /// Whether an edit is being written over this tile's file.
    func isWritingVideo(_ url: URL) -> Bool { writingVideos[url] != nil }

    /// Keep the recording as it was made, before anything is written over it:
    /// a clone in the hidden originals folder (no extra space on the Mac's own
    /// disk), with where its pointer went beside it. Every window playing the
    /// file plays the kept one from now on.
    func keepOriginal(of video: URL) throws {
        let original = VideoOriginals.url(for: video)
        let fm = FileManager.default
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: original.path) {
            try fm.copyItem(at: video, to: original)
        }
        let pointer = PointerTrackSidecar.url(for: video)
        let keptPointer = PointerTrackSidecar.url(for: original)
        if fm.fileExists(atPath: pointer.path), !fm.fileExists(atPath: keptPointer.path) {
            try? fm.copyItem(at: pointer, to: keptPointer)
        }
        MovieLibrary.shared.relocate(from: video, to: original)
    }

    /// Write `document` as the tile's video, in the background. A write
    /// already running for the same tile is stopped first: the newer save is
    /// the one that counts.
    func writeEditedVideo(_ video: URL, document: PhotonzDocument, pictures: ImageStore) {
        let previous = videoWriteTasks[video]
        previous?.cancel()
        // A new one each write: it is also how a write knows it is still the
        // one that counts when it finishes.
        let progress = VideoSaveProgress()
        progress.seconds = Double(document.exportRangeMS(HistoryVideoSave.choice.range).count) / 1000
        writingVideos[video] = progress
        failedVideoWrites.remove(video)
        rememberPendingWrite(video)
        let writing = HistoryVideoSave.writingURL(for: video)
        let choice = HistoryVideoSave.choice
        let steps = ProgressSteps(count: 200)
        videoWriteTasks[video] = Task { @MainActor [weak self] in
            // One write at a time per file: the one stopped takes its half
            // file with it, and must not take this one's.
            await previous?.value
            guard !Task.isCancelled else { return }
            let started = Date()
            do {
                try FileManager.default.createDirectory(at: writing.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: writing)
                try await EditorState.writeVideo(
                    of: document, pictures: pictures, format: .mp4, quality: choice.quality,
                    size: choice.size, to: writing, captions: choice.captions, range: choice.range
                ) { done in
                    guard steps.isNewStep(done) else { return }
                    Task { @MainActor in progress.fraction = done }
                }
                try Task.checkCancellation()
                // A QuickTime recording (what the Mac's own screen recorder
                // writes) gets the same pictures in a QuickTime file, so it
                // stays what its name says.
                var finished = writing
                if video.pathExtension.lowercased() == "mov" {
                    finished = writing.deletingPathExtension().appendingPathExtension("mov")
                    try await DocumentMovieWriter.rewrap(writing, to: finished, as: .mov)
                    try? FileManager.default.removeItem(at: writing)
                }
                try Task.checkCancellation()
                guard let self else { return }
                try Self.putInPlace(finished, over: video)
                NSLog("Saved the edited video \(video.lastPathComponent) in "
                      + String(format: "%.2fs", Date().timeIntervalSince(started)))
                finishWritingVideo(video, progress: progress, failed: false)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: writing)
                try? FileManager.default.removeItem(at: writing.deletingPathExtension().appendingPathExtension("mov"))
            } catch {
                NSLog("Saving the edited video \(video.lastPathComponent) failed: \(error)")
                try? FileManager.default.removeItem(at: writing)
                self?.finishWritingVideo(video, progress: progress, failed: true)
            }
        }
    }

    /// The finished file takes the tile's place under the tile's name and
    /// date, so the tile stays where it was in history, and the project beside
    /// it is stamped with the same moment: it is this video's edit
    /// (`HistoryVideoSave.projectIsCurrent`).
    private static func putInPlace(_ written: URL, over video: URL) throws {
        let fm = FileManager.default
        let made = (try? video.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        _ = try fm.replaceItemAt(video, withItemAt: written)
        let now = Date()
        var dates: [FileAttributeKey: Any] = [.modificationDate: now]
        if let made { dates[.creationDate] = made }
        try? fm.setAttributes(dates, ofItemAtPath: video.path)
        try? fm.setAttributes([.modificationDate: now],
                              ofItemAtPath: HistoryVideoSave.projectURL(for: video).path)
    }

    private func finishWritingVideo(_ video: URL, progress: VideoSaveProgress, failed: Bool) {
        // A newer save of the same tile owns everything from here.
        guard writingVideos[video] === progress else { return }
        videoWriteTasks[video] = nil
        writingVideos[video] = nil
        forgetPendingWrite(video)
        if failed { failedVideoWrites.insert(video) }
        reload()
        land(video, as: entries.first { $0.url == video })
    }

    /// The tile is going away: stop writing to it.
    func stopWritingVideo(_ video: URL) {
        guard let task = videoWriteTasks.removeValue(forKey: video) else { return }
        task.cancel()
        writingVideos[video] = nil
        forgetPendingWrite(video)
        land(video, as: nil)
    }

    /// An edit taken all the way back to the recording: the kept recording
    /// goes back on the tile and the project beside it goes away, so the tile
    /// is exactly what was recorded.
    func putRecordingBack(_ video: URL) throws {
        stopWritingVideo(video)
        let original = VideoOriginals.url(for: video)
        let fm = FileManager.default
        guard fm.fileExists(atPath: original.path) else { return }
        let made = (try? video.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        _ = try fm.replaceItemAt(video, withItemAt: original)
        if let made { try? fm.setAttributes([.creationDate: made], ofItemAtPath: video.path) }
        try? fm.removeItem(at: PointerTrackSidecar.url(for: original))
        try? fm.removeItem(at: HistoryVideoSave.projectURL(for: video))
        MovieLibrary.shared.relocate(from: original, to: video)
        reload()
    }

    // MARK: Finishing what quitting cut short

    #if PHOTONZ_PLAYTEST
    /// What quitting does to a write, short of quitting: it stops, its half
    /// file is left, and nothing in memory knows about it. Only the list of
    /// writes still to finish survives, which is what a launch reads.
    func playtestCutShortVideoWrites() {
        for (video, task) in videoWriteTasks {
            task.cancel()
            writingVideos[video] = nil
        }
    }
    #endif

    private static let pendingKey = "historyVideoSaves.pending"

    private var pendingWrites: HistoryVideoSave.Pending {
        get { HistoryVideoSave.Pending(paths: UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? []) }
        set {
            if newValue.paths.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.pendingKey)
            } else {
                UserDefaults.standard.set(newValue.paths, forKey: Self.pendingKey)
            }
        }
    }

    private func rememberPendingWrite(_ video: URL) { pendingWrites.add(video.path) }
    private func forgetPendingWrite(_ video: URL) { pendingWrites.remove(video.path) }

    /// At launch: every write the last run did not finish is written again
    /// from the project it left beside the tile. The tile shows the recording
    /// until then, which is all it ever was; nothing is lost either way.
    func resumeVideoWrites() {
        let fm = FileManager.default
        for path in pendingWrites.paths {
            let video = URL(fileURLWithPath: path)
            let project = HistoryVideoSave.projectURL(for: video)
            guard writingVideos[video] == nil,
                  fm.fileExists(atPath: video.path), fm.fileExists(atPath: project.path),
                  VideoOriginals.exists(for: video) else {
                forgetPendingWrite(video)
                continue
            }
            let pictures = ImageStore()
            guard let document = try? PackageIO.read(from: project, into: pictures) else {
                forgetPendingWrite(video)
                continue
            }
            _ = EditorState.fileProjectMedia(of: document, project: project)
            NSLog("Finishing the edited video \(video.lastPathComponent) a quit cut short")
            writeEditedVideo(entries.first { $0.url.standardizedFileURL == video.standardizedFileURL }?.url ?? video,
                             document: document, pictures: pictures)
        }
    }
}
