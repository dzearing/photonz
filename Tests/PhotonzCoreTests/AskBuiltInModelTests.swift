import Foundation
@testable import PhotonzCore
import Testing

/// Ask's model runs inside Photonz (`docs/design/ask.md`, "The model"): a
/// server Photonz ships in its own bundle and starts itself, on a model file
/// Settings downloads. Nothing else on the Mac is needed, and Ollama is only
/// ever reached when a person turns it on in Settings.
@Suite("Ask: the model built into Photonz")
struct AskBuiltInModelTests {

    static func json(_ text: String) throws -> AgentJSON { try AgentJSON.parse(Data(text.utf8)) }

    // MARK: Which runtime

    @Test("Ask runs on the built-in model unless a person picked Ollama in Settings")
    func builtInIsTheDefault() {
        #expect(AskRuntime.from(stored: nil) == .builtIn)
        #expect(AskRuntime.from(stored: "") == .builtIn)
        #expect(AskRuntime.from(stored: "something else") == .builtIn)
        #expect(AskRuntime.from(stored: "ollama") == .ollama)
        #expect(AskRuntime.from(stored: "built-in") == .builtIn)
    }

    @Test("No address Ask reaches by default is Ollama's port")
    func defaultNeverReachesOllama() throws {
        // The built-in server listens on a port Photonz picks; Ollama's is
        // never one of them, so a Mac with Ollama open is not used by accident.
        for _ in 0..<200 {
            let port = AskBuiltInServerPlan.pickPort()
            #expect(port != AskRuntime.ollamaPort)
            #expect(AskBuiltInServerPlan.ports.contains(port))
        }
        let url = try #require(AskBuiltInServerPlan.chatURL(port: 18_123))
        #expect(url.host() == "127.0.0.1")
        #expect(url.port == 18_123)
        #expect(AskRuntime.from(stored: nil).reachesOllama == false)
        #expect(AskRuntime.ollama.reachesOllama)
    }

    @Test("Only the Ollama runtime's own file names Ollama's port")
    func ollamaPortIsNamedOnlyInItsOwnPlace() throws {
        // A source check: anything new that dials 11434 must go through the
        // runtime switch, so the default stays off Ollama.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var naming: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("11434") { naming.append(file.lastPathComponent) }
        }
        #expect(naming.sorted() == ["AskBuiltInModel.swift"], "\(naming)")
    }

    // MARK: Which model

    @Test("Every built-in model is a pinned download with a size and somewhere to look")
    func catalogIsPinned() {
        #expect(!AskBuiltInModels.ranked.isEmpty)
        #expect(Set(AskBuiltInModels.ranked.map(\.id)).count == AskBuiltInModels.ranked.count)
        for choice in AskBuiltInModels.ranked {
            for file in choice.files {
                #expect(file.url.scheme == "https", "\(file.name)")
                #expect(file.url.absoluteString.contains("/resolve/"), "pinned to a revision: \(file.name)")
                #expect(file.bytes > 100_000_000, "\(file.name)")
                #expect(file.url.lastPathComponent == file.name)
            }
            #expect(choice.gigabytes * 1e9 > Double(choice.downloadBytes), "\(choice.id) holds at least what it downloads")
            #expect(!choice.name.contains("\u{2014}"))
        }
    }

    @Test("A Mac is offered the best model it can hold, and none when it can hold none")
    func recommendedFitsTheMac() throws {
        let best = try #require(AskBuiltInModels.ranked.first)
        #expect(AskBuiltInModels.recommended(memoryGigabytes: 68.7) == best)
        let small = try #require(AskBuiltInModels.recommended(memoryGigabytes: 17.2))
        #expect(small.gigabytes <= 17.2 * AskModels.memoryShare)
        #expect(AskBuiltInModels.recommended(memoryGigabytes: 4) == nil)
    }

    @Test("The model in use is the one chosen while it is downloaded, else the best downloaded one")
    func resolvesAmongDownloaded() throws {
        let ids = AskBuiltInModels.ranked.map(\.id)
        let best = try #require(ids.first)
        let last = try #require(ids.last)
        #expect(AskBuiltInModels.resolve(chosen: nil, downloaded: [], memoryGigabytes: 68.7) == nil)
        #expect(AskBuiltInModels.resolve(chosen: nil, downloaded: [last, best], memoryGigabytes: 68.7)?.id == best)
        #expect(AskBuiltInModels.resolve(chosen: last, downloaded: [last, best], memoryGigabytes: 68.7)?.id == last)
        #expect(AskBuiltInModels.resolve(chosen: "gone", downloaded: [last], memoryGigabytes: 68.7)?.id == last)
    }

    @Test("The download says its size the way a person reads it")
    func sizeWords() {
        #expect(AskBuiltInModels.sizeWords(19_725_013_408) == "19.7 GB")
        #expect(AskBuiltInModels.sizeWords(629_247_104) == "629 MB")
    }

    // MARK: Talking to the server

    @Test("Ask's chat body becomes the server's, with tools, no thinking and the picture inline")
    func requestTranslates() throws {
        let png = Data([1, 2, 3])
        let body: AgentJSON = [
            "model": "qwen", "stream": false, "think": false, "keep_alive": "30m",
            "options": ["num_ctx": 32768, "temperature": 0],
            "tools": [["type": "function", "function": ["name": "find_elements", "parameters": ["type": "object"]]]],
            "messages": [
                ["role": "system", "content": "be good"],
                ["role": "user", "content": "look", "images": [.string(png.base64EncodedString())]],
            ],
        ]
        let sent = AskServerChat.body(fromOllama: body)
        #expect(sent["temperature"]?.doubleValue == 0)
        #expect(sent["stream"]?.boolValue == false)
        #expect(sent["chat_template_kwargs"]?["enable_thinking"]?.boolValue == false)
        #expect(sent["tools"]?.arrayValue?.count == 1)
        #expect(sent["keep_alive"] == nil)
        // A turn that runs away (an svg that never closes) ends instead of
        // writing until the window is full.
        #expect(sent["max_tokens"]?.intValue == AskServerChat.mostTokensATurn)
        #expect(sent["options"] == nil)
        let messages = try #require(sent["messages"]?.arrayValue)
        #expect(messages[0]["content"]?.stringValue == "be good")
        let parts = try #require(messages[1]["content"]?.arrayValue)
        #expect(parts[0]["type"]?.stringValue == "text")
        #expect(parts[0]["text"]?.stringValue == "look")
        #expect(parts[1]["type"]?.stringValue == "image_url")
        #expect(parts[1]["image_url"]?["url"]?.stringValue == "data:image/png;base64,\(png.base64EncodedString())")
        #expect(messages[1]["images"] == nil)
    }

    @Test("A model that may think is not told not to")
    func thinkingLeftAlone() {
        let sent = AskServerChat.body(fromOllama: ["model": "m", "messages": [], "options": ["temperature": 0]])
        #expect(sent["chat_template_kwargs"] == nil)
    }

    @Test("Each tool answer names the call it answers, matched by tool, in order")
    func toolAnswersCarryTheirCall() throws {
        let body: AgentJSON = [
            "model": "m",
            "messages": [
                ["role": "user", "content": "go"],
                ["role": "assistant", "content": "", "tool_calls": [
                    ["id": "a1", "function": ["name": "add_shape", "arguments": ["kind": "rect"]]],
                    ["function": ["name": "find_elements", "arguments": [:]]],
                    ["id": "a3", "function": ["name": "add_shape", "arguments": ["kind": "oval"]]],
                ]],
                ["role": "tool", "tool_name": "add_shape", "content": "Planned as step 1."],
                ["role": "tool", "tool_name": "add_shape", "content": "Planned as step 2."],
                ["role": "tool", "tool_name": "find_elements", "content": "[]"],
            ],
        ]
        let messages = try #require(AskServerChat.body(fromOllama: body)["messages"]?.arrayValue)
        let calls = try #require(messages[1]["tool_calls"]?.arrayValue)
        #expect(calls.map { $0["id"]?.stringValue } == ["a1", "call_1_1", "a3"])
        #expect(calls[0]["type"]?.stringValue == "function")
        // Arguments go over as a JSON string, the way the server reads them.
        let args = try #require(calls[0]["function"]?["arguments"]?.stringValue)
        #expect(try Self.json(args)["kind"]?.stringValue == "rect")
        #expect(messages[2]["tool_call_id"]?.stringValue == "a1")
        #expect(messages[3]["tool_call_id"]?.stringValue == "a3")
        #expect(messages[4]["tool_call_id"]?.stringValue == "call_1_1")
        #expect(messages[2]["tool_name"] == nil)
    }

    @Test("The server's reply reads like the one Ask already takes")
    func replyTranslates() throws {
        let reply = try Self.json(#"""
        {"choices":[{"message":{"role":"assistant","content":null,"reasoning_content":"hm",
          "tool_calls":[{"id":"x9","type":"function","function":{"name":"add_text","arguments":"{\"text\":\"Hi\",\"x\":8,\"y\":8}"}}]}}]}
        """#)
        let read = AskServerChat.reply(fromServer: reply)
        let message = try #require(read["message"])
        #expect(message["role"]?.stringValue == "assistant")
        #expect(message["content"]?.stringValue == "")
        let call = try #require(message["tool_calls"]?.arrayValue?.first)
        #expect(call["id"]?.stringValue == "x9")
        #expect(call["function"]?["name"]?.stringValue == "add_text")
        #expect(call["function"]?["arguments"]?["text"]?.stringValue == "Hi")

        var talk = AskConversation(request: "add hi", documentRead: #"{"kind":"picture","width":800,"height":600}"#)
        _ = talk.take(read)
        #expect(talk.steps.first?.tool == "add_text")
    }

    @Test("Arguments the server could not write as JSON are passed on as written")
    func brokenArgumentsPassThrough() throws {
        let reply = try Self.json(#"""
        {"choices":[{"message":{"content":"","tool_calls":[{"function":{"name":"add_text","arguments":"{oops"}}]}}]}
        """#)
        let call = try #require(AskServerChat.reply(fromServer: reply)["message"]?["tool_calls"]?.arrayValue?.first)
        #expect(call["function"]?["arguments"]?.stringValue == "{oops")
    }

    @Test("A server error comes back as one sentence")
    func errorTranslates() throws {
        let reply = try Self.json(#"{"error":{"code":400,"message":"the request exceeds the context","type":"x"}}"#)
        #expect(AskServerChat.reply(fromServer: reply)["error"]?.stringValue == "the request exceeds the context")
        #expect(AskServerChat.reply(fromServer: ["nothing": true])["error"] != nil)
    }

    // MARK: The server's own lifetime

    @Test("The server is let go after a few idle minutes")
    func idleRule() {
        #expect(AskBuiltInServerPlan.idleSeconds >= 120)
        #expect(AskBuiltInServerPlan.idleSeconds <= 600)
        let start = Date(timeIntervalSince1970: 0)
        #expect(!AskBuiltInServerPlan.isIdle(lastUsed: start, now: start.addingTimeInterval(60), busy: 0))
        #expect(AskBuiltInServerPlan.isIdle(lastUsed: start, now: start.addingTimeInterval(AskBuiltInServerPlan.idleSeconds + 1), busy: 0))
        #expect(!AskBuiltInServerPlan.isIdle(lastUsed: start, now: start.addingTimeInterval(9_999), busy: 1))
    }

    @Test("The server is started on the model, its eyes, Ask's window, loopback only")
    func serverArguments() throws {
        let choice = try #require(AskBuiltInModels.ranked.first)
        let folder = URL(fileURLWithPath: "/tmp/models")
        let args = AskBuiltInServerPlan.arguments(for: choice, in: folder, port: 18_200)
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        #expect(value("--model") == folder.appending(path: choice.model.name).path)
        if let eyes = choice.eyes { #expect(value("--mmproj") == folder.appending(path: eyes.name).path) }
        #expect(value("--host") == "127.0.0.1")
        #expect(value("--port") == "18200")
        #expect(value("--ctx-size") == String(AskConversation.contextWindow))
        #expect(args.contains("--jinja"))
        #expect(args.contains("--no-webui"))
    }
}
