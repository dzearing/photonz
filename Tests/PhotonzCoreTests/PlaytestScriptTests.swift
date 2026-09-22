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

    @Test("A writePicture step leaves the canvas out unless the walk asks for it")
    func writePictureLeavesTheCanvasOutByDefault() throws {
        let script = try decode("""
        { "steps": [ { "do": "writePicture", "name": "icon", "format": "png" } ] }
        """)
        guard case .writePicture(_, _, _, _, let background, let behind) = script.steps[0] else {
            Issue.record("writePicture"); return
        }
        #expect(background == .drop)
        #expect(behind == nil)
    }

    @Test("A writePicture step can ask for the canvas and claim what is behind the drawing")
    func writePictureCarriesTheCanvasAnswerAndTheClaim() throws {
        let script = try decode("""
        { "steps": [ { "do": "writePicture", "name": "icon", "format": "png",
                       "background": "keep", "behind": "painted" } ] }
        """)
        guard case .writePicture(let name, let format, _, _, let background, let behind) =
            script.steps[0] else {
            Issue.record("writePicture"); return
        }
        #expect(name == "icon")
        #expect(format == "png")
        #expect(background == .keep)
        #expect(behind == .painted)
    }

    @Test("A writePicture step refuses a claim that is not one of the two")
    func writePictureRefusesAnUnknownClaim() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "writePicture", "name": "icon", "format": "png",
                           "behind": "white" } ] }
            """)
        }
    }

    @Test("A shortcut step names the chord and the menu item it must reach")
    func shortcutStepNamesTheMenuItem() throws {
        let script = try decode("""
        { "steps": [ { "do": "shortcut", "key": "z", "modifiers": ["command"], "menuItem": "Undo" } ] }
        """)
        guard case .shortcut(let key, let modifiers, let item, let checked) = script.steps[0] else {
            Issue.record("shortcut"); return
        }
        #expect(key.characters == "z")
        #expect(modifiers == [.command])
        #expect(item == "Undo")
        #expect(checked == nil)
        #expect(script.steps[0].name == "shortcut")
    }

    /// A setting's menu item keeps one name and says its state with a
    /// checkmark, so the only way a walk can prove the state is to read the
    /// checkmark. `checked` is what the item must be wearing BEFORE the press.
    @Test("A shortcut step can require the item to be ticked, or not, before it presses")
    func shortcutStepCanRequireTheCheckmark() throws {
        let script = try decode("""
        { "steps": [
            { "do": "shortcut", "key": "h", "modifiers": ["command", "shift"], "menuItem": "Show History", "checked": false },
            { "do": "shortcut", "key": "h", "modifiers": ["command", "shift"], "menuItem": "Show History", "checked": true }
        ] }
        """)
        guard case .shortcut(_, _, _, let first) = script.steps[0],
              case .shortcut(_, _, _, let second) = script.steps[1] else {
            Issue.record("shortcut"); return
        }
        #expect(first == false)
        #expect(second == true)
    }

    @Test("A shortcut step's checkmark must be true or false, not a word")
    func shortcutCheckmarkMustBeAFlag() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "shortcut", "key": "h", "modifiers": ["command"], "checked": "on" } ] }
            """)
        }
    }

    @Test("A shortcut step may leave the menu item unnamed and just require the chord to land")
    func shortcutStepMayNotNameTheItem() throws {
        let script = try decode("""
        { "steps": [ { "do": "shortcut", "key": "z", "modifiers": ["command", "shift"] } ] }
        """)
        guard case .shortcut(_, let modifiers, let item, let checked) = script.steps[0] else {
            Issue.record("shortcut"); return
        }
        #expect(modifiers == [.command, .shift])
        #expect(item == nil)
        #expect(checked == nil)
    }

    // MARK: Photographing a menu bar menu

    /// A checkmark is a picture, and until now no audit could show one: a menu
    /// draws outside this process, so only a real screen capture sees it.
    @Test("A menuShot step names the menu to open and what to call the picture")
    func menuShotStepNamesTheMenuAndThePicture() throws {
        let script = try decode("""
        { "steps": [ { "do": "menuShot", "menu": "Capture", "name": "capture-menu" } ] }
        """)
        guard case .menuShot(let menu, let name, let ticked, let unticked) = script.steps[0] else {
            Issue.record("menuShot"); return
        }
        #expect(menu == "Capture")
        #expect(name == "capture-menu")
        #expect(ticked.isEmpty)
        #expect(unticked.isEmpty)
        #expect(script.steps[0].name == "menuShot")
    }

    /// The picture is the point, but a picture nobody checks proves nothing, so
    /// the step can also require which rows are wearing a checkmark.
    @Test("A menuShot step can require which rows are ticked and which are not")
    func menuShotStepCanRequireTheCheckmarks() throws {
        let script = try decode("""
        { "steps": [ { "do": "menuShot", "menu": "View", "name": "view-menu",
                       "ticked": ["Show Grid"], "unticked": ["Show Library"] } ] }
        """)
        guard case .menuShot(_, _, let ticked, let unticked) = script.steps[0] else {
            Issue.record("menuShot"); return
        }
        #expect(ticked == ["Show Grid"])
        #expect(unticked == ["Show Library"])
    }

    // MARK: The menu you get by right clicking a row

    /// A menu bar menu hangs off the bar and a panel menu hangs off a button.
    /// The third kind hangs off nothing: it only exists once you right click
    /// the thing it belongs to, which is why an audit could describe the
    /// layer row menu and never show it.
    @Test("A rightClick step names the row whose menu to open")
    func rightClickStepNamesTheRow() throws {
        let script = try decode("""
        { "steps": [ { "do": "rightClick", "on": "Label" } ] }
        """)
        guard case .rightClick(let on, let at, let shot, let choose, let ticked, let unticked) = script.steps[0] else {
            Issue.record("rightClick"); return
        }
        #expect(on == "Label")
        #expect(at == nil)
        #expect(shot == nil)
        #expect(choose == nil)
        #expect(ticked.isEmpty)
        #expect(unticked.isEmpty)
        #expect(script.steps[0].name == "rightClick")
    }

    /// The picture is the point of the step, and the checkmarks are what stops
    /// the picture from being the only thing it proves.
    @Test("A rightClick step can ask for a picture, pick a row, and require the checkmarks")
    func rightClickStepCanPhotographChooseAndRequireCheckmarks() throws {
        let script = try decode("""
        { "steps": [ { "do": "rightClick", "on": "Label", "shot": "layer-row-menu",
                       "choose": "Duplicate", "ticked": ["Visible"], "unticked": ["Locked"] } ] }
        """)
        guard case .rightClick(let on, _, let shot, let choose, let ticked, let unticked) = script.steps[0] else {
            Issue.record("rightClick"); return
        }
        #expect(on == "Label")
        #expect(shot == "layer-row-menu")
        #expect(choose == "Duplicate")
        #expect(ticked == ["Visible"])
        #expect(unticked == ["Locked"])
    }

    /// The picture has no rows to name: the thing you right click on it is a
    /// spot, so the step takes a point in the same coordinates every other
    /// canvas step is written in.
    @Test("A rightClick step can name a spot on the picture instead of a row")
    func rightClickStepCanNameASpotOnThePicture() throws {
        let script = try decode("""
        { "steps": [ { "do": "rightClick", "at": [140, 120], "choose": "Group" } ] }
        """)
        guard case .rightClick(let on, let at, _, let choose, _, _) = script.steps[0] else {
            Issue.record("rightClick"); return
        }
        #expect(on == nil)
        #expect(at == PlaytestPoint(CGPoint(x: 140, y: 120), space: .document))
        #expect(choose == "Group")
    }

    @Test("A rightClick spot can be written in view or window coordinates like any other")
    func rightClickSpotTakesASpace() throws {
        let script = try decode("""
        { "steps": [ { "do": "rightClick", "at": [40, 40], "space": "window" } ] }
        """)
        guard case .rightClick(_, let at, _, _, _, _) = script.steps[0] else {
            Issue.record("rightClick"); return
        }
        #expect(at == PlaytestPoint(CGPoint(x: 40, y: 40), space: .window))
    }

    @Test("A rightClick step with nothing to click is refused with a readable reason")
    func rightClickStepNeedsSomethingToClick() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "rightClick", "shot": "layer-row-menu" } ] }
            """)
        }
    }

    @Test("A menuShot step with no menu named is refused with a readable reason")
    func menuShotStepNeedsAMenu() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "menuShot", "name": "capture-menu" } ] }
            """)
        }
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
        guard case .blank(let canvas, let window, let card, let scale) = script.steps[0] else { Issue.record("blank"); return }
        #expect(canvas == CGSize(width: 800, height: 600))
        #expect(window == CGSize(width: 1200, height: 900))
        #expect(card == "empty-card")
        #expect(scale == 1)
    }

    @Test("A blank step can say the document counts in twos, the way a Retina capture does")
    func blankTakesAPixelScale() throws {
        let script = try decode("""
        {
          "out": "/tmp/walk/out",
          "steps": [
            { "do": "blank", "canvasWidth": 800, "canvasHeight": 600, "pixelScale": 2 }
          ]
        }
        """)
        guard case .blank(_, _, _, let scale) = script.steps[0] else { Issue.record("blank"); return }
        #expect(scale == 2)
    }

    @Test("A blank step refuses a scale that is not a scale")
    func blankRefusesANonsenseScale() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "out": "/tmp/walk/out", "steps": [{ "do": "blank", "pixelScale": 0 }] }
            """)
        }
    }

    @Test("A blank step with no size takes the default preset")
    func blankDefaultsToThePreset() throws {
        let script = try decode("""
        { "out": "/tmp/walk/out", "steps": [{ "do": "blank" }] }
        """)
        guard case .blank(let canvas, let window, let card, let scale) = script.steps[0] else { Issue.record("blank"); return }
        #expect(canvas == BlankCanvas.defaultPreset.size)
        #expect(window == nil)
        #expect(card == nil)
        #expect(scale == 1)
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
        guard case .dragFile(let file, let at, let hold, _, _) = script.steps[0] else {
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
        guard case .dragFile(_, _, _, let released, _) = script.steps[0],
              case .dragFile(_, _, _, let held, _) = script.steps[1] else {
            Issue.record("dragFile"); return
        }
        #expect(released)
        #expect(!held)
    }

    /// An interrupted drag: the walk stops carrying the file and never tells
    /// the views under it that anything ended, which is what escape, a release
    /// outside the window, and a target rebuilt out from under the pointer all
    /// look like from the inside. It is the only way to prove a mark the panel
    /// put up clears itself rather than sticking for good.
    @Test("A dragFile step can walk away without telling the destination the drag ended")
    func dragFileStepCanBeAbandonedInTheAir() throws {
        let script = try decode("""
        { "steps": [
            { "do": "dragFile", "file": "notes.txt", "at": [1150, 300], "space": "window", "leave": true },
            { "do": "dragFile", "file": "notes.txt", "at": [1150, 300], "space": "window" }
        ] }
        """)
        guard case .dragFile(_, _, _, _, let abandoned) = script.steps[0],
              case .dragFile(_, _, _, _, let tidy) = script.steps[1] else {
            Issue.record("dragFile"); return
        }
        #expect(abandoned)
        #expect(!tidy)
    }

    // MARK: - Carrying one of the app's own things over the panel

    @Test("A dragOver step carries something out of the panel over a point and holds it there")
    func dragOverStepCarriesAPanelThing() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragOver", "carry": "Fill", "at": [1150, 300],
                       "space": "window", "hold": "colour-over-a-row" } ] }
        """)
        guard case .dragOver(let carry, let at, let hold, let leave) = script.steps[0] else {
            Issue.record("dragOver"); return
        }
        #expect(carry == "Fill")
        #expect(at.point == CGPoint(x: 1150, y: 300))
        #expect(at.space == .window)
        #expect(hold == "colour-over-a-row")
        #expect(!leave)
        #expect(script.steps[0].name == "dragOver")
        #expect(PlaytestStep.names.contains("dragOver"))
    }

    @Test("A dragOver step can be abandoned in the air too")
    func dragOverStepCanBeAbandonedInTheAir() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragOver", "carry": "Background", "at": [1150, 300],
                       "space": "window", "leave": true } ] }
        """)
        guard case .dragOver(_, _, _, let leave) = script.steps[0] else {
            Issue.record("dragOver"); return
        }
        #expect(leave)
    }

    @Test func aDragOverStepNeedsSomethingToCarry() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "dragOver", "at": [1150, 300], "space": "window" } ] }
            """)
        }
    }

    @Test("A point can be given in window coordinates, for the chrome outside the picture")
    func aPointCanBeInWindowSpace() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragFile", "file": "notes.txt", "at": [1100, 200], "space": "window" } ] }
        """)
        guard case .dragFile(_, let at, _, _, _) = script.steps[0] else {
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
        guard case .dragFile(_, _, let hold, _, _) = script.steps[0] else {
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
        guard case .wait(let seconds, _) = script.steps[1] else { Issue.record("wait"); return }
        #expect(seconds == 0.5)
        guard case .key(let key, let mods) = script.steps[2] else { Issue.record("key"); return }
        #expect(key.name == "i" && mods.isEmpty)
        guard case .key(_, let chord) = script.steps[3] else { Issue.record("chord"); return }
        #expect(chord == [.command, .control])
        guard case .move(.point(let at), let moveMods) = script.steps[4] else { Issue.record("move"); return }
        #expect(at.point == CGPoint(x: 100, y: 200) && at.space == .document && moveMods.isEmpty)
        guard case .click(let click, let count, let clickMods) = script.steps[5] else { Issue.record("click"); return }
        #expect(click.space == .view && count == 2 && clickMods.isEmpty)
        guard case .drag(let from, let to, let steps, _, _, _, _, _, _, _) = script.steps[6] else { Issue.record("drag"); return }
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

    /// A tool that owns modes keeps them in its own button, and choosing one
    /// there is a different act from pressing the tool's key: it picks the tool
    /// up AND sets the mode in one move. A walk names the button by the tool's
    /// words and the row by its own, and can claim which row is wearing the
    /// tick before it picks anything.
    @Test func aWalkCanChooseFromAToolsOwnList() throws {
        let script = try decode("""
        {
          "steps": [
            { "do": "toolFlyout", "tool": "Measure", "choose": "Gap", "ticked": "Distance" },
            { "do": "toolFlyout", "tool": "Crop" }
          ]
        }
        """)
        guard case .toolFlyout(let tool, let choose, let ticked) = script.steps[0] else {
            Issue.record("toolFlyout"); return
        }
        #expect(tool == "Measure" && choose == "Gap" && ticked == "Distance")
        guard case .toolFlyout(let bare, let nothing, let noClaim) = script.steps[1] else {
            Issue.record("toolFlyout"); return
        }
        #expect(bare == "Crop" && nothing == nil && noClaim == nil)
    }

    @Test func defaultsKeepAScriptShort() throws {
        // A one-point click in document space with no modifiers is the common
        // case, so it spells nothing but the point.
        let script = try decode("""
        { "steps": [ { "do": "click", "at": [5, 6] }, { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .click(let at, let count, let mods) = script.steps[0] else { Issue.record("click"); return }
        #expect(at.space == .document && count == 1 && mods.isEmpty)
        guard case .drag(_, _, let steps, _, _, _, _, _, _, _) = script.steps[1] else { Issue.record("drag"); return }
        #expect(steps == PlaytestStep.defaultDragSteps)
        #expect(script.out == nil)
    }

    /// A pointer resting somewhere can be holding a key, and what the canvas
    /// says a press would do depends on it: ⌥ over a layer offers a copy,
    /// while ⌥ over a screen that is not picked offers nothing at all. So a
    /// move can hold modifiers without clicking.
    @Test func aMoveCanHoldModifiers() throws {
        let script = try decode("""
        { "steps": [ { "do": "move", "at": [5, 6], "modifiers": ["option"] },
                     { "do": "move", "at": [7, 8] } ] }
        """)
        guard case .move(.point(let at), let held) = script.steps[0] else { Issue.record("move"); return }
        #expect(at.point == CGPoint(x: 5, y: 6) && held == [.option])
        guard case .move(_, let none) = script.steps[1] else { Issue.record("move"); return }
        #expect(none.isEmpty)
    }

    /// Something whose position depends on the words on it cannot be rested on
    /// by numbers: the button on the line at the foot of the canvas moves every
    /// time its label changes, so a walk aimed at a point would come to rest
    /// beside it and prove nothing. A move can name a control instead, and it
    /// is found the way a press finds one.
    @Test func aMoveCanRestOnAControlByName() throws {
        let script = try decode("""
        { "steps": [ { "do": "move", "control": "Read the Words" },
                     { "do": "move", "control": "Fixed", "in": "Width" } ] }
        """)
        guard case .move(.control(let name, let row), _) = script.steps[0] else {
            Issue.record("move by control"); return
        }
        #expect(name == "Read the Words" && row == nil)
        guard case .move(.control(let named, let inRow), _) = script.steps[1] else {
            Issue.record("move by control in a row"); return
        }
        #expect(named == "Fixed" && inRow == "Width")
    }

    /// A move with neither a point nor a control has nowhere to go, and saying
    /// so beats resting the pointer at the origin.
    @Test func aMoveWithNowhereToGoIsRefused() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "move" } ] }
            """)
        }
    }

    /// A wait normally ends the moment the app goes quiet. A walk about a CLOCK
    /// needs the opposite: the line at the foot of the canvas leaves six
    /// seconds after it arrives whether the app is busy or not.
    @Test func aWaitCanBePutBackOnTheClock() throws {
        let script = try decode("""
        { "steps": [ { "do": "wait", "seconds": 7, "onTheClock": true },
                     { "do": "wait", "seconds": 1 } ] }
        """)
        guard case .wait(let long, let onTheClock) = script.steps[0] else { Issue.record("wait"); return }
        #expect(long == 7 && onTheClock)
        guard case .wait(_, let ordinary) = script.steps[1] else { Issue.record("wait"); return }
        #expect(ordinary == false)
    }

    /// Whether a pointer resting on the pill is holding its clock open is the
    /// half of that pill no walk could see until a walk's pointer could rest on
    /// anything, so it is a claim of its own.
    @Test func aNoticeCanBeClaimedHeldOrLetGo() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectNotice", "says": "Separated", "held": true },
                     { "do": "expectNotice", "held": false } ] }
        """)
        guard case .expectNotice(let says, _, let held) = script.steps[0] else {
            Issue.record("expectNotice"); return
        }
        #expect(says == "Separated" && held == true)
        guard case .expectNotice(_, _, let letGo) = script.steps[1] else {
            Issue.record("expectNotice"); return
        }
        #expect(letGo == false)
    }

    /// A claim that claims nothing passes against every pill and against none.
    @Test func aNoticeClaimHasToClaimSomething() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectNotice" } ] }
            """)
        }
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

    // A walk that says nothing about where to write used to write BESIDE its
    // own file, and every walk lives in the repo, so the default dropped
    // megabytes of renders into the working copy where a `git add -A` could
    // sweep them into a commit. The default is now the scratch folder every
    // walk already names by hand, under the walk's own name so two walks
    // running in a row do not read each other's pictures.
    @Test func theOutputFolderDefaultsToTheScratchFolderNamedAfterTheWalk() throws {
        let beside = try decode("{ \"steps\": [] }")
        let request = URL(fileURLWithPath: "/Users/someone/photonz/Scripts/playtest/panel-walk.json")
        #expect(beside.outputDirectory(besides: request).path == "/tmp/photonz-playtest/panel-walk")
        let explicit = try decode("{ \"out\": \"/var/tmp/renders\", \"steps\": [] }")
        #expect(explicit.outputDirectory(besides: request).path == "/var/tmp/renders")
        // A relative `out` is relative to the script, so a script folder can
        // travel with its renders. That one is the author's own choice, spelled
        // out in the file, rather than something a walk falls into by silence.
        let relative = try decode("{ \"out\": \"renders/one\", \"steps\": [] }")
        #expect(relative.outputDirectory(besides: request).path
                == "/Users/someone/photonz/Scripts/playtest/renders/one")
    }

    // The default never lands inside the repository, whatever the walk is
    // called or wherever it sits, because that is the whole point of it.
    @Test func theDefaultOutputFolderIsNeverInsideTheRepository() throws {
        let script = try decode("{ \"steps\": [] }")
        for name in ["walk.json", "a.b.walk.json", "no-extension", "Odd Name Walk.json"] {
            let request = URL(fileURLWithPath: "/Users/someone/photonz/Scripts/playtest/\(name)")
            let out = script.outputDirectory(besides: request).path
            #expect(out.hasPrefix("/tmp/photonz-playtest/"), "\(name) resolved to \(out)")
            #expect(!out.contains("/photonz/Scripts"), "\(name) resolved to \(out)")
        }
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
            { "do": "hover", "at": [300, 800], "space": "view" },
            { "do": "hover", "label": "Copy", "window": "Capture History" }
          ]
        }
        """)
        guard case .hover(.label(let label), let noWindow) = script.steps[0] else { Issue.record("label"); return }
        #expect(label == "Arrow")
        #expect(noWindow == nil)
        guard case .hover(.point(let at), _) = script.steps[1] else { Issue.record("point"); return }
        #expect(at.point == CGPoint(x: 300, y: 800) && at.space == .view)
        // The capture history is a floating panel of its own, so a walk names
        // the window its controls live in the way `snapshot` already does.
        guard case .hover(.label(let panelLabel), let panel) = script.steps[2] else { Issue.record("window"); return }
        #expect(panelLabel == "Copy")
        #expect(panel == "Capture History")
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

    /// The Font menu offers the curated families plus any the picked labels
    /// already wear, so there is no way through the UI to put a label into a
    /// family long enough to be shortened: the menu will not offer one until a
    /// label already has it. A walk that wants to see the box shortened has to
    /// ask for the family directly, the way `setTextSizeLarge` already asks for
    /// a size.
    @Test func aWalkCanPutTheLabelsIntoAFamilyTooLongForTheBox() throws {
        let script = try decode("""
        { "steps": [
            { "do": "action", "action": "setTextFontShortName" },
            { "do": "action", "action": "setTextFontLongName" }
        ] }
        """)
        let actions: [PlaytestAction] = script.steps.compactMap { step in
            if case .action(let action) = step { return action } else { return nil }
        }
        #expect(actions == [.setTextFontShortName, .setTextFontLongName])
    }

    /// The way back matters as much as the way in: new text comes out in
    /// whatever family the last one was set to, so a probe that has already run
    /// the long-name walk starts the next one already shortened.
    @Test func theShortFamilyIsOneTheBoxHasRoomFor() {
        #expect(TextStyles.fonts.contains(TextStyles.shortNameForPlaytest))
    }

    /// The family the action uses is longer than every curated one, which is
    /// what makes the box shorten it: the menu is held to exactly the width the
    /// curated names need.
    @Test func theLongFamilyIsLongerThanEveryCuratedOne() {
        let longest = TextStyles.fonts.map(\.count).max() ?? 0
        #expect(TextStyles.longNameForPlaytest.count > longest)
        #expect(!TextStyles.fonts.contains(TextStyles.longNameForPlaytest))
    }

    @Test func aDragCanNameAShotTakenWhileTheButtonIsStillDown() throws {
        // The yellow snap guide only exists mid-drag; an audit that has to show
        // it needs the picture taken before the mouse comes up.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "hold": "snapped" } ] }
        """)
        guard case .drag(_, _, _, _, _, let hold, _, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(hold == "snapped")
    }

    @Test func aDragCanClaimWhatTheReadingUnderItSaysMidGesture() throws {
        // The pill a drag carries exists only while the button is down, so
        // there is no step after the release that could ask about it.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "readout": "12 × 8" } ] }
        """)
        guard case .drag(_, _, _, _, _, _, let readout, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(readout == "12 × 8")
    }

    @Test func aDragWithoutAReadoutClaimAsksNothingAboutIt() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, _, _, let readout, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(readout == nil)
    }

    @Test func aDragCanClaimItWasShowingTheBoxItWasMaking() throws {
        // A stack does not move its rows when its box changes, so a picture of
        // the canvas mid-drag cannot tell a live outline from a dead one. The
        // walk claims the outline and the landing agree instead.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "showsBox": true } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, _, _, let showsBox) = script.steps[0] else {
            Issue.record("drag"); return
        }
        #expect(showsBox == true)
    }

    @Test func aDragCanClaimThereIsNoBoxToShow() throws {
        // How a screen, a plain group and a copy of a component are held to
        // behaving exactly as they did: none of them grows a second edge.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "showsBox": false } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, _, _, let showsBox) = script.steps[0] else {
            Issue.record("drag"); return
        }
        #expect(showsBox == false)
    }

    @Test func aDragClaimsNothingAboutItsBoxByDefault() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, _, _, let showsBox) = script.steps[0] else {
            Issue.record("drag"); return
        }
        #expect(showsBox == nil)
    }

    @Test func aReadoutClaimSaysWhatThePillCarriesOrThatThereIsNone() throws {
        let script = try decode("""
        { "steps": [
            { "do": "expectReadout", "says": "343, 287" },
            { "do": "expectReadout", "absent": true }
        ] }
        """)
        guard case .expectReadout(let says, let absent) = script.steps[0] else {
            Issue.record("expectReadout"); return
        }
        #expect(says == "343, 287")
        #expect(!absent)
        guard case .expectReadout(let none, let gone) = script.steps[1] else {
            Issue.record("expectReadout"); return
        }
        #expect(none == nil)
        #expect(gone)
    }

    /// A claim that says both things, or neither, passes against anything and
    /// so is refused where it is written rather than where it runs.
    @Test func aReadoutClaimHasToClaimExactlyOneThing() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectReadout", "says": "12 × 8", "absent": true } ] }
            """)
        }
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectReadout" } ] }
            """)
        }
    }

    @Test func aDragCanHoldAModifierForTheWholeGesture() throws {
        // Command is the escape hatch from every magnet in this app, so a walk
        // that cannot hold it cannot check that the escape hatch still works.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "modifiers": ["command"] } ] }
        """)
        guard case .drag(_, _, _, let modifiers, _, _, _, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(modifiers == [.command])
    }

    @Test func aDragCanPressAKeyWithTheButtonAlreadyDown() throws {
        // A live constraint like ⇧ is pressed and let go of mid drag, so a
        // walk has to be able to change the keys halfway through one.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "halfway": ["shift"] } ] }
        """)
        guard case .drag(_, _, _, let modifiers, let halfway, _, _, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(modifiers == [])
        #expect(halfway == [.shift])
    }

    @Test func aDragCanLetEveryKeyGoHalfwayThrough() throws {
        // An empty list is an instruction ("and then no keys at all"), which
        // is not the same as never writing the field.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "modifiers": ["shift"], "halfway": [] } ] }
        """)
        guard case .drag(_, _, _, let modifiers, let halfway, _, _, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(modifiers == [.shift])
        #expect(halfway == [])
    }

    @Test func aDragThatSaysNothingAboutHalfwayKeepsItsKeysThroughout() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "modifiers": ["shift"] } ] }
        """)
        guard case .drag(_, _, _, _, let halfway, _, _, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(halfway == nil)
    }

    @Test func aDragCanShakeLikeAHandThatIsNotSteady() throws {
        // What proves a snap does not flicker: a pass that does not travel in
        // a perfect straight line.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "wobble": 1.5 } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, let wobble, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(wobble == 1.5)
    }

    @Test func aDragThatSaysNothingAboutWobbleTravelsStraight() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, let wobble, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(wobble == 0)
    }

    @Test func aDragCanBeCalledOffHalfWayWithEscape() throws {
        // Changing your mind with the button still down. It is its own field
        // rather than a `halfway` modifier because Escape does not CONSTRAIN
        // the drag, it ends it, and what the walk goes on to prove is that the
        // rest of the travel wrote nothing.
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9], "cancel": true } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, _, let cancel, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(cancel)
    }

    @Test func aDragThatSaysNothingAboutCancellingRunsAllTheWayThrough() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, _, _, _, _, let cancel, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(!cancel)
    }

    @Test func aTimingDragIsCalledOffThroughTheStripUnlessItAsksForTheKey() throws {
        // The default proves the bar goes back; only `escape` proves anything
        // is listening for the key, so the two cannot be one field.
        let script = try decode("""
        { "steps": [
          { "do": "dragTiming", "bar": "Knob Rotation", "byMS": 90, "cancel": true },
          { "do": "dragTiming", "bar": "Knob Rotation", "byMS": 90, "cancel": true,
            "cancelBy": "escape" }
        ] }
        """)
        guard case .dragTiming(_, _, _, _, let cancelled, let by) = script.steps[0] else {
            Issue.record("dragTiming"); return
        }
        #expect(cancelled && by == .strip)
        guard case .dragTiming(_, _, _, _, _, let byKey) = script.steps[1] else {
            Issue.record("dragTiming"); return
        }
        #expect(byKey == .escape)
    }

    @Test func aTimingDragCalledOffAnUnknownWayIsRefusedOutright() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "dragTiming", "bar": "Knob Rotation", "byMS": 90,
                           "cancel": true, "cancelBy": "mind-reading" } ] }
            """)
        }
    }

    @Test func aDragWithoutAHoldShotTakesNoneAtAll() throws {
        let script = try decode("""
        { "steps": [ { "do": "drag", "from": [0, 0], "to": [9, 9] } ] }
        """)
        guard case .drag(_, _, _, _, _, let hold, _, _, _, _) = script.steps[0] else { Issue.record("drag"); return }
        #expect(hold == nil)
    }

    // MARK: - Reaching into the dock

    @Test func aWalkCanOpenAMenuInsideThePanelAndPhotographIt() throws {
        // Five audits in one day said the same thing: the words on a dock
        // menu's rows could only be covered by a test, never shown.
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "Add", "shot": "add-menu" } ] }
        """)
        guard case .panelMenu(let menu, _, let shot, let choose, _) = script.steps[0] else {
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
        guard case .panelMenu(_, _, let shot, let choose, _) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(shot == nil)
        #expect(choose == "Label")
    }

    @Test func aPanelMenuStepCanSayWhichRowTheMenuIsOn() throws {
        // An effect in the Effects list carries a Color menu AND a Position
        // menu, and a shape can carry two borders, so neither the row's name
        // nor the menu's own says which one on its own.
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "Color", "in": "Border 2" } ] }
        """)
        guard case .panelMenu(let menu, let row, _, _, _) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(menu == "Color")
        #expect(row == "Border 2")
    }

    @Test func aPanelMenuStepWithNoRowSearchesTheWholePanel() throws {
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "Add" } ] }
        """)
        guard case .panelMenu(_, let row, _, _, _) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(row == nil)
    }

    @Test func aPanelMenuStepCanOpenItselfWithARealClick() throws {
        // The zoom percentage answers a single click and a double click
        // differently, so proving a person's click still opens its menu means
        // clicking it rather than pressing the button in code.
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "100%", "clicking": "Zoom level" } ] }
        """)
        guard case .panelMenu(_, _, _, _, let clicking) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(clicking == "Zoom level")
    }

    @Test func aPanelMenuStepOpensItselfInCodeByDefault() throws {
        let script = try decode("""
        { "steps": [ { "do": "panelMenu", "menu": "Add" } ] }
        """)
        guard case .panelMenu(_, _, _, _, let clicking) = script.steps[0] else {
            Issue.record("panelMenu"); return
        }
        #expect(clicking == nil)
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
        guard case .dragTile(let tile, let to, let onto, let hold, let expect, let says)
                = script.steps[0] else {
            Issue.record("dragTile"); return
        }
        #expect(tile == "Button")
        #expect(to?.point == CGPoint(x: 400, y: 300))
        #expect(to?.space == .document)
        #expect(onto == nil)
        #expect(hold == "over-canvas")
        // A walk that says nothing about the answer is asking for the ordinary
        // one: the picture takes it. Every walk written before a tile could be
        // refused still means what it meant.
        #expect(expect == .takes)
        #expect(says == nil)
        #expect(script.steps[0].name == "dragTile")
    }

    /// A saved style carried onto something that cannot wear it is refused, and
    /// a walk has to be able to say so: without this, a refusal working exactly
    /// as designed reads as a broken step.
    @Test func aTileDragCanExpectARefusalAndTheWordsWithIt() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragTile", "tile": "Heading", "to": [400, 300],
                       "expect": "refuses", "says": "is not text" } ] }
        """)
        guard case .dragTile(_, _, _, _, let expect, let says) = script.steps[0] else {
            Issue.record("dragTile"); return
        }
        #expect(expect == .refuses)
        #expect(says == "is not text")
    }

    /// `dragTile` hands the payload to the canvas itself, which proves what
    /// happens once a tile is in the air but not that it ever left the shelf.
    /// `pickUpTile` is the other half: it presses the tile with the mouse and
    /// pulls, and says whether a drag actually started.
    @Test func aWalkCanPickATileUpWithTheMouse() throws {
        let script = try decode("""
        { "steps": [ { "do": "pickUpTile", "tile": "Heading", "to": [400, 300] } ] }
        """)
        guard case .pickUpTile(let tile, let to) = script.steps[0] else {
            Issue.record("pickUpTile"); return
        }
        #expect(tile == "Heading")
        #expect(to.point == CGPoint(x: 400, y: 300))
        #expect(to.space == .document)
        #expect(script.steps[0].name == "pickUpTile")
    }

    /// Where the tile is pulled to is the whole of the gesture, so a step that
    /// does not say is not a gesture.
    @Test func pickingATileUpNeedsSomewhereToPullIt() throws {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "pickUpTile", "tile": "Heading" } ] }
            """)
        }
    }

    @Test func aTileDragTakesTheSameViewSpaceEveryOtherPointDoes() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragTile", "tile": "Button", "to": [40, 30], "space": "view" } ] }
        """)
        guard case .dragTile(_, let to, _, let hold, _, _) = script.steps[0] else {
            Issue.record("dragTile"); return
        }
        #expect(to?.space == .view)
        #expect(hold == nil)
    }

    /// The row in the layers list is the other place a saved style can be put
    /// down, so a walk names it instead of a point on the picture. The two are
    /// alternatives: a step that gives both, or neither, is a walk that has not
    /// said where the tile goes.
    @Test func aWalkCanDragATileOntoARowInTheLayersList() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragTile", "tile": "Heading", "onto": "Title",
                       "expect": "refuses", "says": "is locked" } ] }
        """)
        guard case .dragTile(let tile, let to, let onto, _, let expect, let says)
                = script.steps[0] else {
            Issue.record("dragTile"); return
        }
        #expect(tile == "Heading")
        #expect(to == nil)
        #expect(onto == "Title")
        #expect(expect == .refuses)
        #expect(says == "is locked")
    }

    @Test func aTileDragCannotBeAimedAtBothAPointAndARow() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "dragTile", "tile": "Heading", "to": [400, 300],
                           "onto": "Title" } ] }
            """)
        }
    }

    @Test func aTileDragHasToSayWhereItGoes() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "dragTile", "tile": "Heading" } ] }
            """)
        }
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
        { "steps": [ { "do": "press", "control": "Each side" } ] }
        """)
        guard case .press(let control, let row, let count, let modifiers, _) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(control == "Each side")
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
        guard case .press(let control, let row, _, _, _) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(control == "Fixed")
        #expect(row == "Width")
    }

    @Test func aPressCanBeDoubledAndHeldWithModifiers() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Direction", "count": 2, "modifiers": ["option"] } ] }
        """)
        guard case .press(_, _, let count, let modifiers, _) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(count == 2)
        #expect(modifiers == [.option])
    }

    /// A press lands in the middle of the control, which for a slider means
    /// the knob goes halfway and nowhere else. `across` is how a walk puts one
    /// on a value it names.
    @Test func aPressCanLandPartWayAlongAControl() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Slider", "in": "Label corners", "across": 0.25 } ] }
        """)
        guard case .press(_, _, _, _, let across) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(across == 0.25)
    }

    @Test func aPressWithNoAcrossLandsInTheMiddle() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Each side" } ] }
        """)
        guard case .press(_, _, _, _, let across) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(across == nil)
    }

    /// A fraction outside the control is clamped onto it rather than pressing
    /// somewhere the control is not.
    @Test func anImpossibleAcrossIsPulledOntoTheControl() throws {
        let script = try decode("""
        { "steps": [ { "do": "press", "control": "Slider", "across": 4 } ] }
        """)
        guard case .press(_, _, _, _, let across) = script.steps[0] else {
            Issue.record("press"); return
        }
        #expect(across == 1)
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

    /// The distance a walk has to scroll is a number that goes stale the
    /// moment the dock grows a section, so a walk can name the control it
    /// wants on screen instead and let the step work out the rest.
    @Test func aRevealStepNamesTheControlItBringsIntoReach() throws {
        let script = try decode("""
        { "steps": [ { "do": "reveal", "control": "Limits", "in": "Height" } ] }
        """)
        guard case .reveal(let control, let inRow) = script.steps[0] else { Issue.record("reveal"); return }
        #expect(control == "Limits")
        #expect(inRow == "Height")
    }

    @Test func aRevealStepCanLeaveTheRowOut() throws {
        let script = try decode("""
        { "steps": [ { "do": "reveal", "control": "Clip contents" } ] }
        """)
        guard case .reveal(let control, let inRow) = script.steps[0] else { Issue.record("reveal"); return }
        #expect(control == "Clip contents")
        #expect(inRow == nil)
    }

    @Test func aRevealStepWithoutAControlIsRefused() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "reveal", "in": "Height" } ] }
            """)
        }
    }

    @Test func revealIsOneOfTheStepNames() {
        #expect(PlaytestStep.names.contains("reveal"))
    }

    @Test func aWalkCanCarryAColourFromOneSwatchToAnother() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragColor", "from": "Fill", "onto": "Outline",
                       "hold": "in-flight", "expect": "refuses" } ] }
        """)
        guard case .dragColor(let from, let onto, let hold, let expect, let says)
                = script.steps[0] else {
            Issue.record("dragColor"); return
        }
        #expect(from == "Fill")
        #expect(onto == "Outline")
        #expect(hold == "in-flight")
        #expect(expect == .refuses)
        #expect(says == nil)
        #expect(script.steps[0].name == "dragColor")
    }

    /// The usual thing a walk is checking is that the second swatch TOOK the
    /// colour, so that is what it gets without saying so.
    @Test func aColourDragExpectsTheSwatchToTakeItByDefault() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragColor", "from": "Fill", "onto": "Outline" } ] }
        """)
        guard case .dragColor(_, _, let hold, let expect, _) = script.steps[0] else {
            Issue.record("dragColor"); return
        }
        #expect(hold == nil)
        #expect(expect == .takes)
    }

    /// A ring says yes and a dark swatch says no; neither says WHY, or how far
    /// the drop reaches. `says` is how a walk pins the sentence the target is
    /// saying while the colour is still in the air, the same way `dragTile`
    /// already pins the text style one.
    @Test func aColourDragCanPinTheSentenceTheTargetSays() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragColor", "from": "Border", "onto": "Fill",
                       "says": "both of them" } ] }
        """)
        guard case .dragColor(_, _, _, let expect, let says) = script.steps[0] else {
            Issue.record("dragColor"); return
        }
        #expect(says == "both of them")
        #expect(expect == .takes)
    }

    /// A refusal owes a reason, so the words can be pinned on a drop that is
    /// turned away as well as on one that lands.
    @Test func aRefusedColourDragCanPinItsReason() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragColor", "from": "Fill", "onto": "Fill",
                       "expect": "refuses", "says": "where the colour came from" } ] }
        """)
        guard case .dragColor(_, _, _, let expect, let says) = script.steps[0] else {
            Issue.record("dragColor"); return
        }
        #expect(expect == .refuses)
        #expect(says == "where the colour came from")
    }

    @Test func aColourDragRefusesAnAnswerThatIsNotOne() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "dragColor", "from": "Fill", "onto": "Outline",
                           "expect": "maybe" } ] }
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

    @Test func aWalkCanCarryADockSectionPastAnother() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragSection", "section": "Effects", "past": "Layers", "hold": "mid-drag" } ] }
        """)
        guard case .dragSection(let section, let past, let stop, let hold, let cancel) = script.steps[0] else {
            Issue.record("dragSection"); return
        }
        #expect(section == "Effects")
        #expect(past == "Layers")
        #expect(stop == .middle)
        #expect(hold == "mid-drag")
        #expect(cancel == false)
        #expect(script.steps[0].name == "dragSection")
    }

    @Test func aDockSectionDragCanBeCalledOffWithEscape() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragSection", "section": "Effects", "past": "Layers", "cancel": true } ] }
        """)
        guard case .dragSection(_, _, _, _, let cancel) = script.steps[0] else {
            Issue.record("dragSection"); return
        }
        #expect(cancel)
    }

    /// The complaint this step exists to catch: sections used to swap the
    /// moment the pointer touched one, rather than at its middle.
    @Test func aDockSectionDragCanStopShortOfTheMiddle() throws {
        let script = try decode("""
        { "steps": [ { "do": "dragSection", "section": "Effects", "past": "Layers", "stop": "touching" } ] }
        """)
        guard case .dragSection(_, _, let stop, _, _) = script.steps[0] else {
            Issue.record("dragSection"); return
        }
        #expect(stop == .touching)
    }

    @Test func aDockSectionDragRefusesAStopThatIsNotOne() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "dragSection", "section": "Effects", "past": "Layers", "stop": "halfway" } ] }
            """)
        }
    }

    @Test func aDockSectionDragNeedsSomethingToCarryItPast() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "dragSection", "section": "Effects" } ] }
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
                == "/tmp/photonz-playtest/walk")
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

    // MARK: - Claiming what the panel is showing

    // A walk that only presses things proves the presses happened, not that
    // the app answered. `expect` is the other half: it names a thing in the
    // right hand panel and the words it must be showing, and fails the run
    // when it says anything else.
    // A walk that presses Undo and photographs the result proves the picture
    // came back, not that the layers came back PICKED. `expectPicked` is the
    // half that notices: it names every layer that must be picked, and fails
    // the run when the panel is holding anything else.
    // Timing alone cannot guard how much a click costs: a machine under load
    // fails a green walk and a fast one passes a broken build. What a click
    // REBUILDS can be counted exactly, so that is what a walk asserts. Picking
    // a layer must not re-run the editor's own body, which is the whole
    // window's chrome (`layer-pick-latency-walk`).
    @Test("An expectBuilds step names a view and the most times it may build")
    func expectBuildsNamesTheViewAndTheCeiling() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectBuilds", "view": "editorBody", "atMost": 0 } ] }
        """)
        guard case .expectBuilds(let view, let atMost, _) = script.steps[0] else {
            Issue.record("expectBuilds"); return
        }
        #expect(view == "editorBody")
        #expect(atMost == 0)
        #expect(script.steps[0].name == "expectBuilds")
        #expect(PlaytestStep.names.contains("expectBuilds"))
    }

    /// Both halves are required: a ceiling with no view named is not a claim,
    /// and a view with no ceiling is a reading rather than a check.
    @Test func expectBuildsInsistsOnBothHalves() throws {
        #expect(throws: (any Error).self) {
            _ = try decode("""
            { "steps": [ { "do": "expectBuilds", "atMost": 0 } ] }
            """)
        }
        #expect(throws: (any Error).self) {
            _ = try decode("""
            { "steps": [ { "do": "expectBuilds", "view": "editorBody" } ] }
            """)
        }
    }

    /// A floor as well as a ceiling, because a ceiling of nothing passes just
    /// as quietly when the thing being counted has stopped existing. A walk
    /// that claims a click rebuilds nothing has to be able to claim, on the
    /// next click, that it rebuilds something.
    @Test("An expectBuilds step can claim a view DID build")
    func expectBuildsCanClaimAFloor() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectBuilds", "view": "colorRow", "atLeast": 1 } ] }
        """)
        guard case .expectBuilds(let view, let atMost, let atLeast) = script.steps[0] else {
            Issue.record("expectBuilds"); return
        }
        #expect(view == "colorRow")
        #expect(atMost == nil)
        #expect(atLeast == 1)
    }

    @Test("A floor and a ceiling together bound the count from both sides")
    func expectBuildsTakesBoth() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectBuilds", "view": "colorRow", "atLeast": 1, "atMost": 4 } ] }
        """)
        guard case .expectBuilds(_, let atMost, let atLeast) = script.steps[0] else {
            Issue.record("expectBuilds"); return
        }
        #expect(atLeast == 1)
        #expect(atMost == 4)
    }

    // A pick that brings a row into view has to be told apart from a pick that
    // leaves the list alone, and only the list knows which it did. "A row you
    // can already see wins" is the first rule the layers list follows and the
    // one a reader feels — a click near the top that jolts the panel is the
    // complaint — so a walk can now claim it outright rather than inferring it
    // from a screenshot.
    @Test("An expectListStill step claims the layers list did not move")
    func expectListStillClaimsTheListDidNotMove() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectListStill" } ] }
        """)
        guard case .expectListStill(let moved) = script.steps[0] else {
            Issue.record("expectListStill"); return
        }
        #expect(moved == false)
        #expect(script.steps[0].name == "expectListStill")
        #expect(PlaytestStep.names.contains("expectListStill"))
    }

    /// The other half of the same claim: a row genuinely off the bottom of a
    /// long list MUST be brought in, and a walk that only ever asserted
    /// stillness would pass an app whose list had stopped following at all.
    @Test("expectListStill with moved true claims the list did follow")
    func expectListStillCanClaimTheListFollowed() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectListStill", "moved": true } ] }
        """)
        guard case .expectListStill(let moved) = script.steps[0] else {
            Issue.record("expectListStill"); return
        }
        #expect(moved == true)
    }

    /// The chip under the canvas is the app's one place for saying what the
    /// thing in your hand can do, and nothing could claim it until now.
    @Test("An expectHint step claims the words on the chip")
    func expectHintClaimsTheChip() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectHint", "contains": "Double click a point to curve it" } ] }
        """)
        guard case .expectHint(let contains) = script.steps[0] else {
            Issue.record("expectHint"); return
        }
        #expect(contains == "Double click a point to curve it")
        #expect(script.steps[0].name == "expectHint")
        #expect(PlaytestStep.names.contains("expectHint"))
    }

    /// An empty claim would pass against every chip and against no chip, which
    /// is a walk that looks green and reads nothing.
    @Test func expectHintRefusesAnEmptyClaim() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectHint", "contains": "  " } ] }
            """)
        }
    }

    /// The pointer's shape is the only invitation canvas chrome has, and until
    /// now a walk could read it in the log and not claim it. It is the claim
    /// that catches a crosshair and a corner square disagreeing about which of
    /// them the next press belongs to (`docs/design/canvas-hit-order.md`).
    @Test("An expectCue step claims what a press at the pointer would take")
    func expectCueClaimsWhatThePressWouldTake() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectCue", "says": "grab" } ] }
        """)
        guard case .expectCue(let says) = script.steps[0] else {
            Issue.record("expectCue"); return
        }
        #expect(says == "grab")
        #expect(script.steps[0].name == "expectCue")
        #expect(PlaytestStep.names.contains("expectCue"))
    }

    /// A pill under the canvas took every click across its whole capsule for
    /// six seconds after every separation, and a walk could not tell: a walk's
    /// click is handed to the canvas view directly, so it lands whether or not
    /// anything is covering the spot. This claims what a REAL click would find
    /// there, which is the only way a walk can hold the app to chrome that
    /// lets the picture through.
    @Test("An expectClickReaches step claims who a real click at a point goes to")
    func expectClickReachesClaimsWhoTakesTheClick() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectClickReaches", "at": [500, 774], "space": "view" } ] }
        """)
        guard case .expectClickReaches(let at, let taker) = script.steps[0] else {
            Issue.record("expectClickReaches"); return
        }
        #expect(at.point == CGPoint(x: 500, y: 774))
        #expect(at.space == .view)
        // Left off, the claim is the one nearly every walk wants: the picture
        // gets the click.
        #expect(taker == .canvas)
        #expect(script.steps[0].name == "expectClickReaches")
        #expect(PlaytestStep.names.contains("expectClickReaches"))
    }

    @Test func expectClickReachesAlsoClaimsAControlTakesIt() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectClickReaches", "at": [687, 774], "space": "view",
                       "what": "chrome" } ] }
        """)
        guard case .expectClickReaches(_, let taker) = script.steps[0] else {
            Issue.record("expectClickReaches"); return
        }
        #expect(taker == .chrome)
    }

    @Test func expectClickReachesRefusesSomewhereThereIsNoSuchPlace() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectClickReaches", "at": [1, 2], "what": "the moon" } ] }
            """)
        }
    }

    @Test func expectCueTakesEveryAnswerTheCanvasGives() throws {
        for name in PlaytestScript.pointerCueNames {
            let script = try decode("""
            { "steps": [ { "do": "expectCue", "says": "\(name)" } ] }
            """)
            guard case .expectCue(let says) = script.steps[0] else {
                Issue.record("expectCue \(name)"); return
            }
            #expect(says == name)
        }
        #expect(PlaytestScript.pointerCueNames.contains("resize-up-left-down-right"))
    }

    /// A misspelled cue would otherwise pass against nothing and be read as a
    /// claim that held.
    @Test func expectCueRefusesAnAnswerTheCanvasNeverGives() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectCue", "says": "crosshair" } ] }
            """)
        }
    }

    @Test("An expectPicked step names the layers that must be picked")
    func expectPickedNamesTheLayers() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPicked", "layers": ["Rectangle", "Rectangle 2"] } ] }
        """)
        guard case .expectPicked(let layers, _) = script.steps[0] else {
            Issue.record("expectPicked"); return
        }
        #expect(layers == ["Rectangle", "Rectangle 2"])
        #expect(script.steps[0].name == "expectPicked")
        #expect(PlaytestStep.names.contains("expectPicked"))
    }

    /// An empty list is as much of the point as a full one: it is how a walk
    /// says nothing should be picked here.
    @Test func expectPickedTakesAnEmptyList() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPicked", "layers": [] } ] }
        """)
        guard case .expectPicked(let layers, _) = script.steps[0] else {
            Issue.record("expectPicked"); return
        }
        #expect(layers.isEmpty)
    }

    @Test("An expectRegion step claims where the marquee is")
    func expectRegionClaimsTheOutline() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectRegion", "reads": "400,300 200x100" } ] }
        """)
        guard case .expectRegion(let reads, let present) = script.steps[0] else {
            Issue.record("expectRegion"); return
        }
        #expect(reads == "400,300 200x100")
        #expect(present == nil)
        #expect(script.steps[0].name == "expectRegion")
        #expect(PlaytestStep.names.contains("expectRegion"))
    }

    /// "There is no outline" is the other half of the claim, and the half this
    /// step was written for: a marquee thrown away by a tool key used to be
    /// invisible to every walk.
    @Test func expectRegionCanClaimThereIsNone() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectRegion", "present": false } ] }
        """)
        guard case .expectRegion(let reads, let present) = script.steps[0] else {
            Issue.record("expectRegion"); return
        }
        #expect(reads == nil)
        #expect(present == false)
    }

    @Test func expectRegionHasToClaimSomething() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expectRegion" } ] }
            """)
        }
    }

    @Test func expectPickedHasToSayWhichLayers() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expectPicked" } ] }
            """)
        }
    }

    // A walk that drags a caliper and photographs the canvas proves the drag
    // happened, not that anything landed. `distance-lands-on-release.json` ran
    // green while every stage measured nothing, because no step ever asked
    // (2026-09-08). `expectMeasures` is the step that asks.
    @Test("An expectMeasures step says how many measurements must be on the canvas")
    func expectMeasuresNamesTheCount() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectMeasures", "count": 2 } ] }
        """)
        guard case .expectMeasures(let count) = script.steps[0] else {
            Issue.record("expectMeasures"); return
        }
        #expect(count == 2)
        #expect(script.steps[0].name == "expectMeasures")
        #expect(PlaytestStep.names.contains("expectMeasures"))
    }

    // A walk that exports and photographs the sheet proves the sheet opened,
    // not that the file is shapes: a mark that has quietly gone back to riding
    // out as a picture looks exactly the same on screen. `expectSVG` is the
    // step that asks the file.
    @Test("An expectSVG step says how much of the drawing would go out as pictures")
    func expectSVGNamesWhatWouldBePictured() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectSVG", "pictured": 0,
                       "contains": "mix-blend-mode:multiply" } ] }
        """)
        guard case .expectSVG(let pictured, let contains) = script.steps[0] else {
            Issue.record("expectSVG"); return
        }
        #expect(pictured == 0)
        #expect(contains == "mix-blend-mode:multiply")
        #expect(script.steps[0].name == "expectSVG")
        #expect(PlaytestStep.names.contains("expectSVG"))
    }

    @Test("expectSVG has to claim something")
    func expectSVGWithNoClaimIsRefused() {
        #expect(throws: (any Error).self) {
            _ = try decode("""
            { "steps": [ { "do": "expectSVG" } ] }
            """)
        }
    }

    // Working a whole track back to back used to open a window per guide, five
    // of them all called Tutorial Sample, and no screenshot of any one of them
    // could show it: each window looked exactly right. `expectWindows` is the
    // step that counts them.
    @Test("An expectWindows step says how many windows with that title must be open")
    func expectWindowsNamesTheCount() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectWindows", "titled": "Tutorial Sample", "count": 1 } ] }
        """)
        guard case .expectWindows(let titled, let count) = script.steps[0] else {
            Issue.record("expectWindows"); return
        }
        #expect(titled == "Tutorial Sample")
        #expect(count == 1)
        #expect(script.steps[0].name == "expectWindows")
        #expect(PlaytestStep.names.contains("expectWindows"))
    }

    @Test("expectWindows takes zero, which is how a walk claims a window went away")
    func expectWindowsTakesZero() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectWindows", "titled": "Tutorial Sample", "count": 0 } ] }
        """)
        guard case .expectWindows(_, let count) = script.steps[0] else {
            Issue.record("expectWindows"); return
        }
        #expect(count == 0)
    }

    @Test("expectWindows has to say how many")
    func expectWindowsNeedsACount() throws {
        #expect(throws: (any Error).self) {
            _ = try decode("""
            { "steps": [ { "do": "expectWindows", "titled": "Tutorial Sample" } ] }
            """)
        }
    }

    // The moment a guide ENDS used to be a moment nothing could describe: the
    // callout simply vanished, so a walk had nothing to wait on and nothing to
    // photograph.
    @Test("A walk can wait for a guide to have finished, and press the card it ends on")
    func aWalkCanDriveTheEndOfAGuide() throws {
        let script = try decode("""
        { "steps": [
            { "do": "waitFor", "condition": "tutorialFinished", "value": "take-the-tour" },
            { "do": "action", "action": "tutorialFinishNext" },
            { "do": "action", "action": "tutorialFinishStartYourOwn" },
            { "do": "action", "action": "tutorialFinishMoreGuides" }
        ] }
        """)
        guard case .waitFor(let condition, _) = script.steps[0],
              case .tutorialFinished(let guideID) = condition else {
            Issue.record("tutorialFinished"); return
        }
        #expect(guideID == "take-the-tour")
        for (index, action) in [PlaytestAction.tutorialFinishNext,
                                .tutorialFinishStartYourOwn,
                                .tutorialFinishMoreGuides].enumerated() {
            guard case .action(let found) = script.steps[index + 1] else {
                Issue.record("action \(action.rawValue)"); return
            }
            #expect(found == action)
            // Each one presses the card rather than a window, so a walk in a
            // recording's window can press them with no editor to ask.
            #expect(found.drivesGuide)
        }
    }

    // A command that makes a HUNDRED layers cannot be checked by naming rows:
    // the panel only renders the handful you can see, so a walk asking for
    // "Text 100" is told it is not there when it is. `expectLayers` asks the
    // document instead, which is where the answer actually is.
    @Test("An expectLayers step says how many layers the document must hold")
    func expectLayersNamesTheRange() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectLayers", "atLeast": 100, "atMost": 160 } ] }
        """)
        guard case .expectLayers(let atLeast, let atMost) = script.steps[0] else {
            Issue.record("expectLayers"); return
        }
        #expect(atLeast == 100)
        #expect(atMost == 160)
        #expect(script.steps[0].name == "expectLayers")
        #expect(PlaytestStep.names.contains("expectLayers"))
    }

    @Test("An expectLayers step can name one exact number instead of a range")
    func expectLayersTakesACount() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectLayers", "count": 12 } ] }
        """)
        guard case .expectLayers(let atLeast, let atMost) = script.steps[0] else {
            Issue.record("expectLayers"); return
        }
        #expect(atLeast == 12)
        #expect(atMost == 12)
    }

    @Test("An expectLayers step that claims nothing at all is refused")
    func expectLayersHasToClaimSomething() throws {
        #expect(throws: (any Error).self) {
            _ = try decode("""
            { "steps": [ { "do": "expectLayers" } ] }
            """)
        }
    }

    // Opening an effect used to leave its settings below the bottom of the
    // panel, with nothing scrolling to them (2026-09-08). A capture cannot
    // prove the fix: it shows the panel, and a person has to decide whether
    // the thing they opened is all there. `expectInView` asks the panel
    // instead, and fails saying by how many points the thing is cut off.
    @Test("An expectInView step names what has to be all on screen")
    func expectInViewNamesTheField() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectInView", "field": "Shadow" } ] }
        """)
        guard case .expectInView(let field, let whole) = script.steps[0] else {
            Issue.record("expectInView"); return
        }
        #expect(field == "Shadow")
        // Left unsaid, a thing too tall for the room it is in may run past the
        // bottom, because starting at its top is all the panel can do.
        #expect(whole == false)
        #expect(script.steps[0].name == "expectInView")
        #expect(PlaytestStep.names.contains("expectInView"))
    }

    // "As much of it as there is room for" is the panel's promise in a dock
    // that is over-subscribed, and it is the right promise for a pane nobody
    // asked to see. It is too weak for the pane you just opened: on 2026-09-09
    // opening the second of two effects showed 175 points of its 277 and the
    // step still passed, because that was all the room the panel had kept.
    // `"whole": true` is how a walk says the room itself has to be there.
    @Test("An expectInView step can insist on the whole of it, room and all")
    func expectInViewCanInsistOnTheWhole() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectInView", "field": "Shadow", "whole": true } ] }
        """)
        guard case .expectInView(let field, let whole) = script.steps[0] else {
            Issue.record("expectInView"); return
        }
        #expect(field == "Shadow")
        #expect(whole)
    }

    @Test("An expectInView step's whole has to be true or false")
    func expectInViewWholeIsAFlag() throws {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectInView", "field": "Shadow", "whole": "yes" } ] }
            """)
        }
    }

    @Test("An expectInView step must say which thing it means")
    func expectInViewNeedsAField() throws {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectInView" } ] }
            """)
        }
    }

    // The panel measures one space and used to say two words for it: on
    // 2026-09-08 a capture caught Corner Radius reading "18 pt" two rows above
    // Position and Size saying "px from the top left". `expectOneUnit` is the
    // step that holds the panel to one word, and it takes no arguments on
    // purpose: naming the rows to check is how the next row goes unchecked.
    @Test("An expectOneUnit step needs nothing said about it")
    func expectOneUnitTakesNoFields() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectOneUnit" } ] }
        """)
        guard case .expectOneUnit = script.steps[0] else {
            Issue.record("expectOneUnit"); return
        }
        #expect(script.steps[0].name == "expectOneUnit")
        #expect(PlaytestStep.names.contains("expectOneUnit"))
    }

    // The same shape of claim about the panel's NUMBERS: on 2026-09-09 a
    // capture caught a picked copy of a button reading Corner Radius 0 in
    // Appearance and Corner radius 18 in the Component section under it, over a
    // button that was plainly round. It takes no arguments for the same reason
    // its neighbour does not: naming the rows to check is how the next row goes
    // unchecked.
    @Test("An expectOneNumberPerName step needs nothing said about it")
    func expectOneNumberPerNameTakesNoFields() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectOneNumberPerName" } ] }
        """)
        guard case .expectOneNumberPerName = script.steps[0] else {
            Issue.record("expectOneNumberPerName"); return
        }
        #expect(script.steps[0].name == "expectOneNumberPerName")
        #expect(PlaytestStep.names.contains("expectOneNumberPerName"))
    }

    /// Zero is as much of the point as any other number: it is how a walk says
    /// nothing should have landed here.
    // Neither of the two things that went wrong while a caption was being
    // typed can be settled from a picture: the caret blinks, and the outline
    // is a dashed line a person has to eyeball against a bubble. So a walk
    // claims them instead.
    @Test("An expectCaption step claims the caret, the alignment and the outline")
    func expectCaptionNamesWhatMustHold() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectCaption", "aligned": "centred", "caret": "centred",
                       "outline": "hugs the bubble" } ] }
        """)
        guard case .expectCaption(let aligned, let caret, _, let outline) = script.steps[0] else {
            Issue.record("expectCaption"); return
        }
        #expect(aligned == .centred)
        #expect(caret == .centred)
        #expect(outline == .hugsTheBubble)
        #expect(script.steps[0].name == "expectCaption")
        #expect(PlaytestStep.names.contains("expectCaption"))
    }

    @Test("An expectCaption step can claim just one of the three")
    func expectCaptionTakesOneClaim() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectCaption", "caret": "left" } ] }
        """)
        guard case .expectCaption(let aligned, let caret, let height, let outline) = script.steps[0] else {
            Issue.record("expectCaption"); return
        }
        #expect(aligned == nil)
        #expect(caret == .left)
        #expect(height == nil)
        #expect(outline == nil)
    }

    /// A step that claims nothing passes whatever the app does, which is worse
    /// than no step at all.
    @Test func expectCaptionHasToClaimSomething() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectCaption" } ] }
            """)
        }
    }

    /// A caret can sit in the right place and still be drawn wrong: on an
    /// empty new line it came out about three fifths of a line tall, because
    /// the field was only as tall as the bubble and AppKit cut the caret off
    /// at the field's edge. Where it sits and how tall it is are two claims.
    @Test("An expectCaption step claims how tall the caret is drawn")
    func expectCaptionClaimsCaretHeight() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectCaption", "caret": "centred", "caretHeight": "full" } ] }
        """)
        guard case .expectCaption(let aligned, let caret, let height, let outline) = script.steps[0] else {
            Issue.record("expectCaption"); return
        }
        #expect(aligned == nil)
        #expect(caret == .centred)
        #expect(height == .full)
        #expect(outline == nil)
    }

    @Test("caretHeight is a claim on its own")
    func expectCaptionCaretHeightAlone() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectCaption", "caretHeight": "short" } ] }
        """)
        guard case .expectCaption(_, let caret, let height, _) = script.steps[0] else {
            Issue.record("expectCaption"); return
        }
        #expect(caret == nil)
        #expect(height == .short)
    }

    @Test func expectCaptionRefusesACaretHeightItDoesNotKnow() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectCaption", "caretHeight": "tall" } ] }
            """)
        }
    }

    @Test func expectCaptionRefusesAWordItDoesNotKnow() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectCaption", "caret": "somewhere" } ] }
            """)
        }
    }

    // A walk can photograph a caliper being dragged and still say nothing
    // about where its ends ended up: the feet are two dots a few points across
    // and the reading is a chip that moves with them. `expectFeet` asks the
    // DOCUMENT where the ends are, which is the only way a walk can hold the
    // app to a foot that travelled as far as the hand did.
    @Test("An expectFeet step says where a measurement's ends must have landed")
    func expectFeetNamesTheEnds() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectFeet", "start": [600, 500], "end": [806, 500],
                       "within": 1, "reads": "106 px" } ] }
        """)
        guard case .expectFeet(let layer, let start, let end, let reads, let within) = script.steps[0] else {
            Issue.record("expectFeet"); return
        }
        #expect(layer == nil)
        #expect(start?.point == CGPoint(x: 600, y: 500))
        #expect(end?.point == CGPoint(x: 806, y: 500))
        #expect(reads == "106 px")
        #expect(within == 1)
        #expect(script.steps[0].name == "expectFeet")
        #expect(PlaytestStep.names.contains("expectFeet"))
    }

    @Test func expectFeetClaimsOneEndOnItsOwn() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectFeet", "end": [806, 500] } ] }
        """)
        guard case .expectFeet(_, let start, let end, _, let within) = script.steps[0] else {
            Issue.record("expectFeet"); return
        }
        #expect(start == nil)
        #expect(end?.point == CGPoint(x: 806, y: 500))
        #expect(within == 0.5)
    }

    // A walk can photograph a piece being dragged inside a card on a slant and
    // still say nothing about where it landed: the box is drawn turned, so no
    // picture settles whether the piece followed the hand or went off at an
    // angle to it. `expectBox` asks the DOCUMENT, in both spaces that matter —
    // the numbers the piece's own panel shows, and the corner a person watches
    // on screen.
    @Test("An expectBox step says where a layer's box must have landed")
    func expectBoxNamesTheBox() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectBox", "layer": "Save", "at": [105, 105],
                       "size": [40, 20], "within": 1 } ] }
        """)
        guard case .expectBox(let layer, let at, let size, let corner, let onScreen,
                              let reachable, let within) = script.steps[0] else {
            Issue.record("expectBox"); return
        }
        #expect(layer == "Save")
        #expect(at?.point == CGPoint(x: 105, y: 105))
        #expect(size?.point == CGPoint(x: 40, y: 20))
        #expect(corner == nil)
        #expect(onScreen == nil)
        #expect(reachable == false)
        #expect(within == 1)
        #expect(script.steps[0].name == "expectBox")
        #expect(PlaytestStep.names.contains("expectBox"))
    }

    @Test("An expectBox step can claim one corner as a person sees it")
    func expectBoxNamesACornerOnScreen() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectBox", "layer": "Save", "corner": "bottomRight",
                       "onScreen": [300, 220] } ] }
        """)
        guard case .expectBox(_, let at, _, let corner, let onScreen, _, let within) =
                script.steps[0] else {
            Issue.record("expectBox"); return
        }
        #expect(at == nil)
        #expect(corner == .bottomRight)
        #expect(onScreen?.point == CGPoint(x: 300, y: 220))
        #expect(within == 2)
    }

    // A screen placed past the edge of the canvas is drawn by nothing and
    // reached by nothing, and a picture cannot tell that apart from a screen
    // that is merely off view right now. So a walk can claim the box is ON the
    // canvas without saying where on it.
    @Test("An expectBox step can claim a layer is somewhere the canvas reaches")
    func expectBoxClaimsReachable() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectBox", "layer": "Frame 2", "reachable": true } ] }
        """)
        guard case .expectBox(let layer, let at, _, _, _, let reachable, _) =
                script.steps[0] else {
            Issue.record("expectBox"); return
        }
        #expect(layer == "Frame 2")
        #expect(at == nil)
        #expect(reachable)
    }

    @Test func expectBoxNeverClaimsSomethingIsOutOfReach() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectBox", "layer": "Frame 2", "reachable": false } ] }
            """)
        }
    }

    @Test func expectBoxHasToClaimSomething() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectBox", "layer": "Save" } ] }
            """)
        }
    }

    @Test func expectBoxWantsACornerWithItsPlace() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectBox", "layer": "Save", "corner": "topLeft" } ] }
            """)
        }
    }

    @Test func expectFeetHasToClaimSomething() {
        #expect(throws: PlaytestScriptError.self) {
            try decode("""
            { "steps": [ { "do": "expectFeet" } ] }
            """)
        }
    }

    @Test func expectMeasuresTakesZero() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectMeasures", "count": 0 } ] }
        """)
        guard case .expectMeasures(let count) = script.steps[0] else {
            Issue.record("expectMeasures"); return
        }
        #expect(count == 0)
    }

    @Test func expectMeasuresHasToSayHowMany() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expectMeasures" } ] }
            """)
        }
    }

    @Test func expectMeasuresRefusesANegativeCount() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expectMeasures", "count": -1 } ] }
            """)
        }
    }

    @Test("An expect step names a field and the words it must be showing")
    func expectStepReadsAField() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "field": "Padding", "reads": "40" } ] }
        """)
        guard case .expect(let thing, let named, _, let reads, let present) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .field)
        #expect(named == "Padding")
        #expect(reads == "40")
        #expect(present == nil)
        #expect(script.steps[0].name == "expect")
    }

    @Test("An expect step can read a menu in the panel instead")
    func expectStepReadsAMenu() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "menu": "Version", "reads": "Disabled" } ] }
        """)
        guard case .expect(let thing, let named, _, let reads, _) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .menu)
        #expect(named == "Version")
        #expect(reads == "Disabled")
    }

    /// A menu asked what it READS answers with the words in its box, which is
    /// "Bodoni 72 Smallc..." once the name is too long for the box. What the
    /// pointer resting on it would say is a different sentence, and until now
    /// nothing could ask for it.
    @Test("An expect step can read the tooltip a control in the panel would show")
    func expectStepReadsATooltip() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "tooltip": "Font",
                       "reads": "Bodoni 72 Smallcaps, the font of this text" } ] }
        """)
        guard case .expect(let thing, let named, let inRow, let reads, _) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .tooltip)
        #expect(named == "Font")
        #expect(inRow == nil)
        #expect(reads == "Bodoni 72 Smallcaps, the font of this text")
    }

    /// The other half of the claim: that a control explains itself at all. A
    /// walk asking this is what stops the tooltip being quietly deleted.
    @Test("An expect step can claim a control has a tooltip without saying its words")
    func expectStepClaimsATooltipIsThere() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "tooltip": "Weight", "present": true } ] }
        """)
        guard case .expect(let thing, let named, _, let reads, let present) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .tooltip)
        #expect(named == "Weight")
        #expect(reads == nil)
        #expect(present == true)
    }

    /// The panel is full of rows wearing the same word: an ordinary selection
    /// shows two Colors and two Locks at once. So a tooltip, like a control,
    /// can say which row it means.
    @Test("A tooltip can be narrowed by the row it sits on")
    func aTooltipCanBeNarrowedByTheRowItSitsOn() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "tooltip": "Color", "in": "Shadow",
                       "reads": "The colour of this shadow" } ] }
        """)
        guard case .expect(let thing, let named, let inRow, _, _) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .tooltip)
        #expect(named == "Color")
        #expect(inRow == "Shadow")
    }


    // The other half of a claim: that something is there at all, or, just as
    // often, that it is NOT — a revert arrow before anything has been answered.
    @Test("An expect step can claim a control, a row or a tile is there, or is not")
    func expectStepClaimsSomethingIsThere() throws {
        let script = try decode("""
        { "steps": [
            { "do": "expect", "control": "Revert Padding", "present": true },
            { "do": "expect", "row": "Card", "present": false },
            { "do": "expect", "tile": "Card", "present": true }
        ] }
        """)
        guard case .expect(let first, let firstName, _, _, let firstPresent) = script.steps[0],
              case .expect(let second, _, _, _, let secondPresent) = script.steps[1],
              case .expect(let third, _, _, _, _) = script.steps[2] else {
            Issue.record("expect"); return
        }
        #expect(first == .control)
        #expect(firstName == "Revert Padding")
        #expect(firstPresent == true)
        #expect(second == .row)
        #expect(secondPresent == false)
        #expect(third == .tile)
    }

    // The same word can be on a dozen rows at once: every effect in the list
    // carries a Switch, and so do Fill and Outline above them. `in` narrows the
    // claim to one row, exactly as it does on a press, so a walk can say the
    // BLUR's switch reads off rather than whichever switch comes first.
    @Test("An expect step can narrow a control to the row it sits on")
    func expectStepNarrowsToARow() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "control": "Switch", "in": "Blur", "reads": "Blur, off" } ] }
        """)
        guard case .expect(let thing, let named, let inRow, let reads, _) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .control)
        #expect(named == "Switch")
        #expect(inRow == "Blur")
        #expect(reads == "Blur, off")
    }

    // Only a control and a tooltip are looked up by the row they are on: both
    // answer to a word the panel wears a dozen times over. A field, a menu, a
    // row and a tile are found by their own names, so an `in` on one of those
    // would be a narrowing the step silently ignores, which is worse than a
    // refusal.
    @Test("An expect step refuses in on anything but a control or a tooltip")
    func expectStepRefusesRowOnAField() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expect", "field": "W", "in": "Blur", "reads": "40" } ] }
            """)
        }
    }

    @Test("An expect step has to name exactly one thing")
    func expectStepNamesOneThing() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expect", "reads": "40" } ] }
            """)
        }
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expect", "field": "Padding", "row": "Card", "reads": "40" } ] }
            """)
        }
    }

    // A step that claims nothing would pass forever.
    @Test("An expect step has to claim something")
    func expectStepClaimsSomething() {
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expect", "field": "Padding" } ] }
            """)
        }
    }

    // A field, a menu and a control all SHOW words that change. A tile shows
    // its own name, so "reads" on one is a walk author expecting something the
    // step cannot check.
    @Test("Only a field, a menu, a control or a row can be asked what it reads")
    func expectStepReadsOnlyWhereThereAreWords() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "control": "Outline", "reads": "off" } ] }
        """)
        guard case .expect(let thing, _, _, let reads, _) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .control)
        #expect(reads == "off")
        #expect(throws: PlaytestScriptError.self) {
            _ = try decode("""
            { "steps": [ { "do": "expect", "tile": "Card", "reads": "Card" } ] }
            """)
        }
    }

    // A row says MORE than its name: whether it is a group and open, what a
    // shut group is hiding, whether it is a copy of a component, what a
    // separation left in it, how many pieces a clip is cut into. Those second
    // lines are six point captions, and claiming one in words is the only
    // alternative to photographing it and squinting.
    @Test("A row can be asked what it says under its name")
    func expectStepReadsARowsOwnWords() throws {
        let script = try decode("""
        { "steps": [ { "do": "expect", "row": "Screen recording",
                       "reads": "layer, 3 pieces" } ] }
        """)
        guard case .expect(let thing, let named, _, let reads, _) = script.steps[0] else {
            Issue.record("expect"); return
        }
        #expect(thing == .row)
        #expect(named == "Screen recording")
        #expect(reads == "layer, 3 pieces")
    }

    // A shelf is built in two places from one catalogue — the menu bar once at
    // launch, the window every time it is drawn — so a feature switched off
    // that reaches only one of them has to fail the walk.
    @Test("A walk claims which tutorial shelves are on offer and which are not")
    func expectTutorialTracksClaimsBothWays() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectTutorialTracks",
                       "with": ["Basics"], "without": ["Redlining"] } ] }
        """)
        guard case .expectTutorialTracks(let with, let without) = script.steps[0] else {
            Issue.record("expected an expectTutorialTracks step")
            return
        }
        #expect(with == ["Basics"])
        #expect(without == ["Redlining"])
    }

    @Test("An expectTutorialTracks step that claims nothing is refused")
    func expectTutorialTracksHasToClaimSomething() throws {
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(
                Data("{ \"steps\": [ { \"do\": \"expectTutorialTracks\" } ] }".utf8))
        }
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

    // "all" is the word for the walk that wants a machine that has never run
    // Photonz, which is most of them: 225 of the 405 walks declare nothing at
    // all and so inherit whatever the last walk on the machine left behind.
    // Naming ten areas one by one is how that list goes out of date, and a new
    // area of memory then reaches nobody.
    @Test("A walk can ask to forget everything the app remembers, in one word")
    func setupForgetsEverything() throws {
        let script = try decode("""
        { "setup": { "forget": ["all"] },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.forget == PlaytestMemory.allCases)
        #expect(!script.setup.isEmpty)
    }

    @Test("Forgetting everything and naming an area besides asks for it once")
    func setupForgetsEverythingWithoutRepeatingItself() throws {
        let script = try decode("""
        { "setup": { "forget": ["color", "all", "color"] },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.forget == PlaytestMemory.allCases)
    }

    // The shared component shelf is a FILE rather than a remembered setting,
    // and until 2026-09-20 nothing in `forget` reached it. A walk that shared a
    // component and was then killed part way through — a timeout, a crash, the
    // 180s cap — left its component on the shelf of every walk that ever ran
    // after it on that machine, because the tidy-up that puts the shelf back
    // only runs when the walk reaches its end. Four stale "Save Button"s had
    // collected on the probe that way, and because the shelf is offered ahead
    // of the app's own five, `pickFirstComponent` picked one of THOSE, which
    // the drag and drop steps cannot place: five walks failed with "no
    // component is picked on the Library shelf". "all" means a machine that has
    // never run Photonz, and such a machine has an empty shared shelf, so the
    // leak heals itself at the start of the next walk that asks.
    @Test("Forgetting everything empties the shared component shelf too")
    func setupForgetsTheSharedShelf() throws {
        #expect(PlaytestMemory.allCases.contains(.shelf))
        let script = try decode("""
        { "setup": { "forget": ["all"] },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.forget.contains(.shelf))
    }

    @Test("A walk can name the shared shelf on its own")
    func setupForgetsOnlyTheSharedShelf() throws {
        let script = try decode("""
        { "setup": { "forget": ["shelf"] },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.forget == [.shelf])
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

    // A walk that opens a picture and then saves layers beside it needs a copy
    // of its own. Two walks were opening one out of /tmp that nothing in the
    // repo makes, so they passed on the machine that had it and nowhere else.
    @Test("A walk asks for its own copy of a picture to work on")
    func setupNamesTheScratchFiles() throws {
        let script = try decode("""
        { "setup": { "scratch": ["fixtures/card.png"] },
          "steps": [ { "do": "open", "file": "scratch/card.png" } ] }
        """)
        #expect(script.setup.scratch == ["fixtures/card.png"])
        #expect(!script.setup.isEmpty)
    }

    // A guide, and plenty else, is only there when a feature is switched on in
    // the Experiments window. Until this, a walk could only run the app as it
    // came, so the flags-off half of a feature was checked by hand with
    // `defaults write` and put back by memory, and a walk written for it passed
    // either way.
    @Test("A walk says which features to switch on and off for its run")
    func setupNamesTheFlagsToSwitch() throws {
        let script = try decode("""
        { "setup": { "flags": { "\(FeatureCatalog.measureModesFlag)": false,
                                "\(FeatureCatalog.measurePanelFlag)": true } },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.flags == [
            PlaytestFlagChoice(name: FeatureCatalog.measureModesFlag, isEnabled: false),
            PlaytestFlagChoice(name: FeatureCatalog.measurePanelFlag, isEnabled: true),
        ])
        #expect(!script.setup.isEmpty)
    }

    // Sorted rather than left in whatever order the JSON parser hands back, so
    // the line the log writes about what this walk changed reads the same every
    // run and two runs can be compared.
    @Test("The flags a walk names come out in a steady order")
    func setupFlagsAreInASteadyOrder() throws {
        let script = try decode("""
        { "setup": { "flags": { "\(FeatureCatalog.measurePanelFlag)": false,
                                "\(FeatureCatalog.measureModesFlag)": false } },
          "steps": [ { "do": "blank" } ] }
        """)
        #expect(script.setup.flags.map(\.name)
                == [FeatureCatalog.measureModesFlag, FeatureCatalog.measurePanelFlag].sorted())
    }

    // The whole reason for naming them: a walk that asks for a feature nobody
    // has heard of has to fail loudly. Switching nothing and passing anyway is
    // the bug this replaces.
    @Test("A feature nobody has heard of is refused")
    func unknownFlagIsRefused() throws {
        do {
            _ = try decode("{ \"setup\": { \"flags\": { \"next-measur-modes\": false } }, \"steps\": [] }")
            Issue.record("expected \"next-measur-modes\" to be refused")
        } catch let error as PlaytestScriptError {
            #expect(error.description.contains("next-measur-modes"))
            #expect(error.description.contains("flags"))
        }
    }

    @Test("Flags have to be an object of on and off, not anything else")
    func setupFlagsShapeIsChecked() throws {
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(
                Data("{ \"setup\": { \"flags\": [\"next-measure-modes\"] }, \"steps\": [] }".utf8))
        }
        #expect(throws: PlaytestScriptError.self) {
            _ = try PlaytestScript.decode(
                Data("{ \"setup\": { \"flags\": { \"next-measure-modes\": \"off\" } }, \"steps\": [] }".utf8))
        }
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
            #expect(error.description.contains("flags"))
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
                == ["text", "color", "shapes", "measure", "tools", "groups", "panel", "grid",
                    "frames", "tutorials", "motion", "shelf", "questions"])
    }

    @Test func waitForReadsASectionByItsHeaderText() {
        // The claim "you can see the Rectangle section without scrolling" is a
        // step the walk fails on, not a number somebody reads back afterwards.
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "sectionInView", "value": "Rectangle", "timeout": 3 }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .waitFor(let condition, let timeout) = script.steps[0] else { Issue.record("waitFor"); return }
        #expect(condition == .sectionInView("Rectangle") && timeout == 3)
    }

    @Test func waitForReadsALayerRowByItsName() {
        // The claim "picking that shape put its row in front of you" is a step
        // the walk fails on too, in a list that shows five rows out of forty.
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "layerRowInView", "value": "Rectangle 12", "timeout": 3 }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .waitFor(let condition, let timeout) = script.steps[0] else { Issue.record("waitFor"); return }
        #expect(condition == .layerRowInView("Rectangle 12") && timeout == 3)
    }

    @Test func waitForReadsOneSectionSittingDirectlyUnderAnother() {
        // The claim "Motion is right under Effects" is a step the walk fails
        // on. Reading it back off dockSections afterwards is how it went
        // unnoticed that Motion had drifted ten sections down the panel.
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "sectionDirectlyUnder", "value": "Motion",
              "under": "Effects", "timeout": 3 }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .waitFor(let condition, let timeout) = script.steps[0] else { Issue.record("waitFor"); return }
        #expect(condition == .sectionDirectlyUnder("Motion", under: "Effects") && timeout == 3)
    }

    @Test func waitForRejectsASectionWithNothingToSitUnder() {
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "sectionDirectlyUnder", "value": "Motion" }
        ] }
        """
        #expect(throws: (any Error).self) { try PlaytestScript.decode(Data(json.utf8)) }
    }

    @Test func waitForRejectsASectionWithNoName() {
        let json = """
        { "out": "/tmp/x", "steps": [ { "do": "waitFor", "condition": "sectionInView" } ] }
        """
        #expect(throws: (any Error).self) { try PlaytestScript.decode(Data(json.utf8)) }
    }

    @Test func waitForReadsWhetherADialogIsUp() {
        // A dialog is a sheet the app draws itself, so nothing in the window
        // answers to its name. The condition asks the editor instead, by the
        // words on the dialog.
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "dialogUp", "value": "Resize Image", "timeout": 3 }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .waitFor(let condition, let timeout) = script.steps[0] else { Issue.record("waitFor"); return }
        #expect(condition == .dialog("Resize Image", up: true) && timeout == 3)
    }

    @Test func waitForReadsWhetherADialogHasGone() {
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "dialogGone", "value": "Resize Image" }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .waitFor(let condition, _) = script.steps[0] else { Issue.record("waitFor"); return }
        #expect(condition == .dialog("Resize Image", up: false))
    }

    @Test func waitForRejectsADialogWithNoName() {
        let json = """
        { "out": "/tmp/x", "steps": [ { "do": "waitFor", "condition": "dialogUp" } ] }
        """
        #expect(throws: (any Error).self) { try PlaytestScript.decode(Data(json.utf8)) }
    }

    @Test func aToolFlyoutStepCanChooseTheCommandAtTheFootOfTheList() {
        // Crop's list ends with Resize Image, which is a command rather than a
        // mode. A walk names it the same way it names a mode: by its words.
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "toolFlyout", "tool": "Crop", "choose": "Resize Image" }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .toolFlyout(let tool, let choose, let ticked) = script.steps[0] else {
            Issue.record("toolFlyout"); return
        }
        #expect(tool == "Crop" && choose == "Resize Image" && ticked == nil)
    }

    // MARK: - The colours a path came out wearing

    @Test("An expectPath step can claim how many points curve on one side only")
    func expectPathCountsHalfSmoothPoints() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPath", "halfSmooth": 2 } ] }
        """)
        guard case .expectPath(_, _, _, _, _, let half, _, _, _, _, _, _) = script.steps[0] else {
            Issue.record("expectPath"); return
        }
        #expect(half == 2)
    }

    @Test("A claim about points curved on one side has to be a count")
    func expectPathRefusesANonsenseHalfSmoothCount() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectPath", "halfSmooth": -1 } ] }
            """)
        }
    }

    /// The only claim that can tell a ring from a disc.
    @Test("An expectPath step can claim how many separate loops the outline is made of")
    func expectPathCountsRings() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPath", "rings": 2 } ] }
        """)
        guard case .expectPath(_, _, _, _, _, _, let rings, _, _, _, _, _) = script.steps[0] else {
            Issue.record("expectPath"); return
        }
        #expect(rings == 2)
    }

    @Test("A claim about loops has to be a count")
    func expectPathRefusesANonsenseRingCount() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectPath", "rings": -1 } ] }
            """)
        }
    }

    // MARK: - The pill under the canvas

    @Test("An expectNotice step can claim the words the pill is carrying")
    func expectNoticeReadsThePill() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectNotice", "says": "do not overlap" } ] }
        """)
        guard case .expectNotice(let says, let absent, _) = script.steps[0] else {
            Issue.record("expectNotice"); return
        }
        #expect(says == "do not overlap")
        #expect(absent == nil)
    }

    @Test("An expectNotice step can claim there is no pill at all")
    func expectNoticeCanClaimNone() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectNotice", "absent": true } ] }
        """)
        guard case .expectNotice(let says, let absent, _) = script.steps[0] else {
            Issue.record("expectNotice"); return
        }
        #expect(says == nil)
        #expect(absent == true)
    }

    @Test("An expectNotice step that claims nothing is refused")
    func expectNoticeHasToClaimSomething() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectNotice" } ] }
            """)
        }
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectNotice", "says": "   " } ] }
            """)
        }
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectNotice", "says": "hole", "absent": true } ] }
            """)
        }
    }

    @Test("An expectPath step can claim the two colours the path came out in")
    func expectPathNamesTheColours() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPath", "fill": "#2D7FF9", "ink": "#2D7FF9" } ] }
        """)
        guard case .expectPath(_, _, _, _, _, _, _, _, let fill, let ink, _, _) = script.steps[0] else {
            Issue.record("expectPath"); return
        }
        #expect(fill == "#2D7FF9")
        #expect(ink == "#2D7FF9")
    }

    /// An open path has no inside, and saying so is a real claim: it is the
    /// difference between a line and a shape.
    @Test("An expectPath step can claim a path has no inside at all")
    func expectPathCanClaimNoFill() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPath", "fill": "none" } ] }
        """)
        guard case .expectPath(_, _, _, _, _, _, _, _, let fill, _, _, _) = script.steps[0] else {
            Issue.record("expectPath"); return
        }
        #expect(fill == "none")
    }

    /// A typo in a colour is a walk that passes for the wrong reason, so the
    /// script is refused when it is read.
    @Test("A colour that is not a colour is refused when the script is read")
    func expectPathRefusesANonColour() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectPath", "fill": "blue" } ] }
            """)
        }
        // "none" is a fill nobody has, not an outline nobody has: a path is
        // always drawn in something.
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectPath", "ink": "none" } ] }
            """)
        }
    }

    @Test("A colour on its own is enough of a claim for expectPath")
    func aColourIsEnoughOfAClaim() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectPath", "ink": "#FF3B30" } ] }
        """)
        #expect(script.steps[0].name == "expectPath")
    }

    // MARK: - Did the points keep up with the pointer?

    @Test("An expectChrome step asks how far the points drifted off the shape")
    func expectChromeTakesADistance() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectChrome", "within": 2 } ] }
        """)
        guard case .expectChrome(let within) = script.steps[0] else {
            Issue.record("expectChrome"); return
        }
        #expect(within == 2)
        #expect(script.steps[0].name == "expectChrome")
    }

    /// The claim worth making almost always is "they never came off it at
    /// all", so saying nothing means one point.
    @Test("An expectChrome step with no distance holds the points to one point")
    func expectChromeDefaultsToOnePoint() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectChrome" } ] }
        """)
        guard case .expectChrome(let within) = script.steps[0] else {
            Issue.record("expectChrome"); return
        }
        #expect(within == 1)
    }

    @Test("A negative drift is refused when the script is read")
    func expectChromeRefusesANegativeDistance() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectChrome", "within": -1 } ] }
            """)
        }
    }

    // MARK: - Is the picture on screen drawn at the size it is shown at?

    @Test("An expectSharp step claims the canvas is drawn at the size it is shown at")
    func expectSharpClaimsTheSharpCopy() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectSharp" } ] }
        """)
        guard case .expectSharp(let absent, let within) = script.steps[0] else {
            Issue.record("expectSharp"); return
        }
        #expect(absent == false)
        #expect(within == 3)
        #expect(script.steps[0].name == "expectSharp")
    }

    @Test("An expectSharp step can claim there is no sharp copy at all")
    func expectSharpCanClaimNone() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectSharp", "absent": true, "within": 0.5 } ] }
        """)
        guard case .expectSharp(let absent, let within) = script.steps[0] else {
            Issue.record("expectSharp"); return
        }
        #expect(absent)
        #expect(within == 0.5)
    }

    @Test("A negative wait for the sharp copy is refused when the script is read")
    func expectSharpRefusesANegativeWait() throws {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectSharp", "within": -1 } ] }
            """)
        }
    }

    // MARK: - What the recording on disk says

    // A walk that trims and saves has to be able to ask the FILE, not the app.
    // The whole point of the save is that the media history hands out is the
    // trimmed media, and an app that believes it saved is exactly the thing
    // under suspicion.
    @Test("An expectStoredRecording step claims how long the file on disk is")
    func expectStoredRecordingClaimsTheDuration() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectStoredRecording", "seconds": 6 } ] }
        """)
        guard case .expectStoredRecording(let seconds, let within, let original) = script.steps[0] else {
            Issue.record("expectStoredRecording"); return
        }
        #expect(seconds == 6)
        #expect(within == 0.3)
        #expect(original == nil)
        #expect(script.steps[0].name == "expectStoredRecording")
        #expect(PlaytestStep.names.contains("expectStoredRecording"))
    }

    @Test("An expectStoredRecording step can widen how close the duration must be")
    func expectStoredRecordingTakesATolerance() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectStoredRecording", "seconds": 6, "within": 1 } ] }
        """)
        guard case .expectStoredRecording(_, let within, _) = script.steps[0] else {
            Issue.record("expectStoredRecording"); return
        }
        #expect(within == 1)
    }

    // The hidden original is what makes the edit reversible, so a walk has to
    // be able to say it is there (or that it is not, before the first save).
    @Test("An expectStoredRecording step can claim the untouched original beside it")
    func expectStoredRecordingClaimsTheOriginal() throws {
        let script = try decode("""
        { "steps": [ { "do": "expectStoredRecording", "original": true } ] }
        """)
        guard case .expectStoredRecording(let seconds, _, let original) = script.steps[0] else {
            Issue.record("expectStoredRecording"); return
        }
        #expect(seconds == nil)
        #expect(original == true)
    }

    @Test("An expectStoredRecording step has to claim something")
    func expectStoredRecordingNeedsAClaim() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectStoredRecording" } ] }
            """)
        }
    }

    @Test("A negative tolerance is refused when the script is read")
    func expectStoredRecordingRefusesANegativeTolerance() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "steps": [ { "do": "expectStoredRecording", "seconds": 6, "within": -1 } ] }
            """)
        }
    }

    // MARK: - Saving a recording from a walk

    @Test("A walk can run the save a recording's Command S runs")
    func videoSaveIsAnAction() throws {
        let script = try decode("""
        { "steps": [ { "do": "action", "action": "videoSave" } ] }
        """)
        guard case .action(let action) = script.steps[0] else {
            Issue.record("action"); return
        }
        #expect(action == .videoSave)
        #expect(action.drivesRecording)
    }

    // The close sheet is its own path into the save, and it is the one the
    // user's report says does nothing, so a walk has to be able to press it.
    @Test("A walk can press Save in the close confirmation")
    func videoSaveForCloseIsAnAction() throws {
        let script = try decode("""
        { "steps": [ { "do": "action", "action": "videoCloseAndSave" } ] }
        """)
        guard case .action(let action) = script.steps[0] else {
            Issue.record("action"); return
        }
        #expect(action == .videoCloseAndSave)
        #expect(action.drivesRecording)
    }

    @Test("A walk can put the whole recording back the way Revert to Original does")
    func videoRevertToOriginalIsAnAction() throws {
        let script = try decode("""
        { "steps": [ { "do": "action", "action": "videoRevertToOriginal" } ] }
        """)
        guard case .action(let action) = script.steps[0] else {
            Issue.record("action"); return
        }
        #expect(action == .videoRevertToOriginal)
        #expect(action.drivesRecording)
    }
}
