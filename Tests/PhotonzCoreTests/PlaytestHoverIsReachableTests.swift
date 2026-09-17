import Foundation
import Testing

/// A hover no walk can reach is a hover that can break in silence.
///
/// `.onHover` is the one reaction in the app that a scripted walk cannot drive
/// with a mouse event: AppKit works hover out from the real cursor, and a walk
/// has no real cursor. So every hover in the app goes through `playtestHover`,
/// which is `.onHover` plus an invisible marker a walk's pointer can find
/// (`Sources/Photonz/Playtest/PlaytestPointer.swift`).
///
/// That only holds if nobody writes a bare `.onHover` again, and nothing about
/// writing one looks wrong. So this rule reads the app's own source and fails
/// the build's tests when one turns up, naming the file and the line, because
/// the alternative is finding out from a walk that quietly proves nothing.
@Suite("Every hover is one a walk can reach")
struct PlaytestHoverIsReachableTests {

    /// The app's source, found from this file rather than from the working
    /// directory, which `swift test` does not promise anything about.
    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Sources/Photonz")
    }

    /// The one place a bare `.onHover` is right: inside `playtestHover` itself,
    /// which is what every other hover is routed through.
    private static let allowed = "Playtest/PlaytestPointer.swift"

    /// Whether this line hangs `.onHover` off a view, as opposed to naming the
    /// `ToastEditAction` case of the same name or writing about it.
    static func callsTheModifier(_ line: String) -> Bool {
        var rest = Substring(line)
        while let dot = rest.range(of: ".onHover") {
            let after = rest[dot.upperBound...].drop { $0 == " " }
            let before = rest[..<dot.lowerBound].reversed().drop { $0 == " " }
            let calls = after.first == "(" || after.first == "{"
            // A modifier hangs off what came before it: a closing bracket, an
            // identifier, or the start of a chained line. `== .onHover {` and
            // `case .onHover` do not.
            let hangsOffAValue = before.first.map { $0 == ")" || $0 == "]" || $0.isLetter || $0.isNumber } ?? true
            if calls && hangsOffAValue { return true }
            rest = rest[dot.upperBound...]
        }
        return false
    }

    @Test("No view in the app calls .onHover directly")
    func everyHoverGoesThroughPlaytestHover() throws {
        let root = Self.appSources
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("could not read \(root.path)")
            return
        }
        var offences: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            guard relative != Self.allowed else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // A comment explaining the rule is not a breach of it.
                let code = line.drop { $0 == " " }
                guard !code.hasPrefix("//") else { continue }
                // The modifier is always CALLED, so a bare mention in prose is
                // not it. Neither is `editAction == .onHover`, which compares a
                // `ToastEditAction` and has nothing to do with the pointer, so
                // what comes before the dot has to be a value to hang a
                // modifier on rather than an operator or a keyword.
                guard Self.callsTheModifier(String(line)) else { continue }
                offences.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offences.isEmpty, """
            These call .onHover directly, so no scripted walk can rest a pointer on them \
            and whatever they drive can break unnoticed. Use `.playtestHover { … }` instead: \
            it is the same `.onHover` plus a marker a walk can find.
            \(offences.joined(separator: "\n"))
            """)
    }
}
