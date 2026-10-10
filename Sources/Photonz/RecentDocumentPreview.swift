import AppKit
import PhotonzRender
import QuickLookThumbnailing

/// The picture Recent draws for a document you opened: the preview a saved
/// package keeps inside it, or Quick Look's for a picture or a recording.
/// Read off the main thread, so opening the front door never waits on a disk.
enum RecentDocumentPreview {
    /// The size Quick Look is asked for, in points; a card is 136 by 84.
    private static let size = CGSize(width: 272, height: 168)

    static func image(for url: URL) async -> CGImage? {
        if url.pathExtension.lowercased() == "photonz" {
            return await Task.detached(priority: .utility) { PackageIO.readPreview(from: url) }.value
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1,
                                                   representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }
}
