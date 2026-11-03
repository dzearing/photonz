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
        /// A small model that writes a few words ahead for the big one to
        /// check (llama.cpp's multi-token prediction), or nil. It changes how
        /// fast an answer comes, never what it says, and the model runs
        /// without it when its file is missing.
        public let draft: File?
        /// Memory it holds while Ask uses it at Ask's window, in GB, draft included.
        public let gigabytes: Double
        /// What Settings says it is good at, one short line.
        public let blurb: String
        /// Its held-out score and speed (`AskModelMeasure`), or nil before it is measured.
        public let measured: AskModelMeasure?
        /// Whether Settings and the setup dialog offer it. One that is not is
        /// still listed, to use or delete, on a Mac that already has it.
        public let offered: Bool

        public init(id: String, name: String, model: File, eyes: File?, draft: File? = nil, gigabytes: Double,
                    blurb: String = "", measured: AskModelMeasure? = nil, offered: Bool = true) {
            self.id = id
            self.name = name
            self.model = model
            self.eyes = eyes
            self.draft = draft
            self.gigabytes = gigabytes
            self.blurb = blurb
            self.measured = measured
            self.offered = offered
        }

        /// What it cannot run without.
        public var needed: [File] { [model] + (eyes.map { [$0] } ?? []) }
        /// What a download brings down.
        public var files: [File] { needed + (draft.map { [$0] } ?? []) }
        public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
        public var sees: Bool { eyes != nil }
    }

    /// One pinned file. `folder` keeps it in a folder of its model's own, for
    /// repositories whose file names another model's share ("mmproj-F16.gguf").
    private static func file(_ repo: String, _ revision: String, _ name: String, _ bytes: Int64,
                             folder: String? = nil) -> File {
        // A literal address: only a typo could make it nil, and the tests read every one.
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(name)")
            ?? URL(fileURLWithPath: "/dev/null")
        return File(name: folder.map { "\($0)/\(name)" } ?? name, url: url, bytes: bytes)
    }

    /// Qwen3.8 27B first, by the user's call on 2026-10-24 ("we should be
    /// using qwen 3.8 27b 4 bit quant over 3.6 35b"); its measurements against
    /// Qwen3.6 35B are in `docs/design/ask.md`, "Qwen3.8 27B, 2026-10-24". It
    /// is dense, so it reads a prompt at about a seventh of the 35B's speed,
    /// and its draft roughly doubles how fast it writes.
    ///
    /// The rest by the eval's climb set on 2026-10-22 (M4 Max, 64 GB;
    /// `docs/design/ask.md`, "The model"): Qwen3.6 35B, mixture of experts,
    /// 55.3 at a 22.7 s median, against 53.1 for Ollama's `qwen3.6:27b` (the
    /// default before) at 23.7 s. Qwen3.6 27B scores alike but reads a prompt
    /// at a sixth of the speed here, 90 to 150 s a request, so it is a choice
    /// in Settings, not the default. Then smaller models for Macs with less
    /// memory. Memory held is measured for the two Qwen models and estimated
    /// for the others from their files.
    public static let ranked: [Choice] = [
        Choice(id: "qwen3.8-27b", name: "Qwen3.8 27B",
               model: file("ggml-org/Qwen3.8-27B-GGUF", "a316ea527fde32c12487be7574e2db5ac2ad2a7e",
                           "Qwen3.8-27B-Q4_K_M.gguf", 18_973_870_528),
               eyes: file("ggml-org/Qwen3.8-27B-GGUF", "a316ea527fde32c12487be7574e2db5ac2ad2a7e",
                          "mmproj-Qwen3.8-27B-Q8_0.gguf", 629_247_008),
               draft: file("ggml-org/Qwen3.8-27B-GGUF", "a316ea527fde32c12487be7574e2db5ac2ad2a7e",
                           "mtp-Qwen3.8-27B-Q4_0.gguf", 1_680_271_776),
               // The median over the climb set, as the 35B's 21.7 is; 27.6 at its peak.
               gigabytes: 24.4,
               blurb: "Best at sheets, layouts and video. Slow to start.",
               measured: AskModelMeasure(heldOut: 57.8, medianSeconds: 141.9, run: "20261024-163432-ask-held-out")),
        Choice(id: "qwen3.6-35b-a3b", name: "Qwen3.6 35B",
               model: file("ggml-org/Qwen3.6-35B-A3B-GGUF", "7878dc9a905c7c9379e5e8d6a1aa9affdd6839c5",
                           "Qwen3.6-35B-A3B-Q4_K_M.gguf", 20_419_565_568),
               eyes: file("ggml-org/Qwen3.6-35B-A3B-GGUF", "7878dc9a905c7c9379e5e8d6a1aa9affdd6839c5",
                          "mmproj-Qwen3.6-35B-A3B-Q8_0.gguf", 614_194_304),
               gigabytes: 21.7,
               blurb: "Best at drawings, and quick.",
               measured: AskModelMeasure(heldOut: 60.2, medianSeconds: 49.1, run: "20261024-191502-ask-held-out")),
        Choice(id: "qwen3.6-27b", name: "Qwen3.6 27B",
               model: file("ggml-org/Qwen3.6-27B-GGUF", "1132d03976d88e30a09ab0ddbf1531d5e1b46e7c",
                           "Qwen3.6-27B-Q4_K_M.gguf", 19_095_766_304),
               eyes: file("ggml-org/Qwen3.6-27B-GGUF", "1132d03976d88e30a09ab0ddbf1531d5e1b46e7c",
                          "mmproj-Qwen3.6-27B-Q8_0.gguf", 629_247_104),
               // Not offered: Qwen3.8 27B is the same size and shape, newer
               // and better on the eval, so a Mac that has this one keeps it
               // only until it deletes it.
               gigabytes: 22.8,
               blurb: "Older than Qwen3.8 27B, and slower.",
               offered: false),
        Choice(id: "gemma-4-26b-a4b", name: "Gemma 4 26B",
               model: file("ggml-org/gemma-4-26B-A4B-it-GGUF", "9cf8c8db0f83fb4582f15381f8fb1a7c1b0b9ca2",
                           "gemma-4-26B-A4B-it-Q4_0.gguf", 14_618_145_824),
               eyes: file("ggml-org/gemma-4-26B-A4B-it-GGUF", "9cf8c8db0f83fb4582f15381f8fb1a7c1b0b9ca2",
                          "mmproj-gemma-4-26B-A4B-it-Q8_0.gguf", 806_408_320),
               // Measured held 23.1 GB at the 64k window (`20261102-004807-ask-held-out`).
               gigabytes: 23.1,
               blurb: "Gets video right more than drawings.",
               measured: AskModelMeasure(heldOut: 20.2, medianSeconds: 35.5, run: "20261102-004807-ask-held-out")),
        Choice(id: "qwen3.5-9b", name: "Qwen3.5 9B",
               model: file("unsloth/Qwen3.5-9B-GGUF", "3885219b6810b007914f3a7950a8d1b469d598a5",
                           "Qwen3.5-9B-Q4_K_M.gguf", 5_680_522_464, folder: "qwen3.5-9b"),
               eyes: file("unsloth/Qwen3.5-9B-GGUF", "3885219b6810b007914f3a7950a8d1b469d598a5",
                          "mmproj-F16.gguf", 918_166_080, folder: "qwen3.5-9b"),
               // The most it held over a held-out run planned as a 16 GB Mac,
               // at that Mac's 32k window (7.7 just loaded): it fits a 16 GB Mac
               // by the three-fifths rule, with 0.2 GB to spare.
               gigabytes: 10.1,
               blurb: "Fits a 16 GB Mac. Basic, and slow to answer.",
               // Run as a 16 GB Mac (`--mac 16`). At this Mac's 64k window it
               // scored 21.2 at 76.3 s (`20261102-023538-ask-held-out`).
               measured: AskModelMeasure(heldOut: 20.7, medianSeconds: 91.8, run: "20261102-122343-ask-held-out",
                                         mac: "M4 Max set up as a 16 GB Mac")),
        Choice(id: "qwen3.5-4b", name: "Qwen3.5 4B",
               model: file("unsloth/Qwen3.5-4B-GGUF", "e87f176479d0855a907a41277aca2f8ee7a09523",
                           "Qwen3.5-4B-Q4_K_M.gguf", 2_740_937_888, folder: "qwen3.5-4b"),
               eyes: file("unsloth/Qwen3.5-4B-GGUF", "e87f176479d0855a907a41277aca2f8ee7a09523",
                          "mmproj-F16.gguf", 672_423_616, folder: "qwen3.5-4b"),
               gigabytes: 7.8,
               blurb: "Small.",
               measured: AskModelMeasure(heldOut: 12.4, medianSeconds: 57.4, run: "20261102-012713-ask-held-out")),
        Choice(id: "gemma-4-e2b", name: "Gemma 4 E2B",
               model: file("ggml-org/gemma-4-E2B-it-GGUF", "6938c58e698502037401a5f19f6905f2fb2f7dee",
                           "gemma-4-E2B-it-Q4_0.gguf", 2_841_481_184),
               eyes: file("ggml-org/gemma-4-E2B-it-GGUF", "6938c58e698502037401a5f19f6905f2fb2f7dee",
                          "mmproj-gemma-4-E2B-it-Q8_0.gguf", 557_368_064),
               gigabytes: 4.2,
               blurb: "Smallest and fastest.",
               measured: AskModelMeasure(heldOut: 4.6, medianSeconds: 15.8, run: "20261102-001045-ask-held-out")),
        Choice(id: "gemma-4-e4b", name: "Gemma 4 E4B",
               model: file("ggml-org/gemma-4-E4B-it-GGUF", "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc",
                           "gemma-4-E4B-it-Q4_0.gguf", 4_590_807_392),
               eyes: file("ggml-org/gemma-4-E4B-it-GGUF", "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc",
                          "mmproj-gemma-4-E4B-it-Q8_0.gguf", 559_874_816),
               gigabytes: 7.3,
               blurb: "Small and fast.",
               measured: AskModelMeasure(heldOut: 4.5, medianSeconds: 13.3, run: "20261102-002913-ask-held-out")),
    ]

    public static func choice(id: String) -> Choice? { ranked.first { $0.id == id } }

    /// What a Mac is offered: the best it can hold (`AskModels.memoryShare`).
    public static func recommended(memoryGigabytes: Double) -> Choice? {
        ranked.first { AskModelSetup.offerable($0) && $0.gigabytes <= memoryGigabytes * AskModels.memoryShare }
    }

    /// The model chosen in Settings while it is downloaded, else the best
    /// downloaded one the Mac can hold, else the best downloaded one.
    public static func resolve(chosen: String?, downloaded: [String], memoryGigabytes: Double) -> Choice? {
        if let chosen, downloaded.contains(chosen), let picked = choice(id: chosen) { return picked }
        let have = ranked.filter { downloaded.contains($0.id) }
        return have.first { $0.gigabytes <= memoryGigabytes * AskModels.memoryShare } ?? have.first
    }

    /// The model this Mac would be offered, when a person has another one
    /// but not that: Settings offers it beside the one in use, which keeps
    /// answering until they download it or pick otherwise.
    public static func newer(downloaded: [String], memoryGigabytes: Double) -> Choice? {
        guard !downloaded.isEmpty, let best = recommended(memoryGigabytes: memoryGigabytes),
              !downloaded.contains(best.id), let rank = ranked.firstIndex(of: best) else { return nil }
        // Only a step up: a Mac that has a model ranked above it is not
        // offered a smaller one as its new default.
        let had = ranked.indices.filter { downloaded.contains(ranked[$0].id) }
        return had.allSatisfy { $0 > rank } ? best : nil
    }

    /// Downloaded models a person may delete: every one but the one in use.
    public static func removable(downloaded: [String], inUse: String?) -> [Choice] {
        ranked.filter { downloaded.contains($0.id) && $0.id != inUse }
    }

    /// Where the Hugging Face tools keep the pinned file at `url` on a Mac
    /// that already has it (`~/.cache/huggingface/hub/models--<org>--<name>/
    /// snapshots/<revision>/<path>`), so a download can copy those bytes
    /// instead of fetching them again. Nil for an address that is not a
    /// pinned Hugging Face file.
    public static func huggingFaceCache(for url: URL, home: URL) -> URL? {
        guard url.host() == "huggingface.co" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 5, parts[2] == "resolve" else { return nil }
        return parts[4...].reduce(home.appending(path: ".cache/huggingface/hub/models--\(parts[0])--\(parts[1])/snapshots/\(parts[3])")) {
            $0.appending(path: $1)
        }
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

    /// The server's command line. The draft goes in when its file is on the
    /// Mac (`draftOnDisk`), so a model downloaded without it still runs.
    public static func arguments(for choice: AskBuiltInModels.Choice, in folder: URL, port: Int,
                                 draftOnDisk: Bool = false, window: Int = AskConversation.contextWindow) -> [String] {
        var args = ["--model", folder.appending(path: choice.model.name).path]
        if let eyes = choice.eyes { args += ["--mmproj", folder.appending(path: eyes.name).path] }
        if draftOnDisk, let draft = choice.draft {
            args += ["--spec-type", "draft-mtp", "--model-draft", folder.appending(path: draft.name).path]
        }
        args += [
            "--host", "127.0.0.1", "--port", String(port),
            "--ctx-size", String(window),
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
        // An answer held to a schema (Ollama's `format`): the server's
        // grammar keeps the model to it (the reader's lists, `AskLookup`).
        if let schema = body["format"], schema.objectValue != nil {
            out["response_format"] = ["type": "json_schema", "json_schema": ["name": "answer", "schema": schema]]
        }
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
