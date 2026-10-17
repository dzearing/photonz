import PhotonzCore
import SwiftUI

/// **Freeze Frame…**: how long to hold the frame, typed (`EditorState+FreezeAsk`).
///
/// Hangs from the clip at the playhead. A length field that opens on 2s with
/// the text picked, so typing replaces it; a Freeze every track box, off, so
/// the freeze holds this track and the others keep playing; and Insert, which
/// Return presses. Escape or a click away puts it down with nothing done. On a
/// freeze already there the button says Change.
struct FreezeFramePopover: View {
    @Environment(EditorState.self) private var editorState
    @FocusState private var lengthFocused: Bool

    static let name = "Freeze Frame"

    var body: some View {
        if let ask = editorState.freezeAsk {
            content(ask)
        }
    }

    private func content(_ ask: FreezeAsk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Length")
                    .foregroundStyle(.secondary)
                TextField("Length", text: Binding(
                    get: { editorState.freezeAsk?.text ?? "" },
                    set: { editorState.freezeAsk?.text = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                    .focused($lengthFocused)
                    .onSubmit { editorState.commitFreezeFrame() }
                    .help("Seconds, m:ss, or frames (48f)")
                    .accessibilityLabel("Freeze length")
            }
            Toggle("Freeze every track", isOn: Binding(
                get: { editorState.freezeAsk?.everyTrack ?? false },
                set: { editorState.freezeAsk?.everyTrack = $0 }))
                .toggleStyle(.checkbox)
                .help(HoldPush.everything.help)
                .playtestControl("Freeze every track", detail: Self.name)
            HStack {
                Spacer()
                Button(ask.heldPiece == nil ? "Insert" : "Change") { editorState.commitFreezeFrame() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ask.lengthMS == nil)
                    .playtestControl(ask.heldPiece == nil ? "Insert" : "Change", detail: Self.name)
            }
        }
        .padding(14)
        .frame(width: 220)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.name)
        .playtestField(Self.name)
        .onAppear { lengthFocused = true }
    }
}

extension View {
    /// Hangs the Freeze Frame popover off this view, open while it is up for
    /// `layerID`'s bar.
    func freezeFramePopover(layerID: UUID, editorState: EditorState) -> some View {
        popover(isPresented: Binding(
            get: { editorState.freezeAsk?.layerID == layerID },
            set: { if !$0, editorState.freezeAsk?.layerID == layerID { editorState.closeFreezeFrame() } }),
                arrowEdge: .top) {
            FreezeFramePopover()
                .environment(editorState)
        }
    }
}
