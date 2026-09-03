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

    /// The design-tool key for each align command: the letters sit where the
    /// edge does, W and S for top and bottom, A and D for left and right, and
    /// H and V for the two middles.
    private func alignKey(_ alignment: LayerAlignment) -> KeyEquivalent {
        switch alignment {
        case .left: "a"
        case .horizontalCenter: "h"
        case .right: "d"
        case .top: "w"
        case .verticalCenter: "v"
        case .bottom: "s"
        }
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
            // Starting from nothing used to mean New Window first, then the
            // card. Here it is one step from wherever you are: the size sheet
            // opens over the window you are in, and only once you have picked
            // a size does a window appear. No shortcut: every N is spoken for
            // (⌘N New Layer, ⇧⌘N New Window, ⌥⌘N New from Clipboard).
            if Experiments.shared.blankCanvasEnabled {
                Button("New Blank Canvas…") {
                    if let editor {
                        editor.isBlankCanvasDialogPresented = true
                    } else {
                        coordinator.newBlankCanvasWindowAskingForSize()
                    }
                }
            }
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
            // Same names and order as the menu bar menu (MenuBarMenu), so a
            // command learned in one menu is found in the other.
            Button("Capture Region") { coordinator.capture.beginRectCapture() }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Button("Capture Full Screen") { coordinator.capture.captureFullScreen() }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Button(coordinator.capture.isRecording ? "Stop Recording" : "Record Screen / Video…") {
                coordinator.capture.toggleRecording()
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
            Divider()
            Button("Edit Last Capture") { coordinator.editLastCapture() }
                .keyboardShortcut("6", modifiers: [.command, .shift])
                .disabled(coordinator.lastCapture == nil)
            Button(coordinator.isHistoryShown ? "Hide History" : "Show History") {
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
            let hasLayerSelection = editor?.hasLayerSelection ?? false
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
                else { editor?.duplicateSelectedLayers() }
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(editor?.selection == nil && !hasLayerSelection)
            Button("Blur Behind Selection") { editor?.blurBehindSelection() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(editor?.selection == nil)
            Divider()
            // No shortcut (Photoshop parity: ⌘D is Deselect; ⌘J covers the
            // duplicate-selected-layer case when no region is marqueed).
            Button("Duplicate Layer") { editor?.duplicateSelectedLayers() }
                .disabled(!hasLayerSelection)
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
            // Group and ungroup, on Photoshop's keys, directly above the
            // arrange commands so the structure commands sit together
            // (`docs/design/ui-building.md`). Flagged rows are absent, not
            // greyed, so nobody hunts for why a dead row is there.
            if Experiments.shared.layerGroupsEnabled {
                Divider()
                Button("Group") { editor?.groupSelection() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(!(editor?.canGroupSelection ?? false))
                Button("Ungroup") { editor?.ungroupSelection() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!(editor?.canUngroupSelection ?? false))
            }
            // Groups that arrange their own contents (`next-auto-layout`),
            // right under Group, because a stack IS a group that arranges
            // itself and the two are pressed for the same reason. Stacking is
            // one modifier off grouping, and Photoshop binds neither the
            // command nor Control Command G. Grid Selection takes no key: it
            // is the same act with a column count, and a grid is picked far
            // less often than a row of things.
            if Experiments.shared.autoLayoutEnabled {
                Button("Stack Selection") { editor?.stackSelection(.stack) }
                    .keyboardShortcut("g", modifiers: [.command, .control])
                    .disabled(!(editor?.canStackSelection ?? false))
                Button("Grid Selection") { editor?.stackSelection(.grid) }
                    .disabled(!(editor?.canStackSelection ?? false))
            }
            // Frames sit with the structure commands, because a frame IS a
            // group with a size. Neither row takes a key: F already picks the
            // frame tool, and the design-tool key for Frame Selection (⌥⌘G) is
            // Photoshop's Create Clipping Mask, which this app may want later.
            if Experiments.shared.framesEnabled {
                Button("New Frame…") { editor?.isNewFrameDialogPresented = true }
                    .disabled(editor?.document == nil)
                Button("Frame Selection") { editor?.frameSelection() }
                    .disabled(!(editor?.canFrameSelection ?? false))
            }
            // The component commands form their own group under the structure
            // ones. Option Command K is the key a design tool user already has
            // in their fingers, and Photoshop binds neither the command nor the
            // key, so there is nothing to be compatible with.
            if Experiments.shared.componentsEnabled {
                Button("Make Component") { editor?.makeComponent() }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                    .disabled(!(editor?.canMakeComponent ?? false))
                // Insert Component takes no key: it is the keyboard way to do
                // what a drag from the shelf already does, and the shelf has to
                // be open with a component picked for it to mean anything.
                Button("Insert Component") { editor?.insertPickedComponent() }
                    .disabled(!(editor?.canInsertPickedComponent ?? false))
                // Make Alternatives is ABSENT rather than dimmed when the
                // selection cannot become a choice. Every other row here reads
                // as something you might want on any selection; this one only
                // means anything on two shapes inside an original, and a dead
                // row on every other selection is a row people hunt the reason
                // for. It appears the moment it would work.
                if editor?.canMakeChoice ?? false {
                    Button("Make Alternatives") { editor?.makeChoice() }
                }
                // Option Command B is the design-tool key for detaching, and
                // Photoshop binds neither the command nor the key. Select
                // Original takes none: it is a way to get somewhere, not an
                // edit, and the copy's own section has a button for it.
                Button("Detach Instance") { editor?.detachInstance() }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                    .disabled(!(editor?.canDetachInstance ?? false))
                Button("Select Original") { editor?.selectComponentOriginal() }
                    .disabled(!(editor?.canSelectComponentOriginal ?? false))
            }
            // Lining the selection up with itself (`next-align-layers`). Two
            // submenus rather than eight more rows, because these only ever
            // mean anything with several layers picked and the flat menu is
            // already long. The keys are the design-tool set (Option and a
            // letter, Control Option for spacing): Photoshop binds neither
            // these commands nor these keys, so there is nothing to break.
            if Experiments.shared.alignLayersEnabled {
                Divider()
                Menu("Align") {
                    ForEach(LayerAlignment.allCases, id: \.self) { alignment in
                        Button(alignment.menuTitle) { editor?.alignSelection(alignment) }
                            .keyboardShortcut(alignKey(alignment), modifiers: .option)
                            .disabled(!(editor?.canAlignSelection(alignment) ?? false))
                    }
                }
                .disabled(!(editor?.canAlignSelection ?? false))
                Menu("Space Evenly") {
                    ForEach(LayerDistribution.allCases, id: \.self) { axis in
                        Button(axis == .horizontal ? "Across" : "Down") {
                            editor?.distributeSelection(axis)
                        }
                        .keyboardShortcut(axis == .horizontal ? "h" : "v",
                                          modifiers: [.control, .option])
                        .disabled(!(editor?.canDistributeSelection ?? false))
                    }
                }
                .disabled(!(editor?.canDistributeSelection ?? false))
            }
            Divider()
            // The arrange commands, Duplicate and Delete act on the whole
            // selection: the multi-selection a shift-click, command-click or
            // marquee built, else the one selected layer.
            Button("Bring to Front") { editor?.restackSelectedLayers(.toFront) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!hasLayerSelection)
            Button("Bring Forward") { editor?.restackSelectedLayers(.forward) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!hasLayerSelection)
            Button("Send Backward") { editor?.restackSelectedLayers(.backward) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!hasLayerSelection)
            Button("Send to Back") { editor?.restackSelectedLayers(.toBack) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!hasLayerSelection)
            Divider()
            Button("Delete Layer") { editor?.deleteSelectedLayers() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!hasLayerSelection)
        }

        // The mock's Measure command group (§6, `next-measure-panel`): the tool,
        // then the same commands the Measurements panel menu offers, in the
        // panel's order and under the panel's names (§6's mirror rule: a panel
        // menu never offers a command the menu bar lacks, and both call it by
        // one name). Copy Measurement is the one extra here, since it acts on
        // the selection rather than the whole document. The flag exists only
        // in Next's catalog, so Current never grows this menu.
        if Experiments.shared.measurePanelEnabled {
            CommandMenu("Measure") {
                let count = editor?.measurementCount ?? 0
                let visibleCount = editor?.visibleMeasurementCount ?? 0
                let selectedCount = editor?.selectedMeasureLayerIDs.count ?? 0
                Button("Measure Tool") { editor?.setTool(.measure) }
                    .disabled(editor?.document == nil)
                Divider()
                // Each is off when it would change nothing: Show All while
                // every measurement is already showing, Hide All while none
                // is. Either one is a single undo step.
                Button("Show All Measurements") { editor?.setAllMeasurementsVisible(true) }
                    .disabled(visibleCount == count)
                Button("Hide All Measurements") { editor?.setAllMeasurementsVisible(false) }
                    .disabled(visibleCount == 0)
                Divider()
                // ⌃⌘C: the copy family's free chord. ⇧⌘C is Copy Image (PS
                // Copy Merged), ⌥⌘C is Canvas Size and ⌥⇧⌘C is Content-Aware
                // Scale, both Photoshop keys.
                // Only visible rows are listed, so with every row hidden the
                // item is off rather than copying a bare header.
                Button("Copy as Spec List") { editor?.copyMeasureSpecList() }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                    .disabled(visibleCount == 0)
                // Plain ⌘C on a selected measurement already carries its spec
                // line as text beside the layer payload; this is the text-only
                // form, and the one that copies a multi-selection's lines.
                Button(selectedCount > 1 ? "Copy Measurements" : "Copy Measurement") {
                    editor?.copySelectedMeasurements()
                }
                .disabled(selectedCount == 0)
                Divider()
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
            // The Library shelf, right under Show Layers because they are the
            // same kind of thing. No key: Photoshop binds none for its
            // Libraries panel, and Option Command L is already Show Layers.
            // A flagged command is absent, not greyed, so the row is simply
            // not there when the flag is off.
            if Experiments.shared.libraryEnabled {
                Button((editor?.isLibraryVisible ?? false) ? "Hide Library" : "Show Library") {
                    if let editor { editor.setLibraryVisible(!editor.isLibraryVisible) }
                }
                .disabled(!hasDocument)
            }
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
