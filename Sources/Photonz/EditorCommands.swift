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
    /// The ⌥⌫ half of that was re-measured on 2026-09-17, since until then the
    /// row carried a chord no keyboard could type and so could not have won
    /// anything: a window with a text field in it, the field holding the
    /// keyboard, and a real ⌫ press with ⌥ handed to `NSApplication.sendEvent`
    /// deleted a word and left the menu item alone, while the same press with
    /// nothing focused ran the item. ⌘⌫ goes the other way — the menu takes it
    /// even mid-rename — which is the ordinary Mac split and why Delete Layer
    /// keeps it.
    /// The reason is plainer: an unmodified letter in the menu bar is not a
    /// Mac idiom, and X is already taught on the bucket's swap button, which
    /// wears it as a tooltip. X itself lives on an invisible stand-in in the
    /// tool bar, the same idiom the tool letters use, so it answers under
    /// every tool rather than only the one with the swatches.
    @ViewBuilder private var fillRows: some View {
        Button {
            editor?.fillSelectedLayer(useBackground: false)
        } label: {
            Label { Text("Fill with Foreground") } icon: { Self.swatch(editor?.foregroundFillHex) }
        }
        // Not `.delete`: SwiftUI's is U+0008 and AppKit only matches a ⌫ press
        // against U+007F, so `.delete` puts a chord on the row that no
        // keyboard can type. See `DeleteKeyCharacters`.
        .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.backwards), modifiers: .option)
        .disabled(!(editor?.canFillWithFillColors ?? false))
        Button {
            editor?.fillSelectedLayer(useBackground: true)
        } label: {
            Label { Text("Fill with Background") } icon: { Self.swatch(editor?.backgroundFillHex) }
        }
        .disabled(!(editor?.canFillWithFillColors ?? false))
        Button("Swap Fill Colors") { editor?.swapFillColors() }
            .disabled(editor == nil)
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

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") { coordinator.showAbout() }
            Button("Open Source Notices…") { coordinator.showOpenSourceNotices() }
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
            Button("Save") { focusedSave?.editor.performSave { _ in } }
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
            // One Export command for both editors: a picture and a recording
            // leave the app through the same sheet and the same key.
            Button("Export…") {
                if editor?.document != nil { editor?.isExportDialogPresented = true }
                else if let video, Experiments.shared.recordingExportSheetEnabled {
                    video.isExportSheetPresented = true
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(editor?.document == nil && !(offersRecordingExportSheet(video)))
            // Copy Merged took this key and moved next to Copy in Edit, where
            // the difference between the two copies is readable. Off, the
            // picture-of-everything copy stays here as Copy Image.
            if !Experiments.shared.copyPicksYourLayerEnabled {
                Button("Copy Image") { editor?.copyCompositeToClipboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(editor?.document == nil)
            }
        }

        CommandMenu("Capture") {
            // The same shortcuts are registered as global Carbon hotkeys
            // (CaptureCenter) on the resident agent; these menu items make them
            // discoverable and clickable, and work with no editor window open.
            // ⇧⌘3/⇧⌘4 only reach us once the system Screenshots shortcuts are
            // disabled in System Settings.
            // Same names and order as the menu bar menu (MenuBarMenu), so a
            // command learned in one menu is found in the other.
            Button(CaptureMenuNames.captureRegion) { coordinator.capture.beginRectCapture() }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Button(CaptureMenuNames.captureFullScreen) { coordinator.capture.captureFullScreen() }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Button(CaptureMenuNames.recording(isRecording: coordinator.capture.isRecording)) {
                coordinator.capture.toggleRecording()
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
            Divider()
            Button(CaptureMenuNames.editLastCapture) { coordinator.editLastCapture() }
                .keyboardShortcut("6", modifiers: [.command, .shift])
                .disabled(coordinator.lastCapture == nil)
            // A setting, so one name and a checkmark rather than a title that
            // rewrites itself. The checkmark is also written straight onto the
            // live item whenever history opens or closes (MainMenuState):
            // SwiftUI re-runs this body only while handling an event, and ⇧⌘H
            // rebuilds it from the state before the toggle ran, which left the
            // menu a step behind.
            Toggle(CaptureMenuNames.history, isOn: Binding(
                get: { coordinator.isHistoryShown },
                set: { _ in coordinator.toggleHistory() }))
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
            if Experiments.shared.cutRecordingEnabled {
                // One key, one meaning, two places it can land. A recording
                // that opens as a DOCUMENT is cut on the timeline
                // (`EditorState+ClipBar`); the old recording window is still
                // cut on its strip until it retires. Nothing here is a second
                // way to do the same thing: they are the same command reaching
                // whichever surface is in front of you.
                let onTimeline = editor?.documentHasTime ?? false
                Button("Split at Playhead") {
                    onTimeline ? editor?.splitClipAtPlayhead() : video?.cutAtPlayhead()
                }
                .keyboardShortcut("b", modifiers: [])
                .disabled(!(onTimeline ? (editor?.canSplitClipAtPlayhead ?? false)
                                       : (video?.canCutAtPlayhead ?? false)))
                // Keys picked on a lane are the smaller and more recent thing
                // in hand, so ⌫ takes those and leaves the clip alone
                // (`EditorState+KeyLanes`).
                let keysPicked = onTimeline && (editor?.canDeletePickedKeys ?? false)
                Button(keysPicked ? "Delete Keys" : "Delete This Piece") {
                    if keysPicked {
                        editor?.deletePickedKeys()
                    } else {
                        onTimeline ? editor?.deleteClipPieceInHand() : video?.deleteSelectedPiece()
                    }
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
                .disabled(!(keysPicked || (onTimeline ? (editor?.canDeleteClipPieceInHand ?? false)
                                                      : (video?.canDeleteSelectedPiece ?? false))))
                // Premiere's Ripple Delete, on its Mac key: what is picked goes
                // and everything after it pulls back to close the gap, so a
                // title stays over the frame it was put on
                // (`EditorState+TimelineMenus`).
                if onTimeline {
                    Button("Ripple Delete") { editor?.rippleDeleteInHand() }
                        .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuKeyEquivalent), modifiers: .option)
                        .disabled(!(editor?.canRippleDeleteInHand ?? false))
                    // Premiere's Add Edit to All Tracks.
                    Button("Split Everything at Playhead") {
                        if let editor { editor.splitEverything(atMS: editor.documentTimeMS) }
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(!(editor?.canSplitEverythingAtPlayhead ?? false))
                }
                // A freeze is not a special object: it is a piece whose in and
                // out are the same frame, so it drops onto the timeline like
                // any other piece and can be moved, lengthened and thrown away
                // like any other piece (`video-freeze-wt`).
                // No key: ⇧F walks the Frame slot, ⌥F fills the flow, and a
                // freeze is a thing you do once in a cut rather than forty
                // times. The row is where you would look for it.
                Button("Freeze Frame") { editor?.holdFrameAtPlayhead() }
                    .disabled(!(editor?.canHoldFrameAtPlayhead ?? false))
                // Retiming is a property of the piece you are on, so it is a
                // list of speeds rather than a surface of its own
                // (`video-speed`). Its sound goes with it, at the same rate.
                Menu("Speed") {
                    ForEach(EditorState.clipSpeeds, id: \.self) { percent in
                        Button(ClipSpeed.title(percent)) {
                            editor?.setClipSpeedInHand(percent)
                        }
                        .disabled(!(editor?.canSetClipSpeed(percent) ?? false))
                    }
                }
                .disabled(editor?.clipSpeedInHand == nil)
                Divider()
            }
            // The ruler's marks, at the playhead. The same rows the ruler's
            // right click offers there; M, I and O stay Photoshop's tool keys
            // until the timeline owns the keyboard, so only Clear carries one.
            if editor?.documentHasTime ?? false {
                Button("Add Marker") { if let editor { editor.addMarker(atMS: editor.documentTimeMS) } }
                Button("Set In") { if let editor { editor.setMarkIn(atMS: editor.documentTimeMS) } }
                Button("Set Out") { if let editor { editor.setMarkOut(atMS: editor.documentTimeMS) } }
                Button("Clear In and Out") { editor?.clearMarkInOut() }
                    .keyboardShortcut("x", modifiers: .option)
                    .disabled(!(editor?.canClearMarkInOut ?? false))
                Divider()
            }
            // Where the camera is pointed, and where it goes next
            // (`ClipReframe.swift`). Both rows act on the clip in hand at the
            // playhead, so a punch-in costs no aiming beyond the box you drew
            // on the picture. ⇧Z is the clickthrough's own key.
            if Experiments.shared.punchInEnabled {
                Button("Punch In") { editor?.punchInOnRegion() }
                    .keyboardShortcut("z", modifiers: [.shift])
                    .disabled(!(editor?.canPunchIn ?? false))
                Button("Pull Back Out") { editor?.pullReframeBackOut() }
                    .keyboardShortcut("z", modifiers: [.shift, .option])
                    .disabled(!(editor?.canPullBackOut ?? false))
                Button("Reset Reframe") { editor?.resetReframeInHand() }
                    .disabled(!(editor?.canResetReframe ?? false))
                Divider()
            }
            // What happens at a CUT (`docs/design/video-transitions.md`). The
            // menu acts on the cut in hand — the one picked, else the one the
            // playhead is standing on — so putting a dissolve on the join you
            // are looking at costs no aiming. Every one of these is also a
            // click on the band in the timeline; this is the way in that can be
            // found by reading.
            if Experiments.shared.transitionsAtACutEnabled {
                Menu("Transition at Cut") {
                    Button("Hard Cut") { editor?.setClipTransitionInHand(nil) }
                        .disabled(editor?.cutInHand?.cut.transition == nil)
                    Divider()
                    ForEach(ClipTransitionKind.allCases, id: \.self) { kind in
                        Button(kind.title) { editor?.setClipTransitionInHand(kind) }
                            .disabled(!(editor?.cutInHand?.cut.canAfford(kind) ?? false))
                    }
                }
                .disabled(!(editor?.canWorkWithClipTransitions ?? false)
                          || editor?.cutInHand == nil)
                Divider()
            }
            // Sound rides the same time axis as the picture, so there is no
            // mixer window and no audio mode: these four rows are the whole of
            // it, and everything else a piece of sound needs — cut it, move it,
            // name it, switch it off, undo any of it — is what the timeline
            // already does to a layer (`docs/design/video-audio.md`).
            if Experiments.shared.soundOnTheTimelineEnabled {
                // ⌃⇧D, the key the cut clickthrough's command menu prints for
                // it (`video-cut-wt`): two modifiers away from ⌘D, so not a key
                // anybody presses by accident on a take they have already cut.
                Button("Detach Audio") { editor?.detachSound() }
                    .keyboardShortcut("d", modifiers: [.control, .shift])
                    .disabled(!(editor?.canDetachSound ?? false))
                Button("Add Sound…") { editor?.addSoundFromFile() }
                    .disabled(!(editor?.documentHasTime ?? false))
                Button("Flatten Level") { editor?.clearSoundLevelPoints() }
                    .disabled((editor?.soundLevelInHand.points.isEmpty ?? true))
                Button("Export Sound…") { editor?.exportSound() }
                    .disabled(!(editor?.documentHasAudio ?? false))
                Divider()
            }
            // Captions are what the Title / Text tool does when the document
            // has time, so they live here beside the sound they are written
            // from rather than in a caption menu
            // (`docs/design/mocks/pages/video-captions.html`).
            if Experiments.shared.captionsFromTheSoundEnabled {
                if editor?.isWritingCaptions == true {
                    Button("Stop Writing Captions") { editor?.stopWritingCaptions() }
                } else {
                    Button("Write Captions") { editor?.writeCaptions() }
                        .disabled(!(editor?.canWriteCaptions ?? false))
                }
                Button("Captions Later") {
                    editor?.nudgeCaptions(byMS: EditorState.captionNudgeMS)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
                .disabled(!(editor?.canNudgeCaptions ?? false))
                Button("Captions Earlier") {
                    editor?.nudgeCaptions(byMS: -EditorState.captionNudgeMS)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
                .disabled(!(editor?.canNudgeCaptions ?? false))
                Button("Clear Captions") { editor?.clearCaptions() }
                    .disabled(!(editor?.canClearCaptions ?? false))
                Button("Export Captions…") { editor?.exportCaptions() }
                    .disabled(!(editor?.canExportCaptions ?? false))
                Divider()
            }
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
            // Photoshop ⇧⌘C, and Photoshop's place for it: directly under
            // Copy, so the one that takes the layer you picked and the one
            // that takes everything read as a pair.
            if Experiments.shared.copyPicksYourLayerEnabled {
                Button("Copy Merged") { editor?.copyMerged() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(editor?.document == nil)
            }
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
            Divider()
            fillRows
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
            // with no marquee — duplicate the selected layer. Which pixels the
            // marquee takes follows the copy rule (`newLayerViaCopy`): the
            // layer you picked when you picked one, everything flattened
            // together when you did not.
            Button("New Layer via Copy") { editor?.newLayerViaCopy() }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(editor?.selection == nil && !hasLayerSelection)
            // Photoshop ⇧⌘J, and its twin: the same command with the piece
            // TAKEN rather than copied, and the space it came from filled in
            // from what was around it (`newLayerViaCut`). Directly under the
            // copy row it is the sibling of, so the pair reads as a pair.
            if Experiments.shared.newLayerViaCutEnabled {
                Button("New Layer via Cut") { editor?.newLayerViaCut() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                    .disabled(!(editor?.canCutSelectionToLayer ?? false))
            }
            Button("Blur Behind Selection") { editor?.blurBehindSelection() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(editor?.selection == nil)
            Divider()
            // No shortcut (Photoshop parity: ⌘D is Deselect; ⌘J covers the
            // duplicate-selected-layer case when no region is marqueed).
            Button("Duplicate Layer") { editor?.duplicateSelectedLayers() }
                .disabled(!hasLayerSelection)
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
                Button("Copy Look") { editor?.copyLook() }
                    .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                    .disabled(!(editor?.canCopyLook ?? false))
                Button("Paste Look") { editor?.pasteLook() }
                    .keyboardShortcut("v", modifiers: [.command, .option, .shift])
                    .disabled(!(editor?.canPasteLook ?? false))
            }
            Button("Merge Down") { editor?.mergeDown() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!(editor?.canMergeDown ?? false))
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
                    editor?.turnSelectionIntoPath()
                }
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
                        Button(operation.title) { editor?.combineSelection(operation) }
                    }
                }
                .disabled(!(editor?.canCombineSelection ?? false))
            }
            // The one command that makes a shape or a piece of text into pixels,
            // which is what a marquee needs before it can cut a piece out of it
            // (`RasterizePrompt`, `RegionSliceRefusal`). Named the way the
            // refusal pill names it, not the way Photoshop does.
            Button(RasterizePrompt.menuItem) {
                editor?.rasterizeSelection()
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
                    if let selectedID { editor?.separateIntoLayers(id: selectedID) }
                }
                .disabled(!(selectedID.map { editor?.canSeparateIntoLayers(id: $0) ?? false } ?? false))
                // The step after it, in the same two places, under the same
                // name: a picture of a run of text becomes words you can
                // retype.
                // Over everything picked, like Turn Into Picture above it, and
                // over the whole group a big separation arrives in.
                Button("Turn into Text") { editor?.turnIntoTextForSelection() }
                .disabled(!(editor?.canTurnIntoTextSelection ?? false))
            }
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
                Button("Bring into View") { editor?.bringSelectionIntoView() }
                    .disabled(!(editor?.canBringSelectionIntoView ?? false))
                let fill = editor?.flowFillCommand ?? .none
                Toggle(fill.title, isOn: Binding(get: { fill.isOn },
                                                 set: { _ in editor?.toggleFillsTheFlow() }))
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
                                     set: { _ in editor?.toggleSurface() }))
                .disabled(!surface.isEnabled)
                .help(surface.help)
                // The same step out of the line, the opposite depth: out, and
                // in FRONT, which is where a badge on the corner of a card
                // lives (`FloatingPiece.swift`). Directly under the surface so
                // the pair reads as one idea with two directions, and a tick
                // for the same reason the row above has one.
                Toggle(FloatingCommand.menuTitle,
                       isOn: Binding(get: { surface.isFloating },
                                     set: { _ in editor?.toggleFloating() }))
                .disabled(!surface.isEnabled)
                .help(surface.reason ?? FloatingCommand.reason)
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
                    set: { _ in editor?.toggleFrameColumns() }))
                .disabled(editor?.columnsTargetFrameID == nil)
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
                // Add Variant takes no key either: it is a thing you do once
                // per look, from the original's own Properties list, and a key
                // for it would be a key nobody could name.
                Button(editor?.selectedComponentVariantWording.addCommand ?? "Add Variant") {
                    editor?.addComponentVersion()
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
                    Button(title) { editor?.applyToOtherComponentVersions() }
                        .disabled(!(editor?.canApplyToOtherComponentVersions ?? false))
                }
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
            // Off while everything picked is locked: the lock is a promise the
            // menu keeps out loud, so the row says no before the press rather
            // than the layer disappearing under one.
            Button("Delete Layer") { editor?.deleteSelectedLayers() }
                // U+007F rather than SwiftUI's `.delete`, which is the
                // backspace control character no keyboard sends. See
                // `DeleteKeyCharacters`.
                .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.backwards), modifiers: .command)
                .disabled(!(editor?.canDeleteSelectedLayers ?? false))
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
                // ⌃⌘C: the copy family's free chord. ⇧⌘C is Copy Merged,
                // ⌥⌘C is Canvas Size and ⌥⇧⌘C is Content-Aware Scale, all
                // Photoshop keys.
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

        viewAndHelpCommands
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

        CommandGroup(after: .sidebar) {
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
                    get: { editor?.isLibraryVisible ?? false },
                    set: { _ in
                        if let editor { editor.setLibraryVisible(!editor.isLibraryVisible) }
                    }))
                .disabled(!hasDocument)
            }
            // The timing strip across the bottom (Next, `next-motion-strip`).
            // Next to the panel because it is the same kind of thing: a surface
            // the window can show or put away. Dimmed with nothing moving,
            // because there is no strip for a still picture and a row that
            // would open an empty one is a row that lies.
            if Experiments.shared.motionStripEnabled {
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
            if Experiments.shared.windowModesEnabled {
                Menu(WindowModeCopy.menuTitle) {
                    ForEach(WindowModes.swappable) { mode in
                        Button(mode.title) { WindowModeStore.shared.swap(to: mode.id) }
                            .keyboardShortcut(modeKey(mode.id))
                    }
                    Divider()
                    Button(WindowModeCopy.showEverything) {
                        WindowModeStore.shared.showEverything()
                    }
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
            }
            Divider()
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
}
