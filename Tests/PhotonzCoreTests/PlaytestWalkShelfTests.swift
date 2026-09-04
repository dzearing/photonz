import Foundation
import PhotonzCore
import Testing

/// The Library shelf remembers which scope it was left on, across runs of the
/// probe as well as across launches. That makes the shelf's tab a piece of
/// state one walk hands the next: a walk that opens the Library and then
/// reaches for "Search media" only finds that field when whatever ran before
/// it happened to leave the shelf on Media, and fails otherwise.
///
/// So the rule is that a walk says which shelf it wants. This reads every walk
/// in `Scripts/playtest` and holds them all to it, so the next walk written
/// cannot quietly inherit a tab again.
@Suite("Playtest walks say which Library shelf they want")
struct PlaytestWalkShelfTests {

    /// The walk folder, found from this file rather than from the working
    /// directory, which `swift test` does not promise anything about.
    private static var walkDirectory: URL {
        URL(fileURLWithPath: #filePath)          // Tests/PhotonzCoreTests/…
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Scripts/playtest")
    }

    /// Which shelf each action puts on screen. Only the actions that SAY a
    /// scope count: `showLibrary` opens the Library on whatever tab it was
    /// last left on, which is exactly the state this rule is about.
    private static let shelfActions: [PlaytestAction: LibraryScope] = [
        .showMediaShelf: .media,
        .showComponentShelf: .components,
    ]

    private static func walkFiles() throws -> [URL] {
        let directory = walkDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("Every walk that types in the Library search box asked for that shelf first")
    func walksNameTheShelfBeforeSearchingIt() throws {
        let files = try Self.walkFiles()
        try #require(!files.isEmpty, "no walks found in \(Self.walkDirectory.path)")

        // The placeholder each scope's search field shows, which is the name a
        // `focus` step has to use to reach it.
        let scopeOfPlaceholder = Dictionary(
            uniqueKeysWithValues: LibraryScope.allCases.map {
                ($0.searchPlaceholder.lowercased(), $0)
            })

        for file in files {
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            var shelf: LibraryScope?
            for (index, step) in script.steps.enumerated() {
                switch step {
                case .action(let action):
                    if let asked = Self.shelfActions[action] { shelf = asked }
                case .focus(let field):
                    guard let wanted = scopeOfPlaceholder[field.lowercased()] else { continue }
                    #expect(shelf == wanted, """
                        \(file.lastPathComponent) step \(index + 1) reaches for \
                        "\(field)", but nothing before it put the shelf on \
                        \(wanted.title). The Library opens on the tab the last \
                        run left it on, so this walk passes or fails depending \
                        on what ran before it. Say the shelf first: use the \
                        action that opens the \(wanted.title) shelf instead of \
                        showLibrary (add it to PlaytestAction if that scope has \
                        none yet).
                        """)
                default:
                    continue
                }
            }
        }
    }
}
