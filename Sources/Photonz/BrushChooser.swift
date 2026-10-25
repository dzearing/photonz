import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI
import os

// Brushes picked by their picture (Next, `next-brush`; `brush-library.html`):
// every tile is a sample stroke painted live by that very brush, at its own
// settings and in the colour on the tool bar's swatch. The same tiles show in
// the Library's Brushes shelf and in the chooser over the tool bar, both read
// off `BrushLibrary`, so a brush added to the app is a tile in both.

// MARK: - A tile's picture

/// One brush's sample stroke on its well. Painted off the main thread by the
/// real brush engine (`BrushPreview`) and kept (`BrushPreviewCache`), so the
/// grid fills without a stall and reopening it paints nothing again. Until a
/// new picture is ready the old one stays, so a colour change repaints the
/// tiles rather than blanking them.
struct BrushTilePicture: View {
    let settings: BrushSettings
    let colorHex: String
    let size: CGSize
    /// Told when a picture lands, for the chooser's fill clock.
    var onPainted: (() -> Void)?
    @Environment(\.displayScale) private var displayScale
    @State private var painted: CGImage?

    private struct Request: Hashable {
        var settings: BrushSettings
        var colorHex: String
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat
    }

    private var request: Request {
        Request(settings: settings, colorHex: colorHex, width: size.width.rounded(),
                height: size.height.rounded(), scale: displayScale)
    }

    var body: some View {
        let dark = BrushSample.wellIsDark(forColorHex: colorHex)
        ZStack {
            // The mock's dark well for a light or bright colour, paper for a
            // dark one, so a stroke is never painted on a well it vanishes into.
            Rectangle().fill(dark
                ? LinearGradient(colors: [Color(red: 0.125, green: 0.141, blue: 0.184),
                                          Color(red: 0.078, green: 0.086, blue: 0.114)],
                                 startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [Color(red: 0.97, green: 0.96, blue: 0.93),
                                          Color(red: 0.93, green: 0.92, blue: 0.89)],
                                 startPoint: .top, endPoint: .bottom))
            if let painted {
                Image(decorative: painted, scale: request.scale)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: request) { await paint(request) }
    }

    private func paint(_ request: Request) async {
        let image = await Task.detached(priority: .userInitiated) {
            BrushPreviewCache.shared.image(settings: request.settings, colorHex: request.colorHex,
                                           size: CGSize(width: request.width, height: request.height),
                                           scale: request.scale)
        }.value
        guard !Task.isCancelled else { return }
        painted = image
        onPainted?()
    }
}

// MARK: - The Library's Brushes shelf

/// One brush on the Library shelf: its sample stroke on the shelf's card,
/// the name under it and its group on the quiet line. A click picks the brush
/// and the Brush tool with it.
struct LibraryBrushTile: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.libraryTile) private var tileMetrics
    let medium: BrushMedium

    var body: some View {
        // A button: a brush has one thing a click does, and a button takes
        // the first click in a window that is not yet key, which a tap does not.
        Button { editorState.pickBrush(medium) } label: {
            LibraryShelfTile(name: medium.title, meta: medium.group.title,
                             isSelected: editorState.armedBrush.medium == medium) {
                GeometryReader { proxy in
                    BrushTilePicture(settings: editorState.brushTileSettings(medium),
                                     colorHex: editorState.armedBrushColorHex,
                                     size: proxy.size)
                }
                .frame(height: tileMetrics.pictureHeight)
            }
        }
        .buttonStyle(.plain)
        .panelHelp("\(medium.title). Click to paint with it")
        // A control rather than a shelf tile: a brush is clicked, never
        // dragged, so a walk presses it with real mouse events at its face.
        .playtestControl(medium.title, detail: "Brushes shelf")
    }
}

/// The group chips over the brushes, All first, the mock's words.
struct BrushGroupChips: View {
    let picked: BrushGroup?
    /// The dock's narrow chips shorten Airbrush to Air, as the mock's do.
    var short = false
    let pick: (BrushGroup?) -> Void

    var body: some View {
        LibraryChipWrap {
            LibraryCatalogChip(title: "All", isOn: picked == nil) { pick(nil) }
            ForEach(BrushGroup.allCases, id: \.self) { group in
                let title = short ? group.chipTitle : group.title
                LibraryCatalogChip(title: title, isOn: picked == group) { pick(group) }
            }
        }
    }
}

// MARK: - The chooser over the tool bar

/// The brush in hand, in the tool options over the tool bar: its own little
/// sample stroke and its name. A click opens the chooser, the same tiles as
/// the Library's Brushes shelf with room to see them.
struct BrushChooserButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let medium = editorState.armedBrush.medium
        Button {
            editorState.setBrushChooserOpen(!editorState.isBrushChooserOpen)
        } label: {
            HStack(spacing: 6) {
                BrushTilePicture(settings: editorState.armedBrush,
                                 colorHex: editorState.armedBrushColorHex,
                                 size: CGSize(width: 40, height: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(medium.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 3)
            .padding(.trailing, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Pick a brush by its stroke")
        .accessibilityLabel("Brush, \(medium.title)")
        .playtestControl("Choose brush", detail: medium.title)
        .popover(isPresented: Binding(get: { editorState.isBrushChooserOpen },
                                      set: { editorState.setBrushChooserOpen($0) }),
                 arrowEdge: .top) {
            BrushChooserGrid()
                .environment(editorState)
                // The cards are drawn for the dark chrome they open from (the
                // tool bar, the dock); on a light Mac the popover would turn
                // their white names and chips white on white. The popover's
                // own window takes the dark look, so its glass darkens too.
                .preferredColorScheme(.dark)
                .background(DarkHostWindow())
                .presentationBackground(Color(red: 0.11, green: 0.12, blue: 0.15))
        }
        // Another tool picked while the chooser was up takes it down with it.
        .onDisappear { editorState.setBrushChooserOpen(false) }
    }
}

/// The chooser's tiles: the group chips, then every brush in the group, three
/// across, each its sample stroke in the current colour. Click a tile, or
/// reach it with the arrow keys and press Return; Escape closes.
struct BrushChooserGrid: View {
    @Environment(EditorState.self) private var editorState

    static let tileSize = CGSize(width: 148, height: 76)

    /// How long the grid took to fill from opening, written once per opening
    /// to the system log (`log show --predicate 'category == "brush-tiles"'`),
    /// so the cost of painting every tile is measured on the shipping build.
    @State private var opened = ContinuousClock.now
    @State private var painted = 0
    private static let log = Logger(subsystem: "com.dzearing.photonz", category: "brush-tiles")

    var body: some View {
        let brushes = editorState.brushChooserBrushes
        VStack(alignment: .leading, spacing: 10) {
            BrushGroupChips(picked: editorState.brushChooserGroup) { group in
                editorState.brushChooserGroup = group
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tileSize.width), spacing: 8),
                                     count: EditorState.brushChooserColumns),
                      alignment: .leading, spacing: 8) {
                ForEach(brushes, id: \.self) { medium in
                    tile(medium)
                }
            }
            // Named as a row, so a walk can tell the Airbrush tile from the
            // Airbrush chip above it.
            .playtestField("Brush tiles")
        }
        .padding(12)
        .frame(width: Self.tileSize.width * CGFloat(EditorState.brushChooserColumns) + 8 * 2 + 24,
               alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: brushes)
    }

    /// One tile's picture landed; the last of a fresh grid writes the clock.
    private func tilePainted() {
        painted += 1
        guard painted == BrushMedium.allCases.count else { return }
        let elapsed = opened.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        Self.log.notice("brush chooser filled \(painted) tiles in \(Int(ms)) ms")
    }

    private func tile(_ medium: BrushMedium) -> some View {
        let isHighlighted = editorState.brushChooserHighlight == medium
        // A button, not a tap gesture: a button takes the first click in a
        // popover that is not yet the key window, which a tap does not.
        return Button {
            editorState.pickBrush(medium)
            editorState.setBrushChooserOpen(false)
        } label: {
            VideoKit.Tile(name: medium.title, detail: medium.group.title,
                          isSelected: editorState.armedBrush.medium == medium,
                          thumbnailHeight: Self.tileSize.height) {
                BrushTilePicture(settings: editorState.brushTileSettings(medium),
                                 colorHex: editorState.armedBrushColorHex,
                                 size: Self.tileSize, onPainted: tilePainted)
            }
            .frame(width: Self.tileSize.width)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        // Where the arrow keys are: a white ring outside the card, plainly
        // apart from the picked one's accent border.
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
        .help(medium.blurb)
        // A control rather than a shelf tile, so a walk presses it with real
        // mouse events at its face, the way a hand picks it.
        .playtestControl(medium.title, detail: "Brush chooser")
    }
}

// MARK: - The panel's Brush section

/// The brush in hand, in the panel while the Brush tool is: its name, its
/// group, every one of its settings with the value it is at, and a line about
/// it (`brush-library.html`, Properties driven by the picked tile).
struct BrushToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let brush = editorState.armedBrush
        VStack(alignment: .leading, spacing: 6) {
            row("Name", brush.medium.title)
            row("Group", brush.medium.group.title)
            ForEach(brush.medium.settings, id: \.id) { spec in
                row(spec.name, Self.reading(spec, brush.value(spec.id)))
            }
            Text(brush.medium.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .playtestField(label)
    }

    /// A setting as it reads: a choice by its word, Size in points, the rest
    /// as a percentage.
    static func reading(_ spec: BrushSettingSpec, _ value: Double) -> String {
        if let options = spec.options {
            let index = Int(value.rounded())
            return options.indices.contains(index) ? options[index] : ""
        }
        return spec.id == "size" ? "\(Int(value.rounded())) pt" : "\(Int(value.rounded()))%"
    }
}

/// Gives the window it is hung in the dark look: the brush chooser's popover,
/// whose glass otherwise follows the Mac's light setting under cards drawn
/// for the dark chrome.
private struct DarkHostWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
