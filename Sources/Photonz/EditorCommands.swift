import AppKit
import PhotonzCore
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

/// Carries the key window's `VideoEditorState` (phase 13.3) so the Video menu
/// targets the focused recording window.
struct VideoEditorStateFocusedValueKey: FocusedValueKey {
    typealias Value = VideoEditorState
}

extension FocusedValues {
    var videoEditorState: VideoEditorState? {
        get { self[VideoEditorStateFocusedValueKey.self] }
        set { self[VideoEditorStateFocusedValueKey.self] = newValue }
    }
}

/// The app's menu-bar command set. App-level actions (capture, New, Open, About)
/// go through the resident `AppCoordinator` so they work with no window open;
/// document actions target the focused editor window (`editor`), disabling when
/// there is none.
struct EditorCommands: Commands {
    let coordinator: AppCoordinator
    @FocusedValue(\.editorState) private var editor: EditorState?
    @FocusedValue(\.videoEditorState) private var video: VideoEditorState?

    /// True when a text field/inline editor is focused — text-editing commands
    /// must keep their system meaning there.
    private var fieldEditor: NSText? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") { coordinator.showAbout() }
            Button("Check for Updates…") { coordinator.checkForUpdates() }
            Divider()
            // Release picker + feature flags (phase 18). App-level, so it opens
            // with or without an editor window.
            Button("Experiments…") { coordinator.showExperiments() }
        }

        // Replace the auto "New Window" so its default ⌘N binding doesn't
        // collide: ⌘N belongs to Layer ▸ New Layer (user decision 2026-07-05
        // — the select → ⌘N → fill flow), clipboard moved to ⌥⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Window") { coordinator.newDocumentWindow() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New from Clipboard") { coordinator.newFromClipboardWindow() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open…") { coordinator.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            // ⌘S means the same thing in both editors: commit back to where
            // the media came from. For an image that's the flattened composite
            // written into the capture file; for a recording it's the trim/crop
            // baked into the stored MP4 (the original is preserved alongside,
            // so it stays reversible).
            Button("Save") {
                if let editor { editor.saveDocument() } else { video?.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(editor?.document == nil && !(video?.canSave ?? false))
            // For a recording, "save a copy somewhere else" IS the MP4 export —
            // same panel, same re-encode, no second flow to discover.
            Button("Save As…") {
                if let editor { editor.saveDocumentAs() }
                else if let video { coordinator.saveRecording(video, as: .mp4) }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(editor?.document == nil && !(video?.isReady ?? false))
            Button("Save to Capture History") {
                if let editor, let image = editor.compositeImage(),
                   let url = coordinator.saveEditedCapture(sourceURL: editor.sourceCaptureURL,
                                                           image: image,
                                                           scale: editor.documentPixelScale) {
                    editor.savedToCaptureHistory(at: url) // sidecar + clean baseline
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(editor?.document == nil)
            Divider()
            // ⇧⌘E — plain ⌘E is Merge Down, matching Photoshop's layer shortcuts.
            Button("Export…") { editor?.isExportDialogPresented = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor?.document == nil)
            Button("Copy Image") { editor?.copyCompositeToClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(editor?.document == nil)
        }

        CommandMenu("Capture") {
            // The same shortcuts are registered as global Carbon hotkeys
            // (CaptureCenter) on the resident agent; these menu items make them
            // discoverable and clickable, and work with no editor window open.
            // ⇧⌘3/⇧⌘4 only reach us once the system Screenshots shortcuts are
            // disabled in System Settings.
            Button("Capture Full Screen") { coordinator.capture.captureFullScreen() }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Button("Capture Rectangle") { coordinator.capture.beginRectCapture() }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Button(coordinator.capture.isRecording ? "Stop Recording" : "Record Screen / Video…") {
                coordinator.capture.toggleRecording()
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
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

        // Video menu: only meaningful in a recording window (phase 13.3). Gated
        // on the focused video state so it disables in image windows.
        CommandMenu("Video") {
            let hasVideo = video?.isReady ?? false
            Button((video?.isPlaying ?? false) ? "Pause" : "Play") { video?.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!hasVideo)
            Divider()
            Button("Set Trim Start to Playhead") {
                if let video { video.setTrimIn(video.currentTime) }
            }
            .keyboardShortcut("i", modifiers: [])
            .disabled(!hasVideo)
            Button("Set Trim End to Playhead") {
                if let video { video.setTrimOut(video.currentTime) }
            }
            .keyboardShortcut("o", modifiers: [])
            .disabled(!hasVideo)
            Divider()
            Button((video?.isCropping ?? false) ? "Finish Crop" : "Crop to Region") {
                if let video {
                    if video.isCropping { video.commitCrop() } else { video.beginCrop() }
                }
            }
            .disabled(!hasVideo)
            Button("Reset Crop") { video?.clearCrop() }
                .disabled(!(video?.crop != nil))
            Divider()
            // The saved trim/crop is reversible: the untouched original is kept
            // beside the recording, so this clears the edits and the next save
            // puts the whole clip back.
            Button("Revert to Original") { video?.revertToOriginal() }
                .disabled(!(video?.canRevertToOriginal ?? false))
            Divider()
            Button("Export MP4…") {
                if let video { coordinator.saveRecording(video, as: .mp4) }
            }
            .disabled(!hasVideo)
            Menu("Export GIF") {
                ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                    Button(quality.label) {
                        if let video { coordinator.saveRecording(video, as: .gif, quality: quality) }
                    }
                }
            }
            .disabled(!hasVideo)
            Menu("Export HEIC") {
                ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                    Button(quality.label) {
                        if let video { coordinator.saveRecording(video, as: .heic, quality: quality) }
                    }
                }
            }
            .disabled(!hasVideo)
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
            // ⌘D, Photoshop's Deselect (took it from Duplicate Layer, which
            // has no PS shortcut — ⌘J duplicates when nothing is marqueed).
            Button("Deselect") { editor?.deselect() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(editor?.selection == nil)
            // Photoshop ⇧⌘I: everything outside the current region.
            Button("Invert Selection") { editor?.invertSelection() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editor?.selection == nil)
        }

        // Must REPLACE, not append: SwiftUI's built-in .undoRedo items carry the
        // ⌘Z/⇧⌘Z shortcuts and target the responder-chain UndoManager (which we
        // never register with), so appending leaves ⌘Z dead. See
        // docs/progress/log.md 2026-06-17.
        CommandGroup(replacing: .undoRedo) {
            // ⌘Z targets the focused window: image history in an image window, or
            // the applied-edit stack (trim/crop) in a recording window (where
            // `editor` is nil and `video` is set).
            Button("Undo") {
                if let editor { editor.undo() }
                else { video?.undoLastEdit() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(editor?.canUndo ?? false) && !(video?.canUndoEdit ?? false))
            Button("Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(editor?.canRedo ?? false))
        }

        CommandMenu("Layer") {
            let selectedID = editor?.selectedLayerID
            // New empty (transparent, canvas-sized) layer. The selection
            // region is preserved, so select → ⌘N → fill paints the region
            // onto the fresh layer (user decision 2026-07-05; New from
            // Clipboard moved to ⌥⌘N).
            Button("New Layer") { editor?.newEmptyLayer() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(editor?.document == nil)
            // Photoshop ⌘J: copy the marquee selection to a new layer, or —
            // with no marquee — duplicate the selected layer.
            Button("New Layer via Copy") {
                if editor?.selection != nil { editor?.promoteSelectionToLayer() }
                else if let selectedID { editor?.duplicateLayer(id: selectedID) }
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(editor?.selection == nil && selectedID == nil)
            Button("Blur Behind Selection") { editor?.blurBehindSelection() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(editor?.selection == nil)
            Divider()
            // No shortcut (Photoshop parity: ⌘D is Deselect; ⌘J covers the
            // duplicate-selected-layer case when no region is marqueed).
            Button("Duplicate Layer") {
                if let selectedID { editor?.duplicateLayer(id: selectedID) }
            }
            .disabled(selectedID == nil)
            Button("Merge Down") { editor?.mergeDown() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!(editor?.canMergeDown ?? false))
            Button("Rasterize Layer") {
                if let selectedID { editor?.rasterizeLayer(id: selectedID) }
            }
            .disabled(!(selectedID.map { editor?.canRasterizeLayer(id: $0) ?? false } ?? false))
            Button("Arrange in Collage") { editor?.arrangeSelectionAsCollage() }
                .disabled(!(editor?.canArrangeCollage ?? false))
            Button("New Collage Layer") { editor?.newEmptyCollageLayer() }
                .disabled(editor?.document == nil)
            Divider()
            Button("Bring to Front") {
                if let selectedID { editor?.bringLayerToFront(id: selectedID) }
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(selectedID == nil)
            Button("Bring Forward") {
                if let selectedID { editor?.bringLayerForward(id: selectedID) }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(selectedID == nil)
            Button("Send Backward") {
                if let selectedID { editor?.sendLayerBackward(id: selectedID) }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(selectedID == nil)
            Button("Send to Back") {
                if let selectedID { editor?.sendLayerToBack(id: selectedID) }
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(selectedID == nil)
            Divider()
            Button("Delete Layer") {
                if let selectedID { editor?.deleteLayer(id: selectedID) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedID == nil)
        }

        // The mock's Measure command group (§6, `next-measure-panel`): the tool,
        // the two copy actions (§7), and the two whole-document actions. The
        // flag exists only in Next's catalog, so Current never grows this menu.
        if Experiments.shared.measurePanelEnabled {
            CommandMenu("Measure") {
                let count = editor?.measurementCount ?? 0
                let selectedCount = editor?.selectedMeasureLayerIDs.count ?? 0
                Button("Measure Tool") { editor?.setTool(.measure) }
                    .disabled(editor?.document == nil)
                Divider()
                // ⌃⌘C: the copy family's free chord. ⇧⌘C is Copy Image (PS
                // Copy Merged), ⌥⌘C is Canvas Size and ⌥⇧⌘C is Content-Aware
                // Scale, both Photoshop keys.
                Button("Copy as Spec List") { editor?.copyMeasureSpecList() }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                    .disabled(count == 0)
                // Plain ⌘C on a selected measurement already carries its spec
                // line as text beside the layer payload; this is the text-only
                // form, and the one that copies a multi-selection's lines.
                Button(selectedCount > 1 ? "Copy Measurements" : "Copy Measurement") {
                    editor?.copySelectedMeasurements()
                }
                .disabled(selectedCount == 0)
                Divider()
                Button("Show All Measurements") { editor?.setAllMeasurementsVisible(true) }
                    .disabled(count == 0)
                Button("Clear Measurements") { editor?.clearAllMeasurements() }
                    .disabled(count == 0)
            }
        }

        CommandGroup(after: .sidebar) {
            let hasDocument = editor?.document != nil
            Button((editor?.isLayersPanelVisible ?? false) ? "Hide Layers" : "Show Layers") {
                if let editor { editor.setInspectorVisible(!editor.isLayersPanelVisible) }
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
