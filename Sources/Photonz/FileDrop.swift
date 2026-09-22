import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// The one reading of a file let go anywhere in the editor window.
///
/// Pictures, Photonz documents, sounds and recordings are taken: a picture
/// becomes a layer in the open document, a document opens, a sound goes on the
/// timeline and a recording lands as a clip or opens in a window of its own
/// (`MediaDrop`). Everything else — a text file, an archive, a folder — is
/// refused while it is still in the air, so the pointer shows the no-entry sign
/// rather than promising a copy that never arrives.
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
    static let types: [UTType] = [.fileURL, .image, .audio, .movie, EditorState.photonzType]

    /// Whether this drag is carrying something the app can actually place.
    ///
    /// A picture and a Photonz document are settled by the drag alone. A sound
    /// or a recording is not: a recording always has somewhere to go, and a
    /// piece of sound needs a timeline under it, so the window it is being let
    /// go on is part of the question (`MediaDrop`). Asked without one, only the
    /// two that were always usable count.
    static func carriesUsableFile(_ info: DropInfo, into editorState: EditorState? = nil) -> Bool {
        if info.hasItemsConforming(to: [.image, EditorState.photonzType]) { return true }
        guard Experiments.shared.droppingMedia else { return false }
        // A recording opens in a window of its own wherever it lands, so it is
        // usable even on a window holding nothing.
        if info.hasItemsConforming(to: [.movie]) { return true }
        if info.hasItemsConforming(to: [.audio]) { return editorState?.documentHasTime == true }
        return false
    }

    /// Whether the drag is carrying a sound or a recording, asked of the drag
    /// alone so the panel can answer while it is still in the air.
    ///
    /// Neither of those has a slot in the LAYERS STACK: a piece of sound and a
    /// clip both arrive on top, at the playhead, because where they go is a
    /// place in TIME. So a row must not draw a line promising a slot that the
    /// thing landing is going to ignore.
    static func carriesMedia(_ info: DropInfo) -> Bool {
        Experiments.shared.droppingMedia && info.hasItemsConforming(to: [.audio, .movie])
    }

    /// Whether this drag is a FILE ARRIVING AT ALL — the only kind of drag the
    /// panel's accept and refuse marks are there to answer for.
    ///
    /// The panel's targets take more than files on purpose: a layer row is
    /// registered for plain text as well, because that is how a row being
    /// reordered travels. Everything else the app carries around travels the
    /// same way — a colour off a swatch, a saved colour off the Library shelf,
    /// selected words out of a field — and all of it used to reach the row's
    /// file answer, which marked the WHOLE panel refused for a drag that had
    /// nothing to do with files. So a drag only gets an answer here when it is
    /// carrying one of the things this drop is about.
    static func isAboutAFile(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: types)
    }

    /// Takes the file the drag is carrying. A picture joins the open document
    /// as a new layer; a Photonz document opens.
    ///
    /// `landing` is the slot in the layers stack the panel promised while the
    /// file was still in the air — the one the drop line drew. Nil means land
    /// the way a drop on the canvas chrome always has, on top of everything.
    static func accept(_ info: DropInfo, into editorState: EditorState,
                       landingAt landing: LayerDrop? = nil) -> Bool {
        guard carriesUsableFile(info, into: editorState),
              let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        Task { @MainActor in
            guard let url = await fileURL(from: provider) else { return }
            // A sound or a recording goes through the one answer everything
            // else about this gesture reads (`MediaDrop`): it lands on the
            // timeline, opens in a window of its own, or is refused in words.
            // There is no stack slot for either, so the landing a panel
            // promised is not carried across.
            guard editorState.mediaDropAnswer(for: url) == nil else {
                editorState.dropMedia(at: url)
                return
            }
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
