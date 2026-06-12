import CoreGraphics
import Foundation
import PhotonzCore

/// Reads and writes the .photonz document package: a directory holding
/// `document.json` (the pure model) and `images/<ref-uuid>.heic` (the
/// bitmaps the model's ImageRefs point at).
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

    /// Writes atomically: the package is staged in a temp directory and
    /// swapped into place, so a failed save never corrupts an existing file.
    public static func write(_ document: PhotonzDocument, store: ImageStore, to url: URL) throws {
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

    /// Unique image refs across all layers (blur-behind layers share one).
    private static func imageRefs(in document: PhotonzDocument) -> [ImageRef] {
        var seen = Set<UUID>()
        var refs: [ImageRef] = []
        for layer in document.layers {
            if case .image(let ref) = layer.content, seen.insert(ref.id).inserted {
                refs.append(ref)
            }
        }
        return refs
    }
}
