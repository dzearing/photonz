import Foundation

/// How far the planning model has got writing its answer: how many steps it
/// has started, and the name of the one it is on and of the part inside it
/// it has reached (`AskStage.writing`). Read from the streamed answer, so a
/// person watching a long plan sees it advance ("Writing step 4: Toggle,
/// Knob") rather than a clock alone; a component sheet once sat on
/// "Writing the steps" for 97 s (`while-ask-writes-a-long-plan-its-line-names-each`).
public struct AskWriting: Hashable, Sendable {
    /// Steps (tool calls) started so far; 0 before the first.
    public var step: Int
    /// The tool the step calls, for the trace.
    public var tool: String?
    /// The step's own name: its `name`, `title`, `subject`, `label` or `text`.
    public var subject: String?
    /// The latest name met inside the step: a part, a look, a row.
    public var part: String?

    public init(step: Int = 0, tool: String? = nil, subject: String? = nil, part: String? = nil) {
        self.step = step
        self.tool = tool
        self.subject = subject
        self.part = part
    }
}

/// When a new reading of `AskWriting` is worth saying: a new step or a new
/// name at once, a new part at most once a second, so the line advances
/// without flickering through every word.
public struct AskWritingPacer: Sendable {
    public static let partSeconds = 1.0
    private var said: AskWriting?
    private var saidAt = -Double.infinity

    public init() {}

    /// Nothing before the first step: until then the server's own count
    /// says whether it is writing, and an answer of words has no steps.
    public mutating func says(_ writing: AskWriting, at time: Double) -> Bool {
        guard writing.step > 0, writing != said else { return false }
        let soon = writing.step != said?.step || writing.subject != said?.subject
        guard soon || time - saidAt >= Self.partSeconds else { return false }
        said = writing
        saidAt = time
        return true
    }
}

/// Reads a tool call's arguments a piece at a time, as the model writes
/// them, for the names worth saying. It never needs the whole: it keeps
/// only where it is in the JSON, so a call of any length costs the same per
/// character, and words inside a long string (an svg) are never names.
public struct AskArgumentsReader: Hashable, Sendable {
    /// Keys whose string is the step's own name, best first.
    static let subjectKeys = ["name", "title", "subject", "label", "text"]
    /// Keys whose string names something inside the step.
    static let partKeys: Set<String> = ["name", "title", "label"]
    /// The most of a string kept: a name is short, an svg is not.
    static let longest = 120

    public private(set) var subject: String?
    public private(set) var part: String?
    private var subjectRank = Int.max

    /// `{` or `[`, outermost first.
    private var open: [Character] = []
    private var inString = false
    private var escaped = false
    private var unicode: Int?
    private var stringIsKey = false
    private var expectingKey = false
    private var key: String?
    private var words = ""

    public init() {}

    public mutating func read(_ piece: String) {
        for character in piece { take(character) }
    }

    private mutating func take(_ character: Character) {
        if inString {
            if let left = unicode {
                // \uXXXX: its four digits are skipped, never read as words.
                unicode = left > 1 ? left - 1 : nil
            } else if escaped {
                escaped = false
                switch character {
                case "n", "r", "t": keep(" ")
                case "u": unicode = 4
                default: keep(character)
                }
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString = false
                finishString()
            } else {
                keep(character)
            }
            return
        }
        switch character {
        case "\"":
            inString = true
            words = ""
            stringIsKey = open.last == "{" && expectingKey
        case "{", "[":
            open.append(character)
            expectingKey = character == "{"
        case "}", "]":
            if !open.isEmpty { open.removeLast() }
            expectingKey = false
        case ":":
            expectingKey = false
        case ",":
            expectingKey = open.last == "{"
        default:
            break
        }
    }

    private mutating func keep(_ character: Character) {
        if words.count < Self.longest { words.append(character) }
    }

    private mutating func finishString() {
        if stringIsKey {
            key = words
            return
        }
        guard open.last == "{", let key else { return }
        let said = words.trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty else { return }
        if open.count == 1 {
            if let rank = Self.subjectKeys.firstIndex(of: key), rank < subjectRank {
                subject = said
                subjectRank = rank
            }
        } else if Self.partKeys.contains(key) {
            part = said
        }
    }
}

/// The built-in server's answer as it streams in (llama-server's
/// `/v1/chat/completions` with `stream: true`), one line of its event
/// stream at a time. `reply` is the answer in the shape the server gives
/// without streaming, so everything after it (`AskServerChat.reply`) is
/// unchanged; `writing` is how far it has got. The two were measured equal
/// on b11826 for a whole answer and for one cut off part way (2026-11-18),
/// and the server builds both from the same final parse of what was written.
public struct AskStreamedAnswer: Sendable {
    private struct Call: Sendable {
        var id: String?
        var name = ""
        var arguments = ""
        var reader = AskArgumentsReader()
    }

    private var heard = false
    private var content = ""
    private var reasoning = ""
    private var calls: [Call] = []
    private var finishReason: String?
    private var timings: AgentJSON?
    private var error: AgentJSON?
    /// A body that was not a stream at all: the server refused the request
    /// before it began, with one JSON error.
    private var whole: AgentJSON?

    /// Whether the stream said it was done.
    public private(set) var finished = false
    public private(set) var writing = AskWriting()

    public init() {}

    /// One line of the stream: `data: {…}`, `data: [DONE]`, `error: {…}`, or
    /// (from a request refused before it streamed) the whole body.
    public mutating func take(_ line: String) {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix(":") else { return }
        if line.hasPrefix("{") {
            whole = try? AgentJSON.parse(Data(line.utf8))
            finished = true
            return
        }
        if line.hasPrefix("error:") {
            let json = Self.json(after: "error:", in: line)
            error = json?["error"] ?? json ?? .string(String(line.dropFirst("error:".count)))
            return
        }
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            finished = true
            return
        }
        guard let chunk = Self.json(after: "data:", in: line) else { return }
        if let said = chunk["error"] {
            error = said
            return
        }
        heard = true
        if let timings = chunk["timings"] { self.timings = timings }
        guard let choice = chunk["choices"]?.arrayValue?.first else { return }
        if let reason = choice["finish_reason"]?.stringValue { finishReason = reason }
        guard let delta = choice["delta"] else { return }
        if let words = delta["content"]?.stringValue { content += words }
        if let words = delta["reasoning_content"]?.stringValue { reasoning += words }
        for call in delta["tool_calls"]?.arrayValue ?? [] {
            let index = call["index"]?.intValue ?? max(0, calls.count - 1)
            guard index >= 0, index <= calls.count + 16 else { continue }
            while calls.count <= index { calls.append(Call()) }
            if let id = call["id"]?.stringValue { calls[index].id = id }
            if let name = call["function"]?["name"]?.stringValue { calls[index].name += name }
            if let arguments = call["function"]?["arguments"]?.stringValue {
                calls[index].arguments += arguments
                calls[index].reader.read(arguments)
            }
        }
        if let last = calls.last {
            writing = AskWriting(step: calls.count, tool: last.name.isEmpty ? nil : last.name,
                                 subject: last.reader.subject, part: last.reader.part)
        }
    }

    private static func json(after prefix: String, in line: String) -> AgentJSON? {
        try? AgentJSON.parse(Data(line.dropFirst(prefix.count).utf8))
    }

    /// The answer as the server gives it without streaming.
    public var reply: AgentJSON {
        if let whole { return whole }
        if let error { return ["error": error] }
        guard heard else { return .object([:]) }
        var message: [String: AgentJSON] = ["role": "assistant", "content": .string(content)]
        if !reasoning.isEmpty { message["reasoning_content"] = .string(reasoning) }
        if !calls.isEmpty {
            message["tool_calls"] = .array(calls.map { call in
                var out: [String: AgentJSON] = [
                    "type": "function",
                    "function": ["name": .string(call.name), "arguments": .string(call.arguments)],
                ]
                if let id = call.id { out["id"] = .string(id) }
                return .object(out)
            })
        }
        var choice: [String: AgentJSON] = ["index": 0, "message": .object(message)]
        if let finishReason { choice["finish_reason"] = .string(finishReason) }
        var out: [String: AgentJSON] = ["choices": [.object(choice)]]
        if let timings { out["timings"] = timings }
        return .object(out)
    }
}
