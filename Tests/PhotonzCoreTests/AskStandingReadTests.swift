import Foundation
@testable import PhotonzCore
import Testing

/// Ask's first request after its model loads used to spend a minute reading
/// the same tools and rules it reads every time (about 13,000 tokens on
/// Qwen3.8 27B at under 200 a second). That read is the same for every
/// request, so it is saved once to a file and restored in a fraction of a
/// second (`AskStandingRead`). These say what the saved read is made of and
/// how it is keyed, so it is never reused by another model, another server
/// or another prompt.
@Suite("Ask: the standing read is saved and keyed so it is never stale")
struct AskStandingReadTests {

    static let identity = AskStandingRead.Identity(
        model: "qwen3.8-27b",
        files: ["Qwen3.8-27B-Q4_K_M.gguf 18973870528", "mmproj-Qwen3.8-27B-Q8_0.gguf 629247008"],
        server: "b11826-abc123", window: 65_536)
    static let tokens = Array(1...4_000)

    // MARK: What is saved

    @Test("The standing body is the request's own tools and rules, cut where the document starts")
    func standingBodyIsTheRequestsOwnStart() throws {
        let talk = AskConversation(request: "make the button blue", documentRead: #"{"kind":"picture","layers":[{"id":"d1"}]}"#)
        let body = try #require(talk.standingBody(model: "m"))
        let full = talk.chatBody(model: "m")
        let standing = try #require(body["messages"]?.arrayValue?.first?["content"]?.stringValue)
        let system = try #require(full["messages"]?.arrayValue?.first?["content"]?.stringValue)
        #expect(system.hasPrefix(standing))
        #expect(standing.hasSuffix(AskConversation.documentMarker))
        #expect(!standing.contains("d1"))
        #expect(body["tools"] == full["tools"])
        #expect(body["think"] == full["think"])
        #expect(body["options"] == full["options"])
        #expect(body["model"] == full["model"])
    }

    @Test("Two requests on two documents share one standing body; other tools make another")
    func standingBodyDependsOnTheToolsNotTheDocument() throws {
        let one = AskConversation(request: "measure this", documentRead: #"{"kind":"picture","layers":[{"id":"d1"}]}"#)
        let two = AskConversation(request: "make it red", documentRead: #"{"kind":"picture","layers":[{"id":"d7","name":"Card"}]}"#)
        #expect(one.standingBody(model: "m") == two.standingBody(model: "m"))
        let video = AskConversation(request: "make it red", documentRead: #"{"kind":"video","layers":[]}"#)
        #expect(video.standingBody(model: "m") != one.standingBody(model: "m"))
    }

    @Test("Only the tokens the request and the standing body share from the start are saved")
    func sharedPrefix() {
        #expect(AskStandingRead.shared([1, 2, 3, 4, 5], [1, 2, 3, 9]) == [1, 2, 3])
        #expect(AskStandingRead.shared([1, 2], [1, 2, 3]) == [1, 2])
        #expect(AskStandingRead.shared([7, 2], [1, 2]) == [])
        #expect(AskStandingRead.shared([], [1]) == [])
    }

    @Test("A short shared start is not worth a file")
    func worthSaving() {
        #expect(!AskStandingRead.worthSaving(Array(0..<100)))
        #expect(AskStandingRead.worthSaving(Self.tokens))
    }

    @Test("The server's token list is read from its tokenize answer")
    func tokensFromTheServer() throws {
        let json = try AgentJSON.parse(Data(#"{"tokens":[151644, 8948, 198]}"#.utf8))
        #expect(AskStandingRead.tokens(fromTokenize: json) == [151_644, 8_948, 198])
        #expect(AskStandingRead.tokens(fromTokenize: ["error": "no"]) == nil)
    }

    // MARK: How it is keyed

    @Test("The same model, files, server, window and tokens name the same file")
    func sameEverythingSameFile() {
        #expect(AskStandingRead.fileName(Self.identity, tokens: Self.tokens)
                == AskStandingRead.fileName(Self.identity, tokens: Self.tokens))
    }

    @Test("Another model never reads this model's file, even with the same tokens")
    func neverSharedBetweenModels() {
        let other = AskStandingRead.Identity(model: "qwen3.6-35b-a3b", files: Self.identity.files,
                                             server: Self.identity.server, window: Self.identity.window)
        let mine = AskStandingRead.fileName(Self.identity, tokens: Self.tokens)
        let theirs = AskStandingRead.fileName(other, tokens: Self.tokens)
        #expect(mine != theirs)
        #expect(mine.hasPrefix("qwen3.8-27b-"))
        #expect(AskStandingRead.belongs(mine, to: "qwen3.8-27b"))
        #expect(!AskStandingRead.belongs(mine, to: "qwen3.6-35b-a3b"))
        #expect(!AskStandingRead.belongs(theirs, to: "qwen3.8-27b"))
    }

    @Test("A model whose name is the start of another's does not claim its files")
    func belongsIsExact() {
        let file = AskStandingRead.fileName(.init(model: "gemma-4-e4b", files: [], server: "s", window: 1), tokens: Self.tokens)
        #expect(!AskStandingRead.belongs(file, to: "gemma-4"))
        #expect(AskStandingRead.belongs(file, to: "gemma-4-e4b"))
        #expect(!AskStandingRead.belongs("notes.txt", to: "gemma-4-e4b"))
    }

    @Test("A changed prompt, a new file on disk, a new server build or another window is a new file")
    func anyChangeIsANewFile() {
        let base = AskStandingRead.fileName(Self.identity, tokens: Self.tokens)
        var changed = Self.tokens
        changed[2_000] += 1
        #expect(AskStandingRead.fileName(Self.identity, tokens: changed) != base)
        #expect(AskStandingRead.fileName(Self.identity, tokens: Array(Self.tokens.dropLast())) != base)
        let id = Self.identity
        let withDraft = AskStandingRead.Identity(model: id.model, files: id.files + ["mtp-Qwen3.8-27B-Q4_0.gguf 1680271776"],
                                                 server: id.server, window: id.window)
        #expect(AskStandingRead.fileName(withDraft, tokens: Self.tokens) != base)
        let newServer = AskStandingRead.Identity(model: id.model, files: id.files, server: "b11900-def456", window: id.window)
        #expect(AskStandingRead.fileName(newServer, tokens: Self.tokens) != base)
        let smaller = AskStandingRead.Identity(model: id.model, files: id.files, server: id.server, window: 32_768)
        #expect(AskStandingRead.fileName(smaller, tokens: Self.tokens) != base)
    }

    @Test("The file name is one the server accepts: no folders, no spaces")
    func fileNameIsPlain() {
        let name = AskStandingRead.fileName(Self.identity, tokens: Self.tokens)
        #expect(name.hasSuffix(".bin"))
        #expect(!name.contains("/"))
        #expect(!name.contains(" "))
    }

    // MARK: How many are kept

    @Test("Only the most recently used files are kept")
    func newestAreKept() {
        let now = Date()
        let files = (0..<5).map { (name: "m-\($0).bin", used: now.addingTimeInterval(Double($0))) }
        #expect(Set(AskStandingRead.toRemove(files, keeping: 3)) == ["m-0.bin", "m-1.bin"])
        #expect(AskStandingRead.toRemove(Array(files.prefix(2)), keeping: 3).isEmpty)
    }
}
