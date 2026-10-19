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
    static let notYetPin = 0

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
        // Rows drawn from a list the app builds (`MenuRowsView`): named when
        // the function that builds the list runs its rows through the command.
        for match in source.matches(of: /MenuRowsView\(rows:\s*([^)]*\))/) {
            let at = source.distance(from: source.startIndex, to: match.range.lowerBound)
            let key = "\(section(at)): MenuRowsView \(collapsed(match.output.1))"
            var named: [String] = []
            if let (file, id) = drawnRows[key] {
                let builder = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                if builder.contains("run(.\(id)") || builder.contains("AppCommandCall(.\(id)") { named = ["\(id)"] }
            }
            rows.append(Row(key: key, commands: named, title: "", line: lineNumber(at)))
        }
        return rows
    }

    /// The rows the app builds as a list, and the file whose builder runs each
    /// of them through the named command.
    static let drawnRows: [String: (file: String, command: AppCommandID)] = [
        "insertTitleRows: MenuRowsView editor.titlePresetRows(kind)":
            ("Sources/Photonz/EditorState+TitlePresets.swift", .insertTitle),
        "animatePropertyRows: MenuRowsView inner)":
            ("Sources/Photonz/EditorState+OnlyAnimated.swift", .animateProperty),
        "rangeRows: MenuRowsView editor?.rangeSectionMenuBarRows()":
            ("Sources/Photonz/EditorState+RangeSection.swift", .section),
    ]

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
        "body: \"New Blank Canvas…\"":
            "opens a new window for a person to pick a size in; new_picture makes a blank picture of any size",
        "body: \"New Video…\"":
            "opens a new window for a person to pick a size and length in; new_video (slice 4) makes a blank video",
        "body: UIStarter.menuTitle":
            "opens a new window holding a design starter; new_picture and place_component start one an agent names",
        "body: \"New from Clipboard\"":
            "opens a new window from what the person copied; paste puts the clipboard into a document an agent names",
        "body: \"Save to Capture History\"":
            "asks the person whether to replace the capture or keep both; save writes an edit back over the capture it came from, and export writes a copy to a path",
        "body: \"Copy Image\"":
            "shown only with Copy Merged switched off; at Next's defaults copy_merged copies the whole picture",
        "animateRows: \"Draw a Curve\\u{2026}\"":
            "a pad a person draws a curve on by hand; set_easing gives a stretch any named curve",
        "animateRows: \"Copy Ease\"":
            "carries the curve of a stretch picked on a key graph to others picked there; set_easing names each stretch's curve",
        "animateRows: \"Paste Ease\"":
            "carries the curve of a stretch picked on a key graph to others picked there; set_easing names each stretch's curve",
        "keyLaneRows: \"Show Graph\"":
            "how a lane is drawn for a person; it changes nothing in the document",
        "rangeRows: \"Export Range…\"":
            "opens the Export sheet for a person; export writes a video to a path (slice 4)",
        "layerMenu: \"Insert Component\"":
            "places the component picked in the Library panel; place_component places any component by name",
    ]

    static let notYet: [String: String] = [:]

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
        case .freezeFrame: .command(.freezeFrame)
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
        case .cut: .command(.cut)
        case .copy, .copyTransition: .command(.copy)
        case .pasteKeys, .pasteTransition, .pasteHere: .command(.paste)
        case .delete: .command(.delete)
        case .rippleDelete: .command(.rippleDelete)
        case .showPicture: .command(.showPicture)
        case .rippleTrimStart: .command(.rippleTrimStart)
        case .rippleTrimEnd: .command(.rippleTrimEnd)
        case .fadeIn, .fadeOut: .command(.setFade)
        case .punchIn: .command(.punchIn)
        case .addZoom: .command(.addZoom)
        case .suggestZooms: .command(.suggestZooms)
        case .addClick: .command(.addClick)
        case .animate: .command(.animateProperty)
        case .addKey: .command(.keyAtPlayhead)
        case .breakApart: .command(.breakApart)
        case .replayTitle: .command(.replayTitle)
        case .saveAsPreset: .command(.saveTitlePreset)
        case .addCaptions: .command(.addCaptions)
        case .selectForward: .command(.selectForward)
        case .duplicate: .command(.duplicateLayer)
        case .rename, .editWords: .command(.renameClip)
        case .revealInFinder: .leftOut("shows the file in Finder, outside the app")
        case .joinWithNextLine: .command(.joinWithNextLine)
        case .startHere: .command(.goToCaptionStart)
        case .followCursor: .command(.followCursor)
        case .zoomAmount: .command(.setZoomAmount)
        case .deleteZoom: .command(.deleteZoom)
        case .applyDefaultTransition: .command(.applyDefaultTransition)
        case .transitionLength: .command(.setTransitionLength)
        case .transitionCurve: .command(.setTransitionCurve)
        case .removeTransition: .command(.hardCut)
        case .rollEdit: .command(.rollEditToPlayhead)
        case .joinThroughEdit: .command(.joinThroughEdit)
        case .expandCut: .command(.expandCut)
        case .closeGap: .command(.delete)
        case .addTitlePage, .addNameCard: .command(.insertTitle)
        case .addText, .addRectangle: .leftOut("draws with a tool; add_text and add_shape draw them")
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
        "editorState.turnIntoPathMenuItem(id: id)": .turnIntoPath,
        "\"Rename\"": .renameLayer,
        "OriginalSpaceCopy.menuEdit": .editOriginal,
        "editorState.selectedComponentVariantWording.addCommand": .addVariant,
        "title": .applyToOtherVersions,
        "MenuToggleNames.layerLocked": .lockLayer,
    ]

    static let layerNotYet: [String: String] = [:]

    static let layerLeftOut: [String: String] = [
        "ExactPlacement.menuItem": "opens fields for a person to type a position and size into",
        "MenuToggleNames.layerVisible": "set_layer's visible shows and hides a layer",
        "\"Make \\(container) Fit\"":
            "grows the box a layer was cut off by; set_layer sizes that box, and bring_into_view moves the layer back",
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
                // Source text: an ellipsis may be written `\u{2026}`.
                let words = EveryCommandIsInTheMenuBarTests.literals(in: row.title)
                    .map { $0.replacingOccurrences(of: "\\u{2026}", with: "\u{2026}") }
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
        case .putTextOnPath: "EditorState.putTextOnPathTitle"
        case .turnIntoPicture: "RasterizePrompt.menuItem"
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
