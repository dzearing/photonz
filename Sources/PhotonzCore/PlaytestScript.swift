import CoreGraphics
import Foundation

/// A scripted playtest: the JSON file an unmanned run hands the probe build so
/// it drives the real editor with synthesized keys and clicks, renders the
/// window offscreen at the moments the script asks for, and leaves a log.
///
/// Only the script lives here (pure, so a malformed file fails with a readable
/// error before anything runs); the AppKit driver that performs the steps is
/// `PlaytestHarness` in the app, compiled only into non-shipping builds and
/// switched on only in the probe bundle. How to run one:
/// `docs/design/playtest-harness.md`.
public struct PlaytestScript: Sendable, Equatable {
    /// Where renders and the log go. Absolute, or relative to the script; nil
    /// means an `out` folder beside the script.
    public var out: String?
    public var steps: [PlaytestStep]

    public init(out: String? = nil, steps: [PlaytestStep]) {
        self.out = out
        self.steps = steps
    }

    /// Parses a script, naming the step and field of the first problem.
    public static func decode(_ data: Data) throws -> PlaytestScript {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PlaytestScriptError.invalidJSON(error.localizedDescription)
        }
        guard let top = raw as? [String: Any] else {
            throw PlaytestScriptError.invalidJSON("the top level must be an object with a \"steps\" array")
        }
        guard let rawSteps = top["steps"] as? [Any] else {
            throw PlaytestScriptError.invalidJSON("\"steps\" is missing or not an array")
        }
        let steps = try rawSteps.enumerated().map { index, entry -> PlaytestStep in
            guard let fields = entry as? [String: Any] else {
                throw PlaytestScriptError.invalidField(index: index, step: "?", field: "do", reason: "each step is an object")
            }
            return try PlaytestStep(index: index, fields: fields)
        }
        return PlaytestScript(out: top["out"] as? String, steps: steps)
    }

    /// The folder renders and the log land in, resolved against the script's
    /// own location so a script folder can travel with its output.
    public func outputDirectory(besides scriptURL: URL) -> URL {
        let folder = scriptURL.deletingLastPathComponent()
        guard let out, !out.isEmpty else { return folder.appendingPathComponent("out") }
        if out.hasPrefix("/") { return URL(fileURLWithPath: out) }
        return folder.appendingPathComponent(out).standardizedFileURL
    }
}

/// Why a script did not parse, worded for the person editing the file.
public enum PlaytestScriptError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidJSON(String)
    case unknownStep(index: Int, name: String)
    case invalidField(index: Int, step: String, field: String, reason: String)

    public var description: String {
        switch self {
        case .invalidJSON(let why):
            "playtest script is not valid: \(why)"
        case .unknownStep(let index, let name):
            "step \(index + 1): \"\(name)\" is not a step; use one of \(PlaytestStep.names.joined(separator: ", "))"
        case .invalidField(let index, let step, let field, let reason):
            "step \(index + 1) (\(step)): \"\(field)\" \(reason)"
        }
    }
}

/// A key the script can press, named the way a person would type it: a single
/// character for anything with a glyph, a word for the rest.
public struct PlaytestKey: Hashable, Sendable {
    public let name: String
    /// What the key types (arrow keys carry their function-key scalar).
    public let characters: String
    /// The ANSI virtual key code AppKit expects on a synthesized event.
    public let keyCode: UInt16

    public init?(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count == 1, let code = Self.glyphCodes[trimmed.lowercased()] {
            self.init(name: trimmed, characters: trimmed, keyCode: code)
            return
        }
        guard let named = Self.namedKeys[trimmed.lowercased()] else { return nil }
        self.init(name: trimmed, characters: named.characters, keyCode: named.keyCode)
    }

    private init(name: String, characters: String, keyCode: UInt16) {
        self.name = name
        self.characters = characters
        self.keyCode = keyCode
    }

    /// What this key really types with those modifiers held down: a capital
    /// letter under shift, the upper glyph of a number or punctuation key,
    /// and the same character as ever for keys with no shifted form.
    ///
    /// A synthesized press has to carry this, because it is what AppKit reads
    /// when it matches a shortcut: an event that said ⇧M was a plain "m"
    /// would be telling the app something no keyboard ever sends, and any
    /// shortcut written with a capital letter would silently never fire.
    /// Shift is the only modifier that changes what a key types; ⌘ and ⌥ do
    /// not, and are ignored here on purpose.
    public func characters(with modifiers: [PlaytestModifier]) -> String {
        guard modifiers.contains(.shift) else { return characters }
        return Self.shiftedGlyphs[characters] ?? characters.uppercased()
    }

    /// The upper glyph of every key on the US layout that has one. Letters
    /// are not here: uppercasing covers them.
    private static let shiftedGlyphs: [String: String] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^",
        "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
        "[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"",
        ",": "<", ".": ">", "/": "?", "`": "~",
    ]

    private static let glyphCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    private static let namedKeys: [String: (characters: String, keyCode: UInt16)] = [
        "return": ("\r", 36), "enter": ("\r", 36),
        "tab": ("\t", 48),
        "space": (" ", 49),
        "delete": ("\u{7F}", 51), "backspace": ("\u{7F}", 51),
        "escape": ("\u{1B}", 53), "esc": ("\u{1B}", 53),
        "left": ("\u{F702}", 123), "right": ("\u{F703}", 124),
        "down": ("\u{F701}", 125), "up": ("\u{F700}", 126),
    ]
}

/// Modifier keys by their Mac names.
public enum PlaytestModifier: String, CaseIterable, Hashable, Codable, Sendable {
    case command, shift, option, control
}

/// Which coordinates a point is in: the document's pixels (top-left origin,
/// what a person reads off the image), the canvas view's points, or the whole
/// window's points, measured from its top-left corner — the only way to name a
/// spot that is NOT on the picture, like the right hand panel or the bar above
/// it.
public enum PlaytestSpace: String, Hashable, Codable, Sendable {
    case document, view, window
}

public struct PlaytestPoint: Hashable, Sendable {
    public var point: CGPoint
    public var space: PlaytestSpace

    public init(_ point: CGPoint, space: PlaytestSpace = .document) {
        self.point = point
        self.space = space
    }
}

/// Something a script can wait on instead of sleeping a guessed number of
/// seconds.
public enum PlaytestCondition: Hashable, Sendable {
    /// The editor has finished detecting element edges, so Size and Gap have
    /// something to land on.
    case edgeMap
    /// A caption field has the keyboard.
    case captionField
    case tool(Tool)
    case measureMode(MeasureToolMode)
}

/// A direct call on the editor, for when a shortcut is not honoured by a
/// synthesized event and the script still needs the outcome. The inspector
/// toggle is a button and the zoom commands are menu chords, so a walk that
/// needs the canvas wide or the picture big asks for it here.
/// Which way round the probe draws itself for the shots that follow.
public enum PlaytestAppearance: String, CaseIterable, Hashable, Codable, Sendable {
    case light, dark, system
}

public enum PlaytestAction: String, CaseIterable, Hashable, Codable, Sendable {
    case copySpecList, copyImage, hideAllMeasurements, showAllMeasurements
    case hideInspector, showInspector, zoomIn, zoomOut, zoomToFit
    /// Undo and redo are menu chords too, so a walk that checks an undo step
    /// asks for it here.
    case undo, redo
    /// Save the layers beside the picture this window was opened from, the way
    /// saving a capture keeps its layers. A walk uses it to prove what comes
    /// back the next time the same file is opened, which no dialog-driven save
    /// could do from a background process.
    case saveLayers
    /// Open the New Canvas sheet, so a walk can photograph it. A snapshot
    /// taken while a sheet is up photographs the sheet.
    case newCanvasDialog
    /// Answer the New Canvas sheet with the size it opens on, which is what
    /// pressing Return in it does. A sheet cannot be typed into from a walk,
    /// so this is how a walk proves where the canvas lands.
    case createCanvas
    /// Throw away every picture the layers panel has made, so the next line
    /// measures what a document costs to open COLD. Nothing a person can do,
    /// and nothing the shipping app carries: it is the one moment worth
    /// measuring (a window adopting a document empties the same cache) made
    /// reachable without saving and reopening a hundred layer file.
    case forgetThumbnails
    /// ⌘G and ⇧⌘G are menu chords too.
    case group, ungroup
    /// Layer ▸ Stack Selection and Grid Selection (Next, `next-auto-layout`):
    /// the picked layers become one group that arranges them, or the picked
    /// group starts arranging itself.
    case stackSelection, gridSelection
    /// Layer ▸ Select Original: jumps from a copy of a component to the
    /// original it follows, so a walk can edit the original after dropping a
    /// copy without hunting for its row.
    case selectComponentOriginal
    /// Layer ▸ Delete Layer, which is a menu chord (⌘⌫) and so cannot be
    /// pressed in a walk. A walk that checks what happens after something is
    /// taken away asks for it here.
    case deleteLayer
    /// Edit ▸ Copy and Edit ▸ Paste. Both are menu chords, which do nothing
    /// while the probe is not the active app, so a walk that checks where a
    /// pasted layer lands asks for them here.
    case copyLayer, pasteLayer
    /// The frame rows in the Layer menu (Next, `next-frames`): the size sheet,
    /// and putting a frame around what is selected.
    case newFrameDialog, frameSelection
    /// The Export sheet, so a walk can photograph its frame scope.
    case exportDialog
    /// The View menu's Library rows (Next, `next-library`), so a walk can
    /// photograph the shelf.
    case showLibrary, hideLibrary
    /// Layer > Make Component (Next, `next-components`), a menu chord too, so
    /// a walk can promote a group and photograph what it becomes.
    case makeComponent
    /// Pick the first component on the Library shelf, which is what a click on
    /// its tile does. A walk cannot reach the dock with the pointer, so this is
    /// how the picked component's own section gets photographed.
    case pickFirstComponent
    /// Place the picked Library tile in the picture, which is what the item
    /// section's button and a double click on the tile both do.
    case placeLibraryPick
    /// Layer ▸ Insert Component (Next, `next-components`): puts a copy of the
    /// component picked on the shelf in the middle of what is on screen.
    case insertPickedComponent
    /// Pick the Canvas row, which is what a click on it in the layers dock
    /// does. A walk cannot reach the dock with the pointer, so this is how the
    /// Canvas section's own numbers get typed into.
    case selectCanvas
    /// Rename the selected layer to "Renamed Layer". Renaming happens in the
    /// layers dock, which a walk cannot reach with the pointer, so this is how
    /// a walk proves a name can be changed after the fact and that undo puts
    /// the old one back.
    case renameSelectedLayer
    /// OPEN the selected layer's rename field in the dock, the way
    /// double-clicking its name does, and leave it holding the keyboard. The
    /// row only becomes a field while you are renaming, so this is the only way
    /// a walk can type into one and watch what Return does with the keyboard
    /// afterwards.
    case beginRenameSelectedLayer
    /// Layer ▸ Duplicate Layer. ⌘J is a menu chord, so a walk that checks what
    /// a duplicate keeps asks for it here.
    case duplicateLayer
    /// Expose the first piece of the selected original that could take a
    /// wording knob (Next, `next-components`, step C6). The Add menu is in the
    /// dock, which a walk cannot reach with the pointer, so this is how a knob
    /// gets made before a copy is photographed setting it.
    case exposeWording
    /// The same for a choice: expose the first group inside the selected
    /// original that holds alternatives.
    case exposeChoice
    /// Save as Style on the selected layer's first painted color (Next,
    /// `next-styles`, step D8): opens the name field under that color row. The
    /// button is in the dock, which a walk cannot reach with the pointer, so
    /// this is the way in; the field itself is then a `focus` and a `type`
    /// like any other, and Return saves.
    case saveColorStyle
    /// Point the selected layer's first color at the first style on the shelf,
    /// which is what picking a name out of a color row's menu does.
    case useFirstColorStyle
    /// Let go of the style painting the selected layer's first color, keeping
    /// the color it is wearing.
    case unlinkColorStyle
    /// Paint every picked layer's first color one crimson (#B0184A), which is
    /// what choosing a color in the whole-selection row's well does. The well
    /// opens a popover in the dock, which a walk cannot reach with the pointer,
    /// so this is how one color landing on three boxes gets photographed.
    case paintSelectionColor
    /// Flip the Fill row's checkbox for everything picked, which is what
    /// clicking it in the Color section does: it switches a box's inside, or a
    /// frame's surface, on or off across the whole selection.
    case toggleFillSwitch
    /// Give every picked layer a border, which is what pulling the Effects
    /// section's Border slider off zero over a selection does. It is what puts
    /// the Border row in the Color section, so a walk can photograph it.
    case borderSelection
    /// Paint every picked layer's BORDER one crimson (#B0184A), which is what
    /// choosing a color in the Border row's well does. Same reason as
    /// `paintSelectionColor`: the well opens a popover a walk cannot reach.
    case paintSelectionBorderColor
    /// Open the name field under the Border row, which is what Save as Style
    /// on that row does. The field takes typing like any other, and Return
    /// saves the border color under that name.
    case saveBorderColorStyle
    /// Paint every picked layer's first gradient-taking slot with a straight
    /// gradient running out of the colour it already has, which is what
    /// choosing Linear in the picker's type row does. The type row is inside a
    /// popover a walk cannot reach with a pointer, so this is the way in.
    case paintSelectionGradient
    /// The same, sweeping around the middle instead, so a walk can show more
    /// than one kind of gradient without four separate actions.
    case paintSelectionAngularGradient
    /// Arm the tool in your hand with a straight gradient running out of the
    /// colour it already has, which is what choosing Linear in the toolbar
    /// swatch's picker does. It reaches the tool's interior when it has one
    /// and its outline otherwise. The type row is inside a popover a walk
    /// cannot reach with a pointer, so this is the way in.
    case armToolGradient
    /// The same, sweeping around the middle instead.
    case armToolAngularGradient
    /// Open the toolbar swatch's picker on what the tool in your hand draws
    /// its outline (or a text block its ink) in, which is what clicking that
    /// swatch does.
    case openToolColorPicker
    /// The same, on the toolbar's Fill swatch: the interior the next box comes
    /// out with.
    case openToolFillPicker
    /// Open the color picker on the Color section's first painted row, which
    /// is what clicking that row's swatch does. The dock is out of a walk's
    /// pointer reach, so this is how the picker itself gets photographed.
    case openColorPicker
    /// The same, on the Shadow section's color row, so a walk can show the one
    /// picker turning up in a second place.
    case openShadowColorPicker
    /// Shut whichever picker is open, the way Escape or the picker's own close
    /// button does.
    case closeColorPicker
    /// Save style inside the open picker, on the color the picker is holding.
    /// The button is inside a popover, which a walk cannot reach with the
    /// pointer, so this is the way in; the name is typed and Return saves.
    case saveStyleFromPicker
    /// Pick the first style on the Library shelf, which is what a click on its
    /// tile does, so its own section can be photographed.
    case pickFirstColorStyle
    /// Repaint the picked style green (#00A870), which is what dragging the
    /// Style section's color well to a new color does: everything wearing it
    /// follows in one step.
    case recolorPickedColorStyle
    /// Turn the picked style's ramp a quarter turn and cool its far end, which
    /// is what re-aiming a saved gradient in the Style section's picker does:
    /// every shape wearing it follows, in one step. A flat style becomes a
    /// gradient, which is the other half of the same control.
    case reaimPickedColorStyle
    /// Move the selected copy's first choice knob on to its next option, which
    /// is what picking the next row in that knob's menu does. A walk cannot
    /// open a menu in the dock, so this is how a swapped shape is photographed.
    case cycleChoice
    /// Layer ▸ Make Alternatives (the C6 follow-up): turns the selected shapes
    /// into a set of alternatives with a choice knob over them, so a walk can
    /// photograph the one-step path instead of grouping by hand first.
    case makeChoice
    /// Layer ▸ Detach Instance, so a walk can show a copy stop following.
    case detachInstance
    /// Style the selected layer the way the Effects and Shadow sliders do:
    /// round its corners, give it a shadow, fade it. The sliders live in the
    /// dock, which a walk cannot reach with the pointer, so this is how a look
    /// gets set on an original or on one copy.
    case roundCorners, addShadow, fadeLayer, fadeLayerSlightly, borderLayer
    /// The Effects and Shadow sliders as a person drags them, over EVERYTHING
    /// picked: a few live frames and then a release, so a walk exercises the
    /// same preview-and-commit path the panel does rather than a shortcut past
    /// it. One undo step lands per drag, however many layers it reached.
    case dragCornerRadius, dragOpacity
    /// A colour drag in the picker, taken in two halves so a walk can stand in
    /// the middle of one. `holdColorDrag` pushes a few live frames at the
    /// picked layers' first colour row and STAYS DOWN, which is the moment
    /// worth photographing: the canvas has followed the drag and nothing has
    /// reached history yet. `releaseColorDrag` lets go, which is the one undo
    /// step and the one recents entry for the whole gesture.
    ///
    /// The picker is a popover a walk cannot reach with the pointer, so this
    /// is how the same preview-and-commit path it takes gets exercised.
    case holdColorDrag, releaseColorDrag
    /// The type rows over the whole selection (`ui-building`, step D9): the
    /// Size menu set to 14pt, and the Weight menu set to Bold. Both are menus
    /// in the dock, which a walk cannot reach with the pointer, so this is how
    /// a walk proves one pick reached every picked label.
    /// The Zoom Callout section's own two controls, which live in the dock and
    /// so cannot be reached with the pointer: pull Magnification to 4x the way
    /// a slider drag does (preview, then one committed undo step), and switch
    /// the Shape row to Circle.
    case magnifyCallout, roundCallout
    /// The Zoom Callout TOOL's Shape row, which is the choice made with the
    /// tool in your hand and before any callout exists. Also in the dock, so
    /// also out of a pointer's reach.
    case armCalloutCircle, armCalloutRectangle
    case setTextSize, setTextWeight
    /// The same menus set the other way, so a walk can put the picked labels
    /// into a known state whatever the last walk left the new-text default at.
    case setTextSizeLarge, setTextWeightRegular
    /// The shape rows over the whole selection: one pull on Thickness, and one
    /// on Corner Radius, reaching every picked shape.
    case dragThickness, dragShapeCorners
    /// The same two sliders pulled the other way, so a walk can put the picked
    /// shapes into a known state whatever the last walk left the shape default
    /// at (each kind remembers what its last object was set to).
    case dragThicknessThin, dragShapeCornersSquare
    /// The Shadow section's switch, over the whole selection.
    case toggleShadow
    /// Put the selected copy's whole look back to the original's, which is
    /// what the way back on its section does.
    case followOriginalLook
    /// Put the Library in the dock with its Components shelf showing (Next,
    /// `next-starter-components`). The segmented control is in the dock, which
    /// a walk cannot reach with the pointer, so this is how the shelf the app
    /// arrives stocked with gets photographed.
    case showComponentShelf
    /// ...and the Media shelf, which is where the captures the app already
    /// keeps are. Which scope the shelf opens on is remembered between runs, so
    /// a walk that wants one says so rather than hoping.
    case showMediaShelf
    /// Layer ▸ Align and Layer ▸ Space Evenly (Next, `next-align-layers`).
    /// The buttons are in the dock, which a walk cannot reach with the
    /// pointer, and the menu chords do nothing while the probe is not the
    /// active app, so this is how a walk lines a selection up.
    case alignLeft, alignHorizontalCenter, alignRight
    case alignTop, alignVerticalCenter, alignBottom
    case spaceEvenlyAcross, spaceEvenlyDown
    /// Step into the selected group and pick the first piece inside it, which
    /// is what a double click on that piece does. A walk cannot know where a
    /// component landed on screen, so this is how one of its insides gets
    /// photographed.
    case stepIntoSelection
    /// Move along to the next piece in the group already stepped into,
    /// wrapping at the end — what clicking the piece beside it does.
    case pickNextSibling
    /// Go to the first piece the selected group lists as having a rule of its
    /// own, which is what clicking that name in the Layout section does (Next,
    /// `next-placement`). The list is in the dock, which a walk cannot reach
    /// with the pointer, so this is how a walk shows where a name leads.
    case pickFirstOwnRule
    /// Set the selected layer's own rule to Stretch across (Next,
    /// `next-placement`), which is what picking Stretch in the Layout
    /// section's Horizontal menu does. The menu is in the dock, which a walk
    /// cannot reach with the pointer, so this is how a walk proves a rule set
    /// by hand survives the next resize.
    case stretchSelectionAcross
    /// The same DOWN the box, which is what picking Stretch in that section's
    /// Vertical menu does. It is how a walk shows a label filling the height
    /// of the row holding it instead of hugging one line of words.
    case stretchSelectionDown
    /// Set the selected GROUP's rule for everything inside it to Stretch
    /// across (Next, `next-placement`), which is what picking Stretch in the
    /// Layout section's Horizontal menu under "Contents of" does. Same reason
    /// as above: the menu is in the dock, which a walk cannot reach with the
    /// pointer, and this is the switch that makes every row of a stack fill
    /// the width the stack was given.
    case stretchContentsAcross
    /// Put the selected text's words back on the left of the box they fill,
    /// which is what the Text section's Align row does (Next,
    /// `next-placement`). The control is in the dock, which a walk cannot
    /// reach with the pointer, so this is how a walk shows that where the
    /// words sit after a stretch is still the user's to change.
    case alignWordsLeft
    /// Paint the selected screen's surface a strong colour, which is what the
    /// Frame section's Background swatch does. The swatch is in the dock,
    /// which a walk cannot reach with the pointer, and a white screen is the
    /// one surface a white halo behind dark text cannot be seen against, so
    /// this is how a walk photographs the halo rule at all.
    case paintScreenSurface
    /// Put every sheet away. Escape reaches the window, not the sheet in front
    /// of it, so a walk that photographs a sheet needs a way back out.
    case closeSheets
}

/// What a `hover` step rests the pointer on.
/// Where a row being dragged in the layers list would land: on the line above
/// the row under the pointer, on the line below it, or inside it when that row
/// is a group. It is what the drop line on screen is saying.
public enum PlaytestDropZone: String, CaseIterable, Hashable, Codable, Sendable {
    case above, inside, below
}

public enum PlaytestHoverTarget: Sendable, Equatable {
    /// The control whose tooltip begins with this text ("Arrow", "Measure").
    case label(String)
    /// A point; over no control it rests in the open.
    case point(PlaytestPoint)
}

public enum PlaytestStep: Sendable, Equatable {
    /// Open a file in an editor window and wait until it is ready to drive.
    /// The window is kept invisible; `size` sets its frame first.
    case open(file: String, size: CGSize?)
    /// Start from nothing: a new window given a blank canvas of `canvas`,
    /// waited on until it can be driven, the way clicking Blank canvas in an
    /// empty window and taking the offered size does. `window` sets the window
    /// frame, as `open` does.
    /// `card` names a snapshot taken of the EMPTY window, before the canvas
    /// exists: the onboarding card is the only thing on screen then, and this
    /// is the only way a walk can photograph it.
    case blank(canvas: CGSize, window: CGSize?, card: String?)
    case wait(seconds: Double)
    /// Press and release a key, through the window (or the app, for chords so
    /// menu shortcuts are found).
    case key(PlaytestKey, [PlaytestModifier])
    /// Press a chord and REQUIRE it to reach a menu item, failing the walk
    /// when it does not. `key` sends a chord and reports whoever took it,
    /// which is fine for a press that is meant to land in a text field but
    /// useless for proving a menu shortcut works: a chord that lands on a
    /// dead or dimmed item still reads as "taken by menu". This step looks
    /// the item up first, says which one it is, refuses a dimmed one, and
    /// only then presses. `menuItem` names the item the chord must reach
    /// ("Undo"), so a walk fails when a shortcut is quietly reassigned.
    case shortcut(PlaytestKey, [PlaytestModifier], menuItem: String?)
    /// Press and release a key by handing it to the APPLICATION rather than
    /// straight to a window.
    ///
    /// `key` posts into the window, which is right for typing and for menu
    /// shortcuts but invisible to anything watching the app as a whole. The
    /// history overlay is exactly that: Esc and click-away take it down through
    /// an application-wide event monitor, and a monitor only ever sees what
    /// goes through the app. This step is how a walk reaches those.
    case appKey(PlaytestKey, [PlaytestModifier])
    case move(PlaytestPoint)
    /// Rest the pointer on a control (named by the label its tooltip shows,
    /// or by a point) long enough for its tooltip to appear. A point over no
    /// control rests in the open and hides whatever was showing.
    case hover(PlaytestHoverTarget)
    case click(PlaytestPoint, count: Int, modifiers: [PlaytestModifier])
    /// `hold` names a snapshot taken with the button still DOWN, just before
    /// the release: the only way to photograph anything that exists only while
    /// a drag is in hand, like the yellow snap guide.
    case drag(from: PlaytestPoint, to: PlaytestPoint, steps: Int,
              modifiers: [PlaytestModifier], hold: String?)
    /// Insert text into whatever field has the keyboard.
    case type(String)
    /// Give the keyboard to a named text field in the inspector (its label, as
    /// the field shows it: "W", "H", "X"). Everything after it — `type`, `key`
    /// tab, an arrow key — then goes to that field, the way it would for a
    /// person who clicked it.
    case focus(field: String)
    /// Pick a tool directly, for when its key was not honoured.
    case tool(Tool)
    /// Press I until the Measure tool is in this mode.
    case measureMode(MeasureToolMode)
    case waitFor(PlaytestCondition, timeout: Double)
    /// Drop the component picked on the Library shelf onto the canvas at a
    /// point, which is where a drag off the shelf ends. A synthesized mouse
    /// drag cannot start a real drag session, so this lands the drop the way
    /// the canvas's drag destination does, pasteboard and all.
    case dropComponent(at: PlaytestPoint)
    /// Hold the component picked on the Library shelf over a point WITHOUT
    /// letting go, so a `snapshot` taken next photographs the landing outline
    /// and the frame it would join. The log line says what the canvas answered.
    case dragComponent(at: PlaytestPoint)
    /// A file let go over the canvas, the way one arrives from the Finder.
    /// `file` is relative to the script, like `open`. `hold` names a picture
    /// taken while the file is still in the air over the point, which is the
    /// only moment the landing outline exists.
    case dropImage(file: String, at: PlaytestPoint, hold: String?)
    /// A file held over the canvas WITHOUT letting go, the way one hovers on
    /// the way in from the Finder. The log line says what the canvas answered:
    /// that it would place a copy, or that it refuses the file outright, which
    /// is the only way a walk can record the no-entry pointer a text file or an
    /// archive gets. `file` is relative to the script, like `open`; `hold`
    /// names a picture taken while it is still in the air.
    case dragFile(file: String, at: PlaytestPoint, hold: String?, release: Bool)
    /// Render the window's content offscreen to `<out>/<name>.png`.
    ///
    /// `window` names another of the app's windows to photograph instead of the
    /// editor's, by its title: the history overlay is its own floating panel,
    /// so it is the only way to get a picture of it at all.
    case snapshot(name: String, window: String?)
    /// Composite the document itself to `<out>/<name>.png`, at `scale` output
    /// pixels per document point — 1 for the picture as it is, 2 for the one
    /// the export dialog's 2x hands back.
    case render(name: String, scale: CGFloat)
    /// Open a menu that lives INSIDE the window — the Add menu on a
    /// component's Adjustable list, the ellipsis on the Measurements header —
    /// write its rows to the log, photograph it if `shot` names a picture, and
    /// either pick one of its rows (`choose`) or close it having chosen
    /// nothing.
    ///
    /// A menu is a window of its own that takes the app hostage while it is
    /// open, which is why a walk could not do this before: clicking the button
    /// never returns until the menu closes, and nothing was left running to
    /// close it. The driver arranges its own way out first.
    case panelMenu(menu: String, shot: String?, choose: String?)
    /// Pick a tile up off the Library shelf by its name, hold it over a point
    /// on the picture, and let go there. `hold` names a picture taken while it
    /// is still in hand, which is the only moment the landing outline exists.
    case dragTile(tile: String, to: PlaytestPoint, hold: String?)
    /// Pick a row up in the layers list by its name and let go of it on
    /// another row: above it, below it, or inside it when that row is a group.
    /// `hold` names a picture taken before letting go, which is the only
    /// moment the line that says what will happen is on screen.
    case dragRow(row: String, onto: String, zone: PlaytestDropZone, hold: String?)
    /// Click a row in the layers list by the name it shows, the way a person
    /// picks a layer out of the list rather than off the picture. `modifiers`
    /// read as they do under a pointer: shift ranges from the anchor row,
    /// command adds or removes.
    ///
    /// This is the only way to select a layer the canvas will not give you: a
    /// locked one, which a click on the picture falls straight through.
    case selectRow(row: String, modifiers: [PlaytestModifier])
    /// Write what the right hand panel is showing to the log and to
    /// `panel-<stage>.json`: every tile on the shelf, every row in the layers
    /// list, and every menu in the dock, by the names a walk has to use for
    /// them. The `menus` step for the panel.
    case panel(stage: String)
    /// Turn the wheel over a panel that scrolls, by `by` points (negative goes
    /// down the list). A list that builds only the rows you can see has to be
    /// scrolled to prove the rest arrive, and that is not something a click can
    /// do.
    ///
    /// `row` names a row to turn the wheel over. Leave it out to scroll the
    /// layers list wherever it happens to be sitting: after a few turns the row
    /// a walk started from has scrolled away and is no longer built, so naming
    /// one every time is a step that stops working halfway down the list.
    case scrollPanel(row: String?, by: Double)
    /// Write the editor's state (tool, mode, layers, hint, clipboard note) to
    /// the log under `stage`.
    case describe(stage: String, note: String?)
    case clearClipboard
    /// Log what is on the clipboard.
    case readClipboard(stage: String)
    /// Write the app's own menu bar to the log and to `menus-<stage>.json`:
    /// every menu, item, shortcut and enabled state, exactly as it reads on
    /// screen. `menu` narrows it to one top-level menu by title.
    ///
    /// This is how an unmanned runner names a real menu item. Reading ANOTHER
    /// app's menus needs an Accessibility grant only a person can give, but the
    /// probe is our own app and can always say what is in its own menu bar.
    case menus(stage: String, menu: String?)
    /// Put the probe into light or dark for the shots that follow, so one walk
    /// can photograph a surface both ways. It changes THIS app only, never the
    /// machine's setting, so nothing outside the probe notices.
    case appearance(PlaytestAppearance)
    case action(PlaytestAction)

    public static let defaultTimeout: Double = 10
    public static let defaultDragSteps = 8

    /// Every step name, sorted, as the error text and the doc list them.
    public static let names: [String] = [
        "action", "appKey", "appearance", "blank", "clearClipboard", "click", "describe", "drag", "dragComponent",
        "dragFile", "dragRow", "dragTile", "dropComponent",
        "dropImage", "focus", "hover", "key", "measureMode", "menus", "move", "open",
        "panel", "panelMenu",
        "readClipboard", "render", "scrollPanel", "shortcut", "snapshot", "tool", "type", "wait", "waitFor",
    ]

    /// The `do` name this step answers to.
    public var name: String {
        switch self {
        case .open: "open"
        case .appearance: "appearance"
        case .blank: "blank"
        case .wait: "wait"
        case .key: "key"
        case .shortcut: "shortcut"
        case .appKey: "appKey"
        case .move: "move"
        case .hover: "hover"
        case .click: "click"
        case .drag: "drag"
        case .type: "type"
        case .focus: "focus"
        case .tool: "tool"
        case .measureMode: "measureMode"
        case .waitFor: "waitFor"
        case .dropComponent: "dropComponent"
        case .dragComponent: "dragComponent"
        case .dropImage: "dropImage"
        case .dragFile: "dragFile"
        case .snapshot: "snapshot"
        case .render: "render"
        case .panelMenu: "panelMenu"
        case .dragTile: "dragTile"
        case .dragRow: "dragRow"
        case .selectRow: "selectRow"
        case .panel: "panel"
        case .scrollPanel: "scrollPanel"
        case .describe: "describe"
        case .clearClipboard: "clearClipboard"
        case .readClipboard: "readClipboard"
        case .menus: "menus"
        case .action: "action"
        }
    }

    init(index: Int, fields: [String: Any]) throws {
        guard let name = fields["do"] as? String else {
            throw PlaytestScriptError.invalidField(index: index, step: "?", field: "do", reason: "is missing")
        }
        let f = Fields(index: index, step: name, fields: fields)
        switch name {
        case "open":
            let width = try f.optionalNumber("width"), height = try f.optionalNumber("height")
            let size: CGSize? = if let width, let height { CGSize(width: width, height: height) } else { nil }
            self = .open(file: try f.string("file"), size: size)
        case "blank":
            let canvasWidth = try f.optionalNumber("canvasWidth")
            let canvasHeight = try f.optionalNumber("canvasHeight")
            let canvas: CGSize = if let canvasWidth, let canvasHeight {
                CGSize(width: canvasWidth, height: canvasHeight)
            } else {
                BlankCanvas.defaultPreset.size
            }
            let width = try f.optionalNumber("width"), height = try f.optionalNumber("height")
            let window: CGSize? = if let width, let height { CGSize(width: width, height: height) } else { nil }
            self = .blank(canvas: canvas, window: window, card: try f.optionalString("card"))
        case "wait":
            self = .wait(seconds: try f.number("seconds"))
        case "key":
            let keyName = try f.string("key")
            guard let key = PlaytestKey(keyName) else {
                throw f.invalid("key", "\"\(keyName)\" is not a key; use a single character or return, escape, tab, space, delete, left, right, up, down")
            }
            self = .key(key, try f.modifiers())
        case "shortcut":
            let keyName = try f.string("key")
            guard let key = PlaytestKey(keyName) else {
                throw f.invalid("key", "\"\(keyName)\" is not a key; use a single character or return, escape, tab, space, delete, left, right, up, down")
            }
            self = .shortcut(key, try f.modifiers(), menuItem: try f.optionalString("menuItem"))
        case "appKey":
            let keyName = try f.string("key")
            guard let key = PlaytestKey(keyName) else {
                throw f.invalid("key", "\"\(keyName)\" is not a key; use a single character or return, escape, tab, space, delete, left, right, up, down")
            }
            self = .appKey(key, try f.modifiers())
        case "move":
            self = .move(try f.point("at"))
        case "hover":
            if fields["label"] != nil {
                self = .hover(.label(try f.string("label")))
            } else if fields["at"] != nil {
                self = .hover(.point(try f.point("at")))
            } else {
                throw f.invalid("label", "hover needs a \"label\" (the text the control's tooltip shows) or an \"at\" point")
            }
        case "click":
            let count = try f.optionalNumber("count").map { Int($0) } ?? 1
            self = .click(try f.point("at"), count: max(1, count), modifiers: try f.modifiers())
        case "drag":
            let steps = try f.optionalNumber("steps").map { Int($0) } ?? Self.defaultDragSteps
            self = .drag(from: try f.point("from"), to: try f.point("to"), steps: max(1, steps),
                         modifiers: try f.modifiers(), hold: try f.optionalString("hold"))
        case "type":
            self = .type(try f.string("text"))
        case "focus":
            self = .focus(field: try f.string("field"))
        case "tool":
            self = .tool(try f.enumValue("tool", Tool.self))
        case "measureMode":
            self = .measureMode(try f.enumValue("mode", MeasureToolMode.self))
        case "waitFor":
            let condition = try f.string("condition")
            let parsed: PlaytestCondition = switch condition {
            case "edgeMap": .edgeMap
            case "captionField": .captionField
            case "tool": .tool(try f.enumValue("value", Tool.self))
            case "measureMode": .measureMode(try f.enumValue("value", MeasureToolMode.self))
            default: throw f.invalid("condition", "\"\(condition)\" is not a condition; use edgeMap, captionField, tool or measureMode")
            }
            self = .waitFor(parsed, timeout: try f.optionalNumber("timeout") ?? Self.defaultTimeout)
        case "snapshot":
            self = .snapshot(name: try f.string("name"), window: try f.optionalString("window"))
        case "dropComponent":
            self = .dropComponent(at: try f.point("at"))
        case "dragComponent":
            self = .dragComponent(at: try f.point("at"))
        case "dropImage":
            self = .dropImage(file: try f.string("file"), at: try f.point("at"),
                              hold: try f.optionalString("hold"))
        case "dragFile":
            self = .dragFile(file: try f.string("file"), at: try f.point("at"),
                             hold: try f.optionalString("hold"),
                             release: try f.optionalFlag("release") ?? false)
        case "render":
            self = .render(name: try f.string("name"),
                           scale: CGFloat(try f.optionalNumber("scale") ?? 1))
        case "panelMenu":
            self = .panelMenu(menu: try f.string("menu"),
                              shot: try f.optionalString("shot"),
                              choose: try f.optionalString("choose"))
        case "dragTile":
            self = .dragTile(tile: try f.string("tile"), to: try f.point("to"),
                             hold: try f.optionalString("hold"))
        case "dragRow":
            let zone: PlaytestDropZone = if fields["zone"] == nil {
                .above
            } else {
                try f.enumValue("zone", PlaytestDropZone.self)
            }
            self = .dragRow(row: try f.string("row"), onto: try f.string("onto"),
                            zone: zone, hold: try f.optionalString("hold"))
        case "selectRow":
            self = .selectRow(row: try f.string("row"), modifiers: try f.modifiers())
        case "panel":
            self = .panel(stage: try f.string("stage"))
        case "scrollPanel":
            self = .scrollPanel(row: fields["row"] as? String, by: try f.number("by"))
        case "describe":
            self = .describe(stage: try f.string("stage"), note: fields["note"] as? String)
        case "clearClipboard":
            self = .clearClipboard
        case "readClipboard":
            self = .readClipboard(stage: try f.string("stage"))
        case "menus":
            self = .menus(stage: try f.string("stage"), menu: try f.optionalString("menu"))
        case "appearance":
            self = .appearance(try f.enumValue("value", PlaytestAppearance.self))
        case "action":
            self = .action(try f.enumValue("action", PlaytestAction.self))
        default:
            throw PlaytestScriptError.unknownStep(index: index, name: name)
        }
    }

    /// Typed access to one step's fields, so every problem reports the step,
    /// the field and what was expected.
    private struct Fields {
        let index: Int
        let step: String
        let fields: [String: Any]

        func invalid(_ field: String, _ reason: String) -> PlaytestScriptError {
            .invalidField(index: index, step: step, field: field, reason: reason)
        }

        func string(_ field: String) throws -> String {
            guard let value = fields[field] as? String, !value.isEmpty else { throw invalid(field, "must be a non-empty string") }
            return value
        }

        func optionalString(_ field: String) throws -> String? {
            guard let raw = fields[field] else { return nil }
            guard let value = raw as? String, !value.isEmpty else { throw invalid(field, "must be a non-empty string") }
            return value
        }

        func number(_ field: String) throws -> Double {
            guard let value = try optionalNumber(field) else { throw invalid(field, "must be a number") }
            return value
        }

        func optionalNumber(_ field: String) throws -> Double? {
            guard let raw = fields[field] else { return nil }
            guard let value = raw as? NSNumber else { throw invalid(field, "must be a number") }
            return value.doubleValue
        }

        func optionalFlag(_ field: String) throws -> Bool? {
            guard let raw = fields[field] else { return nil }
            guard let value = raw as? NSNumber else { throw invalid(field, "must be true or false") }
            return value.boolValue
        }

        func point(_ field: String) throws -> PlaytestPoint {
            guard let pair = fields[field] as? [NSNumber], pair.count == 2 else {
                throw invalid(field, "must be a pair of numbers, [x, y]")
            }
            let space: PlaytestSpace
            if let rawSpace = fields["space"] {
                guard let text = rawSpace as? String, let parsed = PlaytestSpace(rawValue: text) else {
                    throw invalid("space", "must be document, view or window")
                }
                space = parsed
            } else {
                space = .document
            }
            return PlaytestPoint(CGPoint(x: pair[0].doubleValue, y: pair[1].doubleValue), space: space)
        }

        func modifiers() throws -> [PlaytestModifier] {
            guard let raw = fields["modifiers"] else { return [] }
            guard let names = raw as? [String] else { throw invalid("modifiers", "must be a list of command, shift, option, control") }
            return try names.map { name in
                guard let modifier = PlaytestModifier(rawValue: name) else {
                    throw invalid("modifiers", "\"\(name)\" is not a modifier; use command, shift, option, control")
                }
                return modifier
            }
        }

        func enumValue<T: RawRepresentable & CaseIterable>(_ field: String, _ type: T.Type) throws -> T where T.RawValue == String {
            let text = try string(field)
            guard let value = T(rawValue: text) else {
                throw invalid(field, "\"\(text)\" is not one of \(T.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return value
        }
    }
}
