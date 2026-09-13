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
    /// What has to be put right before the first step runs.
    public var setup: PlaytestSetup
    public var steps: [PlaytestStep]

    public init(out: String? = nil, setup: PlaytestSetup = PlaytestSetup(), steps: [PlaytestStep]) {
        self.out = out
        self.setup = setup
        self.steps = steps
    }

    /// Everything a walk file may say at the top level. `seed` is prose about
    /// what the walk IS, for whoever reads it; anything it needs DONE goes in
    /// `setup`, where the runner can act on it.
    static let knownKeys = ["out", "seed", "setup", "steps"]

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
        // A misspelled key would otherwise be ignored in silence, which for
        // "setup" means a walk that says what it needs and is not heard.
        if let stray = top.keys.sorted().first(where: { !Self.knownKeys.contains($0) }) {
            throw PlaytestScriptError.invalidJSON(
                "\"\(stray)\" is not something a walk can say; it takes "
                    + Self.knownKeys.joined(separator: ", "))
        }
        let steps = try rawSteps.enumerated().map { index, entry -> PlaytestStep in
            guard let fields = entry as? [String: Any] else {
                throw PlaytestScriptError.invalidField(index: index, step: "?", field: "do", reason: "each step is an object")
            }
            return try PlaytestStep(index: index, fields: fields)
        }
        return PlaytestScript(out: top["out"] as? String,
                              setup: try PlaytestSetup(fields: top["setup"]),
                              steps: steps)
    }

    /// The folder renders and the log land in, resolved against the script's
    /// own location so a script folder can travel with its output.
    public func outputDirectory(besides scriptURL: URL) -> URL {
        Self.outputDirectory(besides: scriptURL, out: out)
    }

    /// The same folder, read straight out of the file before it is parsed.
    ///
    /// A run has to know where to write BEFORE it knows whether the script is
    /// any good, because the report a bad script most needs to leave is the one
    /// saying why it was bad. Anything unreadable falls back to the default
    /// folder beside the script rather than throwing: this answers a question
    /// about a path, not about whether the walk is valid.
    public static func outputDirectory(besides scriptURL: URL, in data: Data) -> URL {
        let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return outputDirectory(besides: scriptURL, out: top?["out"] as? String)
    }

    private static func outputDirectory(besides scriptURL: URL, out: String?) -> URL {
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
    case invalidSetup(field: String, reason: String)

    public var description: String {
        switch self {
        case .invalidJSON(let why):
            "playtest script is not valid: \(why)"
        case .unknownStep(let index, let name):
            if PlaytestAction(rawValue: name) != nil {
                "step \(index + 1): \"\(name)\" is an action, not a step; write it as "
                    + "{ \"do\": \"action\", \"action\": \"\(name)\" }"
            } else {
                "step \(index + 1): \"\(name)\" is not a step; use one of \(PlaytestStep.names.joined(separator: ", "))"
            }
        case .invalidField(let index, let step, let field, let reason):
            "step \(index + 1) (\(step)): \"\(field)\" \(reason)"
        case .invalidSetup(let field, let reason):
            "setup: \"\(field)\" \(reason)"
        }
    }
}

/// What a walk needs put right before its first step, said in a way the runner
/// can act on rather than in a note only a person can read.
///
/// Two walks used to pass only the first time they were ever run on a machine.
/// One changed the remembered text size and then looked for the old size next
/// time; the other needed a picture copied into the Screenshots folder first
/// and said so only in prose. Both are now one line of the walk.
public struct PlaytestSetup: Sendable, Equatable {
    /// Areas of the app's memory to put back to the values a machine that had
    /// never run Photonz would have, before the walk starts.
    public var forget: [PlaytestMemory]
    /// Pictures to place in the capture folder for the length of the walk, so
    /// the Library's Media shelf has them, and take away again afterwards.
    /// Paths are relative to the script, or absolute.
    public var captures: [String]
    /// Files to copy into an empty folder of the walk's own, which the walk
    /// names as "scratch/<file>" and which is thrown away at the end. This is
    /// for a walk that WRITES beside the picture it opened — saving layers next
    /// to it, say — so it starts from the same nothing every time and leaves no
    /// trace. Paths are relative to the script, or absolute.
    public var scratch: [String]

    public init(forget: [PlaytestMemory] = [], captures: [String] = [], scratch: [String] = []) {
        self.forget = forget
        self.captures = captures
        self.scratch = scratch
    }

    public var isEmpty: Bool { forget.isEmpty && captures.isEmpty && scratch.isEmpty }

    /// The known keys, named in the error when a walk uses another one.
    static let knownKeys = ["forget", "captures", "scratch"]

    init(fields raw: Any?) throws {
        guard let raw, !(raw is NSNull) else {
            self.init()
            return
        }
        guard let fields = raw as? [String: Any] else {
            throw PlaytestScriptError.invalidSetup(
                field: "setup", reason: "must be an object holding \(Self.knownKeys.joined(separator: " and/or "))")
        }
        if let stray = fields.keys.sorted().first(where: { !Self.knownKeys.contains($0) }) {
            throw PlaytestScriptError.invalidSetup(
                field: stray, reason: "is not something setup can ask for; it takes "
                    + Self.knownKeys.joined(separator: " and "))
        }
        let forget = try Self.words(fields["forget"], field: "forget").map { word -> PlaytestMemory in
            guard let memory = PlaytestMemory(rawValue: word) else {
                throw PlaytestScriptError.invalidSetup(
                    field: "forget", reason: "names \"\(word)\", which is not something the app remembers; "
                        + "it remembers " + PlaytestMemory.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return memory
        }
        self.init(forget: forget,
                  captures: try Self.words(fields["captures"], field: "captures"),
                  scratch: try Self.words(fields["scratch"], field: "scratch"))
    }

    private static func words(_ raw: Any?, field: String) throws -> [String] {
        guard let raw, !(raw is NSNull) else { return [] }
        guard let list = raw as? [Any] else {
            throw PlaytestScriptError.invalidSetup(field: field, reason: "must be an array")
        }
        return try list.map { entry in
            guard let word = entry as? String, !word.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw PlaytestScriptError.invalidSetup(field: field, reason: "takes words, and none of them empty")
            }
            return word
        }
    }
}

/// One area of the app's memory a walk can ask to have forgotten before it
/// starts. The probe keeps its settings between runs on purpose — that is what
/// a person's app does — so a walk that changes one of these says which.
public enum PlaytestMemory: String, CaseIterable, Sendable, Hashable, Codable {
    /// The font, size, weight and colour a new text block is made in.
    case text
    /// The recent colours, the foreground and background fills, and which
    /// tab the colour picker opens on.
    case color
    /// The look a new shape, arrow or callout is drawn in: its paint, its
    /// stroke, its corner radius and whether it has a fill at all.
    case shapes
    /// The Measure mode and the saved measure looks.
    case measure
    /// Which tool each family in the toolbar stands for, and the wand's reach.
    case tools
    /// Which groups in the layers list are open.
    case groups
    /// Whether the dock and the Library are showing, how wide the dock is, and
    /// which shelf the Library is on.
    case panel
    /// Whether the canvas grid is switched on, how far apart its lines are,
    /// how often one of them is stronger, and whether it draws rows as well as
    /// columns.
    case grid
    /// The size a new frame is offered at, which is the last one chosen.
    case frames
    /// Which guides have been finished and where you stopped in any left part
    /// way. A walk that photographs the Tutorials window forgets this first, or
    /// it photographs whatever the last run happened to leave behind.
    case tutorials
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
    /// A properties-panel section with this header is on screen WHOLE, without
    /// anyone touching the scroll wheel. "You can see the Rectangle section the
    /// moment you pick a rectangle" is then a step the walk fails on rather
    /// than a number a person reads back off the log afterwards.
    case sectionInView(String)
    /// ...and the weaker claim, for a section too tall to ever fit whole: its
    /// header is on screen, so you at least know the settings are there.
    case sectionHeaderInView(String)
    /// A guide is running and it is on this step, named by the step's id. What
    /// a walk waits on after doing the thing a waiting step asked for, so
    /// "picking the Measure tool really moved the guide on" is a step the walk
    /// fails on rather than a claim in a report.
    case tutorialStep(String)
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
    /// The two copies, called directly: ⌘C takes the layer you picked and
    /// ⇧⌘C takes every layer flattened together. A walk asks for them here
    /// because both are menu chords, and because what they leave on the
    /// clipboard is only visible after a paste.
    case copy, copyMerged, cut
    case hideInspector, showInspector, zoomIn, zoomOut, zoomToFit
    /// Take the window in and out of full screen. Full screen is where a Mac
    /// takes the title bar away, so anything that lives in the title bar has
    /// to be checked here rather than assumed.
    case toggleFullScreen
    /// Undo and redo are menu chords too, so a walk that checks an undo step
    /// asks for it here.
    case undo, redo
    /// Save the layers beside the picture this window was opened from, the way
    /// saving a capture keeps its layers. A walk uses it to prove what comes
    /// back the next time the same file is opened, which no dialog-driven save
    /// could do from a background process.
    case saveLayers
    /// Shut the editor window this walk is driving, the way a person closes a
    /// document. The next `open` then builds a window from scratch, reading the
    /// file and the app's memory again, which is the only way one walk can
    /// prove what comes BACK when a document is opened afresh. Without it that
    /// proof needs a second walk, and a walk that only passes when another one
    /// ran first is not a walk that can be trusted.
    case closeDocument
    /// Open the New Canvas sheet, so a walk can photograph it. A snapshot
    /// taken while a sheet is up photographs the sheet.
    /// The guided tutorials, driven from a walk (`TutorialController`).
    /// `startTour` is the real entry point: it opens the guide's OWN sample
    /// window, which is where the guide then runs, so a walk photographing it
    /// names that window. `startTourHere` runs the same guide over the window
    /// the walk is already driving, so the walk can press real controls with
    /// real coordinates and prove a waiting step advances on the thing itself.
    case startTour, startTourHere, tutorialNext, tutorialBack, tutorialClose
    /// Open (or close) the Tutorials window, the hub every guide is listed in.
    /// It is an ordinary app window, so a walk photographs it by name:
    /// `{ "do": "snapshot", "name": "hub", "window": "Tutorials" }`.
    case showTutorials, closeTutorials
    /// Read the Tutorials window the way a screen reader does, and press the
    /// first guide's own button the way a keyboard does. The window is an
    /// ordinary SwiftUI surface with no playtest markers in it, so this is how
    /// a walk proves its list is reachable and its buttons are wired.
    case readTutorialWindow, pressTutorialStart
    /// The first run, walked from a clean slate. `freshInstall` forgets
    /// everything the setup window remembers, so the next `launchHook` behaves
    /// like a machine that has never run Photonz; `oldInstall` instead pretends
    /// an install that finished its setup before tutorials existed, which is
    /// the upgrade that must not be shown first run setup again. `launchHook`
    /// is the launch itself: it runs exactly what the app runs at startup.
    case freshInstall, oldInstall, launchHook
    /// What the launch did. `expectWelcome` fails the walk when the setup
    /// window did not come up, `expectNoWelcome` when it did, which is how a
    /// walk proves an answer is remembered rather than asserting it in prose.
    case expectWelcome, expectNoWelcome
    /// Read the setup window the way a screen reader does, so a walk proves the
    /// two ways on say what they are.
    case readWelcome
    /// The two ways on, pressed for real. `takeTheTour` also moves the walk
    /// over to the window the guide opens for itself, the same way `startTour`
    /// does, because that is the window the person is now looking at.
    case takeTheTour, startWorking
    /// Reopen the setup window the way the menu-bar menu's "Welcome &
    /// Permissions..." does, once the first run is over. It must come back as
    /// the plain setup window it always was, with no tour offer in it, which is
    /// what this checks before closing it again.
    case showWelcomeAgain
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
    /// Share across documents (Next, `next-shared-library`): puts the selected
    /// component on the shelf every document can reach, which is what the
    /// Component section's switch does. A walk cannot reach the dock with the
    /// pointer, so this is how a component gets onto the shared shelf.
    case shareSelectedComponent
    /// ...and takes it back off, which is how a walk photographs what a
    /// document says when its shared original has gone.
    case unshareSelectedComponent
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
    /// View ▸ Show Grid (⌘\u{27}). The menu bar refuses a window scoped chord
    /// while the probe window is not focused, so this is how a walk switches
    /// the grid on the way a person does — without touching the Canvas row,
    /// which is the whole point of the settings being reachable elsewhere.
    case toggleGrid
    /// Put the grid ON, or OFF, whichever it already is. `toggleGrid` flips,
    /// which leaves a walk's outcome depending on what the last walk left
    /// behind; these two make a starting point a walk can rely on.
    case showGrid, hideGrid
    /// View ▸ Grid Settings. Opens the grid's settings on the canvas, switching
    /// the grid on first if it was off, exactly as the menu row does.
    case showGridSettings
    /// View ▸ Adjust Grid, the same door the tool bar's Adjust Grid button
    /// opens: the canvas is taken over to place where the grid starts and pin
    /// guides onto it. A walk uses it so the mode can be entered on a canvas
    /// too narrow to carry the button.
    case adjustGrid
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
    /// Layer ▸ New Layer via Copy (⌘J). Another window-scoped menu chord, and
    /// the one that decides whether the marquee takes the layer you picked or
    /// every layer flattened together.
    case newLayerViaCopy
    /// Layer ▸ New Layer (⌘N): a fresh empty layer on top, with the marquee
    /// left up so the select → new layer → fill flow can be walked. A menu
    /// chord like the rest of the Layer menu, so this is a walk's way in.
    case newLayer
    /// Edit ▸ Fill with Foreground (⌥⌫) and Fill with Background. Both are
    /// menu rows, and the first carries a chord the field editor claims for
    /// itself, so a walk asks for them here rather than through the keyboard.
    case fillWithForeground, fillWithBackground
    /// Expose the first piece of the selected original that could take a
    /// wording knob (Next, `next-components`, step C6). The Add menu is in the
    /// dock, which a walk cannot reach with the pointer, so this is how a knob
    /// gets made before a copy is photographed setting it.
    case exposeWording
    /// The same for a choice: expose the first group inside the selected
    /// original that holds alternatives.
    case exposeChoice
    /// The same for a show-or-hide: expose the first piece of the selected
    /// original that can be turned off.
    case exposeShow
    /// The same for a colour: expose the first colour the selected original has
    /// to offer, which is the fill of the first shape inside it.
    case exposeColor
    /// The same for a number: expose the first number the selected original has
    /// to offer, which is the rounding of the first shape inside it.
    case exposeNumber
    /// Expose the room the selected original keeps inside its OWN outermost
    /// edges, which is the one knob that names the component itself rather than
    /// a piece inside it.
    case exposeRoom
    /// Answers the selected copy's first colour knob with the document's first
    /// saved colour kept for that part. The list is a menu in the dock, which a
    /// walk cannot open, so this is how the named-colour path gets photographed.
    case knobUsesSavedColor
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
    /// Keep every saved color in this document for outlines and text only,
    /// which is what unticking Fills and backgrounds on the Library's Styles
    /// shelf does. Those tickboxes are in the dock, which a walk cannot reach
    /// with the pointer, so this is how a walk shows a colour that a fill row
    /// no longer offers.
    case keepStylesForOutlinesOnly
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
    /// one Border row in the Effects list speaking for the whole selection, so
    /// a walk can photograph it.
    case borderSelection
    /// Paint every picked layer's BORDER one crimson (#B0184A), which is what
    /// choosing a color in the Border row's well does over a selection. Same
    /// reason as `paintSelectionColor`: the well opens a popover, and reaching
    /// it by hand is several steps a walk about something else should not
    /// spend. A walk that IS about the picker presses the well itself.
    ///
    /// There is no `saveBorderColorStyle` beside this any more. It named a row
    /// by the KIND of colour it painted, and the Appearance list stopped having
    /// a Border row when a layer's edge became a Border effect
    /// (`OutlineRetirement.swift`), so it opened a name field under a row that
    /// was not on screen and looked like a button that did nothing. Save as
    /// Style is a row on the Border row's own colour menu, and a walk reaches
    /// it there: `panelMenu "Color" in "Border" choose "Save as Style"`.
    case paintSelectionBorderColor
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
    /// Pick a plain blue in the toolbar swatch's picker, which is what dragging
    /// that picker under the Using line does. It reaches the tool's interior
    /// when it has one and its outline otherwise, like `armToolGradient`. This
    /// is how a walk photographs a tool LETTING GO of the saved colour it was
    /// holding: the picker is inside a popover a walk cannot reach.
    case paintToolColor
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
    /// Layer ▸ Add Version (Next, `next-components`): gives the selected
    /// original another version by duplicating the drawing that is selected,
    /// and selects the new one. The button is in the dock and the row is a
    /// menu, neither of which a walk can reach, so this is the way in.
    case addComponentVersion
    /// Move every selected copy on to the NEXT version its component holds,
    /// which is what picking the next row in the Version menu does. A walk
    /// cannot open a menu in the dock, so this is how a swapped version gets
    /// photographed.
    case showNextComponentVersion
    /// Move the PICKED Library tile on to the next version its component
    /// holds, which is what the Place menu under the shelf does. That menu is
    /// one a walk cannot open, so this is how a tile set to another version
    /// gets photographed, dragged and dropped.
    case chooseNextShelfComponentVersion
    /// Layer ▸ Apply to Other Versions (Next, `next-components`): pushes the
    /// selected piece's look and wording onto the same piece in every other
    /// version of its component. The row is in a menu a walk cannot open, so
    /// this is how one edit reaching every version gets photographed.
    case applyToOtherComponentVersions
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
    /// The rotate knob as a hand drags it: a few live frames on its way round
    /// and then a release, so a walk takes the same preview-and-commit path a
    /// real turn takes rather than a shortcut past it. `turnKnob` puts the
    /// picked layer on a twenty degree slant and `turnKnobStraight` brings it
    /// back to nought, so a walk can show a thing turned and a thing put back.
    /// The knob itself floats off the top edge, which a walk cannot aim at
    /// without knowing the zoom, so this is the way in.
    case turnKnob, turnKnobStraight
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
    /// The Zoom Callout TOOL's Magnification slider, the number the NEXT
    /// callout comes out at: pulled to 4x, and put back to the 2x every
    /// callout used to be drawn at. Also in the dock and the settings capsule,
    /// so also out of a pointer's reach.
    case armCalloutMagnification, armCalloutDefaultMagnification
    /// The LENS TOOL's own settings, the choice made with the tool in your hand
    /// and before any lens exists. They live in the dock and in the capsule
    /// over the tool bar, so a pointer cannot reach them.
    case armLensBlur, armLensPixelate
    /// A PICKED lens's Does row: what the lens on the canvas does to the
    /// picture underneath it. Also in the dock, so also out of reach.
    case lensBlur, lensPixelate, lensGreyscale, lensInvert, lensBrightness
    /// A PICKED lens's own slider, pulled the way a finger pulls it: live
    /// previews, then one committed undo step on release. `pullLensAmount`
    /// takes it to the strong end and `pullLensAmountBack` to the gentle one,
    /// so a walk can show the same lens at two settings.
    case pullLensAmount, pullLensAmountBack
    case setTextSize, setTextWeight
    /// The same menus set the other way, so a walk can put the picked labels
    /// into a known state whatever the last walk left the new-text default at.
    case setTextSizeLarge, setTextWeightRegular
    /// Put the picked labels at a size of three digits
    /// (`TextStyles.threeDigitSizeForPlaytest`). The Size menu offers seven
    /// sizes, all of two digits, and picks a bigger one up only once a label
    /// already wears it, so this is the only way a walk can see the box hold a
    /// number as wide as it will ever have to hold.
    case setTextSizeThreeDigits
    /// Put the picked labels into a family whose name is too long for the Font
    /// menu's box (`TextStyles.longNameForPlaytest`). The menu only offers a
    /// family once a label already wears it, so there is no route to this state
    /// through the UI at all, and without it a walk can never see the box
    /// shorten a name or read the tooltip that says it in full.
    ///
    /// `setTextFontShortName` is the way back to a curated family that fits,
    /// and a walk that means to see the box shorten something starts there:
    /// new text comes out in whatever family the LAST one was set to, which on
    /// a probe that has run this walk before is already the long one.
    case setTextFontLongName, setTextFontShortName
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
    /// Turn the selected piece's "take the room this stack has left over" on,
    /// or off again where it is already on (Next, `next-auto-layout`), which
    /// is what Layer ▸ Fill the Row does and what the Layout section's
    /// fill row does. The menu and the panel are both out of a walk's reach
    /// with the pointer, so this is how a walk photographs a bar with a search
    /// field taking whatever the logo and the buttons leave.
    case fillSelectionInTheFlow
    /// Make the selected piece the surface behind the rest, or hand it back to
    /// the arrangement where it already is one (Next, `next-auto-layout`),
    /// which is what Layer ▸ Surface Behind the Rest does and what the
    /// Layout section's Role row does. Both are out of a walk's reach with the
    /// pointer, so this is how a walk photographs a card whose background is
    /// painted to its own edges.
    case makeSelectionTheSurface
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

/// What in the right hand panel an `expect` step is talking about, by the word
/// the walk uses for it.
public enum PlaytestPanelThing: String, Sendable, Equatable, CaseIterable {
    /// A labelled row of the panel that holds a box of text: Padding, W, Label.
    /// The only kind of thing whose words change under the walk, along with a
    /// menu, which is why these two are the ones that can be asked what they
    /// read.
    case field
    /// A menu in the panel, by the row it sits on or the words on its button.
    case menu
    /// Something a press can land on, by the words on it.
    case control
    /// A row in the layers list.
    case row
    /// A tile on the Library shelf.
    case tile
    /// What a control in the panel would SAY if the pointer rested on it,
    /// named by the control it belongs to.
    ///
    /// Not the same question as what the control reads. A menu too narrow for
    /// the name it is showing reads "Bodoni 72 Smallc...", and the whole point
    /// of the tooltip is that it says the name in full instead. Nothing could
    /// ask for that sentence before, so the only thing holding it up was a test
    /// of the words on their own, which would have gone on passing with the
    /// tooltip deleted.
    case tooltip
}

/// What a walk expects a colour swatch to answer to a colour held over it.
public enum PlaytestColorDropExpectation: String, CaseIterable, Hashable, Codable, Sendable {
    /// It lights up, and letting go paints it.
    case takes
    /// It stays dark, and letting go changes nothing: the swatch the colour
    /// came from, a swatch already wearing it, a swatch with nothing behind it.
    case refuses
}

/// What a walk expects of the grab bar under a resizable panel area.
public enum PlaytestHandleExpectation: String, CaseIterable, Hashable, Codable, Sendable {
    /// There is a bar, and dragging it moves the area point for point.
    case moves
    /// There is no bar, because there is nothing a drag could change.
    case absent
}

/// How far a carried dock section travels before the walk lets go of it.
public enum PlaytestSectionStop: String, CaseIterable, Hashable, Codable, Sendable {
    /// Past the middle of the section named, which is the line it moves aside
    /// on.
    case middle
    /// Only far enough to touch that section's near edge, which is where
    /// nothing should happen yet.
    case touching
}

public enum PlaytestHoverTarget: Sendable, Equatable {
    /// The control whose tooltip begins with this text ("Arrow", "Measure").
    case label(String)
    /// A point; over no control it rests in the open.
    case point(PlaytestPoint)
}

/// A word an `expectCaption` claim is written with.
public protocol CaptionClaimWord: Sendable, Equatable {
    init?(claim: String)
    static var claimWords: [String] { get }
}

/// How the draft is laid out ACROSS its bubble while it is being typed.
public enum CaptionDraftAlignment: String, CaptionClaimWord {
    /// One line, running from the bubble's left inset.
    case left
    /// Several lines, centred on each other the way the committed pill
    /// centres them.
    case centred
    public init?(claim: String) { self.init(rawValue: claim) }
    public static var claimWords: [String] { ["left", "centred"] }
}

/// Where the caret is waiting, across the bubble.
public enum CaptionCaretSpot: String, CaptionClaimWord {
    /// In the middle of the bubble, which is where the next character lands on
    /// a centred line.
    case centred
    /// In from the bubble's left edge, which is where it belongs on a single
    /// line that has nothing typed on it yet.
    case left
    public init?(claim: String) { self.init(rawValue: claim) }
    public static var claimWords: [String] { ["centred", "left"] }
}

/// What the blue selection outline must be doing while the field is open.
public enum CaptionOutlineClaim: CaptionClaimWord {
    /// Drawn round the bubble on screen, not round the caption on disk.
    case hugsTheBubble
    /// No outline at all, which is the right answer with a tool other than
    /// Select in hand.
    case none
    public init?(claim: String) {
        switch claim {
        case "hugs the bubble": self = .hugsTheBubble
        case "none": self = .none
        default: return nil
        }
    }
    public static var claimWords: [String] { ["hugs the bubble", "none"] }
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
    /// `checked` is what a SETTING's item must be wearing before the press:
    /// an item that is simply on or off keeps one name and says its state with
    /// a checkmark, so the checkmark is the only thing left for a walk to read.
    case shortcut(PlaytestKey, [PlaytestModifier], menuItem: String?, checked: Bool?)
    /// Press and release a key by handing it to the APPLICATION rather than
    /// straight to a window.
    ///
    /// `key` posts into the window, which is right for typing and for menu
    /// shortcuts but invisible to anything watching the app as a whole. The
    /// history overlay is exactly that: Esc and click-away take it down through
    /// an application-wide event monitor, and a monitor only ever sees what
    /// goes through the app. This step is how a walk reaches those.
    case appKey(PlaytestKey, [PlaytestModifier])
    /// Move the pointer to a point without pressing anything, so a walk can
    /// read what the canvas SAYS a press would do there. `modifiers` are held
    /// while the pointer rests: ⌥ over a layer is its own cue (the copy
    /// badge), and over a screen's own surface ⌥ means different things
    /// depending on whether the screen is picked, so a walk has to be able to
    /// hold it without clicking.
    case move(PlaytestPoint, [PlaytestModifier])
    /// Pinch the canvas to a zoom, the way two fingers on a trackpad do: a run
    /// of small nudges rather than one jump, each through the very call the
    /// gesture makes. A grid, a guide or a readout that only misbehaves WHILE
    /// the zoom is moving has nowhere to hide from this, and a single
    /// `zoomIn` would step straight over it.
    case pinch(to: CGFloat, steps: Int)
    /// Rest the pointer on a control (named by the label its tooltip shows,
    /// or by a point) long enough for its tooltip to appear. A point over no
    /// control rests in the open and hides whatever was showing.
    ///
    /// `window` names one of the app's OTHER windows to rest in, by its title,
    /// the way `snapshot` does. Without it the pointer rests in the editor
    /// window; with it a walk can reach a floating panel like the capture
    /// history, whose controls are in no editor window at all. A point inside
    /// a named window is measured in window space (down from its top-left),
    /// since there is no canvas there to measure from.
    case hover(PlaytestHoverTarget, window: String?)
    case click(PlaytestPoint, count: Int, modifiers: [PlaytestModifier])
    /// `hold` names a snapshot taken with the button still DOWN, just before
    /// the release: the only way to photograph anything that exists only while
    /// a drag is in hand, like the yellow snap guide.
    /// `wobble` shakes the pointer by that many points as it travels, mostly
    /// back and forth along the line it is walking and half as much sideways:
    /// a hand that is not a ruler. It is what a walk uses to prove a snap does
    /// not flicker under an unsteady hand, and the drag reports how often the
    /// guides came and went.
    /// `halfway` is the modifiers in force for the SECOND half of the travel,
    /// when they differ from the first: a key pressed or let go of with the
    /// button still down. `["shift"]` against no modifiers presses it midway,
    /// `[]` against `modifiers: ["shift"]` lets it go midway. Nil means the
    /// keys never change, which is every other drag.
    case drag(from: PlaytestPoint, to: PlaytestPoint, steps: Int,
              modifiers: [PlaytestModifier], halfway: [PlaytestModifier]?,
              hold: String?, wobble: CGFloat)
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
    /// Choose a row from a tool's OWN list, the one a press and hold on its
    /// button opens: `tool` is the tool's words on the button ("Measure",
    /// "Crop") and `choose` is the row's ("Gap", "16:9").
    ///
    /// The list is drawn by the app rather than by AppKit, so there is no
    /// button in the window a synthetic click can land on. What the step fires
    /// instead is the row's OWN closure, the very one a click on it runs, so a
    /// walk can never choose something the pointer would not.
    ///
    /// With no `choose` it only reads: every row, and which one is wearing the
    /// tick, reaches the log. `ticked` claims which row that must be BEFORE
    /// anything is picked, and fails the walk when the list is telling a
    /// person the wrong mode.
    case toolFlyout(tool: String, choose: String?, ticked: String?)
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
    /// `leave` walks away from the drag WITHOUT telling the views under it that
    /// anything ended, which is what escape, a release outside the window and a
    /// target rebuilt out from under the pointer all look like from the inside.
    /// It is how a walk proves a mark the panel put up clears itself.
    case dragFile(file: String, at: PlaytestPoint, hold: String?, release: Bool, leave: Bool)
    /// One of the app's OWN things — a layer row, a shelf tile, a colour swatch
    /// — picked up by name and held over a point, so a walk can see what the
    /// panel says about a drag that has nothing to do with files. Nothing is
    /// ever let go: the step is there for what is drawn while it is in the air,
    /// and `leave` abandons it there the way `dragFile` does.
    case dragOver(carry: String, at: PlaytestPoint, hold: String?, leave: Bool)
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
    /// `clicking` names a control to CLICK to open it, instead of pressing the
    /// menu button in code. It is how a walk proves that a person's click still
    /// opens a menu, on a control that answers a single click and a double
    /// click differently — the zoom percentage is the one that does.
    /// `in` names the row the menu sits inside, exactly as a `press` step's
    /// does. It is what tells two menus on one row apart, and what tells the
    /// same row arriving twice apart: an effect carries a Color menu AND a
    /// Position menu, and a shape can carry two borders, so neither the row's
    /// name nor the menu's own is enough on its own.
    case panelMenu(menu: String, in: String?, shot: String?, choose: String?, clicking: String?)
    /// Open one of the app's OWN menu-bar menus inside the probe window and
    /// photograph it.
    ///
    /// A `menus` step reads the words and the checkmarks, which is exact but is
    /// not a picture, and a menu draws outside this process so an offscreen
    /// render of it comes back blank. This is the only way an audit can SHOW
    /// what a menu looks like: a real screen capture of the menu, over the
    /// window it belongs to. App-level menus (Capture) photograph honestly;
    /// window-scoped rows come out dimmed and frozen at their launch state,
    /// for the reason in `PlaytestHarness.frozenMenuBar`.
    /// `ticked` and `unticked` name the rows that must, and must not, be
    /// wearing a checkmark, so the step is a test and not only a picture.
    case menuShot(menu: String, name: String, ticked: [String], unticked: [String])
    /// Open the menu you get by RIGHT CLICKING something in the right hand
    /// panel — a layer row, a measurement row — and photograph it.
    ///
    /// The other two menu steps reach menus that hang off something visible: a
    /// menu bar title, or a button in the panel. This one reaches the menus
    /// that hang off nothing at all until the pointer asks for them, which is
    /// why an audit could only ever describe the layer row menu in words.
    /// `shot` names a real screen capture of it, `choose` picks one of its
    /// rows, and `ticked` and `unticked` name the rows that must, and must
    /// not, be wearing a checkmark, so the step is a test and not only a
    /// picture.
    case rightClick(on: String, shot: String?, choose: String?, ticked: [String], unticked: [String])
    /// Pick a tile up off the Library shelf by its name and let go of it
    /// somewhere: `to` a point on the picture, or `onto` a row in the layers
    /// list, which is the other place a saved style can be put down. Exactly
    /// one of the two.
    ///
    /// `hold` names a picture taken while it is still in hand, which is the
    /// only moment the landing outline exists. `expect` says whether the target
    /// should take it, so a walk can prove a refusal is a refusal rather than
    /// reading one as a broken step, and `says` is the words the app has to be
    /// saying while it is held, which is the whole of what a refusal owes
    /// somebody.
    case dragTile(tile: String, to: PlaytestPoint?, onto: String?, hold: String?,
                  expect: PlaytestColorDropExpectation, says: String?)
    /// Press a tile on the Library shelf with the mouse and pull it to a point
    /// on the picture, the way a hand does.
    ///
    /// This is the other half of `dragTile`, and the two are not the same
    /// check. `dragTile` hands the tile's own payload straight to whatever is
    /// being dropped on, which proves everything that happens once a tile is
    /// in the air; nothing in it proves the tile ever left the shelf. This
    /// step proves exactly that one thing and nothing else: the press and the
    /// pull are mouse events on the tile, and the step fails if no drag came
    /// of them. Nothing is let go of, so the document is never changed.
    ///
    /// ONE PER WALK. The app starts no second drag after the first, so a walk
    /// that wants to prove two tiles is two walks; the step says so rather than
    /// reporting the second tile as broken.
    case pickUpTile(tile: String, to: PlaytestPoint)
    /// Pick a row up in the layers list by its name and let go of it on
    /// another row: above it, below it, or inside it when that row is a group.
    /// `hold` names a picture taken before letting go, which is the only
    /// moment the line that says what will happen is on screen.
    case dragRow(row: String, onto: String, zone: PlaytestDropZone, hold: String?)
    /// Pick the colour up off one swatch in the right hand panel and let go of
    /// it on another, naming each by the row it sits on: "Fill", "Outline",
    /// "Shadow". `hold` names a picture taken with the colour still over the
    /// second swatch, which is the only moment the ring that says it will take
    /// it is on screen. `expect` says what the second swatch should answer —
    /// `takes` (the default) or `refuses` — so the step is a test and not only
    /// a picture.
    case dragColor(from: String, onto: String, hold: String?, expect: PlaytestColorDropExpectation)
    /// Pick a section of the right hand panel up by its title and carry it
    /// until the pointer has passed the middle of the section named by `past`,
    /// which is the moment that one moves aside. `hold` names a picture taken
    /// with the section still in hand, the only moment there is anything
    /// lifted off the panel to photograph. `cancel` presses Escape instead of
    /// letting go, so a walk can prove a called-off drag leaves the panel
    /// exactly as it found it. `stop` says how far to carry it: all the way
    /// past that section's middle, which is where it moves aside, or only far
    /// enough to touch it, which is where nothing should happen yet.
    case dragSection(section: String, past: String, stop: PlaytestSectionStop,
                     hold: String?, cancel: Bool)
    /// Drag the grab bar under a resizable area of the right hand panel —
    /// "Layers", "Library" — `by` points down, negative being up, and check
    /// what it did. `expect: "moves"` (the default) requires a bar that is
    /// there and an area that ends up exactly where the drag left it;
    /// `expect: "absent"` requires no bar at all, which is the right answer
    /// for a list too short for any ceiling to change. `hold` names a picture
    /// taken with the bar still held.
    ///
    /// It drives the bar's own handlers rather than posting mouse events, for
    /// the reason written on `PanelAreaHandleProbe`: SwiftUI gestures do not
    /// answer synthesized ones.
    case dragHandle(area: String, by: CGFloat, expect: PlaytestHandleExpectation, hold: String?)
    /// Click a row in the layers list by the name it shows, the way a person
    /// picks a layer out of the list rather than off the picture. `modifiers`
    /// read as they do under a pointer: shift ranges from the anchor row,
    /// command adds or removes.
    ///
    /// This is the only way to select a layer the canvas will not give you: a
    /// locked one, which a click on the picture falls straight through.
    case selectRow(row: String, modifiers: [PlaytestModifier])
    /// Press a control in the right hand panel — or in a popover open on top
    /// of it, the colour picker above all — by the words on it: a button, one
    /// segment of a picker, the name of a row. `in` names the row it sits on,
    /// for when the same word appears twice — the Layout section holds a
    /// Hug and a Fixed for Width and another pair for Height. `count` doubles
    /// the click, `modifiers` read as they do under a pointer.
    ///
    /// A walk could only ever click the picture, so a feature that lives in
    /// the panel could be photographed and never used: three audits on
    /// 2026-09-04 had to say so out loud. This names the control instead of a
    /// pixel, so a panel that reflows does not break the walk, and it presses
    /// with real mouse events, so a control that is dimmed, covered or wired
    /// to nothing fails the walk the way it would fail a person.
    case press(control: String, in: String?, count: Int, modifiers: [PlaytestModifier],
               across: CGFloat?)
    /// Write what the right hand panel is showing to the log and to
    /// `panel-<stage>.json`: every tile on the shelf, every row in the layers
    /// list, and every menu in the dock, by the names a walk has to use for
    /// them. The `menus` step for the panel.
    ///
    /// A popover open on top of the panel is part of the listing while it is
    /// open, since a popover is a window of its own and used to be invisible
    /// to a walk: the colour picker could be photographed and never used.
    case panel(stage: String)
    /// Claim something about the right hand panel and FAIL the run when it is
    /// not so.
    ///
    /// Every other step proves it happened; none of them proves the app
    /// answered. A walk could press Add, place a copy and type a number into a
    /// knob without a single one of those steps noticing that the knob never
    /// arrived. `expect` is the half that notices: it names one thing in the
    /// panel and either the words it must be showing (`reads`) or that it must
    /// be there at all (`present`), and says what it found instead.
    ///
    /// `present: false` is as much of the point as `present: true`: a revert
    /// arrow that appears before anything has been answered is a bug no
    /// screenshot in a passing walk would have caught.
    ///
    /// `inRow` narrows a control to the row it sits on, the way a press does.
    /// One word can be on a dozen rows at once — every effect in the list wears
    /// a Switch, and so do Fill and Outline above them — so without it a claim
    /// about the blur's tick would be answered by the fill's.
    case expect(thing: PlaytestPanelThing, named: String, inRow: String?,
                reads: String?, present: Bool?)
    /// The layers that must be PICKED right now, by name, however they came to
    /// be picked: one clicked, several ⇧-clicked, or a whole sweep.
    ///
    /// `expect` asks the panel what it is showing; this asks what the app is
    /// holding, which is the thing a snapshot cannot photograph. It is what a
    /// walk uses to prove an undo handed the picking back along with the
    /// drawing: before this, a walk could press Undo, see both boxes return
    /// and pass, while the panel had gone empty and the next Stack Selection
    /// or ⌫ did nothing at all (reported 2026-09-08).
    ///
    /// An empty list is as much of the point as a full one: it says nothing
    /// should be picked here.
    case expectPicked(layers: [String])
    /// How many measurements must be on the canvas right now.
    ///
    /// `expectPicked` asks what the app is holding; this asks what it has
    /// actually left behind. A walk that drags a caliper and photographs the
    /// canvas proves the drag happened, not that anything landed:
    /// `distance-lands-on-release.json` ran green while every stage measured
    /// nothing, because no step ever asked (2026-09-08). The failure names
    /// what a half-placed caliper is still waiting for, so a walk that stops
    /// one click short says so instead of showing an empty list.
    ///
    /// Zero is as much of the point as any other number: it says nothing
    /// should have landed here.
    case expectMeasures(count: Int)
    /// Claims about the arrow caption field that is open right now: how the
    /// draft is laid out across its bubble, where the caret is waiting, and
    /// whether the blue outline is drawn round the bubble on screen.
    ///
    /// None of the three can be settled from a picture. The caret blinks, so
    /// half the snapshots of it are of nothing; the outline is a dashed line a
    /// person has to eyeball against a bubble. Both went wrong at once on
    /// 2026-09-12 — Return left the caret at the bubble's left edge while the
    /// next letter landed in the middle, and the outline kept the shape it had
    /// when the field opened — and a walk had photographed both without
    /// noticing either.
    case expectCaption(aligned: CaptionDraftAlignment?, caret: CaptionCaretSpot?,
                       outline: CaptionOutlineClaim?)
    /// The named dock section must be drawing whatever it holds down to and
    /// including its first OPEN entry, whole.
    ///
    /// The dock shortens a list when the panel is over-subscribed, and a list
    /// of small panes — Effects, where every entry is a heading with its own
    /// settings under it — cuts badly: on 2026-09-08 a Border opened in a full
    /// dock and its Width slider was sliced across the middle, which reads as
    /// a rendering fault rather than as a list with more in it. The floor that
    /// stops it is `DockHeightBudget.paneListFloor`, and this is how a walk
    /// proves the floor is really being applied, in the real dock, at whatever
    /// height the window happens to be.
    ///
    /// The section is named the way the dock names it: "Effects", "Layers".
    case expectSectionFits(section: String)
    /// The named thing in the right hand panel must be ALL on screen: inside
    /// the window, and inside whatever is scrolling it.
    ///
    /// The claim `expectSectionFits` cannot make. That one asks whether the
    /// dock gave a section room; this asks whether one named row, pane or
    /// control ended up somewhere a person can actually see, which is the
    /// question a reveal answers. On 2026-09-08 pressing an effect's chevron
    /// open put its settings below the bottom of the panel and nothing
    /// scrolled to them: the walk that proves that fixed says
    /// `{"do": "expectInView", "field": "Shadow"}` and fails naming the points
    /// that are cut off.
    ///
    /// By default a thing TALLER than the room it is in may run past the
    /// bottom, since starting at its top is all the panel can do about it.
    /// `"whole": true` refuses that answer: the room has to be there as well,
    /// which is the claim to make about a pane the panel promised to keep room
    /// for. Opening the second of two effects in a short window showed 175
    /// points of its 277 and passed the plain step, because 175 was all the
    /// room the panel had kept for it (2026-09-09).
    case expectInView(field: String, whole: Bool)
    /// CLAIMS that every readout in the right hand panel spells the unit the
    /// same way, and fails the run naming the row that does not.
    ///
    /// The panel measures ONE space — where a layer sits, how wide it is, how
    /// round its corners are, how thick its outline is — so it says one word
    /// for it. It did not always: on 2026-09-08 a capture caught Corner Radius
    /// reading "18 pt" and a border "4 pt" two rows above Position and Size
    /// saying "px from the top left", and a person redlining a screenshot had
    /// to work out which of two units their number was in.
    ///
    /// A unit word is nobody's job to remember, so this asks the panel itself
    /// rather than a walk listing the rows it happens to know about: a row
    /// added next month is covered the day it arrives.
    case expectOneUnit
    /// CLAIMS that no two rows in the right hand panel wear the same name and
    /// read different numbers, and fails the run naming them and what each one
    /// says.
    ///
    /// One name, one number. It did not always hold: on 2026-09-09 a capture
    /// caught a picked copy of a button showing Corner Radius 0 in Appearance,
    /// slider at the far left, and Corner radius 18 in the Component section
    /// under it, over a button that was plainly round. Both were true of
    /// different layers and nothing on screen said which was which
    /// (`InstanceRounding.swift`).
    ///
    /// A row inside another row keeps its owner's name in front of its own, so
    /// a shadow's Opacity and the layer's own Opacity are two different names
    /// and are allowed to differ, which is exactly what the bracket round a
    /// part's settings says on screen. Like `expectOneUnit` this asks the panel
    /// itself rather than a walk listing the rows it happens to know about, so a
    /// row added next month is covered the day it arrives.
    case expectOneNumberPerName
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
    /// Scroll the dock until a named control is where a person could press it,
    /// however far that turns out to be.
    ///
    /// `scrollPanel` says a DISTANCE, and a distance is a number that was true
    /// on the day it was written: the dock grew an Effects section on
    /// 2026-09-07 and four walks that had scrolled far enough the day before
    /// were suddenly pressing a control the panel's edge cut across. What a
    /// person does is scroll until they can see the thing, so a walk says the
    /// thing. `in` names the row when two controls wear the same word, exactly
    /// as `press` takes it.
    case reveal(control: String, inRow: String?)
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
    /// Write the measured frame of every glass group along the bottom of the
    /// canvas to the log and to `toolbar-<stage>.json`: its height, its top and
    /// bottom edge, and its centre line, left to right.
    ///
    /// The row is a set of separate capsules that each set their own size, so
    /// "they line up" is a claim about numbers. This is how a walk proves it
    /// rather than photographing it and hoping.
    case toolBar(stage: String)
    /// Write the measured frame of every icon parked on the inspector panel's
    /// trailing edge to the log and to `panel-edge-<stage>.json`: each one's
    /// centre line, given as a distance in from the panel's own right edge.
    ///
    /// The eyes, the locks and the section grips are drawn by three different
    /// views that each used to carry their own trailing space, so "they sit on
    /// one line" is a claim about numbers. This is how a walk proves it rather
    /// than photographing it and hoping.
    case panelEdge(stage: String)
    /// The mirror of `panelEdge`: write the measured LEADING edge of every
    /// section heading, every row and every folded subsection in the panel to
    /// the log and to `panel-start-<stage>.json`, each one given as a distance
    /// in from the panel's own left edge.
    ///
    /// "Everything inside a section begins on one margin, and only a subsection
    /// steps in" is a claim about numbers, and the rows are drawn by different
    /// views in different files, so this is how a walk proves it rather than
    /// photographing it and hoping.
    case panelStart(stage: String)
    /// Put the probe into light or dark for the shots that follow, so one walk
    /// can photograph a surface both ways. It changes THIS app only, never the
    /// machine's setting, so nothing outside the probe notices.
    case appearance(PlaytestAppearance)
    case action(PlaytestAction)

    public static let defaultTimeout: Double = 10
    public static let defaultDragSteps = 8
    /// Enough nudges that a pinch across a whole octave of zoom lands on more
    /// zooms than a hand would, so nothing can slip between two of them.
    public static let defaultPinchSteps = 24

    /// Every step name, sorted, as the error text and the doc list them.
    public static let names: [String] = [
        "action", "appKey", "appearance", "blank", "clearClipboard", "click", "describe", "drag",
        "dragColor", "dragComponent",
        "dragFile", "dragHandle", "dragOver", "dragRow", "dragSection", "dragTile", "dropComponent",
        "dropImage", "expect", "expectCaption", "expectInView", "expectMeasures", "expectOneNumberPerName", "expectOneUnit", "expectPicked", "expectSectionFits", "focus", "hover", "key", "measureMode", "menuShot", "menus", "move", "open",
        "panel", "panelEdge", "panelMenu", "panelStart", "pickUpTile", "pinch", "press",
        "readClipboard", "render", "reveal", "rightClick", "scrollPanel", "selectRow", "shortcut", "snapshot", "tool", "toolBar", "toolFlyout", "type", "wait", "waitFor",
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
        case .pinch: "pinch"
        case .hover: "hover"
        case .click: "click"
        case .drag: "drag"
        case .type: "type"
        case .focus: "focus"
        case .tool: "tool"
        case .measureMode: "measureMode"
        case .toolFlyout: "toolFlyout"
        case .waitFor: "waitFor"
        case .dropComponent: "dropComponent"
        case .dragComponent: "dragComponent"
        case .dropImage: "dropImage"
        case .dragFile: "dragFile"
        case .dragOver: "dragOver"
        case .snapshot: "snapshot"
        case .render: "render"
        case .panelMenu: "panelMenu"
        case .menuShot: "menuShot"
        case .rightClick: "rightClick"
        case .dragTile: "dragTile"
        case .pickUpTile: "pickUpTile"
        case .dragRow: "dragRow"
        case .dragColor: "dragColor"
        case .dragSection: "dragSection"
        case .dragHandle: "dragHandle"
        case .selectRow: "selectRow"
        case .press: "press"
        case .panel: "panel"
        case .expect: "expect"
        case .expectMeasures: "expectMeasures"
        case .expectCaption: "expectCaption"
        case .expectSectionFits: "expectSectionFits"
        case .expectInView: "expectInView"
        case .expectOneUnit: "expectOneUnit"
        case .expectOneNumberPerName: "expectOneNumberPerName"
        case .expectPicked: "expectPicked"
        case .scrollPanel: "scrollPanel"
        case .reveal: "reveal"
        case .describe: "describe"
        case .clearClipboard: "clearClipboard"
        case .readClipboard: "readClipboard"
        case .menus: "menus"
        case .toolBar: "toolBar"
        case .panelEdge: "panelEdge"
        case .panelStart: "panelStart"
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
            self = .shortcut(key, try f.modifiers(), menuItem: try f.optionalString("menuItem"),
                             checked: try f.optionalFlag("checked"))
        case "appKey":
            let keyName = try f.string("key")
            guard let key = PlaytestKey(keyName) else {
                throw f.invalid("key", "\"\(keyName)\" is not a key; use a single character or return, escape, tab, space, delete, left, right, up, down")
            }
            self = .appKey(key, try f.modifiers())
        case "move":
            self = .move(try f.point("at"), try f.modifiers())
        case "pinch":
            let to = CGFloat(try f.number("to"))
            guard to.isFinite, to > 0 else {
                throw f.invalid("to", "a zoom to pinch to has to be a positive number, like 2 for 200%")
            }
            let steps = try f.optionalNumber("steps").map { Int($0) } ?? Self.defaultPinchSteps
            self = .pinch(to: to, steps: max(1, steps))
        case "hover":
            let hoverWindow = try f.optionalString("window")
            if fields["label"] != nil {
                self = .hover(.label(try f.string("label")), window: hoverWindow)
            } else if fields["at"] != nil {
                self = .hover(.point(try f.point("at")), window: hoverWindow)
            } else {
                throw f.invalid("label", "hover needs a \"label\" (the text the control's tooltip shows) or an \"at\" point")
            }
        case "click":
            let count = try f.optionalNumber("count").map { Int($0) } ?? 1
            self = .click(try f.point("at"), count: max(1, count), modifiers: try f.modifiers())
        case "drag":
            let steps = try f.optionalNumber("steps").map { Int($0) } ?? Self.defaultDragSteps
            self = .drag(from: try f.point("from"), to: try f.point("to"), steps: max(1, steps),
                         modifiers: try f.modifiers(),
                         halfway: try f.optionalModifiers("halfway"),
                         hold: try f.optionalString("hold"),
                         wobble: CGFloat(try f.optionalNumber("wobble") ?? 0))
        case "type":
            self = .type(try f.string("text"))
        case "focus":
            self = .focus(field: try f.string("field"))
        case "tool":
            self = .tool(try f.enumValue("tool", Tool.self))
        case "measureMode":
            self = .measureMode(try f.enumValue("mode", MeasureToolMode.self))
        case "toolFlyout":
            self = .toolFlyout(tool: try f.string("tool"),
                               choose: try f.optionalString("choose"),
                               ticked: try f.optionalString("ticked"))
        case "waitFor":
            let condition = try f.string("condition")
            let parsed: PlaytestCondition = switch condition {
            case "edgeMap": .edgeMap
            case "captionField": .captionField
            case "tool": .tool(try f.enumValue("value", Tool.self))
            case "measureMode": .measureMode(try f.enumValue("value", MeasureToolMode.self))
            case "sectionInView": .sectionInView(try f.string("value"))
            case "sectionHeaderInView": .sectionHeaderInView(try f.string("value"))
            case "tutorialStep": .tutorialStep(try f.string("value"))
            default: throw f.invalid("condition", "\"\(condition)\" is not a condition; use edgeMap, captionField, tool, measureMode, sectionInView, sectionHeaderInView or tutorialStep")
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
                             release: try f.optionalFlag("release") ?? false,
                             leave: try f.optionalFlag("leave") ?? false)
        case "dragOver":
            self = .dragOver(carry: try f.string("carry"), at: try f.point("at"),
                             hold: try f.optionalString("hold"),
                             leave: try f.optionalFlag("leave") ?? false)
        case "render":
            self = .render(name: try f.string("name"),
                           scale: CGFloat(try f.optionalNumber("scale") ?? 1))
        case "menuShot":
            self = .menuShot(menu: try f.string("menu"), name: try f.string("name"),
                             ticked: try f.optionalStrings("ticked"),
                             unticked: try f.optionalStrings("unticked"))
        case "panelMenu":
            self = .panelMenu(menu: try f.string("menu"),
                              in: try f.optionalString("in"),
                              shot: try f.optionalString("shot"),
                              choose: try f.optionalString("choose"),
                              clicking: try f.optionalString("clicking"))
        case "rightClick":
            self = .rightClick(on: try f.string("on"),
                               shot: try f.optionalString("shot"),
                               choose: try f.optionalString("choose"),
                               ticked: try f.optionalStrings("ticked"),
                               unticked: try f.optionalStrings("unticked"))
        case "dragTile":
            let landing: PlaytestColorDropExpectation = if fields["expect"] == nil {
                .takes
            } else {
                try f.enumValue("expect", PlaytestColorDropExpectation.self)
            }
            let onto = try f.optionalString("onto")
            guard onto == nil || fields["to"] == nil else {
                throw PlaytestScriptError.invalidField(
                    index: index, step: name, field: "onto",
                    reason: "is a row in the layers list, and cannot be given with \"to\", "
                        + "which is a point on the picture")
            }
            guard onto != nil || fields["to"] != nil else {
                throw PlaytestScriptError.invalidField(
                    index: index, step: name, field: "to",
                    reason: "is missing; a tile is let go either \"to\" a point on the picture "
                        + "or \"onto\" a row in the layers list")
            }
            self = .dragTile(tile: try f.string("tile"),
                             to: onto == nil ? try f.point("to") : nil, onto: onto,
                             hold: try f.optionalString("hold"), expect: landing,
                             says: try f.optionalString("says"))
        case "pickUpTile":
            self = .pickUpTile(tile: try f.string("tile"), to: try f.point("to"))
        case "dragRow":
            let zone: PlaytestDropZone = if fields["zone"] == nil {
                .above
            } else {
                try f.enumValue("zone", PlaytestDropZone.self)
            }
            self = .dragRow(row: try f.string("row"), onto: try f.string("onto"),
                            zone: zone, hold: try f.optionalString("hold"))
        case "dragColor":
            let expect: PlaytestColorDropExpectation = if fields["expect"] == nil {
                .takes
            } else {
                try f.enumValue("expect", PlaytestColorDropExpectation.self)
            }
            self = .dragColor(from: try f.string("from"), onto: try f.string("onto"),
                              hold: try f.optionalString("hold"), expect: expect)
        case "dragHandle":
            let expect: PlaytestHandleExpectation = if fields["expect"] == nil {
                .moves
            } else {
                try f.enumValue("expect", PlaytestHandleExpectation.self)
            }
            // A step that asks for no movement is asking for nothing to drag,
            // so the two ways of saying it must not disagree.
            let by = try f.optionalNumber("by") ?? 0
            if expect == .moves, abs(by) < 1 {
                throw PlaytestScriptError.invalidField(index: index, step: name, field: "by",
                                                       reason: "must move the bar at least a point")
            }
            self = .dragHandle(area: try f.string("area"), by: CGFloat(by),
                               expect: expect, hold: try f.optionalString("hold"))
        case "dragSection":
            let stop: PlaytestSectionStop = if fields["stop"] == nil {
                .middle
            } else {
                try f.enumValue("stop", PlaytestSectionStop.self)
            }
            self = .dragSection(section: try f.string("section"), past: try f.string("past"),
                                stop: stop, hold: try f.optionalString("hold"),
                                cancel: try f.optionalFlag("cancel") ?? false)
        case "selectRow":
            self = .selectRow(row: try f.string("row"), modifiers: try f.modifiers())
        case "press":
            let count = try f.optionalNumber("count").map { Int($0) } ?? 1
            // `across` presses a control at a fraction of its own width
            // rather than in its middle, which is the only way to put a
            // slider's knob anywhere but halfway.
            let across = try f.optionalNumber("across").map { CGFloat(min(max($0, 0), 1)) }
            self = .press(control: try f.string("control"), in: try f.optionalString("in"),
                          count: max(1, count), modifiers: try f.modifiers(), across: across)
        case "panel":
            self = .panel(stage: try f.string("stage"))
        case "expect":
            let named = PlaytestPanelThing.allCases.filter { fields[$0.rawValue] != nil }
            guard named.count == 1, let thing = named.first else {
                throw f.invalid("field", "expect names exactly one thing to look at: "
                    + PlaytestPanelThing.allCases.map(\.rawValue).joined(separator: ", ")
                    + (named.isEmpty ? "; this one names none" : "; this one names \(named.count)"))
            }
            let reads = try f.optionalString("reads")
            let present = try f.optionalFlag("present")
            guard reads != nil || present != nil else {
                throw f.invalid("reads", "expect has to claim something: \"reads\" for the words it is showing, or \"present\" for whether it is there at all")
            }
            // Only a field and a menu wear words that change under a walk. A
            // row or a tile shows its own name, so asking one what it reads is
            // a claim the step could never test.
            if reads != nil, thing == .row || thing == .tile {
                throw f.invalid("reads", "only a field, a menu or a control can be asked what it reads; a \(thing.rawValue) shows its own name, so claim \"present\" instead")
            }
            // Only a control and a tooltip are looked up by the row they are
            // on; everything else is found by its own name, so an `in` there
            // would be a narrowing the step quietly ignored. A tooltip needs it
            // for the same reason a control does: the panel is full of rows
            // wearing the same word, and there are two Colors and two Locks
            // showing at once on an ordinary selection.
            let inRow = try f.optionalString("in")
            if inRow != nil, thing != .control, thing != .tooltip {
                throw f.invalid("in", "only a control is found by the row it sits on; a \(thing.rawValue) is found by its own name, so leave \"in\" off")
            }
            self = .expect(thing: thing, named: try f.string(thing.rawValue),
                           inRow: inRow, reads: reads, present: present)
        case "expectMeasures":
            guard fields["count"] != nil else {
                throw f.invalid("count", "expectMeasures has to say how many measurements must be on the canvas; 0 means none should have landed")
            }
            let howMany = try f.number("count")
            guard howMany >= 0, howMany == howMany.rounded() else {
                throw f.invalid("count", "a count of measurements is a whole number, zero or more, not \(howMany)")
            }
            self = .expectMeasures(count: Int(howMany))
        case "expectCaption":
            func word<V: CaptionClaimWord>(_ field: String) throws -> V? {
                guard let raw = try f.optionalString(field) else { return nil }
                guard let value = V(claim: raw) else {
                    throw f.invalid(field, "\(field) on an expectCaption is one of "
                        + V.claimWords.joined(separator: ", ") + ", not \"\(raw)\"")
                }
                return value
            }
            let aligned: CaptionDraftAlignment? = try word("aligned")
            let caret: CaptionCaretSpot? = try word("caret")
            let outline: CaptionOutlineClaim? = try word("outline")
            guard aligned != nil || caret != nil || outline != nil else {
                throw f.invalid("caret", "an expectCaption has to claim something: \"aligned\", \"caret\" or \"outline\". A step that claims nothing passes whatever the app does")
            }
            self = .expectCaption(aligned: aligned, caret: caret, outline: outline)
        case "expectSectionFits":
            self = .expectSectionFits(section: try f.string("section"))
        case "expectInView":
            self = .expectInView(field: try f.string("field"),
                                 whole: try f.optionalFlag("whole") ?? false)
        case "expectOneUnit":
            self = .expectOneUnit
        case "expectOneNumberPerName":
            self = .expectOneNumberPerName
        case "expectPicked":
            guard fields["layers"] != nil else {
                throw f.invalid("layers", "expectPicked has to say which layers must be picked, by name; an empty list means nothing should be")
            }
            self = .expectPicked(layers: try f.optionalStrings("layers"))
        case "scrollPanel":
            self = .scrollPanel(row: fields["row"] as? String, by: try f.number("by"))
        case "reveal":
            self = .reveal(control: try f.string("control"), inRow: fields["in"] as? String)
        case "describe":
            self = .describe(stage: try f.string("stage"), note: fields["note"] as? String)
        case "clearClipboard":
            self = .clearClipboard
        case "readClipboard":
            self = .readClipboard(stage: try f.string("stage"))
        case "menus":
            self = .menus(stage: try f.string("stage"), menu: try f.optionalString("menu"))
        case "toolBar":
            self = .toolBar(stage: try f.string("stage"))
        case "panelEdge":
            self = .panelEdge(stage: try f.string("stage"))
        case "panelStart":
            self = .panelStart(stage: try f.string("stage"))
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

        func optionalStrings(_ field: String) throws -> [String] {
            guard let raw = fields[field] else { return [] }
            guard let values = raw as? [String], values.allSatisfy({ !$0.isEmpty }) else {
                throw invalid(field, "must be a list of non-empty strings")
            }
            return values
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
            try optionalModifiers("modifiers") ?? []
        }

        /// The same list under any name, and nil when the walk did not write
        /// the field at all. The difference matters for a field whose whole
        /// job is to say "and then no keys at all": an empty list is an
        /// instruction, a missing one is silence.
        func optionalModifiers(_ field: String) throws -> [PlaytestModifier]? {
            guard let raw = fields[field] else { return nil }
            guard let names = raw as? [String] else { throw invalid(field, "must be a list of command, shift, option, control") }
            return try names.map { name in
                guard let modifier = PlaytestModifier(rawValue: name) else {
                    throw invalid(field, "\"\(name)\" is not a modifier; use command, shift, option, control")
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
