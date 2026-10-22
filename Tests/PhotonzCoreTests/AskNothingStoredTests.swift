import Foundation
@testable import PhotonzCore
import Testing

/// Nothing Ask or the skill makes comes from a stored drawing or from code
/// written for a particular subject (the user, 2026-10-20: "i don't want a
/// hardcoded anything"). The stored emoji set and the coded illustrator were
/// taken out on 2026-10-22; these keep them out.
@Suite("Ask draws from nothing stored and no subject's own code")
struct AskNothingStoredTests {

    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("No drawing set ships with the app")
    func noStoredSet() {
        #expect(!FileManager.default.fileExists(atPath: Self.repo.appendingPathComponent("Resources/Drawings").path))
    }

    @Test("No source file draws scenes or looks drawings up by name")
    func noIllustratorOrLibrary() throws {
        let core = Self.repo.appendingPathComponent("Sources/PhotonzCore")
        let files = try FileManager.default.contentsOfDirectory(atPath: core.path)
        #expect(files.filter { $0.hasPrefix("Illustrat") || $0.hasPrefix("DrawingLibrary") }.isEmpty)
    }

    @Test("Drawing code names no subject: the words it reads name looks, kinds of picture and times of day")
    func wordsNameNoSubject() {
        let subjects: Set<String> = ["fox", "lighthouse", "skyline", "mountain", "mountains", "forest", "city",
                                     "cottage", "cat", "dog", "tree", "trees", "bird", "birds", "cloud", "clouds",
                                     "sea", "lake", "cliff", "stars", "moon", "sun"]
        #expect(AgentDrawingWords.sceneWords.isDisjoint(with: subjects))
        let looks = AgentDrawingWords.lookWords(in: subjects.sorted().joined(separator: " "))
        #expect(looks.isEmpty)
    }

    @Test("add_drawing offers no switch for a built-in drawing")
    func noBuiltInSwitch() {
        let tool = AgentTools.all.first { $0.name == "add_drawing" }
        let properties = tool?.inputSchema["properties"]?.objectValue ?? [:]
        #expect(!properties.isEmpty)
        #expect(properties["builtIn"] == nil)
    }

    @Test("A painted drawing and the model's own svg count as drawn; a stored or coded one would still be counted")
    func sourcesStillCounted() {
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"painted: z-image-turbo, 40 paths in 25 s"}"#) == .drawn)
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"your svg"}"#) == .drawn)
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"built-in: cat"}"#) == .stored)
        #expect(AskDrawingSource.of(tool: "add_drawing", answer: #"{"from":"illustration: sunset"}"#) == .template)
    }
}
