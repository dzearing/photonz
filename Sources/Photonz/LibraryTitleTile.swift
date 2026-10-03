import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - A title page or name card on the Library shelf (Next, video)

/// One preset on the Components shelf's Titles group (`video-title-wt.html`,
/// step 10: the lower third dragged from the Library onto a track). A picture
/// of it at rest on this document's frame, its name, and its kind under it.
/// Click picks it, double click lands it at the playhead exactly as Sequence
/// > Insert does, and dragging it onto a track lands it under the pointer
/// with the same ghost a file draws (`TitlePresetDrag`).
struct LibraryTitleTile: View {
    /// How big the shelf is drawing its tiles right now (`LibraryTileMetrics`).
    @Environment(\.libraryTile) private var tileMetrics
    @Environment(EditorState.self) private var editorState
    let preset: TitlePreset

    private var isSelected: Bool { editorState.selectedLibraryItemID == preset.id }

    var body: some View {
        let entry = preset.entry
        LibraryShelfTile(name: entry.name, meta: entry.detail, isSelected: isSelected) { thumbnail }
        .onTapGesture(count: 2) { insert() }
        .onTapGesture { editorState.selectLibraryItem(preset.id) }
        // What is in the air is noted where the drag starts, so the timeline
        // can draw the ghost the moment it arrives. It is not watched, so
        // noting it redraws nothing mid hand-over.
        .onDrag {
            editorState.titleTileLifted = preset
            return TitlePresetDrag.itemProvider(preset)
        } preview: {
            thumbnail.frame(width: tileMetrics.pictureWidth, height: tileMetrics.pictureHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .contextMenu {
            Button("Insert at Playhead") { insert() }
            if case .saved(let saved) = preset {
                Divider()
                Button("Delete Preset") { editorState.forgetTitlePreset(saved.id) }
            }
        }
        .panelHelp("\(entry.name), \(entry.detail). Drag it onto a track, or double click to insert it at the playhead.")
        .playtestTarget(entry.name, kind: .tile, detail: "Titles",
                        payload: { TitlePresetDrag.itemProvider(preset) })
        .accessibilityLabel(entry.name)
        .accessibilityValue(entry.detail)
    }

    /// The preset drawn on this document's frame shape, whole: letterboxed in
    /// the card's well rather than cut, so a name card in its corner is never
    /// the part cropped away.
    private var thumbnail: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: tileMetrics.pictureHeight)
            .overlay {
                if let image = editorState.titlePresetPicture(preset, pixelsWide: pixelsWide) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            }
            .clipped()
    }

    private var pixelsWide: CGFloat {
        LibraryShelfLayout.pictureSourceDimension(
            for: CGSize(width: tileMetrics.wellWidth, height: tileMetrics.pictureHeight))
    }

    private func insert() {
        editorState.selectLibraryItem(preset.id)
        editorState.insertTitle(preset)
    }
}

/// What the dock says about a picked title tile: its name, its kind and
/// length, and the one thing to do with it.
struct LibraryTitlePresetInspector: View {
    @Environment(EditorState.self) private var editorState
    let preset: TitlePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preset.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text("\(preset.entry.detail), \(ClipTransitionCopy.seconds(preset.lengthMS))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Insert at Playhead") { editorState.insertTitle(preset) }
                .controlSize(.small)
                .disabled(!editorState.canInsertTitle)
                .panelHelp("Puts this on the timeline at the playhead, on a track of its own")
                .playtestControl("Insert at Playhead", detail: "the picked title tile")
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 4)
    }
}

/// What a title tile carries when it is dragged: the preset's shelf id and
/// nothing else, in the app's own type, since a preset means nothing outside
/// a timeline.
enum TitlePresetDrag {
    /// DECLARED in the app's Info.plist (`Scripts/build-app.sh`,
    /// `UTExportedTypeDeclarations`), for the reason `TextStyleDrag` gives: an
    /// identifier the system has never heard of carries zero bytes.
    static let typeIdentifier = "com.photonz.title-preset"
    static let type = UTType(typeIdentifier) ?? .data

    static func itemProvider(_ preset: TitlePreset) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = preset.name
        let data = Data(preset.id.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                            visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// The preset the bytes name, among this app's presets right now.
    @MainActor static func preset(from data: Data?) -> TitlePreset? {
        data.flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { TitlePreset(entryID: $0, saved: TitlePresetStore.shared.saved) }
    }

    /// The preset a drop is carrying, read off its first provider of this type.
    @MainActor static func load(_ info: DropInfo, then use: @escaping @MainActor (TitlePreset) -> Void) {
        guard let provider = info.itemProviders(for: [type]).first else { return }
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            Task { @MainActor in
                guard let preset = preset(from: data) else { return }
                use(preset)
            }
        }
    }
}
