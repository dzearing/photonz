import CoreGraphics
import Foundation
import PhotonzCore

/// The Library's Media shelf: the pictures THIS document holds, and putting
/// one of them down again.
///
/// The shelf used to list the app's whole capture folder, which is the global
/// shelf's job (History, ⇧⌘H) and meant a brand new document opened onto other
/// documents' work. What belongs here is what this file contains and can place
/// again — `DocumentMedia` decides that, in the core, where it is tested.
extension EditorState {

    /// The shelf, newest first. Empty with no document open.
    var documentMediaItems: [DocumentMediaItem] {
        document.map { DocumentMedia.items(in: $0) } ?? []
    }

    /// The same shelf as Library entries, which is what search speaks.
    var mediaEntries: [LibraryEntry] {
        document.map { DocumentMedia.entries(in: $0) } ?? []
    }

    /// The picture the picked tile stands for, nil when what is picked is a
    /// component, a style, or a tile from the document before this one.
    var selectedMediaItem: DocumentMediaItem? {
        guard let id = selectedLibraryItemID, let document else { return nil }
        return DocumentMedia.item(id: id, in: document)
    }

    /// Puts one of the document's own pictures down again as a new layer.
    /// Reuses the picture itself, so a second placement is a second layer and
    /// never a second bitmap.
    func placeMediaItem(_ item: DocumentMediaItem, at point: CGPoint? = nil) {
        placeImage(item.image, at: point, named: item.name)
    }

    /// The same, for a picture named by the id its shelf tile carries: a tile
    /// dragged onto the canvas and let go at a point.
    func placeDocumentImage(id: UUID, at point: CGPoint?) {
        guard let item = mediaItem(id: id) else { return }
        placeMediaItem(item, at: point)
    }

    /// ...and a tile let go on a ROW of the layers list, which points at a
    /// place in the stack rather than a place on the picture.
    func placeDocumentImage(id: UUID, landingAt landing: LayerDrop?) {
        guard let item = mediaItem(id: id) else { return }
        placeImage(item.image, named: item.name, landingAt: landing)
    }

    private func mediaItem(id: UUID) -> DocumentMediaItem? {
        document.flatMap { DocumentMedia.item(id: id.uuidString, in: $0) }
    }
}
