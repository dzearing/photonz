import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// The one reading of a file let go anywhere in the editor window.
///
/// Only pictures and Photonz documents are taken: a picture becomes a layer in
/// the open document, a document opens. Everything else — a text file, an
/// archive, a folder — is refused while it is still in the air, so the pointer
/// shows the no-entry sign rather than promising a copy that never arrives.
///
/// It lives on its own because the window is not the only surface that has to
/// answer. SwiftUI hands a drag to the INNERMOST drop target under the pointer
/// and never falls through to the one behind it, so every part of the inspector
/// that takes a drag of its own — a section header, a layer row — has to give
/// the same answer for a file, or the same panel says yes low down and no
/// higher up.
@MainActor
enum FileDrop {
    /// The types a view registers for to be offered a file at all. `.fileURL`
    /// is in the list because that is the type the file itself arrives as:
    /// without it the drop is handed a picture with no name and no path, and a
    /// Photonz document could not be opened.
    static let types: [UTType] = [.fileURL, .image, EditorState.photonzType]

    /// Whether this drag is carrying something the app can actually place.
    static func carriesUsableFile(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.image, EditorState.photonzType])
    }

    /// Takes the file the drag is carrying. A picture joins the open document
    /// as a new layer; a Photonz document opens.
    ///
    /// `landing` is the slot in the layers stack the panel promised while the
    /// file was still in the air — the one the drop line drew. Nil means land
    /// the way a drop on the canvas chrome always has, on top of everything.
    static func accept(_ info: DropInfo, into editorState: EditorState,
                       landingAt landing: LayerDrop? = nil) -> Bool {
        guard carriesUsableFile(info),
              let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        Task { @MainActor in
            guard let url = await fileURL(from: provider) else { return }
            editorState.addImageLayerOrOpen(at: url, landingAt: landing)
        }
        return true
    }

    /// The file a drag is carrying. The provider answers on a queue of its own,
    /// so this waits for it rather than blocking the pointer. Nil when the item
    /// turns out not to be a file after all, which is the same as dropping
    /// nothing.
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
