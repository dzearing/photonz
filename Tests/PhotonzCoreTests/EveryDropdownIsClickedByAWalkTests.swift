import Foundation
import Testing

/// Every dropdown in the panel is proved the way a hand uses it.
///
/// On 2026-09-28 the user found every panel dropdown dead to the pointer while
/// every walk that pressed one by name was green: pressing a menu by name
/// proves it exists, not that a person can click it. So each dropdown has to
/// appear in a walk that OPENS it the way a person does (`panelMenu` with
/// `at`: a pointer click on its face, or a key with it focused), and a walk
/// whose name says it proves a click may not open a menu any other way.
@Suite("Every panel dropdown is opened by a pointer click in some walk")
struct EveryDropdownIsClickedByAWalkTests {

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
    }

    /// The names the dropdowns whose row name is built from a variable
    /// answer to, as they show in the panel. A dropdown added with a built
    /// name has to be written in here AND clicked by a walk; the count below
    /// is what notices one was added.
    static let builtNames = [
        "Caption said", "Caption coming",
        "Hold on black",
        "Fade In", "Fade Out",
        // `SelectionMenu`, the Text section's (and a Captions layer's) type
        // menus, on the panel's dropdown since 2026-10-05. In Next, Size is a
        // box whose preset list (`PanelNumberField.presets`) is the dropdown.
        "Font", "Size", "Weight",
        // A saved effect style's own settings (`EffectStylePanel.picker`),
        // on the panel's dropdown since 2026-10-05.
        "Kind", "Position",
    ]
    /// How many dropdown call sites build their row name from a variable.
    static let builtSites = 6

    /// The name a walk finds each dropdown by: the first `playtestField` or
    /// `playtestControl` after the call, nil when that name is built at run
    /// time.
    static func dropdownNames() throws -> (literal: [String], built: Int, sites: [String]) {
        let app = root.appendingPathComponent("Sources/Photonz")
        guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            return ([], 0, [])
        }
        var literal: [String] = []
        var built = 0
        var sites: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" {
            // The segmented control's own fallback (a bar too narrow for its
            // words) is named by the row it stands in, as is anything the kit
            // builds inside itself.
            guard !file.path.contains("/VideoKit/"),
                  !file.path.hasSuffix("/DesignSystem/SegmentedControl.swift") else { continue }
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated()
            where line.contains("VideoKit.DropdownRow(") || line.contains("VideoKit.Dropdown(") {
                let site = "\(file.lastPathComponent):\(index + 1)"
                sites.append(site)
                let after = lines[index..<min(lines.count, index + 16)].joined(separator: "\n")
                guard let name = firstName(in: after) else {
                    Issue.record("\(site): a dropdown with no playtestField or playtestControl a walk can find it by")
                    continue
                }
                if name.contains("\\(") { built += 1 } else { literal.append(name) }
            }
        }
        return (literal, built, sites)
    }

    /// A name that is not one plain string (`field ?? "…"`, `"Caption \(label)"`)
    /// comes back holding `\(`, which is what marks it as built.
    static func firstName(in text: String) -> String? {
        let marks = [".playtestField(", ".playtestControl("]
        let found = marks.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        guard let open = found?.upperBound else { return nil }
        guard text[open...].first == "\"" else { return "\\(built)" }
        let start = text.index(after: open)
        guard let end = text[start...].firstIndex(of: "\"") else { return nil }
        return String(text[start..<end])
    }

    /// Every walk, by file name, with its steps.
    static func walks() throws -> [(name: String, steps: [[String: Any]])] {
        let folder = root.appendingPathComponent("Scripts/playtest")
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                guard let object = json as? [String: Any], let steps = object["steps"] as? [[String: Any]] else {
                    return nil
                }
                return (url.deletingPathExtension().lastPathComponent, steps)
            }
    }

    @Test("Every dropdown in the panel is opened by a pointer click in some walk")
    func everyDropdownIsClicked() throws {
        let names = try Self.dropdownNames()
        #expect(names.sites.count >= 10, "found only \(names.sites.count) dropdowns; the scan is broken")
        #expect(names.built == Self.builtSites, """
            \(names.built) dropdowns build their row name at run time, and this test knows \(Self.builtSites). \
            Add the names a new one shows to `builtNames`, and click it in a walk (`panelMenu` with `at`).
            """)
        var clicked = Set<String>()
        for walk in try Self.walks() {
            for step in walk.steps where step["do"] as? String == "panelMenu" && step["at"] != nil {
                if let menu = step["menu"] as? String { clicked.insert(menu) }
            }
        }
        let missing = (names.literal + Self.builtNames).filter { !clicked.contains($0) }
        #expect(missing.isEmpty, """
            No walk opens these dropdowns the way a person does. Add a `panelMenu` step with \
            "at": ["centre", "start", "end"] for each, at Next defaults \
            (Scripts/playtest/every-dropdown-opens-on-a-click-walk.json and its neighbours): \
            \(missing.joined(separator: ", "))
            """)
    }

    /// The dropdowns whose list opens in a popover (`VideoKit.ListDropdown`),
    /// by the name a walk presses them by.
    static func listDropdownNames() throws -> [String] {
        let app = root.appendingPathComponent("Sources/Photonz")
        guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            return []
        }
        var names: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" && !file.path.contains("/VideoKit/") {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() where line.contains("VideoKit.ListDropdown(") {
                let after = lines[index..<min(lines.count, index + 16)].joined(separator: "\n")
                guard let name = firstName(in: after), !name.contains("\\(") else {
                    Issue.record("\(file.lastPathComponent):\(index + 1): a list dropdown with no plain playtestControl a walk can press it by")
                    continue
                }
                names.append(name)
            }
        }
        return names
    }

    /// A list dropdown opens a popover, not a menu, so `panelMenu` cannot open
    /// it. A walk proves a hand opens it with `press` steps: one in the middle
    /// (no `across`) and one near each end (`across` at most 0.1 and at least
    /// 0.9), each followed by a press on a row of the list it opened.
    @Test("Every list dropdown in the panel is pressed by a walk at its middle and both ends")
    func everyListDropdownIsClicked() throws {
        let names = try Self.listDropdownNames()
        #expect(names.count >= 2, "found only \(names.count) list dropdowns; the scan is broken")
        var spots: [String: Set<String>] = [:]
        for walk in try Self.walks() {
            for step in walk.steps where step["do"] as? String == "press" && step["in"] == nil {
                guard let control = step["control"] as? String else { continue }
                let across = (step["across"] as? NSNumber)?.doubleValue
                let spot = across == nil ? "centre" : across! <= 0.1 ? "start" : across! >= 0.9 ? "end" : "other"
                spots[control, default: []].insert(spot)
            }
        }
        let missing = names.filter { !(spots[$0] ?? []).isSuperset(of: ["centre", "start", "end"]) }
        #expect(missing.isEmpty, """
            No walk presses these list dropdowns at their middle and near both ends. Add `press` steps \
            with no `across`, `"across": 0.05` and `"across": 0.95`, each followed by a press on a row \
            of the list (Scripts/playtest/appearance-and-effects-dropdowns-open-on-a-click-walk.json): \
            \(missing.joined(separator: ", "))
            """)
    }

    @Test("A walk that proves a click opens its menus with a click")
    func clickWalksClick() throws {
        let proofs = try Self.walks().filter { $0.name.hasSuffix("-on-a-click-walk") }
        #expect(!proofs.isEmpty)
        for walk in proofs {
            for (index, step) in walk.steps.enumerated() where step["do"] as? String == "panelMenu" {
                #expect(step["at"] != nil || step["clicking"] != nil, """
                    \(walk.name) step \(index + 1) opens "\(step["menu"] ?? "")" by pressing it in code, \
                    in a walk whose name says it proves a person's click. Give it "at".
                    """)
            }
        }
    }
}
