import Foundation
import PhotonzCore
import Testing

/// **Every command a person reaches from a menu has a name an agent can run**
/// (`AppCommandTable`, `docs/design/agent-mcp.md` slice 2).
///
/// Three surfaces are counted here, read out of the source:
///
/// * the menu bar: every `Button`, `Toggle` and drawn list of rows in
///   `EditorCommands.swift`. A row is named when its action goes through
///   `run(.someCommand)`, the switch an agent's `run_command` goes through too;
/// * the timeline's right-click rows (`TimelineMenuRow`), by an exhaustive
///   switch below, so a new row does not build until it is placed;
/// * the layer's right-click rows (`LayerCommandMenu.swift`), by title.
///
/// Every other right-click row in the app is a menu bar row under the same or
/// other words (`EveryCommandIsInTheMenuBarTests`), so it is named here through
/// that row.
///
/// A row with no name is either LEFT OUT on purpose, with the reason, or NOT
/// YET named. The not-yet list may only shrink: its size is pinned, so adding a
/// row to it means raising the pin where a reviewer sees it, and naming one
/// means lowering it.
@Suite("Every menu command can be run by name")
struct EveryMenuCommandHasANameTests {

    static var root: URL { EveryCommandIsInTheMenuBarTests.root }

    /// How many menu bar rows are not named yet. Lower it as rows get names;
    /// never raise it to make room for a new row (give that row a name).
    static let notYetPin = 77

    /// A menu bar row: where it is (the `var` it is built in, then the words
    /// or expression its title is), the commands its action runs, and the
    /// whole call for reading its literal titles.
    struct Row {
        let key: String
        let commands: [String]
        let title: Substring
        let line: Int
    }

    // MARK: Reading EditorCommands.swift

    static func skipString(_ s: [Character], _ i: Int) -> Int {
        var i = i + 1
        while i < s.count {
            if s[i] == "\\" { i += 2; continue }
            if s[i] == "\"" { return i }
            i += 1
        }
        return i
    }

    static func close(_ s: [Character], from open: Int, _ o: Character, _ c: Character) -> Int {
        var depth = 0, i = open
        while i < s.count {
            let ch = s[i]
            if ch == "\"" { i = skipString(s, i) } else if ch == o { depth += 1 } else if ch == c {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return s.count - 1
    }

    static func collapsed(_ text: some StringProtocol) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    static func menuBarRows() throws -> [Row] {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Photonz/EditorCommands.swift"),
                                encoding: .utf8)
        let s = Array(source)
        // Where each `var` the rows are built in starts.
        var sections: [(at: Int, name: String)] = []
        var lineStarts: [Int] = [0]
        for (index, ch) in s.enumerated() where ch == "\n" { lineStarts.append(index + 1) }
        for start in lineStarts {
            let line = String(s[start..<min(s.count, start + 120)].prefix { $0 != "\n" })
            if let match = line.firstMatch(of: /^    (?:@\w+ )*(?:private )?var (\w+)/) {
                sections.append((start, String(match.output.1)))
            }
        }
        func section(_ at: Int) -> String { sections.last { $0.at < at }?.name ?? "?" }
        func lineNumber(_ at: Int) -> Int { (lineStarts.lastIndex { $0 <= at } ?? 0) + 1 }
        func commands(in text: String) -> [String] {
            text.matches(of: /run\(\s*(?:AppCommandCall\()?\.(\w+)/).map { String($0.output.1) }
        }

        var rows: [Row] = []
        var i = 0
        while i < s.count {
            // `Button(`, `Toggle(` and `Button {` not inside a longer name.
            var callee: String?
            for name in ["Button", "Toggle"] where i + name.count < s.count
                && String(s[i..<i + name.count]) == name {
                let before = i > 0 ? s[i - 1] : " "
                if before.isLetter || before.isNumber || before == "_" || before == "." { continue }
                let after = s[i + name.count]
                if after == "(" || (name == "Button" && after == " " && i + name.count + 1 < s.count
                                    && s[i + name.count + 1] == "{") {
                    callee = name
                }
            }
            guard let callee else { i += 1; continue }
            let open = i + callee.count
            if s[open] == "(" {
                let end = close(s, from: open, "(", ")")
                var depth = 0, j = open + 1, firstEnd = end
                while j < end {
                    let ch = s[j]
                    if ch == "\"" { j = skipString(s, j) } else if "([{".contains(ch) { depth += 1 }
                    else if ")]}".contains(ch) { depth -= 1 }
                    else if ch == ",", depth == 0 { firstEnd = j; break }
                    j += 1
                }
                var k = end + 1
                while k < s.count, " \t\n".contains(s[k]) { k += 1 }
                let callEnd = k < s.count && s[k] == "{" ? close(s, from: k, "{", "}") : end
                let text = String(s[i...callEnd])
                rows.append(Row(key: "\(section(i)): \(collapsed(String(s[(open + 1)..<firstEnd])))",
                                commands: commands(in: text), title: Substring(String(s[(open + 1)..<firstEnd])),
                                line: lineNumber(i)))
                i = callEnd + 1
            } else {
                // `Button { action } label: { ... Text("words") ... }`
                let actionOpen = open + 1
                let actionEnd = close(s, from: actionOpen, "{", "}")
                var k = actionEnd + 1
                while k < s.count, s[k] != "{" { k += 1 }
                let labelEnd = close(s, from: k, "{", "}")
                let label = String(s[k...labelEnd])
                let words = label.firstMatch(of: /Text\("([^"]*)"\)/).map { String($0.output.1) } ?? "?"
                rows.append(Row(key: "\(section(i)): \"\(words)\"",
                                commands: commands(in: String(s[i...labelEnd])), title: Substring("\"\(words)\""),
                                line: lineNumber(i)))
                i = labelEnd + 1
            }
        }
        // Rows drawn from a list the app builds (`MenuRowsView`).
        for match in source.matches(of: /MenuRowsView\(rows:\s*([^)]*\))/) {
            let at = source.distance(from: source.startIndex, to: match.range.lowerBound)
            rows.append(Row(key: "\(section(at)): MenuRowsView \(collapsed(match.output.1))", commands: [],
                            title: "", line: lineNumber(at)))
        }
        return rows
    }

    // MARK: The lists

    static let leftOut: [String: String] = [
        "tutorialMenu: row.title":
            "starts a guided tutorial, which is for a person learning the app",
        "openRecentMenu: title":
            "the person's own recent files; open_document opens any file by path",
        "openRecentMenu: \"Clear Menu\"":
            "the person's own recent files; open_document opens any file by path",
        "body: \"About \\(AppInfo.name)\"":
            "a window about the app itself, not a document: an agent works in documents",
        "body: \"Open Source Notices…\"":
            "a window about the app itself, not a document: an agent works in documents",
        "body: \"Check for Updates…\"":
            "a window about the app itself, not a document: an agent works in documents",
        "body: \"Experiments…\"":
            "a window about the app itself, not a document: an agent works in documents",
        "body: \"New Window\"":
            "an empty window waiting for a person to drop something in",
        "body: \"Open…\"":
            "a file panel for a person; open_document opens a file by path",
        "body: \"Save As…\"":
            "asks for a place in a save panel; export writes to a path (slices 3 and 4)",
        "body: \"Export…\"":
            "asks for a place in a save panel; export writes to a path (slices 3 and 4)",
        "body: \"Undo\"":
            "an agent has undo and redo tools of their own",
        "body: \"Redo\"":
            "an agent has undo and redo tools of their own",
        "captureRows: CaptureMenuNames.captureRegion":
            "captures the screen, which needs a person at the Mac and the Screen Recording grant; open_document opens what History holds",
        "captureRows: CaptureMenuNames.captureFullScreen":
            "captures the screen, which needs a person at the Mac and the Screen Recording grant; open_document opens what History holds",
        "captureRows: CaptureMenuNames.recording(isRecording: coordinator.capture.isRecording)":
            "captures the screen, which needs a person at the Mac and the Screen Recording grant; open_document opens what History holds",
        "captureRows: CaptureMenuNames.editLastCapture":
            "captures the screen, which needs a person at the Mac and the Screen Recording grant; open_document opens what History holds",
        "historyToggle: CaptureMenuNames.history":
            "shows the History strip; list_history reads it",
        "screenRecordingAccessRow: \"Request Screen Recording Access…\"":
            "asks the person for a system permission",
        "freezeAndSpeedRows: \"Change Speed\\u{2026}\"":
            "opens the panel's Time section for a person; set_speed sets the speed",
        "toolsMenu: tool.barTitle(onVideoBar: editor?.hasVideoToolBar ?? false)":
            "picks up a tool for the pointer; an agent works through commands, not a pointer",
        "toolsMenu: \"Blade\"":
            "picks up a tool for the pointer; an agent works through commands, not a pointer",
        "clipItselfRows: \"Reveal in Finder\"":
            "shows the file in Finder, outside the app",
        "placedLayerRows: TitleTime.fadeTitle(ms)":
            "shown only with picture fades switched off; at Next's defaults Fade In and Fade Out are set_fade",
        "videoMenu: (video?.isPlaying ?? false) ? \"Pause\" : \"Play\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: \"Set Trim Start to Playhead\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: \"Set Trim End to Playhead\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: (video?.isCropping ?? false) ? \"Finish Crop\" : \"Crop to Region\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: \"Reset Crop\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: \"Revert to Original\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: \"Export…\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: \"Export MP4…\"":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "recordingWindowRows: quality.label":
            "the small recording window, which only Current still opens; Next edits a recording on the timeline",
        "layerMenu: MotionPivot.PlaceOnCanvas.menuBarTitle":
            "places a point by pointing at the canvas",
        "layerMenu: ExactPlacement.menuItem":
            "opens fields for a person to type a position and size into; set_layer sets them (slice 3)",
        "layerMenu: \"Show Transform Values\"":
            "a readout for a person; read_document gives the values",
        "measureMenu: \"Measure Tool\"":
            "picks up a tool for the pointer; an agent works through commands, not a pointer",
        "viewAndHelpCommands: SettingsWindowModel.menuItem":
            "a window about the app itself, not a document: an agent works in documents",
        "viewAndHelpCommands: TutorialMenuModel.hubRowTitle":
            "starts a guided tutorial, which is for a person learning the app",
        "viewMenuRows: MenuToggleNames.panel":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: MenuToggleNames.library":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: mode.menuTitle":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: MenuToggleNames.timeline":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: MenuToggleNames.timingStrip":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: mode.title":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: WindowModeCopy.showEverything":
            "how the window is laid out for a person; it changes nothing in the document",
        "viewMenuRows: \"Show Camera Settings\"":
            "opens a panel for a person",
        "viewMenuRows: MenuToggleNames.grid":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: CanvasGridCopy.settingsMenuItem":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: MenuToggleNames.snapToGrid":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: CanvasGridCopy.adjustMenuItem":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: MenuToggleNames.iconKeylines":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: MenuToggleNames.iconSnapGrid":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: MenuToggleNames.iconSnapKeylines":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: MenuToggleNames.iconSnapGeometry":
            "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "viewMenuRows: PlayerFullScreen.menuTitle(isFullScreen: editor?.isWindowFullScreen ?? false)":
            "how the window is laid out for a person; it changes nothing in the document",
    ]

    static let notYet: [String: String] = [
        "body: \"New Blank Canvas…\"":
            "a new document of a given size: new_picture and new_video (slices 3 and 4)",
        "body: \"New Video…\"":
            "a new document of a given size: new_picture and new_video (slices 3 and 4)",
        "body: UIStarter.menuTitle":
            "a new document of a given size: new_picture and new_video (slices 3 and 4)",
        "body: \"New from Clipboard\"":
            "a new document of a given size: new_picture and new_video (slices 3 and 4)",
        "body: \"Import Media…\"":
            "a file panel; add_clip takes a path (slice 4)",
        "body: \"Save\"":
            "save_document, saving to the document's own file",
        "body: \"Save to Capture History\"":
            "a command that files the picture in History",
        "body: \"Copy Image\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Cut\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Copy\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Copy Merged\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Copy SVG\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Copy Video\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Copy as GIF\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "body: \"Paste\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "imageMenu: \"Resize Image…\"":
            "a dialog of sizes; needs a command that takes the new size",
        "imageMenu: \"Canvas Size…\"":
            "a dialog of sizes; needs a command that takes the new size",
        "freezeAndSpeedRows: \"Freeze Frame\\u{2026}\"":
            "asks how long in a popover; needs a command that takes the length",
        "animateRows: curve.title":
            "acts on keys or stretches picked on a lane, which an agent cannot pick yet",
        "animateRows: \"Draw a Curve\\u{2026}\"":
            "acts on keys or stretches picked on a lane, which an agent cannot pick yet",
        "animateRows: \"Copy Ease\"":
            "acts on keys or stretches picked on a lane, which an agent cannot pick yet",
        "animateRows: \"Paste Ease\"":
            "acts on keys or stretches picked on a lane, which an agent cannot pick yet",
        "addMediaRow: \"Add Media at Playhead…\"":
            "a file panel; add_clip takes a path (slice 4)",
        "saveTitlePresetRow: \"Save as Preset…\"":
            "asks for a name; needs a command that takes it",
        "exportSoundRow: \"Export Sound…\"":
            "a save panel; export writes to a path (slice 4)",
        "captionRows: \"Export Captions as SRT…\"":
            "a save panel; export writes to a path (slice 4)",
        "captionRows: \"Export Captions as WebVTT…\"":
            "a save panel; export writes to a path (slice 4)",
        "layerListRows: \"Rename Layer…\"":
            "opens the name for typing in place; needs a command that takes the new name",
        "effectRows: kind.title":
            "effects: needs commands that add and remove an effect by name",
        "effectRows: style.name":
            "effects: needs commands that add and remove an effect by name",
        "effectRows: row.title":
            "effects: needs commands that add and remove an effect by name",
        "clipItselfRows: \"Rename…\"":
            "opens the name for typing in place; needs a command that takes the new name",
        "clipItselfRows: \"Add Click at Playhead\\u{2026}\"":
            "places a click by pointing at the canvas; needs a command that takes the point",
        "clipItselfRows: \"Follow Cursor\"":
            "acts on a zoom picked on its lane, which an agent cannot pick yet",
        "clipItselfRows: \"\\(stop)%\"":
            "acts on a zoom picked on its lane, which an agent cannot pick yet",
        "clipItselfRows: \"Delete Zoom\"":
            "acts on a zoom picked on its lane, which an agent cannot pick yet",
        "keyLaneRows: \"Show Graph\"":
            "acts on keys or stretches picked on a lane, which an agent cannot pick yet",
        "keyLaneRows: \"Stop Animating\"":
            "acts on a property picked on a lane, which an agent cannot pick yet",
        "straightenRow: \"Straighten This Stretch\"":
            "acts on keys or stretches picked on a lane, which an agent cannot pick yet",
        "rangeRows: \"Export Range…\"":
            "a save panel; export writes to a path (slice 4)",
        "trackMenu: \"Rename Track…\"":
            "opens the name for typing in place; needs a command that takes the new name",
        "captionEditRows: \"Edit Word\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Split Here\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Merge with Next\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Delete Word\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Move to Previous Line\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Move to Next Line\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Join with Next Line\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Play from Here\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "captionEditRows: \"Start Here\"":
            "acts on a caption word picked on the canvas or the timeline, which an agent cannot pick yet",
        "layerMenu: style.title":
            "arrows: drawing comes with slice 3",
        "layerMenu: ArrowStyle.reshuffleTitle":
            "arrows: drawing comes with slice 3",
        "layerMenu: ArrowBend.straightenTitle":
            "arrows: drawing comes with slice 3",
        "layerMenu: editor?.turnSelectionIntoPathMenuItem ?? TurnIntoPathPrompt.menuItem":
            "needs a command of its own",
        "layerMenu: EditorState.putTextOnPathTitle":
            "needs a command of its own",
        "layerMenu: RasterizePrompt.menuItem":
            "needs a command of its own",
        "layerMenu: \"Bring into View\"":
            "needs a command of its own",
        "layerMenu: fill.title":
            "needs a command of its own",
        "layerMenu: SurfaceCommand.menuTitle":
            "needs a command of its own",
        "layerMenu: FloatingCommand.menuTitle":
            "needs a command of its own",
        "layerMenu: \"New Frame…\"":
            "needs a command of its own",
        "layerMenu: FrameColumnsCopy.menuItem":
            "needs a command of its own",
        "layerMenu: \"Insert Component\"":
            "needs a command of its own",
        "layerMenu: editor?.selectedComponentVariantWording.addCommand ?? \"Add Variant\"":
            "needs a command of its own",
        "layerMenu: title":
            "needs a command of its own",
        "layerMenu: \"Make Alternatives\"":
            "needs a command of its own",
        "layerMenu: OriginalSpaceCopy.menuEdit":
            "needs a command of its own",
        "layerMenu: OriginalSpaceCopy.menuDone":
            "needs a command of its own",
        "layerMenu: \"Reset 3D Rotation\"":
            "needs a command of its own",
        "layerMenu: \"Bring Nearer\"":
            "needs a command of its own",
        "layerMenu: \"Send Further\"":
            "needs a command of its own",
        "measureMenu: \"Copy as Spec List\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "measureMenu: selectedCount > 1 ? \"Copy Measurements\" : \"Copy Measurement\"":
            "the clipboard: these rows also act on a text field being typed in, so their commands must say which",
        "viewMenuRows: \"Reset Camera\"":
            "needs a command of its own",
        "insertTitleRows: MenuRowsView editor.titlePresetRows(kind)":
            "the title presets, one row each: add_title (slice 4)",
        "animatePropertyRows: MenuRowsView inner)":
            "acts on a property picked on a lane, which an agent cannot pick yet",
        "rangeRows: MenuRowsView editor?.rangeSectionMenuBarRows()":
            "acts on a clip picked under a range, which an agent cannot pick yet",
    ]

    // MARK: The timeline's right-click rows

    /// What each timeline right-click row is to an agent. Exhaustive, so a
    /// new row does not build until it is placed.
    enum Reach: Equatable {
        /// Runs this command, after picking what the row was opened on.
        case command(AppCommandID)
        /// A submenu: its rows are counted one by one.
        case holds
        case leftOut(String)
        case notYet(String)
    }

    static func reach(_ row: TimelineMenuRow) -> Reach {
        switch row {
        case .split: .command(.splitAtPlayhead)
        case .freezeFrame: .notYet("asks how long in a popover")
        case .speed: .command(.setSpeed)
        case .startAtPlayhead: .command(.startAtPlayhead)
        case .endAtPlayhead: .command(.endAtPlayhead)
        case .addTransition: .command(.setTransition)
        case .detachAudio: .command(.detachAudio)
        case .audio, .more, .track, .captionsTrack, .trackRows: .holds
        case .normalize: .command(.normalizeLoudness)
        case .cleanNoise: .command(.cleanNoise)
        case .resetGain: .command(.resetGain)
        case .animateIn: .command(.animateIn)
        case .animateOut: .command(.animateOut)
        case .cut, .copy, .pasteKeys, .copyTransition, .pasteTransition, .pasteHere:
            .notYet("the clipboard")
        case .delete: .command(.delete)
        case .rippleDelete: .command(.rippleDelete)
        case .showPicture: .command(.showPicture)
        case .rippleTrimStart: .command(.rippleTrimStart)
        case .rippleTrimEnd: .command(.rippleTrimEnd)
        case .fadeIn, .fadeOut: .command(.setFade)
        case .punchIn: .command(.punchIn)
        case .addZoom: .command(.addZoom)
        case .suggestZooms: .command(.suggestZooms)
        case .addClick: .notYet("places a click by pointing at the canvas")
        case .animate: .notYet("the properties to animate, a list built from the layer")
        case .addKey: .command(.keyAtPlayhead)
        case .breakApart: .command(.breakApart)
        case .replayTitle: .command(.replayTitle)
        case .saveAsPreset: .notYet("asks for a name")
        case .addCaptions: .command(.addCaptions)
        case .selectForward: .command(.selectForward)
        case .duplicate: .command(.duplicateLayer)
        case .rename, .editWords: .notYet("opens the words for typing in place")
        case .revealInFinder: .leftOut("shows the file in Finder, outside the app")
        case .joinWithNextLine, .startHere: .notYet("acts on a caption word, which an agent cannot pick yet")
        case .followCursor, .zoomAmount, .deleteZoom: .notYet("acts on a zoom, which an agent cannot pick yet")
        case .applyDefaultTransition: .command(.applyDefaultTransition)
        case .transitionLength: .command(.setTransitionLength)
        case .transitionCurve: .command(.setTransitionCurve)
        case .removeTransition: .command(.hardCut)
        case .rollEdit: .command(.rollEditToPlayhead)
        case .joinThroughEdit: .command(.joinThroughEdit)
        case .expandCut: .command(.expandCut)
        case .closeGap: .notYet("acts on a gap, which an agent cannot pick yet")
        case .addTitlePage, .addNameCard: .notYet("the title presets: add_title (slice 4)")
        case .addText, .addRectangle: .notYet("draws with a tool: add_text and add_shape (slice 3)")
        case .putLayerHere: .command(.putOnTimeline)
        case .zoomToFit: .command(.zoomTimelineToFit)
        case .compactTracks: .command(.compactTracks)
        }
    }

    // MARK: The layer's right-click rows

    /// A layer right-click row whose words are not its command's title.
    static let layerAliases: [String: AppCommandID] = [
        "\"Duplicate\"": .duplicateLayer,
        "\"Delete\"": .deleteLayer,
        "operation.title": .combineShapes,
    ]

    static let layerNotYet: [String: String] = [
        "\"Copy SVG\"": "the clipboard",
        "editorState.turnIntoPathMenuItem(id: id)": "needs a command of its own",
        "EditorState.putTextOnPathTitle": "needs a command of its own",
        "RasterizePrompt.menuItem": "asks first; needs a command of its own",
        "\"Reset 3D Rotation\"": "needs a command of its own",
        "\"Bring Nearer\"": "needs a command of its own",
        "\"Send Further\"": "needs a command of its own",
        "\"Bring into View\"": "needs a command of its own",
        "\"Make \\(container) Fit\"": "needs a command of its own",
        "\"Rename\"": "opens the name for typing in place",
        "OriginalSpaceCopy.menuEdit": "needs a command of its own",
        "editorState.selectedComponentVariantWording.addCommand": "needs a command of its own",
        "title": "needs a command of its own",
        "MenuToggleNames.layerVisible": "showing and hiding a layer: set_layer (slice 3)",
        "MenuToggleNames.layerLocked": "locking a layer: set_layer (slice 3)",
    ]

    static let layerLeftOut: [String: String] = [
        "ExactPlacement.menuItem": "opens fields for a person to type a position and size into",
    ]

    static func layerRows() throws -> [String] {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Photonz/LayerCommandMenu.swift"),
                                encoding: .utf8)
        return [".command", ".toggle", ".submenu"].flatMap { callee in
            EveryCommandIsInTheMenuBarTests.firstArguments(of: callee, in: source[...]).map { collapsed($0) }
        }.filter { !$0.hasPrefix("\"j\"") && !$0.hasPrefix("\"d\"") && !$0.hasPrefix("\"e\"")
                   && !$0.hasPrefix("\"g\"") && !$0.hasPrefix("\"]\"") && !$0.hasPrefix("\"[\"") }
    }

    /// The command whose title (or other words) a row says.
    static func command(titled words: String) -> AppCommand? {
        AppCommandTable.all.first { $0.titles.contains(words) }
    }

    // MARK: The checks

    @Test("Every menu bar row runs a named command, or says why it does not")
    func everyMenuBarRowIsNamed() throws {
        let rows = try Self.menuBarRows()
        #expect(rows.count > 250, "the source reader found only \(rows.count) rows")
        for row in rows where row.commands.isEmpty {
            if Self.leftOut[row.key] != nil || Self.notYet[row.key] != nil { continue }
            Issue.record("""
                EditorCommands.swift:\(row.line) \(row.key) runs no named command. Give it one in \
                AppCommandTable and run it with editor?.run(.name), or say why in leftOut.
                """)
        }
    }

    @Test("A named row runs a command in the table, and wears that command's words")
    func namedRowsMatchTheTable() throws {
        for row in try Self.menuBarRows() where !row.commands.isEmpty {
            for name in row.commands {
                guard let id = AppCommandID.allCases.first(where: { "\($0)" == name }),
                      let command = AppCommandTable.command(id) else {
                    Issue.record("EditorCommands.swift:\(row.line) runs .\(name), which is not in the table")
                    continue
                }
                let words = EveryCommandIsInTheMenuBarTests.literals(in: row.title)
                if words.isEmpty { continue }
                #expect(words.contains { command.titles.contains($0) },
                        "EditorCommands.swift:\(row.line) says \(words) but runs \(command.name), titled \(command.titles)")
            }
        }
    }

    @Test("Every command in the table is reached by a menu bar row")
    func everyCommandHasARow() throws {
        let reached = Set(try Self.menuBarRows().flatMap(\.commands))
        for id in AppCommandID.allCases {
            #expect(reached.contains("\(id)"), "\(id.rawValue) is in the table but no menu bar row runs it")
        }
    }

    @Test("The lists name only rows that still exist, so they cannot go stale")
    func listsAreLive() throws {
        let unnamed = Set(try Self.menuBarRows().filter { $0.commands.isEmpty }.map(\.key))
        for key in Array(Self.leftOut.keys) + Array(Self.notYet.keys) {
            #expect(unnamed.contains(key), "\(key) is no longer an unnamed row; take it off the list")
        }
        for (key, reason) in Self.leftOut { #expect(!reason.isEmpty, "\(key) is left out with no reason") }
    }

    @Test("The not-yet list only shrinks")
    func notYetOnlyShrinks() {
        #expect(Self.notYet.count <= Self.notYetPin,
                "\(Self.notYet.count) rows are not named yet against a pin of \(Self.notYetPin): name the new ones instead")
        #expect(Self.notYet.count >= Self.notYetPin,
                "only \(Self.notYet.count) rows are left to name: lower notYetPin to \(Self.notYet.count)")
    }

    @Test("Every timeline right-click row is a named command, a submenu, or listed")
    func everyTimelineRowIsPlaced() {
        var named = 0
        for row in TimelineMenuRow.allCases {
            switch Self.reach(row) {
            case .command(let id):
                named += 1
                #expect(AppCommandTable.command(id) != nil, "\(row) runs \(id.rawValue), which is not in the table")
            case .leftOut(let why), .notYet(let why):
                #expect(!why.isEmpty, "\(row) has no reason")
            case .holds:
                break
            }
        }
        #expect(named >= 35, "only \(named) timeline right-click rows run a named command")
    }

    @Test("Every layer right-click row is a named command, or listed")
    func everyLayerRowIsNamed() throws {
        let rows = try Self.layerRows()
        #expect(rows.count > 30, "the source reader found only \(rows.count) layer rows")
        for key in rows {
            let words = EveryCommandIsInTheMenuBarTests.literals(in: key[...]).first
            if let words, Self.command(titled: words) != nil { continue }
            if Self.layerAliases[key] != nil || Self.layerNotYet[key] != nil || Self.layerLeftOut[key] != nil { continue }
            if let constant = AppCommandTable.all.first(where: { key == constantName(of: $0) }) { _ = constant; continue }
            Issue.record("The layer right-click row \(key) runs no named command. Name it, or list it.")
        }
        for key in Array(Self.layerNotYet.keys) + Array(Self.layerLeftOut.keys) + Array(Self.layerAliases.keys) {
            #expect(rows.contains(key), "\(key) is no longer a layer right-click row; take it off the list")
        }
    }

    /// Rows titled by a constant the table's title is: `MirrorAcrossCenter.title`.
    func constantName(of command: AppCommand) -> String? {
        switch command.id {
        case .mirrorAcrossCenter: "MirrorAcrossCenter.title"
        case .centerOnArtboard: "CenterOnArtboard.title"
        case .combineShapes: "PathCombine.menuItem"
        case .union: "PathCombine.unionTitle"
        case .outlineStroke: "OutlineStroke.title"
        case .stackSelection: "LayersPanelHeader.MenuRow.stackTitle"
        default: nil
        }
    }

    @Test("The count the audit reports")
    func count() throws {
        let rows = try Self.menuBarRows()
        let named = rows.filter { !$0.commands.isEmpty }.count
        print("""
            Menu bar rows: \(rows.count); named: \(named); left out: \(Self.leftOut.count); \
            not yet: \(Self.notYet.count). Commands in the table: \(AppCommandTable.all.count). \
            Timeline right-click rows: \(TimelineMenuRow.allCases.count), named: \
            \(TimelineMenuRow.allCases.filter { if case .command = Self.reach($0) { true } else { false } }.count).
            """)
        let listed = rows.filter { Self.leftOut[$0.key] != nil || Self.notYet[$0.key] != nil }.count
        #expect(named + listed == rows.count)
    }
}
