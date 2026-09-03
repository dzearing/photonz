import PhotonzCore
import SwiftUI

// The two window roots every release starts from: one per editor kind, each
// owning its window's state and publishing it as the focused scene value for
// the menu commands. They live here, outside any release folder, because both
// releases use them today. A release that needs its own copy forks it into its
// own folder (see Sources/Photonz/Releases/README.md).

/// Owns this window's image `EditorState`, seeds it once from the window
/// identity, and publishes it as the focused editor for the menu commands.
struct ImageEditorRootView: View {
    let windowID: EditorWindowID?
    @Environment(AppCoordinator.self) private var coordinator
    @State private var editorState = EditorState()

    var body: some View {
        EditorView()
            .environment(editorState)
            .focusedSceneValue(\.editorState, editorState)
            .navigationTitle(editorState.windowTitle)
            // Standard document behavior: confirm before closing with unsaved
            // edits, and show the edited dot in the close button meanwhile.
            .background(WindowCloseGuard(editorState: editorState))
            .onChange(of: editorState.hasUnsavedChanges) { _, dirty in
                editorState.hostWindow?.isDocumentEdited = dirty
            }
            .task {
                // Starting from nothing while this window holds a picture opens
                // another window rather than replacing what is here.
                editorState.openBlankCanvasWindow = { [coordinator] size in
                    coordinator.newBlankCanvasWindow(size: size)
                }
                if let windowID {
                    editorState.seed(from: windowID, capture: coordinator.capture)
                }
            }
    }
}

/// Owns this window's `VideoEditorState` (phase 13.3), seeds it from the
/// recording URL, and publishes it as the focused video editor.
struct VideoEditorRootView: View {
    let url: URL
    @Environment(AppCoordinator.self) private var coordinator
    @State private var state = VideoEditorState()

    var body: some View {
        VideoEditorView()
            .environment(state)
            .focusedSceneValue(\.videoEditorState, state)
            .navigationTitle(state.windowTitle)
            // Same document behavior as an image window: confirm before closing
            // with an uncommitted trim/crop, and show the edited dot meanwhile.
            .background(WindowCloseGuard(editorState: state))
            .onChange(of: state.hasUnsavedChanges) { _, dirty in
                state.hostWindow?.isDocumentEdited = dirty
            }
            .task { state.seed(url: url, capture: coordinator.capture) }
    }
}
