import Foundation

/// Where Ask's model runs (`docs/design/ask.md`, "The model").
///
/// Built in is the default and needs nothing else on the Mac: Photonz ships a
/// model server inside its own bundle, starts it when Ask first needs it and
/// stops it when Ask has been idle a few minutes or Photonz quits. Ollama is
/// for people who already keep one running, and only when they pick it in
/// Settings (the user, 2026-10-22: "we should not have a dependency on
/// opening ollama").
public enum AskRuntime: String, Sendable, CaseIterable {
    case builtIn = "built-in"
    case ollama

    /// Settings' key for the choice; absent means built in.
    public static let settingKey = "ask.runtime"

    /// Ollama's own port. Named here and nowhere else in Sources
    /// (`AskBuiltInModelTests`), so nothing reaches it except through this switch.
    public static let ollamaPort = 11434

    public static func from(stored: String?) -> AskRuntime {
        stored.flatMap(AskRuntime.init(rawValue:)) ?? .builtIn
    }

    public var reachesOllama: Bool { self == .ollama }

    public static var ollamaBase: URL? { URL(string: "http://127.0.0.1:\(ollamaPort)") }
}

/// The models Photonz can download and run itself: GGUF files from Hugging
/// Face, pinned to a revision so every Mac gets the same bytes.
public enum AskBuiltInModels {

    public struct File: Sendable, Equatable {
        public let name: String
        public let url: URL
        public let bytes: Int64

        public init(name: String, url: URL, bytes: Int64) {
            self.name = name
            self.url = url
            self.bytes = bytes
        }
    }

    public struct Choice: Sendable, Equatable {
        /// Stable id, kept in Settings.
        public let id: String
        /// What Settings calls it.
        public let name: String
        /// The weights.
        public let model: File
        /// The picture reader that lets it see, or nil when it cannot.
        public let eyes: File?
        /// Memory it holds while Ask uses it at Ask's window, in GB.
        public let gigabytes: Double

        public var files: [File] { [model] + (eyes.map { [$0] } ?? []) }
        public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
        public var sees: Bool { eyes != nil }
    }

    private static func file(_ repo: String, _ revision: String, _ name: String, _ bytes: Int64) -> File {
        // A literal address: only a typo could make it nil, and the tests read every one.
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(name)")
            ?? URL(fileURLWithPath: "/dev/null")
        return File(name: name, url: url, bytes: bytes)
    }

    /// Best first, by the eval's climb set on 2026-10-22 (M4 Max, 64 GB;
    /// `docs/design/ask.md`, "The model"): Qwen3.6 35B, mixture of experts,
    /// 55.3 at a 22.7 s median, against 53.1 for Ollama's `qwen3.6:27b` (the
    /// default before) at 23.7 s. Qwen3.6 27B scores alike but reads a prompt
    /// at a sixth of the speed here, 90 to 150 s a request, so it is a choice
    /// in Settings, not the default. Then smaller models for Macs with less
    /// memory. Memory held is measured for the two Qwen models and estimated
    /// for the others from their files.
    public static let ranked: [Choice] = [
        Choice(id: "qwen3.6-35b-a3b", name: "Qwen3.6 35B",
               model: file("ggml-org/Qwen3.6-35B-A3B-GGUF", "7878dc9a905c7c9379e5e8d6a1aa9affdd6839c5",
                           "Qwen3.6-35B-A3B-Q4_K_M.gguf", 20_419_565_568),
               eyes: file("ggml-org/Qwen3.6-35B-A3B-GGUF", "7878dc9a905c7c9379e5e8d6a1aa9affdd6839c5",
                          "mmproj-Qwen3.6-35B-A3B-Q8_0.gguf", 614_194_304),
               gigabytes: 21.7),
        Choice(id: "qwen3.6-27b", name: "Qwen3.6 27B",
               model: file("ggml-org/Qwen3.6-27B-GGUF", "1132d03976d88e30a09ab0ddbf1531d5e1b46e7c",
                           "Qwen3.6-27B-Q4_K_M.gguf", 19_095_766_304),
               eyes: file("ggml-org/Qwen3.6-27B-GGUF", "1132d03976d88e30a09ab0ddbf1531d5e1b46e7c",
                          "mmproj-Qwen3.6-27B-Q8_0.gguf", 629_247_104),
               gigabytes: 22.8),
        Choice(id: "gemma-4-26b-a4b", name: "Gemma 4 26B",
               model: file("ggml-org/gemma-4-26B-A4B-it-GGUF", "9cf8c8db0f83fb4582f15381f8fb1a7c1b0b9ca2",
                           "gemma-4-26B-A4B-it-Q4_0.gguf", 14_618_145_824),
               eyes: file("ggml-org/gemma-4-26B-A4B-it-GGUF", "9cf8c8db0f83fb4582f15381f8fb1a7c1b0b9ca2",
                          "mmproj-gemma-4-26B-A4B-it-Q8_0.gguf", 806_408_320),
               gigabytes: 18.5),
        Choice(id: "gemma-4-e4b", name: "Gemma 4 E4B",
               model: file("ggml-org/gemma-4-E4B-it-GGUF", "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc",
                           "gemma-4-E4B-it-Q4_0.gguf", 4_590_807_392),
               eyes: file("ggml-org/gemma-4-E4B-it-GGUF", "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc",
                          "mmproj-gemma-4-E4B-it-Q8_0.gguf", 559_874_816),
               gigabytes: 7.5),
    ]

    public static func choice(id: String) -> Choice? { ranked.first { $0.id == id } }

    /// What a Mac is offered: the best it can hold (`AskModels.memoryShare`).
    public static func recommended(memoryGigabytes: Double) -> Choice? {
        ranked.first { $0.gigabytes <= memoryGigabytes * AskModels.memoryShare }
    }

    /// The model chosen in Settings while it is downloaded, else the best
    /// downloaded one the Mac can hold, else the best downloaded one.
    public static func resolve(chosen: String?, downloaded: [String], memoryGigabytes: Double) -> Choice? {
        if let chosen, downloaded.contains(chosen), let picked = choice(id: chosen) { return picked }
        let have = ranked.filter { downloaded.contains($0.id) }
        return have.first { $0.gigabytes <= memoryGigabytes * AskModels.memoryShare } ?? have.first
    }

    /// "19.7 GB", "629 MB".
    public static func sizeWords(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1e9
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        return String(format: "%.0f MB", Double(bytes) / 1e6)
    }
}

/// How Photonz runs the built-in server: on which port, with what, and when it
/// is let go.
public enum AskBuiltInServerPlan {

    /// Ports Photonz picks from, away from the ones other apps on a Mac
    /// commonly hold (Ollama's 11434 among them).
    public static let ports: ClosedRange<Int> = 18_100...18_899

    public static func pickPort() -> Int { Int.random(in: ports) }

    public static func base(port: Int) -> URL? { URL(string: "http://127.0.0.1:\(port)") }

    public static func chatURL(port: Int) -> URL? { base(port: port)?.appending(path: "v1/chat/completions") }

    /// How long the server stays loaded with nothing asked of it.
    public static let idleSeconds: TimeInterval = 300

    public static func isIdle(lastUsed: Date, now: Date, busy: Int) -> Bool {
        busy == 0 && now.timeIntervalSince(lastUsed) > idleSeconds
    }

    /// The server's command line.
    public static func arguments(for choice: AskBuiltInModels.Choice, in folder: URL, port: Int) -> [String] {
        var args = ["--model", folder.appending(path: choice.model.name).path]
        if let eyes = choice.eyes { args += ["--mmproj", folder.appending(path: eyes.name).path] }
        args += [
            "--host", "127.0.0.1", "--port", String(port),
            "--ctx-size", String(AskConversation.contextWindow),
            // Every layer on the GPU, the chat template's own tool calling,
            // one request at a time (Ask runs one at a time), no web page.
            "--n-gpu-layers", "999", "--jinja", "--parallel", "1", "--no-webui",
        ]
        return args
    }
}

/// Ask speaks Ollama's `/api/chat` (`AskConversation.chatBody`); the built-in
/// server speaks the OpenAI-style `/v1/chat/completions`. These translate both
/// ways, so the conversation itself does not care which runs it.
public enum AskServerChat {

    /// The most one turn may write: a big drawing's svg fits with room to
    /// spare, and a turn that never stops is cut off in a minute or two
    /// rather than writing until the window is full.
    public static let mostTokensATurn = 8192

    public static func body(fromOllama body: AgentJSON) -> AgentJSON {
        var out: [String: AgentJSON] = ["stream": false, "max_tokens": .number(Double(mostTokensATurn))]
        if let model = body["model"] { out["model"] = model }
        if let temperature = body["options"]?["temperature"] { out["temperature"] = temperature }
        if let tools = body["tools"] { out["tools"] = tools }
        if body["think"]?.boolValue == false {
            out["chat_template_kwargs"] = ["enable_thinking": false]
        }
        var messages: [AgentJSON] = []
        // Calls not answered yet, oldest first: (id, tool name).
        var open: [(id: String, name: String)] = []
        for (index, message) in (body["messages"]?.arrayValue ?? []).enumerated() {
            guard var object = message.objectValue else { continue }
            let role = object["role"]?.stringValue ?? ""
            if let images = object["images"]?.arrayValue, !images.isEmpty {
                var parts: [AgentJSON] = []
                if let text = object["content"]?.stringValue, !text.isEmpty {
                    parts.append(["type": "text", "text": .string(text)])
                }
                for image in images {
                    guard let base64 = image.stringValue else { continue }
                    parts.append(["type": "image_url", "image_url": ["url": .string("data:image/png;base64,\(base64)")]])
                }
                object["content"] = .array(parts)
                object["images"] = nil
            }
            if role == "assistant", let calls = object["tool_calls"]?.arrayValue {
                object["tool_calls"] = .array(calls.enumerated().map { number, call in
                    var call = call.objectValue ?? [:]
                    let id = call["id"]?.stringValue ?? "call_\(index)_\(number)"
                    var function = call["function"]?.objectValue ?? [:]
                    if let arguments = function["arguments"], arguments.stringValue == nil {
                        function["arguments"] = .string(arguments.encodedString())
                    }
                    open.append((id, function["name"]?.stringValue ?? ""))
                    call["id"] = .string(id)
                    call["type"] = "function"
                    call["function"] = .object(function)
                    return .object(call)
                })
                if object["content"] == nil || object["content"] == .null { object["content"] = "" }
                object["thinking"] = nil
            }
            if role == "tool" {
                let name = object["tool_name"]?.stringValue ?? ""
                if object["tool_call_id"] == nil, !open.isEmpty {
                    let at = open.firstIndex { $0.name == name } ?? 0
                    object["tool_call_id"] = .string(open.remove(at: at).id)
                }
                object["tool_name"] = nil
            }
            messages.append(.object(object))
        }
        out["messages"] = .array(messages)
        return .object(out)
    }

    public static func reply(fromServer reply: AgentJSON) -> AgentJSON {
        if let error = reply["error"] {
            return ["error": .string(error["message"]?.stringValue ?? error.stringValue ?? "The model said no.")]
        }
        guard let message = reply["choices"]?.arrayValue?.first?["message"] else {
            return ["error": "The model gave no answer."]
        }
        var out: [String: AgentJSON] = [
            "role": "assistant",
            "content": .string(message["content"]?.stringValue ?? ""),
        ]
        if let calls = message["tool_calls"]?.arrayValue, !calls.isEmpty {
            out["tool_calls"] = .array(calls.map { call in
                var function: [String: AgentJSON] = ["name": call["function"]?["name"] ?? ""]
                let arguments = call["function"]?["arguments"] ?? .object([:])
                if let text = arguments.stringValue {
                    function["arguments"] = (try? AgentJSON.parse(Data(text.utf8))) ?? arguments
                } else {
                    function["arguments"] = arguments
                }
                var out: [String: AgentJSON] = ["function": .object(function)]
                if let id = call["id"] { out["id"] = id }
                return .object(out)
            })
        }
        return ["message": .object(out)]
    }
}
