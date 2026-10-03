import PhotonzCore
import SwiftUI

/// Save as Preset…: a name, and which list it goes in (`EditorState+TitlePresets`).
///
/// The kind opens on what the thing looks like (it fills the frame, so it is a
/// title page) and is a menu because the list of kinds grows.
struct SaveTitlePresetDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: TitleKind = .nameCard
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as Preset")
                .font(.headline)
            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .playtestField("Preset name")
                Picker("Kind", selection: $kind) {
                    ForEach(TitleKind.allCases) { kind in
                        Text(kind.name).tag(kind)
                    }
                }
                .playtestField("Preset kind")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    editorState.titlePresetSaving = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .playtestControl("Cancel", detail: "Save as Preset")
                Button("Save") {
                    if editorState.saveTitlePreset(name: name, kind: kind) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .playtestControl("Save", detail: "Save as Preset")
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            kind = editorState.titlePresetSavingKind
            name = editorState.titlePresetSuggestedName(for: kind)
            nameFocused = true
        }
    }
}
