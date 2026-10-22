import Foundation
import Observation
import PhotonzCore

/// Downloads a built-in model for Ask (Settings > Ask): every file of it, one
/// after another, into `AskModelServer.folder`, with progress and a Stop. A
/// file is written as `<name>.part` and only takes its real name once it is
/// whole, so a stopped download never looks like a model.
@MainActor
@Observable
final class AskModelDownload {

    static let shared = AskModelDownload()

    /// The model being downloaded, or nil.
    private(set) var choice: AskBuiltInModels.Choice?
    /// Bytes on the Mac so far, of every file of `choice`.
    private(set) var done: Int64 = 0
    /// Why the last download stopped short, in one sentence.
    private(set) var trouble: String?

    var active: Bool { choice != nil }
    var fraction: Double {
        guard let choice, choice.downloadBytes > 0 else { return 0 }
        return min(1, Double(done) / Double(choice.downloadBytes))
    }

    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var current: URLSessionDownloadTask?

    func start(_ choice: AskBuiltInModels.Choice) {
        guard self.choice == nil else { return }
        trouble = nil
        let folder = AskModelServer.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = choice.files.filter { !Self.isWhole($0, in: folder) }
        let need = missing.reduce(Int64(0)) { $0 + $1.bytes }
        if let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < need + 2_000_000_000 {
            trouble = "Not enough free space. It needs \(AskBuiltInModels.sizeWords(need + 2_000_000_000))."
            return
        }
        self.choice = choice
        done = choice.downloadBytes - need
        work = Task { [weak self] in
            for file in missing {
                guard let self, !Task.isCancelled else { return }
                let before = done
                do {
                    try await fetch(file, into: folder) { [weak self] written in
                        self?.done = before + written
                    }
                } catch {
                    if !Task.isCancelled { trouble = "The download stopped. Try again." }
                    finish()
                    return
                }
                done = before + file.bytes
            }
            self?.finish()
        }
    }

    /// Stops the download. What came down so far is thrown away.
    func stop() {
        work?.cancel()
        current?.cancel()
        finish()
    }

    private func finish() {
        choice = nil
        current = nil
        work = nil
    }

    static func isWhole(_ file: AskBuiltInModels.File, in folder: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: file.name).path)[.size]
            as? NSNumber)?.int64Value
        return size == file.bytes
    }

    private func fetch(_ file: AskBuiltInModels.File, into folder: URL,
                       progress: @escaping @MainActor (Int64) -> Void) async throws {
        let target = folder.appending(path: file.name)
        let part = folder.appending(path: file.name + ".part")
        let watcher = Watcher(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: watcher, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: file.url)
        current = task
        let landed: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                watcher.finished = { result in continuation.resume(with: result) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        defer { try? FileManager.default.removeItem(at: landed) }
        try? FileManager.default.removeItem(at: part)
        try FileManager.default.moveItem(at: landed, to: part)
        let size = (try FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value
        guard size == file.bytes else {
            try? FileManager.default.removeItem(at: part)
            throw URLError(.cannotDecodeContentData)
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: part, to: target)
    }

    /// The download's delegate: how far along, and where the file landed.
    private final class Watcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: @MainActor (Int64) -> Void
        // Set once before the task starts; called once from the session's queue.
        var finished: ((Result<URL, Error>) -> Void)?
        private var lastReport = Date.distantPast

        init(progress: @escaping @MainActor (Int64) -> Void) {
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            // A few times a second is plenty for a bar.
            guard Date().timeIntervalSince(lastReport) > 0.25 else { return }
            lastReport = Date()
            let progress = progress
            Task { @MainActor in progress(totalBytesWritten) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The file at `location` is gone once this returns: keep it.
            let kept = FileManager.default.temporaryDirectory.appending(path: "photonz-ask-\(UUID().uuidString)")
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
                finish(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                try FileManager.default.moveItem(at: location, to: kept)
                finish(.success(kept))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(error)) }
        }

        private func finish(_ result: Result<URL, Error>) {
            finished?(result)
            finished = nil
        }
    }
}
