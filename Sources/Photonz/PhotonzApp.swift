import SwiftUI

@main
struct PhotonzApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(appState)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") { appState.isImporterPresented = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo") { appState.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.canUndo)
                Button("Redo") { appState.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.canRedo)
            }
        }
    }
}
