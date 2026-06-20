import AppKit
import SwiftUI

/// Carries the key window's `EditorState` to the menu commands. The editor is
/// multi-window now, so menu actions (undo, save, zoom, layer ops…) must target
/// the focused window's state rather than a single app-wide object. Each editor
/// window publishes its state via `.focusedSceneValue(\.editorState, …)`.
struct EditorStateFocusedValueKey: FocusedValueKey {
    typealias Value = EditorState
}

extension FocusedValues {
    var editorState: EditorState? {
        get { self[EditorStateFocusedValueKey.self] }
        set { self[EditorStateFocusedValueKey.self] = newValue }
    }
}

/// The app's menu-bar command set. App-level actions (capture, New, Open, About)
/// go through the resident `AppCoordinator` so they work with no window open;
/// document actions target the focused editor window (`editor`), disabling when
/// there is none.
struct EditorCommands: Commands {
    let coordinator: AppCoordinator
    @FocusedValue(\.editorState) private var editor: EditorState?

    /// True when a text field/inline editor is focused — text-editing commands
    /// must keep their system meaning there.
    private var fieldEditor: NSText? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Photonz") { coordinator.showAbout() }
        }

        // Replace the auto "New Window" so ⌘N is Preview-style "New from
        // Clipboard"; without replacing, WindowGroup's default New Window also
        // binds ⌘N and the two collide.
        CommandGroup(replacing: .newItem) {
            Button("New Window") { coordinator.newDocumentWindow() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New from Clipboard") { coordinator.newFromClipboardWindow() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { coordinator.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Save") { editor?.saveDocument() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(editor?.document == nil)
            Button("Save As…") { editor?.saveDocumentAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(editor?.document == nil)
            Divider()
            Button("Export…") { editor?.isExportDialogPresented = true }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(editor?.document == nil)
            Button("Copy Image") { editor?.copyCompositeToClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(editor?.document == nil)
        }

        CommandMenu("Capture") {
            // The same shortcuts are registered as global Carbon hotkeys
            // (CaptureCenter) on the resident agent; these menu items make them
            // discoverable and clickable, and work with no editor window open.
            // ⌘⇧3/⌘⇧4 only reach us once the system Screenshots shortcuts are
            // disabled in System Settings.
            Button("Capture Full Screen") { coordinator.capture.captureFullScreen() }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Button("Capture Rectangle") { coordinator.capture.beginRectCapture() }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Divider()
            Button(coordinator.isHistoryShown ? "Hide Capture History" : "Show Capture History") {
                coordinator.toggleHistory()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Request Screen Recording Access…") {
                coordinator.capture.requestScreenRecordingAccess()
            }
            .help("Registers Photonz in System Settings → Privacy → Screen & System Audio Recording and opens that pane.")
        }

        CommandMenu("Image") {
            Button("Resize Image…") { editor?.isResizeDialogPresented = true }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(editor?.document == nil)
            Button("Canvas Size…") { editor?.isCanvasSizeDialogPresented = true }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor?.document == nil)
        }

        // Cut/copy/paste/select-all target layers — except while an inline text
        // editor (or any text field) has focus, where they keep their text
        // meaning, so the actions forward to the field editor.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if let fieldEditor { fieldEditor.cut(nil) } else { editor?.cutSelectedLayer() }
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            Button("Copy") {
                if let fieldEditor { fieldEditor.copy(nil) } else { editor?.copySelectedLayer() }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            Button("Paste") {
                if let fieldEditor { fieldEditor.paste(nil) } else { editor?.paste() }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            Divider()
            Button("Select All") {
                if let fieldEditor { fieldEditor.selectAll(nil) } else { editor?.selectAll() }
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            Button("Deselect") { editor?.deselect() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(editor?.selection == nil)
        }

        // Must REPLACE, not append: SwiftUI's built-in .undoRedo items carry the
        // ⌘Z/⇧⌘Z shortcuts and target the responder-chain UndoManager (which we
        // never register with), so appending leaves ⌘Z dead. See
        // docs/progress/log.md 2026-06-17.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { editor?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(editor?.canUndo ?? false))
            Button("Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(editor?.canRedo ?? false))
        }

        CommandMenu("Layer") {
            let selectedID = editor?.selectedLayerID
            Button("Promote Selection to Layer") { editor?.promoteSelectionToLayer() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(editor?.selection == nil)
            Button("Blur Behind Selection") { editor?.blurBehindSelection() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(editor?.selection == nil)
            Divider()
            Button("Duplicate Layer") {
                if let selectedID { editor?.duplicateLayer(id: selectedID) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(selectedID == nil)
            Button("Delete Layer") {
                if let selectedID { editor?.deleteLayer(id: selectedID) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedID == nil)
        }

        CommandGroup(after: .sidebar) {
            let hasDocument = editor?.document != nil
            Button((editor?.isLayersPanelVisible ?? false) ? "Hide Layers" : "Show Layers") {
                editor?.isLayersPanelVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(!hasDocument)
            Button("Zoom In") { editor?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command) // the ⌘+ key
                .disabled(!hasDocument)
            Button("Zoom Out") { editor?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!hasDocument)
            Button("Zoom to Fit") { editor?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!hasDocument)
            Button("Actual Size") { editor?.zoomToActualSize() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!hasDocument)
            Divider()
        }
    }
}
