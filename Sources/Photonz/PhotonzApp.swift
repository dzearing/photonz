import SwiftUI

@main
struct PhotonzApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(appState)
                .frame(minWidth: 760, minHeight: 520)
                .task { appState.capture.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") { appState.isImporterPresented = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Capture") {
                // The same shortcuts are registered as global Carbon hotkeys
                // (CaptureCenter); these menu items make them discoverable and
                // clickable. ⌘⇧3/⌘⇧4 only reach us once the system Screenshots
                // shortcuts are disabled in System Settings.
                Button("Capture Full Screen") { appState.capture.captureFullScreen() }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Capture Rectangle") { appState.capture.beginRectCapture() }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Divider()
                Button(appState.capture.isHistoryVisible ? "Hide Capture History" : "Show Capture History") {
                    appState.capture.toggleHistory()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandMenu("Image") {
                Button("Resize Image…") { appState.isResizeDialogPresented = true }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(appState.document == nil)
                Button("Canvas Size…") { appState.isCanvasSizeDialogPresented = true }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(appState.document == nil)
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo") { appState.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.canUndo)
                Button("Redo") { appState.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.canRedo)
            }
            CommandMenu("Layer") {
                let selectedID = appState.selectedLayerID
                Button("Duplicate Layer") {
                    if let selectedID { appState.duplicateLayer(id: selectedID) }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(selectedID == nil)
                Button("Delete Layer") {
                    if let selectedID { appState.deleteLayer(id: selectedID) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selectedID == nil)
            }
            CommandGroup(after: .sidebar) {
                let hasDocument = appState.document != nil
                Button(appState.isLayersPanelVisible ? "Hide Layers" : "Show Layers") {
                    appState.isLayersPanelVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!hasDocument)
                Button("Zoom In") { appState.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command) // the ⌘+ key
                    .disabled(!hasDocument)
                Button("Zoom Out") { appState.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!hasDocument)
                Button("Zoom to Fit") { appState.zoomToFit() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(!hasDocument)
                Button("Actual Size") { appState.zoomToActualSize() }
                    .keyboardShortcut("1", modifiers: .command)
                    .disabled(!hasDocument)
                Divider()
            }
        }
    }
}
