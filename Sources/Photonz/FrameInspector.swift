import PhotonzCore
import SwiftUI

/// A frame's own properties (Next, `next-frames`): the size it is, and what it
/// does with what hangs off its edge.
///
/// Size lives here as a menu of the screens people actually build for; the
/// exact numbers stay in Position & Size, where every layer's numbers are, so
/// there is one place to type a width and one place to pick a screen. Its
/// surface is a color, so it lives in the Color section with every other one.
struct FrameInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    /// Preview-aware, exactly as Position & Size is. A drag in flight has not
    /// reached the document, so reading the document here left this row saying
    /// 700 x 640 while the W and H fields four rows above it said 1040 x 820
    /// and the frame on the canvas was plainly the second one. One frame, one
    /// width.
    private var size: CGSize {
        editorState.previewedFrame(of: layer.id)?.size
            ?? editorState.document?.layer(id: layer.id)?.frame.size ?? layer.frame.size
    }

    private var clips: Bool {
        editorState.document?.layer(id: layer.id)?.group?.clipsContents ?? true
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
            // The menu itself is opened with a `panelMenu` step, by the size it
            // is showing; the row names it so a `panel` step says where it is.
            .playtestField("Size")

            Toggle(isOn: Binding(get: { clips },
                                 set: { editorState.setClipsContents(id: layer.id, $0) })) {
                Text("Clip contents")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .playtestControl("Clip contents", detail: clips ? "Frame, on" : "Frame, off")
            // The surface is NOT here: it is the Fill row in the Color
            // section, with every other color, and its checkbox is what used
            // to be the "No background" button in this section's popover.
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .id(layer.id)
    }

    /// The preset's name when the size is one, the numbers when it is not, so
    /// the menu never claims a screen the frame is not.
    private var currentSizeLabel: String {
        if let preset = FramePreset.matching(size) { return preset.title }
        return Self.dimensions(size)
    }

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }
}
