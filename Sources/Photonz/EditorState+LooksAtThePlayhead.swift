import Foundation
import PhotonzCore

/// The panel's look rows (Opacity, a blur's Amount, a shadow's or a glow's
/// Size, Corner Radius, Thickness) at the playhead
/// (`opacity-changes-a-shape-on-a-video-and-animates`, `LooksAtThePlayhead.swift`).
///
/// On a keyed value they read what the keys give it at the playhead and a
/// change is a key there, the way the canvas already treats a drag on a keyed
/// layer. Anything not keyed is the layer's own value, as on a picture.
extension EditorState {

    /// The document the look rows READ: each picked layer wearing its keyed
    /// look values as they are at the playhead, so the knob follows the
    /// playhead between keys. Just the document where nothing is keyed.
    var lookReadingDocument: PhotonzDocument? {
        guard let document else { return nil }
        guard documentHasTime else { return document }
        let ids = colorStyleTargetIDs.filter { document.layer(id: $0)?.motions?.isEmpty == false }
        guard !ids.isEmpty else { return document }
        return document.lookPosed(layerIDs: ids, atDocumentTimeMS: documentTimeMS)
    }

    /// One layer as the look rows read it.
    func lookAtPlayhead(of id: UUID) -> Layer? {
        guard let document, let layer = document.layer(id: id) else { return nil }
        guard documentHasTime, layer.motions?.isEmpty == false else { return layer }
        return document.lookPosed(layerIDs: [id], atDocumentTimeMS: documentTimeMS).layer(id: id)
    }

    /// A look row's edit to `doc`, made at the playhead: keyed values become
    /// keys, everything else is the layer's own. Used for the live preview and
    /// the commit alike, so what the hand sees is what lands.
    func editingLooksHere(_ ids: [UUID], in doc: inout PhotonzDocument,
                          _ mutate: (inout PhotonzDocument) -> Void) {
        guard documentHasTime else { return mutate(&doc) }
        doc.editLooks(layerIDs: ids, atDocumentTimeMS: documentTimeMS,
                      ease: newKeyEaseToWrite, mutate)
    }

    /// `perform`, for a look row: one undo step, made at the playhead.
    func performLooksHere(_ ids: [UUID], _ mutate: (inout PhotonzDocument) -> Void) {
        guard documentHasTime else { return perform(mutate) }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        perform { $0.editLooks(layerIDs: ids, atDocumentTimeMS: time, ease: ease, mutate) }
    }
}
