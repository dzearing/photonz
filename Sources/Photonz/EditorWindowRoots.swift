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
        // Equal to itself: the editor takes nothing from here but what it
        // reads for itself, and it redraws on exactly that. Without this every
        // edit re-ran the whole editor, because this body (which re-runs on
        // every edit, for the Save menu below) handed it a fresh value
        // (`a-long-captioned-recording-walk`).
        EditorView()
            .equatable()
            .environment(editorState)
            .focusedSceneValue(\.editorState, editorState)
            // What Save means in this window, recomputed here — inside a view
            // body, which IS re-run when the editor changes — so the menu is
            // told rather than having to notice (`FocusedSaveTarget`).
            .focusedSceneValue(\.saveTarget,
                               FocusedSaveTarget(editor: editorState,
                                                 affordance: editorState.saveAffordance))
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
                // A recording let go on a window holding a still picture opens
                // in a window of its own, the way a Photonz document dropped on
                // a canvas always has (`MediaDrop`). It goes through the same
                // door as File then Open, so a file that has gone or is still
                // landing says so rather than opening an empty window.
                editorState.openRecordingInItsOwnWindow = { [coordinator] url in
                    coordinator.openRecording(url)
                }
                editorState.showCaptureHistory = { [coordinator] in coordinator.showHistory() }
                // From here on this window takes the shared shelf's edits as
                // they happen (`EditorState+SharedComponents`).
                editorState.followSharedShelf()
                if let windowID {
                    // A window holding a recording says so, so asking to open
                    // the same recording again focuses it rather than
                    // re-checking a file somebody may have moved underneath it
                    // (`AppCoordinator.hasOpenRecordingWindow`).
                    if case .video(let url) = windowID {
                        coordinator.noteRecordingWindow(editorState, for: url)
                        editorState.onRecordingWouldNotOpen = { [coordinator] url in
                            coordinator.reportRecordingWouldNotOpen(url)
                            editorState.hostWindow?.close()
                        }
                    }
                    editorState.seed(from: windowID, capture: coordinator.capture)
                    // A window a guide opened for itself starts that guide as
                    // soon as its sample picture is in it, so picking the
                    // tutorial off the menu is one step, not two.
                    if case .tutorial(_, let guideID) = windowID,
                       let guide = TutorialCatalog.guide(id: guideID) {
                        TutorialController.shared.start(guide, in: editorState)
                    }
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
            // A recording reads its own length a moment AFTER its window opens,
            // so a menu that only caught up on focus events was born dimmed and
            // stayed that way. Publishing the affordance from here changes the
            // focused value when the clip lands, and the menu re-reads itself.
            .focusedSceneValue(\.saveTarget,
                               FocusedSaveTarget(editor: state,
                                                 affordance: state.saveAffordance))
            .navigationTitle(state.windowTitle)
            // Same document behavior as an image window: confirm before closing
            // with an uncommitted trim/crop, and show the edited dot meanwhile.
            .background(WindowCloseGuard(editorState: state))
            .onChange(of: state.hasUnsavedChanges) { _, dirty in
                state.hostWindow?.isDocumentEdited = dirty
            }
            .task {
                state.saves = coordinator.recordingSaves
                coordinator.noteRecordingWindow(state, for: url)
                state.seed(url: url, capture: coordinator.capture)
                // From here on a guide can find this window: one that brought
                // its own recording starts as soon as the clip is loaded, and
                // one picked off the Tutorials window later finds it standing.
                TutorialLauncher.register(state)
                #if PHOTONZ_PLAYTEST
                PlaytestHarness.register(state)
                #endif
                // Reusing a window that already holds the sample means the
                // clip is loaded before anybody is watching for it.
                if state.isReady { TutorialLauncher.startPendingGuide(in: state) }
            }
            // Loaded, sized and revealed: only now does a callout have controls
            // to point at, because nothing on the floating controller exists
            // until the clip is ready.
            .onChange(of: state.isReady) { _, ready in
                guard ready else { return }
                TutorialLauncher.startPendingGuide(in: state)
            }
    }
}
