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
            CommandGroup(replacing: .appInfo) {
                Button("About Photonz") {
                    let credits = NSMutableAttributedString(
                        string: "Fast photo & screenshot editing for the Mac.\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ])
                    credits.append(NSAttributedString(
                        string: "dzearing.github.io/photonz",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .link: URL(string: "https://dzearing.github.io/photonz/")!,
                        ]))
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
                }
            }
            // Replace the auto "New Window" so ⌘N is Preview-style "New from
            // Clipboard"; without replacing, WindowGroup's default New Window
            // also binds ⌘N and the two collide.
            CommandGroup(replacing: .newItem) {
                Button("New from Clipboard") { appState.newFromClipboard() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { appState.isImporterPresented = true }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Save") { appState.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(appState.document == nil)
                Button("Save As…") { appState.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(appState.document == nil)
                Divider()
                Button("Export…") { appState.isExportDialogPresented = true }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(appState.document == nil)
                Button("Copy Image") { appState.copyCompositeToClipboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(appState.document == nil)
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
            // Cut/copy/paste/select-all target layers — except while an inline
            // text editor (or any text field) has focus, where they must keep
            // their text meaning, so the actions forward to the field editor.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        textView.cut(nil)
                    } else {
                        appState.cutSelectedLayer()
                    }
                }
                .keyboardShortcut("x", modifiers: .command)
                Button("Copy") {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        textView.copy(nil)
                    } else {
                        appState.copySelectedLayer()
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                Button("Paste") {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        textView.paste(nil)
                    } else {
                        appState.paste()
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
                Divider()
                Button("Select All") {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        textView.selectAll(nil)
                    } else {
                        appState.selectAll()
                    }
                }
                .keyboardShortcut("a", modifiers: .command)
                Button("Deselect") { appState.deselect() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(appState.selection == nil)
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
                Button("Promote Selection to Layer") { appState.promoteSelectionToLayer() }
                    .keyboardShortcut("j", modifiers: .command)
                    .disabled(appState.selection == nil)
                Button("Blur Behind Selection") { appState.blurBehindSelection() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(appState.selection == nil)
                Divider()
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
