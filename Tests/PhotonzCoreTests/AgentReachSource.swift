import Foundation
import PhotonzCore

/// Reads the app's own source for what a person can click in the panel and in
/// every right-click menu, for `AgentReachTests`.
///
/// A source reader rather than a registry in Core, chosen 2026-11-10: the
/// panel is about fifty sections drawn by some ninety SwiftUI files, and a
/// registry the app did not draw from would be one more list to forget. This
/// reads what is drawn, so a new control is counted the day it is written.
enum AgentReachSource {

    static var root: URL { EveryCommandIsInTheMenuBarTests.root }

    // MARK: Characters

    /// The file with every comment blanked to spaces, so a word in a comment
    /// is never read as a control, and every offset still matches the file.
    static func code(_ path: String) throws -> [Character] {
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        var s = Array(text)
        var i = 0
        while i < s.count {
            if s[i] == "\"" {
                if i + 2 < s.count, s[i + 1] == "\"", s[i + 2] == "\"" {
                    // A multi-line string: to its closing three quotes.
                    var j = i + 3
                    while j + 2 < s.count, !(s[j] == "\"" && s[j + 1] == "\"" && s[j + 2] == "\"") { j += 1 }
                    i = j + 3
                    continue
                }
                i = skipString(s, i) + 1
                continue
            }
            if s[i] == "/", i + 1 < s.count, s[i + 1] == "/" {
                while i < s.count, s[i] != "\n" { s[i] = " "; i += 1 }
                continue
            }
            if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" {
                while i + 1 < s.count, !(s[i] == "*" && s[i + 1] == "/") {
                    if s[i] != "\n" { s[i] = " " }
                    i += 1
                }
                if i + 1 < s.count { s[i] = " "; s[i + 1] = " " }
                i += 2
                continue
            }
            i += 1
        }
        return s
    }

    /// The index of the quote that closes the string opened at `i`, stepping
    /// over `\(...)` interpolations whole.
    static func skipString(_ s: [Character], _ i: Int) -> Int {
        var i = i + 1
        while i < s.count {
            if s[i] == "\\" {
                if i + 1 < s.count, s[i + 1] == "(" {
                    i = close(s, from: i + 1, "(", ")") + 1
                    continue
                }
                i += 2
                continue
            }
            if s[i] == "\"" || s[i] == "\n" { return i }
            i += 1
        }
        return i
    }

    /// The index of the bracket that closes the one at `open`.
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

    /// The first argument inside the parentheses opening at `open`, up to the
    /// first comma at its own depth.
    static func firstArgument(_ s: [Character], open: Int) -> String {
        let end = close(s, from: open, "(", ")")
        var depth = 0, j = open + 1
        while j < end {
            let ch = s[j]
            if ch == "\"" { j = skipString(s, j) } else if "([{".contains(ch) { depth += 1 } else if ")]}".contains(ch) {
                depth -= 1
            } else if ch == ",", depth == 0 { return collapsed(String(s[(open + 1)..<j])) }
            j += 1
        }
        return collapsed(String(s[(open + 1)..<max(open + 1, end)]))
    }

    /// The literal a whole argument is, when it is one string with nothing
    /// built into it: `"Gain"`, not `"Part \(n)"` or `label`.
    static func plainLiteral(_ argument: String) -> String? {
        guard argument.count >= 2, argument.first == "\"", argument.last == "\"" else { return nil }
        let body = argument.dropFirst().dropLast()
        if body.contains("\"") || body.isEmpty { return nil }
        return String(body)
    }

    /// The literal an argument is, interpolations kept as written: `"Part
    /// \(row) Direction"`. Nil for anything that is not one string.
    static func writtenLiteral(_ argument: String) -> String? {
        guard argument.count >= 3, argument.first == "\"", argument.last == "\"" else { return nil }
        let s = Array(argument)
        return skipString(s, 0) == s.count - 1 ? String(argument.dropFirst().dropLast()) : nil
    }

    /// Where each member a type declares starts, at four spaces or none: the
    /// `func`, `var` or `struct` a control is drawn in.
    static func members(_ s: [Character]) -> [(at: Int, name: String)] {
        var found: [(Int, String)] = []
        var start = 0
        while start < s.count {
            var end = start
            while end < s.count, s[end] != "\n" { end += 1 }
            // Cheap first: four spaces or none, then a letter or `@`.
            var lead = start
            while lead < end, s[lead] == " " { lead += 1 }
            guard lead - start == 0 || lead - start == 4, lead < end, s[lead].isLetter || s[lead] == "@" else {
                start = end + 1
                continue
            }
            let line = String(s[start..<end])
            if let match = line.firstMatch(
                of: /^(?:    )?(?:@\w+(?:\([^)]*\))? )*(?:(?:private|fileprivate|static|public|nonisolated|mutating|override|final)\s+)*(?:func|var|struct|enum|class|extension)\s+([\w.]+)/) {
                found.append((start, String(match.output.1)))
            }
            start = end + 1
        }
        return found
    }

    static func member(at offset: Int, in members: [(at: Int, name: String)]) -> String {
        members.last { $0.at < offset }?.name ?? "?"
    }

    static func lineNumber(_ s: [Character], _ offset: Int) -> Int {
        var count = 1
        for i in 0..<min(offset, s.count) where s[i] == "\n" { count += 1 }
        return count
    }

    /// Every use of one of `names` (`Slider`, `VideoKit.DropdownRow`) that
    /// opens a call or a trailing closure, never a longer name or a
    /// declaration: (where, which name, where its `(` or `{` is).
    static func calls(of names: Set<String>, in s: [Character]) -> [(at: Int, name: String, open: Int)] {
        var found: [(Int, String, Int)] = []
        var i = 0
        while i < s.count {
            let ch = s[i]
            if ch == "\"" { i = skipString(s, i) + 1; continue }
            guard ch.isLetter else { i += 1; continue }
            let before: Character = i > 0 ? s[i - 1] : " "
            var j = i
            while j < s.count, s[j].isLetter || s[j].isNumber || s[j] == "_" || (s[j] == "." && j + 1 < s.count && s[j + 1].isUppercase) {
                j += 1
            }
            let name = String(s[i..<j])
            if before.isLetter || before.isNumber || before == "_" || before == "." || !names.contains(name) {
                i = j
                continue
            }
            let lead = String(s[max(0, i - 10)..<i])
            if lead.hasSuffix("struct ") || lead.hasSuffix("extension ") || lead.hasSuffix("class ") { i = j; continue }
            var k = j
            while k < s.count, s[k] == " " { k += 1 }
            if k < s.count, s[k] == "(" || s[k] == "{" {
                found.append((i, name, k))
            }
            i = j
        }
        return found
    }

    /// The end of a call opening at `open`, its trailing closures included
    /// (`label: {...}` ones too).
    static func callEnd(_ s: [Character], open: Int) -> Int {
        var end = s[open] == "(" ? close(s, from: open, "(", ")") : close(s, from: open, "{", "}")
        while true {
            var k = end + 1
            while k < s.count, " \t\n".contains(s[k]) { k += 1 }
            if k < s.count, s[k] == "{" { end = close(s, from: k, "{", "}"); continue }
            // `label: {`, `minimumValueLabel: {`
            var l = k
            while l < s.count, s[l].isLetter { l += 1 }
            if l > k, l < s.count, s[l] == ":" {
                var m = l + 1
                while m < s.count, s[m] == " " { m += 1 }
                if m < s.count, s[m] == "{" { end = close(s, from: m, "{", "}"); continue }
            }
            return end
        }
    }

    /// The modifiers chained after `end`: their names and first arguments.
    static func modifiers(_ s: [Character], after end: Int) -> [(name: String, first: String)] {
        var found: [(String, String)] = []
        var k = end + 1
        while true {
            var j = k
            while j < s.count, " \t\n".contains(s[j]) { j += 1 }
            guard j < s.count, s[j] == "." else { return found }
            var n = j + 1
            while n < s.count, s[n].isLetter || s[n].isNumber || s[n] == "_" { n += 1 }
            let name = String(s[(j + 1)..<n])
            if name.isEmpty { return found }
            if n < s.count, s[n] == "(" {
                found.append((name, firstArgument(s, open: n)))
                k = close(s, from: n, "(", ")") + 1
            } else if n < s.count, s[n] == " " || s[n] == "{" {
                var m = n
                while m < s.count, s[m] == " " { m += 1 }
                if m < s.count, s[m] == "{" {
                    found.append((name, ""))
                    k = close(s, from: m, "{", "}") + 1
                } else {
                    found.append((name, ""))
                    k = n
                }
            } else {
                found.append((name, ""))
                k = n
            }
        }
    }

    // MARK: The panel

    /// The SwiftUI controls a person sets or presses.
    static let systemControls: Set<String> = [
        "Slider", "Toggle", "Picker", "Stepper", "Button", "Menu", "ColorPicker", "TextField", "SecureField",
    ]

    /// The app's own panel controls: each use is one setting, so the controls
    /// inside their own definitions are not counted again.
    static let appControls: Set<String> = [
        "VideoKit.DropdownRow", "VideoKit.ListDropdown", "VideoKit.HeaderMenu", "PanelNumberField",
        "LayerStyleSlider", "CurveRow", "ShapeSlider", "ColorWellButton", "CaptionColourWellRow",
        "MotionSettingRow", "SelectionMenu", "MotionNumberField", "ChannelSwitch", "SoundEffectSlider",
        "SpaceValueRow", "EffectChoiceRow", "KeyDiamondButton", "SegmentedControl", "FourSidedButton",
    ]

    /// The rows that put a label beside a control: a control inside one is
    /// known by the row's label, so a slider and the box beside it that set
    /// the same value are one setting.
    static let labelledRows: Set<String> = ["VideoKit.FieldRow", "PanelFieldRow", "LabeledContent"]

    /// The files that draw the panel: the ones the copy budget reads
    /// (`PanelCopyBudgetTests.isPanelFile`), and the files outside that naming
    /// whose views a section draws controls from.
    static let panelExtras = [
        "LayersListView.swift", "MeasurementsListView.swift", "BrushChooser.swift", "TransitionsGroup.swift",
        "LibraryTitleTile.swift", "LibraryCatalogTiles.swift", "AddKeyControl.swift", "ArrowStyleTiles.swift",
        "BrushSettingControls.swift", "CanvasGridSettingsView.swift", "ChipStyleTiles.swift",
        "ClickEffectRows.swift", "ColorGradeEffectRows.swift", "EffectsListRow.swift",
        "LayersPanelHeaderControls.swift", "LibraryColorDrop.swift", "TitleBackgroundPicker.swift",
    ]

    static var panelFiles: [String] {
        (PanelCopyBudgetTests.panelFiles + panelExtras).sorted()
    }

    /// One control drawn in the panel, known by the words a person reads
    /// beside it.
    struct Control: Hashable {
        let file: String
        /// `Gain`, or `fadeRow: label` when the words are only known at run
        /// time.
        let label: String
        let line: Int
        var key: String { "\(file) › \(label)" }
    }

    static func panelControls() throws -> [Control] {
        var found: [Control] = []
        for file in panelFiles {
            var s = try code("Sources/Photonz/" + file)
            // A right-click menu in the panel is a menu, counted with the
            // menus.
            for menu in contextMenus(in: s) {
                for i in menu.open...menu.end where s[i] != "\n" { s[i] = " " }
            }
            let members = members(s)
            // The app's own controls' own insides.
            var inside: [ClosedRange<Int>] = []
            for definition in definitions(of: appControls, in: s) { inside.append(definition) }
            let rows: [(range: ClosedRange<Int>, label: String?)] = calls(of: labelledRows, in: s).map { row in
                let end = callEnd(s, open: row.open)
                var label: String?
                if s[row.open] == "(" {
                    let first = firstArgument(s, open: row.open)
                    let bare = first.hasPrefix("label:") ? collapsed(first.dropFirst(6)) : first
                    label = writtenLiteral(bare).flatMap { $0.isEmpty ? nil : $0 }
                }
                return (row.at...end, label)
            }
            for call in calls(of: systemControls.union(appControls), in: s) {
                if inside.contains(where: { $0.contains(call.at) }) { continue }
                let end = callEnd(s, open: call.open)
                let whole = String(s[call.at...end])
                var own: String?
                // The walk's own name for it, then the words it is titled with.
                for modifier in modifiers(s, after: end)
                where modifier.name == "playtestControl" || modifier.name == "playtestField" {
                    own = own ?? writtenLiteral(modifier.first)
                }
                var first = ""
                if s[call.open] == "(" {
                    first = firstArgument(s, open: call.open)
                    if own == nil, let named = whole.firstMatch(of: /(?:label|title|name): *("(?:[^"\\]|\\.)*")/) {
                        own = writtenLiteral(String(named.output.1))
                    }
                    if own == nil { own = writtenLiteral(first).flatMap { $0.isEmpty ? nil : $0 } }
                }
                if own == nil, ["Button", "Toggle", "Menu"].contains(call.name),
                   let text = whole.firstMatch(of: /(?:Text|Label)\(("(?:[^"\\]|\\.)*")/) {
                    own = writtenLiteral(String(text.output.1))
                }
                let row = rows.last { $0.range.contains(call.at) && $0.label != nil }?.label
                let label = row ?? own
                    ?? "\(member(at: call.at, in: members)): \(call.name)(\(String(first.prefix(48))))"
                found.append(Control(file: file, label: label, line: lineNumber(s, call.at)))
            }
        }
        return found
    }

    /// Where each of `names` is declared in `s`: `struct Name ... { ... }`.
    static func definitions(of names: Set<String>, in s: [Character]) -> [ClosedRange<Int>] {
        var found: [ClosedRange<Int>] = []
        let text = String(s)
        for match in text.matches(of: /struct (\w+)/) where names.contains(String(match.output.1))
            || names.contains("VideoKit." + match.output.1) {
            let at = text.distance(from: text.startIndex, to: match.range.lowerBound)
            var open = at
            while open < s.count, s[open] != "{" { open += 1 }
            found.append(at...close(s, from: open, "{", "}"))
        }
        return found
    }

    // MARK: Right-click menus

    /// Every `.contextMenu { ... }` in `s`: where it is and its braces.
    static func contextMenus(in s: [Character]) -> [(at: Int, open: Int, end: Int)] {
        var found: [(Int, Int, Int)] = []
        let needle = Array(".contextMenu")
        var i = 0
        while i + needle.count < s.count {
            if s[i] == "\"" { i = skipString(s, i) + 1; continue }
            if s[i] == ".", Array(s[i..<(i + needle.count)]) == needle {
                var k = i + needle.count
                while k < s.count, s[k] == " " { k += 1 }
                if k < s.count, s[k] == "{" {
                    let end = close(s, from: k, "{", "}")
                    found.append((i, k, end))
                    i = end
                    continue
                }
            }
            i += 1
        }
        return found
    }

    /// One row of a right-click menu, as written: its title's words or
    /// expression, and the menu it is in.
    struct MenuRowRef: Hashable {
        /// `File › member`: the function the rows are built in, or the view
        /// whose `.contextMenu` draws them.
        let menu: String
        /// The title as written: `"Delete"`, `MenuToggleNames.layerLocked`.
        let title: String
        let line: Int
    }

    /// Every row a right-click menu is built from: the `MenuRow` lists
    /// (`.command`, `.toggle`, `.submenu`), the rows written straight into a
    /// `.contextMenu`, and the track header's menu.
    static func rightClickRows() throws -> [MenuRowRef] {
        var found: [MenuRowRef] = []
        let base = root.appendingPathComponent("Sources/Photonz")
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        let files = walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && !$0.path.contains("/Playtest/") }
        for url in files.sorted(by: { $0.path < $1.path }) {
            let file = url.lastPathComponent
            // The menu bar has its own count; MenuRow.swift is the row type.
            if file == "EditorCommands.swift" || file == "MenuRow.swift" { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let raw = try String(contentsOf: url, encoding: .utf8)
            guard raw.contains(".command(") || raw.contains(".toggle(") || raw.contains(".submenu(")
                    || raw.contains(".contextMenu") else { continue }
            let s = try code(relative)
            let members = members(s)
            // MenuRow lists.
            var i = 0
            while i < s.count {
                if s[i] == "\"" { i = skipString(s, i) + 1; continue }
                if s[i] == ".", i > 0, !(s[i - 1].isLetter || s[i - 1].isNumber || s[i - 1] == "_" || s[i - 1] == ")") {
                    for callee in ["command(", "toggle(", "submenu("] {
                        let word = Array(callee)
                        guard i + 1 + word.count <= s.count, Array(s[(i + 1)..<(i + 1 + word.count)]) == word else { continue }
                        let open = i + word.count
                        let first = firstArgument(s, open: open)
                        // `.command("k")` is a key, not a row.
                        if first.isEmpty || (first.count == 3 && first.first == "\"") { continue }
                        // `.submenu` and `.toggle` named a row's kind in a
                        // pattern, not a row.
                        if first.hasPrefix("let ") || first.hasPrefix("_") || first.hasPrefix("isOn:") { continue }
                        found.append(MenuRowRef(menu: "\(file) › \(member(at: i, in: members))",
                                                title: first, line: lineNumber(s, i)))
                    }
                }
                i += 1
            }
            // Rows written into a `.contextMenu`.
            let rowCalls = calls(of: ["Button", "Toggle", "Menu"], in: s)
            for menu in contextMenus(in: s) {
                let key = "\(file) › \(member(at: menu.at, in: members)) (right-click)"
                for call in rowCalls where call.at > menu.open && call.at < menu.end {
                    if s[call.open] == "(" {
                        found.append(MenuRowRef(menu: key, title: firstArgument(s, open: call.open),
                                                line: lineNumber(s, call.at)))
                    }
                }
            }
            // The track header's menu, a view of its own.
            if file == "TimelineTrackRows.swift",
               let start = String(s).range(of: "struct TimelineTrackMenu: View {") {
                let text = String(s)
                let at = text.distance(from: text.startIndex, to: start.upperBound) - 1
                let end = close(s, from: at, "{", "}")
                for call in rowCalls where call.at > at && call.at < end {
                    if s[call.open] == "(" {
                        found.append(MenuRowRef(menu: "\(file) › TimelineTrackMenu",
                                                title: firstArgument(s, open: call.open),
                                                line: lineNumber(s, call.at)))
                    }
                }
            }
        }
        return found
    }

    /// The `MenuToggleNames` constants, by name.
    static func toggleNames() throws -> [String: String] {
        let names = try String(contentsOf: root.appendingPathComponent("Sources/PhotonzCore/MenuToggleNames.swift"),
                               encoding: .utf8)
        var constants: [String: String] = [:]
        for match in names.matches(of: /static let (\w+) = "([^"]+)"/) {
            constants[String(match.output.1)] = String(match.output.2)
        }
        return constants
    }
}
