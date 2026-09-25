import CoreGraphics
import Foundation
import PhotonzCore

/// Reads and writes the .photonz document package: a directory holding
/// `document.json` (the pure model), `images/<ref-uuid>.heic` (the
/// bitmaps the model's ImageRefs point at) and, for a video, `media.json`:
/// where each recording and sound it plays was when it was saved
/// (`ProjectMedia`). Recordings are pointed at, never copied in.
public enum PackageIO {

    public enum PackageError: Error, Equatable {
        /// A layer references a bitmap the store doesn't hold (write) or the
        /// package doesn't contain (read).
        case missingImage(UUID)
        case encodingFailed(UUID)
        case decodingFailed(UUID)
    }

    private static let documentFile = "document.json"
    private static let imagesDirectory = "images"
    private static let mediaFile = "media.json"

    /// Writes atomically: the package is staged in a temp directory and
    /// swapped into place, so a failed save never corrupts an existing file.
    public static func write(_ document: PhotonzDocument, store: ImageStore,
                             media: [ProjectMediaFile] = [], to url: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("photonz-staging-\(UUID().uuidString)")
            .appendingPathComponent(url.lastPathComponent)
        try fm.createDirectory(at: staging.appendingPathComponent(imagesDirectory),
                               withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: staging.appendingPathComponent(documentFile))
        // Only where there is something to say, so a picture's package is
        // exactly what it always was.
        if !media.isEmpty {
            try encoder.encode(media).write(to: staging.appendingPathComponent(mediaFile))
        }

        for ref in imageRefs(in: document) {
            guard let image = store.image(for: ref) else { throw PackageError.missingImage(ref.id) }
            guard let data = ImageCodec.encode(image, format: .heic, quality: 0.95) else {
                throw PackageError.encodingFailed(ref.id)
            }
            try data.write(to: staging
                .appendingPathComponent(imagesDirectory)
                .appendingPathComponent("\(ref.id.uuidString).heic"))
        }

        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: url)
        }
    }

    /// Loads the document and registers its bitmaps in `store` under their
    /// original ref ids, so the document's ImageRefs resolve unchanged.
    public static func read(from url: URL, into store: ImageStore) throws -> PhotonzDocument {
        let data = try Data(contentsOf: url.appendingPathComponent(documentFile))
        let document = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        for ref in imageRefs(in: document) {
            let imageURL = url.appendingPathComponent(imagesDirectory)
                .appendingPathComponent("\(ref.id.uuidString).heic")
            guard let imageData = try? Data(contentsOf: imageURL) else {
                throw PackageError.missingImage(ref.id)
            }
            guard let image = ImageCodec.decode(imageData) else {
                throw PackageError.decodingFailed(ref.id)
            }
            store.register(image, as: ref)
        }
        return document
    }

    /// Where the recordings and sounds a saved video plays were when it was
    /// saved. Empty for a picture, and for any package written before videos
    /// could be saved.
    public static func readMedia(from url: URL) throws -> [ProjectMediaFile] {
        let tableURL = url.appendingPathComponent(mediaFile)
        guard FileManager.default.fileExists(atPath: tableURL.path) else { return [] }
        return try JSONDecoder().decode([ProjectMediaFile].self, from: Data(contentsOf: tableURL))
    }

    /// Unique image refs across all layers (blur-behind layers share one),
    /// including the photos held inside collage slots.
    private static func imageRefs(in document: PhotonzDocument) -> [ImageRef] {
        var seen = Set<UUID>()
        var refs: [ImageRef] = []
        func collect(_ ref: ImageRef) {
            if seen.insert(ref.id).inserted { refs.append(ref) }
        }
        // Flattened, so a photo that lives inside a group is written to the
        // package too instead of the picture opening blank.
        for layer in document.flattenedLayers {
            // A clip's picture is whichever frame of its recording is under
            // the playhead, fetched from the file; it is never kept.
            if layer.movie != nil { continue }
            switch layer.content {
            case .image(let ref): collect(ref)
            case .collage(let collage):
                for slot in collage.slots { slot.imageRef.map(collect) }
            default: break
            }
        }
        return refs
    }
}
