import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - A recording or a sound on the Library shelf (Next, video)

/// One recording or piece of sound the document has been given, on the Media
/// shelf beside its pictures (`video.html`, Library scope Media: b-roll.mov
/// 0:04). Click picks it, double click puts it on the timeline at the
/// playhead, and dragging it onto a track lands it under the pointer exactly
/// as the same file dragged in from the Finder would, ghost, snapping and ⌘
/// insert included, because what the drag carries IS that file.
///
/// The length sits in the corner of the picture rather than on a second line
/// under the name, where Premiere's icon view puts it: the shelf is height
/// capped and every tile on it is one height (`LibraryShelfLayout`).
struct LibraryClipTile: View {
    let item: LibraryEntry
    let clip: DocumentClipItem
    @Environment(EditorState.self) private var editorState
    /// The recording's first frame, read small once the tile is on screen.
    @State private var poster: CGImage?

    private var isSelected: Bool { editorState.selectedLibraryItemID == item.id }

    var body: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            thumbnail
            Text(item.name)
                .font(.system(size: LibraryShelfLayout.captionFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(LibraryShelfLayout.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { addAtPlayhead() }
        .onTapGesture { editorState.selectLibraryItem(item.id) }
        .onDrag(dragItem, preview: {
            thumbnail.frame(width: LibraryShelfLayout.tileMinimumWidth,
                            height: LibraryShelfLayout.thumbnailHeight)
        })
        .contextMenu {
            Button("Add at Playhead") { addAtPlayhead() }
                .disabled(editorState.document?.hasTime != true)
        }
        .panelHelp("\(item.name) • \(item.detail). Drag it onto a track, or double click to add it at the playhead.")
        .playtestTarget(item.name, kind: .tile, detail: item.detail, payload: dragItem)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.detail)
        .task(id: clip.id) { await readPoster() }
    }

    /// What dragging this tile hands over: the file itself, so every place
    /// that takes a file from the Finder takes this the same way and the
    /// timeline's landing is the one it already has.
    private func dragItem() -> NSItemProvider {
        DocumentClipDrag.itemProvider(url: editorState.fileURL(of: clip), name: item.name)
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(clip.isSound ? AnyShapeStyle(Self.soundWell) : AnyShapeStyle(.quaternary))
            .frame(height: LibraryShelfLayout.thumbnailHeight)
            .overlay {
                if let poster {
                    Image(decorative: poster, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: clip.isSound ? "waveform" : "film")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(clip.isSound ? AnyShapeStyle(Color.white.opacity(0.62))
                                                      : AnyShapeStyle(.tertiary))
                }
            }
            .overlay(alignment: .bottomTrailing) { lengthBadge }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
    }

    /// How long it runs, in the corner: the mock's `.mt`, mono and faint.
    private var lengthBadge: some View {
        Text(clip.length)
            .font(.system(size: LibraryShelfLayout.tileBadgeFontSize, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, LibraryShelfLayout.tileBadgeHorizontalPadding)
            .padding(.vertical, LibraryShelfLayout.tileBadgeVerticalPadding)
            .background(Capsule().fill(.regularMaterial))
            .padding(LibraryShelfLayout.tileBadgeInset)
    }

    /// The mock's sound tile: `linear-gradient(180deg,#26463a,#1c3a30)`.
    private static let soundWell = LinearGradient(
        colors: [Color(red: 0x26 / 255, green: 0x46 / 255, blue: 0x3a / 255),
                 Color(red: 0x1c / 255, green: 0x3a / 255, blue: 0x30 / 255)],
        startPoint: .top, endPoint: .bottom)

    private func readPoster() async {
        guard let movie = clip.movie, let url = editorState.fileURL(of: clip) else { return }
        let width = LibraryShelfLayout.pictureSourceStep * 2
        let height = (width * movie.pixelSize.height / max(1, movie.pixelSize.width)).rounded()
        poster = await MovieDecoder.shared.frame(of: movie, at: url, sourceMS: 0,
                                                 size: CGSize(width: width, height: max(1, height)))
    }

    private func addAtPlayhead() {
        editorState.selectLibraryItem(item.id)
        editorState.placeLibraryPick()
    }
}

/// What a recording or sound tile carries when it is dragged: the file's own
/// URL, visible to this app only. The timeline, the picture and the layers
/// list all read it the way they read a file from the Finder. Kept inside the
/// app on purpose, since a file URL let go on the Finder can MOVE the file,
/// and the document would lose its media.
enum DocumentClipDrag {
    static func itemProvider(url: URL?, name: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        guard let url else { return provider }
        let payload = Data(url.absoluteString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier,
                                            visibility: .ownProcess) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }
}
