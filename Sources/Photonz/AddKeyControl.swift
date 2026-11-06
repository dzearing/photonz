import PhotonzCore
import SwiftUI

/// **Add Key**, full width, with the small arrow beside it
/// (`docs/design/mocks/pages/picture-keys.html`, `video.html`).
///
/// One control on a picture and a video, on screen as soon as a layer is
/// picked. The arrow holds Animate a property, for the person who wants one
/// value keyed without changing it: an Advanced way in, never the first step.
struct AddKeyControl: View {
    @Environment(EditorState.self) private var editorState
    @Binding var isPicking: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button {
                editorState.run(.keyAtPlayhead)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "diamond")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add Key")
                        .font(.system(size: 11, weight: .medium))
                    Text("K")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editorState.canKeyAtPlayhead)
            .panelHelp("Add a key at the playhead, then change the layer (K)")
            .playtestControl("Add Key", detail: "Motion")
            Divider().frame(height: 14)
            Menu {
                Section("Advanced") {
                    Button("Animate a Property") { isPicking = true }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More ways to key")
            .panelHelp("Animate one property without changing it")
            .playtestControl("Add Key Menu", detail: "Motion")
        }
        .foregroundStyle(.primary)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1)))
    }
}
