import Foundation
import Testing

/// The video sections of the panel are labels and values, never paragraphs
/// (`the-video-properties-look-like-the-rest-of-the-d`, 2026-09-24).
///
/// The user's words about the panel beside a recording: "It has paragraphs of
/// text in there." Reframe explained itself in two sentences, Time in six, and
/// Captions in three. This reads the sections' own source, so a sentence added
/// to any of them next month fails here the day it lands.
@Suite("The video panel sections say labels, not sentences")
struct VideoPanelCopyTests {

    /// The sections, by the file each is drawn in.
    static let files = [
        "SpeedInspector.swift",
        "SoundInspector.swift",
        "CaptionsInspector.swift",
        "TransitionInspector.swift",
    ]

    /// The longest string a video section may carry, tooltips included.
    static let longest = 60

    static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Photonz")
    }

    /// Every string literal in a file, comments left out.
    static func literals(in text: String) -> [String] {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("//") ? "" : String(line)
        }.joined(separator: "\n")
        let pattern = try? NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#)
        let range = NSRange(code.startIndex..., in: code)
        return (pattern?.matches(in: code, range: range) ?? []).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
    }

    @Test(arguments: files)
    func noStringIsLongerThanALabel(file: String) throws {
        let text = try String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8)
        let long = Self.literals(in: text).filter { $0.count > Self.longest }
        #expect(long.isEmpty, "\(file) says: \(long)")
    }

    @Test(arguments: files)
    func noSentenceIsBuiltOutOfPieces(file: String) throws {
        let text = try String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8)
        let glued = try NSRegularExpression(pattern: #""\s*\n?\s*\+\s*""#)
        let found = glued.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        #expect(found == 0, "\(file) glues string literals together to get past the limit")
    }

    @Test func theReframeSectionIsGone() {
        let path = Self.sources.appendingPathComponent("ReframeInspector.swift").path
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func theCheckItselfFindsALongString() {
        let sample = """
        // "A comment can say as much as it likes, however long the sentence runs on for."
        Text("Short")
        Text("A freeze is not a new kind of object. It is a piece whose in and out are the same frame.")
        """
        #expect(Self.literals(in: sample) == [
            "Short",
            "A freeze is not a new kind of object. It is a piece whose in and out are the same frame.",
        ])
    }
}
