import Foundation
import Testing

/// Every command a right-click or the panel offers is also a row of the menu
/// bar.
///
/// The placement contract's menu bar row (UX-PATTERNS.md): "Nothing missing: a
/// command reachable only from a bar or a right-click is a bug." Until
/// 2026-09-30 tracks, markers, sound cleanup, caption edits, keys, effects and
/// several clip commands could only be found by right-clicking the right thing
/// (`docs/design/ia-audit-2026-09-29.md`).
///
/// This reads both sides out of the source. The right-click side is every row a
/// right-click menu is built from: the `MenuRow` lists (`.command`, `.toggle`,
/// `.submenu`), the literal rows of every `.contextMenu`, and the track
/// header's menu; plus the panel's verbs, listed by hand below because a panel
/// button looks like any other button. The menu bar side is every literal a
/// `Button`, `Toggle` or `Menu` in `EditorCommands.swift` is titled with, and
/// the `MenuToggleNames` it uses.
///
/// A new right-click row fails here until the menu bar has a row for it. When
/// the bar says it in other words (the timeline's Delete is Clip ▸ Delete This
/// Piece), name the bar's row in `sameCommand`; when there truly is nothing in
/// hand for a menu bar row to act on, say why in `noRow`, which the audit
/// reads back to the user.
@Suite("Every right-click and panel command is also in the menu bar")
struct EveryCommandIsInTheMenuBarTests {

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
    }

    /// The panel's verbs: buttons in a section, not rows of a menu, so they are
    /// named here rather than read. Each is the button's own words.
    static let panelCommands = [
        "Normalize",                    // Sound: Gain
        "Clean Noise",                  // Sound: Noise
        "Reset Gain",                   // Sound: Gain
        "Stop Animating",               // Animating: a row's x
        "Add Effect",                   // Effects: the header's plus
        "Remove Effect",                // Effects: a row's x
        "Apply to Every Cut",           // Transitions: the header's plus
        "Set as Default Transition",    // Transitions: the header's plus
        "Reset Captions",               // Captions
        "Safe Areas",                   // Captions
    ]

    /// A right-click row the menu bar holds under other words: the right-click
    /// title, and the bar's row that does the same thing to the thing in hand.
    static let sameCommand: [String: String] = [
        // The timeline's Delete on a clip, a range or picked pieces is the
        // Clip menu's ⌫ row, which names what it will take.
        "Delete": "Delete This Piece",
        "Delete Key": "Delete Keys",
        // Edit's Copy and Paste take the keys picked on a lane before the
        // layer, the way Premiere's keyframe clipboard does.
        "Copy Key": "Copy",
        "Paste Keys": "Paste",
        "Duplicate": "Duplicate Layer",
        "Rename": "Rename Layer…",
        "Edit Words": "Rename…",
        "Add Transition": "Transition at Cut",
        "Remove Transition": "Hard Cut",
        "Timing": "Captions Later",
        "Earlier": "Captions Earlier",
        "Later": "Captions Later",
        "Export Subtitles": "Export Captions as SRT…",
        "Split Everything Here": "Split Everything at Playhead",
        "Clear Range": "Clear In and Out",
        "To the Box": "Punch In",
        "Reset": "Reset Reframe",
        "Straight": "Curve the Path",
        "Curved": "Curve the Path",
        "Go to Key": "Go to Next Key",
        "Add Key": "Key at Playhead",
        "Add Key Here": "Key at Playhead",
        "Remove Key": "Remove Key at Playhead",
        "Remove Key Here": "Remove Key at Playhead",
        // The motion list's Remove stops that property moving.
        "Remove": "Stop Animating",
        "Unmute Track": "Mute Track",
        "Show Track": "Hide Track",
        "Stop Soloing": "Solo Track",
        "Unlock Track": "Lock Track",
        "Safe Areas": "Caption Safe Areas",
        // An empty track's rows: a tool picked, or the clipboard, at the
        // playhead.
        "Add Rectangle": "Tools",
        "Add Text": "Tools",
        "Paste Here": "Paste",
        "Put Layer Here": "Put on Timeline",
        // A Library tile is a thing in the panel, not in the document; the bar
        // brings media in from a file.
        "Add at Playhead": "Import Media…",
    ]

    /// A right-click row with no menu bar row, and why.
    static let noRow: [String: String] = [
        "Delete Style": "a saved caption style is a tile in the Captions section, and nothing about the document says which one is in hand",
    ]

    // MARK: Reading the source

    private static func swiftFiles(under folder: String) -> [URL] {
        let base = root.appendingPathComponent(folder)
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The whole string literals in `text` with nothing interpolated into
    /// them, at least two characters long. A literal with `\(` in it is built
    /// at run time and is not a title this can check.
    private static func literals(in text: Substring) -> [String] {
        var found: [String] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "\"") {
            var cursor = text.index(after: open)
            var body = ""
            var built = false
            var depth = 0
            while cursor < text.endIndex {
                let character = text[cursor]
                if character == "\\" {
                    let next = text.index(after: cursor)
                    if next < text.endIndex, text[next] == "(" { built = true; depth += 1; cursor = text.index(after: next); continue }
                    body.append(character)
                    if next < text.endIndex { body.append(text[next]); cursor = text.index(after: next) } else { cursor = next }
                    continue
                }
                if depth > 0 {
                    if character == "(" { depth += 1 }
                    if character == ")" { depth -= 1 }
                    cursor = text.index(after: cursor)
                    continue
                }
                if character == "\"" { break }
                body.append(character)
                cursor = text.index(after: cursor)
            }
            if !built, body.count >= 2 { found.append(body) }
            guard cursor < text.endIndex else { break }
            index = text.index(after: cursor)
        }
        return found
    }

    /// The first argument of every call to `callee` in `text`: what a
    /// `Button`, `Toggle`, `Menu` or `MenuRow` is titled with, ternaries and
    /// all, and never a later argument.
    private static func firstArguments(of callee: String, in text: Substring) -> [Substring] {
        var found: [Substring] = []
        var from = text.startIndex
        while let range = text.range(of: callee + "(", range: from..<text.endIndex) {
            from = range.upperBound
            // `Button(` inside a longer name (`ToolModeButton(`) is not a Button.
            if range.lowerBound > text.startIndex {
                let before = text[text.index(before: range.lowerBound)]
                if before.isLetter || before.isNumber { continue }
            }
            var depth = 0
            var inString = false
            var cursor = range.upperBound
            while cursor < text.endIndex {
                let character = text[cursor]
                if inString {
                    if character == "\\" {
                        cursor = text.index(after: cursor)
                    } else if character == "\"" {
                        inString = false
                    }
                } else if character == "\"" {
                    inString = true
                } else if character == "(" || character == "[" {
                    depth += 1
                } else if character == ")" || character == "]" {
                    if depth == 0 { break }
                    depth -= 1
                } else if character == ",", depth == 0 {
                    break
                } else if character == "{", depth == 0 {
                    break
                }
                guard cursor < text.endIndex else { break }
                cursor = text.index(after: cursor)
            }
            found.append(text[range.upperBound..<min(cursor, text.endIndex)])
        }
        return found
    }

    /// The block a `{` at `open` starts, braces balanced.
    private static func block(in source: String, from open: String.Index) -> Substring {
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return source[open...index] }
            }
            index = source.index(after: index)
        }
        return source[open...]
    }

    /// The titles of every Button, Toggle and Menu in `text`.
    private static func controlTitles(in text: Substring) -> [String] {
        ["Button", "Toggle", "Menu"].flatMap { callee in
            firstArguments(of: callee, in: text).flatMap(literals(in:))
        }
    }

    /// Every right-click title, with where it came from.
    static func rightClickTitles() throws -> [String: Set<String>] {
        var found: [String: Set<String>] = [:]
        for file in swiftFiles(under: "Sources/Photonz")
        where !file.path.contains("/Playtest/") && file.lastPathComponent != "EditorCommands.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            for callee in [".command", ".toggle", ".submenu"] {
                for title in firstArguments(of: callee, in: source[...]).flatMap(literals(in:)) {
                    found[title, default: []].insert(name)
                }
            }
            var from = source.startIndex
            while let range = source.range(of: ".contextMenu {", range: from..<source.endIndex) {
                let open = source.index(before: range.upperBound)
                for title in controlTitles(in: block(in: source, from: open)) {
                    found[title, default: []].insert(name + " (right-click)")
                }
                from = range.upperBound
            }
            if let start = source.range(of: "struct TimelineTrackMenu: View {") {
                let open = source.index(before: start.upperBound)
                for title in controlTitles(in: block(in: source, from: open)) {
                    found[title, default: []].insert(name + " (track header)")
                }
            }
        }
        for title in panelCommands { found[title, default: []].insert("the panel") }
        return found
    }

    /// Every title a row of the menu bar can wear.
    static func menuBarTitles() throws -> Set<String> {
        let commands = try String(contentsOf: root.appendingPathComponent("Sources/Photonz/EditorCommands.swift"),
                                  encoding: .utf8)
        var titles = Set(controlTitles(in: commands[...]))
        let names = try String(contentsOf: root.appendingPathComponent("Sources/PhotonzCore/MenuToggleNames.swift"),
                               encoding: .utf8)
        var constants: [String: String] = [:]
        for match in names.matches(of: /static let (\w+) = "([^"]+)"/) {
            constants[String(match.output.1)] = String(match.output.2)
        }
        for match in commands.matches(of: /MenuToggleNames\.(\w+)/) {
            if let title = constants[String(match.output.1)] { titles.insert(title) }
        }
        return titles
    }

    // MARK: The checks

    @Test("Every right-click and panel command has a menu bar row")
    func everyCommandHasARow() throws {
        let bar = try Self.menuBarTitles()
        let offered = try Self.rightClickTitles()
        #expect(offered.count > 60, "the source reader found only \(offered.count) right-click titles")
        for (title, sources) in offered.sorted(by: { $0.key < $1.key }) {
            if bar.contains(title) || Self.noRow[title] != nil { continue }
            if let other = Self.sameCommand[title] {
                #expect(bar.contains(other),
                        "\"\(title)\" is said to be the menu bar's \"\(other)\", and no row of the menu bar is called that")
                continue
            }
            Issue.record("""
                "\(title)" (\(sources.sorted().joined(separator: ", "))) has no row in the menu bar. \
                Add one to EditorCommands.swift, or name the row that does the same in sameCommand.
                """)
        }
    }

    @Test("Every word in the lists above is still offered, so the lists cannot go stale")
    func listsAreLive() throws {
        let offered = try Self.rightClickTitles()
        for title in Array(Self.sameCommand.keys) + Array(Self.noRow.keys) {
            #expect(offered[title] != nil, "\"\(title)\" is no longer offered anywhere; take it off the list")
        }
    }

    @Test("The track header's commands each have their own row, not an alias")
    func tracksHaveRows() throws {
        let bar = try Self.menuBarTitles()
        for title in ["Add Video Track", "Add Audio Track", "Add Captions Track", "Add Track Above",
                      "Add Track Below", "Rename Track…", "Mute Track", "Hide Track", "Solo Track",
                      "Lock Track", "Group Track", "Ungroup Tracks", "Delete Track", "Delete Empty Tracks"] {
            #expect(bar.contains(title), "no menu bar row called \"\(title)\"")
        }
    }
}
