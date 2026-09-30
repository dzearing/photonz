import Foundation
import Testing
@testable import PhotonzCore

/// Every menu row, menu heading and button label the app writes is in Title
/// Case, the Mac's way (UX-PATTERNS §7 "How a menu row is capitalised").
///
/// The mocks write rows in sentence case ("Apply to every cut"); the user chose
/// the Mac's casing on 2026-09-30, after four audits in three days had each
/// explained the same departure. This reads the titles out of the source the
/// way `EveryCommandIsInTheMenuBarTests` does: every row of the menu bar and
/// its headings, every right-click row, and the title of every `Button` and
/// `Menu` in the app. A label beside a control in the panel is not read: it is
/// a label, and keeps sentence case. The Current release's own folder is not
/// read either: Next is what this rule was asked for.
@Suite("Every menu row and button the app writes is in Title Case")
struct MenuRowsAreTitleCaseTests {

    private typealias Source = EveryCommandIsInTheMenuBarTests

    /// A title that breaks the rule on purpose, and why.
    static let allowed: [String: String] = [
        // "For" closes the clause "what it is for"; written small it reads
        // as the start of another phrase.
        "Set What It Is For in the Library": "the For closes the clause what it is for",
    ]

    /// A literal as it reads on screen: `\u{2026}` is the ellipsis.
    static func onScreen(_ literal: String) -> String {
        var text = literal
        while let open = text.range(of: "\\u{"),
              let close = text[open.upperBound...].firstIndex(of: "}"),
              let code = UInt32(text[open.upperBound..<close], radix: 16),
              let scalar = Unicode.Scalar(code) {
            text.replaceSubrange(open.lowerBound...close, with: String(Character(scalar)))
        }
        return text
    }

    /// The headings of the menu bar's own menus.
    static func menuHeadings() throws -> Set<String> {
        let commands = try String(contentsOf: Source.root.appendingPathComponent("Sources/Photonz/EditorCommands.swift"),
                                  encoding: .utf8)
        return Set(Source.firstArguments(of: "CommandMenu", in: commands[...]).flatMap(Source.literals(in:)))
    }

    /// The title of every `Button` and `Menu` the app writes, and of every row
    /// and heading of a panel dropdown (`VideoKit.Choice`), with the file.
    static func controlTitles() throws -> [String: Set<String>] {
        var found: [String: Set<String>] = [:]
        for file in Source.swiftFiles(under: "Sources/Photonz")
        where !file.path.contains("/Playtest/") && !file.path.contains("/Releases/Current/") {
            let source = try String(contentsOf: file, encoding: .utf8)
            for callee in ["Button", "Menu", ".item", ".heading"] {
                for title in Source.firstArguments(of: callee, in: source[...]).flatMap(Source.literals(in:)) {
                    found[onScreen(title), default: []].insert(file.lastPathComponent)
                }
            }
        }
        return found
    }

    /// Every title this rule covers, with where it came from.
    static func everyTitle() throws -> [String: Set<String>] {
        var found = try controlTitles()
        for title in try Source.menuBarTitles() { found[title, default: []].insert("the menu bar") }
        for title in try menuHeadings() { found[title, default: []].insert("a menu bar heading") }
        for (title, sources) in try Source.rightClickTitles() { found[title, default: []].formUnion(sources) }
        return found
    }

    @Test("Every menu row, menu heading and button is in Title Case")
    func everyTitleIsTitleCase() throws {
        let titles = try Self.everyTitle()
        #expect(titles.count > 200, "the source reader found only \(titles.count) titles")
        // One of each kind: a menu bar row, a right-click row, a panel button,
        // a panel dropdown's row written with an escaped ellipsis.
        for known in ["Apply to Every Cut", "Play from Here", "Key It", "Draw a Curve\u{2026}"] {
            #expect(titles[known] != nil, "the source reader no longer finds \"\(known)\"")
        }
        for (title, sources) in titles.sorted(by: { $0.key < $1.key }) where Self.allowed[title] == nil {
            let wrong = MenuTitleCase.departures(in: title)
            guard !wrong.isEmpty else { continue }
            Issue.record("""
                "\(title)" (\(sources.sorted().joined(separator: ", "))) is not in Title Case: \
                \(wrong.joined(separator: ", ")). Write it "\(MenuTitleCase.titleCased(title))".
                """)
        }
    }

    @Test("Every title allowed to break the rule is still written somewhere")
    func allowedIsLive() throws {
        let titles = try Self.everyTitle()
        for title in Self.allowed.keys {
            #expect(titles[title] != nil, "\"\(title)\" is no longer written anywhere; take it off the list")
        }
    }
}
