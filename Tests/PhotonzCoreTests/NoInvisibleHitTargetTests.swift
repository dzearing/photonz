import Foundation
import Testing

/// A control nobody can see is a control nobody can reliably click.
///
/// Until 2026-09-28 every dropdown in the video panel was a drawn face with a
/// real menu button laid over it at 1% opacity to take the click. The button
/// sized itself to its own (invisible) title, not to the face, so a person
/// clicking the face mostly clicked nothing, while every walk that pressed the
/// button by name stayed green. The user found every panel dropdown dead.
///
/// The fix makes the face itself the thing that is clicked. This rule keeps
/// the trick from coming back: a VIEW faded below 5% is either meant to be
/// gone (use `.hidden()` or leave it out) or is being used as an invisible hit
/// target, and neither is written as a near-zero opacity. A COLOUR at a low
/// opacity (`Palette.ink.opacity(0.03)`) is a tint, not a view, and is fine.
@Suite("No control is clicked through a near-invisible overlay")
struct NoInvisibleHitTargetTests {

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Sources/Photonz")
    }

    /// The opacity below which a view counts as invisible.
    static let floor = 0.05

    /// Every `.opacity(<literal>)` on this line that fades a VIEW below the
    /// floor: one that starts a chained line, or hangs off a closing bracket.
    /// One that hangs off a name (`Color.black.opacity(0.02)`) is a colour.
    static func fadesAViewBelowTheFloor(_ line: String) -> Bool {
        var rest = Substring(line)
        while let dot = rest.range(of: ".opacity(") {
            let before = rest[..<dot.lowerBound].reversed().drop { $0 == " " }
            let hangsOffAView = before.first.map { $0 == ")" || $0 == "}" } ?? true
            let argument = rest[dot.upperBound...].prefix { $0 != ")" }
            if hangsOffAView, let value = Double(argument.trimmingCharacters(in: .whitespaces)),
               value > 0, value < floor {
                return true
            }
            rest = rest[dot.upperBound...]
        }
        return false
    }

    @Test("The rule catches the overlay trick and leaves tints alone")
    func theRuleReadsLinesRight() {
        #expect(Self.fadesAViewBelowTheFloor("                    .opacity(0.011)"))
        #expect(Self.fadesAViewBelowTheFloor("Menu { items }.opacity(0.01)"))
        #expect(!Self.fadesAViewBelowTheFloor("    .fill(Color.black.opacity(0.02))"))
        #expect(!Self.fadesAViewBelowTheFloor("    .opacity(isOn ? 1 : 0)"))
        #expect(!Self.fadesAViewBelowTheFloor("    .opacity(0)"))
        #expect(!Self.fadesAViewBelowTheFloor("    .opacity(0.4)"))
    }

    @Test("No view in the app is faded below 5% to take a click")
    func noNearInvisibleOverlays() throws {
        let root = Self.appSources
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("could not read \(root.path)")
            return
        }
        var offences: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.drop { $0 == " " }
                guard !code.hasPrefix("//") else { continue }
                if Self.fadesAViewBelowTheFloor(String(line)) {
                    offences.append("\(relative):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offences.isEmpty, """
            These fade a view below \(Self.floor) opacity, which is how an invisible control gets laid \
            over a drawn one to take its click. A person's click then lands wherever that invisible \
            control happens to be, not on the face they can see. Make the visible face the control \
            (for a dropdown, `VideoKit.Dropdown`), or hide the view outright.
            \(offences.joined(separator: "\n"))
            """)
    }
}
