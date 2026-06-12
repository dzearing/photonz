import AppKit
import Observation
import PhotonzCore
import UniformTypeIdentifiers

/// Owns the on-disk capture library: PNGs + an index.json in Application
/// Support. Ordering/pruning policy lives in `CaptureHistory` (PhotonzCore,
/// tested); this class just mirrors that policy onto the filesystem.
@MainActor
@Observable
final class CaptureStore {
    private(set) var history = CaptureHistory()
    private var imageCache: [UUID: CGImage] = [:]

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Photonz/Captures", isDirectory: true)
    }

    init(directory: URL = CaptureStore.defaultDirectory) {
        self.directory = directory
    }

    func loadFromDisk() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode(CaptureHistory.self, from: data) else { return }
        // Drop entries whose PNG vanished (user cleaned up, iCloud, …).
        let live = saved.entries.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        history = CaptureHistory(entries: live, limit: saved.limit)
    }

    @discardableResult
    func add(_ image: CGImage, takenAt date: Date = .now) -> CaptureEntry {
        let entry = CaptureEntry(createdAt: date)
        writePNG(image, to: fileURL(for: entry))
        imageCache[entry.id] = image
        let pruned = history.add(entry)
        for old in pruned {
            try? FileManager.default.removeItem(at: fileURL(for: old))
            imageCache[old.id] = nil
        }
        saveIndex()
        return entry
    }

    func remove(id: UUID) {
        guard let entry = history.remove(id: id) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: entry))
        imageCache[entry.id] = nil
        saveIndex()
    }

    func image(for entry: CaptureEntry) -> CGImage? {
        if let cached = imageCache[entry.id] { return cached }
        guard let source = CGImageSourceCreateWithURL(fileURL(for: entry) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        imageCache[entry.id] = image
        return image
    }

    func copyToPasteboard(_ entry: CaptureEntry) {
        guard let image = image(for: entry) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    // MARK: - Disk

    private func fileURL(for entry: CaptureEntry) -> URL {
        directory.appendingPathComponent(entry.fileName)
    }

    private func writePNG(_ image: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private func saveIndex() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
