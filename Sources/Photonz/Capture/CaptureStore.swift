import AppKit
import Observation
import PhotonzCore
import UniformTypeIdentifiers

/// The capture history, backed **directly by a user folder** (default
/// `~/Pictures/Screenshots`) — there is no private library or index. The folder
/// is the single source of truth:
///
/// - New captures/recordings are written straight into it.
/// - History is a live listing of its media files, newest first.
/// - Deleting in history moves the file to the Trash; deleting the file in the
///   folder removes it from history (a filesystem watcher keeps them in sync).
///
/// Thumbnails are cached in memory; video poster frames are generated on demand
/// (no poster files are written into the user's folder).
@MainActor
@Observable
final class CaptureStore {
    /// Current folder contents, newest first.
    private(set) var entries: [CaptureEntry] = []

    /// The watched folder (source of truth).
    let directory: URL

    /// Memory caches (observed, so async loads refresh the UI).
    private var imageCache: [URL: CGImage] = [:]
    private var durations: [URL: TimeInterval] = [:]
    private var posterLoading: Set<URL> = []

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1
    @ObservationIgnored private var reloadDebounce: DispatchWorkItem?

    nonisolated static var defaultDirectory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        return pictures.appendingPathComponent("Screenshots", isDirectory: true)
    }

    init(directory: URL = CaptureStore.defaultDirectory) {
        self.directory = directory
    }

    /// Called once at launch: create the folder if needed, list it, and start
    /// watching for external changes.
    func start() {
        ensureDirectory()
        reload()
        startWatching()
    }

    // MARK: - Folder listing

    func reload() {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []

        var found: [CaptureEntry] = []
        for url in urls {
            guard let kind = CaptureLibrary.kind(forPathExtension: url.pathExtension) else { continue }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            found.append(CaptureEntry(url: url, createdAt: date, kind: kind))
        }
        let sorted = CaptureLibrary.sortedNewestFirst(found)

        // Drop caches for files that disappeared.
        let live = Set(sorted.map(\.url))
        imageCache = imageCache.filter { live.contains($0.key) }
        durations = durations.filter { live.contains($0.key) }

        entries = sorted
    }

    // MARK: - Adding

    /// Write a screenshot into the folder; returns the new entry (after reload).
    @discardableResult
    func add(_ image: CGImage, takenAt date: Date = .now) -> CaptureEntry? {
        ensureDirectory()
        let url = uniqueURL(prefix: "Screenshot", date: date, ext: "png")
        writePNG(image, to: url)
        reload()
        // Match by file name: the URL `contentsOfDirectory` yields can differ
        // (percent-encoding, symlink resolution) from our constructed one.
        let entry = entries.first { $0.fileName == url.lastPathComponent }
        if let entry { imageCache[entry.url] = image }
        return entry
    }

    /// Move a finalized recording into the folder (phase 12.4).
    @discardableResult
    func addRecording(tempURL: URL, takenAt date: Date = .now) -> CaptureEntry? {
        ensureDirectory()
        let url = uniqueURL(prefix: "Recording", date: date, ext: "mp4")
        do {
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            NSLog("Couldn't file recording: \(error)")
            return nil
        }
        reload()
        return entries.first { $0.fileName == url.lastPathComponent }
    }

    /// Override-in-place (phase 11.5): rewrite an existing capture's pixels.
    func replace(at url: URL, with image: CGImage) {
        guard entries.contains(where: { $0.url == url }) else { return }
        writePNG(image, to: url)
        imageCache[url] = image
        reload()
    }

    // MARK: - Removing

    /// Delete a capture — moves the file to the Trash (recoverable), which also
    /// removes it from history.
    func remove(_ entry: CaptureEntry) {
        try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        imageCache[entry.url] = nil
        durations[entry.url] = nil
        reload()
    }

    /// "Clear All": move every shown capture to the Trash.
    func clearAll() {
        for entry in entries {
            try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        }
        imageCache.removeAll()
        durations.removeAll()
        reload()
    }

    // MARK: - Media access

    /// Thumbnail image: the screenshot itself, or a recording's poster frame
    /// (generated + cached lazily; the UI refreshes when it lands).
    func image(for entry: CaptureEntry) -> CGImage? {
        if let cached = imageCache[entry.url] { return cached }
        if entry.kind == .video {
            loadVideoMetadata(entry)
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        imageCache[entry.url] = image
        return image
    }

    /// Recording length, loaded lazily alongside the poster.
    func duration(for entry: CaptureEntry) -> TimeInterval? {
        if let d = durations[entry.url] { return d }
        if entry.kind == .video { loadVideoMetadata(entry) }
        return nil
    }

    func copyToPasteboard(_ entry: CaptureEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if entry.kind == .video {
            pasteboard.writeObjects([entry.url as NSURL])
            return
        }

        // One item carrying every flavor a paste target might want:
        // - the file URL (apps like Claude / Mail / Finder attach the file),
        // - PNG (web/Electron read public.png),
        // - TIFF (native image apps).
        // This is why image-data-only copy failed to paste into Claude.
        let item = NSPasteboardItem()
        item.setString(entry.url.absoluteString, forType: .fileURL)
        if let image = image(for: entry) {
            if let png = Self.pngData(image) { item.setData(png, forType: .png) }
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            if let tiff = nsImage.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        pasteboard.writeObjects([item])
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// On-disk media location — used by the overlay's drag-to-export.
    func fileURL(for entry: CaptureEntry) -> URL { entry.url }

    // MARK: - Video metadata (lazy)

    private func loadVideoMetadata(_ entry: CaptureEntry) {
        let url = entry.url
        guard !posterLoading.contains(url) else { return }
        posterLoading.insert(url)
        Task {
            let poster = await VideoExporter.posterFrame(of: url)
            let duration = await VideoExporter.duration(of: url)
            posterLoading.remove(url)
            // Only keep if the file is still present in history.
            guard entries.contains(where: { $0.url == url }) else { return }
            if let poster { imageCache[url] = poster }
            durations[url] = duration
        }
    }

    // MARK: - Folder watching

    private func startWatching() {
        stopWatching()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { [weak self] in
            MainActor.assumeIsolated {
                if let fd = self?.watchedFD, fd >= 0 { close(fd) }
                self?.watchedFD = -1
            }
        }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    /// Coalesce bursts of filesystem events (a single save can fire several).
    private func scheduleReload() {
        reloadDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        reloadDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    // MARK: - Disk helpers

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A collision-free destination, named macOS-style
    /// ("Screenshot 2026-06-21 at 10.30.45.png").
    private func uniqueURL(prefix: String, date: Date, ext: String) -> URL {
        let base = "\(prefix) \(Self.timestampFormatter.string(from: date))"
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    private func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
