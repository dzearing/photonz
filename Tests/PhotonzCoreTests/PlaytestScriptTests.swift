import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The scripted playtest a probe build can be handed: a JSON file listing the
/// steps to drive the editor with. The app-side driver is AppKit and compiled
/// only into non-shipping builds; the script model is pure so a malformed
/// script fails here, with a readable error, rather than deep inside a run.
@Suite("Playtest script")
struct PlaytestScriptTests {

    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("A shortcut step names the chord and the menu item it must reach")
    func shortcutStepNamesTheMenuItem() throws {
        let script = try decode("""
        { "steps": [ { "do": "shortcut", "key": "z", "modifiers": ["command"], "menuItem": "Undo" } ] }
        """)
        guard case .shortcut(let key, let modifiers, let item) = script.steps[0] else {
            Issue.record("shortcut"); return
        }
        #expect(key.characters == "z")
        #expect(modifiers == [.command])
        #expect(item == "Undo")
        #expect(script.steps[0].name == "shortcut")
    }

    @Test("A shortcut step may leave the menu item unnamed and just require the chord to land")
    func shortcutStepMayNotNameTheItem() throws {
        let script = try decode("""
        { "steps": [ { "do": "shortcut", "key": "z", "modifiers": ["command", "shift"] } ] }
        """)
        guard case .shortcut(_, let modifiers, let item) = script.steps[0] else {
            Issue.record("shortcut"); return
        }
        #expect(modifiers == [.command, .shift])
        #expect(item == nil)
    }

    @Test("A shortcut step with no key is refused with a readable reason")
    func shortcutStepNeedsAKey() {
        #expect(throws: PlaytestScriptError.self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "shortcut", "modifiers": ["command"] } ] }
            """.utf8))
        }
    }

    @Test("A shortcut step with a key nobody can press is refused")
    func shortcutStepRefusesAnUnknownKey() {
        #expect(throws: PlaytestScriptError.self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "shortcut", "key": "quux", "modifiers": ["command"] } ] }
            """.utf8))
        }
    }

    @Test("A walk can give the keyboard to a named inspector field")
    func focusStepNamesTheField() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "focus", "field": "W" } ] }
        """.utf8))
        guard case .focus(let field) = script.steps[0] else { Issue.record("focus"); return }
        #expect(field == "W")
        #expect(script.steps[0].name == "focus")
    }

    @Test("A focus step with no field named is refused with a readable reason")
    func focusStepNeedsAField() {
        #expect(throws: PlaytestScriptError.self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "focus" } ] }
            """.utf8))
        }
    }

    @Test("A blank step starts a walk from an empty canvas instead of a file")
    func blankStartsFromNothing() throws {
        let script = try decode("""
        {
          "out": "/tmp/walk/out",
          "steps": [
            { "do": "blank", "canvasWidth": 800, "canvasHeight": 600, "width": 1200, "height": 900, "card": "empty-card" }
          ]
        }
        """)
        guard case .blank(let canvas, let window, let card) = script.steps[0] else { Issue.record("blank"); return }
        #expect(canvas == CGSize(width: 800, height: 600))
        #expect(window == CGSize(width: 1200, height: 900))
        #expect(card == "empty-card")
    }

    @Test("A blank step with no size takes the default preset")
    func blankDefaultsToThePreset() throws {
        let script = try decode("""
        { "out": "/tmp/walk/out", "steps": [{ "do": "blank" }] }
        """)
        guard case .blank(let canvas, let window, let card) = script.steps[0] else { Issue.record("blank"); return }
        #expect(canvas == BlankCanvas.defaultPreset.size)
        #expect(window == nil)
        #expect(card == nil)
    }

    @Test("blank is listed among the step names the error text offers")
    func blankIsANamedStep() {
        #expect(PlaytestStep.names.contains("blank"))
    }

    @Test("A dragComponent step holds the picked component over a point without letting go")
    func dragComponentStepHoldsTheDragInTheAir() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragComponent", "at": [120, 80] } ] }
        """)
        guard case .dragComponent(let at) = script.steps[0] else {
            Issue.record("dragComponent"); return
        }
        #expect(at.point == CGPoint(x: 120, y: 80))
        #expect(script.steps[0].name == "dragComponent")
    }

    @Test("A dragFile step holds a file over a point and records what the canvas answered")
    func dragFileStepHoldsAFileInTheAir() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragFile", "file": "notes.txt", "at": [300, 200], "hold": "refused" } ] }
        """)
        guard case .dragFile(let file, let at, let hold, _) = script.steps[0] else {
            Issue.record("dragFile"); return
        }
        #expect(file == "notes.txt")
        #expect(at.point == CGPoint(x: 300, y: 200))
        #expect(hold == "refused")
        #expect(script.steps[0].name == "dragFile")
        #expect(PlaytestStep.names.contains("dragFile"))
    }

    @Test("A dragFile step can let go, so a walk can prove the file landed")
    func dragFileStepCanLetGo() throws {
        let script = try decode("""
        { "steps": [
            { "do": "dragFile", "file": "shot.png", "at": [1050, 620], "space": "window", "release": true },
            { "do": "dragFile", "file": "shot.png", "at": [1050, 620] }
        ] }
        """)
        guard case .dragFile(_, _, _, let released) = script.steps[0],
              case .dragFile(_, _, _, let held) = script.steps[1] else {
            Issue.record("dragFile"); return
        }
        #expect(released)
        #expect(!held)
    }

    @Test("A point can be given in window coordinates, for the chrome outside the picture")
    func aPointCanBeInWindowSpace() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragFile", "file": "notes.txt", "at": [1100, 200], "space": "window" } ] }
        """)
        guard case .dragFile(_, let at, _, _) = script.steps[0] else {
            Issue.record("dragFile"); return
        }
        #expect(at.point == CGPoint(x: 1100, y: 200))
        #expect(at.space == .window)
    }

    @Test("A dragFile step can hold a file without taking a picture of it")
    func dragFileStepDoesNotNeedAHold() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragFile", "file": "notes.txt", "at": [10, 10] } ] }
        """)
        guard case .dragFile(_, _, let hold, _) = script.steps[0] else {
            Issue.record("dragFile"); return
        }
        #expect(hold == nil)
    }

    @Test("A pinch step names the zoom to arrive at and how many nudges to take")
    func pinchStepNamesTheZoomItIsWalkingTo() throws {
        let script = try decode("""
        { "steps": [ { "do": "pinch", "to": 2.5, "steps": 40 } ] }
        """)
        guard case .pinch(let to, let steps) = script.steps[0] else { Issue.record("pinch"); return }
        #expect(to == 2.5)
        #expect(steps == 40)
        #expect(script.steps[0].name == "pinch")
    }

    @Test("A pinch step walks in a sensible number of nudges when it is not told")
    func pinchStepHasADefaultNumberOfNudges() throws {
        let script = try decode("""
        { "steps": [ { "do": "pinch", "to": 0.25 } ] }
        """)
        guard case .pinch(_, let steps) = script.steps[0] else { Issue.record("pinch"); return }
        #expect(steps == PlaytestStep.defaultPinchSteps)
    }

    @Test("A pinch to nowhere is refused before the run starts")
    func pinchToAnImpossibleZoomIsRefused() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "pinch", "to": 0 } ] }
            """)
        }
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "pinch", "to": -1 } ] }
            """)
        }
    }

    @Test func aScriptIsAnOutputFolderAndAListOfSteps() throws {
        let script = try decode("""
        {
          "out": "/tmp/walk/out",
          "steps": [
            { "do": "open", "file": "/tmp/shot.png", "width": 1280, "height": 840 },
            { "do": "wait", "seconds": 0.5 },
            { "do": "key", "key": "i" },
            { "do": "key", "key": "c", "modifiers": ["command", "control"] },
            { "do": "move", "at": [100, 200] },
            { "do": "click", "at": [100, 200], "count": 2, "space": "view" },
            { "do": "drag", "from": [10, 10], "to": [200, 120], "steps": 4 },
            { "do": "type", "text": "Primary button" },
            { "do": "tool", "tool": "arrow" },
            { "do": "measureMode", "mode": "size" },
            { "do": "waitFor", "condition": "edgeMap", "timeout": 5 },
            { "do": "waitFor", "condition": "measureMode", "value": "gap" },
            { "do": "snapshot", "name": "3-distance" },
            { "do": "render", "name": "final" },
            { "do": "describe", "stage": "3-distance", "note": "after two clicks" },
            { "do": "clearClipboard" },
            { "do": "readClipboard", "stage": "8-spec" },
            { "do": "action", "action": "copySpecList" }
          ]
        }
        """)
        #expect(script.out == "/tmp/walk/out")
        #expect(script.steps.count == 18)
        guard case .open(let file, let size) = script.steps[0] else { Issue.record("open"); return }
        #expect(file == "/tmp/shot.png")
        #expect(size == CGSize(width: 1280, height: 840))
        guard case .wait(let seconds) = script.steps[1] else { Issue.record("wait"); return }
        #expect(seconds == 0.5)
        guard case .key(let key, let mods) = script.steps[2] else { Issue.record("key"); return }
        #expect(key.name == "i" && mods.isEmpty)
        guard case .key(_, let chord) = script.steps[3] else { Issue.record("chord"); return }
        #expect(chord == [.command, .control])
        guard case .move(let at) = script.steps[4] else { Issue.record("move"); return }
        #expect(at.point == CGPoint(x: 100, y: 200) && at.space == .document)
        guard case .click(let click, let count, let clickMods) = script.steps[5] else { Issue.record("click"); return }
        #expect(click.space == .view && count == 2 && clickMods.isEmpty)
        guard case .drag(let from, let to, let steps, _, _, _) = script.steps[6] else { Issue.record("drag"); return }
        #expect(from.point == CGPoint(x: 10, y: 10) && to.point == CGPoint(x: 200, y: 120) && steps == 4)
        guard case .type(let text) = script.steps[7] else { Issue.record("type"); return }
        #expect(text == "Primary button")
        guard case .tool(let tool) = script.steps[8] else { Issue.record("tool"); return }
        #expect(tool == .arrow)
        guard case .measureMode(let mode) = script.steps[9] else { Issue.record("measureMode"); return }
        #expect(mode == .size)
        guard case .waitFor(let condition, let timeout) = script.steps[10] else { Issue.record("waitFor"); return }
        #expect(condition == .edgeMap && timeout == 5)
        guard case .waitFor(let modeCondition, let defaultTimeout) = script.steps[11] else { Issue.record("waitFor"); return }
        #expect(modeCondition == .measureMode(.gap))
        #expect(defaultTimeout == PlaytestStep.defaultTimeout)
        guard case .snapshot(let name, _) = script.steps[12] else { Issue.record("snapshot"); return }
        #expect(name == "3-distance")
        guard case .render(let render, let renderScale) = script.steps[13] else { Issue.record("render"); return }
        #expect(render == "final" && renderScale == 1)
        guard case .describe(let stage, let note) = script.steps[14] else { Issue.record("describe"); return }
        #expect(stage == "3-distance" && note == "after two clicks")
        guard case .clearClipboard = script.steps[15] else { Issue.record("clearClipboard"); return }
        guard case .readClipboard(let clipStage) = script.steps[16] else { Issue.record("readClipboard"); return }
        #expect(clipStage == "8-spec")
        guard case .action(let action) = script.steps[17] else { Issue.record("action"); return }
        #expect(action == .copySpecList)
    }

    @Test func defaultsKeepAScriptShort() throws {
        // A one-point click in document space with no modifiers is the common
        // case, so it spells nothing but the point.
        let script = try decode("""
        { "steps": [ { "do": "click", "at": [5, 6] }, { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .click(let at, let count, let mods) = script.steps[0] else { Issue.record("click"); return }
        #expect(at.space == .document && count == 1 && mods.isEmpty)
        guard case .drag(_, _, let steps, _, _, _) = script.steps[1] else { Issue.record("drag"); return }
        #expect(steps == PlaytestStep.defaultDragSteps)
        #expect(script.out == nil)
    }

    /// A walk that wants to see what EXPORTING looks like asks the render step
    /// for the scale the export dialog would use.
    @Test func aRenderStepCanAskForAnExportScale() throws {
        let script = try decode("""
        { "steps": [ { "do": "render", "name": "at-2x", "scale": 2 },
                     { "do": "render", "name": "plain" } ] }
        """)
        guard case .render(let name, let scale) = script.steps[0] else { Issue.record("render"); return }
        #expect(name == "at-2x" && scale == 2)
        guard case .render(_, let plain) = script.steps[1] else { Issue.record("render"); return }
        #expect(plain == 1)
    }

    @Test func theOutputFolderDefaultsToOutBesideTheScript() throws {
        let beside = try decode("{ \"steps\": [] }")
        let request = URL(fileURLWithPath: "/tmp/photonz-playtest/walk.json")
        #expect(beside.outputDirectory(besides: request).path == "/tmp/photonz-playtest/out")
        let explicit = try decode("{ \"out\": \"/var/tmp/renders\", \"steps\": [] }")
        #expect(explicit.outputDirectory(besides: request).path == "/var/tmp/renders")
        // A relative `out` is relative to the script, so a script folder can
        // travel with its renders.
        let relative = try decode("{ \"out\": \"renders/one\", \"steps\": [] }")
        #expect(relative.outputDirectory(besides: request).path == "/tmp/photonz-playtest/renders/one")
    }

    // The unmanned loop reads the app's own menu bar this way. Reading another
    // app's menus needs an Accessibility grant only a person can give, but the
    // probe is our app, so it can simply say what is in its own menu bar and an
    // audit can name a real menu item instead of one guessed from the source.
    @Test func aMenusStepReadsTheWholeMenuBarOrOneMenu() throws {
        let script = try decode("""
        {
          "steps": [
            { "do": "menus", "stage": "capture-names" },
            { "do": "menus", "stage": "capture-only", "menu": "Capture" }
          ]
        }
        """)
        guard case .menus(let allStage, let allMenu) = script.steps[0] else { Issue.record("menus"); return }
        #expect(allStage == "capture-names")
        #expect(allMenu == nil)
        guard case .menus(let oneStage, let oneMenu) = script.steps[1] else { Issue.record("menus"); return }
        #expect(oneStage == "capture-only")
        #expect(oneMenu == "Capture")
        #expect(script.steps[0].name == "menus")
        #expect(PlaytestStep.names.contains("menus"))
    }

    @Test func aMenusStepNeedsAStage() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("{ \"steps\": [ { \"do\": \"menus\" } ] }")
        }
    }

    @Test func anUnknownStepNamesTheOnesThatExist() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("{ \"steps\": [ { \"do\": \"tap\", \"at\": [1, 1] } ] }")
        }
        do {
            _ = try decode("{ \"steps\": [ { \"do\": \"tap\", \"at\": [1, 1] } ] }")
        } catch let error as PlaytestScriptError {
            let text = error.description
            #expect(text.contains("tap"))
            #expect(text.contains("click"))
            #expect(text.contains("snapshot"))
            #expect(text.contains("step 1"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func aMissingOrMalformedFieldSaysWhichStepAndWhich() {
        do {
            _ = try decode("{ \"steps\": [ { \"do\": \"wait\", \"seconds\": 1 }, { \"do\": \"click\", \"at\": [1] } ] }")
            Issue.record("a one-number point decoded")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("step 2"))
            #expect(error.description.contains("at"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
        do {
            _ = try decode("{ \"steps\": [ { \"do\": \"key\", \"key\": \"hyperspace\" } ] }")
            Issue.record("an unknown key decoded")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("hyperspace"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
        do {
            _ = try decode("{ \"steps\": [ { \"do\": \"tool\", \"tool\": \"laser\" } ] }")
            Issue.record("an unknown tool decoded")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("laser"))
            #expect(error.description.contains("measure"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func keysAreNamedTheWayAPersonWouldTypeThem() {
        // Letters and digits by themselves; the keys with no glyph by name.
        #expect(PlaytestKey("i")?.keyCode == 34)
        #expect(PlaytestKey("I")?.keyCode == 34)
        #expect(PlaytestKey("I")?.characters == "I")
        #expect(PlaytestKey("a")?.keyCode == 0)
        #expect(PlaytestKey("c")?.keyCode == 8)
        #expect(PlaytestKey("4")?.keyCode == 21)
        #expect(PlaytestKey("return")?.keyCode == 36)
        #expect(PlaytestKey("return")?.characters == "\r")
        #expect(PlaytestKey("escape")?.keyCode == 53)
        #expect(PlaytestKey("tab")?.keyCode == 48)
        #expect(PlaytestKey("space")?.keyCode == 49)
        #expect(PlaytestKey("delete")?.keyCode == 51)
        #expect(PlaytestKey("left")?.keyCode == 123)
        #expect(PlaytestKey("up")?.keyCode == 126)
        #expect(PlaytestKey("ENTER")?.keyCode == 36)
        #expect(PlaytestKey("hyperspace") == nil)
        #expect(PlaytestKey("") == nil)
    }

    /// A synthesized press has to carry what the keyboard would really type,
    /// because that is what AppKit matches shortcuts against: hold shift and
    /// M types "M", 4 types "$". A press that carried the unshifted character
    /// would tell the app ⇧M was a plain m.
    @Test func shiftTypesWhatTheKeyboardWouldReallyType() {
        #expect(PlaytestKey("m")?.characters(with: []) == "m")
        #expect(PlaytestKey("m")?.characters(with: [.shift]) == "M")
        #expect(PlaytestKey("m")?.characters(with: [.command, .shift]) == "M")
        #expect(PlaytestKey("m")?.characters(with: [.command, .option]) == "m")
        #expect(PlaytestKey("M")?.characters(with: [.shift]) == "M")
        // The number and punctuation rows type their upper glyph.
        #expect(PlaytestKey("4")?.characters(with: [.shift]) == "$")
        #expect(PlaytestKey("/")?.characters(with: [.shift]) == "?")
        #expect(PlaytestKey("[")?.characters(with: [.shift]) == "{")
        #expect(PlaytestKey("-")?.characters(with: [.shift]) == "_")
        // The keys with no shifted form stay exactly as they are, so ⇧↑ and
        // ⇧⌫ keep working.
        #expect(PlaytestKey("up")?.characters(with: [.shift]) == "\u{F700}")
        #expect(PlaytestKey("return")?.characters(with: [.shift]) == "\r")
        #expect(PlaytestKey("delete")?.characters(with: [.shift]) == "\u{7F}")
        #expect(PlaytestKey("space")?.characters(with: [.shift]) == " ")
    }

    @Test func modifiersDecodeByTheirMacNames() throws {
        let script = try decode("""
        { "steps": [ { "do": "key", "key": "c", "modifiers": ["shift", "option", "control", "command"] } ] }
        """)
        guard case .key(_, let mods) = script.steps[0] else { Issue.record("key"); return }
        #expect(Set(mods) == Set(PlaytestModifier.allCases))
        #expect(throws: PlaytestScriptError.self) {
            try decode("{ \"steps\": [ { \"do\": \"key\", \"key\": \"c\", \"modifiers\": [\"hyper\"] } ] }")
        }
    }

    @Test func hoverNamesEitherAPointOrTheControlItLabels() throws {
        // A walk rests the pointer on a control to see its tooltip. The tool
        // bar is chrome, so it is more natural to name the control than to
        // measure where it landed; a point still works for anything else.
        let script = try decode("""
        {
          "steps": [
            { "do": "hover", "label": "Arrow" },
            { "do": "hover", "at": [300, 800], "space": "view" }
          ]
        }
        """)
        guard case .hover(.label(let label)) = script.steps[0] else { Issue.record("label"); return }
        #expect(label == "Arrow")
        guard case .hover(.point(let at)) = script.steps[1] else { Issue.record("point"); return }
        #expect(at.point == CGPoint(x: 300, y: 800) && at.space == .view)
        #expect(throws: PlaytestScriptError.self) {
            try decode(#"{ "steps": [ { "do": "hover" } ] }"#)
        }
    }

    @Test func anAppKeyStepGoesThroughTheAppNotTheWindow() throws {
        // Esc takes the history overlay down through an application-wide event
        // monitor, and a monitor never sees a press handed straight to a
        // window, so a walk that wants to prove that path asks for this step.
        let script = try decode("""
        { "steps": [
            { "do": "appKey", "key": "escape" },
            { "do": "appKey", "key": "h", "modifiers": ["command", "shift"] }
          ]
        }
        """)
        guard case .appKey(let plain, let noModifiers) = script.steps[0] else { Issue.record("appKey"); return }
        #expect(plain == PlaytestKey("escape"))
        #expect(noModifiers.isEmpty)
        guard case .appKey(let letter, let modifiers) = script.steps[1] else { Issue.record("appKey"); return }
        #expect(letter == PlaytestKey("h"))
        #expect(modifiers == [.command, .shift])
        #expect(script.steps[0].name == "appKey")
        #expect(PlaytestStep.names.contains("appKey"))
    }

    @Test func anAppKeyStepNeedsAKeyItKnows() {
        #expect(throws: PlaytestScriptError.self) {
            try decode(#"{ "steps": [ { "do": "appKey", "key": "wiggle" } ] }"#)
        }
    }

    @Test func everyStepNameIsListedOnce() {
        // The error text and the doc both come from this list, so a new step
        // that forgets to register itself is caught here.
        let names = PlaytestStep.names
        #expect(Set(names).count == names.count)
        #expect(names.contains("open") && names.contains("waitFor") && names.contains("action"))
        #expect(names == names.sorted())
    }

    @Test func theEditorActionsCoverTheChromeAWalkCannotReachByKey() throws {
        // The inspector toggle is a button and the zoom keys are menu chords,
        // neither of which a hidden, never-active probe window honours, so a
        // walk that needs the canvas wide or the picture big says so directly.
        let script = try decode("""
        { "steps": [
            { "do": "action", "action": "hideInspector" },
            { "do": "action", "action": "showInspector" },
            { "do": "action", "action": "zoomIn" },
            { "do": "action", "action": "zoomOut" },
            { "do": "action", "action": "zoomToFit" }
        ] }
        """)
        let actions: [PlaytestAction] = script.steps.compactMap { step in
            if case .action(let action) = step { return action } else { return nil }
        }
        let expected: [PlaytestAction] = [.hideInspector, .showInspector, .zoomIn, .zoomOut, .zoomToFit]
        #expect(actions == expected)
    }

    @Test func aWalkCanGroupAndUngroupTheSelection() throws {
        // ⌘G and ⇧⌘G are menu chords, which a hidden probe window does not
        // honour, so a walk that checks grouping asks for it directly.
        let script = try decode("""
        { "steps": [
            { "do": "action", "action": "group" },
            { "do": "action", "action": "ungroup" }
        ] }
        """)
        let actions: [PlaytestAction] = script.steps.compactMap { step in
            if case .action(let action) = step { return action } else { return nil }
        }
        #expect(actions == [.group, .ungroup])
    }

    @Test func aWalkCanPickTheCanvasRow() throws {
        // The Canvas row lives in the layers dock, which a walk cannot reach
        // with the pointer, so typing into the Canvas section's own numbers
        // starts by asking for the row directly.
        let script = try decode("""
        { "steps": [
            { "do": "action", "action": "selectCanvas" }
        ] }
        """)
        let actions: [PlaytestAction] = script.steps.compactMap { step in
            if case .action(let action) = step { return action } else { return nil }
        }
        #expect(actions == [.selectCanvas])
    }

    @Test func aDragCanNameAShotTakenWhileTheButtonIsStillDown() throws {
        // The yellow snap guide only exists mid-drag; an audit that has to show
        // it needs the picture taken before the mouse comes up.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "hold": "snapped" } ] }
        """)
        guard case .drag(_, _, _, _, let hold, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(hold == "snapped")
    }

    @Test func aDragCanHoldAModifierForTheWholeGesture() throws {
        // Command is the escape hatch from every magnet in this app, so a walk
        // that cannot hold it cannot check that the escape hatch still works.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "modifiers": ["command"] } ] }
        """)
        guard case .drag(_, _, _, let modifiers, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(modifiers == [.command])
    }

    @Test func aDragCanShakeLikeAHandThatIsNotSteady() throws {
        // What proves a snap does not flicker: a pass that does not travel in
        // a perfect straight line.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "wobble": 1.5 } ] }
        """)
        guard case .drag(_, _, _, _, _, let wobble) = script.steps[0] else { Issue.record("drag"); return }
        #expect(wobble == 1.5)
    }

    @Test func aDragThatSaysNothingAboutWobbleTravelsStraight() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, _, let wobble) = script.steps[0] else { Issue.record("drag"); return }
        #expect(wobble == 0)
    }

    @Test func aDragWithoutAHoldShotTakesNoneAtAll() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, let hold, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(hold == nil)
    }

    // MARK: - Reaching into the dock

    @Test func aWalkCanOpenAMenuInsideThePanelAndPhotographIt() throws {
        // Five audits in one day said the same thing: the words on a dock
        // menu's rows could only be covered by a test, never shown.
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "Add", "shot": "add-menu" } ] }
        """)
        guard case .panelMenu(let menu, let shot, let choose) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(menu == "Add")
        #expect(shot == "add-menu")
        #expect(choose == nil)
        #expect(script.steps[0].name == "panelMenu")
    }

    @Test func aPanelMenuStepCanPickOneOfItsRows() throws {
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "Add", "choose": "Label" } ] }
        """)
        guard case .panelMenu(_, let shot, let choose) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(shot == nil)
        #expect(choose == "Label")
    }

    @Test func aPanelMenuStepMustNameTheMenu() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "panelMenu", "shot": "add-menu" } ] }
            """)
        }
    }

    @Test func aWalkCanDragATileOffTheLibraryOntoThePicture() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragTile", "tile": "Button", "to": [400, 300], "hold": "over-canvas" } ] }
        """)
        guard case .dragTile(let tile, let to, let hold) = script.steps[0] else {
            Issue.record("dragTile"); return
        }
        #expect(tile == "Button")
        #expect(to.point == CGPoint(x: 400, y: 300))
        #expect(to.space == .document)
        #expect(hold == "over-canvas")
        #expect(script.steps[0].name == "dragTile")
    }

    @Test func aTileDragTakesTheSameViewSpaceEveryOtherPointDoes() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragTile", "tile": "Button", "to": [40, 30], "space": "view" } ] }
        """)
        guard case .dragTile(_, let to, let hold) = script.steps[0] else {
            Issue.record("dragTile"); return
        }
        #expect(to.space == .view)
        #expect(hold == nil)
    }

    @Test func aWalkCanDragOneLayerRowOntoAnother() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragRow", "row": "Label", "onto": "Card", "zone": "inside", "hold": "drop-line" } ] }
        """)
        guard case .dragRow(let row, let onto, let zone, let hold) = script.steps[0] else {
            Issue.record("dragRow"); return
        }
        #expect(row == "Label")
        #expect(onto == "Card")
        #expect(zone == .inside)
        #expect(hold == "drop-line")
        #expect(script.steps[0].name == "dragRow")
    }

    @Test func aRowDragLandsAboveTheRowByDefault() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragRow", "row": "Label", "onto": "Card" } ] }
        """)
        guard case .dragRow(_, _, let zone, _) = script.steps[0] else { Issue.record("dragRow"); return }
        #expect(zone == .above)
    }

    /// The canvas cannot select a locked layer — a click on the picture falls
    /// through it — so the layers list is the only way in.
    @Test func aWalkCanPickALayerOutOfTheLayersList() throws {
        let script = try decode("""
        { "steps": [ { "do": "selectRow", "row": "Background" },
                     { "do": "selectRow", "row": "Label", "modifiers": ["shift"] } ] }
        """)
        guard case .selectRow(let row, let modifiers) = script.steps[0] else {
            Issue.record("selectRow"); return
        }
        #expect(row == "Background")
        #expect(modifiers.isEmpty)
        #expect(script.steps[0].name == "selectRow")
        guard case .selectRow(_, let held) = script.steps[1] else { Issue.record("selectRow"); return }
        #expect(held == [.shift])
    }

    @Test func pickingARowNeedsToSayWhichRow() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "selectRow" } ] }
            """)
        }
    }

    /// A list that builds only the rows you can see has to be scrolled for the
    /// rest to arrive, and no other step can turn a wheel.
    /// Three audits on 2026-09-04 had to hand back a photograph of a button
    /// in the right hand panel instead of a press, because nothing could reach
    /// one. A press names the words on the control, never a pixel.
    @Test func aWalkCanPressAControlInThePanelByItsName() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Clear Stretch" } ] }
        """)
        guard case .press(let control, let row, let count, let modifiers) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(control == "Clear Stretch")
        #expect(row == nil)
        #expect(count == 1)
        #expect(modifiers.isEmpty)
        #expect(script.steps[0].name == "press")
    }

    /// The Layout section holds a Hug and a Fixed for Width and another pair
    /// for Height, so the words alone do not say which one.
    @Test func aPressCanSayWhichRowTheControlIsOn() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Fixed", "in": "Width" } ] }
        """)
        guard case .press(let control, let row, _, _) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(control == "Fixed")
        #expect(row == "Width")
    }

    @Test func aPressCanBeDoubledAndHeldWithModifiers() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Direction", "count": 2, "modifiers": ["option"] } ] }
        """)
        guard case .press(_, _, let count, let modifiers) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(count == 2)
        #expect(modifiers == [.option])
    }

    @Test func aPressMustNameTheControl() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "press" } ] }
            """)
        }
    }

    @Test func pressIsOneOfTheStepNames() {
        #expect(PlaytestStep.names.contains("press"))
    }

    @Test func aScrollPanelStepNamesARowAndHowFarToGo() throws {
        let script = try decode("""
        { "steps": [ { "do": "scrollPanel", "row": "Background", "by": -400 } ] }
        """)
        guard case .scrollPanel(let row, let by) = script.steps[0] else { Issue.record("scrollPanel"); return }
        #expect(row == "Background")
        #expect(by == -400)
    }

    /// Halfway down a lazy list the row a walk started from is gone, so the
    /// step has to work without naming one.
    @Test func aScrollPanelStepCanLeaveTheRowOut() throws {
        let script = try decode("""
        { "steps": [ { "do": "scrollPanel", "by": -160 } ] }
        """)
        guard case .scrollPanel(let row, let by) = script.steps[0] else { Issue.record("scrollPanel"); return }
        #expect(row == nil)
        #expect(by == -160)
    }

    @Test func aScrollPanelStepWithoutADistanceIsRefused() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "scrollPanel", "row": "Background" } ] }
            """)
        }
    }

    @Test func aRowDragRefusesAZoneThatIsNotOne() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "dragRow", "row": "Label", "onto": "Card", "zone": "beside" } ] }
            """)
        }
    }

    @Test func aWalkCanListWhatThePanelIsShowing() throws {
        // Naming a tile or a row is only possible when a walk can find out
        // what they are called, the way `menus` does for the menu bar.
        let script = try decode("""
        { "steps": [ { "do": "panel", "stage": "shelf" } ] }
        """)
        guard case .panel(let stage) = script.steps[0] else { Issue.record("panel"); return }
        #expect(stage == "shelf")
        #expect(script.steps[0].name == "panel")
    }

    @Test func aColourDragIsHeldAndThenLetGoOfAsTwoSteps() throws {
        // The whole point of the pair: a walk can stop in the middle of a
        // colour drag, photograph the canvas following it, and only then let
        // go — which is how "live while you drag, one step when you release"
        // is proved rather than asserted.
        let script = try decode("""
        {
          "steps": [
            { "do": "action", "action": "holdColorDrag" },
            { "do": "action", "action": "releaseColorDrag" }
          ]
        }
        """)
        guard case .action(let held) = script.steps[0] else { Issue.record("hold"); return }
        #expect(held == .holdColorDrag)
        guard case .action(let released) = script.steps[1] else { Issue.record("release"); return }
        #expect(released == .releaseColorDrag)
    }

    // A walk that does not parse used to be invisible: the harness resolved its
    // output folder only AFTER decoding, so the failure landed in a default
    // "out" folder beside the script while the launcher sat watching the folder
    // the script had asked for, and timed out after three minutes with nothing
    // in it. The folder is a property of the file, not of it being correct.
    @Test func theOutputFolderIsKnownEvenWhenTheScriptDoesNotParse() throws {
        let request = URL(fileURLWithPath: "/tmp/photonz-playtest/walk.json")
        let broken = Data("""
        { "out": "/tmp/photonz-playtest/frames", "steps": [ { "do": "frameSelection" } ] }
        """.utf8)
        #expect(throws: PlaytestScriptError.self) { try PlaytestScript.decode(broken) }
        #expect(PlaytestScript.outputDirectory(besides: request, in: broken).path
                == "/tmp/photonz-playtest/frames")
        // A relative `out` still resolves against the script, and a file that is
        // not JSON at all falls back to the folder beside it.
        let relative = Data("{ \"out\": \"renders\", \"steps\": [ { \"do\": \"nope\" } ] }".utf8)
        #expect(PlaytestScript.outputDirectory(besides: request, in: relative).path
                == "/tmp/photonz-playtest/renders")
        #expect(PlaytestScript.outputDirectory(besides: request, in: Data("not json".utf8)).path
                == "/tmp/photonz-playtest/out")
    }

    // Actions are written `{ "do": "action", "action": "frameSelection" }`, but
    // the natural mistake is to write the action name as the step. There are far
    // more actions than steps, so the generic "not a step" list is no help:
    // the error names the exact line to write instead.
    @Test func anActionNameWrittenAsAStepSaysHowToWriteIt() throws {
        do {
            _ = try PlaytestScript.decode(Data("{ \"steps\": [ { \"do\": \"frameSelection\" } ] }".utf8))
            Issue.record("expected the bare action name to be refused")
        } catch let error as PlaytestScriptError {
            let text = error.description
            #expect(text.contains("\"do\": \"action\""))
            #expect(text.contains("\"action\": \"frameSelection\""))
        }
    }

    // The list the error prints is what a walk author reads to fix a typo, so a
    // step missing from it is a step nobody can discover.
    @Test func everyStepNameIsListedForTheErrorText() throws {
        #expect(PlaytestStep.names.contains("selectRow"))
        #expect(PlaytestStep.names == PlaytestStep.names.sorted())
    }

    // MARK: - Setup a walk can ask for

    // Two walks only ever passed on their first run on a machine: one changed
    // the remembered text size and looked for the old one next time, and the
    // other needed a picture copied into the Screenshots folder by hand and
    // said so only in a note for a person. A walk says what it needs, and the
    // harness puts it right.
    @Test("A walk asks for remembered settings to be forgotten first")
    func setupNamesTheMemoriesToForget() throws {
        let script = try decode("""
        { "setup": { "forget": ["text", "color"] },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.forget == [.text, .color])
        #expect(script.setup.captures.isEmpty)
        #expect(!script.setup.isEmpty)
    }

    @Test("A walk with no setup block asks for nothing")
    func noSetupBlockIsEmptySetup() throws {
        let script = try decode("{ \"steps\": [ { \"do\": \"blank\" } ] }")
        #expect(script.setup.isEmpty)
        #expect(script.setup.forget.isEmpty)
        #expect(script.setup.captures.isEmpty)
    }

    @Test("A walk asks for the pictures its shelf needs")
    func setupNamesTheCapturesToPlace() throws {
        let script = try decode("""
        { "setup": { "captures": ["fixtures/probe.png"] },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.captures == ["fixtures/probe.png"])
    }

    // A misspelled memory is the whole point of naming them: it has to come
    // back naming the ones that exist, not silently forget nothing.
    @Test("An unknown memory says which ones there are")
    func unknownMemoryListsTheRealOnes() throws {
        do {
            _ = try decode("{ \"setup\": { \"forget\": [\"fonts\"] }, \"steps\": [] }")
            Issue.record("expected \"fonts\" to be refused")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("fonts"))
            #expect(error.description.contains("text"))
            #expect(error.description.contains("color"))
        }
    }

    @Test("A setup block with a key nobody knows says so")
    func unknownSetupKeyIsRefused() throws {
        do {
            _ = try decode("{ \"setup\": { \"seed\": \"copy a file first\" }, \"steps\": [] }")
            Issue.record("expected \"seed\" inside setup to be refused")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("seed"))
            #expect(error.description.contains("forget"))
            #expect(error.description.contains("captures"))
        }
    }

    @Test("Setup has to be an object, and forget and captures have to be lists of words")
    func setupShapeIsChecked() throws {
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(Data("{ \"setup\": \"forget text\", \"steps\": [] }".utf8))
        }
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(Data("{ \"setup\": { \"forget\": \"text\" }, \"steps\": [] }".utf8))
        }
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(Data("{ \"setup\": { \"captures\": [\"\"] }, \"steps\": [] }".utf8))
        }
    }

    // A walk that misspelled "setup" would otherwise be heard as a walk that
    // asked for nothing, and fail on its second run with no clue why.
    @Test("A top level key nobody knows is refused, so a misspelled setup cannot go unheard")
    func unknownTopLevelKeyIsRefused() throws {
        do {
            _ = try decode("{ \"setups\": { \"forget\": [\"text\"] }, \"steps\": [] }")
            Issue.record("expected \"setups\" to be refused")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("setups"))
            #expect(error.description.contains("setup"))
        }
        // The three a walk really does use all still pass.
        _ = try decode("{ \"out\": \"o\", \"seed\": \"what this walk is\", "
                       + "\"setup\": { \"forget\": [\"text\"] }, \"steps\": [] }")
    }

    // The names are what a walk author types, so they are plain words and the
    // list is discoverable from the error text.
    @Test func everyMemoryNameIsAPlainWord() throws {
        #expect(PlaytestMemory.allCases.map(\.rawValue)
                == ["text", "color", "shapes", "measure", "tools", "groups", "panel", "grid"])
    }
}
