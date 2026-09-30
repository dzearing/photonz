import Foundation

/// Whether a line on a pill or a toast tells somebody what to DO.
///
/// The placement contract gives toasts one purpose, "what just happened", and
/// names what never goes there: instructions ("Drag to...", "Press X to...").
/// A result a person can act on carries a button (Undo, Turn Into Picture);
/// how to use a tool is taught by the tool's hover tip and the tutorials, the
/// way a pro Mac editor does it (`pills-and-toasts-say-what-happened-never-how-to`).
///
/// This is the test for that rule, and it is deliberately blunt: it splits a
/// line into clauses and flags any that opens on an imperative (Click, Drag,
/// Press, Pick, Turn, Esc...) or carries one of the stock pieces of advice
/// (try again, Command Z, from the Layer menu, instead). A result ("Turned into
/// a path", "3 shapes are now one path", "Copies pick it with Size") opens on a
/// noun or a past tense and passes.
public enum NoticeCopy {

    /// The clauses of `line` that are instructions, in the order they appear.
    /// Empty when the line only says what happened.
    public static func instructions(in line: String) -> [String] {
        let lowered = line.lowercased()
        var found: [String] = []
        for phrase in advice where lowered.contains(phrase) {
            found.append(phrase)
        }
        for pattern in advicePatterns
        where lowered.range(of: pattern, options: .regularExpression) != nil {
            found.append(pattern)
        }
        for clause in clauses(of: lowered) where opensOnAnImperative(clause) {
            found.append(clause)
        }
        return found
    }

    /// Stock advice, wherever it sits in the line.
    static let advice = [
        "try again", "run it again", "again for more", "command z", "\u{2318}z", " instead",
        "first, then", "then try",
    ]

    /// "from the Layer menu", "switch Fill on".
    static let advicePatterns = [#"from the \w+ menu"#, #"switch \w+ on"#]

    /// The words an instruction starts with. Whole words only: "Turned",
    /// "Detached" and "Separated" are results.
    static let imperatives: [[String]] = [
        ["click"], ["double", "click"], ["drag"], ["press"], ["pick"], ["choose"], ["select"],
        ["turn"], ["switch"], ["separate"], ["try"], ["run"], ["use"], ["open"], ["hold"],
        ["esc"], ["return"], ["make"], ["detach"], ["clear"], ["keep", "clicking"], ["delete"],
        ["arrow", "keys"], ["option", "drag"], ["unlock"], ["undo"],
    ]

    /// A line cut at its sentence and clause breaks, with the joining word
    /// ("or", "and", "then") taken off the front of each piece.
    static func clauses(of lowered: String) -> [String] {
        let pieces = lowered.split(whereSeparator: { ".,;:".contains($0) })
        return pieces.map { piece in
            var words = piece.split(separator: " ").map(String.init)
            while let first = words.first, ["or", "and", "then", "so"].contains(first) {
                words.removeFirst()
            }
            return words.joined(separator: " ")
        }
        .filter { !$0.isEmpty }
    }

    static func opensOnAnImperative(_ clause: String) -> Bool {
        let words = clause.split(separator: " ").map(String.init)
        return imperatives.contains { verb in
            words.count >= verb.count && Array(words.prefix(verb.count)) == verb
        }
    }
}
