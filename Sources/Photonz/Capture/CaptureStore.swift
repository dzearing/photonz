import AppKit
import Observation
import PhotonzCore
import PhotonzMedia
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
    /// Each capture's backing scale (2 for a Retina screenshot). Resolved once
    /// per file and never observed: it is always worked out in the same pass as
    /// the image itself, so nothing is waiting on it.
    @ObservationIgnored private var scaleCache: [URL: CGFloat] = [:]
    /// The last cropped thumbnail made for each capture, so a tile that redraws
    /// (hover, selection, the strip scrolling) hands SwiftUI the SAME image
    /// object instead of a fresh one every pass, which would re-upload it.
    @ObservationIgnored private var cropCache: [URL: (crop: CGRect, image: CGImage)] = [:]
    /// Media-file fingerprint each cached poster/duration was derived from, so
    /// saving a trim in the video editor (which rewrites the file) refreshes the
    /// thumbnail and duration pill.
    @ObservationIgnored private var mediaStamps: [URL: String?] = [:]

    /// Recordings that have been stopped but whose file macOS is still closing,
    /// by the name each is reserved to land under. They are in history from the
    /// moment Stop is pressed (a placeholder tile) and the file fills them in:
    /// closing a three minute recording with sound takes macOS most of a second,
    /// and nothing the person does should wait on it.
    private var saving: [URL: CaptureEntry] = [:]
    /// What is waiting on a saving recording to land: its copy to the
    /// clipboard, a request to open it.
    @ObservationIgnored private var landingWaiters: [URL: [(CaptureEntry?) -> Void]] = [:]
    /// Saving recordings deleted from history before they landed; their file
    /// goes straight to the Trash when it does.
    @ObservationIgnored private var discardedWhileSaving: Set<URL> = []
    /// The exact URL each saved recording was listed under while it was saving,
    /// by file name. The folder listing can spell the same file differently
    /// (`/private/var` for `/var`, percent-encoding), and a tile, a corner card
    /// or a waiting action holding the saving URL must keep finding it after it
    /// lands.
    @ObservationIgnored private var reservedURLs: [String: URL] = [:]

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
        for listed in urls {
            let url = reservedURLs[listed.lastPathComponent] ?? listed
            guard let kind = CaptureLibrary.kind(forPathExtension: url.pathExtension) else { continue }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            found.append(CaptureEntry(url: url, createdAt: date, kind: kind))
        }
        let sorted = CaptureLibrary.sortedNewestFirst(found)
        let listedNames = Set(urls.map(\.lastPathComponent))
        reservedURLs = reservedURLs.filter { listedNames.contains($0.key) || saving[$0.value] != nil }

        // Drop caches for files that disappeared.
        let live = Set(sorted.map(\.url))
        imageCache = imageCache.filter { live.contains($0.key) }
        durations = durations.filter { live.contains($0.key) }
        scaleCache = scaleCache.filter { live.contains($0.key) }
        cropCache = cropCache.filter { live.contains($0.key) }

        // Drop video caches whose media file changed (a save in the video
        // editor commits the trim into it), so the poster and duration
        // regenerate on next display.
        for entry in sorted where entry.kind == .video {
            let stamp = mediaStamp(for: entry.url)
            if mediaStamps[entry.url] != stamp {
                mediaStamps[entry.url] = stamp
                imageCache[entry.url] = nil
                durations[entry.url] = nil
                cropCache[entry.url] = nil
            }
        }
        mediaStamps = mediaStamps.filter { live.contains($0.key) }

        entries = CaptureLibrary.merging(listed: sorted, saving: Array(saving.values))
    }

    /// Fingerprint of a recording's media file (mtime + size); `nil` when it
    /// can't be read.
    private func mediaStamp(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        return "\(mtime)-\(size)"
    }

    // MARK: - Adding

    /// Write a screenshot into the folder; returns the new entry (after reload).
    @discardableResult
    func add(_ image: CGImage, takenAt date: Date = .now, scale: CGFloat = 1) -> CaptureEntry? {
        ensureDirectory()
        let url = uniqueURL(prefix: "Screenshot", date: date, ext: "png")
        writePNG(image, to: url, scale: scale)
        reload()
        // Match by file name: the URL `contentsOfDirectory` yields can differ
        // (percent-encoding, symlink resolution) from our constructed one.
        let entry = entries.first { $0.fileName == url.lastPathComponent }
        if let entry {
            imageCache[entry.url] = image
            scaleCache[entry.url] = max(1, scale)
            cropCache[entry.url] = nil
        }
        return entry
    }

    // MARK: - Recordings (phase 12.4), listed before their file is saved

    /// Put a just-stopped recording in history before its file exists: reserve
    /// the name it will land under and list it now, placed by when it started.
    /// Finish with `finishSaving` once the recorder hands the file back, or
    /// `failSaving` if it never does.
    func beginSaving(recordingStartedAt started: Date, takenAt date: Date = .now) -> CaptureEntry {
        ensureDirectory()
        let url = uniqueURL(prefix: "Recording", date: date, ext: "mp4")
        let entry = CaptureEntry(url: url, createdAt: started, kind: .video)
        saving[url] = entry
        reservedURLs[url.lastPathComponent] = url
        reload()
        return entry
    }

    /// The saving recording's file has closed: move it under its reserved name
    /// and let its tile become the real thing.
    @discardableResult
    func finishSaving(_ entry: CaptureEntry, tempURL: URL) -> CaptureEntry? {
        saving[entry.url] = nil
        guard discardedWhileSaving.remove(entry.url) == nil else {
            try? FileManager.default.trashItem(at: tempURL, resultingItemURL: nil)
            reload()
            land(entry.url, as: nil)
            return nil
        }
        var destination = entry.url
        if FileManager.default.fileExists(atPath: destination.path) {
            // Somebody put a file under the reserved name while it was saving.
            destination = uniqueURL(prefix: "Recording", date: .now, ext: "mp4")
        }
        var landed: CaptureEntry?
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            reload()
            landed = entries.first { $0.fileName == destination.lastPathComponent }
        } catch {
            NSLog("Couldn't file recording: \(error)")
            reload()
        }
        land(entry.url, as: landed)
        return landed
    }

    /// The recording never produced a file: take its tile down.
    func failSaving(_ entry: CaptureEntry) {
        saving[entry.url] = nil
        discardedWhileSaving.remove(entry.url)
        reload()
        land(entry.url, as: nil)
    }

    /// Whether this capture is a recording whose file is still being closed.
    func isSaving(_ url: URL) -> Bool { saving[url] != nil }

    /// Run `action` once the capture at `url` is a real file: right away when
    /// it already is, or when its recording lands. It gets nil when the
    /// recording never landed (it failed, or was deleted while saving).
    func whenLanded(_ url: URL, _ action: @escaping (CaptureEntry?) -> Void) {
        guard saving[url] != nil else {
            action(entries.first { $0.url == url })
            return
        }
        landingWaiters[url, default: []].append(action)
    }

    private func land(_ url: URL, as entry: CaptureEntry?) {
        let waiters = landingWaiters.removeValue(forKey: url) ?? []
        for waiter in waiters { waiter(entry) }
    }

    /// Override-in-place (phase 11.5): rewrite an existing capture's pixels.
    func replace(at url: URL, with image: CGImage, scale: CGFloat = 1) {
        guard entries.contains(where: { $0.url == url }) else { return }
        writePNG(image, to: url, scale: scale)
        imageCache[url] = image
        scaleCache[url] = max(1, scale)
        cropCache[url] = nil
        reload()
    }

    // MARK: - Removing

    /// Delete a capture — moves the file to the Trash (recoverable), which also
    /// removes it from history. An edited capture's layered `.photonz` sidecar
    /// goes with it.
    func remove(_ entry: CaptureEntry) {
        if saving[entry.url] != nil {
            saving[entry.url] = nil
            discardedWhileSaving.insert(entry.url)
            reload()
            return
        }
        try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        trashSidecar(for: entry.url)
        imageCache[entry.url] = nil
        durations[entry.url] = nil
        scaleCache[entry.url] = nil
        cropCache[entry.url] = nil
        reload()
    }

    /// "Clear All": move every shown capture (and its sidecar) to the Trash.
    func clearAll() {
        for entry in entries {
            if saving[entry.url] != nil {
                saving[entry.url] = nil
                discardedWhileSaving.insert(entry.url)
                continue
            }
            try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
            trashSidecar(for: entry.url)
        }
        imageCache.removeAll()
        durations.removeAll()
        scaleCache.removeAll()
        cropCache.removeAll()
        reload()
    }

    /// A capture's companions go to the Trash with it: the image editor's
    /// layered `.photonz` package, a recording's `.photonzedits` record, and the
    /// preserved original a video save kept for reversibility.
    private func trashSidecar(for url: URL) {
        for sidecar in [EditorState.sidecarURL(for: url),
                        VideoEditsSidecar.url(for: url),
                        VideoOriginals.url(for: url)]
        where FileManager.default.fileExists(atPath: sidecar.path) {
            try? FileManager.default.trashItem(at: sidecar, resultingItemURL: nil)
        }
    }

    // MARK: - Media access

    /// Thumbnail image: the screenshot itself, or a recording's poster frame
    /// (generated + cached lazily; the UI refreshes when it lands).
    func image(for entry: CaptureEntry) -> CGImage? {
        if let cached = imageCache[entry.url] { return cached }
        // A recording still being saved has no file to read yet; its tile is a
        // placeholder until it lands, and reading it now would only fail.
        if saving[entry.url] != nil { return nil }
        if entry.kind == .video {
            loadVideoMetadata(entry)
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        imageCache[entry.url] = image
        return image
    }

    /// The part of a capture a tile is showing, as its own image. The whole
    /// picture comes back unchanged when `crop` covers it, and a real crop is
    /// remembered so the identical tile drawn again is the identical object.
    func thumbnail(for entry: CaptureEntry, cropped crop: CGRect) -> CGImage? {
        guard let full = image(for: entry) else { return nil }
        let whole = CGRect(x: 0, y: 0, width: CGFloat(full.width), height: CGFloat(full.height))
        guard crop != whole else { return full }
        if let cached = cropCache[entry.url], cached.crop == crop { return cached.image }
        guard let cropped = full.cropping(to: crop) else { return full }
        cropCache[entry.url] = (crop, cropped)
        return cropped
    }

    /// The capture's backing scale: 2 for a Retina screenshot, 1 for an ordinary
    /// picture. Read from the PNG's DPI, which `writePNG` embeds as 72 x scale.
    ///
    /// A thumbnail needs this because a bitmap's pixel count is NOT the size of
    /// the picture: a 2x capture of a 60x30 point region is a 120x60 bitmap, and
    /// drawing it at 120x60 points is already twice the size the person saw.
    ///
    /// A recording has no such tag and reports 1. That is safe rather than
    /// merely convenient: a poster frame is always far bigger than a tile, so
    /// the never-upscale rule never has to decide anything about it.
    func pixelScale(for entry: CaptureEntry) -> CGFloat {
        if let cached = scaleCache[entry.url] { return cached }
        var scale: CGFloat = 1
        if entry.kind != .video,
           let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? Double {
            scale = DisplayScale.pixelScale(forDPI: dpi)
        }
        scaleCache[entry.url] = scale
        return scale
    }

    /// Recording length, loaded lazily alongside the poster.
    func duration(for entry: CaptureEntry) -> TimeInterval? {
        if let d = durations[entry.url] { return d }
        if entry.kind == .video, saving[entry.url] == nil { loadVideoMetadata(entry) }
        return nil
    }

    func copyToPasteboard(_ entry: CaptureEntry) {
        // A file that is still being closed cannot be pasted yet: copy it the
        // moment it lands.
        if saving[entry.url] != nil {
            whenLanded(entry.url) { [weak self] landed in
                if let landed { self?.copyToPasteboard(landed) }
            }
            return
        }
        if entry.kind == .video {
            // File flavors only — including the legacy one Electron apps
            // (Teams/Slack) need. Edits-aware copy (trim/crop, GIF) is the
            // coordinator's `copyRecording`.
            ClipboardWriter.writeFile(entry.url)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

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
        // The stored file is the truth (phase 19): a saved trim/crop is already
        // baked into it, so the poster and duration come straight off the file.
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
        while FileManager.default.fileExists(atPath: candidate.path) || saving[candidate] != nil {
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

    /// Writes a PNG, embedding the display scale as DPI (72 × scale) so a Retina
    /// (2×) capture keeps its scale — reopening it then shows at its on-screen
    /// point size at 100% instead of double. Without this, every capture/save
    /// flattened to a scale-less 72-DPI PNG (17.14).
    private func writePNG(_ image: CGImage, to url: URL, scale: CGFloat = 1) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        let dpi = 72 * max(1, scale)
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}
