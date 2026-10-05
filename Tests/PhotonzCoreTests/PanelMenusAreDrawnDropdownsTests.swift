import Foundation
import Testing

/// Every menu in the right hand panel wears the panel's own dropdown.
///
/// The panel's menus were moved onto `VideoKit.Dropdown` one section at a time:
/// the Time section first, then Text on 2026-10-05, then Appearance and Effects
/// the same day. Each pass found a section the last one had not reached, still
/// drawing the system pop-up (up and down arrows on a narrower grey box) right
/// under one drawn as the panel's dropdown, so the panel read as two apps. This
/// reads the panel's source and fails on a system pop-up, so the next menu
/// added to the panel cannot drift back.
///
/// A system pop-up is `.pickerStyle(.menu)`, or a `Picker` given no style at
/// all, which on the Mac is the same thing. A picker drawn as a segmented
/// control, inline or as radio buttons is something else and passes. So is a
/// button drawing the pop-up's up and down arrows by hand, which is what
/// Blending and Masked by wore until 2026-10-05: a list that opens in a
/// popover wears the dropdown's face too (`VideoKit.ListDropdown`).
@Suite("The panel's menus are drawn as the panel's dropdown")
struct PanelMenusAreDrawnDropdownsTests {

    private static var app: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Sources/Photonz")
    }

    /// Files that are not the panel: dialogs, sheets, the canvas capsule and
    /// popovers that sit over the canvas. Everything else under
    /// `Sources/Photonz` is held to the rule, so a new panel file is too.
    static let notThePanel: Set<String> = [
        "ExportDialog.swift",
        "ExperimentsDialog.swift",
        "SaveTitlePresetDialog.swift",
        "CanvasGridSettingsView.swift",
        // The text tool's popover over the canvas, not the panel.
        "EditorView.swift",
        // The tool settings capsule floating over the canvas.
        "ToolSettingsCapsule.swift",
        "RecordingSetupController.swift",
        // The kit's own fallback for a bar too narrow for its words.
        "SegmentedControl.swift",
    ]

    /// Panel menus still drawn as system pop-ups on 2026-10-05, by file, and
    /// how many. This list may only shrink: converting one means lowering its
    /// count here, and the test says so when a count is higher than the file.
    /// Converting them is the task "The tool, lens, text style and component
    /// menus in the panel wear the panel's dropdown".
    static let stillSystemPopUps: [String: Int] = [
        // The measure tool's Mode, Snap and Show, and the crop tool's Aspect.
        "ToolInspectors.swift": 4,
        // A lens layer's Does, and the lens tool's.
        "LensInspector.swift": 2,
        // A Library text style's Font, Size and Weight.
        "TextStylePanel.swift": 3,
        // A component's property menus.
        "ComponentPanel.swift": 3,
    ]

    /// Every system pop-up in one file's text, as the line it starts on.
    static func systemPopUps(in text: String) -> [Int] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var found: [Int] = []
        var pickers: [Int] = []
        for (index, line) in lines.enumerated() {
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//") else { continue }
            if startsAPicker(line) { pickers.append(index) }
            if line.contains(".pickerStyle(.menu)") || line.contains(".pickerStyle(MenuPickerStyle())")
                || line.contains("\"chevron.up.chevron.down\"") {
                found.append(index + 1)
            }
        }
        // A picker with no style of its own is a pop-up. Its style, if it has
        // one, comes before the next picker and within a screenful of it.
        for (order, start) in pickers.enumerated() {
            let next = order + 1 < pickers.count ? pickers[order + 1] : lines.count
            let end = min(next, start + 40, lines.count)
            let body = lines[start..<end].joined(separator: "\n")
            if !body.contains(".pickerStyle(") { found.append(start + 1) }
        }
        return found.sorted()
    }

    /// `Picker(` on its own, not `ColorPicker(` or `TransitionPicker(`.
    static func startsAPicker(_ line: String) -> Bool {
        line.range(of: #"(^|[^A-Za-z0-9_])Picker\("#, options: .regularExpression) != nil
    }

    static func panelFiles() throws -> [(name: String, text: String)] {
        guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [(String, String)] = []
        for case let file as URL in walk where file.pathExtension == "swift" {
            let name = file.lastPathComponent
            guard !notThePanel.contains(name), !file.path.contains("/VideoKit/"),
                  !file.path.contains("/Playtest/") else { continue }
            files.append((name, try String(contentsOf: file, encoding: .utf8)))
        }
        return files
    }

    @Test("A bare Picker, a menu-style Picker and hand-drawn pop-up arrows all read as system pop-ups")
    func scannerSeesBoth() {
        let bare = """
            Picker("Kind", selection: $kind) {
                Text("A").tag(1)
            }
            .labelsHidden()
            """
        let menu = """
            Picker("Kind", selection: $kind) { Text("A").tag(1) }
                .pickerStyle(.menu)
            """
        let segmented = """
            Picker("Kind", selection: $kind) { Text("A").tag(1) }
                .pickerStyle(.segmented)
            """
        let handDrawn = """
            Image(systemName: "chevron.up.chevron.down")
            """
        let others = """
            ColorPicker("Fill", selection: $color)
            TransitionPicker(place: place)
            // Picker("Old", selection: $x)
            """
        #expect(Self.systemPopUps(in: bare) == [1])
        #expect(!Self.systemPopUps(in: menu).isEmpty)
        #expect(Self.systemPopUps(in: segmented).isEmpty)
        #expect(Self.systemPopUps(in: handDrawn) == [1])
        #expect(Self.systemPopUps(in: others).isEmpty)
    }

    @Test("No menu in the panel is drawn as a system pop-up")
    func noSystemPopUps() throws {
        let files = try Self.panelFiles()
        #expect(files.count > 50, "found only \(files.count) panel files; the scan is broken")
        var offenders: [String] = []
        var stale: [String] = []
        for file in files {
            let lines = Self.systemPopUps(in: file.text)
            let allowed = Self.stillSystemPopUps[file.name] ?? 0
            if lines.count > allowed {
                offenders.append("\(file.name) at line \(lines.map(String.init).joined(separator: ", "))")
            } else if lines.count < allowed {
                stale.append("\(file.name): \(lines.count), not \(allowed)")
            }
        }
        #expect(offenders.isEmpty, """
            A menu in the panel is drawn as a system pop-up. Draw it with VideoKit.Dropdown (a value \
            and a list of choices), the face every other panel menu wears: \
            \(offenders.joined(separator: "; "))
            """)
        #expect(stale.isEmpty, """
            Fewer system pop-ups than `stillSystemPopUps` allows. Lower the count so the list keeps \
            shrinking: \(stale.joined(separator: "; "))
            """)
    }
}
