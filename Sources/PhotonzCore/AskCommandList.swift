import Foundation

/// One row of the list `/` opens in Ask's composer: a call a person can make
/// by pressing Return on it.
public struct AskCommandEntry: Identifiable, Hashable, Sendable {
    /// The API name and any choice: what the row shows at its right, and
    /// what finds it again.
    public var id: String { apiName }
    /// The words of its menu row, and the choice when it has one.
    public let title: String
    public let apiName: String
    /// Where a person finds it in the menu bar.
    public let menu: String
    /// When it can run, in a few plain words.
    public let needs: String
    public let area: AppCommand.Area
    public let call: AppCommandCall
    /// Other words the same row wears, which find it too.
    let otherTitles: [String]
}

/// **`/` in Ask's composer** (`agent-generate-wt.html`, UX-PATTERNS D6): the
/// same field turns into a filtered list of every command, and Return runs the
/// one picked, through the same call the menu row and an agent make.
///
/// A row is only listed when Return on it does something:
///
/// * a command with no required argument is one row;
/// * a command that needs one choice is a row for each choice (Align Left);
/// * a command whose menu row ends in an ellipsis asks the person itself when
///   the argument is left out, so it is one row with nothing filled in;
/// * anything else needs a value no row can hold (a length, a name from this
///   document) and stays in its menu.
public enum AskCommandList {

    public static let all: [AskCommandEntry] = AppCommandTable.all.flatMap(entries)

    /// What is being searched for, or nil when `draft` is a request.
    public static func query(in draft: String) -> String? {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.hasPrefix("/") else { return nil }
        return String(words.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The rows for `query`, what can run now first and the closest words
    /// first within that.
    public static func matching(_ query: String, canRun: (AskCommandEntry) -> Bool) -> Listing {
        let wanted = query.lowercased()
        let found = all.enumerated().compactMap { index, entry -> (entry: AskCommandEntry, rank: Int, index: Int)? in
            rank(entry, for: wanted).map { (entry, $0, index) }
        }
        let ordered = found.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.entry)
        var ready: [AskCommandEntry] = []
        var waiting: [AskCommandEntry] = []
        for entry in ordered {
            if canRun(entry) { ready.append(entry) } else { waiting.append(entry) }
        }
        return Listing(rows: ready + waiting, runnableCount: ready.count)
    }

    /// What the list shows, and which row Return runs.
    public struct Listing: Hashable, Sendable {
        public let rows: [AskCommandEntry]
        /// How many rows, from the top, can run now.
        public let runnableCount: Int
        public private(set) var highlight = 0

        public init(rows: [AskCommandEntry] = [], runnableCount: Int = 0) {
            self.rows = rows
            self.runnableCount = runnableCount
        }

        /// What Return runs: nothing when no row can run now.
        public var picked: AskCommandEntry? {
            highlight < runnableCount ? rows[highlight] : nil
        }

        /// The pick moved by the arrow keys, stopping at the ends.
        public func moved(by step: Int) -> Listing {
            var next = self
            next.highlight = max(0, min(highlight + step, runnableCount - 1))
            return next
        }

        /// The pick on a row the pointer is over.
        public func highlighting(_ index: Int) -> Listing {
            moved(by: index - highlight)
        }
    }

    /// How close `entry` is to `wanted`, lower is closer, or nil for no match.
    private static func rank(_ entry: AskCommandEntry, for wanted: String) -> Int? {
        guard !wanted.isEmpty else { return 0 }
        let title = entry.title.lowercased()
        if title.hasPrefix(wanted) { return 0 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(wanted) }) { return 1 }
        if title.contains(wanted) { return 2 }
        let others = entry.otherTitles + [entry.apiName, entry.menu]
        return others.contains { $0.lowercased().contains(wanted) } ? 3 : nil
    }

    private static func entries(of command: AppCommand) -> [AskCommandEntry] {
        func entry(_ title: String, _ apiName: String, _ options: [String: AgentJSON] = [:]) -> AskCommandEntry {
            AskCommandEntry(title: title, apiName: apiName, menu: command.menu, needs: command.needs,
                            area: command.area, call: AppCommandCall(command.id, options: options),
                            otherTitles: command.otherTitles)
        }
        let required = command.options.filter(\.required)
        if required.isEmpty || command.title.hasSuffix("\u{2026}") {
            return [entry(command.title, command.name)]
        }
        guard required.count == 1, let argument = required.first else { return [] }
        switch argument.kind {
        case .choice(let words):
            return words.map { word in
                entry("\(command.title) \(spoken(word))", "\(command.name) \(word)", [argument.name: .string(word)])
            }
        case .number(let numbers):
            let unit = argument.name == "percent" ? "%" : ""
            return numbers.map { number in
                entry("\(command.title) \(number)\(unit)", "\(command.name) \(number)",
                      [argument.name: .number(Double(number))])
            }
        default:
            return []
        }
    }

    /// A choice's stored word as a menu says it: `horizontalCenter` is
    /// Horizontal Center, `slide_left` is Slide Left.
    static func spoken(_ word: String) -> String {
        var out = ""
        for character in word {
            if character == "_" || character == "-" {
                out.append(" ")
            } else {
                if character.isUppercase, let last = out.last, last != " " { out.append(" ") }
                out.append(character)
            }
        }
        return out.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
