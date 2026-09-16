import Foundation
import Testing
@testable import PhotonzCore

/// The rule that stops the panel counting at two again.
///
/// Twelve sentences across the panel each said "all 2 of them" because each was
/// written on its own, and fixing the drop lines in September 2026 left the
/// rest an inch away still counting. Words shared by that many sentences cannot
/// be kept in line by anybody remembering, so the source is read here: write a
/// crowd by hand anywhere in the app and the build says so.
@Suite("Nothing counts a crowd by hand")
struct CrowdWordsDriftTests {

    /// The two shipping modules, found from this file rather than the working
    /// directory, which `swift test` does not promise anything about.
    private static var sourceDirectories: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Sources")
        return ["Photonz", "PhotonzCore", "PhotonzRender"].map(root.appendingPathComponent)
    }

    private static func swiftFiles() -> [URL] {
        sourceDirectories.flatMap { directory -> [URL] in
            let walk = FileManager.default.enumerator(at: directory,
                                                      includingPropertiesForKeys: nil)
            return (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
    }

    /// A crowd is "all" with a COUNT interpolated after it: "all \(count) of
    /// them", "all \(pinned.count) labels". That is the shape that reads wrong
    /// the moment the count is two, and `CrowdWords` is the one place allowed
    /// to write it, because it is the place that decides when to.
    ///
    /// "all \(points(height)) of it" is a measurement rather than a crowd and
    /// is right at any number, so the rule asks for a count and not merely for
    /// something interpolated.
    @Test func noSourceSpellsOutACrowdItself() {
        let handWritten = try! Regex(#"\ball \\\([^)]*\bcount\b"#)
        var offenders: [String] = []
        for file in Self.swiftFiles() where file.lastPathComponent != "CrowdWords.swift" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() where line.contains(handWritten) {
                offenders.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, """
            These say a crowd in their own words, so they count at two. \
            Ask CrowdWords.them or CrowdWords.all for the words instead:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
