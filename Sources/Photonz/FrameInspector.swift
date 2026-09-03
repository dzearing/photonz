import PhotonzCore
import SwiftUI

/// A frame's own three properties (Next, `next-frames`): the size it is, what
/// it does with what hangs off its edge, and the surface it paints.
///
/// Size lives here as a menu of the screens people actually build for; the
/// exact numbers stay in Position & Size, where every layer's numbers are, so
/// there is one place to type a width and one place to pick a screen.
struct FrameInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    @State private var isBackgroundPickerShown = false

    private var size: CGSize {
        editorState.document?.layer(id: layer.id)?.frame.size ?? layer.frame.size
    }

    private var clips: Bool {
        editorState.document?.layer(id: layer.id)?.group?.clipsContents ?? true
    }

    private var backgroundHex: String? {
        editorState.document?.layer(id: layer.id)?.group?.backgroundHex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Size")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Menu {
                    ForEach(FramePreset.all) { preset in
                        Button {
                            editorState.setFrameSize(id: layer.id, size: preset.size)
                        } label: {
                            Text("\(preset.title)  \(Self.dimensions(preset.size))")
                        }
                    }
                } label: {
                    Text(currentSizeLabel)
                        .font(.callout.monospacedDigit())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Toggle(isOn: Binding(get: { clips },
                                 set: { editorState.setFrameClips(id: layer.id, $0) })) {
                Text("Clip contents")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)

            // The surface, on the same label-then-color grid every other
            // color row in the inspector uses (Next, `next-styles`).
            ColorPartRow(part: "Background", slot: .fill) {
                backgroundSwatchButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .id(layer.id)
    }

    private var backgroundSwatchButton: some View {
        Button {
            isBackgroundPickerShown = true
        } label: {
            swatch
        }
        .buttonStyle(.plain)
        .help("The surface this frame paints behind its contents")
        .popover(isPresented: $isBackgroundPickerShown, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                ColorPickerPopover(initialHex: backgroundHex ?? Layer.defaultFrameBackgroundHex,
                                   recents: editorState.recentColors.colors,
                                   embedded: true) { hex in
                    editorState.setFrameBackground(id: layer.id, hex: hex)
                }
                Divider()
                Button("No background") {
                    editorState.setFrameBackground(id: layer.id, hex: nil)
                    isBackgroundPickerShown = false
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
            .padding(14)
        }
    }

    /// The preset's name when the size is one, the numbers when it is not, so
    /// the menu never claims a screen the frame is not.
    private var currentSizeLabel: String {
        if let preset = FramePreset.matching(size) { return preset.title }
        return Self.dimensions(size)
    }

    @ViewBuilder private var swatch: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        Group {
            if let hex = backgroundHex {
                shape.fill(Color(hex: hex))
            } else {
                // No surface: the diagonal every app uses for "nothing here".
                shape.fill(.background)
                    .overlay(
                        Path { path in
                            path.move(to: CGPoint(x: 1, y: 17))
                            path.addLine(to: CGPoint(x: 17, y: 1))
                        }
                        .stroke(.red.opacity(0.8), lineWidth: 1.5))
            }
        }
        .frame(width: 18, height: 18)
        .overlay(shape.strokeBorder(.primary.opacity(0.25), lineWidth: 1))
    }

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }
}
