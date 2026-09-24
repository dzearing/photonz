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

    /// Every answer the canvas gives for what a press at the pointer would
    /// take hold of, which is what `expectCue` may claim. A walk naming
    /// anything else is a typo, and a typo that reads as a passing claim is
    /// worse than no claim at all.
    public static let pointerCueNames: [String] =
        ["none", "grab", "rotate", "name-grab", "drag-copy",
         "screen-sweep", "screen-move", "screen-copy"]
        + ResizeAxis.allCases.map { "resize-\($0.rawValue)" }

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

    /// Where a walk writes when it does not say: a folder of its own under
    /// `/tmp/photonz-playtest`, named after the walk.
    ///
    /// This used to be `out` beside the script, which sounds harmless and was
    /// not: every walk lives inside the repository, so a walk written without
    /// an `out` quietly dropped its renders, captures and logs into the working
    /// copy, where `git add -A` sweeps them into a commit. The default a walk
    /// falls into by silence must land somewhere throwaway.
    public static let scratchRoot = "/tmp/photonz-playtest"

    /// The folder renders and the log land in. An `out` the walk names itself
    /// is resolved against the script's own location, so a script folder can
    /// travel with its output; a walk that names none gets `scratchRoot`.
    public func outputDirectory(besides scriptURL: URL) -> URL {
        Self.outputDirectory(besides: scriptURL, out: out)
    }

    /// The same folder, read straight out of the file before it is parsed.
    ///
    /// A run has to know where to write BEFORE it knows whether the script is
    /// any good, because the report a bad script most needs to leave is the one
    /// saying why it was bad. Anything unreadable falls back to the scratch
    /// folder named after the walk rather than throwing: this answers a
    /// question about a path, not about whether the walk is valid.
    public static func outputDirectory(besides scriptURL: URL, in data: Data) -> URL {
        let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return outputDirectory(besides: scriptURL, out: top?["out"] as? String)
    }

    private static func outputDirectory(besides scriptURL: URL, out: String?) -> URL {
        guard let out, !out.isEmpty else { return defaultOutputDirectory(for: scriptURL) }
        if out.hasPrefix("/") { return URL(fileURLWithPath: out) }
        return scriptURL.deletingLastPathComponent()
            .appendingPathComponent(out).standardizedFileURL
    }

    /// `/tmp/photonz-playtest/<walk name>`. Naming it after the walk rather
    /// than sharing one `out` keeps two walks run back to back from reading
    /// each other's pictures.
    private static func defaultOutputDirectory(for scriptURL: URL) -> URL {
        let name = scriptURL.deletingPathExtension().lastPathComponent
        let folder = name.isEmpty ? "walk" : name
        return URL(fileURLWithPath: scratchRoot).appendingPathComponent(folder)
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
    /// Paths are relative to the script, or absolute, or the one name that is
    /// not a file at all: `sampleRecordingToken`.
    public var captures: [String]

    /// The one `captures` entry that names no file. It means the guides' own
    /// sample recording, written fresh by the runner: a walk about history
    /// needs a RECORDING in the capture folder, and the repo keeps no video
    /// fixture, because the sample is drawn in code so nothing binary is
    /// committed. Named here rather than in the app so the guard test that
    /// checks every borrowed capture exists knows to let this one through.
    public static let sampleRecordingToken = "sample-recording"
    /// Files to copy into an empty folder of the walk's own, which the walk
    /// names as "scratch/<file>" and which is thrown away at the end. This is
    /// for a walk that WRITES beside the picture it opened — saving layers next
    /// to it, say — so it starts from the same nothing every time and leaves no
    /// trace. Paths are relative to the script, or absolute.
    public var scratch: [String]
    /// Features to switch on or off for the length of the walk, and put back
    /// afterwards, named the way the Experiments window names them.
    ///
    /// A guide is only offered when the feature it teaches is switched on, and
    /// plenty else in the app reads a flag the same way, so "what this looks
    /// like switched off" is half of what a walk has to be able to say. Before
    /// this it could not: the flags were changed by hand with `defaults write`
    /// and put back by memory, and the walk written for it passed either way.
    public var flags: [PlaytestFlagChoice]
    /// Guide steps this walk EXPECTS to find nothing to ring, named
    /// "<guide>/<step>".
    ///
    /// A guide step normally has to point at a control that is really on
    /// screen, and a walk fails when one does not. A few steps are about the
    /// other case on purpose: skip every step of the trim guide and nothing was
    /// ever trimmed, so there is no Save button to ring and the last card has
    /// to stand on its own. A walk exercising that says so here, and the check
    /// turns around: the step has to point at nothing, or the declaration is
    /// out of date and the walk fails for that instead.
    public var expectNoControl: [String]

    public init(forget: [PlaytestMemory] = [], captures: [String] = [],
                scratch: [String] = [], expectNoControl: [String] = [],
                flags: [PlaytestFlagChoice] = []) {
        self.forget = forget
        self.captures = captures
        self.scratch = scratch
        self.expectNoControl = expectNoControl
        self.flags = flags
    }

    public var isEmpty: Bool {
        forget.isEmpty && captures.isEmpty && scratch.isEmpty && expectNoControl.isEmpty
            && flags.isEmpty
    }

    /// The known keys, named in the error when a walk uses another one.
    static let knownKeys = ["captures", "expectNoControl", "flags", "forget", "scratch"]

    /// The word a walk writes in `forget` to start from a machine that has
    /// never run Photonz.
    static let everything = "all"

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
                    + Self.knownKeys.joined(separator: ", "))
        }
        // "all" is the word for a machine that has never run Photonz, which is
        // what most walks want and what none of them can name without listing
        // every area by hand and going out of date the next time one is added.
        var forget: [PlaytestMemory] = []
        for word in try Self.words(fields["forget"], field: "forget") {
            if word == Self.everything {
                forget = PlaytestMemory.allCases
                break
            }
            guard let memory = PlaytestMemory(rawValue: word) else {
                throw PlaytestScriptError.invalidSetup(
                    field: "forget", reason: "names \"\(word)\", which is not something the app remembers; "
                        + "it remembers " + Self.everything + ", "
                        + PlaytestMemory.allCases.map(\.rawValue).joined(separator: ", "))
            }
            if !forget.contains(memory) { forget.append(memory) }
        }
        self.init(forget: forget,
                  captures: try Self.words(fields["captures"], field: "captures"),
                  scratch: try Self.words(fields["scratch"], field: "scratch"),
                  expectNoControl: try Self.words(fields["expectNoControl"],
                                                  field: "expectNoControl"),
                  flags: try Self.choices(fields["flags"]))
    }

    /// Reads `"flags": { "<feature>": true, "<other>": false }`.
    ///
    /// A name no release has a feature for is refused here rather than applied
    /// to nothing: a walk that switches nothing off and then claims the app
    /// looks right switched off is worse than no walk at all. Sorted by name,
    /// so the line the log writes about what was changed reads the same every
    /// run.
    private static func choices(_ raw: Any?) throws -> [PlaytestFlagChoice] {
        guard let raw, !(raw is NSNull) else { return [] }
        guard let object = raw as? [String: Any] else {
            throw PlaytestScriptError.invalidSetup(
                field: "flags", reason: "must be an object naming each feature and whether it is on: "
                    + "{ \"next-measure-modes\": false }")
        }
        return try object.keys.sorted().map { name in
            guard let value = object[name] as? Bool else {
                throw PlaytestScriptError.invalidSetup(
                    field: "flags", reason: "says \"\(name)\" is something other than true or false")
            }
            guard PlaytestFlagChoice.isKnownFeature(name) else {
                throw PlaytestScriptError.invalidSetup(
                    field: "flags", reason: "names \"\(name)\", which is no feature this app has; "
                        + "the names are the ones in the Experiments window")
            }
            return PlaytestFlagChoice(name: name, isEnabled: value)
        }
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
    /// The size a new frame is offered at, which is the last one chosen, and
    /// whether an icon frame draws the space an icon has to live inside.
    case frames
    /// Which guides have been finished and where you stopped in any left part
    /// way. A walk that photographs the Tutorials window forgets this first, or
    /// it photographs whatever the last run happened to leave behind.
    case tutorials
    /// Whether the timing strip across the bottom is open or put away to its
    /// row. It lasts across launches, so without it in this list a walk that
    /// put the strip away and did not put it back would hand every later walk
    /// a window with no strip in it, and no walk could say why.
    case motion
    /// The components put on the shelf every document shares. It is a file
    /// rather than a setting, so it is emptied by hand (`PlaytestSetupRunner`),
    /// and it belongs here because a machine that has never run Photonz has
    /// nothing on that shelf. The harness already hands the shelf back at the
    /// end of a walk, but a walk that is killed part way through never reaches
    /// that, and what it shared is then on the shelf of every walk that follows
    /// it on that machine, for good. It is offered ahead of the app's own five
    /// starters, so what that leak really broke was `pickFirstComponent`.
    case shelf
    /// Which of the app's questions have been told not to ask again. A walk
    /// that ticks "Don't ask again" and does not forget it leaves that question
    /// silent for every walk after it, and none of them could say why.
    case questions
}

/// One feature a walk switches on or off for the length of its run.
///
/// The name is the one the Experiments window shows, so a walk reads like the
/// setting a person would change by hand, and the harness puts it back however
/// the run ends.
public struct PlaytestFlagChoice: Sendable, Hashable, Codable {
    public let name: String
    public let isEnabled: Bool

    public init(name: String, isEnabled: Bool) {
        self.name = name
        self.isEnabled = isEnabled
    }

    /// Whether any release has a feature by this name. Asked of every release
    /// rather than of the one running, because the script is parsed before
    /// anything knows which release this launch is; the harness asks the
    /// narrower question when it applies them.
    static func isKnownFeature(_ name: String) -> Bool {
        Release.allCases.contains { release in
            FeatureCatalog.flags(for: release).contains { $0.name == name }
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

    /// Escape, by name, for the steps that press it themselves rather than
    /// reading it out of a script: calling off a drag half way through.
    public static let escape = PlaytestKey(name: "escape", characters: "\u{1B}", keyCode: 53)

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
        "home": ("\u{F729}", 115), "end": ("\u{F72B}", 119),
        "forwarddelete": ("\u{F728}", 117),
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

/// Who a click at a point ends up with, for `expectClickReaches`.
public enum PlaytestClickTaker: String, Hashable, Sendable {
    /// The picture. Anything the app floats over the canvas is letting the
    /// click through, which is what almost every piece of canvas chrome owes
    /// the person underneath it.
    case canvas
    /// Something floating over the picture: a button on a notice pill, the
    /// tool bar, a popover. The click stops there and the canvas never sees it.
    case chrome
}

/// Where one point of a path has to have ended up, which is how a walk claims
/// that reshaping it actually reshaped it.
///
/// `within` is slack in the same space the point is written in, because a drag
/// is synthesized as a run of moves and lands where the pointer lands, not on
/// the exact number a script asked for.
public struct PlaytestAnchorClaim: Hashable, Sendable {
    public var index: Int
    public var near: PlaytestPoint
    public var within: CGFloat

    public init(index: Int, near: PlaytestPoint, within: CGFloat) {
        self.index = index
        self.near = near
        self.within = within
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
    /// One section is the NEXT one down from another, by their header text.
    /// Where a section sits is the whole of what the panel order does, and it
    /// is the one thing a snapshot argues about badly: a walk could report the
    /// order in its log for weeks while Motion drifted ten sections away from
    /// the Effects list it is meant to be read beside. This fails instead.
    case sectionDirectlyUnder(String, under: String)
    /// A layer's row, by the layer's name, is on screen WHOLE in the layers
    /// list, without anyone touching the scroll wheel. "Clicking that shape
    /// puts its row in front of you" is then a step the walk fails on rather
    /// than a number a person reads back off the log afterwards.
    case layerRowInView(String)
    /// A guide is running and it is on this step, named by the step's id. What
    /// a walk waits on after doing the thing a waiting step asked for, so
    /// "picking the Measure tool really moved the guide on" is a step the walk
    /// fails on rather than a claim in a report.
    case tutorialStep(String)
    /// A guide has FINISHED and the card it ends on is up, named by the guide's
    /// id. What a walk waits on before photographing the moment a guide ends,
    /// which used to be a moment nothing could describe: the callout simply
    /// vanished (`TutorialFinish`).
    case tutorialFinished(String)
    /// The Export sheet has finished working out what a GIF or a HEIC will
    /// weigh, which it does by writing one (`ExportWeigh`). How long that takes
    /// is how long the recording is, so a walk that photographs the number
    /// waits for it here rather than guessing at a delay and photographing a
    /// percentage.
    case exportSizeWeighed
    /// A dialog is up (or has gone), named by the words at the top of it:
    /// "Resize Image", "Export", "New Frame", "Blank Canvas", "Canvas Size".
    ///
    /// A dialog is a sheet the app draws for itself, so there is no AppKit
    /// window carrying its name for a walk to find, and the only thing a walk
    /// could say about one was that the step which opens it did not throw.
    /// This asks the editor whether the sheet is really up, so "pressing that
    /// row opened the resize dialog" is a step the walk fails on.
    case dialog(String, up: Bool)
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
    /// What the window is set up for (`WindowModes`, `next-window-modes`). Each
    /// one is View ▸ Mode ▸ … and ⌃1 … ⌃4, so every one of them hangs off the
    /// focused window and is dimmed for the whole of a walk; a walk reaches
    /// them here, or presses the chip in the title bar by name.
    ///
    /// Written out one case per mode rather than taken as a value, because a
    /// walk's script is a fixed list a person reads: `modeRedline` says what
    /// the press means, where `mode("redline")` would put a mode's id in a
    /// script and a typo in it would be a walk that quietly did nothing. The
    /// slice that makes modes editable data will have to revisit this, and the
    /// test that every shipped mode has an action here is what will say so.
    case modeIcon, modeRedline, modeVideo, modeDesign, modeShowEverything
    /// Take the window in and out of full screen. Full screen is where a Mac
    /// takes the title bar away, so anything that lives in the title bar has
    /// to be checked here rather than assumed.
    case toggleFullScreen
    /// Size the editor window to the smallest one the app supports, 1200 by
    /// 720, the laptop window every dock rule is measured against
    /// (`InspectorDockLayout.swift`). For the walks that open the sample
    /// recording, which has no `width` and `height` of its own to ask for.
    case windowLaptop
    /// Drag the right hand panel in to the narrowest the dock allows (220pt),
    /// the width where a row too wide to fit shows first. Put back to what it
    /// was when the walk ends, however it ends.
    case dockNarrowest
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
    /// Ask the editor window this walk is driving to close, exactly as the
    /// red button or Command W does, and read the question it stops to ask.
    /// Fails when nothing asks: the point is proving work is never dropped
    /// without a word. The sheet stays up for a snapshot and an answer.
    case askToClose
    /// Answer that question with its first button (Save, or Export where Save
    /// cannot write the changes) and say what happened to the window.
    case answerCloseFirst
    /// Export the document that has time as an MP4 through the same path the
    /// Export sheet's button runs, into the walk's scratch folder, and wait
    /// for it to land. What an export changes about the window (a recording
    /// that cannot be saved counts as kept once exported) is then checkable.
    case exportVideoAsTheSheetDoes
    /// Open the New Canvas sheet, so a walk can photograph it. A snapshot
    /// taken while a sheet is up photographs the sheet.
    /// The guided tutorials, driven from a walk (`TutorialController`).
    /// `startTour` is the real entry point: it opens the guide's OWN sample
    /// window, which is where the guide then runs, so a walk photographing it
    /// names that window. `startTourHere` runs the same guide over the window
    /// the walk is already driving, so the walk can press real controls with
    /// real coordinates and prove a waiting step advances on the thing itself.
    case startTour, startTourHere, tutorialNext, tutorialBack, tutorialClose
    /// The rows on the card a guide ENDS on (`TutorialFinish`): carry on with
    /// the track, leave the practice picture for an empty window of your own,
    /// or go to the list of every guide. Pressed by what the row does rather
    /// than by the words on it, so rewording the card never breaks a walk.
    case tutorialFinishNext, tutorialFinishStartYourOwn, tutorialFinishMoreGuides
    /// Open (or close) the Tutorials window, the hub every guide is listed in.
    /// It is an ordinary app window, so a walk photographs it by name:
    /// `{ "do": "snapshot", "name": "hub", "window": "Tutorials" }`.
    case showTutorials, closeTutorials
    /// Open (or close) the Settings window, the one place a question you told
    /// the app to stop asking can be turned back on. Its controls carry the
    /// same markers the panel's do, so a walk presses "Ask Me Again" with an
    /// ordinary `press` step and claims things about it with `expect`.
    case showSettings, closeSettings
    /// Open (or close) the Experiments window, where the release is picked and
    /// its feature flags are switched. It is an ordinary app window, so a walk
    /// photographs it by name:
    /// `{ "do": "snapshot", "name": "flags", "window": "Experiments" }`.
    case showExperiments, closeExperiments
    /// Read the Tutorials window the way a screen reader does, and press the
    /// first guide's own button the way a keyboard does. The window is an
    /// ordinary SwiftUI surface with no playtest markers in it, so this is how
    /// a walk proves its list is reachable and its buttons are wired.
    case readTutorialWindow, pressTutorialStart
    /// A recording's window, driven the way the buttons on its floating
    /// controller drive it. The video guides teach in there, and it is not the
    /// picture editor: no canvas, no tool bar, no layers, so none of the
    /// actions above reach anything in it.
    ///
    /// The two handle moves take the quarter and three quarter marks of the
    /// clip, which is a real drag's outcome without a walk having to know how
    /// long the sample is.
    case videoBeginTrim, videoTrimStart, videoTrimEnd, videoTrimDone, videoTrimCancel, videoCopyGIF
    /// Put the whole recording back without leaving the trim: the Reset in the
    /// trim tool's capsule (`docs/design/video-surface.md` §10.2). Only the
    /// trim TOOL has one; the window this replaces had a Reset too, and it
    /// meant the same thing.
    case videoTrimReset
    /// Open a recording window on the guides' sample clip WITHOUT a guide: a
    /// fresh eight second MP4 with dead air at both ends and something
    /// happening in the middle. What a cutting walk needs, since every other
    /// way into a recording window depends on the person having recorded
    /// something.
    case openSampleRecording
    /// Open a screen recording with somebody TALKING in it, as a person would
    /// open one: the sample picture with the Mac's own voice as its sound
    /// (`TutorialSampleTalk`). What a walk of captions writing themselves
    /// needs, since the sample recording's own sound has no words in it.
    case openSampleTalk
    /// The other doors a recording is asked for through, so a walk can check
    /// that one which cannot be opened SAYS so rather than leaving a window
    /// with nothing in it (`RecordingDoor`).
    ///
    /// `openRecordingFromDisk` puts a copy of the sample somewhere that is NOT
    /// the capture folder and asks the app to open it exactly as Finder does.
    /// `openMissingRecording` asks for one that is not there. `openLandingRecording`
    /// asks for one that is still being written and keeps writing it for a
    /// couple of seconds afterwards, which is what a big file being copied in
    /// looks like.
    case openRecordingFromDisk, openMissingRecording, openLandingRecording
    /// ⇧⌘6 / the menu's "Edit Last Capture": open the newest thing in history
    /// for editing, from wherever you are. A walk pairs it with a setup that
    /// lends `sample-recording` to the capture folder, which is the only way to
    /// drive the real history door with a real recording in it.
    case editLastCapture
    /// Shut the window holding the sample recording and ask for it again: how a
    /// walk checks that coming back puts the playhead where it was left.
    case reopenSampleRecording
    /// Move the playhead to a fraction of what is left to watch, which is a
    /// real scrub's outcome without a walk having to know how long the clip is.
    case videoSeekQuarter, videoSeekMiddle, videoSeekThreeQuarters
    /// Back to the first frame. A walk that has to place something at the head
    /// of the timeline needs a way to put the playhead there, and the three
    /// fractions above cannot say nought.
    case videoSeekStart
    /// The playhead a second later, or a second earlier: how a walk puts it
    /// BETWEEN two moments the fractions above land on, which is where a
    /// keyed value is on its way (`every-value-in-the-panel-has-a-key-diamond`).
    case videoStepOneSecond, videoStepBackOneSecond
    /// A quarter second later: in between two keys half a second apart.
    case videoStepQuarterSecond
    /// Cutting a recording into pieces: put a cut where the playhead is, throw
    /// away the piece the playhead is in, and take the last one back.
    case videoCut, videoDeletePiece, videoUndoEdit
    /// Saving, the three ways a person reaches it. `videoSave` is what ⌘S and
    /// File ▸ Save run. `videoCloseAndSave` is the close confirmation's own
    /// Save button, which is a different path into the same commit and the one
    /// the 2026-09-18 report says did nothing. `videoRevertToOriginal` puts the
    /// whole clip back, so a walk can show a save undone as well as done.
    case videoSave, videoCloseAndSave, videoRevertToOriginal
    /// What Command S runs on whatever window is in front: the recording's
    /// commit in a video window, the document's save in an image one.
    ///
    /// This exists because of the frozen menu bar. A walk never brings the
    /// probe to the front, so File > Save is dimmed with nothing behind it for
    /// the whole walk and the chord reports that back at itself. The chord
    /// stands in for this (`PlaytestMenuStandIn`), so a walk pressing Command S
    /// still means save, and it means the SAME save whichever kind of window is
    /// in front, exactly as the menu item does.
    case save
    /// Playback, driven the way space does.
    case videoPlay, videoPause
    /// The start handle dragged by hand towards the first cut in the
    /// recording, stopped at the three distances that decide whether a magnet
    /// is a snap or a stutter: well inside the reach, where it must catch;
    /// just outside it, where a cut already caught must keep holding; and
    /// clearly past it, where it must let go and follow the hand again. The
    /// distances are points on screen off the real track, so this is the same
    /// path a pointer takes rather than a number poked into the trim.
    case videoDragTrimNearCut, videoDragTrimJustPastCut, videoDragTrimClearOfCut
    /// The start handle dragged to three points short of the first cut with ⌘
    /// HELD, which is a place the magnet makes unreachable otherwise: anything
    /// the hand puts within eight points of a cut is taken by the cut. Used
    /// straight after one of the drags above, with no release in between, so a
    /// walk shows the key being reached for part way through a drag rather
    /// than only before one.
    case videoDragTrimFreedNearCut
    /// The end handle dragged the other way onto the last cut, so a walk shows
    /// both ends of the window catching rather than assuming the second one
    /// does because the first one did.
    case videoDragTrimEndNearCut
    /// Let go of the handle being dragged.
    case videoDragTrimRelease
    /// Open the recording's Export sheet, the way ⇧⌘S and File ▸ Export… do,
    /// already showing one of the three formats. Asked for here rather than by
    /// pressing the format row, so a walk can photograph GIF on a Mac whose
    /// screen is locked, and so photographing GIF never decides what the NEXT
    /// walk's Export opens on.
    case videoExportSheet, videoExportSheetAsGIF, videoExportSheetAsHEIC
    /// Shut the Export sheet the way Cancel does, so a walk can show that
    /// choosing a format and then backing out writes nothing.
    case videoExportSheetCancel
    /// Start writing the recording out for real, straight past the save box a
    /// walk cannot drive, so the card that says how far along it is can be
    /// photographed while it is up. Deliberately the slowest of the three
    /// formats at its biggest preset, because the thing under test is what a
    /// write long enough to wait for looks like.
    case videoExportBegin
    /// Export what the sheet has just weighed, straight past the save box.
    ///
    /// A GIF's size is found out by writing one, so by the time the sheet says
    /// a number the file exists; pressing Export hands that very file over
    /// rather than writing it again (`ExportWeigh`). This is that press, so a
    /// walk can check that the file which lands is the file that was weighed,
    /// and that it lands at once.
    case videoExportWeighed
    /// Press Stop on that card. What has been written so far goes with it, so
    /// the walk can then show there is no half a file on the disk.
    case videoExportStop
    /// Crop the recording to the middle half of its frame, which is a real
    /// crop's outcome without a walk having to know how big the clip is. What
    /// lets a walk check that a saved copy comes out at the CROP's size rather
    /// than the recording's.
    case videoCropMiddle

    // MARK: Cutting on the TIMELINE (`EditorState+ClipBar`)
    //
    // The same jobs as `videoCut` and `videoDeletePiece`, in the ordinary
    // editor rather than in the recording window. Separate ids rather than
    // reused ones because they are a different surface with different rules:
    // ⌫ here takes a PICKED piece, and every edge on the bar can be dragged.

    /// Split the clip under the playhead in two: B, and Video ▸ Split at
    /// Playhead. Fails the walk when the playhead is nowhere a cut means
    /// anything, so a walk cannot quietly photograph a cut that never landed.
    case clipSplit
    /// Throw the picked piece away. The join closes and everything after it
    /// slides back.
    case clipDeletePiece
    /// Hold on the frame under the playhead: a piece whose in and out are the
    /// same frame, dropped onto the timeline like any other piece.
    case clipHoldFrame
    /// Retime the piece in hand. Its sound goes with it, at the same rate.
    case clipSpeedDouble, clipSpeedHalf
    /// Take the picked clip's sound off its picture and lay it on a layer of
    /// its own (`docs/design/video-audio.md`). Fails the walk when there is
    /// nothing to take off, so a walk cannot photograph a detach that never
    /// happened.
    case soundDetach
    /// Put the sample piece of music on the timeline where the playhead is: the
    /// panel-free path Add Sound takes, so a walk never has to answer an open
    /// panel.
    case soundAddSample
    /// Put the spoken sample on the timeline where the playhead is: the Mac's
    /// own voice reading five sentences about this app. What a captioning walk
    /// needs, because the sample recording's own sound is tones and blips and
    /// there are no words in it (`TutorialSampleVoiceover`).
    case captionsAddVoiceover
    /// **Write Captions**, and wait for the listening to finish. On this
    /// machine it runs about ninety times faster than the sound it is
    /// listening to, so a walk waits seconds rather than minutes.
    case captionsWrite
    /// **Write Captions** on a recording with no words in it, and fail unless
    /// it comes back SAYING it heard nothing. The thing that must never happen
    /// is a recogniser inventing words out of a tone, and the second thing is
    /// it leaving an empty track and letting somebody think it is still
    /// working.
    case captionsWriteHearingNothing
    /// Move every caption a tenth of a second later, then earlier: the nudge
    /// that fixes a whole track that ran late.
    case captionsNudgeLater, captionsNudgeEarlier
    /// Type over the first word of the first caption, which on this sample is
    /// the app's own name and the word the recogniser reliably gets wrong. A
    /// walk's stand-in for double clicking the words and fixing them.
    case captionsCorrectFirstWord
    /// Take every caption off again.
    case captionsClear
    /// Fail unless the captions in the document are the shape a caption track
    /// has to be: there are some, each is a text layer with an in and an out,
    /// they are in order, none overlaps the next, and every one of them holds
    /// the words the machine heard with the moments it heard them.
    case captionsExpectSound
    /// Fail unless every caption's words still carry the timings they were
    /// heard with, which is what a correction must not cost.
    case captionsExpectTimingsKept
    /// Wait, without pressing anything, for the captions to write themselves,
    /// and fail unless they land. What opening a recording with speech in it
    /// has to do at Next's defaults.
    case captionsWaitForThemselves
    /// Fail unless every caption is on ONE Captions track, side by side.
    case captionsExpectOneTrack
    /// Open the first caption's words for typing over its bar, the way a
    /// double click on it does; `captionsCommitFirstWords` types the fix in.
    case captionsEditFirstInPlace, captionsCommitFirstWords
    /// Drag the first caption's right hand end in by a third of a second.
    case captionsTrimFirstEnd
    /// Pick one of the named caption styles, for every caption at once.
    case captionsStyleCaption, captionsStyleLowerThird, captionsStyleKaraoke
    /// Move every caption to the top of the picture, and back.
    case captionsPositionTop, captionsPositionBottom
    /// Fail unless the frame drawn at the playhead has the spoken word lit.
    case captionsExpectLitWord
    /// Write the captions out as SubRip and WebVTT into the walk's own
    /// folder, and fail unless both files read back as what they claim.
    case captionsExportFiles
    /// Turn Auto off, and back on.
    case captionsAutoOff, captionsAutoOn
    /// Fail unless the words being typed on the canvas are a caption's: what a
    /// double click on a caption on the picture has to open.
    case captionsExpectEditingOnCanvas
    /// Write the film with its picture clean and its captions as an SRT file
    /// beside it, into the walk's own folder, and fail unless both land.
    case captionsWriteFilmWithFileBeside
    /// Duck the picked layer: four points either side of a dip, which is all a
    /// duck is. It is a walk's stand-in for dragging four dots on the bar.
    case soundDuck
    /// Pull the picked layer's fader down to half, so a walk can photograph a
    /// level that is not the one it was recorded at.
    case soundLevelHalf
    /// Fail the walk unless sound is actually coming out: the engine running
    /// with every piece of the mix scheduled on it. The one thing about playing
    /// that can be checked without ears, so a walk never photographs a playhead
    /// moving in silence and calls it playing.
    case soundExpectPlaying
    /// Write the mix out beside the walk's own pictures, and fail if nothing
    /// lands: the one step that proves an export really happened.
    case soundExportMix
    /// Fail the walk unless the document's mix really does add up past what a
    /// sound file can hold, AND unless the app is holding it down: the plan
    /// reads over, the plan the player and the export are handed does not, and
    /// the balance between the layers survived the trip. The one thing about
    /// clipping that can be checked without ears
    /// (`docs/design/video-audio.md` §9).
    case soundExpectMixOver
    /// Fail the walk unless the meter reads what is actually under the
    /// playhead: high where there is sound and nothing where there is none.
    /// A meter that never moves photographs exactly like one that does.
    case soundExpectMeterReads
    /// Drag the playhead across a sound and back again, through the very three
    /// calls the timeline's own hand makes, and fail the walk unless sound came
    /// out of it: grains forward, grains backward, every layer under the
    /// playhead heard, the playhead landing exactly where the hand asked every
    /// step of the way, and no single grain costing a frame. The one thing
    /// about scrubbing that can be checked without ears.
    case soundScrubAcrossIt
    /// The bar's LEFT end dragged an eighth of the document inwards, and back
    /// out again by the same amount. The pair is the proof that nothing was
    /// thrown away: what the first one put out of play, the second one takes
    /// back. Driven through the real drag, so the clamping and the catching
    /// are exercised rather than stepped around.
    case clipDragStartIn, clipDragStartBackOut
    /// The bar's RIGHT end dragged an eighth of the document inwards.
    case clipDragEndIn
    /// The LAST piece carried to the front of the order, which is a real
    /// rearrange without a walk having to know how long any piece is.
    case clipCarryLastToFront
    /// The whole clip slid an eighth of the document later, so a walk shows a
    /// clip being placed as well as cut.
    case clipSlideLater
    /// The same two drags, LEFT IN THE HAND rather than let go of, so a walk
    /// can photograph what a drag SHOWS you before you commit to it: the green
    /// line where it has caught, and the order it would land in.
    /// `clipSlideOntoPlayheadHeld` aims the clip's start a hair short of the
    /// playhead, which is inside the catching distance, so the picture is of a
    /// catch rather than of a near miss.
    case clipSlideOntoPlayheadHeld, clipCarryLastToFrontHeld
    /// The picked clip taken hold of and carried up onto the track above
    /// its own, or up past the top track, where a drop makes a new track, and
    /// LEFT IN THE HAND so a walk can photograph the lane or the line lit
    /// where it would land (`DocumentTracks.swift`). `clipDragRelease` lets go.
    case clipCarryUpATrackHeld, clipCarryToNewTrackOnTopHeld
    /// Group the tracks picked in the timeline's gutter: the right-click
    /// menu's Group Tracks, for a walk that cannot open a right-click menu.
    case tracksGroupPicked
    /// Let go of whichever of those is in the hand.
    case clipDragRelease
    /// The LEFT end of a TITLE's bar dragged an eighth of the document
    /// earlier, and the RIGHT end an eighth later
    /// (`next-a-title-has-an-in-and-an-out`).
    ///
    /// Not the same gesture as `clipDragStartIn` above, and that is the thing
    /// they are here to prove: a clip's left end trims into the frames behind
    /// it and the clip stays where it was put, while a title has nothing
    /// behind it, so its left end simply moves the moment it arrives and its
    /// far end does not budge. Both go through the real drag on the layer
    /// PICKED, so they refuse loudly where what is picked is a clip.
    case titleDragStartEarlier, titleDragEndLater

    /// Drag the key diamond under the playhead, on the picked layer's clip,
    /// half a second later: the same move a hand makes on the timeline
    /// (`ClipKeys.swift`). Fails where no diamond sits at the playhead.
    case clipKeyAtPlayheadLater

    // MARK: Key lanes (`KeyLanes.swift`)

    /// The arrow on the picked layer's track header: its lanes open or close.
    case keyLanesToggle
    /// Pick every lane key on the picked layer that sits at the playhead, the
    /// way a box drawn down through the playhead does.
    case keyLanesPickAtPlayhead
    /// Pick every lane key on the picked layer: a box drawn round them all.
    case keyLanesPickAll
    /// Drag the picked keys half a second later, or with Option held, copy
    /// them there.
    case keyLanesPickedLater, keyLanesPickedCopyLater
    /// Right-click a picked key and choose Hold, or Bezier.
    case keyLanesPickedHold, keyLanesPickedBezier
    /// Drag the leaving handle of the first picked key, on its open curve, most
    /// of the way along its stretch: a strong ease out. Fails where no picked
    /// key has a stretch after it.
    case keyLanesHandleLater
    /// Video ▸ Go to Next Key (⇧K) and Go to Previous Key (⌥K): the playhead
    /// to the picked layer's next or previous key. Fails where there is none.
    case goToNextKey, goToPreviousKey

    // MARK: What happens at a cut (`ClipTransitions.swift`)

    /// Pick the cut in hand: the join the playhead is standing on. Fails the
    /// walk when there is no cut to pick, so a walk cannot photograph a panel
    /// talking about a join that is not there.
    case clipPickCut
    /// Pick the clip's FIRST cut, wherever the playhead happens to be. What
    /// `clipPickCut` cannot do: reach a join the playhead is nowhere near,
    /// which is exactly what a walk needs after it has rearranged the pieces.
    case clipPickFirstCut
    /// Put a cross dissolve on the cut in hand. Fails the walk when the cut
    /// cannot pay for one, which is the whole point of the refusal: a dissolve
    /// with no spare media either side is not quietly made shorter.
    case clipTransitionDissolve
    /// ...and a dip to black, which needs no spare media at all.
    case clipTransitionDipToBlack
    /// Take whatever is on the cut off again, leaving a hard cut.
    case clipTransitionHardCut
    /// Drag the band's right hand end outwards, through the real drag, so the
    /// clamping and the readout are exercised rather than stepped around.
    case clipTransitionDragLonger
    /// Put a blur on the picked layer and tell it to come on over a second from
    /// the playhead: the second half of this work, driven through the same two
    /// calls the Effects plus and the Motion plus make.
    case clipBlurComesOn

    // MARK: Opening the timeline out (`TimelineZoom.swift`)

    /// The minus and the plus in the timeline's own bar: show more of the
    /// recording, or open out around the playhead. Each refuses out loud at
    /// its end of the range, so a walk cannot photograph a press that did
    /// nothing and call it a zoom.
    case timelineZoomIn, timelineZoomOut
    /// Fit: the whole recording back across the width, in one press, from
    /// however far in.
    case timelineFit
    /// **Make this document five minutes long**, which is the length of a real
    /// screen recording and the length the timeline is unreadable at.
    ///
    /// A stand-in, and it says so: the sample every other walk is driven on is
    /// eight seconds, there is no five minute file to ship in the repo, and
    /// the thing under test is the RULER rather than the pixels. So the
    /// take is slid along until it ends at the five minute mark, playhead and
    /// all, which is exactly what the strip has to draw when somebody is
    /// working on one moment of a long recording. Slid rather than left at the
    /// front with empty time after it because a document's duration follows
    /// what is in it: four and a half minutes of nothing would collapse the
    /// moment anything was edited, and content that really runs to five
    /// minutes does not.
    case timelineFiveMinutes

    /// Whether this action drives the TIMELINE in the ordinary editor: cutting,
    /// arranging and retiming what is on it. Answered by the editor, never by
    /// the old recording window, which has its own ids above.
    public var drivesTheTimeline: Bool {
        switch self {
        case .clipSplit, .clipDeletePiece, .clipHoldFrame,
             .clipSpeedDouble, .clipSpeedHalf,
             .soundDetach, .soundAddSample, .soundDuck, .soundLevelHalf,
             .captionsAddVoiceover, .captionsWrite, .captionsWriteHearingNothing,
             .captionsNudgeLater, .captionsNudgeEarlier,
             .captionsCorrectFirstWord, .captionsClear, .captionsExpectSound,
             .captionsExpectTimingsKept, .captionsWaitForThemselves, .captionsExpectOneTrack,
             .captionsEditFirstInPlace, .captionsCommitFirstWords, .captionsTrimFirstEnd,
             .captionsStyleCaption, .captionsStyleLowerThird, .captionsStyleKaraoke,
             .captionsPositionTop, .captionsPositionBottom, .captionsExpectLitWord,
             .captionsExportFiles, .captionsAutoOff, .captionsAutoOn, .captionsExpectEditingOnCanvas,
             .captionsWriteFilmWithFileBeside,
             .soundExpectPlaying, .soundExportMix, .soundScrubAcrossIt,
             .soundExpectMixOver, .soundExpectMeterReads,
             .clipDragStartIn, .clipDragStartBackOut, .clipDragEndIn,
             .clipCarryLastToFront, .clipSlideLater,
             .clipSlideOntoPlayheadHeld, .clipCarryLastToFrontHeld, .clipDragRelease,
             .clipCarryUpATrackHeld, .clipCarryToNewTrackOnTopHeld, .tracksGroupPicked,
             .clipPickCut, .clipPickFirstCut, .clipTransitionDissolve, .clipTransitionDipToBlack,
             .clipTransitionHardCut, .clipTransitionDragLonger, .clipBlurComesOn,
             .titleDragStartEarlier, .titleDragEndLater, .clipKeyAtPlayheadLater,
             .keyLanesToggle, .keyLanesPickAtPlayhead, .keyLanesPickAll,
             .keyLanesPickedLater, .keyLanesPickedCopyLater, .keyLanesPickedHold,
             .keyLanesPickedBezier, .keyLanesHandleLater, .goToNextKey, .goToPreviousKey,
             .timelineZoomIn, .timelineZoomOut, .timelineFit, .timelineFiveMinutes: true
        default: false
        }
    }

    /// Whether this action drives the GUIDE rather than a window: pressing the
    /// callout's own button. A guide can be running over a recording's window,
    /// where there is no editor to ask for, so a walk in one needs these
    /// answered without one.
    public var drivesGuide: Bool {
        switch self {
        case .tutorialNext, .tutorialBack, .tutorialClose,
             .tutorialFinishNext, .tutorialFinishStartYourOwn, .tutorialFinishMoreGuides: true
        default: false
        }
    }

    /// Whether this action belongs to a recording's window rather than to the
    /// picture editor. What tells a walk which window to ask.
    public var drivesRecording: Bool {
        switch self {
        case .videoBeginTrim, .videoTrimStart, .videoTrimEnd, .videoTrimDone, .videoTrimCancel,
             .videoTrimReset, .videoCopyGIF,
             .videoSeekQuarter, .videoSeekMiddle, .videoSeekThreeQuarters, .videoSeekStart,
             .videoCut, .videoDeletePiece, .videoUndoEdit, .videoPlay, .videoPause,
             .videoSave, .videoCloseAndSave, .videoRevertToOriginal, .save,
             .videoDragTrimNearCut, .videoDragTrimJustPastCut, .videoDragTrimClearOfCut,
             .videoDragTrimFreedNearCut,
             .videoDragTrimEndNearCut, .videoDragTrimRelease,
             .videoExportSheet, .videoExportSheetAsGIF, .videoExportSheetAsHEIC,
             .videoExportSheetCancel, .videoExportBegin, .videoExportStop,
             .videoCropMiddle: true
        default: false
        }
    }
    /// The trim, said in the ordinary editor's own terms.
    ///
    /// Trim stopped being a window and became a tool, and the action ids
    /// survived the move on purpose (`docs/design/video-surface.md` §10.6): a
    /// walk asks for `videoBeginTrim` and gets the tool where it used to get
    /// the window's button. These are the ones a document can answer; saving,
    /// exporting and cutting a recording are still the window's.
    public var drivesTheTrimTool: Bool {
        switch self {
        case .videoBeginTrim, .videoTrimStart, .videoTrimEnd, .videoTrimDone,
             .videoTrimCancel, .videoTrimReset, .videoPlay, .videoPause,
             .videoSeekQuarter, .videoSeekMiddle, .videoSeekThreeQuarters,
             .videoSeekStart, .videoStepOneSecond, .videoStepBackOneSecond,
             .videoStepQuarterSecond: true
        default: false
        }
    }

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
    /// Be (or stop being) the person who never gives Photonz the screen.
    /// These change what the APP reads the Screen Recording grant as, in the
    /// probe build only: nothing about macOS is touched and nothing is
    /// granted or revoked. The probe machine granted the screen long ago, so
    /// without this a walk can never reach the half of the first run that
    /// belongs to somebody who only wants to draw.
    case screenRecordingOff, screenRecordingOn
    /// Reach for a screenshot the way ⇧⌘4 does, from a walk. Only useful
    /// after `screenRecordingOff`: the point is the moment somebody who said
    /// no to setup finds out what saying no cost them, which has to be the
    /// moment they try, with the way to fix it in reach. Nothing is captured
    /// and no selection overlay is drawn, because the app stops before either.
    case tryToCapture
    /// Open (and close) the Position and Size numbers, which are a popover
    /// hung off the selection now rather than a section in the panel
    /// (`ExactPlacement`). A walk that wants to type a width asks for this
    /// first, exactly as a person presses Option Command P or right clicks the
    /// layer's row, and then `focus` finds the field in the popover's own
    /// window.
    case positionAndSize, closePositionAndSize
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
    /// Put 20 points of room round the inside of the picked group, which is the
    /// Padding field in the Layout section. A group with room round its
    /// contents has empty air at its own corners, and that is the shape of
    /// everything Corner Radius over a group is about
    /// (`PhotonzCore/ContainerRounding.swift`). The field is a typed number in
    /// the dock, which a walk cannot reach with the pointer, so this is the way
    /// in.
    case roomAroundContents
    /// Layer ▸ Select Original: jumps from a copy of a component to the
    /// original it follows, so a walk can edit the original after dropping a
    /// copy without hunting for its row.
    case selectComponentOriginal
    /// Layer ▸ Delete Layer, which is a menu chord (⌘⌫) and so cannot be
    /// pressed in a walk. A walk that checks what happens after something is
    /// taken away asks for it here.
    case deleteLayer
    /// The four arrange rows in the Layer menu: Bring to Front, Bring Forward,
    /// Send Backward, Send to Back. All four are menu chords hanging off the
    /// focused window, so all four are dimmed and empty for the whole of a
    /// walk (`PlaytestMenuStandIn`).
    ///
    /// The stack IS the composite order and it is the rule a matte reads, so a
    /// walk about compositing that cannot restack is a walk that can only look
    /// at half of it (`LayerCompositing.swift`).
    case bringToFront, bringForward, sendBackward, sendToBack
    /// Edit ▸ Copy and Edit ▸ Paste. Both are menu chords, which do nothing
    /// while the probe is not the active app, so a walk that checks where a
    /// pasted layer lands asks for them here.
    case copyLayer, pasteLayer
    /// The frame rows in the Layer menu (Next, `next-frames`): the size sheet,
    /// and putting a frame around what is selected.
    case newFrameDialog, frameSelection
    /// The Export sheet, so a walk can photograph its frame scope.
    case exportDialog
    /// The Export sheet already on SVG (Next, `next-export-svg`). A walk cannot
    /// click inside a sheet, and Export opens on the format you picked last
    /// time, so this asks for SVG the same way picking it once would and then
    /// opens the sheet.
    case exportDialogAsSVG
    /// The Export sheet already on PNG, for the same reason: a walk cannot
    /// click the format row inside a sheet, and PNG is where the question of
    /// what to do with the canvas behind a drawing is asked.
    case exportDialogAsPNG
    /// The Export sheet already on JPEG (Next, `next-export-quality`), for the
    /// same reason: a walk cannot click the format row inside a sheet, and the
    /// quality slider only exists for a format that has a quality.
    case exportDialogAsJPEG
    /// The Export sheet already on WebP (Next, `next-export-webp`), so a walk
    /// can photograph the one format whose slider reaches lossless.
    case exportDialogAsWebP
    /// The Export sheet with the hand-off question answered for it (Next,
    /// `next-export-animated-svg`): a walk cannot open a menu inside a sheet,
    /// so this says where the file is going and then opens it. Asked for on
    /// the sheet rather than written into the app's memory, so a walk cannot
    /// change where the NEXT walk's Export opens on.
    case exportDialogToWebPage, exportDialogToReadme
    /// The Export sheet on a document that HAS TIME (Next,
    /// `next-export-the-video`), which is the video sheet: as it opens, and
    /// already on GIF at the Small preset, since a walk cannot click a
    /// segmented row inside a sheet.
    case exportDialogAsVideo, exportDialogAsSmallGIF
    /// ...and already on the picture, which is the fourth answer on that same
    /// row: one frame of the document, at the moment the playhead is on.
    case exportDialogAsFrame
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
    /// Pick the first picture on the Library's Media shelf, which is the
    /// newest one the document holds (`DocumentMedia`). Same reason as above:
    /// a walk cannot reach the dock with the pointer.
    case pickFirstMedia
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
    /// View ▸ Show Icon Keylines (Next, `next-icon-frames`): the space an icon
    /// has to live inside, on every icon frame at once. Put them ON, or OFF,
    /// whichever they already are, so a walk starts from something it can rely
    /// on rather than from what the last walk left behind.
    case showIconKeylines, hideIconKeylines
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
    /// Layer ▸ New Layer via Cut (⇧⌘J, Next, `next-new-layer-via-cut`): the
    /// marquee's piece lifts onto a layer of its own and the space it came
    /// from is filled in from what was around it. A menu chord, so this is a
    /// walk's way in.
    case newLayerViaCut
    /// Layer ▸ Separate into Layers on the SELECTED layer (Next,
    /// `next-separate-into-layers`). A menu row on a picture, so a walk asks
    /// for it here rather than hunting a right click in the layers list. The
    /// sweep runs off the main thread, so a walk waits a beat after it.
    case separateIntoLayers
    /// Layer ▸ Turn into Text on the SELECTED layer (Next,
    /// `next-separate-into-layers`): the picture of a run of text becomes
    /// words. Reads off the main thread like the sweep, so a walk waits a beat
    /// after it.
    case turnIntoText
    /// Layer ▸ Turn Into Picture on the SELECTED layers. It raises the question
    /// that asks first, as a sheet on the window, so a walk that wants the turn
    /// itself presses the sheet's own buttons afterwards: "Don't ask again" is
    /// a button on that sheet like any other. Asked for as an action rather
    /// than through the layer row's right click menu so the walk still runs
    /// with the screen locked, where an open menu cannot be driven.
    case turnIntoPicture
    /// Layer ▸ New Layer (⌘N): a fresh empty layer on top, with the marquee
    /// left up so the select → new layer → fill flow can be walked. A menu
    /// chord like the rest of the Layer menu, so this is a walk's way in.
    case newLayer
    /// Edit ▸ Fill with Foreground (⌥⌫) and Fill with Background. Both are
    /// menu rows, and the first carries a chord the field editor claims for
    /// itself, so a walk asks for them here rather than through the keyboard.
    case fillWithForeground, fillWithBackground
    /// Layer ▸ Copy Look (⌥⇧⌘C) and Paste Look (⌥⇧⌘V): take one shape's
    /// paint, borders and effects and put them on another. Window-scoped menu
    /// rows, so a walk's chord reaches a frozen bar and does nothing; these
    /// are the stand-ins (`PlaytestMenuStandIn`).
    case copyLook, pasteLook
    /// View ▸ Show Timing (⌥⌘T): the timing strip under the canvas, opened or
    /// put away. A window-scoped row like the two above.
    case toggleTimingStrip
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
    /// Paint the selected layer's first color with the first entry in the
    /// SECOND list its menu offers: the colours it can paint with but cannot
    /// wear the name of — a colour kept for other parts, a ramp where no ramp
    /// can go, or the colour inside a saved border, shadow, glow or way of
    /// setting text (`BorrowedColors.swift`). That list lives in a menu in the
    /// dock, which a walk cannot open with the pointer.
    case useFirstBorrowedColor
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
    /// Flip the Outline row's switch on every picked PATH, which is what
    /// clicking it in Appearance does: it takes a drawn shape's line away and
    /// hands it back at the weight a fresh one wears
    /// (`PhotonzCore/PathLineStyle.swift`).
    ///
    /// Here for the same reason `toggleFillSwitch` is: a scripted press lands
    /// on a button and on a segment of a picker, and a SwiftUI switch does not
    /// answer one, so every walk that needs a part switched reaches for an
    /// action instead.
    case togglePathOutline
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
    /// Remember the first colour row of the right hand panel exactly as the row
    /// itself holds it, and then, after the walk has picked something else,
    /// paint through the row it remembered.
    ///
    /// This is the one thing a picture cannot show about a panel that leaves
    /// controls alone. A colour row the panel skipped is still on screen
    /// holding the address it was born with, and the promise is that painting
    /// through it reaches whatever is picked NOW rather than the shape it was
    /// drawn for (`ColorTarget.Source`). `paintHeldColorRow` paints and then
    /// checks both halves: every picked layer with that colour wears the new
    /// one, and nothing that is not picked moved at all.
    ///
    /// Every step of the walk that uses these is a click at a place on the
    /// canvas, so it is the one colour check that still answers on a Mac whose
    /// screen is locked and no control carries a name.
    case holdColorRow, paintHeldColorRow
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
    /// ...and the sixth kind, Magnify, which is what the Zoom Callout became:
    /// the next drag marks a region to magnify rather than a box to blur.
    case armLensMagnify
    /// A PICKED lens's Does row: what the lens on the canvas does to the
    /// picture underneath it. Also in the dock, so also out of reach.
    case lensBlur, lensPixelate, lensGreyscale, lensInvert, lensBrightness
    /// The same row switched TO Magnify, which turns the picked lens into a
    /// magnifier of the region it was covering (`LensConversion`).
    case lensMagnify
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
    /// Thickness pulled right up, for a walk about what happens at the ENDS of
    /// a line: the whole difference between a flat, a round and a square end
    /// is the last half width, so on a hairline there is nothing to photograph.
    case dragThicknessFat
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
    /// Take the selected piece out of the line its group arranges and put it in
    /// front of the rest, or hand it back to the line (Next,
    /// `next-auto-layout`), which is what Layer ▸ In Front of the Rest does and
    /// what the Layout section's Role row does. Same reason as the row above:
    /// both are out of a walk's reach with the pointer, and this is how a walk
    /// photographs a badge sitting on the corner of a card.
    case floatSelectionInFront
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

/// What is behind the drawing in a picture a walk wrote: nothing, or the
/// canvas it was made on.
///
/// Read off the four corners of the file itself, because that is where a
/// canvas that should have been left out shows up and where a drawing never
/// reaches.
public enum PictureCorners: String, Sendable, Equatable, CaseIterable {
    /// Every corner see-through, so the icon sits on any colour.
    case empty
    /// Every corner solid, so the picture carries its own background.
    case painted
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
/// How a `dragTiming` step lets go of a bar without keeping the change.
public enum PlaytestTimingCancel: String, CaseIterable, Hashable, Codable, Sendable {
    /// Through the strip's own call-off, the way every other probe reaches a
    /// SwiftUI gesture. It proves the bar goes back; it says nothing about
    /// what a person would press to make that happen.
    case strip
    /// A real Escape press, posted into the app so everything watching for a
    /// key sees it exactly as it sees one off a keyboard.
    case escape
}

/// Which part of a bar on the timing strip a `dragTiming` step takes hold of.
/// What a step claims about the selection chrome on the canvas.
public enum PlaytestOutlineClaim: String, CaseIterable, Hashable, Codable, Sendable {
    /// The blue box and its handles are drawn.
    case drawn
    /// Nothing is drawn round the picked layer.
    case none
}

public enum PlaytestTimingGrab: String, CaseIterable, Hashable, Codable, Sendable {
    /// The bar itself: it moves, keeping its length, so WHEN the motion starts
    /// changes and how long it takes does not.
    case body
    /// Its left hand end: the start moves and the finish stays put.
    case start
    /// Its right hand end: the finish moves and the start stays put.
    case end
}

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

/// Where a `move` step puts the pointer.
///
/// A point is the canvas's own language and is what nearly every move wants.
/// A control is for something whose position depends on the words on it — the
/// button on the line at the foot of the canvas moves every time its label
/// changes — so a walk that aimed at numbers would come to rest beside it and
/// quietly prove nothing. It is found the same way a `press` finds it, through
/// the app's own register of controls, so a control that has gone fails the
/// walk instead.
public enum PlaytestMoveTarget: Sendable, Equatable {
    /// A point, in whichever space the step named.
    case point(PlaytestPoint)
    /// The middle of the control the panel calls this, optionally in a named
    /// row, exactly as `press` reads them.
    case control(String, in: String?)
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

/// How tall the caret is drawn, against a whole line of the caption's face.
///
/// Where the caret sits and how tall it is are two different wrongs. On
/// 2026-09-12 it sat in the wrong place; the day after, on an empty new line,
/// it sat in the right place and was drawn about three fifths of a line tall,
/// because the field was only as tall as the bubble and the line the caret was
/// waiting on hung below the field's bottom edge.
public enum CaptionCaretHeight: String, CaptionClaimWord {
    /// A whole line of the caption's face, the same caret a line with words on
    /// it gets.
    case full
    /// Cut off short of a line, which nothing should be.
    case short
    public init?(claim: String) { self.init(rawValue: claim) }
    public static var claimWords: [String] { ["full", "short"] }
}

/// What the blue selection outline must be doing while the field is open.
/// A corner of a layer's box, named the way a person points at one.
public enum LayerBoxCorner: String, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    /// Which of the four `Layer.transformedCorners` this is: they come back
    /// clockwise from the top left.
    public var index: Int {
        switch self {
        case .topLeft: 0
        case .topRight: 1
        case .bottomRight: 2
        case .bottomLeft: 3
        }
    }

    public static var words: [String] {
        ["topLeft", "topRight", "bottomRight", "bottomLeft"]
    }
}

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
    ///
    /// `pixelScale` is how many of the document's numbers make one point, the
    /// way a Retina capture counts in twos. One, and the document counts one
    /// to one, which is what a blank canvas has always done and what every
    /// walk written before this gets. It is here so a walk can put two
    /// documents that count differently side by side, which is the only way to
    /// see a component cross between them at the size it should be
    /// (`SharedComponentScale`).
    case blank(canvas: CGSize, window: CGSize?, card: String?, pixelScale: CGFloat)
    /// Let the editor finish what the step before started. It ends the moment
    /// the app goes quiet, which is why a walk's waits cost seconds rather than
    /// minutes.
    ///
    /// `onTheClock` spends the whole time instead, and is for the few walks
    /// about a CLOCK rather than about work: the line at the foot of the canvas
    /// leaves after six seconds of an app doing nothing at all, so a walk that
    /// waits for quiet is back in a tenth of a second and has proved nothing
    /// about the six.
    case wait(seconds: Double, onTheClock: Bool)
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
    /// Move the pointer without pressing anything, so a walk can read what the
    /// canvas SAYS a press would do there AND what resting on something makes
    /// the app do. `control` rests on a control by the name the panel gives it,
    /// which is how a walk points at something whose position depends on the
    /// words on it. `modifiers` are held
    /// while the pointer rests: ⌥ over a layer is its own cue (the copy
    /// badge), and over a screen's own surface ⌥ means different things
    /// depending on whether the screen is picked, so a walk has to be able to
    /// hold it without clicking.
    case move(PlaytestMoveTarget, [PlaytestModifier])
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
    /// `readout` is what the pill riding under the drag must say at the end of
    /// the travel, with the button STILL DOWN. It is the only way to claim
    /// anything about a reading that exists solely mid-gesture, and a walk that
    /// passes it has proved the number kept up with the pointer rather than
    /// that a pill was drawn somewhere.
    /// `cancel` presses Escape half way along the travel and then carries on
    /// to the end and lets go, which is a hand changing its mind: a walk that
    /// passes it has proved both that the drag went back AND that the rest of
    /// the gesture did nothing, since the button is still down for all of it.
    /// `showsBox: true` claims that this drag was outlining the box it was
    /// making while the button was still down, AND that the box outlined is
    /// exactly where the thing landed once it came up. It is the claim for a
    /// container that arranges itself, whose contents do not move when its box
    /// changes, so a picture of the canvas mid-drag cannot tell a live box from
    /// a dead one (`ContainerResizeBox`). It needs no numbers in the walk on
    /// purpose: the walk is claiming the outline and the landing AGREE, and the
    /// app knows both.
    ///
    /// `showsBox: false` claims the opposite, and is how the three kinds of
    /// container that must NOT change are held to that: a screen has its own
    /// live edge, and a plain group and a copy of a component both move their
    /// contents under the hand, so a second box on any of them would be one
    /// edge claimed twice. Left off entirely, a drag claims nothing either way.
    case drag(from: PlaytestPoint, to: PlaytestPoint, steps: Int,
              modifiers: [PlaytestModifier], halfway: [PlaytestModifier]?,
              hold: String?, readout: String?, wobble: CGFloat, cancel: Bool,
              showsBox: Bool?)
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
    /// `says` is what the canvas must be SAYING about the file while it is in
    /// the air: a sound or a recording answers in words rather than with a
    /// landing box, and a refusal that names no reason is the thing those words
    /// exist to stop (`MediaDrop`). Matched loosely, so a walk can name the
    /// half of the sentence it cares about.
    /// A press, a pull and a let go posted to the WINDOW rather than handed
    /// to the canvas, so it reaches whatever is under the pointer the way a
    /// hand does: a clip on the timeline, the level line on a sound, a fade
    /// handle. Points are window points, top left, unless `space` says other.
    case windowDrag(from: PlaytestPoint, to: PlaytestPoint, steps: Int)
    case dragFile(file: String, at: PlaytestPoint, hold: String?, release: Bool, leave: Bool,
                  says: String?)
    /// A file carried from the Finder onto the TIMELINE, over the lane of the
    /// track called `track`, `seconds` into the document, and let go there
    /// unless `release` is false. It goes through the timeline's own drop
    /// target, so where it lands is what the ghost promised. `insert` holds ⌘,
    /// which a walk cannot press while a drag is in the air. `hold` names a
    /// picture taken while it is still in the air, ghost and all, and `says`
    /// is what the ghost must be saying then.
    ///
    /// `tile` carries a recording or sound off the Library shelf instead of a
    /// file, by its name there, through the tile's own drag: exactly one of
    /// `file` and `tile` is given.
    case dropOnTimeline(file: String?, tile: String?, track: String, seconds: Double, insert: Bool,
                        hold: String?, release: Bool, says: String?)
    /// Where a clip on the timeline is, by its name, and FAIL when it is not
    /// so: which track it is on, when it starts and when it ends, in seconds,
    /// give or take `within`. `count` is how many clips are called that,
    /// which is what an overwrite that split a clip in two has to claim.
    case expectClip(named: String, track: String?, startsAt: Double?, endsAt: Double?,
                    count: Int?, within: Double)
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
    /// Write the document out as SVG to `<out>/<name>.svg`, the way Export's
    /// SVG answer does (Next, `next-export-svg`). A save panel cannot be driven
    /// from a walk, so this is how a walk proves that what leaves the app is a
    /// real vector file and what it says about the layers it could not write as
    /// shapes.
    ///
    /// `background` is what the Export sheet's Include the background checkbox
    /// says: "drop" (the default, and what the sheet opens on) leaves the
    /// canvas the drawing was made on out of the file, "keep" paints it in.
    /// With a photograph behind the drawing rather than a canvas there is
    /// nothing to leave out and both write the same file.
    case writeSVG(name: String, background: SVGExport.Background)
    /// Write the document out as a picture to `<out>/<name>.<ext>`, at the
    /// format, quality and scale Export would use (Next,
    /// `next-export-quality`), and log how many bytes it came to.
    ///
    /// The number in that log line is the number the Export sheet shows for the
    /// same answers, because it comes from the same encoder given the same
    /// picture. That is how a walk proves the sheet is not estimating: the file
    /// is beside the log line and it weighs what the line said.
    ///
    /// `background` is the Export sheet's Include the background checkbox, the
    /// same answer `writeSVG` takes: "drop" (the default, and what the sheet
    /// opens on) leaves the canvas the drawing was made on out of the picture,
    /// so an icon goes out see-through behind the shapes; "keep" paints it in.
    /// A format that cannot hold transparency writes the canvas either way.
    ///
    /// `behind` is the CLAIM about the file that landed: "empty" means every
    /// corner of it is see-through, "painted" means every corner is solid.
    /// Printing what the corners are is not checking them, and a white box
    /// round an icon is invisible in a screenshot of a white sheet, so this is
    /// the step that can fail.
    case writePicture(name: String, format: String, quality: Int, scale: CGFloat,
                      background: SVGExport.Background, behind: PictureCorners?)
    /// Set the quality a picture format is remembered at, exactly as pressing
    /// Export at that quality would (Next, `next-export-quality`). A walk
    /// cannot drag a slider inside a sheet, so this is how the sheet gets
    /// photographed at a quality other than the one it opens on, and it checks
    /// the remembering at the same time.
    case exportQuality(format: String, percent: Int)
    /// Write the open recording out to a real file, exactly as pressing
    /// Export… on its sheet and choosing a place would, then READ the file back
    /// and check it.
    ///
    /// The save box cannot be driven by a walk, so this runs the same writer
    /// the box hands to and then opens what landed: how long it runs, how big
    /// its picture is, and what it weighs. That is the difference between a
    /// walk that trusts the app about the trim and the crop and one that finds
    /// out. `copied` claims the fast path: an untouched recording going out as
    /// MP4 is a verbatim file copy, so the bytes on disk must match the
    /// recording's own, and a re-encode that has quietly crept in fails here.
    ///
    /// `quality` names one of the three presets; leaving it out takes the one
    /// the Export sheet itself would open on for that format, which is what a
    /// person pressing Export gets.
    ///
    /// `twice` writes the same file a SECOND time and compares the two byte for
    /// byte, which is the only way to find out whether exporting the same
    /// recording twice really gives the same file. `estimateWithin` is the
    /// fraction the sheet's own weight estimate is allowed to be out by: it is
    /// what stops the number under the format quietly drifting away from the
    /// file that lands.
    case writeRecording(name: String, format: String, quality: String?,
                        seconds: Double?, within: Double,
                        width: Double?, height: Double?, copied: Bool?,
                        twice: Bool, estimateWithin: Double?)
    /// Write the DOCUMENT out as a video, exactly as pressing Export… on its
    /// sheet and choosing a place would, then read the file back and check it
    /// (`EditorState.writeVideo`).
    ///
    /// The save box cannot be driven by a walk, so this runs the same writer
    /// the box hands to. `seconds` is how long the file must run, which is what
    /// proves a cut reached it: a walk that threw a piece away expects a file
    /// shorter than the recording. `sound` says whether the file must carry a
    /// sound track, `copied` claims the fast path, and `width`/`height` are the
    /// picture's size in the file rather than the app's idea of it.
    case writeVideo(name: String, format: String, quality: String?,
                    seconds: Double?, within: Double,
                    width: Double?, height: Double?, sound: Bool?, copied: Bool?)
    /// Write ONE FRAME of the document out as a picture, exactly as choosing
    /// PNG on that same sheet and picking a place would, then read the file
    /// back and check it (`EditorState.exportStillFrame`).
    ///
    /// `width` and `height` are the picture's size in the file that landed,
    /// which is what proves the frame left at the size the document is rather
    /// than at whatever the last video preset was set to. `atMS` writes the
    /// frame at a moment other than the one the playhead is on, for a walk
    /// that wants two different frames without moving the playhead twice.
    case writeFrame(name: String, atMS: Int?, width: Double?, height: Double?)
    /// Open a menu that lives INSIDE the window — the Add menu on a
    /// component's Properties list, the ellipsis on the Measurements header —
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
    /// Open the menu you get by RIGHT CLICKING something — a layer row or a
    /// measurement row in the right hand panel (`on`), or a spot on the picture
    /// itself (`at`) — and photograph it.
    ///
    /// The other two menu steps reach menus that hang off something visible: a
    /// menu bar title, or a button in the panel. This one reaches the menus
    /// that hang off nothing at all until the pointer asks for them, which is
    /// why an audit could only ever describe the layer row menu in words.
    /// `shot` names a real screen capture of it, `choose` picks one of its
    /// rows, and `ticked` and `unticked` name the rows that must, and must
    /// not, be wearing a checkmark, so the step is a test and not only a
    /// picture.
    ///
    /// Exactly one of `on` and `at`. The picture has no rows to name — the
    /// thing you right click on it is a SPOT — so `at` is a point in the same
    /// coordinates every other canvas step is written in, document pixels
    /// unless `space` says otherwise.
    case rightClick(on: String?, at: PlaytestPoint?, shot: String?, choose: String?,
                    ticked: [String], unticked: [String])
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
    /// a picture. `says` pins the SENTENCE the target is saying while the
    /// colour is still in the air, matched anywhere in the line and ignoring
    /// case: a ring says yes and a dark swatch says no, but neither says why
    /// it is dark or how many layers a bright one would paint.
    case dragColor(from: String, onto: String, hold: String?,
                   expect: PlaytestColorDropExpectation, says: String?)
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
    /// Drag one bar on the timing strip across the bottom of the window
    /// (`next-motion-strip`). `bar` names it the way the strip labels it,
    /// layer then property: "Bell body Rotation". `grab` says which part of it
    /// is taken hold of — the bar itself, which moves it, or either end, which
    /// changes how long it takes — and `byMS` how far the hand travels, in the
    /// milliseconds the strip is measured in rather than in points, so a walk
    /// says the thing it means. `hold` names a picture taken with the bar still
    /// in hand, which is the only moment the gap bracket is on screen, and
    /// `cancel` lets go of it without committing.
    ///
    /// It drives the strip's own drag rather than posting mouse events, for the
    /// reason written on `PanelAreaHandleProbe`: SwiftUI gestures do not answer
    /// synthesized ones. Everything the drag DECIDES is real — the snapping,
    /// the gap readout, the lap being held, the single undo step — and only the
    /// pointer that would have started it is not.
    /// `cancelBy` says HOW it is called off when `cancel` is set: `strip`
    /// calls the strip's own call-off straight, and `escape` posts a real
    /// Escape key into the app the way a keyboard does, which is the only way
    /// to prove the key is wired to anything at all.
    case dragTiming(bar: String, grab: PlaytestTimingGrab, byMS: Int,
                    hold: String?, cancel: Bool, cancelBy: PlaytestTimingCancel)
    /// Drag ONE KEY along a bar on the timing strip: the mark at a moment the
    /// value is nailed to, between the bar's two ends (`MotionStripKey`).
    ///
    /// The opposite bargain to `dragTiming`: the move stays exactly where it
    /// is and one of its moments changes, which is how a hold is made longer
    /// or shorter. `key` counts the marks from ONE at the left hand end, the
    /// way a person would say "the second one". `cancel` calls the drag off
    /// and checks the key went back where it was.
    case dragMotionKey(bar: String, key: Int, byMS: Int, hold: String?, cancel: Bool)
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
    /// `outline` is the second claim, about the CHROME rather than about what
    /// is picked: `drawn` means the blue box and its handles are on the canvas,
    /// `none` means they are not. The one that matters is `none`, for a layer
    /// with an in and an out at a moment it is not on screen: the words are
    /// gone and their box must go with them, or the picture says the layer is
    /// there and broken (`TitleTime.swift`).
    case expectPicked(layers: [String], outline: PlaytestOutlineClaim?)
    /// What the icon previews strip is showing right now: the sizes its chips
    /// are labelled with, smallest first, or that there is no strip at all.
    ///
    /// A snapshot cannot settle this. The strip is a small card in the top
    /// left of the canvas, and "is it still there, and is it still the same
    /// icon" is the one thing the row exists to be trusted about: it used to
    /// vanish the moment you picked nothing, which is the ordinary way to
    /// stand back and look at what you have drawn. This asks the editor which
    /// icon frame the strip is speaking for and what sizes it drew.
    ///
    /// `absent: true` claims no strip at all, which is what a document with no
    /// icon frame in it must give.
    case expectIconPreviews(sides: [Int], absent: Bool)
    /// How many times a named view may have built since the step before it.
    ///
    /// The guard for what a click COSTS, written as a count rather than as a
    /// time: a stopwatch on a busy machine fails a walk that is fine and
    /// passes one that is not, while "picking a layer rebuilt the whole editor"
    /// is either true or it is not. The views that can be counted are the ones
    /// the probe build meters (`ViewBuildMeter`): `editorBody`,
    /// `inspectorPanel`, `layersList`, `layersRow`, `layerThumbnail`, `colorRow`.
    ///
    /// Zero is the usual ceiling and the useful one: picking a layer must not
    /// re-run the editor's own body, which is the canvas, the tool bar, the
    /// zoom bar and the dock together. It did until 2026-09-14, because the
    /// picked layer rode into the undo stack and the whole window is drawn
    /// from that stack (`layer-pick-latency-walk`).
    /// `atLeast` is the other side of the same claim, and a walk asserting a
    /// ceiling of nothing wants it: a count that is zero because the view has
    /// stopped being drawn at all passes exactly as quietly as one that is zero
    /// because the click was skipped. So the walk that says "an alike pick
    /// rebuilds no colour row" says on the next click that a pick which really
    /// changes something rebuilds some (`color-row-leaves-alone-walk`). One of
    /// the two is enough; both together bound the count from either side.
    case expectBuilds(view: String, atMost: Int?, atLeast: Int?)
    /// Whether the layers list moved under the last pick, which is the one
    /// promise the list makes that a picture cannot show: a row you can
    /// already see wins, and the list stays exactly where the reader left it.
    ///
    /// `moved: false` (the default) is the interesting one. A click near the
    /// top of a list that jolts the panel is the complaint this rule exists
    /// for, and nothing could claim it before: the list's decision is
    /// arithmetic done once and thrown away, so a screenshot taken after the
    /// scroll settled looks the same either way.
    ///
    /// `moved: true` is the other half — a row off the bottom of a long list
    /// MUST be brought in — so a list that quietly stopped following cannot
    /// pass by standing still.
    case expectListStill(moved: Bool)
    /// Whether closing the window right now would lose work: the dot in the
    /// close button, and the save prompt behind it.
    ///
    /// It is here for the promises the app makes about work NOBODY DID. The
    /// words read off a separated picture are written into the document so the
    /// file opens already named, and the one thing that must never follow from
    /// that is a person being asked to save changes they did not make. A walk
    /// that separates a page, lets the reading land and presses undo can say
    /// `expectEdited: false` and pin it.
    case expectEdited(Bool)
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
    /// What the document would be WRITTEN as, asked without saving anything.
    ///
    /// `pictured` is how many layers have no vector answer and would ride out
    /// as embedded pictures; zero is the usual claim and the one that says a
    /// drawing really is shapes. `contains` is a run of text the file must
    /// carry, for the handful of things a picture of the file cannot show —
    /// that a highlight says it mixes with what is under it, say.
    ///
    /// A `writeSVG` step already prints both, but printing is not checking: a
    /// walk stays green while the line quietly changes. This is the claim.
    case expectSVG(pictured: Int?, contains: String?)
    /// How many editor WINDOWS carrying this title are open right now.
    ///
    /// The one claim about the app that is not about anything inside a window,
    /// and the only way a walk can hold the guides to leaving at most one
    /// practice window behind. Working a track back to back used to open a
    /// window per guide, five of them all called Tutorial Sample, and no
    /// screenshot of any one of those windows could show it: each one looked
    /// exactly right (`TutorialLauncher`). Panels do not count, so a callout or
    /// a tooltip floating over a window is never mistaken for one.
    case expectWindows(titled: String, count: Int)
    /// What the recording in front of the walk is made of: how many pieces it
    /// is in, which one is picked (1-based, 0 for none), how many of them the
    /// live trim window keeps, and how long that window is. Every claim is
    /// optional; the step has to make at least one.
    case expectRecording(pieces: Int?, picked: Int?, keeps: Int?, seconds: Double?,
                         starts: Double?, caught: Bool?, playhead: Double?)
    /// What the recording's FILE on disk says, which is the only thing that
    /// settles whether a save saved. `seconds` is how long the stored media
    /// must now be, `within` how close that has to be, and `original` whether
    /// the untouched original is preserved beside it (what makes the edit
    /// reversible). The app is not asked: the file is opened and measured.
    case expectStoredRecording(seconds: Double?, within: Double, original: Bool?)
    /// Which tutorial shelves must be on offer right now, and which must not,
    /// by the name a person reads ("Redlining").
    ///
    /// Asked of BOTH places a shelf shows: Help ▸ Tutorials, and the Tutorials
    /// window, which has to be open. They are built from the same catalogue but
    /// at different moments — the menu bar once at launch, the window every
    /// time it is drawn — so a feature switched off that reaches only one of
    /// them is exactly the kind of thing that goes unnoticed.
    case expectTutorialTracks(with: [String], without: [String])
    /// Where a measurement's ends are right now, and what it reads.
    ///
    /// A picture cannot settle this. The feet are two dots a few points across
    /// sitting on a picture full of edges, and telling "the end went six points
    /// right" from "the end went two points left" off a screenshot is counting
    /// pixels. This asks the DOCUMENT, in the same coordinates the walk's own
    /// clicks are written in, which is how a walk can claim that an end
    /// travelled as far as the hand did and the same way.
    ///
    /// `start` and `end` are the two feet, either one on its own, with `within`
    /// document points of slack (half a point unless said otherwise: a drag is
    /// synthesized as a run of moves and lands where the pointer lands).
    /// `reads` is the label the measurement is wearing, "106 px", which is the
    /// other half of the claim: a reading that got shorter while the hand
    /// pulled it longer is the bug this step was written for.
    /// `layer` names which measurement to ask when there is more than one; the
    /// only one on the canvas is meant when it is left off.
    case expectFeet(layer: String?, start: PlaytestPoint?, end: PlaytestPoint?,
                    reads: String?, within: CGFloat)
    /// Where the marquee is right now, or that there is none.
    ///
    /// The outline is the one thing on the canvas a walk cannot photograph a
    /// claim about: `describe` writes it into the log and nothing reads it
    /// back, so a marquee thrown away by a stray tool key passed every walk
    /// that watched it for a week (2026-09-08). `reads` is the outline's box
    /// exactly as the log spells it, "400,300 200x100"; `present` claims only
    /// whether there is one at all, and `false` is the useful half.
    case expectRegion(reads: String?, present: Bool?)
    /// The words on the chip under the canvas right now must contain `contains`.
    ///
    /// The chip is the app's one place for saying what the thing you are
    /// holding can do, and until now nothing could claim it: `describe` wrote
    /// it into the log and no walk read it back. That is how a path shipped
    /// with every reshape gesture working and the chip, at the one moment
    /// anybody needed it, talking about something else (2026-09-15). A
    /// substring rather than the whole line, so a walk claims the PROMISE the
    /// chip makes rather than breaking on a comma.
    case expectHint(contains: String)
    /// What the canvas says a press at the pointer would take hold of, right
    /// now: `none`, `grab`, `rotate`, or `resize-<axis>`.
    ///
    /// The pointer's shape is the only invitation canvas chrome has — a small
    /// mark sitting on top of a much larger object looks like the object until
    /// the cursor says otherwise — so a walk has to be able to claim it. It is
    /// the app's own answer for the point the walk last moved to, which makes
    /// it exact and repeatable; the real OS cursor is somewhere else entirely
    /// during a walk and comes back in the log as corroboration only.
    case expectCue(says: String)
    /// Who a REAL click at a point would go to: the picture, or a piece of
    /// chrome floating over it.
    ///
    /// A walk's own click is handed to the canvas view directly, so it lands
    /// whether or not anything is covering the spot. That is right for driving
    /// the picture and useless for the question this asks, which is whether
    /// chrome the app floats over the canvas is LETTING THE PICTURE THROUGH.
    /// The notice pill under the canvas took every click across its whole
    /// capsule for six seconds after each separation and no walk could see it.
    ///
    /// The answer comes from the window, hit testing the point exactly as
    /// AppKit does for a pointer, so what it reports is what a hand would get.
    case expectClickReaches(PlaytestPoint, what: PlaytestClickTaker)
    /// What the NOTICE PILL under the canvas is saying, or that there is none.
    ///
    /// The pill and the tool chip share the slot under the canvas and the pill
    /// wins while it is up (`EditorView`), but they are different surfaces
    /// saying different kinds of thing: a chip teaches the gesture under your
    /// hand, and a pill reports what a command just did. This claims the pill,
    /// which is the only way a walk can hold the app to a sentence it is
    /// obliged to say — above all the sentence a command says when it changed
    /// NOTHING, which is the one case where the canvas cannot tell you.
    case expectNotice(says: String?, absent: Bool?, held: Bool?)
    /// What the TOASTS in the bottom-right corner are saying, or that none of
    /// them is saying it.
    ///
    /// The corner is where the app reports work that outlives the window that
    /// asked for it: a capture landing, a clip reaching the clipboard, and now
    /// a recording being written (`RecordingSaveAnnouncer`). Each toast is its
    /// own panel rather than anything inside the window, so no other step can
    /// see one — a walk could watch a recording save correctly and have no way
    /// to ask whether the app ever SAID so, which is the whole of what this
    /// change is about.
    ///
    /// `says` matches a substring of any toast on screen, progress bars
    /// included, so a walk claims the promise rather than the punctuation.
    case expectToast(says: String?, absent: Bool?)
    /// What the path the Pen just drew is actually made of: how many anchors it
    /// has, whether it closed, and how many of its runs are curves.
    ///
    /// A picture cannot settle any of the three. A closed triangle and an open
    /// one photograph almost identically at the join, a curve dragged half a
    /// point is a curve the render cannot show, and counting anchors off a
    /// screenshot is counting dots that are chrome and gone by the time the
    /// shot is taken. This asks the DOCUMENT, which is where the anchors live.
    ///
    /// `layer` names which path to ask when there is more than one; the last
    /// path in the document is the one meant when it is left off, because a
    /// walk that just drew one is asking about the one it drew.
    ///
    /// `width` is the weight the line came out at, which is the other thing a
    /// picture cannot settle: a 2 point line and a 4 point line on a canvas at
    /// 3200% are both simply "a red line", and telling them apart means
    /// counting pixels off a screenshot (`IconStrokeWeight`).
    /// `fill` and `ink` are the two colours the path came out wearing: the
    /// inside it paints once it closes, and the outline it is drawn in. They
    /// are what a walk about ARMING a colour has to claim — a screenshot of a
    /// blue triangle proves it is blue-ish, not that it is the blue the tool
    /// bar was set to, and an offscreen render resolves colours differently
    /// again. `fill: "none"` claims a path with no inside at all.
    /// `halfSmooth` is how many of its points curve on ONE side only, which
    /// is the one shape neither `curves` nor `smooth` can pin down: a point
    /// that arrives straight and leaves on a curve is not a smooth bend and
    /// the runs either side of it are counted the same whether it is one or a
    /// hard corner sitting between a line and a curve.
    ///
    /// `rings` is how many separate loops the outline is made of, which is the
    /// only way a walk can claim that a shape really has a HOLE in it: a ring
    /// built by cutting one circle out of another has exactly two, and a walk
    /// that only counted its points would pass on a solid disc with the same
    /// number of them (`PathCombining.swift`).
    /// `picked` is how many of its points are PICKED right now, which is the
    /// only way a walk can claim a box swept over them took the ones it went
    /// round: the shape itself is unchanged by picking anything.
    case expectPath(layer: String?, anchors: Int?, closed: Bool?, curves: Int?,
                    smooth: Int?, halfSmooth: Int?, rings: Int?, width: CGFloat?,
                    fill: String?, ink: String?, picked: Int?,
                    anchorAt: PlaytestAnchorClaim?)
    /// How far the points and levers drawn on the picked path may be from the
    /// shape the canvas is actually drawing, in screen points, at the worst
    /// moment of the drag that just ran.
    ///
    /// This is the one claim that can only be made WHILE the button is down.
    /// On 2026-09-14 a lever drag bent the shape under a set of points that
    /// never moved until the release, and every check there was passed: the
    /// document was right, the render was right, and the picture taken after
    /// the drag was right. So the app keeps a reading of its own as the drag
    /// runs (`pathChromeDrift`), and this is a walk asking for the worst of it.
    ///
    /// `within` is a distance on screen, not in the document, so the same claim
    /// holds at every zoom. Left off it is one point: the points are on the
    /// shape, not near it.
    case expectChrome(within: CGFloat)
    /// CLAIMS that the canvas is showing the picture drawn at the size it is
    /// being shown at, rather than a document-sized picture blown up.
    ///
    /// Zoomed past 1:1 the canvas lays a sharp copy of what is in the window
    /// over the stretched composite (`refreshCrispTile`). Without it, every
    /// shape on screen is whatever the document's own pixels make of it, which
    /// at 3200% is 1-document-pixel blocks with a stepped fringe: a circle
    /// drawn on a 24 point icon frame stops looking like a circle.
    ///
    /// A picture cannot settle this on its own, and nor can a person's patience:
    /// the sharp copy lands about a tenth of a second after whatever changed,
    /// so the step waits up to `within` seconds (three unless said otherwise)
    /// for it and fails naming what the canvas is showing instead.
    /// `absent: true` is the other claim, for at or below 1:1 where a second
    /// copy would buy nothing.
    case expectSharp(absent: Bool, within: Double)
    /// What the pill riding under a drag says right now, or that there is no
    /// pill at all. The absent form is how a walk proves the reading goes the
    /// instant the button comes up rather than lingering over the canvas.
    case expectReadout(says: String?, absent: Bool)
    /// Where the canvas says a press would put the first point of a shape,
    /// which is the mark drawn under the pointer while you are only hovering
    /// (`CanvasDrawLanding`).
    ///
    /// A picture cannot settle this. The mark is a ring a few points across
    /// sitting on a grid crossing that is itself a line on screen, so reading
    /// "the ring is on the right line" off a screenshot is counting pixels
    /// between two things that are both chrome. This asks the canvas for the
    /// document point the ring is on, which is the same point the press uses.
    ///
    /// `near` is where it should be, in document coordinates, with `within`
    /// document points of slack (half a point unless said otherwise, because
    /// the claim worth making is that it is EXACTLY on the crossing).
    /// `absent: true` claims no mark at all, which is what ⌘ and a canvas with
    /// nothing pulling must both give.
    case expectLanding(near: PlaytestPoint?, within: CGFloat, absent: Bool)
    /// How many layers the document must hold right now, counting the ones
    /// inside groups.
    ///
    /// The panel cannot answer this. A command that makes a hundred layers
    /// renders a dozen rows and keeps the rest until you scroll to them, so a
    /// walk that asks the panel for "Text 100" is told it is not there when it
    /// is — which is how a walk over a whole screenshot fails for the wrong
    /// reason. This asks the DOCUMENT, which is where the count lives.
    ///
    /// A range rather than one number, because the thing usually worth claiming
    /// is "a lot came out and the list did not become a wall": `atLeast` is the
    /// floor a person would notice missing, `atMost` the ceiling the limit
    /// promises (`SeparateBudget`). `count` sets both to the same number when a
    /// walk really does know the answer exactly.
    case expectLayers(atLeast: Int?, atMost: Int?)
    /// What the timeline keys did (`TimelineKeys.swift`): where the playhead
    /// is to the millisecond, whether the timeline or the canvas has the
    /// keyboard, how fast it is playing, which of the timeline's tools is in
    /// hand, and the In and Out marks. A picture cannot tell one frame from
    /// the next, and `expectRecording`'s playhead is only good to a quarter
    /// of a second.
    case expectTimeline(PlaytestTimelineClaim)
    /// Plays the document for `seconds` and looks at what the canvas is
    /// showing `moments` times along the way, writing each look to
    /// `<name>-<n>.png`. Fails if the clip area is empty in any of them.
    ///
    /// A snapshot or two cannot see a frame that is empty for 33ms, which is
    /// how playing a full-screen recording flickered while every walk that
    /// played one passed (`playing-a-recording-never-blinks`).
    case expectPlaybackNeverBlank(name: String, seconds: Double, moments: Int)
    /// Where a named layer's box must have landed, in the two spaces that
    /// matter.
    ///
    /// `at` and `size` are the box the layer's own Position and Size panel
    /// shows: its place inside whatever holds it, measured upright. `corner`
    /// and `onScreen` are one corner as a PERSON sees it, after every turn
    /// above the layer and its own.
    ///
    /// Both exist because of pieces inside a card that has been turned. A
    /// picture of one settles nothing: the box is drawn on the slant, so a
    /// drag that followed the hand and a drag that went off at an angle to it
    /// look much the same in a snapshot, and a resize that swung the far
    /// corner looks exactly like one that held it. The first pair says the
    /// piece moved by what the hand moved, the second says the corner nobody
    /// touched stayed where it was.
    ///
    /// `reachable` is the third claim and the plainest one: the layer's whole
    /// box is inside the canvas, so the camera can be scrolled to look at it.
    /// A layer placed past the canvas edge is drawn by nothing and reached by
    /// nothing — it shows in the layers list and nowhere else — and a picture
    /// of the canvas cannot tell that apart from a layer that is merely off
    /// screen right now.
    case expectBox(layer: String, at: PlaytestPoint?, size: PlaytestPoint?,
                   corner: LayerBoxCorner?, onScreen: PlaytestPoint?,
                   reachable: Bool, within: CGFloat)
    /// Claims about the inline typing field that is open right now: where its
    /// top left corner sits on screen, in document points, and how far it
    /// leans, in degrees clockwise.
    ///
    /// A picture cannot settle this on its own. The field is a thin blue
    /// outline over the words it is standing in for, and on a card turned a
    /// few degrees a field in the right place and a field a little off both
    /// read as "a box near the label". It opened at the spot the words would
    /// take if the card were straight, which on a twenty degree card put it
    /// about sixty points from the label and upright over a slanted one.
    case expectField(onScreen: PlaytestPoint?, degrees: CGFloat?, within: CGFloat)
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
                       caretHeight: CaptionCaretHeight?, outline: CaptionOutlineClaim?)
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
    /// The sections the right hand panel shows, top to bottom, START with
    /// these, in this order (Layers aside, since it heads every dock).
    ///
    /// How a walk reads back the rule about what a layer in a document with
    /// time leads with (`TimePanelOrder`): a clip's Time, Sound, Animating; a
    /// title's Time, Text, Animating; a sound's Sound, Time. Named the way the
    /// dock titles them. The failure lists the order the dock really has.
    case expectSections(leading: [String])
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
    /// Measure every labelled row and control in the panel against the
    /// panel's side margin (`PanelMarginRule`), write them to
    /// `panel-margins-<stage>.json`, and fail the walk if any of them comes
    /// closer to either edge than the margin. `"report": true` writes the
    /// numbers and passes, for a survey of a panel nobody has fixed yet.
    case panelMargins(stage: String, reportOnly: Bool)
    /// Put the probe into light or dark for the shots that follow, so one walk
    /// can photograph a surface both ways. It changes THIS app only, never the
    /// machine's setting, so nothing outside the probe notices.
    case appearance(PlaytestAppearance)
    case action(PlaytestAction)
    /// Start one guide by id, the way picking it off the Help menu does. The
    /// walk then follows it into whatever window it teaches in, so a guide
    /// that brings a sample is driven in the window a person would be looking
    /// at: `{ "do": "startGuide", "guide": "mark-it-up" }`. `startTour` is the
    /// same thing for the one promoted guide, kept because the first run
    /// offers that one by name.
    ///
    /// `width` and `height` set the size of that window, the same way `open`
    /// does. A guide's own window otherwise arrives at whatever size the app
    /// gives it, which is always roomy, and some of what a guide has to get
    /// right only happens when the window is NARROW: the tool bar sheds its
    /// last buttons into a More menu, and a step naming one of those tools has
    /// to point at the menu instead.
    case startGuide(String, window: CGSize? = nil)
    /// Put the picked lens's own slider on an exact number, the way a finger
    /// that landed precisely would: live previews on the way, one undo step at
    /// the end.
    ///
    /// `pullLensAmount` takes it to the far end, which is enough for a walk
    /// that only wants the lens strong. A walk about a THRESHOLD needs both
    /// sides of the line, one point under and one point over, and neither end
    /// of the slider is either of those.
    ///
    /// `hold` leaves the finger DOWN: the picture follows the pull and nothing
    /// is settled, which is the only way a walk can drag past a mark and come
    /// back the way a hand does.
    case setLensAmount(CGFloat, hold: Bool)
    /// Which step of a guide is up RIGHT NOW, by the step's id.
    ///
    /// The other half of `waitFor tutorialStep`, and the half that can prove a
    /// guide DID NOT move on. Waiting proves a step arrived; only asking on the
    /// spot proves a step stayed. A guide that advances on a change far short
    /// of what it asked for passes every waiting step in its walk, because the
    /// step it wrongly moved to is the step the walk was waiting for.
    case expectTutorialStep(String)

    public static let defaultTimeout: Double = 10
    public static let defaultDragSteps = 8
    /// Enough nudges that a pinch across a whole octave of zoom lands on more
    /// zooms than a hand would, so nothing can slip between two of them.
    public static let defaultPinchSteps = 24

    /// Every step name, sorted, as the error text and the doc list them.
    public static let names: [String] = [
        "action", "appKey", "appearance", "blank", "clearClipboard", "click", "describe", "drag",
        "dragColor", "dragComponent",
        "dragFile", "dragHandle", "dragMotionKey", "dragOver", "dragRow", "dragSection", "dragTile", "dragTiming",
        "dropComponent",
        "dropImage", "dropOnTimeline", "expect", "expectBox", "expectBuilds", "expectCaption", "expectChrome", "expectClickReaches", "expectClip", "expectCue", "expectEdited", "expectFeet", "expectField", "expectHint", "expectIconPreviews", "expectInView", "expectLanding", "expectLayers", "expectListStill", "expectMeasures", "expectNotice", "expectOneNumberPerName", "expectOneUnit", "expectPath", "expectPicked", "expectPlaybackNeverBlank", "expectReadout", "expectRecording", "expectRegion", "expectSVG", "expectSectionFits", "expectSections", "expectSharp", "expectStoredRecording", "expectTimeline", "expectToast", "expectTutorialStep", "expectTutorialTracks", "expectWindows", "exportQuality", "focus", "hover", "key", "measureMode", "menuShot", "menus", "move", "open",
        "panel", "panelEdge", "panelMargins", "panelMenu", "panelStart", "pickUpTile", "pinch", "press",
        "readClipboard", "render", "reveal", "rightClick", "scrollPanel", "selectRow", "setLensAmount", "shortcut", "snapshot", "startGuide", "tool", "toolBar", "toolFlyout", "type", "wait", "waitFor", "writeFrame", "writePicture", "writeRecording", "writeSVG", "writeVideo", "windowDrag",
    ].sorted()

    /// The `do` name this step answers to.
    public var name: String {
        switch self {
        case .open: "open"
        case .startGuide: "startGuide"
        case .setLensAmount: "setLensAmount"
        case .expectTutorialStep: "expectTutorialStep"
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
        case .windowDrag: "windowDrag"
        case .dropOnTimeline: "dropOnTimeline"
        case .expectClip: "expectClip"
        case .dragOver: "dragOver"
        case .snapshot: "snapshot"
        case .render: "render"
        case .writeSVG: "writeSVG"
        case .writePicture: "writePicture"
        case .exportQuality: "exportQuality"
        case .writeRecording: "writeRecording"
        case .writeVideo: "writeVideo"
        case .writeFrame: "writeFrame"
        case .panelMenu: "panelMenu"
        case .menuShot: "menuShot"
        case .rightClick: "rightClick"
        case .dragTile: "dragTile"
        case .pickUpTile: "pickUpTile"
        case .dragRow: "dragRow"
        case .dragColor: "dragColor"
        case .dragSection: "dragSection"
        case .dragTiming: "dragTiming"
        case .dragMotionKey: "dragMotionKey"
        case .dragHandle: "dragHandle"
        case .selectRow: "selectRow"
        case .press: "press"
        case .panel: "panel"
        case .expect: "expect"
        case .expectMeasures: "expectMeasures"
        case .expectSVG: "expectSVG"
        case .expectWindows: "expectWindows"
        case .expectRecording: "expectRecording"
        case .expectStoredRecording: "expectStoredRecording"
        case .expectTutorialTracks: "expectTutorialTracks"
        case .expectFeet: "expectFeet"
        case .expectRegion: "expectRegion"
        case .expectPath: "expectPath"
        case .expectChrome: "expectChrome"
        case .expectSharp: "expectSharp"
        case .expectReadout: "expectReadout"
        case .expectLanding: "expectLanding"
        case .expectHint: "expectHint"
        case .expectCue: "expectCue"
        case .expectClickReaches: "expectClickReaches"
        case .expectNotice: "expectNotice"
        case .expectToast: "expectToast"
        case .expectLayers: "expectLayers"
        case .expectTimeline: "expectTimeline"
        case .expectPlaybackNeverBlank: "expectPlaybackNeverBlank"
        case .expectBox: "expectBox"
        case .expectField: "expectField"
        case .expectCaption: "expectCaption"
        case .expectSectionFits: "expectSectionFits"
        case .expectSections: "expectSections"
        case .expectInView: "expectInView"
        case .expectOneUnit: "expectOneUnit"
        case .expectOneNumberPerName: "expectOneNumberPerName"
        case .expectPicked: "expectPicked"
        case .expectIconPreviews: "expectIconPreviews"
        case .expectBuilds: "expectBuilds"
        case .expectListStill: "expectListStill"
        case .expectEdited: "expectEdited"
        case .scrollPanel: "scrollPanel"
        case .reveal: "reveal"
        case .describe: "describe"
        case .clearClipboard: "clearClipboard"
        case .readClipboard: "readClipboard"
        case .menus: "menus"
        case .toolBar: "toolBar"
        case .panelEdge: "panelEdge"
        case .panelStart: "panelStart"
        case .panelMargins: "panelMargins"
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
            let scale = try f.optionalNumber("pixelScale") ?? 1
            guard scale > 0, scale.isFinite else {
                throw f.invalid("pixelScale", "must be a positive number")
            }
            self = .blank(canvas: canvas, window: window, card: try f.optionalString("card"),
                          pixelScale: CGFloat(scale))
        case "wait":
            self = .wait(seconds: try f.number("seconds"),
                         onTheClock: try f.optionalFlag("onTheClock") ?? false)
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
            if let control = try f.optionalString("control") {
                self = .move(.control(control, in: try f.optionalString("in")), try f.modifiers())
            } else if fields["at"] != nil {
                self = .move(.point(try f.point("at")), try f.modifiers())
            } else {
                throw f.invalid("at", "move needs an \"at\" point on the canvas or a \"control\" to rest on by name")
            }
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
                         readout: try f.optionalString("readout"),
                         wobble: CGFloat(try f.optionalNumber("wobble") ?? 0),
                         cancel: try f.optionalFlag("cancel") ?? false,
                         showsBox: try f.optionalFlag("showsBox"))
        case "expectReadout":
            let says = try f.optionalString("says")
            let absent = try f.optionalFlag("absent") ?? false
            guard absent != (says != nil) else {
                throw f.invalid("says", "expectReadout claims one of two things: \"says\" with "
                    + "the words the pill under the drag must be carrying, or \"absent\": true "
                    + "for no pill at all. It cannot claim both and it has to claim one")
            }
            self = .expectReadout(says: says, absent: absent)
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
            case "sectionDirectlyUnder": .sectionDirectlyUnder(try f.string("value"),
                                                               under: try f.string("under"))
            case "layerRowInView": .layerRowInView(try f.string("value"))
            case "tutorialStep": .tutorialStep(try f.string("value"))
            case "tutorialFinished": .tutorialFinished(try f.string("value"))
            case "exportSizeWeighed": .exportSizeWeighed
            case "dialogUp": .dialog(try f.string("value"), up: true)
            case "dialogGone": .dialog(try f.string("value"), up: false)
            default: throw f.invalid("condition", "\"\(condition)\" is not a condition; use edgeMap, captionField, tool, measureMode, sectionInView, sectionHeaderInView, sectionDirectlyUnder, layerRowInView, tutorialStep, tutorialFinished, exportSizeWeighed, dialogUp or dialogGone")
            }
            self = .waitFor(parsed, timeout: try f.optionalNumber("timeout") ?? Self.defaultTimeout)
        case "startGuide":
            let width = try f.optionalNumber("width"), height = try f.optionalNumber("height")
            let window: CGSize? = if let width, let height { CGSize(width: width, height: height) } else { nil }
            self = .startGuide(try f.string("guide"), window: window)
        case "setLensAmount":
            guard fields["to"] != nil else {
                throw f.invalid("to", "setLensAmount has to say what to put the slider on, "
                    + "in the unit the lens's own adjustment states: points for Blur and Pixelate")
            }
            self = .setLensAmount(CGFloat(try f.number("to")),
                                  hold: try f.optionalFlag("hold") ?? false)
        case "expectTutorialStep":
            self = .expectTutorialStep(try f.string("step"))
        case "snapshot":
            self = .snapshot(name: try f.string("name"), window: try f.optionalString("window"))
        case "dropComponent":
            self = .dropComponent(at: try f.point("at"))
        case "dragComponent":
            self = .dragComponent(at: try f.point("at"))
        case "dropImage":
            self = .dropImage(file: try f.string("file"), at: try f.point("at"),
                              hold: try f.optionalString("hold"))
        case "windowDrag":
            let steps = try f.optionalNumber("steps").map { Int($0) } ?? Self.defaultDragSteps
            let windowed = fields["space"] == nil
            var from = try f.point("from"), to = try f.point("to")
            if windowed {
                from.space = .window
                to.space = .window
            }
            self = .windowDrag(from: from, to: to, steps: max(1, steps))
        case "dragFile":
            self = .dragFile(file: try f.string("file"), at: try f.point("at"),
                             hold: try f.optionalString("hold"),
                             release: try f.optionalFlag("release") ?? false,
                             leave: try f.optionalFlag("leave") ?? false,
                             says: try f.optionalString("says"))
        case "dropOnTimeline":
            let file = try f.optionalString("file")
            let tile = try f.optionalString("tile")
            guard (file == nil) != (tile == nil) else {
                throw PlaytestScriptError.invalidField(
                    index: index, step: name, field: file == nil ? "file" : "tile",
                    reason: "a dropOnTimeline step carries either a \"file\" from disk or a \"tile\" "
                        + "off the Library shelf, exactly one of them")
            }
            self = .dropOnTimeline(file: file, tile: tile, track: try f.string("track"),
                                   seconds: try f.number("seconds"),
                                   insert: try f.optionalFlag("insert") ?? false,
                                   hold: try f.optionalString("hold"),
                                   release: try f.optionalFlag("release") ?? true,
                                   says: try f.optionalString("says"))
        case "expectClip":
            let count = try f.optionalNumber("count").map { Int($0) }
            let track = try f.optionalString("track")
            let startsAt = try f.optionalNumber("startsAt")
            let endsAt = try f.optionalNumber("endsAt")
            guard track != nil || startsAt != nil || endsAt != nil || count != nil else {
                throw f.invalid("startsAt", "expectClip has to claim something: "
                    + "a track, a startsAt, an endsAt or a count")
            }
            self = .expectClip(named: try f.string("clip"), track: track, startsAt: startsAt,
                               endsAt: endsAt, count: count,
                               within: try f.optionalNumber("within") ?? 0.05)
        case "dragOver":
            self = .dragOver(carry: try f.string("carry"), at: try f.point("at"),
                             hold: try f.optionalString("hold"),
                             leave: try f.optionalFlag("leave") ?? false)
        case "render":
            self = .render(name: try f.string("name"),
                           scale: CGFloat(try f.optionalNumber("scale") ?? 1))
        case "writeSVG":
            let background = f.has("background")
                ? try f.enumValue("background", SVGExport.Background.self)
                : SVGExport.Background.drop
            self = .writeSVG(name: try f.string("name"), background: background)
        case "writePicture":
            let canvas = f.has("background")
                ? try f.enumValue("background", SVGExport.Background.self)
                : SVGExport.Background.drop
            self = .writePicture(name: try f.string("name"),
                                 format: try f.string("format"),
                                 quality: Int(try f.optionalNumber("quality")
                                     ?? Double(ExportQuality.standard)),
                                 scale: CGFloat(try f.optionalNumber("scale") ?? 1),
                                 background: canvas,
                                 behind: f.has("behind")
                                     ? try f.enumValue("behind", PictureCorners.self) : nil)
        case "exportQuality":
            self = .exportQuality(format: try f.string("format"),
                                  percent: Int(try f.number("percent")))
        case "writeRecording":
            self = .writeRecording(name: try f.string("name"),
                                   format: try f.optionalString("format") ?? "mp4",
                                   quality: try f.optionalString("quality"),
                                   seconds: try f.optionalNumber("seconds"),
                                   within: try f.optionalNumber("within") ?? 0.4,
                                   width: try f.optionalNumber("width"),
                                   height: try f.optionalNumber("height"),
                                   copied: try f.optionalFlag("copied"),
                                   twice: try f.optionalFlag("twice") ?? false,
                                   estimateWithin: try f.optionalNumber("estimateWithin"))
        case "writeVideo":
            self = .writeVideo(name: try f.string("name"),
                               format: try f.optionalString("format") ?? "mp4",
                               quality: try f.optionalString("quality"),
                               seconds: try f.optionalNumber("seconds"),
                               within: try f.optionalNumber("within") ?? 0.4,
                               width: try f.optionalNumber("width"),
                               height: try f.optionalNumber("height"),
                               sound: try f.optionalFlag("sound"),
                               copied: try f.optionalFlag("copied"))
        case "writeFrame":
            self = .writeFrame(name: try f.string("name"),
                               atMS: try f.optionalNumber("atMS").map { Int($0) },
                               width: try f.optionalNumber("width"),
                               height: try f.optionalNumber("height"))
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
            let onRow = try f.optionalString("on")
            let onCanvas = fields["at"] == nil ? nil : try f.point("at")
            guard onRow != nil || onCanvas != nil else {
                throw f.invalid("on", "must name a row, or the step must name a spot "
                              + "on the picture with \"at\": [x, y]")
            }
            self = .rightClick(on: onRow, at: onCanvas,
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
                              hold: try f.optionalString("hold"), expect: expect,
                              says: try f.optionalString("says"))
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
        case "dragTiming":
            let grab: PlaytestTimingGrab = if fields["grab"] == nil {
                .body
            } else {
                try f.enumValue("grab", PlaytestTimingGrab.self)
            }
            let cancelBy: PlaytestTimingCancel = if fields["cancelBy"] == nil {
                .strip
            } else {
                try f.enumValue("cancelBy", PlaytestTimingCancel.self)
            }
            self = .dragTiming(bar: try f.string("bar"), grab: grab,
                               byMS: Int(try f.number("byMS").rounded()),
                               hold: try f.optionalString("hold"),
                               cancel: try f.optionalFlag("cancel") ?? false,
                               cancelBy: cancelBy)
        case "dragMotionKey":
            let key = Int(try f.number("key").rounded())
            guard key >= 1 else {
                throw PlaytestScriptError.invalidField(index: index, step: name, field: "key",
                                                      reason: "counts the marks from 1 at the "
                                                          + "left hand end of the bar")
            }
            self = .dragMotionKey(bar: try f.string("bar"), key: key,
                                  byMS: Int(try f.number("byMS").rounded()),
                                  hold: try f.optionalString("hold"),
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
            // A tile shows its own name and nothing else, so asking one what
            // it reads is a claim the step could never test. A ROW is not like
            // that: it says whether it is a group and open, what a shut group
            // is hiding, whether it is a copy of a component, what a
            // separation left in it, how many pieces a clip is cut into and
            // which half of a mask it is, all in captions six points high
            // (`LayersRow.rowDetail`).
            // Claiming those in words is the only alternative to photographing
            // them and squinting.
            if reads != nil, thing == .tile {
                throw f.invalid("reads", "only a field, a menu, a control or a row can be asked what it reads; a \(thing.rawValue) shows its own name, so claim \"present\" instead")
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
        case "expectPath":
            let anchors = try f.optionalNumber("anchors")
            let curves = try f.optionalNumber("curves")
            let smooth = try f.optionalNumber("smooth")
            let halfSmooth = try f.optionalNumber("halfSmooth")
            let rings = try f.optionalNumber("rings")
            let picked = try f.optionalNumber("picked")
            let closed = try f.optionalFlag("closed")
            // Where one named point ENDED UP, which is the only way a walk can
            // claim that dragging it did anything: a reshaped path has the same
            // number of points it started with.
            var anchorAt: PlaytestAnchorClaim?
            if let index = try f.optionalNumber("anchor") {
                guard index >= 0, index == index.rounded() else {
                    throw f.invalid("anchor", "a point is named by its place in the path, "
                        + "a whole number from 0, not \(index)")
                }
                guard fields["near"] != nil else {
                    throw f.invalid("near", "naming a point with \"anchor\" is only half a claim: "
                        + "add \"near\" with the [x, y] it should have ended up at")
                }
                anchorAt = PlaytestAnchorClaim(index: Int(index), near: try f.point("near"),
                                               within: try f.optionalNumber("within") ?? 8)
            }
            let width = try f.optionalNumber("width")
            if let width, width < 0 {
                throw f.invalid("width", "a line's weight is zero or more, not \(width)")
            }
            let fill = try f.optionalString("fill")
            let ink = try f.optionalString("ink")
            for (field, value) in [("fill", fill), ("ink", ink)] {
                guard let value else { continue }
                guard Self.isPathColourClaim(value, allowingNone: field == "fill") else {
                    throw f.invalid(field, "a colour is a hex like \"#2D7FF9\""
                        + (field == "fill" ? ", or \"none\" for a path with no inside" : "")
                        + ", not \"\(value)\"")
                }
            }
            guard anchors != nil || closed != nil || curves != nil || smooth != nil
                    || halfSmooth != nil || rings != nil || width != nil || fill != nil
                    || ink != nil || picked != nil || anchorAt != nil else {
                throw f.invalid("anchors", "expectPath has to claim something about the path: "
                    + "\"anchors\" for how many points it has, \"closed\" for whether it joined "
                    + "back up, \"curves\" for how many of its runs are curved, \"smooth\" for "
                    + "how many of its points are smooth bends, \"halfSmooth\" for how many "
                    + "curve on one side only, \"rings\" for how many separate loops it is "
                    + "made of, \"picked\" for how many of its points are picked, "
                    + "\"width\" for the weight its "
                    + "line came out at, \"fill\" or \"ink\" for the colours it came out "
                    + "wearing, or \"anchor\" and \"near\" for "
                    + "where one point ended up")
            }
            for (field, value) in [("anchors", anchors), ("curves", curves), ("smooth", smooth),
                                   ("halfSmooth", halfSmooth), ("rings", rings),
                                   ("picked", picked)] {
                guard let value else { continue }
                guard value >= 0, value == value.rounded() else {
                    throw f.invalid(field, "a number of \(field) is a whole number, zero or more, not \(value)")
                }
            }
            self = .expectPath(layer: try f.optionalString("layer"),
                               anchors: anchors.map { Int($0) }, closed: closed,
                               curves: curves.map { Int($0) }, smooth: smooth.map { Int($0) },
                               halfSmooth: halfSmooth.map { Int($0) },
                               rings: rings.map { Int($0) },
                               width: width.map { CGFloat($0) }, fill: fill, ink: ink,
                               picked: picked.map { Int($0) },
                               anchorAt: anchorAt)
        case "expectLanding":
            let absent = try f.optionalFlag("absent") ?? false
            let near = fields["near"] == nil ? nil : try f.point("near")
            guard absent != (near != nil) else {
                throw f.invalid("near", "expectLanding claims one of two things: \"near\" with "
                    + "the [x, y] the mark should be sitting on, or \"absent\": true for no mark "
                    + "at all. It cannot claim both and it has to claim one")
            }
            let within = try f.optionalNumber("within") ?? 0.5
            guard within >= 0 else {
                throw f.invalid("within", "a distance is zero or more, not \(within)")
            }
            self = .expectLanding(near: near, within: CGFloat(within), absent: absent)
        case "expectChrome":
            let within = try f.optionalNumber("within") ?? 1
            guard within >= 0 else {
                throw f.invalid("within", "a distance on screen is zero or more, not \(within)")
            }
            self = .expectChrome(within: CGFloat(within))
        case "expectSharp":
            let absent = try f.optionalFlag("absent") ?? false
            let within = try f.optionalNumber("within") ?? 3
            guard within >= 0 else {
                throw f.invalid("within", "a number of seconds to wait is zero or more, not \(within)")
            }
            self = .expectSharp(absent: absent, within: within)
        case "expectMeasures":
            guard fields["count"] != nil else {
                throw f.invalid("count", "expectMeasures has to say how many measurements must be on the canvas; 0 means none should have landed")
            }
            let howMany = try f.number("count")
            guard howMany >= 0, howMany == howMany.rounded() else {
                throw f.invalid("count", "a count of measurements is a whole number, zero or more, not \(howMany)")
            }
            self = .expectMeasures(count: Int(howMany))
        case "expectSVG":
            let pictured: Int?
            if fields["pictured"] != nil {
                let howMany = try f.number("pictured")
                guard howMany >= 0, howMany == howMany.rounded() else {
                    throw f.invalid("pictured", "a count of layers that go out as pictures is a whole number, zero or more, not \(howMany)")
                }
                pictured = Int(howMany)
            } else {
                pictured = nil
            }
            let contains = fields["contains"] != nil ? try f.string("contains") : nil
            guard pictured != nil || contains != nil else {
                throw f.invalid("pictured", "expectSVG has to claim something: how many layers would go out as pictures, or a run of text the file must carry")
            }
            self = .expectSVG(pictured: pictured, contains: contains)
        case "expectWindows":
            let titled = try f.string("titled")
            guard fields["count"] != nil else {
                throw f.invalid("count", "expectWindows has to say how many windows with that title must be open; 1 is the usual claim and 0 says there should be none left")
            }
            let howMany = try f.number("count")
            guard howMany >= 0, howMany == howMany.rounded() else {
                throw f.invalid("count", "a count of windows is a whole number, zero or more, not \(howMany)")
            }
            self = .expectWindows(titled: titled, count: Int(howMany))
        case "expectRecording":
            func whole(_ key: String) throws -> Int? {
                guard fields[key] != nil else { return nil }
                let value = try f.number(key)
                guard value >= 0, value == value.rounded() else {
                    throw f.invalid(key, "\(key) is a whole number, zero or more, not \(value)")
                }
                return Int(value)
            }
            let pieces = try whole("pieces")
            let picked = try whole("picked")
            let keeps = try whole("keeps")
            let seconds = fields["seconds"] != nil ? try f.number("seconds") : nil
            let starts = fields["starts"] != nil ? try f.number("starts") : nil
            let caught = try f.optionalFlag("caught")
            let playhead = fields["playhead"] != nil ? try f.number("playhead") : nil
            guard pieces != nil || picked != nil || keeps != nil || seconds != nil
                || starts != nil || caught != nil || playhead != nil else {
                throw f.invalid("pieces", "expectRecording has to claim something about the "
                    + "recording: \"pieces\" for how many pieces it is in, \"picked\" for which "
                    + "one is picked (1-based, 0 for none), \"keeps\" for how many of them the "
                    + "trim window keeps, \"seconds\" for how long the window is, \"starts\" for "
                    + "where the start handle sits, \"caught\" for whether a handle is "
                    + "standing on a cut, or \"playhead\" for what second the playhead is on")
            }
            self = .expectRecording(pieces: pieces, picked: picked, keeps: keeps, seconds: seconds,
                                    starts: starts, caught: caught, playhead: playhead)
        case "expectStoredRecording":
            let seconds = fields["seconds"] != nil ? try f.number("seconds") : nil
            if let seconds, seconds < 0 {
                throw f.invalid("seconds", "a recording cannot be \(seconds) seconds long")
            }
            let within = fields["within"] != nil ? try f.number("within") : 0.3
            guard within >= 0 else {
                throw f.invalid("within", "how close the duration has to be is zero or more, not \(within)")
            }
            let original = try f.optionalFlag("original")
            guard seconds != nil || original != nil else {
                throw f.invalid("seconds", "expectStoredRecording has to claim something about the "
                    + "file on disk: \"seconds\" for how long the stored recording is now, or "
                    + "\"original\" for whether the untouched original is preserved beside it")
            }
            self = .expectStoredRecording(seconds: seconds, within: within, original: original)
        case "expectTutorialTracks":
            let with = try f.optionalStrings("with")
            let without = try f.optionalStrings("without")
            guard !with.isEmpty || !without.isEmpty else {
                throw f.invalid("without", "expectTutorialTracks has to claim something: \"with\" "
                    + "naming the shelves that must be on offer, \"without\" naming the ones that "
                    + "must not be, or both")
            }
            self = .expectTutorialTracks(with: with, without: without)
        case "expectFeet":
            let start = fields["start"] == nil ? nil : try f.point("start")
            let end = fields["end"] == nil ? nil : try f.point("end")
            let reads = try f.optionalString("reads")
            guard start != nil || end != nil || reads != nil else {
                throw f.invalid("start", "expectFeet has to claim something: \"start\" or "
                    + "\"end\" with the [x, y] a foot should have landed on, or \"reads\" with "
                    + "the label the measurement must be wearing")
            }
            let within = try f.optionalNumber("within") ?? 0.5
            guard within >= 0 else {
                throw f.invalid("within", "a distance is zero or more, not \(within)")
            }
            self = .expectFeet(layer: try f.optionalString("layer"), start: start, end: end,
                               reads: reads, within: CGFloat(within))
        case "expectBox":
            let layer = try f.string("layer")
            let at = fields["at"] == nil ? nil : try f.point("at")
            let size = fields["size"] == nil ? nil : try f.point("size")
            let onScreen = fields["onScreen"] == nil ? nil : try f.point("onScreen")
            var reachable = false
            if let raw = fields["reachable"] {
                guard let flag = raw as? Bool else {
                    throw f.invalid("reachable", "is true or false: true claims the layer's whole "
                        + "box is on the canvas, where the camera can be scrolled to see it")
                }
                guard flag else {
                    throw f.invalid("reachable", "only ever claims true. A walk saying a layer is "
                        + "out of reach is a walk asking for the bug to stay")
                }
                reachable = flag
            }
            var corner: LayerBoxCorner?
            if let raw = fields["corner"] {
                guard let text = raw as? String, let parsed = LayerBoxCorner(rawValue: text) else {
                    throw f.invalid("corner", "must be one of "
                        + LayerBoxCorner.words.joined(separator: ", "))
                }
                corner = parsed
            }
            guard at != nil || size != nil || onScreen != nil || reachable else {
                throw f.invalid("at", "expectBox has to claim something: \"at\" with the [x, y] "
                    + "the layer's own panel should read, \"size\" with the [w, h] it should be, "
                    + "\"corner\" and \"onScreen\" with where a corner must sit on screen, or "
                    + "\"reachable\": true to claim its whole box is on the canvas")
            }
            if corner != nil, onScreen == nil {
                throw f.invalid("onScreen", "naming a corner without saying where it should be "
                    + "claims nothing; add \"onScreen\": [x, y]")
            }
            if onScreen != nil, corner == nil {
                throw f.invalid("corner", "say WHICH corner has to be at that spot: one of "
                    + LayerBoxCorner.words.joined(separator: ", "))
            }
            let boxWithin = try f.optionalNumber("within") ?? 2
            guard boxWithin >= 0 else {
                throw f.invalid("within", "a distance is zero or more, not \(boxWithin)")
            }
            self = .expectBox(layer: layer, at: at, size: size, corner: corner,
                              onScreen: onScreen, reachable: reachable, within: CGFloat(boxWithin))
        case "expectField":
            let onScreen = fields["onScreen"] == nil ? nil : try f.point("onScreen")
            let degrees = try f.optionalNumber("degrees")
            guard onScreen != nil || degrees != nil else {
                throw f.invalid("onScreen", "expectField has to claim something: \"onScreen\" "
                    + "with the [x, y] the field's top left corner must sit at, \"degrees\" with "
                    + "how far it must lean, or both")
            }
            let fieldWithin = try f.optionalNumber("within") ?? 2
            guard fieldWithin >= 0 else {
                throw f.invalid("within", "a distance is zero or more, not \(fieldWithin)")
            }
            self = .expectField(onScreen: onScreen, degrees: degrees.map { CGFloat($0) },
                                within: CGFloat(fieldWithin))
        case "expectHint":
            let contains = try f.string("contains")
            guard !contains.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw f.invalid("contains", "expectHint has to say which words the chip must "
                    + "carry; an empty claim passes against every chip and against no chip")
            }
            self = .expectHint(contains: contains)
        case "expectCue":
            let says = try f.string("says")
            guard PlaytestScript.pointerCueNames.contains(says) else {
                throw f.invalid("says", "the canvas answers one of "
                    + PlaytestScript.pointerCueNames.joined(separator: ", ")
                    + "; \"\(says)\" is none of them")
            }
            self = .expectCue(says: says)
        case "expectClickReaches":
            let at = try f.point("at")
            let what = try f.optionalString("what") ?? PlaytestClickTaker.canvas.rawValue
            guard let taker = PlaytestClickTaker(rawValue: what) else {
                throw f.invalid("what", "a click reaches either the "
                    + PlaytestClickTaker.canvas.rawValue + " or the "
                    + PlaytestClickTaker.chrome.rawValue
                    + " floating over it; \"\(what)\" is neither")
            }
            self = .expectClickReaches(at, what: taker)
        case "expectToast":
            let says = try f.optionalString("says")
            let absent = try f.optionalFlag("absent")
            guard says != nil || absent != nil else {
                throw f.invalid("says", "expectToast has to claim something: \"says\" for words a "
                    + "toast in the bottom-right corner must be carrying, or \"absent\": true for "
                    + "no toast there at all")
            }
            if let says, says.trimmingCharacters(in: .whitespaces).isEmpty {
                throw f.invalid("says", "an empty claim passes against every toast and against no "
                    + "toast, so it claims nothing")
            }
            self = .expectToast(says: says, absent: absent)
        case "expectNotice":
            let says = try f.optionalString("says")
            let absent = try f.optionalFlag("absent")
            // Whether the pointer resting on the pill is holding its clock
            // open. The half of the pill a walk could not see until a walk's
            // pointer could be rested on anything at all (`PlaytestPointer`).
            let held = try f.optionalFlag("held")
            guard says != nil || absent != nil || held != nil else {
                throw f.invalid("says", "expectNotice has to claim something: \"says\" for words "
                    + "the pill under the canvas must be carrying, \"absent\": true for no "
                    + "pill at all, or \"held\" for whether the pointer resting on its button is "
                    + "holding it open")
            }
            if let says, says.trimmingCharacters(in: .whitespaces).isEmpty {
                throw f.invalid("says", "an empty claim passes against every pill and against no "
                    + "pill; name the words that matter")
            }
            if says != nil, absent == true {
                throw f.invalid("absent", "a pill that is not there cannot also be saying "
                    + "something; claim one or the other")
            }
            self = .expectNotice(says: says, absent: absent, held: held)
        case "expectRegion":
            let reads = try f.optionalString("reads")
            let present = fields["present"] as? Bool
            guard reads != nil || present != nil else {
                throw f.invalid("reads", "expectRegion has to claim something: "
                    + "\"reads\" for the outline's box, spelled the way the log spells it "
                    + "(\"400,300 200x100\"), or \"present\": false for no outline at all")
            }
            self = .expectRegion(reads: reads, present: present)
        case "expectLayers":
            let count = try f.optionalNumber("count")
            let atLeast = try f.optionalNumber("atLeast") ?? count
            let atMost = try f.optionalNumber("atMost") ?? count
            guard atLeast != nil || atMost != nil else {
                throw f.invalid("atLeast", "expectLayers has to claim something: "
                    + "\"count\" for an exact number of layers, or \"atLeast\" and \"atMost\" "
                    + "for the range a walk is willing to see")
            }
            for (field, value) in [("atLeast", atLeast), ("atMost", atMost)] {
                guard let value else { continue }
                guard value >= 0, value == value.rounded() else {
                    throw f.invalid(field, "a number of layers is a whole number, zero or more, not \(value)")
                }
            }
            if let atLeast, let atMost, atLeast > atMost {
                throw f.invalid("atLeast", "atLeast \(atLeast) is more than atMost \(atMost), "
                    + "so no number of layers could ever pass")
            }
            self = .expectLayers(atLeast: atLeast.map { Int($0) }, atMost: atMost.map { Int($0) })
        case "expectTimeline":
            let keyboard: PlaytestTimelineClaim.Keyboard?
            switch try f.optionalString("keyboard") {
            case nil: keyboard = nil
            case "timeline": keyboard = .timeline
            case "canvas": keyboard = .canvas
            case let other?:
                throw f.invalid("keyboard", "the keyboard is on the \"timeline\" or the \"canvas\", not \"\(other)\"")
            }
            let claim = PlaytestTimelineClaim(
                playheadMS: try f.optionalNumber("playheadMS").map { Int($0) },
                withinMS: Int(try f.optionalNumber("withinMS") ?? 0),
                keyboard: keyboard,
                rate: try f.optionalNumber("rate"),
                blade: fields["blade"] as? Bool,
                markInMS: try f.optionalNumber("markInMS").map { Int($0) },
                markOutMS: try f.optionalNumber("markOutMS").map { Int($0) },
                hasIn: fields["hasIn"] as? Bool,
                hasOut: fields["hasOut"] as? Bool,
                markers: try f.optionalNumber("markers").map { Int($0) })
            guard claim.claimsSomething else {
                throw f.invalid("playheadMS", "expectTimeline has to claim something: \"playheadMS\", "
                    + "\"keyboard\", \"rate\", \"blade\", \"markInMS\", \"markOutMS\", \"hasIn\", "
                    + "\"hasOut\" or \"markers\"")
            }
            self = .expectTimeline(claim)
        case "expectPlaybackNeverBlank":
            let seconds = try f.optionalNumber("seconds") ?? 3
            let moments = try f.optionalNumber("moments") ?? 20
            guard seconds > 0, seconds <= 30 else {
                throw f.invalid("seconds", "a playback is watched for more than nothing and "
                    + "at most 30 seconds, not \(seconds)")
            }
            guard moments >= 2, moments == moments.rounded() else {
                throw f.invalid("moments", "a playback is looked at a whole number of times, "
                    + "at least twice, not \(moments)")
            }
            self = .expectPlaybackNeverBlank(name: try f.string("name"), seconds: seconds,
                                             moments: Int(moments))
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
            let caretHeight: CaptionCaretHeight? = try word("caretHeight")
            let outline: CaptionOutlineClaim? = try word("outline")
            guard aligned != nil || caret != nil || caretHeight != nil || outline != nil else {
                throw f.invalid("caret", "an expectCaption has to claim something: \"aligned\", \"caret\", \"caretHeight\" or \"outline\". A step that claims nothing passes whatever the app does")
            }
            self = .expectCaption(aligned: aligned, caret: caret,
                                  caretHeight: caretHeight, outline: outline)
        case "expectSectionFits":
            self = .expectSectionFits(section: try f.string("section"))
        case "expectSections":
            let leading = try f.optionalStrings("leading")
            guard !leading.isEmpty else {
                throw f.invalid("leading", "expectSections has to name the sections the panel must start with, in order")
            }
            self = .expectSections(leading: leading)
        case "expectInView":
            self = .expectInView(field: try f.string("field"),
                                 whole: try f.optionalFlag("whole") ?? false)
        case "expectOneUnit":
            self = .expectOneUnit
        case "expectOneNumberPerName":
            self = .expectOneNumberPerName
        case "expectBuilds":
            guard fields["view"] != nil else {
                throw f.invalid("view", "expectBuilds has to name the view it is counting: editorBody, inspectorPanel, layersList, layersRow, layerThumbnail or colorRow")
            }
            guard fields["atMost"] != nil || fields["atLeast"] != nil else {
                throw f.invalid("atMost", "expectBuilds has to bound the count: \"atMost\": 0 is the usual one, and \"atLeast\": 1 is how a walk says the view really did build")
            }
            self = .expectBuilds(view: try f.string("view"),
                                 atMost: fields["atMost"] == nil
                                     ? nil : Int(try f.number("atMost")),
                                 atLeast: fields["atLeast"] == nil
                                     ? nil : Int(try f.number("atLeast")))
        case "expectListStill":
            self = .expectListStill(moved: try f.optionalFlag("moved") ?? false)
        case "expectEdited":
            self = .expectEdited(try f.optionalFlag("edited") ?? f.optionalFlag("is") ?? true)
        case "expectPicked":
            guard fields["layers"] != nil else {
                throw f.invalid("layers", "expectPicked has to say which layers must be picked, by name; an empty list means nothing should be")
            }
            self = .expectPicked(layers: try f.optionalStrings("layers"),
                                 outline: try f.optionalString("outline").map {
                                     guard let claim = PlaytestOutlineClaim(rawValue: $0) else {
                                         throw f.invalid("outline", "outline is \"drawn\" or \"none\"")
                                     }
                                     return claim
                                 })
        case "expectIconPreviews":
            let absent = try f.optionalFlag("absent") ?? false
            guard absent || fields["sides"] != nil else {
                throw f.invalid("sides", "expectIconPreviews has to say which sizes the strip must be showing, smallest first, or carry \"absent\": true to claim there is no strip at all")
            }
            self = .expectIconPreviews(sides: try f.optionalNumbers("sides").map { Int($0) },
                                       absent: absent)
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
        case "panelMargins":
            self = .panelMargins(stage: try f.string("stage"), reportOnly: try f.optionalFlag("report") ?? false)
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

        func has(_ field: String) -> Bool { fields[field] != nil }

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

        func optionalNumbers(_ field: String) throws -> [Double] {
            guard let raw = fields[field] else { return [] }
            guard let values = raw as? [NSNumber] else {
                throw invalid(field, "must be a list of numbers")
            }
            return values.map { $0.doubleValue }
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

extension PlaytestStep {
    /// Whether a colour a walk claimed is one the app could ever answer with:
    /// a hex the picker writes, or the word "none" where a missing colour is a
    /// real answer. A typo here is a walk that passes for the wrong reason, so
    /// it is refused when the script is read rather than at step time.
    static func isPathColourClaim(_ value: String, allowingNone: Bool) -> Bool {
        if allowingNone, value.caseInsensitiveCompare("none") == .orderedSame { return true }
        return RGBA(hex: value) != nil
    }
}


/// What an `expectTimeline` step claims. Every field is optional; at least one
/// is set.
public struct PlaytestTimelineClaim: Hashable, Sendable {
    public enum Keyboard: String, Hashable, Sendable { case timeline, canvas }

    public var playheadMS: Int?
    /// How far the playhead may be from `playheadMS`: nought, exactly there,
    /// unless the step says otherwise.
    public var withinMS: Int
    public var keyboard: Keyboard?
    /// How fast it is playing: nought stopped, 1 normal, negative backwards.
    public var rate: Double?
    /// The Blade in hand (true) or the Select arrow (false).
    public var blade: Bool?
    public var markInMS: Int?
    public var markOutMS: Int?
    public var hasIn: Bool?
    public var hasOut: Bool?
    public var markers: Int?

    public init(playheadMS: Int? = nil, withinMS: Int = 0, keyboard: Keyboard? = nil, rate: Double? = nil,
                blade: Bool? = nil, markInMS: Int? = nil, markOutMS: Int? = nil,
                hasIn: Bool? = nil, hasOut: Bool? = nil, markers: Int? = nil) {
        self.playheadMS = playheadMS
        self.withinMS = max(0, withinMS)
        self.keyboard = keyboard
        self.rate = rate
        self.blade = blade
        self.markInMS = markInMS
        self.markOutMS = markOutMS
        self.hasIn = hasIn
        self.hasOut = hasOut
        self.markers = markers
    }

    public var claimsSomething: Bool {
        playheadMS != nil || keyboard != nil || rate != nil || blade != nil || markInMS != nil
            || markOutMS != nil || hasIn != nil || hasOut != nil || markers != nil
    }
}
