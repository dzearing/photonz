import Foundation

// The eval has to measure what a person feels, not what a small visible set
// rewards (the user, 2026-10-20: Ask scored 92 on drawings while it drew one
// cat for every cat request). Two things feed it from the app: a person's
// thumbs on each of Ask's rows, a thumbs down saved as a new held-out case,
// and where each drawing came from, so climbing by lookup shows as a number
// (`Scripts/ask-eval/README.md`, "The held-out set").

/// Where a drawing Ask made came from.
public enum AskDrawingSource: String, Codable, Hashable, Sendable, CaseIterable {
    /// A built-in drawing, looked up by the words of its name.
    case stored
    /// A coded scene or subject, picked by the kind of request. Nothing in
    /// the app makes one any more (the illustrator was taken out on
    /// 2026-10-22); it is still counted, so one slipping back shows.
    case template
    /// Made for the request: the model's own svg, shapes or paths, or a
    /// picture painted for it by the picture model and traced.
    case drawn

    /// The source of a step that ran, from its tool and the app's answer.
    /// Nil for a step that is not a drawing (words, a measurement, an edit),
    /// and for an add_drawing answer that does not say where it came from.
    public static func of(tool: String, answer: String) -> AskDrawingSource? {
        switch tool {
        case "add_shape", "add_path": return .drawn
        case "add_drawing", "add_photo":
            guard let data = answer.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let from = object["from"] as? String else { return nil }
            if from.hasPrefix("built-in") { return .stored }
            if from.hasPrefix("illustration") { return .template }
            if from.hasPrefix("your svg") || from.hasPrefix("painted") { return .drawn }
            return nil
        default: return nil
        }
    }
}

/// A person's verdict on one of Ask's rows.
public enum AskVerdict: String, Codable, Hashable, Sendable {
    case up, down
}

/// What a vote saves beside the documents before and after the request:
/// `case.json` in a folder named by `folderName`, which the eval reads
/// (`Scripts/ask-eval/eval.mjs feedback`).
public struct AskFeedbackCase: Codable, Hashable, Sendable {
    public let request: String
    public let verdict: AskVerdict
    /// When, as ISO 8601.
    public let at: String
    /// The row's words.
    public let sentence: String
    public let sources: [AskDrawingSource]
    /// The canvas, width and height.
    public let canvas: [Double]
    public let model: String?
    public let app: String

    public init(request: String, verdict: AskVerdict, at: String, sentence: String,
                sources: [AskDrawingSource], canvas: [Double], model: String?, app: String) {
        self.request = request
        self.verdict = verdict
        self.at = at
        self.sentence = sentence
        self.sources = sources
        self.canvas = canvas
        self.model = model
        self.app = app
    }

    /// How much of the request a folder name keeps.
    public static let slugLength = 40

    /// `20261020-153705-draw-a-cat-curled-up-sleeping`: sorts by time and says
    /// what was asked.
    public static func folderName(request: String, at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let words = request.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var slug = ""
        for word in words {
            let next = slug.isEmpty ? word : slug + "-" + word
            if next.count > slugLength { break }
            slug = next
        }
        if slug.isEmpty { slug = String(words.first?.prefix(slugLength) ?? "request") }
        return formatter.string(from: date) + "-" + slug
    }
}
