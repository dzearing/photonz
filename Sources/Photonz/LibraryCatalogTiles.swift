import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The catalog's own tiles and chips (Next, video)

// The Library's Catalog pivot in a video (`VideoCatalog`, mock
// `docs/design/mocks/pages/video-library.html`). Titles, pictures and
// components keep the tiles they already had; a moving background and a
// transition get theirs here, drawn on the same card (`LibraryShelfTile`), so
// one shelf reads as one grammar whatever kind a tile is.

/// A moving background: its look playing in the card while the pointer is on
/// it or it is picked, a still otherwise. Click picks it, double click lands
/// it at the playhead on a track of its own.
struct LibraryBackgroundTile: View {
    @Environment(\.libraryTile) private var tileMetrics
    @Environment(EditorState.self) private var editorState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let look: LiveLook
    @State private var isHovered = false

    private var id: String { VideoCatalog.backgroundID(look) }
    private var isSelected: Bool { editorState.selectedLibraryItemID == id }

    var body: some View {
        LibraryShelfTile(name: look.title, meta: VideoCatalogCategory.backgrounds.singular,
                         isSelected: isSelected) {
            // A steady rectangle with the look laid over it, the way the
            // title tile draws its reel: what the pointer lands on never
            // changes when the look starts playing under it.
            Rectangle()
                .fill(Color.black)
                .frame(height: tileMetrics.pictureHeight)
                .overlay {
                    LiveLookThumbnail(paint: VideoCatalog.backgroundPaint(look),
                                      plays: (isHovered || isSelected) && !reduceMotion)
                        .allowsHitTesting(false)
                }
                .clipped()
                .playtestHover("Background tile \(look.title)") { isHovered = $0 }
        }
        .libraryTileClicks(pick: { editorState.selectLibraryItem(id) }, open: insert)
        // Dragged onto a track it lands under the pointer, with the ghost a
        // picture draws. What is in the air is noted where the drag starts,
        // so the timeline can answer the moment it arrives.
        .onDrag {
            editorState.backgroundTileLifted = look
            return BackgroundDrag.itemProvider(look)
        } preview: {
            LiveLookThumbnail(paint: VideoCatalog.backgroundPaint(look), plays: false)
                .frame(width: tileMetrics.pictureWidth, height: tileMetrics.pictureHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .contextMenu {
            Button("Insert at Playhead") { insert() }
        }
        .panelHelp("\(look.title), a moving background. Drag it onto a track, or double click to insert it at the playhead.")
        .playtestTarget(look.title, kind: .tile, detail: "Backgrounds",
                        payload: { BackgroundDrag.itemProvider(look) })
    }

    private func insert() {
        editorState.selectLibraryItem(id)
        editorState.insertCatalogBackground(look)
    }
}

/// A transition, the one the Transitions group draws, on the shelf's card: it
/// plays while the pointer is on it. A click is the group's click (onto the
/// cut in hand, or every place it could go lights up) and a drag onto a cut
/// puts it there (`TransitionDrag`).
struct LibraryTransitionTile: View {
    @Environment(\.libraryTile) private var tileMetrics
    @Environment(EditorState.self) private var editorState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ClipTransitionKind
    @State private var isHovered = false

    var body: some View {
        let isDefault = editorState.defaultTransitionKind == kind
        LibraryShelfTile(name: kind.title, meta: TransitionsGroup.blurb(kind),
                         isSelected: editorState.transitionsGroupPick == kind) {
            thumbnail
        }
        .overlay(alignment: .topTrailing) {
            if isDefault { TransitionPicker.defaultKeycap(kind, in: "Catalog") }
        }
        // Not the shelf's pick: a click here must not let go of the cut in
        // hand, which is the very thing it is about to go on.
        .onTapGesture { editorState.pickTransitionTile(kind) }
        .onDrag {
            editorState.transitionsGroupPick = kind
            editorState.transitionTileLifted = kind
            return TransitionDrag.itemProvider(kind)
        } preview: {
            VideoKit.AnimatedTransitionThumbnail(style: TransitionPicker.style(kind))
                .frame(width: tileMetrics.pictureWidth, height: tileMetrics.pictureHeight)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .contextMenu {
            Button("Apply to Every Cut") { editorState.putTransitionOnEveryCut(kind) }
            Button("Set as Default Transition") { editorState.setDefaultTransition(kind) }
                .disabled(isDefault)
        }
        .panelHelp("\(kind.title). Drag it onto a cut on the timeline.")
        .playtestTarget(kind.title, kind: .tile, detail: "Catalog",
                        payload: { TransitionDrag.itemProvider(kind) })
    }

    @ViewBuilder
    private var thumbnail: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: tileMetrics.pictureHeight)
            .overlay {
                Group {
                    if isHovered && !reduceMotion {
                        VideoKit.AnimatedTransitionThumbnail(style: TransitionPicker.style(kind))
                    } else {
                        VideoKit.TransitionThumbnail(style: TransitionPicker.style(kind))
                    }
                }
                .allowsHitTesting(false)
            }
        .clipped()
        .playtestHover("Transition tile \(kind.title)") { isHovered = $0 }
    }
}

/// What a background tile carries when it is dragged: the look's tile id, in
/// the app's own type, DECLARED in the app's Info.plist (`Scripts/build-app.sh`)
/// for the reason `TitlePresetDrag` gives.
enum BackgroundDrag {
    static let typeIdentifier = "com.photonz.catalog-background"
    static let type = UTType(typeIdentifier) ?? .data

    static func itemProvider(_ look: LiveLook) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = look.title
        let data = Data(VideoCatalog.backgroundID(look).utf8)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                            visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// The look a drop is carrying, read off its first provider of this type.
    @MainActor static func load(_ info: DropInfo, then use: @escaping @MainActor (LiveLook) -> Void) {
        guard let provider = info.itemProviders(for: [type]).first else { return }
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            Task { @MainActor in
                guard let id = data.flatMap({ String(data: $0, encoding: .utf8) }),
                      let look = VideoCatalog.background(id: id) else { return }
                use(look)
            }
        }
    }
}

/// What the dock says about a picked background: its name, what it is, and
/// the one thing to do with it.
struct LibraryBackgroundInspector: View {
    @Environment(EditorState.self) private var editorState
    let look: LiveLook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(look.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text("Moving background, \(ClipTransitionCopy.seconds(VideoCatalog.backgroundLengthMS))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Insert at Playhead") { editorState.insertCatalogBackground(look) }
                .controlSize(.small)
                .disabled(!editorState.documentHasTime)
                .panelHelp("Puts this on the timeline at the playhead, on a track of its own")
                .playtestControl("Insert at Playhead", detail: "the picked background tile")
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 4)
    }
}

// MARK: - The kinds, as chips

/// One kind of thing in the catalog, with how many there are: picked, it is
/// the only kind the shelf shows.
struct LibraryCatalogChip: View {
    let title: String
    let count: Int
    let isOn: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .monospacedDigit()
                    // On the accent the count stays white, quieter; on the
                    // plain chip it is the secondary label colour.
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .font(.caption)
            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .panelHelp(title)
        .playtestControl(title, detail: "Catalog kind")
    }
}

/// Chips laid left to right, starting a new row rather than running off the
/// dock's edge. The packing is `ToolSettingsBar.rows`, the one the tool
/// settings capsule wraps with; unlike the capsule, rows here start at the
/// leading edge, the way a list of filters reads.
struct LibraryChipWrap: Layout {
    var spacing: CGFloat = 4
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes: [CGSize] = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows: [[Int]] = ToolSettingsBar.rows(ofWidths: sizes.map(\.width), spacing: spacing,
                                                 within: proposal.width ?? .infinity)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for row in rows {
            var rowWidth: CGFloat = spacing * CGFloat(max(0, row.count - 1))
            var rowHeight: CGFloat = 0
            for index in row {
                rowWidth += sizes[index].width
                rowHeight = max(rowHeight, sizes[index].height)
            }
            width = max(width, rowWidth)
            height += rowHeight
        }
        height += rowSpacing * CGFloat(max(0, rows.count - 1))
        // The whole width it is offered, so the chips start at the leading
        // edge of the dock rather than centred in it.
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(width: offered ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = ToolSettingsBar.rows(ofWidths: sizes.map(\.width), spacing: spacing, within: bounds.width)
        var y = bounds.minY
        for row in rows {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (height - sizes[index].height) / 2),
                                      anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += height + rowSpacing
        }
    }
}
