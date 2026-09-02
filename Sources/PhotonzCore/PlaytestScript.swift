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
/// what a person reads off the image) or the canvas view's points.
public enum PlaytestSpace: String, Hashable, Codable, Sendable {
    case document, view
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
public enum PlaytestAction: String, CaseIterable, Hashable, Codable, Sendable {
    case copySpecList, copyImage, hideAllMeasurements, showAllMeasurements
    case hideInspector, showInspector, zoomIn, zoomOut, zoomToFit
    /// Undo and redo are menu chords too, so a walk that checks an undo step
    /// asks for it here.
    case undo, redo
}

public enum PlaytestStep: Sendable, Equatable {
    /// Open a file in an editor window and wait until it is ready to drive.
    /// The window is kept invisible; `size` sets its frame first.
    case open(file: String, size: CGSize?)
    case wait(seconds: Double)
    /// Press and release a key, through the window (or the app, for chords so
    /// menu shortcuts are found).
    case key(PlaytestKey, [PlaytestModifier])
    case move(PlaytestPoint)
    case click(PlaytestPoint, count: Int, modifiers: [PlaytestModifier])
    case drag(from: PlaytestPoint, to: PlaytestPoint, steps: Int)
    /// Insert text into whatever field has the keyboard.
    case type(String)
    /// Pick a tool directly, for when its key was not honoured.
    case tool(Tool)
    /// Press I until the Measure tool is in this mode.
    case measureMode(MeasureToolMode)
    case waitFor(PlaytestCondition, timeout: Double)
    /// Render the window's content offscreen to `<out>/<name>.png`.
    case snapshot(name: String)
    /// Composite the document itself to `<out>/<name>.png`.
    case render(name: String)
    /// Write the editor's state (tool, mode, layers, hint, clipboard note) to
    /// the log under `stage`.
    case describe(stage: String, note: String?)
    case clearClipboard
    /// Log what is on the clipboard.
    case readClipboard(stage: String)
    case action(PlaytestAction)

    public static let defaultTimeout: Double = 10
    public static let defaultDragSteps = 8

    /// Every step name, sorted, as the error text and the doc list them.
    public static let names: [String] = [
        "action", "clearClipboard", "click", "describe", "drag", "key", "measureMode", "move",
        "open", "readClipboard", "render", "snapshot", "tool", "type", "wait", "waitFor",
    ]

    /// The `do` name this step answers to.
    public var name: String {
        switch self {
        case .open: "open"
        case .wait: "wait"
        case .key: "key"
        case .move: "move"
        case .click: "click"
        case .drag: "drag"
        case .type: "type"
        case .tool: "tool"
        case .measureMode: "measureMode"
        case .waitFor: "waitFor"
        case .snapshot: "snapshot"
        case .render: "render"
        case .describe: "describe"
        case .clearClipboard: "clearClipboard"
        case .readClipboard: "readClipboard"
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
        case "wait":
            self = .wait(seconds: try f.number("seconds"))
        case "key":
            let keyName = try f.string("key")
            guard let key = PlaytestKey(keyName) else {
                throw f.invalid("key", "\"\(keyName)\" is not a key; use a single character or return, escape, tab, space, delete, left, right, up, down")
            }
            self = .key(key, try f.modifiers())
        case "move":
            self = .move(try f.point("at"))
        case "click":
            let count = try f.optionalNumber("count").map { Int($0) } ?? 1
            self = .click(try f.point("at"), count: max(1, count), modifiers: try f.modifiers())
        case "drag":
            let steps = try f.optionalNumber("steps").map { Int($0) } ?? Self.defaultDragSteps
            self = .drag(from: try f.point("from"), to: try f.point("to"), steps: max(1, steps))
        case "type":
            self = .type(try f.string("text"))
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
            self = .snapshot(name: try f.string("name"))
        case "render":
            self = .render(name: try f.string("name"))
        case "describe":
            self = .describe(stage: try f.string("stage"), note: fields["note"] as? String)
        case "clearClipboard":
            self = .clearClipboard
        case "readClipboard":
            self = .readClipboard(stage: try f.string("stage"))
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

        func number(_ field: String) throws -> Double {
            guard let value = try optionalNumber(field) else { throw invalid(field, "must be a number") }
            return value
        }

        func optionalNumber(_ field: String) throws -> Double? {
            guard let raw = fields[field] else { return nil }
            guard let value = raw as? NSNumber else { throw invalid(field, "must be a number") }
            return value.doubleValue
        }

        func point(_ field: String) throws -> PlaytestPoint {
            guard let pair = fields[field] as? [NSNumber], pair.count == 2 else {
                throw invalid(field, "must be a pair of numbers, [x, y]")
            }
            let space: PlaytestSpace
            if let rawSpace = fields["space"] {
                guard let text = rawSpace as? String, let parsed = PlaytestSpace(rawValue: text) else {
                    throw invalid("space", "must be document or view")
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
