import CoreGraphics
import Foundation

/// What Ask does with a request when nothing is open: typed into the New
/// window's Describe field, or asked in an empty window.
///
/// A request to make a picture makes a blank image and Ask draws into it,
/// exactly as it would on one opened by hand. A request for a video is one Ask
/// cannot make yet, and a request about something that would already have to
/// be open (measure this, find the misalignments) has nothing to work on;
/// each says so in one sentence and keeps the words.
///
/// This is routing, not content: it reads what KIND of request it is from the
/// words that refer to something already there (this, the screenshot), the
/// verbs that work on something already there (measure, crop), and the words
/// that name time (video, animated). Nothing here knows any subject.
public enum AskFromNothing {

    public enum Start: Equatable, Sendable {
        /// Make a blank picture this size and ask for the drawing on it.
        case picture(CGSize)
        /// Asked for a video, which Ask cannot make yet.
        case video
        /// Asked about something that would already have to be open.
        case needsSomethingOpen
    }

    /// What a video request is told.
    public static let videoSentence = "Ask can't make videos yet."
    /// What a request about something already open is told.
    public static let nothingOpenSentence = "Nothing is open yet."

    /// What to do with `words`, or nil when nothing was typed. `picked` is
    /// the size the person has picked (the New window's size list), used
    /// when the request names neither a size nor a shape.
    public static func start(_ words: String, picked: CGSize) -> Start? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        let tokens = Self.tokens(of: words)
        if needsSomethingOpen(tokens) { return .needsSomethingOpen }
        if tokens.contains(where: timeWords.contains) { return .video }
        if let size = namedSize(in: words) { return .picture(size) }
        if let shape = format(tokens) { return .picture(shape) }
        return .picture(BlankCanvas.normalized(picked))
    }

    /// A size written in the request: "1920x1080", "800 × 600", "640 by 480".
    /// Kept inside what a blank canvas may be.
    public static func namedSize(in words: String) -> CGSize? {
        let pattern = #"(\d{2,5})\s*(?:x|×|by|\*)\s*(\d{2,5})"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(words.startIndex..., in: words)
        guard let match = expression.firstMatch(in: words, range: range), match.numberOfRanges == 3,
              let first = Range(match.range(at: 1), in: words), let second = Range(match.range(at: 2), in: words),
              let width = Double(words[first]), let height = Double(words[second]) else { return nil }
        return BlankCanvas.normalized(CGSize(width: width, height: height))
    }

    // MARK: The words

    private static func tokens(of words: String) -> [String] {
        words.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Verbs that work on something already there, when the request starts
    /// with one.
    static let workingVerbs: Set<String> = [
        "measure", "redline", "align", "crop", "resize", "rotate", "flip", "find", "fix", "remove",
        "delete", "erase", "blur", "sharpen", "annotate", "highlight", "select", "trim", "cut", "split",
        "export", "save", "rename", "recolor", "recolour", "change", "move", "straighten",
        "check", "caption", "translate", "explain", "summarize", "summarise", "undo", "redo",
        "brighten", "darken", "enhance", "shrink", "enlarge", "duplicate", "hide", "inspect", "compare",
        "distribute", "ungroup", "replace", "edit",
    ]

    /// Words that point at something already there.
    static let pointing: Set<String> = ["this", "these", "those", "selection", "selected"]

    /// What is already there, after "the": "crop the screenshot".
    static let openThings: Set<String> = [
        "screenshot", "screenshots", "picture", "image", "photo", "video", "clip", "clips", "recording",
        "layer", "layers", "document", "canvas", "timeline", "selection",
    ]

    /// Pronouns that, straight after a working verb or "make", point back.
    static let pronouns: Set<String> = ["it", "them"]

    static func needsSomethingOpen(_ tokens: [String]) -> Bool {
        guard let first = tokens.first else { return false }
        if workingVerbs.contains(first) { return true }
        if tokens.contains(where: pointing.contains) { return true }
        // "make it blue", "turn them red"
        if tokens.count > 1, ["make", "turn", "set", "give", "put"].contains(first), pronouns.contains(tokens[1]) {
            return true
        }
        return zip(tokens, tokens.dropFirst()).contains { $0 == "the" && openThings.contains($1) }
    }

    /// Words that name something with time in it.
    static let timeWords: Set<String> = [
        "video", "videos", "movie", "movies", "animation", "animations", "animated", "animate", "gif",
        "slideshow", "trailer",
    ]

    /// A shape the request names, as a format ("a poster", "a banner") or as
    /// a shape word on the picture itself ("a square image", "portrait
    /// orientation"). A shape word that is the subject ("a red square", "a
    /// portrait of a cat") is not a format.
    static func format(_ tokens: [String]) -> CGSize? {
        let wide = CGSize(width: 1500, height: 500)
        let tall = CGSize(width: 1024, height: 1440)
        let landscape = BlankCanvas.defaultPreset.size
        let square = CGSize(width: 1000, height: 1000)
        let formatNouns: Set<String> = ["image", "picture", "canvas", "format", "orientation", "shape", "size"]
        let shapes: [String: CGSize] = [
            "square": square, "portrait": tall, "vertical": tall, "tall": tall,
            "landscape": landscape, "horizontal": landscape, "wide": wide,
        ]
        for (word, next) in zip(tokens, tokens.dropFirst()) where formatNouns.contains(next) {
            if let shape = shapes[word] { return shape }
        }
        if tokens.contains("banner") || tokens.contains("header") { return wide }
        if tokens.contains("poster") || tokens.contains("flyer") { return tall }
        return nil
    }
}
