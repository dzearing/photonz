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
    static let types: [UTType] = [.fileURL, .image, .audio, .movie, .commaSeparatedText, .tabSeparatedText,
                                  EditorState.photonzType]

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
        // A table lands as a chart, on a video (`EditorState+Charts`).
        if info.hasItemsConforming(to: [.commaSeparatedText, .tabSeparatedText]) {
            return editorState?.takesChartFiles == true
        }
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

    /// Whether the drag is a picture FILE arriving from outside: a logo or a
    /// photo off the Finder, which the Library keeps on its shelf. A tile
    /// lifted off that very shelf carries a picture too, but no file.
    static func carriesPictureFile(_ info: DropInfo) -> Bool {
        Experiments.shared.droppingMedia && info.hasItemsConforming(to: [.image])
            && info.hasItemsConforming(to: [.fileURL])
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

    /// Puts every recording, sound and picture the drag carries on the
    /// Library shelf, and nothing anywhere else (`EditorState.importMedia`).
    static func keepOnShelf(_ info: DropInfo, into editorState: EditorState) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for (index, provider) in providers.enumerated() {
                if let url = await fileURL(from: provider, index: index) { urls.append(url) }
            }
            await editorState.importMedia(urls)
        }
        return true
    }

    /// The file a drag is carrying. The provider answers on a queue of its own,
    /// so this waits for it rather than blocking the pointer. Nil when the item
    /// turns out not to be a file after all, which is the same as dropping
    /// nothing.
    ///
    /// A drag can say it carries a file and still only hand over what is in
    /// it: a History tile's recording crossed the drag pasteboard as a
    /// promised movie, and asking it for its link failed, so it landed
    /// nowhere and drew no ghost (user 2026-10-27). So a movie, a sound or a
    /// picture that will not give its link is read as the file itself.
    /// The History tile the drag in the air began on, when its file is still
    /// there. The provider SwiftUI hands a drop of a History tile answers
    /// "nothing" to every way of asking it for its file (user 2026-10-28: "the
    /// timeline is not a droptarget at all").
    static func draggedFile() -> URL? {
        guard let lifted = CaptureThumbnailView.lifted,
              FileManager.default.fileExists(atPath: lifted.path) else { return nil }
        return lifted
    }

    /// Where the file a drop is carrying was found, for the line each drag
    /// writes (`TimelineFileDropDelegate.log`).
    enum Source: String, Sendable {
        case provider = "the drop itself"
        case dragPasteboard = "the drag pasteboard"
        case historyTile = "the tile lifted here"
        case representation = "a copy of its contents"
    }

    /// The drag in the air, as AppKit holds it, when one is. A walk cannot
    /// make a real drag, so it stands its own board here, and during a walk
    /// nothing else is read: the drag pasteboard is the whole Mac's and keeps
    /// the last drag made anywhere, so a walk read off it the person's own
    /// drag of the night before and landed the wrong recording (2026-10-28).
    static func dragPasteboard() -> NSPasteboard? {
        #if PHOTONZ_PLAYTEST
        if PlaytestHarness.isDrivingAWalk { return playtestPasteboard }
        #endif
        return NSPasteboard(name: .drag)
    }

    #if PHOTONZ_PLAYTEST
    /// Set by the harness for the length of one scripted file drag, and put
    /// back to nil the moment it ends.
    static var playtestPasteboard: NSPasteboard?
    #endif

    /// The file the drag in the air holds as its `index`th item, read off the
    /// drag pasteboard itself.
    ///
    /// A History tile dragged out of ANOTHER Photonz reaches this one with a
    /// provider that answers nothing, and nothing remembered on this side
    /// either: History is one folder every copy on the Mac shows, and ⇧⌘H
    /// opens the History of whichever copy holds the shortcut, which is often
    /// not the copy the video is open in (user 2026-11-13: "i can't drag any
    /// videos from history into the timeline"). The pasteboard of that very
    /// drag holds the file twice: the History file itself as its plain link,
    /// and a copy SwiftUI made in its own caches as its file link. The History
    /// file is taken, so the clip plays the recording History keeps rather
    /// than a copy nobody will ever see again.
    static func fileOnTheDrag(at index: Int = 0) -> URL? {
        guard let board = dragPasteboard() else { return nil }
        return file(on: board, at: index)
    }

    /// The file `board`'s `index`th item holds: its plain link when that is a
    /// file still on disk, otherwise its file link when that is.
    static func file(on board: NSPasteboard, at index: Int) -> URL? {
        guard let items = board.pasteboardItems, items.indices.contains(index) else { return nil }
        let item = items[index]
        let exists = { (url: URL) in url.isFileURL && FileManager.default.fileExists(atPath: url.path) }
        for type in [NSPasteboard.PasteboardType.URL, .fileURL] {
            guard let text = item.string(forType: type), let url = URL(string: text) else { continue }
            if exists(url) { return url.standardizedFileURL }
        }
        return nil
    }

    /// What a drop that could not be read carried, for the line that says so:
    /// the types its provider offered, and what the drag pasteboard held (nil
    /// during a walk that stood no board in).
    static func carried(_ provider: NSItemProvider) -> (offered: String, held: String?) {
        let held = dragPasteboard().map { board in
            board.pasteboardItems?.first?.types.map(\.rawValue).joined(separator: " ") ?? ""
        }
        return (provider.registeredTypeIdentifiers.joined(separator: " "), held)
    }

    static func fileURL(from provider: NSItemProvider, index: Int = 0) async -> URL? {
        await read(provider, index: index)?.url
    }

    /// The file a drop carries and where it was found: the provider's link,
    /// then the drag pasteboard, then the History tile this app lifted, then
    /// the contents as a file.
    ///
    /// The drag pasteboard is read before anything is awaited, while the drag
    /// that put it there is certainly still the one on it.
    static func read(_ provider: NSItemProvider, index: Int = 0) async -> (url: URL, source: Source)? {
        let found = await find(provider, index: index)
        #if PHOTONZ_PLAYTEST
        playtestLastRead = found
        #endif
        return found
    }

    #if PHOTONZ_PLAYTEST
    /// The last file a drop was read as and where it was found, so a walk can
    /// say which way a drag it carried was read.
    static var playtestLastRead: (url: URL, source: Source)?
    #endif

    private static func find(_ provider: NSItemProvider, index: Int) async -> (url: URL, source: Source)? {
        let onTheDrag = fileOnTheDrag(at: index)
        let linked: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
        // A link into SwiftUI's own drag caches is a copy made for the drag;
        // the History file it was made from is on the pasteboard beside it.
        if let linked, let onTheDrag, linked.path.contains("/com.apple.SwiftUI.Drag-") {
            return (onTheDrag, .dragPasteboard)
        }
        if let linked { return (linked, .provider) }
        if let onTheDrag { return (onTheDrag, .dragPasteboard) }
        if let carried = draggedFile() { return (carried, .historyTile) }
        return await representation(provider).map { ($0, .representation) }
    }

    /// A movie, a sound or a picture the provider will hand over as a file.
    private static func representation(_ provider: NSItemProvider) async -> URL? {
        let media: [UTType] = [.movie, .audio, .image]
        guard let type = provider.registeredTypeIdentifiers.first(where: { id in
            UTType(id).map { found in media.contains { found.conforms(to: $0) } } ?? false
        }) else { return nil }
        let name = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, inPlace, _ in
                guard let url else { return continuation.resume(returning: nil) }
                if inPlace { return continuation.resume(returning: url) }
                // A copy made for the drop is thrown away when this returns,
                // so it is kept somewhere of the app's own first.
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Dropped", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let kept = folder.appendingPathComponent(
                    name.map { $0 + "." + url.pathExtension } ?? url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: kept)
                    continuation.resume(returning: kept)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
