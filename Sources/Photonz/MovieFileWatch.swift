import AppKit
import Dispatch
import PhotonzCore
import PhotonzMedia

/// Notices a recording's file changing while windows hold it, and hands each
/// of them the new file (`EditorState.recordingReplaced`).
///
/// Told by the disk rather than by asking it over and over: each file played
/// has a watch on it, and every file is looked at again when the app comes to
/// the front, which is what somebody who has just exported over one in another
/// app does next. A change is taken once the file has stopped changing and can
/// be read, so one being written for ten seconds reloads once, when it is done.
@MainActor
final class MovieFileWatch {
    static let shared = MovieFileWatch()

    /// The most files watched at once; the ones filed longest ago go first and
    /// are still looked at when the app comes to the front. Each watch is an
    /// open file descriptor, and an app has 256.
    static let mostWatched = 64
    /// How long a file has to have stopped changing for.
    static let settleSeconds = 0.4
    /// How many looks a file being written, or gone for a moment, is given:
    /// half a minute.
    static let looks = 75

    private struct Watch {
        let source: DispatchSourceFileSystemObject
        let fileID: UInt64
    }
    private var watches: [URL: Watch] = [:]
    private var order: [URL] = []
    private let editors = NSHashTable<EditorState>.weakObjects()
    /// The files being looked at until they settle.
    private var settling: [URL: Task<Void, Never>] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MovieFileWatch.shared.look() }
        }
    }

    /// A window that plays recordings, told when one of them changes.
    func add(_ editor: EditorState) { editors.add(editor) }

    /// Watch the file at `url` for a change.
    func watch(_ url: URL) {
        let fileID = MediaFileStamp.of(url)?.fileID
        if let known = watches[url], known.fileID == fileID { return }
        stopWatching(url)
        guard let fileID else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { MovieFileWatch.shared.settle(url) } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watches[url] = Watch(source: source, fileID: fileID)
        order.append(url)
        while order.count > Self.mostWatched { stopWatching(order[0]) }
    }

    private func stopWatching(_ url: URL) {
        watches.removeValue(forKey: url)?.source.cancel()
        order.removeAll { $0 == url }
    }

    /// Look at every file a window plays.
    func look() {
        for editor in editors.allObjects {
            for url in MovieLibrary.shared.changedOnDisk(editor.playedRecordingIDs).values { settle(url) }
        }
    }

    /// Wait for the file at `url` to stop changing, then hand it over.
    private func settle(_ url: URL) {
        guard settling[url] == nil else { return }
        settling[url] = Task { [weak self] in
            var last: MediaFileStamp?
            for _ in 0..<Self.looks {
                try? await Task.sleep(for: .seconds(Self.settleSeconds))
                guard let self else { return }
                let now = MediaFileStamp.of(url)
                defer { last = now }
                guard let now, now == last else { continue }
                // Swapped in whole, it is another file on the disk: the watch
                // was on the one that is gone.
                watch(url)
                if await handOver(url) {
                    settling[url] = nil
                    // Changed again while it was being read.
                    look()
                    return
                }
            }
            self?.settling[url] = nil
        }
    }

    /// Hand the file at `url` to every window holding what it was before.
    /// False where it cannot be read yet.
    private func handOver(_ url: URL) async -> Bool {
        let holding = editors.allObjects.compactMap { editor -> (EditorState, [UUID])? in
            let old = MovieLibrary.shared.changedOnDisk(editor.playedRecordingIDs)
                .filter { $0.value == url }.map(\.key)
            return old.isEmpty ? nil : (editor, old)
        }
        guard !holding.isEmpty else { return true }
        guard let movie = await MovieLibrary.shared.movie(at: url) else { return false }
        for (editor, old) in holding {
            await editor.recordingReplaced(old, with: movie)
        }
        return true
    }
}
