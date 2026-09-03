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
        guard case .drag(let from, let to, let steps, _, _) = script.steps[6] else { Issue.record("drag"); return }
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
        guard case .snapshot(let name) = script.steps[12] else { Issue.record("snapshot"); return }
        #expect(name == "3-distance")
        guard case .render(let render) = script.steps[13] else { Issue.record("render"); return }
        #expect(render == "final")
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
        guard case .drag(_, _, let steps, _, _) = script.steps[1] else { Issue.record("drag"); return }
        #expect(steps == PlaytestStep.defaultDragSteps)
        #expect(script.out == nil)
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

    @Test func aDragCanNameAShotTakenWhileTheButtonIsStillDown() throws {
        // The yellow snap guide only exists mid-drag; an audit that has to show
        // it needs the picture taken before the mouse comes up.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "hold": "snapped" } ] }
        """)
        guard case .drag(_, _, _, _, let hold) = script.steps[0] else { Issue.record("drag"); return }
        #expect(hold == "snapped")
    }

    @Test func aDragCanHoldAModifierForTheWholeGesture() throws {
        // Command is the escape hatch from every magnet in this app, so a walk
        // that cannot hold it cannot check that the escape hatch still works.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "modifiers": ["command"] } ] }
        """)
        guard case .drag(_, _, _, let modifiers, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(modifiers == [.command])
    }

    @Test func aDragWithoutAHoldShotTakesNoneAtAll() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, let hold) = script.steps[0] else { Issue.record("drag"); return }
        #expect(hold == nil)
    }
}
