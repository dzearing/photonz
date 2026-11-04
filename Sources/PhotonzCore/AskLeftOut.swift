import Foundation

// A change that stops short says so (`docs/design/ask.md`, "When Ask stops part
// way"). On 2026-10-23 a model sent one refused add_shape back three times, Ask
// offered a title, a subtitle and one empty card, and the row read Made a
// pricing section on brand. A plan keeps what it could not make (`AskUnplanned`)
// and a run keeps what it had to leave out (`AskPlanRun`), and each says it in
// one short line, for the row and for where Ask answers.

/// What a plan could not make: things the model was told to leave out and
/// never made after all, and where planning stopped when it stopped before the
/// model said it was finished.
public struct AskUnplanned: Hashable, Sendable {
    public let things: [String]
    /// The last thing planned, when planning stopped before the model finished.
    public let stoppedAfter: String?

    public init(things: [String], stoppedAfter: String?) {
        self.things = things
        self.stoppedAfter = stoppedAfter
    }

    public var sentence: String {
        if let stoppedAfter { return "Stopped after \(stoppedAfter); the rest could not be planned." }
        let listed = switch things.count {
        case 1: things[0]
        case 2: "\(things[0]) and \(things[1])"
        default: "\(things.first ?? "") and \(things.count - 1) more"
        }
        return "Left out \(listed); \(things.count == 1 ? "it" : "they") could not be planned."
    }
}

/// A person's words for a step and for why it failed.
public enum AskLeftOutWords {

    /// The most of a text's words the line quotes.
    static let longestWords = 24
    /// A reason longer than this is not one short line.
    static let longestReason = 60
    public static let noReason = "it could not be done"

    /// What a step makes, as the line calls it: its name, its words, or the
    /// kind of thing it is.
    public static func thing(_ step: AskStep, names: [String: String] = [:]) -> String {
        if let name = plain(step.arguments["name"]) { return name }
        if let component = plain(step.arguments["component"]) {
            if let named = names[component] { return named }
            if UUID(uuidString: component) == nil { return component }
        }
        if let words = plain(step.arguments["text"]) {
            let flat = words.replacingOccurrences(of: "\n", with: " ")
            let cut = flat.count > longestWords ? String(flat.prefix(longestWords - 1)) + "\u{2026}" : flat
            return "\u{201C}\(cut)\u{201D}"
        }
        return AskChangeWords.oneThing(step) ?? "a step"
    }

    private static func plain(_ value: AgentJSON?) -> String? {
        guard let word = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else { return nil }
        return word
    }

    /// Why a step failed, from what the tool said. Tools speak to a model, so
    /// only a short first sentence with no ids or tool names in it is shown.
    public static func reason(_ refusal: String) -> String {
        var said = refusal.trimmingCharacters(in: .whitespacesAndNewlines)
        // "set_layer: Card is locked." speaks to whoever called set_layer.
        if let colon = said.firstIndex(of: ":"), !said[..<colon].contains(" ") {
            said = String(said[said.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        if let end = said.range(of: ". ") { said = String(said[..<end.lowerBound]) }
        while said.hasSuffix(".") { said.removeLast() }
        let words = said.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "$" }).map(String.init)
        guard let id = words.firstIndex(where: isID) else {
            return said.isEmpty || said.count > longestReason || said.contains("_") ? noReason : said
        }
        // "There is no layer 6F96…": the kind of thing is the part a person can use.
        if id >= 2, words[id - 2].lowercased() == "no" { return "that \(words[id - 1]) is not there" }
        return noReason
    }

    private static func isID(_ word: String) -> Bool {
        UUID(uuidString: word) != nil || AskStep.stepNamed(word) != nil
    }
}

/// A plan as it runs, a step at a time: what each step made, and what was left
/// out and why. A step that fails changed nothing, so everything else still
/// runs, and a step counting on it (`$N`) cannot and is left out with it. The
/// app does the running (`AskSession.run`), all of it one undo step.
public struct AskPlanRun: Sendable {

    public struct LeftOut: Hashable, Sendable {
        public let number: Int
        public let thing: String
        public let why: String
        /// The left out step this one counted on, nil when it failed itself.
        public let needed: Int?
    }

    public let plan: AskPlan
    /// What each step made, by step number, for a later step's `$N`.
    public private(set) var made: [Int: String] = [:]
    public private(set) var landed: [AskStep] = []
    public private(set) var leftOut: [LeftOut] = []

    public init(plan: AskPlan) {
        self.plan = plan
    }

    /// Leaves step `number` out when a step it counts on was left out, and
    /// says whether it did.
    public mutating func passOver(_ number: Int) -> Bool {
        guard plan.steps.indices.contains(number - 1) else { return false }
        let step = plan.steps[number - 1]
        guard let needed = leftOut.first(where: { step.names(step: $0.number) }) else { return false }
        leftOut.append(LeftOut(number: number, thing: AskLeftOutWords.thing(step, names: plan.names),
                               why: "It needed \(needed.thing)", needed: needed.number))
        return true
    }

    /// Step `number` ran, and made `id` if it says so.
    public mutating func land(_ number: Int, id: String?) {
        guard plan.steps.indices.contains(number - 1) else { return }
        landed.append(plan.steps[number - 1])
        if let id { made[number] = id }
    }

    /// Step `number` failed, in the tool's own words.
    public mutating func leaveOut(_ number: Int, because refusal: String) {
        guard plan.steps.indices.contains(number - 1) else { return }
        leftOut.append(LeftOut(number: number, thing: AskLeftOutWords.thing(plan.steps[number - 1], names: plan.names),
                               why: AskLeftOutWords.reason(refusal), needed: nil))
    }

    /// What this change did not make, in one short line; nil when it made it all.
    public var sentence: String? {
        let said = [plan.unplanned?.sentence, ranSentence].compactMap { $0 }
        return said.isEmpty ? nil : said.joined(separator: " ")
    }

    private var ranSentence: String? {
        let failed = leftOut.filter { $0.needed == nil }
        guard let first = failed.first else { return nil }
        let others = leftOut.count - 1
        if failed.count > 1 { return "Left out \(first.thing) and \(others) more: \(first.why)." }
        if others == 0 { return "Left out \(first.thing): \(first.why)." }
        return "Left out \(first.thing) and \(others == 1 ? "a step" : "\(others) steps") that needed it: \(first.why)."
    }
}
