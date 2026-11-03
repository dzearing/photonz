import Foundation

/// What Ask is doing right now, for the one live line under a working request
/// in the Agent panel and for an agent reading `list_documents`
/// (`docs/design/ask.md`, "Saying what it is doing"). The user, 2026-10-24:
/// "if we're researching, or building out instructions, or thinking, etc,
/// I'd like some indication of what's happening for the request."
///
/// Each stage is set by the pipeline as it starts, never by a timer. The line
/// is gone once the request is finished: a finished row says what it made and
/// never lists its steps (the user, 2026-10-20).
public enum AskStage: Hashable, Sendable {
    /// Sent, before anything else is known.
    case starting
    /// Ask's model is loading into memory, the first request after a while.
    case gettingModelReady
    /// The picture model is loading into memory.
    case gettingPainterReady
    case reading(video: Bool)
    case lookingAtCanvas
    /// Opening a web page the request named (`AskWeb`), by its short host.
    case openingPage(String)
    /// The planning model at work; turn 1 is the first answer.
    case thinking(turn: Int)
    /// The planning model reading the request and everything sent with it,
    /// this far through.
    case readingRequest(percent: Int)
    /// The planning model writing its answer.
    case writing
    /// The planning model asked to look at something before it plans.
    case lookingUp(tool: String)
    case planningDrawing(subject: String, part: Int, of: Int)
    /// The picture model painting a drawing, this far through when it says.
    case painting(subject: String, part: Int, of: Int, percent: Int? = nil)
    /// A drawing made without the picture model.
    case drawing(subject: String, part: Int, of: Int)
    /// A painting being turned into layers.
    case tracing(subject: String, part: Int, of: Int)
    case photo(subject: String, part: Int, of: Int, percent: Int? = nil)
    /// The plan's other steps running.
    case making(step: Int, of: Int)
    /// A model that can see looking at a drawing it made.
    case checking(subject: String, part: Int, of: Int)
    case tryingAgain(Why)
    case keepingClosest

    /// Why a drawing is being made again.
    public enum Why: Hashable, Sendable {
        /// It was seen as something else.
        case seenAs(String)
        /// It does not show a statement of its plan.
        case missed(String)
        /// The painting ran off the picture's edge.
        case offTheEdge
    }

    /// The most a line may run, the panel's budget (UX-PATTERNS §4).
    public static let budget = 40

    /// The line as shown: within `budget`, the subject or reason cut first.
    public var line: String {
        let (head, middle, tail) = parts
        let whole = head + middle + tail
        guard whole.count > Self.budget else { return whole }
        let room = Self.budget - head.count - tail.count - 1
        guard room > 0 else { return String(whole.prefix(Self.budget - 1)) + "…" }
        var cut = String(middle.prefix(room))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > room / 2 {
            cut = String(cut[..<space])
        }
        cut = cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:."))
        return head + cut + "…" + tail
    }

    /// The whole line, uncut, for the tooltip and for an agent.
    public var fullLine: String {
        let (head, middle, tail) = parts
        return head + middle + tail
    }

    /// The line in three: its words, the part that may be cut, and what
    /// comes after it, which is never cut.
    private var parts: (String, String, String) {
        func counted(_ part: Int, _ of: Int, _ percent: Int? = nil) -> String {
            (of > 1 ? ", \(part) of \(of)" : "") + (percent.map { ", \($0)%" } ?? "")
        }
        switch self {
        case .starting: return ("Getting ready", "", "")
        case .gettingModelReady: return ("Getting the model ready", "", "")
        case .gettingPainterReady: return ("Getting ready to paint", "", "")
        case .reading(let video): return (video ? "Reading the video" : "Reading the picture", "", "")
        case .lookingAtCanvas: return ("Looking at the canvas", "", "")
        case .openingPage(let host): return ("Opening ", host, "")
        case .thinking(let turn): return (turn <= 1 ? "Thinking it through" : "Working out the steps", "", "")
        case .readingRequest(let percent): return ("Reading your request, \(percent)%", "", "")
        case .writing: return ("Writing the steps", "", "")
        case .lookingUp(let tool): return (Self.lookingUp(tool), "", "")
        case .planningDrawing(let subject, let part, let of):
            return ("Planning ", Self.plain(subject), counted(part, of))
        case .painting(let subject, let part, let of, let percent):
            return ("Painting ", Self.plain(subject), counted(part, of, percent))
        case .drawing(let subject, let part, let of):
            return ("Drawing ", Self.plain(subject), counted(part, of))
        case .tracing(let subject, let part, let of):
            return ("Turning ", Self.plain(subject), " into layers" + counted(part, of))
        case .photo(let subject, let part, let of, let percent):
            return ("Making a photo of ", Self.plain(subject), counted(part, of, percent))
        case .making(let step, let of):
            return (of > 1 ? "Making the changes, \(step) of \(of)" : "Making the change", "", "")
        case .checking(let subject, let part, let of):
            return ("Checking ", Self.plain(subject), counted(part, of))
        case .tryingAgain(.seenAs(let seen)): return ("Trying again: it looked like ", Self.plain(seen, lower: true), "")
        case .tryingAgain(.missed(let statement)): return ("Trying again: missed ", Self.plain(statement, lower: true), "")
        case .tryingAgain(.offTheEdge): return ("Painting again: it ran off the edge", "", "")
        case .keepingClosest: return ("Keeping the closest try", "", "")
        }
    }

    /// What the planning model looks at, in the person's words.
    private static func lookingUp(_ tool: String) -> String {
        switch tool {
        case "list_components": "Looking through the components"
        case "list_styles": "Looking through the styles"
        case "list_titles": "Looking through the titles"
        case "list_brushes": "Looking through the brushes"
        case "read_document": "Reading the layers"
        case "render_picture", "video_frame", "contact_sheet": "Looking at the canvas"
        case "find_elements": "Finding the parts"
        case "find_misalignments": "Checking the alignment"
        case "find_measurements": "Measuring"
        default: "Looking something up"
        }
    }

    /// A subject or a sentence as it sits inside a line: one line, no closing
    /// full stop, no em dash.
    private static func plain(_ words: String, lower: Bool = false) -> String {
        var said = words.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "—", with: ", ")
            .trimmingCharacters(in: .whitespaces)
        while let last = said.last, ".!".contains(last) { said.removeLast() }
        if lower, let first = said.first, said.dropFirst().first?.isLowercase ?? true {
            said = first.lowercased() + said.dropFirst()
        }
        return said
    }

    /// A painting or a photo this far through; any other stage as it is.
    public func at(_ percent: Int?) -> AskStage {
        switch self {
        case .painting(let subject, let part, let of, _): .painting(subject: subject, part: part, of: of, percent: percent)
        case .photo(let subject, let part, let of, _): .photo(subject: subject, part: part, of: of, percent: percent)
        default: self
        }
    }

    /// A model turn's line from what its server says it has done: how far it
    /// has read against the tokens the request was estimated at, or that it
    /// is writing. Never 100% while it is still reading, since the estimate
    /// can come in under the truth.
    public static func thinking(turn: Int, at progress: AskModelProgress?, expected: Int) -> AskStage {
        guard let progress else { return .thinking(turn: turn) }
        if progress.written > 0 { return .writing }
        let percent = expected > 0 ? progress.read * 100 / expected : 0
        return .readingRequest(percent: min(99, max(1, percent)))
    }

    /// The time a stage has taken, once it passes five seconds: "12s",
    /// then "1:05".
    public static func elapsed(_ seconds: Double) -> String? {
        guard seconds >= 5 else { return nil }
        let whole = Int(seconds)
        return whole < 60 ? "\(whole)s" : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// One of each stage, for the copy checks.
    public static let examples: [AskStage] = [
        .starting, .gettingModelReady, .gettingPainterReady, .reading(video: false), .reading(video: true),
        .lookingAtCanvas, .thinking(turn: 1), .thinking(turn: 3), .readingRequest(percent: 99), .writing,
        .lookingUp(tool: "list_components"), .lookingUp(tool: "list_styles"), .lookingUp(tool: "list_titles"),
        .lookingUp(tool: "list_brushes"), .lookingUp(tool: "read_document"), .lookingUp(tool: "render_picture"),
        .lookingUp(tool: "find_elements"), .lookingUp(tool: "find_misalignments"),
        .lookingUp(tool: "find_measurements"), .lookingUp(tool: "x"),
        .planningDrawing(subject: "a fox", part: 1, of: 2), .painting(subject: "a fox", part: 2, of: 2),
        .painting(subject: "a red fox curled up asleep in the snow", part: 2, of: 3, percent: 99),
        .drawing(subject: "a fox", part: 1, of: 1), .tracing(subject: "a fox in a forest at sunset", part: 1, of: 1),
        .photo(subject: "a beach at dawn with waves rolling in", part: 1, of: 1),
        .making(step: 12, of: 14), .making(step: 1, of: 1), .tryingAgain(.offTheEdge),
        .checking(subject: "a fox", part: 1, of: 1), .tryingAgain(.seenAs("a dog")),
        .tryingAgain(.missed("its tail is curled around its feet")), .keepingClosest,
    ]
}

/// What the picture model's server says it is doing (`server.py`, `say`):
/// "painting", "painting 3/9", "painting again 3/9", "tracing".
public enum AskPainterSaid: Hashable, Sendable {
    case painting(again: Bool, step: Int?, of: Int?)
    case tracing

    public init?(_ said: String) {
        let words = said.trimmingCharacters(in: .whitespacesAndNewlines)
        if words == "tracing" {
            self = .tracing
            return
        }
        let again = words.hasPrefix("painting again")
        guard again || words.hasPrefix("painting") else { return nil }
        let rest = words.dropFirst(again ? "painting again".count : "painting".count)
            .trimmingCharacters(in: .whitespaces)
        let numbers = rest.split(separator: "/").compactMap { Int($0) }
        if numbers.count == 2, numbers[1] > 0 {
            self = .painting(again: again, step: numbers[0], of: numbers[1])
        } else {
            self = .painting(again: again, step: nil, of: nil)
        }
    }

    /// How far through the painting is, never 100 before it is done.
    public var percent: Int? {
        guard case .painting(_, let step?, let of?) = self, of > 0 else { return nil }
        return min(99, max(1, step * 100 / of))
    }
}

/// How far the model's server has got with the request it is working on,
/// read from llama-server's `/slots`.
public struct AskModelProgress: Hashable, Sendable {
    /// Tokens of the request read so far, cached ones included.
    public let read: Int
    /// Tokens of the answer written so far.
    public let written: Int

    public init(read: Int, written: Int) {
        self.read = read
        self.written = written
    }

    /// The first slot at work, or nil when none is (or the answer is not
    /// the slots list at all).
    public init?(slots: AgentJSON) {
        guard let busy = slots.arrayValue?.first(where: { $0["is_processing"]?.boolValue == true }),
              let read = busy["n_prompt_tokens"]?.doubleValue else { return nil }
        let next = busy["next_token"]?.arrayValue?.first ?? busy["next_token"]
        self.init(read: Int(read), written: Int(next?["n_decoded"]?.doubleValue ?? 0))
    }
}

/// The lines one request showed, with when each came, from its send: what
/// the walk and the audit read to say how long the panel went without news.
public struct AskStageLog: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let at: Double
        public let stage: AskStage
        public var line: String { stage.line }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var ended: Double?

    public init() {}

    /// A stage starts at `at` seconds. The same line again is not a change.
    public mutating func enter(_ stage: AskStage, at: Double) {
        guard entries.last?.line != stage.line else { return }
        entries.append(Entry(at: at, stage: stage))
    }

    public mutating func end(at: Double) {
        ended = at
    }

    /// The longest the line went without changing, to the end when it ended.
    public var longestGap: Double {
        let times = entries.map(\.at) + (ended.map { [$0] } ?? [])
        return zip(times, times.dropFirst()).map { $1 - $0 }.max() ?? 0
    }

    /// "1.0s Thinking it through", a line a change, and "done" at the end.
    public var lines: [String] {
        entries.map { String(format: "%.1fs ", $0.at) + $0.line }
            + (ended.map { [String(format: "%.1fs done", $0)] } ?? [])
    }
}
