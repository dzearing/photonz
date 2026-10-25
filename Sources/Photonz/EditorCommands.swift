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

/// What Save would act on in the key window, and what it would mean there.
///
/// The menu used to reach for the image editor and the video editor separately
/// and then reason about the pair, which had two faults in one expression: the
/// action preferred the image editor while the dimming preferred whichever one
/// had something to save, so with both kinds of window open Save could look
/// live and do nothing to the recording in front of you. And because it read
/// the state objects directly, the menu only caught up on a focus event — a
/// recording that finished loading a moment after its window appeared kept the
/// dimmed Save it was born with.
///
/// This is one focused value, published by whichever window root is in front,
/// carrying both the thing to save and the answer to "what does Save mean here"
/// (`SaveAffordance`). It is `Equatable`, so the window's own view — which IS
/// re-run when the editor changes — hands SwiftUI a different value the moment
/// the affordance changes, and the menu re-reads itself.
struct FocusedSaveTarget: Equatable {
    let editor: any SaveableEditor
    let affordance: SaveAffordance

    static func == (lhs: FocusedSaveTarget, rhs: FocusedSaveTarget) -> Bool {
        lhs.editor === rhs.editor && lhs.affordance == rhs.affordance
    }
}

struct FocusedSaveTargetKey: FocusedValueKey {
    typealias Value = FocusedSaveTarget
}

extension FocusedValues {
    var saveTarget: FocusedSaveTarget? {
        get { self[FocusedSaveTargetKey.self] }
        set { self[FocusedSaveTargetKey.self] = newValue }
    }
}

/// The app's menu-bar command set. App-level actions (capture, New, Open, About)
/// go through the resident `AppCoordinator` so they work with no window open;
/// document actions target the focused editor window (`editor`), disabling when
/// there is none.
struct EditorCommands: Commands {
    /// Layer ▸ New Layer's key: Photoshop's ⇧⌘N once ⌘N is File ▸ New
    /// (`next-front-door`), ⌘N before. The right-click row prints the same.
    static var newLayerKey: KeyboardShortcut {
        Experiments.shared.frontDoorEnabled
            ? KeyboardShortcut("n", modifiers: [.command, .shift])
            : KeyboardShortcut("n", modifiers: .command)
    }

    let coordinator: AppCoordinator
    @FocusedValue(\.editorState) private var editor: EditorState?
    @FocusedValue(\.videoEditorState) private var video: VideoEditorState?
    /// What ⌘S acts on in the key window, and whether it is live there. One
    /// value read by both the action and the dimming, so they can never ask
    /// different questions (see `FocusedSaveTarget`).
    @FocusedValue(\.saveTarget) private var saveTarget: FocusedSaveTarget?

    /// The resolved answer to "what would Save do here", read by the Save
    /// action AND by its dimming so the two can never disagree.
    ///
    /// The fallback is belt and braces rather than decoration: if the focused
    /// value has not arrived for some window, Save falls back to whichever
    /// state object is in front, which is what it used to do. Losing the
    /// focused value can then cost a menu that is a moment stale; it can never
    /// cost a Save that is dimmed on a document with work in it, which is the
    /// failure this whole change is about.
    private var focusedSave: FocusedSaveTarget? {
        if let saveTarget { return saveTarget }
        if let editor, editor.document != nil {
            return FocusedSaveTarget(editor: editor, affordance: editor.saveAffordance)
        }
        if let video { return FocusedSaveTarget(editor: video, affordance: video.saveAffordance) }
        if let editor { return FocusedSaveTarget(editor: editor, affordance: editor.saveAffordance) }
        return nil
    }

    /// True when a text field/inline editor is focused — text-editing commands
    /// must keep their system meaning there.
    private var fieldEditor: NSText? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    /// The Edit menu's home for the foreground and background fills.
    ///
    /// The colour capsule appears only for the tools that paint
    /// (`Tool.colorControl`), so with Select, crop, a marquee or the wand in
    /// hand there are no swatches on the bar. The pair goes on painting all the
    /// same: ⌥⌫ fills what you picked with the foreground, ⌫ clears a locked
    /// background to the background colour, and growing the canvas outward
    /// paints the new space with it. These three rows are where you can see
    /// which two colours that is, and swap them, without picking up the bucket
    /// first. Each row wears the colour it would use, so the menu ANSWERS the
    /// question rather than naming a setting you then have to go and read.
    ///
    /// Swap carries no key equivalent even though X does it. Not for safety:
    /// an earlier note here said a plain letter in the menu bar would swallow
    /// an X typed into a text field, and that is simply not how AppKit
    /// dispatches. A key equivalent is offered to the key window's views
    /// before the main menu, and the field editor claims both a plain letter
    /// and ⌥⌫ for itself, so a focused field keeps them either way (measured
    /// both ways on 2026-09-08 against a control case that fired the menu).
    ///
    /// What the ⌫ rows carry. A real ⌫ press carries U+007F, but AppKit only
    /// matches it against a row holding U+0008, so a row holding U+007F prints
    /// ⌫ and no press ever reaches it (`DeleteKeyCharacters.menuKeyEquivalent`).
    /// Measured on 2026-09-28 with events built by CoreGraphics the way a
    /// keyboard builds them, against SwiftUI rows: U+007F matched never, bare
    /// or with ⌘ or ⌥, and U+0008 matched every time; and in the probe with
    /// its menu bar live, ⌘⌫ and ⌥⌫ went past both rows to the canvas. An
    /// earlier note here (2026-09-17) said the opposite because it measured
    /// with a hand-built `NSEvent`, which matches U+007F and no real press
    /// ever looks like. With a field holding the keyboard a live ⌥⌫ row
    /// still leaves the press to the field; a live ⌘⌫ row does not, it wins
    /// even mid-rename, so Delete Layer hands the press back to the field
    /// itself (`deleteLayerRow`).
    /// The reason is plainer: an unmodified letter in the menu bar is not a
    /// Mac idiom, and X is already taught on the bucket's swap button, which
    /// wears it as a tooltip. X itself lives on an invisible stand-in in the
    /// tool bar, the same idiom the tool letters use, so it answers under
    /// every tool rather than only the one with the swatches.
    /// Edit ▸ Transform: Flip Horizontal and Flip Vertical, on what is picked
    /// (`EditorState+Flip.swift`).
    private var transformMenu: some View {
        Menu("Transform") {
            Button(FlipAxis.horizontal.title) { editor?.run(.flipHorizontal) }
                .disabled(!(editor?.canRun(.flipHorizontal) ?? false))
            Button(FlipAxis.vertical.title) { editor?.run(.flipVertical) }
                .disabled(!(editor?.canRun(.flipVertical) ?? false))
        }
    }

    @ViewBuilder private var fillRows: some View {
        Button {
            editor?.run(.fillWithForeground)
        } label: {
            Label { Text("Fill with Foreground") } icon: { Self.swatch(editor?.foregroundFillHex) }
        }
        // U+0008, the character AppKit matches a real ⌫ against, once
        // `next-menu-keys-do-what-they-say` is on; U+007F off, which prints ⌫
        // and leaves the press to the canvas. See `DeleteKeyCharacters`.
        .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuRow(
            answersThePress: Experiments.shared.menuKeysDoWhatTheySayEnabled)), modifiers: .option)
        .disabled(!(editor?.canFillWithFillColors ?? false))
        Button {
            editor?.run(.fillWithBackground)
        } label: {
            Label { Text("Fill with Background") } icon: { Self.swatch(editor?.backgroundFillHex) }
        }
        .disabled(!(editor?.canFillWithFillColors ?? false))
        Button("Swap Fill Colors") { editor?.run(.swapFillColors) }
            .disabled(!(editor?.canRun(.swapFillColors) ?? false))
    }

    /// Layer ▸ Delete Layer, on ⌘⌫.
    ///
    /// Off (`next-menu-keys-do-what-they-say`), the row holds U+007F, which
    /// prints ⌫ and which no press reaches, so only the canvas answers ⌘⌫. On,
    /// it holds U+0008 and the press reaches it from anywhere, the layers list
    /// included. A live ⌘⌫ row wins over a text field too (measured
    /// 2026-09-28), so while a field is being typed in the row does to the
    /// field what ⌘⌫ means there, delete to the start of the line, the same
    /// way Cut, Copy and Paste act on a field that has the keyboard. It cannot
    /// tell a press from a pick with the mouse: SwiftUI runs the action later,
    /// when `NSApp.currentEvent` is no longer the key press.
    @ViewBuilder private var deleteLayerRow: some View {
        let live = Experiments.shared.menuKeysDoWhatTheySayEnabled
        Button("Delete Layer") {
            if live, let fieldEditor {
                fieldEditor.doCommand(by: #selector(NSStandardKeyBindingResponding.deleteToBeginningOfLine(_:)))
            } else {
                editor?.run(.deleteLayer)
            }
        }
        .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuRow(answersThePress: live)),
                          modifiers: .command)
        // Off while everything picked is locked: the lock is a promise the
        // menu keeps out loud, so the row says no before the press rather
        // than the layer disappearing under one. A dimmed row declines the
        // press (`performKeyEquivalent` answers false for it, measured
        // 2026-09-28), so it goes on to whatever has the keyboard.
        .disabled(!(editor?.canRun(.deleteLayer) ?? false))
    }

    /// A menu row's colour chip. Drawn rather than tinted from a symbol because
    /// a menu row's image is a template by default, which would paint every
    /// colour the same grey.
    private static func swatch(_ hex: String?) -> Image {
        let side: CGFloat = 12
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 2.5, yRadius: 2.5)
            NSColor(Color(hex: hex ?? "#000000")).setFill()
            path.fill()
            path.lineWidth = 1
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
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

    /// Help ▸ Tutorials, read straight off the catalogue: the promoted guide,
    /// one submenu per populated track, and the way into the window. Nothing
    /// here writes a guide's name down, so a guide added to the data gets its
    /// row with this file untouched.
    /// Less anything teaching a feature this app has switched off
    /// (`TutorialLauncher.offered`): a row for a mode that is not there rings
    /// a button nobody can press.
    private var tutorialMenu: TutorialMenuModel {
        TutorialMenuModel(guides: TutorialLauncher.offered)
    }

    private func startTutorial(_ guide: TutorialGuide) {
        TutorialLauncher.start(guide, coordinator: coordinator,
                               editor: editor ?? TutorialLauncher.frontEditor())
    }

    /// One guide's row, wherever it appears. A guide that teaches over your own
    /// picture is dimmed with nothing open, rather than doing nothing when
    /// pressed.
    @ViewBuilder
    private func tutorialRow(_ row: TutorialMenuModel.GuideRow) -> some View {
        Button(row.title) { startTutorial(row.guide) }
            .help(row.help)
            .disabled(row.guide.sample == nil && editor == nil
                      && TutorialLauncher.frontEditor() == nil)
    }

    /// Whether Export… has a recording to open the sheet on.
    ///
    /// Written out rather than inlined so the action and the dimming read off
    /// the same test: the plain Save had them disagree once, and the item
    /// looked alive while doing nothing.
    private func offersRecordingExportSheet(_ video: VideoEditorState?) -> Bool {
        Experiments.shared.recordingExportSheetEnabled && (video?.isReady ?? false)
    }

    /// The key a mode answers to: ⌃1 … ⌃9, in the order the list shows them, so
    /// the menu, the chip's list and the keyboard never disagree about which
    /// number means which mode (`WindowModes.shortcutNumber`).
    ///
    /// Control rather than Command: every Command digit in this app is already
    /// spoken for (⌘0 fits, ⌘1 is actual size) and Photoshop spends its own on
    /// channels, so a mode taking one would be taking it off something a hand
    /// already knows.
    private func modeKey(_ id: String) -> KeyboardShortcut? {
        guard let number = WindowModes.shortcutNumber(for: id),
              let character = String(number).first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: .control)
    }

    /// File > Open Recent: the same documents the front door's Recent puts
    /// among your captures, newest first.
    private var openRecentMenu: some View { OpenRecentMenu(coordinator: coordinator) }

    var body: some Commands {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.menuCommands)
        #endif
        // The playhead is read unwatched from here to the end, and what the
        // menu shows about it is watched through one value that changes only
        // when the playhead crosses something (`EditorState+MenuPlayhead`).
        let _ = EditorState.beginMenuRead(editor)
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") { coordinator.showAbout() }
            Button("Open Source Notices…") { coordinator.showOpenSourceNotices() }
            Button("Check for Updates…") { coordinator.checkForUpdates() }
            Divider()
            // Release picker + feature flags (phase 18). App-level, so it opens
            // with or without an editor window.
            Button("Experiments…") { coordinator.showExperiments() }
        }

        // File reads like every Mac app's at Next (`next-front-door`, the
        // user's call on 2026-10-22): what makes something new at the top,
        // New (⌘N) opening the New window that makes an Image or a Video,
        // then Open and Open Recent, then capture as its own section, then
        // Save and Export. New Layer moved to ⇧⌘N, Photoshop's key for it.
        //
        // Off, the auto "New Window" is replaced so its default ⌘N binding
        // doesn't collide: ⌘N belongs to Layer ▸ New Layer (user decision
        // 2026-07-05, the select → ⌘N → fill flow), clipboard moved to ⌥⌘N.
        CommandGroup(replacing: .newItem) {
            if Experiments.shared.frontDoorEnabled {
                Button("New…") { coordinator.newDocumentWindow() }
                    .keyboardShortcut("n", modifiers: .command)
            } else {
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
                // A video from nothing, the mock's New video (`video.html`, step
                // 1): Premiere's File ▸ New ▸ Sequence, with no shortcut for the
                // same reason New Blank Canvas has none.
                if Experiments.shared.blankVideoEnabled {
                    Button("New Video…") {
                        if let editor {
                            editor.isBlankVideoDialogPresented = true
                        } else {
                            coordinator.newBlankVideoWindowAskingForSize()
                        }
                    }
                }
            }
            // The empty window's Design UI row, in the menu bar too. No
            // ellipsis: it asks nothing, it opens. No shortcut, as above. Off
            // by default at Next since 2026-10-22: New makes an Image or a
            // Video, and a UI design is the Design mode inside an image.
            if Experiments.shared.designUIStartEnabled {
                Button(UIStarter.menuTitle) {
                    if let editor {
                        editor.startUIDesign()
                    } else {
                        coordinator.newUIDesignWindow()
                    }
                }
            }
            Button("New from Clipboard") { coordinator.newFromClipboardWindow() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            if Experiments.shared.frontDoorEnabled { Divider() }
            Button("Open…") { coordinator.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
            // The documents you opened and saved, where every Mac app keeps
            // them, with Clear Menu at the foot (`next-recent-documents`).
            if Experiments.shared.recentDocumentsEnabled {
                openRecentMenu
            }
            // Recordings and sounds onto the Library shelf and nowhere else,
            // the mock's File row (`video.html`) and where Premiere and Final
            // Cut people look for it. ⇧⌘I is Photoshop's Invert Selection too,
            // so the key is Import only while there is no marquee to invert;
            // with one up it stays Invert and Photoshop hands never notice.
            if Experiments.shared.libraryEnabled && Experiments.shared.droppingMedia {
                Button("Import Media…") { editor?.run(.importMedia) }
                    .keyboardShortcut(editor?.selection == nil
                                      ? KeyboardShortcut("i", modifiers: [.command, .shift]) : nil)
                    .disabled(!(editor?.canImportMedia ?? false))
            }
            fileCaptureSubmenu
            if !Experiments.shared.frontDoorEnabled {
                Divider()
                saveRows
            }
        }
        // Close above Save, where every Mac document app has it (Preview,
        // Pages, Photoshop): the save section is the app's own, with its own
        // Close in place of the one SwiftUI hangs after everything else.
        if Experiments.shared.frontDoorEnabled {
            CommandGroup(replacing: .saveItem) {
                Button("Close") { NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil) }
                    .keyboardShortcut("w", modifiers: .command)
                saveRows
            }
        }

        // Cut/copy/paste/select-all target layers — except while an inline text
        // editor (or any text field) has focus, where they keep their text
        // meaning, so the actions forward to the field editor.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                // Keys picked on a lane are the smaller, more recent thing in
                // hand, so ⌘X, ⌘C and ⌘V take those before the layer
                // (`EditorState+KeyLanes`, Premiere's keyframe clipboard),
                // and a range drawn on the ruler next
                // (`EditorState+RangeClipboard`).
                if let fieldEditor {
                    fieldEditor.cut(nil)
                } else {
                    editor?.run(.cut)
                }
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            Button("Copy") {
                if let fieldEditor {
                    fieldEditor.copy(nil)
                } else {
                    editor?.run(.copy)
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            // Photoshop ⇧⌘C, and Photoshop's place for it: directly under
            // Copy, so the one that takes the layer you picked and the one
            // that takes everything read as a pair.
            if Experiments.shared.copyPicksYourLayerEnabled {
                Button("Copy Merged") { editor?.run(.copyMerged) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(editor?.document == nil)
            }
            // A drawing's code as text, for a code editor: Photoshop's Copy
            // SVG, under the copies it sits beside. No key; dimmed on a
            // screenshot, which is pixels however it is written.
            if Experiments.shared.svgExportEnabled {
                Button("Copy SVG") { editor?.run(.copySVG) }
                    .disabled(!(editor?.canRun(.copySVG) ?? false))
            }
            // The edit onto the clipboard as a file, to paste into a chat
            // without exporting one first: Current's recording window had
            // these on its own bar. Every Copy key with ⌘ and one or two of
            // ⇧ ⌥ ⌃ is taken, so ⌃⇧⌘, with G for the GIF.
            if Experiments.shared.videoExportEnabled {
                Button("Copy Video") { editor?.run(.copyVideo) }
                    .keyboardShortcut("c", modifiers: [.command, .shift, .control])
                    .disabled(!(editor?.canCopyVideo ?? false))
                Button("Copy as GIF") { editor?.run(.copyAsGIF) }
                    .keyboardShortcut("g", modifiers: [.command, .shift, .control])
                    .disabled(!(editor?.canCopyVideo ?? false))
            }
            Button("Paste") {
                if let fieldEditor {
                    fieldEditor.paste(nil)
                } else {
                    editor?.run(.paste)
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            Divider()
            Button("Select All") {
                if let fieldEditor { fieldEditor.selectAll(nil) } else { editor?.run(.selectAll) }
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(editor == nil && fieldEditor == nil)
            // ⌘D, Photoshop's Deselect (took it from Duplicate Layer, which
            // has no PS shortcut — ⌘J duplicates when nothing is marqueed).
            Button("Deselect") { editor?.run(.deselect) }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!(editor?.canRun(.deselect) ?? false))
            // Photoshop ⇧⌘I: everything outside the current region.
            Button("Invert Selection") { editor?.run(.invertSelection) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!(editor?.canRun(.invertSelection) ?? false))
            Divider()
            fillRows
            // Photoshop's Edit ▸ Transform, under Fill where Photoshop keeps
            // it, with the pair it gives no keys (UX-PATTERNS §7).
            if Experiments.shared.flipLayersEnabled {
                Divider()
                transformMenu
            }
            if Experiments.shared.proMenuBarEnabled {
                Divider()
                toolsMenu
            }
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
            // Ask (Next, `next-ask`), in Edit beside the Mac's own Writing
            // Tools. ⌘K as the mock prints it, except on a video, where ⌘K
            // is Premiere's Add Edit (Split at Playhead, UX-PATTERNS §7).
            // Ready in a window with nothing open too: there it makes a
            // picture for the request, and in the New window it is the
            // Describe field (`AskSession.summon`).
            if Experiments.shared.askEnabled {
                Divider()
                Button("Ask…") { if let editor { editor.ask.summon(in: editor) } }
                    .keyboardShortcut(timed ? nil : KeyboardShortcut("k", modifiers: .command))
                    .disabled(editor == nil)
            }
        }

        documentMenus

        viewAndHelpCommands
        let _ = EditorState.endMenuRead()
    }

    // MARK: - The menus for what the document is made of

    /// Image, Layer, then Clip and Sequence on a document with time, then
    /// Measure: the order a Photoshop or Final Cut user reads along the top of
    /// the screen (`MenuBarOrder`). Declared in that order because SwiftUI
    /// lays its menus out in the order they are declared; `MenuBarArranger`
    /// then puts View after them.
    ///
    /// With `next-a-pro-menu-bar` off, the old set: Capture, Image, Video,
    /// Layer, Measure.
    @CommandsBuilder private var documentMenus: some Commands {
        if !Experiments.shared.proMenuBarEnabled {
            captureMenu
        }
        imageMenu
        if !Experiments.shared.proMenuBarEnabled {
            videoMenu
        }
        layerMenu
        // Only on a document with time: a picture has no clips and no
        // sequence, and a menu of dimmed rows it can never use is a menu that
        // lies about what the document is.
        if Experiments.shared.proMenuBarEnabled && timed {
            clipMenu
            sequenceMenu
        }
        measureMenu
    }

    /// Whether the document in front has time, so a video rather than a
    /// picture.
    private var timed: Bool { editor?.documentHasTime ?? false }

    /// The Premiere keys that are also Photoshop tool letters mean the
    /// timeline's thing only while the timeline has the keyboard, and the rows
    /// print them only then, so the menu never promises a key the canvas is
    /// about to spend on a tool (`EditorState+TimelineKeys`).
    private var timelineKeys: Bool { timed && (editor?.timelineHasKeyboard ?? false) }

    // MARK: Save

    /// File's Save, Save As, Save to Capture History, Export and Copy Image.
    @ViewBuilder private var saveRows: some View {
        // ⌘S means the same thing in both editors: commit back to where
        // the media came from. For an image that's the flattened composite
        // written into the capture file; for a recording it's the trim/crop
        // baked into the stored MP4 (the original is preserved alongside,
        // so it stays reversible).
        Button("Save") {
            if let editor = focusedSave?.editor as? EditorState { editor.run(.save) }
            else { focusedSave?.editor.performSave { _ in } }
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!(focusedSave?.affordance.isSaveEnabled ?? false))
        // For a recording, "save a copy somewhere else" IS the export, so
        // it goes through the one Export sheet rather than a second flow to
        // discover (Next, `next-recording-export-sheet`). With the flag off
        // it is the bare save box with MP4 already decided, as before.
        // Same order in the action as in the dimming below, which is the
        // fault the plain Save had: an action that preferred the image
        // editor under a test that preferred whoever had something to save.
        Button("Save As…") {
            if editor?.document != nil { editor?.saveDocumentAs() }
            else if let video {
                if Experiments.shared.recordingExportSheetEnabled {
                    video.isExportSheetPresented = true
                } else {
                    coordinator.saveRecording(video, as: .mp4)
                }
            }
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(editor?.document == nil && !(video?.isReady ?? false))
        // A picture only. It flattens the window into one PNG, which for a
        // video is a single still frame; a recording in history is saved
        // into history by Save itself (`HistoryVideoSave`).
        if editor?.documentHasTime != true {
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
        }
        Divider()
        // ⇧⌘E — plain ⌘E is Merge Down, matching Photoshop's layer shortcuts.
        // On a video too (UX-PATTERNS §7): Premiere gives ⌘E to Edit
        // Original and Export to ⌘M, so neither tool gives ⌘E to Export,
        // and Merge Down there never takes a layer with time
        // (`LayerMerge.swift`).
        // One Export command for both editors: a picture and a recording
        // leave the app through the same sheet and the same key.
        Button("Export…") {
            if editor?.document != nil { editor?.isExportDialogPresented = true }
            else if let video, Experiments.shared.recordingExportSheetEnabled {
                video.isExportSheetPresented = true
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        // One file at a time: the window stays usable while a video
        // writes, but a second export would have nowhere to go.
        .disabled((editor?.document == nil && !(offersRecordingExportSheet(video)))
                  || editor?.videoExport != nil)
        // Copy Merged took this key and moved next to Copy in Edit, where
        // the difference between the two copies is readable. Off, the
        // picture-of-everything copy stays here as Copy Image.
        if !Experiments.shared.copyPicksYourLayerEnabled {
            Button("Copy Image") { editor?.copyCompositeToClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(editor?.document == nil)
        }
    }

    // MARK: Capture

    // The same shortcuts are registered as global Carbon hotkeys
    // (CaptureCenter) on the resident agent; these menu items make them
    // discoverable and clickable, and work with no editor window open.
    // ⇧⌘3/⇧⌘4 only reach us once the system Screenshots shortcuts are
    // disabled in System Settings.
    // Same names and order as the menu bar menu (MenuBarMenu), so a
    // command learned in one menu is found in the other.
    @ViewBuilder private var captureRows: some View {
        Button(CaptureMenuNames.captureRegion) { coordinator.capture.beginRectCapture() }
            .keyboardShortcut("4", modifiers: [.command, .shift])
        Button(CaptureMenuNames.captureFullScreen) { coordinator.capture.captureFullScreen() }
            .keyboardShortcut("3", modifiers: [.command, .shift])
        Button(CaptureMenuNames.recording(isRecording: coordinator.capture.isRecording)) {
            coordinator.capture.toggleRecording()
        }
        .keyboardShortcut("5", modifiers: [.command, .shift])
        // One section in File, where these sit between Open and Save.
        if !Experiments.shared.frontDoorEnabled { Divider() }
        Button(CaptureMenuNames.editLastCapture) { coordinator.editLastCapture() }
            .keyboardShortcut("6", modifiers: [.command, .shift])
            .disabled(coordinator.lastCapture == nil)
    }

    // A setting, so one name and a checkmark rather than a title that
    // rewrites itself. The checkmark is also written straight onto the
    // live item whenever history opens or closes (MainMenuState):
    // SwiftUI re-runs this body only while handling an event, and ⇧⌘H
    // rebuilds it from the state before the toggle ran, which left the
    // menu a step behind.
    @ViewBuilder private var historyToggle: some View {
        Toggle(CaptureMenuNames.history, isOn: Binding(
            get: { coordinator.isHistoryShown },
            set: { _ in coordinator.toggleHistory() }))
        .keyboardShortcut("h", modifiers: [.command, .shift])
    }

    @ViewBuilder private var screenRecordingAccessRow: some View {
        Button("Request Screen Recording Access…") {
            coordinator.capture.requestScreenRecordingAccess()
        }
        .help("Registers Photonz in System Settings → Privacy → Screen & System Audio Recording and opens that pane.")
    }

    /// The top-level Capture menu, before the pro menu bar. With it, the same
    /// rows are File ▸ Capture and Window ▸ Show History.
    @CommandsBuilder private var captureMenu: some Commands {
        CommandMenu(CaptureMenuNames.menuTitle) {
            captureRows
            historyToggle
            Divider()
            screenRecordingAccessRow
        }
    }

    /// File ▸ Capture, where Preview keeps Take Screenshot: the capture
    /// commands under their own names and keys, one level down.
    ///
    /// With File reading like every Mac app's (`next-front-door`) the rows
    /// are a section of File itself, under Open, where the user asked for
    /// them ("capture can be a secondary section", 2026-10-22).
    @ViewBuilder private var fileCaptureSubmenu: some View {
        if Experiments.shared.frontDoorEnabled {
            Divider()
            captureRows
            screenRecordingAccessRow
        } else if Experiments.shared.proMenuBarEnabled {
            Divider()
            Menu(CaptureMenuNames.menuTitle) {
                captureRows
                Divider()
                screenRecordingAccessRow
            }
        }
    }

    // MARK: Image

    @CommandsBuilder private var imageMenu: some Commands {
        CommandMenu("Image") {
            Button("Resize Image…") { editor?.run(.resizeImage) }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(editor?.document == nil)
            Button("Canvas Size…") { editor?.run(.canvasSize) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor?.document == nil)
        }
    }

    // MARK: Playing the time

    @ViewBuilder private var transportRows: some View {
        Button((editor?.isDocumentPlaying ?? false) ? "Pause" : "Play") {
            editor?.run(.playPause)
        }
        .keyboardShortcut(.space, modifiers: [])
        Button("Play In to Out") { editor?.run(.playInToOut) }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            .disabled(!(editor?.canRun(.playInToOut) ?? false))
        Button("Play Backward") { editor?.run(.playBackward) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("j", modifiers: []) : nil)
        Button("Stop") { editor?.run(.stop) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("k", modifiers: []) : nil)
            .disabled(!(editor?.canRun(.stop) ?? false))
        Button("Play Forward") { editor?.run(.playForward) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("l", modifiers: []) : nil)
    }

    @ViewBuilder private var editPointRows: some View {
        Button("Go to Previous Edit") { editor?.run(.goToPreviousEdit) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut(.upArrow, modifiers: []) : nil)
            .disabled(!(editor?.canRun(.goToPreviousEdit) ?? false))
        Button("Go to Next Edit") { editor?.run(.goToNextEdit) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut(.downArrow, modifiers: []) : nil)
            .disabled(!(editor?.canRun(.goToNextEdit) ?? false))
    }

    // MARK: Cutting

    // One key, one meaning, two places it can land. A recording
    // that opens as a DOCUMENT is cut on the timeline
    // (`EditorState+ClipBar`); the old recording window is still
    // cut on its strip until it retires. Nothing here is a second
    // way to do the same thing: they are the same command reaching
    // whichever surface is in front of you.
    @ViewBuilder private var splitAndDeleteRows: some View {
        let onTimeline = timed
        // Premiere's Add Edit, ⌘K, on the timeline, where B picks up
        // the Blade; the recording window keeps its B.
        Button("Split at Playhead") {
            if onTimeline { editor?.run(.splitAtPlayhead) } else { video?.cutAtPlayhead() }
        }
        .keyboardShortcut(onTimeline ? KeyboardShortcut("k", modifiers: .command)
                                     : KeyboardShortcut("b", modifiers: []))
        .disabled(!(onTimeline ? (editor?.canRun(.splitAtPlayhead) ?? false)
                               : (video?.canCutAtPlayhead ?? false)))
        // What ⌫ takes, in the order it looks: keys (or points on a sound's
        // line) picked on a lane, a transition picked on a cut, a clip's
        // part of a range, a range on the ruler, a range on some tracks or
        // pieces a box picked, a gap a click picked, else the piece in hand
        // (`EditorState.deleteInHand`, the one rule the agent's `delete`
        // runs too).
        let inHand = onTimeline ? editor?.deleteInHand : nil
        Button(inHand == .points ? "Delete Points" : inHand == .keys ? "Delete Keys"
               : inHand == .transition ? "Delete Transition" : inHand == .section ? "Delete Section"
               : inHand == .range || inHand == .trackRange ? "Delete Range"
               : inHand == .pieces ? "Delete Pieces" : inHand == .gap ? "Delete Gap" : "Delete This Piece") {
            if onTimeline { editor?.run(.delete) } else { video?.deleteSelectedPiece() }
        }
        // A MENU ROW carries U+0008 for ⌫, which is not the U+007F
        // the key sends: AppKit normalises the press to backspace
        // before it looks along the menu bar, so a row holding U+007F
        // prints ⌫ beside its name and the key never reaches it. This
        // row held U+007F and the walk that presses ⌫ for it failed
        // for five days. See `DeleteKeyCharacters.menuKeyEquivalent`
        // for the measurement, including the half that says a text
        // field with the keyboard still keeps the key.
        .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuKeyEquivalent), modifiers: [])
        .disabled(!(onTimeline ? (editor?.canRun(.delete) ?? false) : (video?.canDeleteSelectedPiece ?? false)))
    }

    // Premiere's Ripple Delete, on its Mac key: what is picked goes
    // and everything after it pulls back to close the gap, so a
    // title stays over the frame it was put on
    // (`EditorState+TimelineMenus`).
    //
    // On the pro menu bar it prints ⇧⌫, the key the timeline answers for it,
    // and only while the timeline has the keyboard: ⌥⌫ is Photoshop's Fill
    // with Foreground in Edit, and one key on two rows lies on one of them.
    @ViewBuilder private var rippleDeleteRow: some View {
        let pro = Experiments.shared.proMenuBarEnabled
        Button(editor?.sectionTakesTheDelete == true ? "Ripple Delete Section" : "Ripple Delete") {
            editor?.run(.rippleDelete)
        }
            .keyboardShortcut(pro
                ? (timelineKeys ? KeyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuKeyEquivalent),
                                                   modifiers: .shift) : nil)
                : KeyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuKeyEquivalent), modifiers: .option))
            .disabled(!(editor?.canRun(.rippleDelete) ?? false))
    }

    // Premiere's Add Edit to All Tracks.
    @ViewBuilder private var splitEverythingRow: some View {
        Button("Split Everything at Playhead") {
            editor?.run(.splitEverythingAtPlayhead)
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
        .disabled(!(editor?.canRun(.splitEverythingAtPlayhead) ?? false))
    }

    // Premiere's Q and W. Plain letters, like I and O: the
    // timeline answers them while it has the keyboard, and on
    // the canvas W is still the Magic Wand.
    @ViewBuilder private var rippleTrimRows: some View {
        Button("Ripple Trim Start to Playhead") { editor?.run(.rippleTrimStart) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("q", modifiers: []) : nil)
            .disabled(!(editor?.canRun(.rippleTrimStart) ?? false))
        Button("Ripple Trim End to Playhead") { editor?.run(.rippleTrimEnd) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("w", modifiers: []) : nil)
            .disabled(!(editor?.canRun(.rippleTrimEnd) ?? false))
    }

    // Final Cut's ⌘T: the default transition on the cut
    // picked, else the cut at the playhead. Premiere's ⌘D is
    // Photoshop's Deselect here, and the canvas keeps it.
    @ViewBuilder private var applyDefaultTransitionRow: some View {
        if Experiments.shared.transitionsAtACutEnabled {
            Button("Apply Default Transition") { editor?.run(.applyDefaultTransition) }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!(editor?.canRun(.applyDefaultTransition) ?? false))
        }
    }

    // The mock's Edit point group (`video-transition-wt.html`, `#cmdMenu`):
    // Expand the cut, ⌥E. A view of the cut in hand, so it keeps its name
    // and wears a tick while that cut is open.
    @ViewBuilder private var expandCutRow: some View {
        if Experiments.shared.transitionsAtACutEnabled {
            Toggle(TimelineMenuTable.title(.expandCut, playheadMS: 0) ?? "", isOn: Binding(
                get: { editor?.isCutInHandExpanded ?? false },
                set: { _ in editor?.run(.expandCut) }))
                .keyboardShortcut("e", modifiers: .option)
                .disabled(!(editor?.canRun(.expandCut) ?? false))
        }
    }

    // Premiere's Sequence > Snap in Timeline, on its S. A
    // setting, so it keeps its name and wears a checkmark; the
    // magnet in the timeline's bar is the same switch.
    @ViewBuilder private var snapRow: some View {
        Toggle(MenuToggleNames.snapInTimeline, isOn: Binding(
            get: { editor?.isTimelineSnapping ?? true },
            set: { _ in editor?.run(.snapInTimeline) }))
        .keyboardShortcut(timelineKeys ? KeyboardShortcut("s", modifiers: []) : nil)
    }

    // Premiere's Nudge Clip Selection Left and Right, on its Mac keys: the
    // picked clips a frame earlier or later, five with ⇧ held
    // (`EditorState+ClipNudge`). Printed only while the timeline has the
    // keyboard, where the keys mean it. A field being typed in (a clip or
    // track being renamed in the dock) keeps ⌘← and ⌘→ for its caret, the
    // way Cut, Copy and Paste act on a field that has the keyboard.
    @ViewBuilder private var nudgeClipRows: some View {
        Button("Nudge Earlier") {
            if let fieldEditor {
                fieldEditor.doCommand(by: #selector(NSStandardKeyBindingResponding.moveToLeftEndOfLine(_:)))
            } else {
                editor?.run(.nudgeEarlier)
            }
        }
        .keyboardShortcut(timelineKeys ? KeyboardShortcut(.leftArrow, modifiers: .command) : nil)
        .disabled(!(editor?.canRun(.nudgeEarlier) ?? false))
        Button("Nudge Later") {
            if let fieldEditor {
                fieldEditor.doCommand(by: #selector(NSStandardKeyBindingResponding.moveToRightEndOfLine(_:)))
            } else {
                editor?.run(.nudgeLater)
            }
        }
        .keyboardShortcut(timelineKeys ? KeyboardShortcut(.rightArrow, modifiers: .command) : nil)
        .disabled(!(editor?.canRun(.nudgeLater) ?? false))
    }

    // Final Cut's Break Apart Clip Items, on its key, which is Photoshop's
    // Ungroup too: the one key that takes a thing made of things apart. The
    // row holds it only while a merged clip is in hand, and Layer ▸ Ungroup
    // holds it the rest of the time, so the two never print the same key.
    @ViewBuilder private var breakApartRow: some View {
        let breaks = editor?.canBreakApartInHand ?? false
        Button("Break Apart") { editor?.run(.breakApart) }
            .keyboardShortcut(breaks ? KeyboardShortcut("g", modifiers: [.command, .shift]) : nil)
            .disabled(!breaks)
    }

    // A freeze is not a special object: it is a piece whose in and
    // out are the same frame, so it drops onto the timeline like
    // any other piece and can be moved, lengthened and thrown away
    // like any other piece (`video-freeze-wt`).
    // Freeze Frame… asks how long in a popover on the clip
    // (`EditorState+FreezeAsk`). ⇧⌥F: Premiere gives frame holds no
    // key, ⇧F walks the Frame slot and ⌥F fills the flow.
    // Retiming is a property of the piece you are on, so it is a
    // list of speeds rather than a surface of its own
    // (`video-speed`). Its sound goes with it, at the same rate.
    // Premiere's ⌘R, Speed/Duration, opens that list in the panel's Time
    // section; a submenu's own title cannot carry a key, so the key is on a
    // row of its own above the list (`EditorState+SpeedKey`). Photoshop's ⌘R
    // is Rulers, which this app does not have.
    @ViewBuilder private var freezeAndSpeedRows: some View {
        Button("Freeze Frame\u{2026}") { editor?.run(.freezeFrame) }
            .keyboardShortcut("f", modifiers: [.option, .shift])
            .disabled(!(editor?.canHoldFrameAtPlayhead ?? false))
        // A stretch whose picture a range took off (Hide Picture for Section).
        Button("Show Picture") {
            editor?.run(.showPicture)
        }
        .disabled(!(editor?.canRun(.showPicture) ?? false))
        Button("Change Speed\u{2026}") { editor?.openClipSpeed() }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!(editor?.canOpenClipSpeed ?? false))
        Menu("Speed") {
            ForEach(EditorState.clipSpeeds, id: \.self) { percent in
                Button(ClipSpeed.title(percent)) {
                    editor?.run(.setSpeed, ["percent": .number(Double(percent))])
                }
                .disabled(!(editor?.canRun(.setSpeed, ["percent": .number(Double(percent))]) ?? false))
            }
            // Speed stops (`EditorState+SpeedStops`): no key, since the
            // mock's A is Premiere's Track Select Forward (UX-PATTERNS §7).
            Divider()
            Button(SpeedStopNames.add) { editor?.run(.addSpeedStop) }
                .disabled(!(editor?.canRun(.addSpeedStop) ?? false))
            Button(SpeedStopNames.delete) { editor?.run(.deleteSpeedStop) }
                .disabled(!(editor?.canRun(.deleteSpeedStop) ?? false))
            Button(SpeedStopNames.reset) { editor?.run(.resetRamp) }
                .disabled(!(editor?.canRun(.resetRamp) ?? false))
        }
        .disabled(editor?.clipSpeedInHand == nil)
    }

    // MARK: Keys

    // The playhead from key to key, on the pair of keys the user
    // asked for. K alone is still the Lens and, once the timeline
    // owns the keyboard, Premiere's Stop; the chords are free of it.
    @ViewBuilder private var keyNavigationRows: some View {
        Button("Go to Next Key") { editor?.run(.goToNextKey) }
            .keyboardShortcut("k", modifiers: .shift)
            .disabled(!(editor?.canRun(.goToNextKey) ?? false))
        Button("Go to Previous Key") { editor?.run(.goToPreviousKey) }
            .keyboardShortcut("k", modifiers: .option)
            .disabled(!(editor?.canRun(.goToPreviousKey) ?? false))
    }

    // The mock's Animate commands (`video-move-wt.html`,
    // `#cmdMenu`). No K for Key at Playhead: K is the Lens on the
    // canvas and Premiere's Stop on the timeline.
    @ViewBuilder private var animateRows: some View {
        Button("Key at Playhead") { editor?.run(.keyAtPlayhead) }
            .disabled(!(editor?.canRun(.keyAtPlayhead) ?? false))
        Toggle(MenuToggleNames.curveThePath, isOn: Binding(
            get: { editor?.motionPathShape == .curved },
            set: { _ in editor?.run(.curveThePath) }))
            .disabled(!(editor?.canRun(.curveThePath) ?? false))
        // The same list as Between the keys' Curve, acting on the
        // stretch under the playhead.
        Menu("Easing") {
            ForEach(Array(EasingCurve.named.enumerated()), id: \.offset) { _, curve in
                Toggle(curve.title, isOn: Binding(
                    get: { editor?.betweenKeysCurve == curve },
                    set: { if $0 { editor?.run(.setEasing, ["curve": .string(curve.title)]) } }))
            }
        }
        .disabled(editor?.betweenKeysCurve == nil)
        // The segments picked on a graph (`EditorState+KeyGraph`), the same
        // rows as a segment's right click.
        Button("Draw a Curve\u{2026}") { editor?.drawCurveForPickedSegments() }
            .disabled(!(editor?.hasPickedSegments ?? false))
        Button("Copy Ease") { editor?.copyPickedSegmentsEase() }
            .disabled(editor?.pickedSegmentsCurveInHand == nil)
        Button("Paste Ease") { editor?.pastePickedSegmentsEase() }
            .disabled(!(editor?.hasPickedSegments ?? false) || editor?.copiedStretchCurve == nil)
    }

    // MARK: Marks

    // The ruler's marks, at the playhead. The same rows the ruler's
    // right click offers there; M, I and O are Photoshop's tool keys
    // on the canvas and the timeline's marks while it has the keyboard,
    // and X, the canvas's fill swap, is Premiere's Mark Clip there.
    @ViewBuilder private var markRows: some View {
        Button("Add Marker") { editor?.run(.addMarker) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("m", modifiers: []) : nil)
        Button("Set In") { editor?.run(.setIn) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("i", modifiers: []) : nil)
        Button("Set Out") { editor?.run(.setOut) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("o", modifiers: []) : nil)
        Button("Mark Clip") { editor?.run(.markClip) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("x", modifiers: []) : nil)
            .disabled(!(editor?.canRun(.markClip) ?? false))
        Button("Go to In") { editor?.run(.goToIn) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("i", modifiers: .shift) : nil)
            .disabled(!(editor?.canRun(.goToIn) ?? false))
        Button("Go to Out") { editor?.run(.goToOut) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("o", modifiers: .shift) : nil)
            .disabled(!(editor?.canRun(.goToOut) ?? false))
        Button("Clear In") { editor?.run(.clearIn) }
            .keyboardShortcut("i", modifiers: .option)
            .disabled(!(editor?.canRun(.clearIn) ?? false))
        Button("Clear Out") { editor?.run(.clearOut) }
            .keyboardShortcut("o", modifiers: .option)
            .disabled(!(editor?.canRun(.clearOut) ?? false))
        Button("Clear In and Out") { editor?.run(.clearInAndOut) }
            .keyboardShortcut("x", modifiers: .option)
            .disabled(!(editor?.canRun(.clearInAndOut) ?? false))
    }

    // Premiere's Extract and Lift. Plain keys, like I and O: the
    // timeline answers them while it has the keyboard.
    @ViewBuilder private var extractLiftRows: some View {
        Button("Extract") { editor?.run(.extract) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("'", modifiers: []) : nil)
            .disabled(!(editor?.canRun(.extract) ?? false))
        Button("Lift") { editor?.run(.lift) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut(";", modifiers: []) : nil)
            .disabled(!(editor?.canRun(.lift) ?? false))
    }

    // MARK: Reframing

    // Where the camera is pointed, and where it goes next
    // (`ClipReframe.swift`). Both rows act on the clip in hand at the
    // playhead, so a punch-in costs no aiming beyond the box you drew
    // on the picture. ⇧Z is the clickthrough's own key, and the only thing
    // ⇧Z means: the timeline fits itself on Premiere's \ instead.
    @ViewBuilder private var punchInRows: some View {
        Button("Punch In") { editor?.run(.punchIn) }
            .keyboardShortcut("z", modifiers: [.shift])
            .disabled(!(editor?.canRun(.punchIn) ?? false))
        Button("Pull Back Out") { editor?.run(.pullBackOut) }
            .keyboardShortcut("z", modifiers: [.shift, .option])
            .disabled(!(editor?.canRun(.pullBackOut) ?? false))
        Button("Reset Reframe") { editor?.run(.resetReframe) }
            .disabled(!(editor?.canRun(.resetReframe) ?? false))
    }

    // MARK: Transitions

    // What happens at a CUT (`docs/design/video-transitions.md`). The
    // menu acts on the cut in hand — the one picked, else the one the
    // playhead is standing on — so putting a dissolve on the join you
    // are looking at costs no aiming. Every one of these is also a
    // click on the band in the timeline; this is the way in that can be
    // found by reading.
    @ViewBuilder private var transitionAtCutMenu: some View {
        Menu("Transition at Cut") {
            Button("Hard Cut") { editor?.run(.hardCut) }
                .disabled(!(editor?.canRun(.hardCut) ?? false))
            // The panel menu's third row (`#propMenu`).
            Button("Reset to Default Length") { editor?.run(.resetTransitionLength) }
                .disabled(!(editor?.canRun(.resetTransitionLength) ?? false))
            // The cut's right-click offers these too, for the transition on it.
            let transition = editor?.cutInHand?.cut.drawnTransition
            Menu("Length") {
                ForEach(editor?.clipTransitionLengthOffers ?? [], id: \.self) { ms in
                    Toggle(ClipTransitionCopy.lengthChoice(ms, of: transition?.kind ?? .dissolve),
                           isOn: Binding(get: { transition?.lengthMS == ms },
                                         set: { _ in editor?.run(.setTransitionLength, ["milliseconds": .number(Double(ms))]) }))
                }
            }
            .disabled(transition == nil)
            Menu("Curve") {
                ForEach(Array(EasingCurve.named.prefix(EasingCurve.standardCount)), id: \.self) { curve in
                    Toggle(curve.title, isOn: Binding(get: { transition?.curve == curve },
                                                      set: { _ in editor?.run(.setTransitionCurve, ["curve": .string(curve.title)]) }))
                }
            }
            .disabled(transition == nil)
            Divider()
            ForEach(ClipTransitionKind.allCases, id: \.self) { kind in
                Button(kind.title) { editor?.run(.setTransition, ["kind": .string(kind.rawValue)]) }
                    .disabled(!(editor?.canRun(.setTransition, ["kind": .string(kind.rawValue)]) ?? false))
            }
            // The Transitions section's plus: the transition in hand (the
            // cut's, else the tile picked there) on every cut, or as ⌘T's.
            if Experiments.shared.proMenuBarEnabled, let kind = editor?.transitionKindInHand {
                Divider()
                Button("Apply to Every Cut") { editor?.run(.applyTransitionToEveryCut) }
                    .help("\(kind.title) on every cut")
                Button("Set as Default Transition") { editor?.run(.setDefaultTransition) }
                    .help("\(kind.title) on Command T")
                    .disabled(!(editor?.canRun(.setDefaultTransition) ?? false))
            }
        }
        .disabled(!(editor?.canWorkWithClipTransitions ?? false)
                  || (editor?.cutInHand == nil && !Experiments.shared.proMenuBarEnabled))
    }

    // MARK: Sound

    // Sound rides the same time axis as the picture, so there is no
    // mixer window and no audio mode: everything a piece of sound needs —
    // cut it, move it, name it, switch it off, undo any of it — is what the
    // timeline already does to a layer (`docs/design/video-audio.md`).
    // ⌃⇧D, the key the cut clickthrough's command menu prints for
    // it (`video-cut-wt`): two modifiers away from ⌘D, so not a key
    // anybody presses by accident on a take they have already cut.
    // Once the sound is a layer of its own the same row, on the same key,
    // reads Re-attach Audio and puts it back: one row that toggles, the way
    // Premiere's Link and Unlink are one row on ⌘L.
    @ViewBuilder private var detachAudioRow: some View {
        if editor?.canReattachSound == true {
            Button("Re-attach Audio") { editor?.run(.reattachAudio) }
                .keyboardShortcut("d", modifiers: [.control, .shift])
        } else {
            Button("Detach Audio") { editor?.run(.detachAudio) }
                .keyboardShortcut("d", modifiers: [.control, .shift])
                .disabled(!(editor?.canRun(.detachAudio) ?? false))
        }
    }

    /// A video or a sound, onto the timeline at the playhead: the menu's
    /// way in for a second clip, where Import Media only fills the Library.
    @ViewBuilder private var addMediaRow: some View {
        Button("Add Media at Playhead…") { editor?.run(.addMediaAtPlayhead) }
            .disabled(!(editor?.documentHasTime ?? false))
    }

    @ViewBuilder private var flattenLevelRow: some View {
        Button("Flatten Level") { editor?.run(.flattenLevel) }
            .disabled(!(editor?.canRun(.flattenLevel) ?? false))
    }

    /// Insert Title Page ▸ and Insert Name Card ▸, each listing its presets,
    /// the person's own first (`EditorState+TitlePresets`). Dimmed where the
    /// document has no time to put one in.
    @ViewBuilder private var insertTitleRows: some View {
        ForEach(TitleKind.offered(charts: Experiments.shared.animatedChartsEnabled)) { kind in
            Menu("Insert \(kind.name)") {
                if let editor { MenuRowsView(rows: editor.titlePresetRows(kind)) }
            }
            .disabled(!(editor?.canInsertTitle ?? false))
        }
    }

    /// Save as Preset…: the picked title page or name card, kept as your own.
    @ViewBuilder private var saveTitlePresetRow: some View {
        // Replay Title: the picked title's in, played again.
        if Experiments.shared.titleRestyleEnabled {
            Button("Replay Title") { editor?.run(.replayTitle) }
                .disabled(!(editor?.canRun(.replayTitle) ?? false))
        }
        Button("Save as Preset…") { editor?.run(.saveTitlePreset) }
            .disabled(editor?.titlePresetLayerInHand == nil)
    }

    @ViewBuilder private var exportSoundRow: some View {
        Button("Export Sound…") { editor?.run(.exportSound) }
            .disabled(!(editor?.documentHasAudio ?? false))
    }

    // MARK: Captions

    // Captions are what the Title / Text tool does when the document
    // has time, so they live beside the sound they are written
    // from rather than in a caption menu
    // (`docs/design/mocks/pages/video-captions.html`).
    @ViewBuilder private var captionRows: some View {
        // Premiere's Transcribe: captions are made only when asked.
        if editor?.isWritingCaptions == true {
            Button("Cancel Captions") { editor?.run(.cancelCaptions) }
        } else {
            Button(editor?.hasCaptions == true ? "Rewrite Captions" : "Add Captions") {
                editor?.run(.addCaptions)
            }
            .disabled(!(editor?.canRun(.addCaptions) ?? false))
        }
        Button("Captions Later") {
            editor?.run(.captionsLater)
        }
        .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
        .disabled(!(editor?.canRun(.captionsLater) ?? false))
        Button("Captions Earlier") {
            editor?.run(.captionsEarlier)
        }
        .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
        .disabled(!(editor?.canRun(.captionsEarlier) ?? false))
        Button("Clear Captions") { editor?.run(.clearCaptions) }
            .disabled(!(editor?.canRun(.clearCaptions) ?? false))
        Button("Export Captions as SRT…") { editor?.run(.exportCaptions, ["format": "srt"]) }
            .disabled(!(editor?.canExportCaptions ?? false))
        Button("Export Captions as WebVTT…") { editor?.run(.exportCaptions, ["format": "vtt"]) }
            .disabled(!(editor?.canExportCaptions ?? false))
    }

    // A recording opened in the editor: every edit thrown away, back
    // to the recording as it opened, in one undo step
    // (`EditorState+RevertRecording`).
    @ViewBuilder private var revertRecordingRow: some View {
        Button("Revert to Original") { editor?.run(.revertToOriginal) }
            .disabled(!(editor?.canRun(.revertToOriginal) ?? false))
    }

    // MARK: Every command, in the menu bar too

    // What a right-click or the panel does, as a row that acts on the thing in
    // hand (`EditorState+MenuBar`): the placement contract's menu bar row says a
    // command reachable only from a bar or a right-click is a bug, and
    // `EveryCommandIsInTheMenuBarTests` reads both sides and fails on one.

    /// Edit ▸ Tools: every tool on the bar, the one in hand ticked, each letter
    /// printed on the row a press of it would pick now (`ToolMenu`). A letter
    /// the timeline takes while it has the keyboard is not promised then, the
    /// same rule the bar's tooltips keep.
    @ViewBuilder private var toolsMenu: some View {
        let tools = menuTools
        Menu("Tools") {
            ForEach(tools, id: \.self) { tool in
                let key = editor.flatMap { editor in
                    ToolMenu.printedKey(for: tool, among: tools, active: editor.activeTool,
                                        remembered: { editor.lastTool(in: $0) })
                }
                Toggle(tool.barTitle(onVideoBar: editor?.hasVideoToolBar ?? false), isOn: Binding(
                    get: { editor?.activeTool == tool && !(editor?.isTimelineBlade ?? false) },
                    set: { _ in pickTool(tool, key: key, among: tools) }))
                .keyboardShortcut(key.flatMap { key in
                    !timelineKeys || TimelineKeys.leavesToTheCanvas(key)
                        ? KeyboardShortcut(KeyEquivalent(key), modifiers: []) : nil
                })
            }
            // The timeline's Blade, on a video, where the bar shows it too.
            if editor?.hasVideoToolBar ?? false {
                Divider()
                Toggle("Blade", isOn: Binding(
                    get: { editor?.isTimelineBlade ?? false },
                    set: { _ in
                        editor?.setTool(.select)
                        editor?.perform(timelineCommand: .bladeTool)
                    }))
                .keyboardShortcut("b", modifiers: [])
            }
        }
        .disabled(editor?.document == nil)
    }

    /// The tools the bar offers in this window, in its order.
    private var menuTools: [Tool] {
        let layout = Experiments.shared.toolBarLayout(inTime: editor?.documentHasTime ?? false)
        let bounds = ToolGroup.bounds.tools.filter { editor?.boundsToolsOffered.contains($0) ?? ($0 == .crop) }
        return ToolMenu.tools(layout, bounds: bounds)
    }

    /// A tool row, picked or pressed: what its letter hands you, read live, so
    /// a click and a key can never pick two different tools.
    private func pickTool(_ tool: Tool, key: Character?, among tools: [Tool]) {
        guard let editor else { return }
        let picked = key.flatMap {
            ToolMenu.tool(forKey: $0, among: tools, active: editor.activeTool,
                          remembered: { editor.lastTool(in: $0) })
        } ?? tool
        editor.setTool(picked)
        if editor.isTimelineBlade { editor.isTimelineBlade = false }
    }

    // Layer: the verbs the layers list's right-click has.
    @ViewBuilder private var layerListRows: some View {
        let selected = editor?.selectedLayerID
        Button("Rename Layer…") { editor?.run(.renameLayer) }
            .disabled(selected == nil)
        // The Layers list's lock, here too (Photoshop's Layer ▸ Lock Layers).
        Toggle(MenuToggleNames.layerLocked, isOn: Binding(
            get: { editor?.isOn(.lockLayer) ?? false },
            set: { _ in editor?.run(.lockLayer) }))
            .disabled(selected == nil)
        Button("Select Pixels") { editor?.run(.selectPixels) }
            .disabled(!(editor?.canRun(.selectPixels) ?? false))
        if timed {
            Button("Put on Timeline") { editor?.run(.putOnTimeline) }
                .disabled(!(editor?.canRun(.putOnTimeline) ?? false))
        }
    }

    // Layer: the Effects list's plus and its rows' x.
    @ViewBuilder private var effectRows: some View {
        let canRestyle = editor?.hasRestylableSelection ?? false
        Menu("Add Effect") {
            ForEach(editor?.addableEffects ?? AddableEffect.allCases) { kind in
                Button(kind.title) { editor?.run(.addEffect, ["kind": .string(kind.rawValue)]) }
                    .disabled(!(editor?.canAddEffect(kind) ?? false))
            }
            let saved = editor?.namedEffectStyles ?? []
            if !saved.isEmpty {
                Section("Saved effects") {
                    ForEach(saved) { style in
                        Button(style.name) { editor?.run(.addSavedEffect, ["style": .string(style.name)]) }
                    }
                }
            }
        }
        .disabled(!canRestyle)
        let effects = canRestyle ? (editor?.layerEffectRows ?? []) : []
        Menu("Remove Effect") {
            ForEach(effects) { row in
                Button(row.title) { editor?.run(.removeEffect, ["index": .number(Double(row.index))]) }
            }
        }
        .disabled(effects.isEmpty)
    }

    // Clip: the clip's own right-click verbs that were nowhere else.
    @ViewBuilder private var clipItselfRows: some View {
        let clip = editor?.clipInHandID
        Button("Rename…") { editor?.run(.renameClip) }
            .disabled(clip == nil)
        Button("Select Forward") { editor?.run(.selectForward) }
            .disabled(clip == nil)
        let clickClip = editor?.clipToAddClickTo
        Button("Add Click at Playhead\u{2026}") { editor?.run(.addClick) }
        .disabled(clickClip == nil)
        if Experiments.shared.clickEffectsEnabled {
            // The Clicks switch on the clip's Properties (`ClickEffectRows`).
            let effectClip = editor?.clickEffectClip?.id
            Toggle("Show Click Effects", isOn: Binding(
                get: { effectClip.map { editor?.clickEffect(ofClip: $0).isOn ?? false } ?? false },
                set: { on in editor?.run(AppCommandCall(.showClickEffects, on: on)) }))
                .disabled(!(editor?.canRun(.showClickEffects) ?? false))
            // A tick's own verbs (`ClickTicksView`), for the click at the playhead.
            let clickNow = editor?.clickAtPlayhead
            Button(clickNow?.mark.isHidden == true ? "Show Click at Playhead" : "Hide Click at Playhead") {
                // Asked again here: the row was drawn at the last boundary the
                // playhead crossed, and the press is now.
                editor?.run(.hideClickAtPlayhead)
            }
            .disabled(!(editor?.canRun(.hideClickAtPlayhead) ?? false))
            Button("Next Click") { editor?.run(.nextClick) }
                .disabled(!(editor?.canRun(.nextClick) ?? false))
        }
        if Experiments.shared.zoomRegionsEnabled {
            Button("Add Zoom") {
                editor?.run(.addZoom)
            }
            .disabled(!(editor?.canRun(.addZoom) ?? false))
            Button("Suggest Zooms") { editor?.run(.suggestZooms) }
                .disabled(!(editor?.canRun(.suggestZooms) ?? false))
            // The picked zooms' own verbs, as their bars' right-click has
            // them: every zoom picked at once.
            let zoomRefs = editor?.pickedZooms ?? []
            let allFollow = editor.map { !zoomRefs.isEmpty && $0.pickedZoomsReading.followsCursor == true } ?? false
            Toggle("Follow Cursor", isOn: Binding(
                get: { allFollow },
                set: { on in editor?.run(AppCommandCall(.followCursor, on: on)) }))
                .disabled(zoomRefs.isEmpty || !(editor?.canFollowCursor(zoomRefs) ?? false))
            Menu("Zoom") {
                ForEach(EditorState.zoomScaleStops, id: \.self) { stop in
                    Button("\(stop)%") { editor?.run(.setZoomAmount, ["percent": .number(Double(stop))]) }
                }
            }
            .disabled(zoomRefs.isEmpty)
            Button("Delete Zoom") { editor?.run(.deleteZoom) }
                .disabled(zoomRefs.isEmpty)
        }
        let media = editor?.mediaURLInHand
        Button("Reveal in Finder") { if let media { NSWorkspace.shared.activateFileViewerSelecting([media]) } }
            .disabled(media == nil)
    }

    // Clip: a cut's Roll Edit and Join Through Edit, beside the transition rows.
    @ViewBuilder private var rollEditRow: some View {
        Button("Roll Edit to Playhead") { editor?.run(.rollEditToPlayhead) }
            .disabled(!(editor?.canRun(.rollEditToPlayhead) ?? false))
        Button("Join Through Edit") { editor?.run(.joinThroughEdit) }
            .disabled(!(editor?.canRun(.joinThroughEdit) ?? false))
    }

    // Clip: the sound's gain, as its right-click and the Sound section have it.
    @ViewBuilder private var soundCleanupRows: some View {
        let sound = editor?.soundLayerInHand
        let ids = sound.map { editor?.soundLayers(actingOn: $0.id) ?? [] } ?? []
        Menu("Normalize") {
            Button("Peaks to -1 dB") {
                editor?.run(.normalizePeaks)
            }
            Divider()
            ForEach(AudioNormalize.Target.allCases, id: \.self) { target in
                Button(target.title) {
                    editor?.run(.normalizeLoudness, ["target": .string(target.rawValue)])
                }
            }
            Divider()
            Toggle("Clean Noise", isOn: Binding(
                get: { editor?.normalizeCleansNoise ?? false },
                set: { _ in editor?.run(.normalizeCleansNoise) }))
        }
        .disabled(ids.isEmpty)
        let cleaned = ids.contains {
            editor?.document?.layer(id: $0)?.soundLevel?.noiseReduction != nil
                || editor?.document?.layer(id: $0)?.hasSectionNoiseCleaning == true
        }
        Button(cleaned ? "Remove Noise Cleaning" : "Clean Noise") {
            editor?.run(.cleanNoise)
        }
        .disabled(ids.isEmpty)
        Button("Reset Gain") {
            editor?.run(.resetGain)
        }
        .disabled(!(editor?.canRun(.resetGain) ?? false))
    }

    // Clip: Fade In ▸ and Fade Out ▸, on the picked clip, title or shape, the
    // rows its right-click has. The one-second row of each carries its key.
    @ViewBuilder private var pictureFadeRows: some View {
        let layer = editor?.pictureFadeLayerInHand
        // Both ends in one step, on every pick, at the lengths the last of
        // its kind faded at.
        let both = Toggle("Fade In and Out", isOn: Binding(
            get: { editor.map { $0.fadesInAndOut($0.pictureFadeTargetsInHand) } ?? false },
            set: { _ in editor?.run(.fadeInAndOut) }))
        both.keyboardShortcut(EditorState.fadeInAndOutKey.keyEquivalent,
                              modifiers: EditorState.fadeInAndOutKey.modifiers)
            .disabled(!(editor?.canRun(.fadeInAndOut) ?? false))
        ForEach(FadeEnd.allCases, id: \.self) { end in
            let now = layer?.pictureFadeMS(end) ?? 0
            let stops = layer.map { editor?.pictureFadeStops(end, layer: $0) ?? [] } ?? PictureFade.stopsMS
            Menu(end.title) {
                ForEach(stops, id: \.self) { ms in
                    let row = Toggle(PictureFade.title(ms), isOn: Binding(
                        get: { now == ms },
                        set: { _ in editor?.run(.setFade, ["end": .string(end.rawValue), "milliseconds": .number(Double(ms))]) }))
                    if ms == EditorState.pictureFadeKeyMS {
                        let key = EditorState.pictureFadeKey(end)
                        row.keyboardShortcut(key.keyEquivalent, modifiers: key.modifiers)
                    } else {
                        row
                    }
                }
            }
            .disabled(layer == nil)
        }
    }

    // Clip ▸ Animate: a title's time, and the keys and path of the picked layer.
    @ViewBuilder private var placedLayerRows: some View {
        let placed = editor?.placedLayerInHand
        Button("Start at Playhead") { editor?.run(.startAtPlayhead) }
            .disabled(!(editor?.canRun(.startAtPlayhead) ?? false))
        Button("End at Playhead") { editor?.run(.endAtPlayhead) }
            .disabled(!(editor?.canRun(.endAtPlayhead) ?? false))
        // A title fades the way a clip does once picture fades are on: Clip ▸
        // Fade In and Fade Out (`pictureFadeRows`).
        if !Experiments.shared.pictureFadesEnabled {
            Menu("Fade") {
                ForEach(TitleTime.fadeStopsMS, id: \.self) { ms in
                    Toggle(TitleTime.fadeTitle(ms), isOn: Binding(
                        get: { (placed?.titleFadeMS ?? 0) == ms },
                        set: { _ in if let placed { editor?.setPlacedLayerFade(ms, layerID: placed.id) } }))
                }
            }
            .disabled(placed == nil)
        }
        let animates = placed != nil && !(placed.map { editor?.isClipLocked($0.id) ?? true } ?? true)
        Menu("Animate In") {
            ForEach(TitleAnimation.allCases, id: \.self) { kind in
                Button(kind.title) { editor?.run(.animateIn, ["kind": .string(kind.rawValue)]) }
            }
        }
        .disabled(!animates)
        Menu("Animate Out") {
            ForEach(TitleAnimation.allCases, id: \.self) { kind in
                Button(kind.title) { editor?.run(.animateOut, ["kind": .string(kind.rawValue)]) }
            }
        }
        .disabled(!animates)
    }

    @ViewBuilder private var keyLaneRows: some View {
        Button("Remove Key at Playhead") { editor?.run(.removeKeyAtPlayhead) }
            .disabled(!(editor?.canRun(.removeKeyAtPlayhead) ?? false))
        Button("Select All Keys") { editor?.run(.selectAllKeys) }
            .disabled(!(editor?.canRun(.selectAllKeys) ?? false))
        let lane = editor?.keyLaneInHand
        Toggle("Show Graph", isOn: Binding(
            get: { lane.map { editor?.isKeyLaneGraphed($0.motionID) ?? false } ?? false },
            set: { _ in if let lane { editor?.toggleKeyGraph(lane.motionID) } }))
        .disabled(!(editor?.canGraphKeyLaneInHand ?? false))
        let property = editor?.animatingPropertyInHand
        Button("Stop Animating") { editor?.run(.stopAnimating) }
            .disabled(property == nil)
    }

    // The clip's Animate ▸ list, the same one its right click offers: every
    // value of the picked layer not animating yet, under Transform, 3D, Look
    // and Effects (`video-animate.html`).
    @ViewBuilder private var animatePropertyRows: some View {
        if let layer = editor?.keyLayer, let row = editor?.animateMenuRow(layerID: layer.id),
           case .submenu(let inner) = row.kind {
            MenuRowsView(rows: inner)
            Divider()
        }
    }

    @ViewBuilder private var straightenRow: some View {
        Button("Straighten This Stretch") { editor?.run(.straightenStretch) }
            .disabled(editor?.curvedStretchInHand == nil)
    }

    // Sequence: the ruler's marker rows that act on one that is there.
    @ViewBuilder private var markerRows: some View {
        // Premiere's keys. ⇧M is the canvas's selection cycle until the
        // timeline has the keyboard; ⌘⇧M is nothing else's.
        Button("Go to Next Marker") { editor?.run(.goToNextMarker) }
            .keyboardShortcut(timelineKeys ? KeyboardShortcut("m", modifiers: .shift) : nil)
            .disabled(!(editor?.canRun(.goToNextMarker) ?? false))
        Button("Go to Previous Marker") { editor?.run(.goToPreviousMarker) }
            .keyboardShortcut(timed ? KeyboardShortcut("m", modifiers: [.command, .shift]) : nil)
            .disabled(!(editor?.canRun(.goToPreviousMarker) ?? false))
        Button("Remove Marker") { editor?.run(.removeMarker) }
            .disabled(!(editor?.canRun(.removeMarker) ?? false))
        Button("Clear All Markers") { editor?.run(.clearAllMarkers) }
            .disabled(!(editor?.canRun(.clearAllMarkers) ?? false))
    }

    // Sequence: what a range drawn on the ruler or across tracks does.
    @ViewBuilder private var rangeRows: some View {
        Button("Split at Range Edges") {
            editor?.run(.splitAtRangeEdges)
        }
        .disabled(!(editor?.canRun(.splitAtRangeEdges) ?? false))
        Button("Merge into One Clip") { editor?.run(.mergeIntoOneClip) }
            .disabled(!(editor?.canRun(.mergeIntoOneClip) ?? false))
        if Experiments.shared.captionsFromTheSoundEnabled {
            Button("Add Captions for Range") { editor?.run(.addCaptionsForRange) }
                .disabled(!(editor?.canRun(.addCaptionsForRange) ?? false))
        }
        Button("Export Range…") { editor?.exportRange() }
            .disabled(editor?.document?.markedRangeMS == nil)
        // What a range does to the clips picked under it, every row from the
        // one table, lit only where a range and a pick it fits are in hand
        // (`EditorState+RangeSection`).
        Menu("Picked in Range") {
            MenuRowsView(rows: editor?.rangeSectionMenuBarRows() ?? [])
        }
        .disabled(editor?.rangeSection == nil)
    }

    /// Sequence ▸ Track: everything a track's header offers, on the track in
    /// hand (the one picked, else the clip in hand's), and the gutter's + for
    /// a new track of each kind.
    @ViewBuilder private var trackMenu: some View {
        let track = editor?.trackInHand
        Menu("Track") {
            Button("Add Video Track") { editor?.run(.addVideoTrack) }
            Button("Add Audio Track") { editor?.run(.addAudioTrack) }
            Button("Add Captions Track") { editor?.run(.addCaptionsTrack) }
            Divider()
            Button("Add Track Above") { editor?.run(.addTrackAbove) }
                .disabled(track == nil)
            Button("Add Track Below") { editor?.run(.addTrackBelow) }
                .disabled(track == nil)
            Divider()
            Button("Rename Track…") { editor?.run(.renameTrack) }
                .disabled(track == nil)
            if track?.kind == .audio {
                Toggle("Mute Track", isOn: Binding(
                    get: { track?.isMuted ?? false },
                    set: { _ in editor?.run(.muteTrack) }))
            } else {
                Toggle("Hide Track", isOn: Binding(
                    get: { track?.isHidden ?? false },
                    set: { _ in editor?.run(.hideTrack) }))
                .disabled(track == nil)
            }
            Toggle("Solo Track", isOn: Binding(
                get: { track?.isSolo ?? false },
                set: { _ in editor?.run(.soloTrack) }))
            .disabled(track == nil)
            Toggle("Lock Track", isOn: Binding(
                get: { track?.isLocked ?? false },
                set: { _ in editor?.run(.lockTrack) }))
            .disabled(track == nil)
            Divider()
            Button("Group Track") { editor?.run(.groupTrack) }
                .disabled(!(editor?.canRun(.groupTrack) ?? false))
            Button("Ungroup Tracks") { editor?.run(.ungroupTracks) }
                .disabled(!(editor?.canRun(.ungroupTracks) ?? false))
            Divider()
            // With tracks picked on their headers this row is what ⌫ does, so
            // it answers the key (U+0008, see `DeleteKeyCharacters`) for when
            // the canvas has the keyboard rather than the timeline. Otherwise
            // it acts on the clip in hand's track and only prints ⌫: a live
            // key there would take a track where ⌫ means the clip or the layer.
            let held = editor?.tracksInHand.count ?? 0
            Button(held > 1 ? "Delete \(held) Tracks" : "Delete Track", role: .destructive) {
                editor?.run(.deleteTrack)
            }
            .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuRow(answersThePress: held > 0)), modifiers: [])
            .disabled(track == nil)
            Button("Delete Empty Tracks", role: .destructive) { editor?.run(.deleteEmptyTracks) }
                .disabled(!(editor?.canRun(.deleteEmptyTracks) ?? false))
        }
    }

    // Sequence: the captions' own reset, and the word being said.
    @ViewBuilder private var captionEditRows: some View {
        Button("Reset Captions") { editor?.run(.resetCaptions) }
            .disabled(!(editor?.canRun(.resetCaptions) ?? false))
        let word = editor?.captionWordInHand
        Menu("Caption Word") {
            Button("Edit Word") { editor?.run(.editCaptionWord) }
            Button("Split Here") { editor?.run(.splitCaptionWord) }
                .disabled(!(editor?.canRun(.splitCaptionWord) ?? false))
            Button("Merge with Next") { editor?.run(.mergeCaptionWord) }
                .disabled(!(editor?.canRun(.mergeCaptionWord) ?? false))
            Button("Delete Word", role: .destructive) { editor?.run(.deleteCaptionWord) }
            Divider()
            Button("Move to Previous Line") { editor?.run(.moveWordToPreviousLine) }
                .disabled(!(editor?.canRun(.moveWordToPreviousLine) ?? false))
            Button("Move to Next Line") { editor?.run(.moveWordToNextLine) }
            Button("Join with Next Line") { editor?.run(.joinWithNextLine) }
                .disabled(!(editor?.canRun(.joinWithNextLine) ?? false))
            Button("Play from Here") { editor?.run(.playFromWord) }
            Button("Start Here") { editor?.run(.goToCaptionStart) }
        }
        .disabled(word == nil)
    }

    // View: how the timeline's rows are looked at, and the captions' guides.
    @ViewBuilder private var timelineViewRows: some View {
        Button("Compact Tracks") { editor?.run(.compactTracks) }
            .disabled(!(editor?.canRun(.compactTracks) ?? false))
        if Experiments.shared.captionsFromTheSoundEnabled {
            Toggle("Caption Safe Areas", isOn: Binding(
                get: { EditorState.showsSafeAreas },
                set: { _ in editor?.run(.captionSafeAreas) }))
            .disabled(!(editor?.canRun(.captionSafeAreas) ?? false))
        }
    }

    // MARK: Clip and Sequence (`next-a-pro-menu-bar`)

    /// What acts on the picked clip, the way Final Cut's and Premiere's Clip
    /// menus hold it: cut it, retime it, freeze it, reframe it, what happens at
    /// its cuts, its sound, and its keys. Each row acts on the clip in hand,
    /// the one picked, else the one under the playhead.
    @CommandsBuilder private var clipMenu: some Commands {
        CommandMenu(MenuBarOrder.clip) {
            if Experiments.shared.cutRecordingEnabled {
                splitAndDeleteRows
                rippleDeleteRow
                rippleTrimRows
                nudgeClipRows
                breakApartRow
                Divider()
            }
            clipItselfRows
            Divider()
            if Experiments.shared.cutRecordingEnabled {
                freezeAndSpeedRows
                Divider()
            }
            if Experiments.shared.punchInEnabled {
                punchInRows
                Divider()
            }
            if Experiments.shared.pictureFadesEnabled {
                pictureFadeRows
            }
            if Experiments.shared.transitionsAtACutEnabled {
                transitionAtCutMenu
                if Experiments.shared.cutRecordingEnabled { applyDefaultTransitionRow }
                expandCutRow
            }
            if Experiments.shared.cutRecordingEnabled { rollEditRow }
            Divider()
            if Experiments.shared.soundOnTheTimelineEnabled {
                detachAudioRow
                flattenLevelRow
                soundCleanupRows
                Divider()
            }
            if Experiments.shared.titlePresetsEnabled {
                saveTitlePresetRow
                Divider()
            }
            // A submenu rather than a section: everything a key, a path or a
            // title's time does made the Clip menu taller than a laptop's
            // screen, and a menu that scrolls hides its own rows. The keys it
            // prints still answer from inside it.
            Menu("Animate") {
                animatePropertyRows
                placedLayerRows
                Divider()
                keyNavigationRows
                animateRows
                Divider()
                keyLaneRows
                straightenRow
            }
        }
    }

    /// What acts on the time as a whole, the way Premiere's Sequence menu
    /// holds it: playing it, moving between edits, the marks and what cuts
    /// between them, splitting every track, snapping, the sound and captions
    /// that run the length of it, and putting the recording back.
    @CommandsBuilder private var sequenceMenu: some Commands {
        CommandMenu(MenuBarOrder.sequence) {
            transportRows
            Divider()
            editPointRows
            Divider()
            markRows
            markerRows
            Divider()
            extractLiftRows
            if Experiments.shared.cutRecordingEnabled {
                rangeRows
                splitEverythingRow
                Divider()
                snapRow
            }
            Divider()
            trackMenu
            Divider()
            if Experiments.shared.soundOnTheTimelineEnabled {
                addMediaRow
                exportSoundRow
                Divider()
            }
            if Experiments.shared.titlePresetsEnabled {
                insertTitleRows
                Divider()
            }
            if Experiments.shared.captionsFromTheSoundEnabled {
                captionRows
                captionEditRows
                Divider()
            }
            revertRecordingRow
        }
    }

    // MARK: Video, before the pro menu bar

    // Video menu: only meaningful in a recording window (phase 13.3). Gated
    // on the focused video state so it disables in image windows. The rows
    // under Revert are the small recording window's, which only Current still
    // opens; the pro menu bar has no Video menu at all.
    @CommandsBuilder private var videoMenu: some Commands {
        CommandMenu("Video") {
            let hasVideo = video?.isReady ?? false
            // A document with time plays in the editor, not in a recording
            // window, so the row plays whichever is in front of you.
            if timed {
                transportRows
                Divider()
                editPointRows
            } else {
                Button((video?.isPlaying ?? false) ? "Pause" : "Play") { video?.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!hasVideo)
            }
            Divider()
            if Experiments.shared.cutRecordingEnabled {
                splitAndDeleteRows
                if timed {
                    rippleDeleteRow
                    splitEverythingRow
                    rippleTrimRows
                    nudgeClipRows
                    applyDefaultTransitionRow
                    snapRow
                }
                freezeAndSpeedRows
                Divider()
            }
            if timed {
                keyNavigationRows
                Divider()
                Section("Animate") {
                    animateRows
                }
                Divider()
                markRows
                extractLiftRows
                Divider()
            }
            if Experiments.shared.punchInEnabled {
                punchInRows
                Divider()
            }
            if Experiments.shared.transitionsAtACutEnabled {
                transitionAtCutMenu
                Divider()
            }
            if Experiments.shared.soundOnTheTimelineEnabled {
                detachAudioRow
                addMediaRow
                flattenLevelRow
                exportSoundRow
                Divider()
            }
            if Experiments.shared.captionsFromTheSoundEnabled {
                captionRows
                Divider()
            }
            if timed {
                revertRecordingRow
            } else {
                recordingWindowRows
            }
        }
    }

    @ViewBuilder private var recordingWindowRows: some View {
        let hasVideo = video?.isReady ?? false
        // I and O belong to the recording window here; a document with
        // time spends them on its marks, above.
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
        // One way out, not three. The format and the size preset are
        // chosen ON the sheet, where you can see what they cost, rather
        // than in a submenu you had to get right before the save box
        // appeared (Next, `next-recording-export-sheet`). No key of its
        // own: File ▸ Export… carries ⇧⌘E for both editors.
        if Experiments.shared.recordingExportSheetEnabled {
            Button("Export…") { video?.isExportSheetPresented = true }
                .disabled(!hasVideo)
        } else {
            Button("Export MP4…") {
                if let video { coordinator.saveRecording(video, as: .mp4) }
            }
            .disabled(!hasVideo)
            Menu("Export GIF") {
                ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                    Button(quality.label) {
                        if let video {
                            coordinator.saveRecording(video, as: .gif, quality: quality)
                        }
                    }
                }
            }
            .disabled(!hasVideo)
            Menu("Export HEIC") {
                ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                    Button(quality.label) {
                        if let video {
                            coordinator.saveRecording(video, as: .heic, quality: quality)
                        }
                    }
                }
            }
            .disabled(!hasVideo)
        }
    }

    // MARK: Layer

    @CommandsBuilder private var layerMenu: some Commands {
        CommandMenu("Layer") {
            // New empty (transparent, canvas-sized) layer. The selection
            // region is preserved, so select → the key → fill paints the
            // region onto the fresh layer (user decision 2026-07-05). With
            // File reading like every Mac app's, ⌘N is File ▸ New and this
            // is ⇧⌘N, Photoshop's key for New Layer (2026-10-22).
            Button("New Layer") { editor?.run(.newLayer) }
                .keyboardShortcut(EditorCommands.newLayerKey)
                .disabled(!(editor?.canRun(.newLayer) ?? false))
            // Photoshop ⌘J: copy the marquee selection to a new layer, or —
            // with no marquee — duplicate the selected layer. Which pixels the
            // marquee takes follows the copy rule (`newLayerViaCopy`): the
            // layer you picked when you picked one, everything flattened
            // together when you did not.
            Button("New Layer via Copy") { editor?.run(.newLayerViaCopy) }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(!(editor?.canRun(.newLayerViaCopy) ?? false))
            // Photoshop ⇧⌘J, and its twin: the same command with the piece
            // TAKEN rather than copied, and the space it came from filled in
            // from what was around it (`newLayerViaCut`). Directly under the
            // copy row it is the sibling of, so the pair reads as a pair.
            // ⇧⌘J moves to Close Path… when one open outline is picked and no
            // marquee is up, the one case the cut has nothing to do
            // (`PathClose.shiftCommandJ`), so the bar prints it on one row.
            let shiftJ = editor?.shiftCommandJ ?? .newLayerViaCut
            let shiftJKey = KeyboardShortcut("j", modifiers: [.command, .shift])
            if Experiments.shared.newLayerViaCutEnabled {
                Button("New Layer via Cut") { editor?.run(.newLayerViaCut) }
                    .keyboardShortcut(shiftJ == .newLayerViaCut ? shiftJKey : nil)
                    .disabled(!(editor?.canRun(.newLayerViaCut) ?? false))
            }
            Button("Blur Behind Selection") { editor?.run(.blurBehindSelection) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!(editor?.canRun(.blurBehindSelection) ?? false))
            Divider()
            // No shortcut (Photoshop parity: ⌘D is Deselect; ⌘J covers the
            // duplicate-selected-layer case when no region is marqueed).
            Button("Duplicate Layer") { editor?.run(.duplicateLayer) }
                .disabled(!(editor?.canRun(.duplicateLayer) ?? false))
            // A copy reflected about the middle of its frame, so the second
            // half of a symmetrical icon is exact (`MirrorAcrossCenter.swift`).
            // Pictures and icons only: on a video ⇧⌘M is Go to Previous
            // Marker, and the row is absent there.
            if Experiments.shared.mirrorAcrossCenterEnabled && !timed {
                Button(MirrorAcrossCenter.title) { editor?.run(.mirrorAcrossCenter) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(!(editor?.canRun(.mirrorAcrossCenter) ?? false))
            }
            // Beside it, as the icon mock's Layers panel menu has them: what is
            // picked moves, as one piece, onto the middle of its frame
            // (`CenterOnArtboard.swift`). No key: the mock's ⌥⌘C is Canvas
            // Size, as it is in Photoshop.
            if Experiments.shared.iconShapeCommandsEnabled && !timed {
                Button(CenterOnArtboard.title) { editor?.run(.centerOnArtboard) }
                    .disabled(!(editor?.canRun(.centerOnArtboard) ?? false))
            }
            if Experiments.shared.proMenuBarEnabled {
                layerListRows
            }
            // Photoshop keeps Copy Layer Style and Paste Layer Style on the
            // layer's own right click menu with NO key at all, so nothing
            // Photoshop-shaped is being displaced here and there is no key to
            // inherit. Figma, Sketch and the Mac's own Copy Style in Pages and
            // TextEdit all use Option Command C and V, which is what a person
            // reaches for first — but Option Command C already belongs to
            // Canvas Size, which IS Photoshop's, so it stays where it is and
            // the look takes the shifted pair one step along. They sit under
            // Duplicate Layer, and on the layer's right click menu too, which
            // is where somebody coming from Photoshop looks for them.
            if Experiments.shared.copyALookEnabled {
                Button("Copy Look") { editor?.run(.copyLook) }
                    .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                    .disabled(!(editor?.canRun(.copyLook) ?? false))
                Button("Paste Look") { editor?.run(.pasteLook) }
                    .keyboardShortcut("v", modifiers: [.command, .option, .shift])
                    .disabled(!(editor?.canRun(.pasteLook) ?? false))
            }
            if Experiments.shared.proMenuBarEnabled {
                effectRows
            }
            // How a picked arrow is drawn, and a new hand for it: the same two
            // rows its right-click menu carries, under the same names, beside
            // the other look commands. Dimmed rather than absent with no arrow
            // picked, so the menu is where somebody learns they exist.
            if Experiments.shared.arrowStylesEnabled {
                Menu(ArrowStyle.menuTitle) {
                    ForEach(ArrowStyle.allCases, id: \.self) { style in
                        Toggle(style.title, isOn: Binding(
                            get: { editor?.pickedArrowStyle == style },
                            set: { _ in editor?.run(.setArrowStyle, ["style": .string(style.rawValue)]) }))
                    }
                }
                .disabled(editor?.pickedArrowIDs.isEmpty ?? true)
                Button(ArrowStyle.reshuffleTitle) { editor?.run(.reshuffleArrows) }
                    .disabled(!(editor?.canRun(.reshuffleArrows) ?? false))
            }
            if Experiments.shared.arrowBendEnabled {
                Button(ArrowBend.straightenTitle) { editor?.run(.straightenArrows) }
                    .disabled(!(editor?.canRun(.straightenArrows) ?? false))
            }
            // The Around menu's Somewhere else, where every command lives with
            // its key: the next press on the canvas puts the picked turn's
            // pivot down. Dimmed with nothing turning, so the row is where a
            // person learns the key exists.
            if Experiments.shared.motionEnabled {
                Button(MotionPivot.PlaceOnCanvas.menuBarTitle) { editor?.beginPlacingMotionPivot() }
                    .keyboardShortcut(KeyEquivalent(MotionPivot.PlaceOnCanvas.key), modifiers: [])
                    .disabled(!(editor?.canPlaceMotionPivot ?? false))
            }
            Button("Merge Down") { editor?.run(.mergeDown) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!(editor?.canRun(.mergeDown) ?? false))
            // The one command that makes a rectangle into an outline you can
            // pull the points of (`ShapeToPath.swift`). Right above Turn Into
            // Picture, because the two are the same kind of one-way turn and
            // this is the gentler one: it keeps the shape editable. Disabled
            // rather than absent on a layer that has no outline to find, so the
            // row is somewhere you can learn it exists.
            if Experiments.shared.turnIntoPathEnabled {
                // On the whole selection, like Duplicate and Delete: picking
                // three lines that meet and asking for a path gives you ONE
                // path, welded where their ends meet (`PathJoining.swift`).
                // ...and picking two outlines already drawn with the PEN
                // welds those, which is the same command: the row retitles
                // itself Join Paths when nothing picked has to be turned first,
                // and Close Path over one open outline on its own, which shuts
                // it on its own two ends (`PathClosing.swift`).
                Button(editor?.turnSelectionIntoPathMenuItem ?? TurnIntoPathPrompt.menuItem) {
                    editor?.run(.turnIntoPath)
                }
                .keyboardShortcut(shiftJ == .closePath ? shiftJKey : nil)
                .disabled(!(editor?.canTurnSelectionIntoPath ?? false))
            }
            // Two shapes become one (`PathCombining.swift`). A submenu rather
            // than four rows in the Layer menu, because they are one idea with
            // four answers and the menu is already long; directly under Turn
            // Into Path, because both turn a shape you drew into an outline you
            // can pull the points of. The whole submenu is dimmed on a
            // selection with fewer than two shapes in it, which is where
            // somebody finds out the commands exist.
            if Experiments.shared.penEnabled {
                Menu(PathCombine.menuItem) {
                    ForEach(PathCombine.Operation.allCases, id: \.self) { operation in
                        Button(operation.title) { editor?.run(.combineShapes, ["operation": .string(operation.rawValue)]) }
                    }
                }
                .disabled(!(editor?.canCombineSelection ?? false))
            }
            // Words set along a drawn curve (`TextOnPath.swift`): beside the
            // other commands that turn what you drew into something new, and
            // dimmed until a text and a path are picked together.
            if Experiments.shared.textOnPathEnabled {
                Button(EditorState.putTextOnPathTitle) { editor?.run(.putTextOnPath) }
                    .disabled(!(editor?.canPutTextOnPath ?? false))
            }
            // The two the icon mock's Layers panel menu puts together: Join
            // under the name every other drawing program gives it, with the
            // mock's key, and a line turned into the filled shape it draws
            // (`OutlineStroke.swift`). Pictures and icons only, like the
            // panel menu's rows.
            if Experiments.shared.penEnabled && Experiments.shared.iconShapeCommandsEnabled && !timed {
                Button(PathCombine.unionTitle) { editor?.run(.union) }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                    .disabled(!(editor?.canRun(.union) ?? false))
                Button(OutlineStroke.title) { editor?.run(.outlineStroke) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(!(editor?.canRun(.outlineStroke) ?? false))
            }
            // The one command that makes a shape or a piece of text into pixels,
            // which is what a marquee needs before it can cut a piece out of it
            // (`RasterizePrompt`, `RegionSliceRefusal`). Named the way the
            // refusal pill names it, not the way Photoshop does.
            Button(RasterizePrompt.menuItem) {
                editor?.run(.turnIntoPicture)
            }
            // Its own key, so the refusal's way out is reachable by somebody
            // who never touches a pointer, and stays reachable after the pill
            // that offers it has faded. Photoshop leaves Rasterize unbound, so
            // nothing is being displaced; ⇧⌘R is free here and R is the letter
            // the other name for this command starts with.
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!(editor?.canRasterizeSelection ?? false))
            // The same command the picture's own row menu carries, under the
            // same name, so it is reachable without hunting for a right click
            // (Next, `next-separate-into-layers`). Absent rather than greyed
            // when the flag is off, like every other flagged row.
            if Experiments.shared.separateIntoLayersEnabled {
                Button("Separate into Layers") {
                    editor?.run(.separateIntoLayers)
                }
                .disabled(!(editor?.canRun(.separateIntoLayers) ?? false))
                // The step after it, in the same two places, under the same
                // name: a picture of a run of text becomes words you can
                // retype.
                // Over everything picked, like Turn Into Picture above it, and
                // over the whole group a big separation arrives in.
                Button("Turn into Text") { editor?.run(.turnIntoText) }
                .disabled(!(editor?.canRun(.turnIntoText) ?? false))
            }
            Button("Arrange in Collage") { editor?.run(.arrangeInCollage) }
                .disabled(!(editor?.canRun(.arrangeInCollage) ?? false))
            Button("New Collage Layer") { editor?.run(.newCollageLayer) }
                .disabled(!(editor?.canRun(.newCollageLayer) ?? false))
            // Group and ungroup, on Photoshop's keys, directly above the
            // arrange commands so the structure commands sit together
            // (`docs/design/ui-building.md`). Flagged rows are absent, not
            // greyed, so nobody hunts for why a dead row is there.
            if Experiments.shared.layerGroupsEnabled {
                Divider()
                Button("Group") { editor?.run(.group) }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(!(editor?.canRun(.group) ?? false))
                // ⇧⌘G goes to Clip ▸ Break Apart while a merged clip is in
                // hand, so one key never sits on two rows.
                Button("Ungroup") { editor?.run(.ungroup) }
                    .keyboardShortcut(Experiments.shared.proMenuBarEnabled && (editor?.canBreakApartInHand ?? false)
                                      ? nil : KeyboardShortcut("g", modifiers: [.command, .shift]))
                    .disabled(!(editor?.canRun(.ungroup) ?? false))
            }
            // Groups that arrange their own contents (`next-auto-layout`),
            // right under Group, because a stack IS a group that arranges
            // itself and the two are pressed for the same reason. Stacking is
            // one modifier off grouping, and Photoshop binds neither the
            // command nor Control Command G. Grid Selection takes no key: it
            // is the same act with a column count, and a grid is picked far
            // less often than a row of things.
            if Experiments.shared.autoLayoutEnabled {
                Button(LayersPanelHeader.MenuRow.stackTitle) { editor?.run(.stackSelection) }
                    .keyboardShortcut("g", modifiers: [.command, .control])
                    .disabled(!(editor?.canRun(.stackSelection) ?? false))
                Button("Grid Selection") { editor?.run(.gridSelection) }
                    .disabled(!(editor?.canRun(.gridSelection) ?? false))
                // Telling a piece to take whatever room its stack has left is
                // the answer people reach for most while building a bar, and
                // until now it was only reachable two rows into a panel that
                // has to be open to be read. It sits directly under the rows
                // that MAKE a stack, because a stack is what gives it anything
                // to take. Option F joins the align set (Option and a letter),
                // and Photoshop binds neither the command nor the key. It is a
                // tick rather than a button so the row also answers "is this
                // piece filling?", and its hover line says why it is grey when
                // it is: a menu row has nowhere else to explain itself.
                // A layer a container has swallowed comes back in one move,
                // the same move the orange scissors on its row make. It is
                // here as well because the Layer menu is where somebody who
                // has not noticed a small mark in the list goes looking, and
                // because a menu row can carry the words "Bring into View"
                // where a glyph cannot. No key: this is a rescue you reach for
                // once in a while, not a working command, and every free
                // Photoshop-safe combination is worth more to one.
                Button("Bring into View") { editor?.run(.bringIntoView) }
                    .disabled(!(editor?.canBringSelectionIntoView ?? false))
                let fill = editor?.flowFillCommand ?? .none
                Toggle(fill.title, isOn: Binding(get: { fill.isOn },
                                                 set: { _ in editor?.run(.fillTheStack) }))
                .keyboardShortcut("f", modifiers: .option)
                .disabled(!fill.isEnabled)
                .help(fill.help)
                // The other thing a piece inside an arrangement can be, and
                // the one that could not be said in a single act anywhere
                // until now: a surface is stretched BOTH ways, and a stack
                // owns the direction it runs, so the panel could only ever
                // offer one of the two Stretches it takes. It sits beside
                // Fill because the two are the same question — what is this
                // piece doing in this group — with opposite answers, and a
                // piece cannot be both. A tick rather than a button, so the
                // row also answers "is this the surface?". No key: it is set
                // once while a component is being built, not reached for
                // while working, and every free Photoshop-safe combination
                // is worth more to something pressed often.
                let surface = editor?.surfaceCommand ?? .none
                Toggle(SurfaceCommand.menuTitle,
                       isOn: Binding(get: { surface.isOn },
                                     set: { _ in editor?.run(.surfaceBehind) }))
                .disabled(!surface.isEnabled)
                .help(surface.help)
                // The same step out of the line, the opposite depth: out, and
                // in FRONT, which is where a badge on the corner of a card
                // lives (`FloatingPiece.swift`). Directly under the surface so
                // the pair reads as one idea with two directions, and a tick
                // for the same reason the row above has one.
                Toggle(FloatingCommand.menuTitle,
                       isOn: Binding(get: { surface.isFloating },
                                     set: { _ in editor?.run(.inFrontOfTheRest) }))
                .disabled(!surface.isEnabled)
                .help(surface.reason ?? FloatingCommand.reason)
            }
            // Frames sit with the structure commands, because a frame IS a
            // group with a size. Neither row takes a key: F already picks the
            // frame tool, and the design-tool key for Frame Selection (⌥⌘G) is
            // Photoshop's Create Clipping Mask, which this app may want later.
            if Experiments.shared.framesEnabled {
                Button("New Frame…") { editor?.run(.newFrame) }
                    .disabled(editor?.document == nil)
                Button("Frame Selection") { editor?.run(.frameSelection) }
                    .disabled(!(editor?.canRun(.frameSelection) ?? false))
                // The columns the selected screen is designed to, beside the
                // rows that make a screen. No key: the canvas grid already has
                // the obvious one, and two grid-ish chords a finger apart is
                // how you press the wrong one every time. It acts on the screen
                // you have picked, or on the screen whatever you have picked
                // lives in, and it is dimmed when the selection is nowhere near
                // one. The numbers live in the Columns section of the panel,
                // where this same switch also sits, so nobody has to hunt for
                // the half of the feature the menu does not carry.
                Toggle(FrameColumnsCopy.menuItem, isOn: Binding(
                    get: { editor?.isShowingFrameColumns ?? false },
                    set: { _ in editor?.run(.showColumns) }))
                .disabled(editor?.columnsTargetFrameID == nil)
            }
            // The component commands form their own group under the structure
            // ones. Option Command K is the key a design tool user already has
            // in their fingers, and Photoshop binds neither the command nor the
            // key, so there is nothing to be compatible with.
            if Experiments.shared.componentsEnabled {
                Button("Make Component") { editor?.run(.makeComponent) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                    .disabled(!(editor?.canRun(.makeComponent) ?? false))
                // Insert Component takes no key: it is the keyboard way to do
                // what a drag from the shelf already does, and the shelf has to
                // be open with a component picked for it to mean anything.
                Button("Insert Component") { editor?.insertPickedComponent() }
                    .disabled(!(editor?.canInsertPickedComponent ?? false))
                // Add Variant takes no key either: it is a thing you do once
                // per look, from the original's own Properties list, and a key
                // for it would be a key nobody could name.
                Button(editor?.selectedComponentVariantWording.addCommand ?? "Add Variant") {
                    editor?.run(.addVariant)
                }
                    .disabled(!(editor?.canAddComponentVersion ?? false))
                // Apply to Other Variants is ABSENT unless the selected piece
                // is part of an original that HAS other looks, because on
                // anything else it is a row about a feature you are not using.
                // When it is there it NAMES them — "Apply to Hover and
                // Disabled" — so nobody has to press it to find out what it
                // would touch, and it dims saying why when there is nothing to
                // do. No key: it is the follow-up to an edit you just made,
                // and every key a design tool user has in their fingers for
                // this belongs to something else.
                if let title = editor?.applyToOtherComponentVersionsTitle {
                    Button(title) { editor?.run(.applyToOtherVersions) }
                        .disabled(!(editor?.canApplyToOtherComponentVersions ?? false))
                }
                // Make Alternatives is ABSENT rather than dimmed when the
                // selection cannot become a choice. Every other row here reads
                // as something you might want on any selection; this one only
                // means anything on two shapes inside an original, and a dead
                // row on every other selection is a row people hunt the reason
                // for. It appears the moment it would work.
                if editor?.canMakeChoice ?? false {
                    Button("Make Alternatives") { editor?.run(.makeAlternatives) }
                }
                // Option Command B is the design-tool key for detaching, and
                // Photoshop binds neither the command nor the key. Select
                // Original takes none: it is a way to get somewhere, not an
                // edit, and the copy's own section has a button for it.
                Button("Make Unique") { editor?.run(.makeUnique) }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                    .disabled(!(editor?.canRun(.makeUnique) ?? false))
                Button(OriginalSpaceCopy.menuEdit) { editor?.run(.editOriginal) }
                    .disabled(!(editor?.canEditPickedOriginal ?? false))
                Button(OriginalSpaceCopy.menuDone) { editor?.run(.doneEditingOriginal) }
                    .disabled(!(editor?.isEditingOriginal ?? false))
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
                        Button(alignment.menuTitle) { editor?.run(.align, ["edge": .string(alignment.rawValue)]) }
                            .keyboardShortcut(alignKey(alignment), modifiers: .option)
                            .disabled(!(editor?.canRun(.align, ["edge": .string(alignment.rawValue)]) ?? false))
                    }
                }
                .disabled(!(editor?.canAlignSelection ?? false))
                Menu("Space Evenly") {
                    ForEach(LayerDistribution.allCases, id: \.self) { axis in
                        Button(axis == .horizontal ? "Across" : "Down") {
                            editor?.run(.spaceEvenly, ["axis": .string(axis.rawValue)])
                        }
                        .keyboardShortcut(axis == .horizontal ? "h" : "v",
                                          modifiers: [.control, .option])
                        .disabled(!(editor?.canRun(.spaceEvenly, ["axis": .string(axis.rawValue)]) ?? false))
                    }
                }
                .disabled(!(editor?.canDistributeSelection ?? false))
            }
            // Where a layer sits and how big it is, typed exactly
            // (`ExactPlacement`). These four numbers used to be a section
            // sitting open in the right hand panel for every layer; they are
            // asked for now, and this row is their home in the menu bar. Option
            // Command P because P is the letter Position starts with and
            // Photoshop binds neither the command nor the key; plain Command T
            // is left alone because macOS reserves it for Show Fonts wherever
            // there is text, and this app has text.
            if Experiments.shared.geometryFieldsEnabled {
                Divider()
                Button(ExactPlacement.menuItem) { editor?.openExactPlacement() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(!(editor?.canOpenExactPlacement ?? false))
            }
            // The picked layer's transform values, in the popover the tool
            // bar's Info button opens (`TransformValuesPopover`). F8 is
            // Photoshop's key for its Info panel. The row opens and closes it:
            // chosen from the menu it is always opening, because the menu
            // starting to track has already closed it.
            if Experiments.shared.transformBarEnabled {
                if !Experiments.shared.geometryFieldsEnabled { Divider() }
                Button("Show Transform Values") { editor?.toggleTransformValues() }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey) ?? " ")),
                                      modifiers: [])
                    .disabled(!(editor?.canShowTransformValues ?? false))
            }
            Divider()
            // The arrange commands, Duplicate and Delete act on the whole
            // selection: the multi-selection a shift-click, command-click or
            // marquee built, else the one selected layer.
            Button("Bring to Front") { editor?.run(.bringToFront) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!(editor?.canRun(.bringToFront) ?? false))
            Button("Bring Forward") { editor?.run(.bringForward) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(editor?.canRun(.bringForward) ?? false))
            Button("Send Backward") { editor?.run(.sendBackward) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(editor?.canRun(.sendBackward) ?? false))
            Button("Send to Back") { editor?.run(.sendToBack) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!(editor?.canRun(.sendToBack) ?? false))
            // Turning the picked layers in space (Next, `next-turn-in-depth`,
            // `video-depth.html`): Option with the arrange keys moves them
            // nearer and further rather than up and down the stack.
            if Experiments.shared.turnInDepthEnabled {
                Divider()
                Button("Reset 3D Rotation") { editor?.run(.reset3DRotation) }
                    .disabled(!(editor?.canResetSpaceRotation ?? false))
                Button("Bring Nearer") { editor?.run(.bringNearer) }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                    .disabled(!(editor?.canPushDepth ?? false))
                Button("Send Further") { editor?.run(.sendFurther) }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                    .disabled(!(editor?.canPushDepth ?? false))
            }
            Divider()
            deleteLayerRow
        }
    }

    // MARK: Measure

    @CommandsBuilder private var measureMenu: some Commands {
        // The mock's Measure command group (§6, `next-measure-panel`): the tool,
        // then the same commands the Measurements panel menu offers, in the
        // panel's order and under the panel's names (§6's mirror rule: a panel
        // menu never offers a command the menu bar lacks, and both call it by
        // one name). Copy Measurement is the one extra here, since it acts on
        // the selection rather than the whole document. The flag exists only
        // in Next's catalog, so Current never grows this menu.
        if Experiments.shared.measurePanelEnabled {
            CommandMenu("Measure") {
                let visibleCount = editor?.visibleMeasurementCount ?? 0
                let selectedCount = editor?.selectedMeasureLayerIDs.count ?? 0
                Button("Measure Tool") { editor?.setTool(.measure) }
                    .disabled(editor?.document == nil)
                Divider()
                // Each is off when it would change nothing: Show All while
                // every measurement is already showing, Hide All while none
                // is. Either one is a single undo step.
                Button("Show All Measurements") { editor?.run(.showAllMeasurements) }
                    .disabled(!(editor?.canRun(.showAllMeasurements) ?? false))
                Button("Hide All Measurements") { editor?.run(.hideAllMeasurements) }
                    .disabled(!(editor?.canRun(.hideAllMeasurements) ?? false))
                Divider()
                // ⌃⌘C: the copy family's free chord. ⇧⌘C is Copy Merged,
                // ⌥⌘C is Canvas Size and ⌥⇧⌘C is Content-Aware Scale, all
                // Photoshop keys.
                // Only visible rows are listed, so with every row hidden the
                // item is off rather than copying a bare header.
                Button("Copy as Spec List") { editor?.run(.copySpecList) }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                    .disabled(visibleCount == 0)
                // Plain ⌘C on a selected measurement already carries its spec
                // line as text beside the layer payload; this is the text-only
                // form, and the one that copies a multi-selection's lines.
                Button(selectedCount > 1 ? "Copy Measurements" : "Copy Measurement") {
                    editor?.run(.copyMeasurements)
                }
                .disabled(selectedCount == 0)
                Divider()
                Button("Clear Measurements") { editor?.run(.clearMeasurements) }
                    .disabled(!(editor?.canRun(.clearMeasurements) ?? false))
            }
        }
    }


    /// The View menu's additions, the Help menu, and the app menu's Settings
    /// row, together in one place. They are grouped only because a `Commands`
    /// body takes ten statements and this file had ten before the guides
    /// arrived.
    @CommandsBuilder private var viewAndHelpCommands: some Commands {
        // Settings sits where every Mac app puts it: its own slot under the app
        // menu, on ⌘,. It is the one place a silenced question can be turned
        // back on, so the app menu has to offer it even though today it opens a
        // window with one page (`SettingsDialog`). Next only: with the flag off
        // the slot stays empty and the app menu is exactly what it was.
        CommandGroup(replacing: .appSettings) {
            if Experiments.shared.settingsWindowEnabled {
                Button(SettingsWindowModel.menuItem) { coordinator.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        // View's rows. On the pro menu bar they are a menu the app declares
        // after the document menus, so SwiftUI lays View out before Window by
        // itself and nothing has to move it (`MenuBarArranger`); with the flag
        // off they join SwiftUI's own View, as they always did.
        if Experiments.shared.proMenuBarEnabled {
            CommandMenu(MenuBarOrder.view) { viewMenuRows }
        } else {
            CommandGroup(after: .sidebar) {
                viewMenuRows
                Divider()
            }
        }
        // The capture history is a window of its own, so on the pro menu bar
        // it is where a Mac user looks for one: Window, with the checkmark
        // saying whether it is up (Photoshop's Window ▸ History).
        CommandGroup(after: .windowArrangement) {
            if Experiments.shared.proMenuBarEnabled {
                Divider()
                historyToggle
            }
        }
        // There is no Help menu until this: macOS supplies a default one whose
        // single row opens a help book Photonz does not have. Replacing the
        // group puts the guides there instead, which is the first place anybody
        // looks for them. The track submenus and the hub window are their own
        // task; this is the one row that proves the framework.
        CommandGroup(replacing: .help) {
            if Experiments.shared.tutorialsEnabled {
                let tutorials = tutorialMenu
                if !tutorials.isEmpty {
                    Menu(TutorialMenuModel.menuTitle) {
                        // The promoted guide, first, because it is the one a
                        // person who has never opened the app should take. It
                        // is a shortcut and not an exception: it is still
                        // listed under its own track below, because a track
                        // list that leaves a guide out is a lie.
                        if let tour = tutorials.tour {
                            tutorialRow(tour)
                            Divider()
                        }
                        // One submenu per track that has something on it. A
                        // flat list of every guide is what this menu exists to
                        // avoid, so there is never one, not even while only one
                        // track is populated.
                        ForEach(tutorials.tracks) { track in
                            Menu(track.title) {
                                ForEach(track.rows) { row in
                                    tutorialRow(row)
                                }
                            }
                        }
                        Divider()
                        Button(TutorialMenuModel.hubRowTitle) { coordinator.showTutorials() }
                            .help(TutorialMenuModel.hubRowHelp)
                    }
                }
            }
        }
    }

    /// What View holds: the panel, the modes, the zooms, the grid.
    @ViewBuilder private var viewMenuRows: some View {
        let hasDocument = editor?.document != nil
        // A setting, so one name and a checkmark: the item never renames
        // itself and never changes width under the pointer, and it reports
        // its own on/off to accessibility (MenuToggleNames).
        //
        // Every `set` below FLIPS what the state says right now rather than
        // storing the value SwiftUI hands it. A Commands body is re-run
        // only while an event is being handled, so the value the item was
        // drawn from can be a toggle behind; flipping the live reading is
        // what the plain Button did and it cannot be talked into a press
        // that does nothing. `set` runs only when a person picks the item,
        // so there is no other writer to disagree with.
        Toggle(MenuToggleNames.panel, isOn: Binding(
            get: { editor?.isLayersPanelVisible ?? false },
            set: { _ in
                if let editor { editor.setInspectorVisible(!editor.isLayersPanelVisible) }
            }))
        .keyboardShortcut("l", modifiers: [.command, .option])
        .disabled(!hasDocument)
        // The Library shelf, right under Show Panel because they are the
        // same kind of thing, and in the order they nest: the panel is the
        // column, the Library is one shelf inside it. No key: Photoshop
        // binds none for its Libraries panel, and Option Command L already
        // shows the panel.
        // A flagged command is absent, not greyed, so the row is simply
        // not there when the flag is off.
        if Experiments.shared.libraryEnabled {
            Toggle(MenuToggleNames.library, isOn: Binding(
                get: { editor?.isLibraryShown ?? false },
                set: { _ in
                    if let editor { editor.setLibraryVisible(!editor.isLibraryShown) }
                }))
            .disabled(!hasDocument)
        }
        // The timing strip across the bottom (Next, `next-motion-strip`).
        // Next to the panel because it is the same kind of thing: a surface
        // the window can show or put away. Dimmed with nothing moving,
        // because there is no strip for a still picture and a row that
        // would open an empty one is a row that lies.
        //
        // A recording has no strip to show or hide: its tracks are Edit
        // mode's, and the window is a player or the editor
        // (`ViewEditMode`), on ⌘1 and ⌘2 like the title bar's switch.
        if editor?.documentHasTime ?? false {
            ForEach(ViewEditMode.allCases, id: \.self) { mode in
                Toggle(mode.menuTitle, isOn: Binding(
                    get: { editor?.viewEditMode == mode },
                    set: { _ in editor?.setViewEditMode(mode) }))
                .keyboardShortcut(KeyEquivalent(mode.commandKey), modifiers: .command)
            }
            // The transport's timeline toggle, on the key an icon's
            // timing strip has.
            Toggle(MenuToggleNames.timeline, isOn: Binding(
                get: { editor?.isMotionStripOpen ?? false },
                set: { _ in editor?.pressTimelineToggle() }))
            .keyboardShortcut("t", modifiers: [.command, .option])
        } else if Experiments.shared.motionStripEnabled {
            Toggle(MenuToggleNames.timingStrip, isOn: Binding(
                get: { editor?.isMotionStripShown ?? false },
                set: { _ in editor?.toggleMotionStrip() }))
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(!(editor?.hasMotionStrip ?? false))
        }
        // What this window is set up for (Next, `next-window-modes`). Here
        // rather than anywhere else because a mode is a VIEW preference in
        // the strictest sense: it changes what the window offers and
        // nothing whatever about the document. It sits with the panel and
        // the strip above it, which are the other two surfaces a window can
        // put away.
        //
        // A submenu rather than a flat run of rows: five modes and two ways
        // out would be seven rows in the middle of View, and the chip in
        // the title bar is the everyday door. This one is the keyboard's
        // door and accessibility's.
        //
        // Modes are for pictures: a document with time has one setup, so the
        // submenu is there but dimmed, and ⌃1 … ⌃3 do nothing to it.
        if Experiments.shared.windowModesEnabled {
            Menu(WindowModeCopy.menuTitle) {
                ForEach(WindowModes.offered(hasTime: false)) { mode in
                    Button(mode.title) { editor?.swapWindowMode(to: mode.id) }
                        .keyboardShortcut(modeKey(mode.id))
                }
                Divider()
                Button(WindowModeCopy.showEverything) {
                    editor?.showEverythingInWindow()
                }
            }
            .disabled(!hasDocument || (editor?.documentHasTime ?? false))
        }
        Button("Zoom In") { editor?.run(.zoomIn) }
            .keyboardShortcut("=", modifiers: .command) // the ⌘+ key
            .disabled(!(editor?.canRun(.zoomIn) ?? false))
        Button("Zoom Out") { editor?.run(.zoomOut) }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!(editor?.canRun(.zoomOut) ?? false))
        Button("Zoom to Fit") { editor?.run(.zoomToFit) }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(!(editor?.canRun(.zoomToFit) ?? false))
        // ⌘1 is View mode on a document with time (`ViewEditMode`), so
        // there Actual Size takes Photoshop's older ⌥⌘0.
        Button("Actual Size") { editor?.run(.actualSize) }
            .keyboardShortcut((editor?.documentHasTime ?? false) ? "0" : "1",
                              modifiers: (editor?.documentHasTime ?? false) ? [.command, .option] : .command)
            .disabled(!hasDocument)
        // The timeline, fitted to the whole of the time: the row its
        // right-click has, on Premiere's \, which the timeline answers
        // while it has the keyboard (⇧Z is Punch In).
        if Experiments.shared.proMenuBarEnabled && timed {
            Button("Zoom Timeline to Fit") { editor?.run(.zoomTimelineToFit) }
                .keyboardShortcut(timelineKeys ? KeyboardShortcut("\\", modifiers: []) : nil)
                .disabled(!(editor?.canRun(.zoomTimelineToFit) ?? false))
            timelineViewRows
        }
        // The camera the frame is seen through (Next, `next-turn-in-depth`):
        // a view of the picture, so it sits with the zooms. Show Camera
        // Settings picks the frame, whose panel holds the Camera section.
        if Experiments.shared.turnInDepthEnabled {
            Divider()
            Button("Show Camera Settings") { editor?.showCameraSettings() }
                .disabled(editor?.document == nil)
            Button("Reset Camera") { editor?.run(.resetCamera) }
                .disabled(!(editor?.canResetCamera ?? false))
        }
        // The grid you build against (Next, `next-canvas-grid`), on the key
        // Photoshop uses for its own. It is a view preference, not part of
        // the picture, so it belongs on this menu next to the zooms rather
        // than anywhere near Layer or Image. Everything that shapes it is
        // one row below, on Grid Settings, and on the chip the grid puts in
        // the tool bar while it is showing.
        if Experiments.shared.canvasGridEnabled {
            Divider()
            Toggle(MenuToggleNames.grid, isOn: Binding(
                get: { editor?.canvasGrid.isVisible ?? false },
                set: { _ in editor?.toggleCanvasGrid() }))
            .keyboardShortcut("'", modifiers: .command)
            .disabled(!hasDocument)
            // Right under the switch, because the menu you turn the grid on
            // from is the first place you look for what shapes it. It is
            // also the same popover the grid's icon in the tool bar opens,
            // and it leaves the grid alone either way: the switch above is
            // the first row of what it raises.
            Button(CanvasGridCopy.settingsMenuItem) {
                editor?.showGridSettings()
            }
            .disabled(!hasDocument || (editor?.isAdjustingGrid ?? false))
            // Photoshop's own key for Snap, next to the grid it pulls to.
            // Dimmed with the grid hidden, because with no lines on the
            // picture there is nothing to pull to.
            Toggle(MenuToggleNames.snapToGrid, isOn: Binding(
                get: { editor?.canvasGrid.snapsToGrid ?? true },
                set: { _ in editor?.toggleSnapToGrid() }))
            .keyboardShortcut(";", modifiers: [.command, .shift])
            .disabled(!hasDocument || !(editor?.canvasGrid.isVisible ?? false))
            // Where the grid starts, and the guides pinned onto it. It
            // takes the canvas over, so it reads as an action with an
            // ellipsis rather than as a switch. The tool bar's Adjust Grid
            // button is the same door on a canvas wide enough to hold it;
            // this is how you get in at any width.
            //
            // Dimmed with the grid hidden, for the reason Snap above it is:
            // the whole mode is placing a zero point against lines you can
            // see. With the grid off the gear is not on the tool bar
            // either, so the two doors say the same thing.
            Button(CanvasGridCopy.adjustMenuItem) {
                editor?.beginGridAdjustment()
            }
            .disabled(!hasDocument || !(editor?.canvasGrid.isVisible ?? false)
                      || (editor?.isAdjustingGrid ?? false))
        }
        // The space an icon has to live inside (Next, `next-icon-frames`).
        // Here rather than on Layer because it is the same kind of thing
        // the grid above it is: how you like to draw, kept between
        // launches, true of every icon frame at once. Nothing else shapes
        // it, because the frame's size already says what the margin is.
        //
        // Dimmed when nothing in the document is the size an icon is drawn
        // at: a tick beside a row that plainly changes nothing on screen
        // is worse than a row that says there is nothing to change.
        if Experiments.shared.iconFramesEnabled {
            Divider()
            Toggle(MenuToggleNames.iconKeylines, isOn: Binding(
                get: { editor?.iconKeylinesShowing ?? false },
                set: { _ in editor?.toggleIconKeylines() }))
            .disabled(!hasDocument || !(editor?.hasIconFrames ?? false))
            // What a point inside an icon is pulled onto, each pull on its
            // own: the icon mock's Snap to row (`icon-draw-wt.html`), here
            // because snapping is how you look at the work, like the grid's
            // own Snap above (UX-PATTERNS placement contract). Keylines is
            // dimmed while they are hidden, for the reason Snap to Grid is:
            // a pull towards lines nobody can see feels like a bug.
            Menu(MenuToggleNames.snapInIcons) {
                Toggle(MenuToggleNames.iconSnapGrid, isOn: Binding(
                    get: { editor?.iconSnapChoices.grid ?? true },
                    set: { _ in editor?.toggleIconSnap(\.grid) }))
                Toggle(MenuToggleNames.iconSnapKeylines, isOn: Binding(
                    get: { editor?.iconSnapChoices.keylines ?? true },
                    set: { _ in editor?.toggleIconSnap(\.keylines) }))
                .disabled(!(editor?.iconKeylinesShowing ?? false))
                Toggle(MenuToggleNames.iconSnapGeometry, isOn: Binding(
                    get: { editor?.iconSnapChoices.geometry ?? true },
                    set: { _ in editor?.toggleIconSnap(\.geometry) }))
            }
            .disabled(!hasDocument || !(editor?.hasIconFrames ?? false))
        }
        // Last, where every Mac app has it, on the Mac's own ⌃⌘F, for a
        // picture or a video, the player or the editor (`PlayerFullScreen`).
        // Only on the pro menu bar: there AppKit's own row is in SwiftUI's
        // View, which `MenuBarArranger` hides, so without this one nothing on
        // the bar carried the chord. With the flag off, SwiftUI's View is
        // the one on screen and keeps AppKit's row.
        if Experiments.shared.proMenuBarEnabled {
            Divider()
            Button(PlayerFullScreen.menuTitle(isFullScreen: editor?.isWindowFullScreen ?? false)) {
                editor?.toggleWindowFullScreen()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
            .disabled(!hasDocument)
        }
    }
}

/// Open Recent: the same documents the front door's Recent puts among your
/// captures, newest first, with Clear Menu at the foot. One list for File and
/// for the menu under the app's icon (`MenuBarMenu`), so the two never differ.
struct OpenRecentMenu: View {
    let coordinator: AppCoordinator

    var body: some View { openRecentMenu }

    // Its rows under this name, which is what `EveryMenuCommandHasANameTests`
    // reads File's rows by.
    private var openRecentMenu: some View {
        let recents = RecentDocumentsStore.shared
        let documents = recents.documents
        let titles = RecentDocuments.menuTitles(documents)
        return Menu("Open Recent") {
            ForEach(Array(zip(documents, titles)), id: \.0.id) { document, title in
                Button(title) { coordinator.openFileWindow(document.url) }
            }
            if !documents.isEmpty { Divider() }
            Button("Clear Menu") { recents.clear() }
                .disabled(documents.isEmpty)
        }
    }
}
