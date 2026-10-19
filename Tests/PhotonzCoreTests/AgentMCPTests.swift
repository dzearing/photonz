import Foundation
import PhotonzAgentLink
import PhotonzCore
import Testing

/// The app speaks MCP itself, one JSON-RPC message per line, over its own
/// socket (`docs/design/agent-mcp.md`). These pin the handshake, the tool list
/// and the shape of an answer, so any MCP client can talk to it.
@Suite("Agent channel: MCP over JSON-RPC")
struct AgentMCPTests {

    static let server = AgentMCP.Server(name: "photonz", version: "1.2.3")

    static func reply(_ line: String) throws -> AgentJSON {
        guard case .reply(let data) = AgentMCP.handle(line: Data(line.utf8), server: server) else {
            Issue.record("expected a reply to \(line)")
            return .null
        }
        #expect(!data.contains(UInt8(ascii: "\n")), "an answer must be one line")
        return try AgentJSON.parse(data)
    }

    @Test("initialize answers with the tools capability and the client's protocol version")
    func initialize() throws {
        let answer = try Self.reply(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#)
        #expect(answer["jsonrpc"]?.stringValue == "2.0")
        #expect(answer["id"] == .number(1))
        let result = answer["result"]
        #expect(result?["protocolVersion"]?.stringValue == "2025-03-26")
        #expect(result?["capabilities"]?["tools"] != nil)
        #expect(result?["serverInfo"]?["name"]?.stringValue == "photonz")
        let instructions = result?["instructions"]?.stringValue ?? ""
        #expect(instructions.isEmpty == false)
    }

    @Test("A protocol version the app does not know is answered with its own")
    func unknownVersion() throws {
        let answer = try Self.reply(#"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect(answer["id"] == .string("a"))
        #expect(answer["result"]?["protocolVersion"]?.stringValue == AgentMCP.latestProtocolVersion)
    }

    @Test("tools/list lists every tool with its schema")
    func toolsList() throws {
        let answer = try Self.reply(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = answer["result"]?["tools"]?.arrayValue ?? []
        #expect(tools.compactMap { $0["name"]?.stringValue } == AgentTools.all.map(\.name))
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"]?.stringValue == "object" })
    }

    @Test("A notification gets no answer, and ping gets an empty one")
    func notificationsAndPing() throws {
        let line = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        #expect(AgentMCP.handle(line: line, server: Self.server) == .nothing)
        let ping = try Self.reply(#"{"jsonrpc":"2.0","id":9,"method":"ping"}"#)
        #expect(ping["result"] == .object([:]))
    }

    @Test("tools/call with good arguments is handed to the app to answer")
    func call() {
        let line = Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"video_frame","arguments":{"seconds":10}}}"#.utf8)
        #expect(AgentMCP.handle(line: line, server: Self.server)
                == .call(id: .number(7), request: .videoFrame(document: nil, atMS: 10_000, region: nil,
                                                               maxSize: AgentTools.defaultMaxSize)))
    }

    @Test("tools/call with bad arguments is answered as a tool error the model can read")
    func badArguments() throws {
        let answer = try Self.reply(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"undo","arguments":{"steps":"x"}}}"#)
        #expect(answer["result"]?["isError"] == .bool(true))
        #expect(answer["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue?.contains("steps") == true)
    }

    @Test("An unknown tool, an unknown method and a broken line are protocol errors")
    func protocolErrors() throws {
        let tool = try Self.reply(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"nope"}}"#)
        #expect(tool["error"]?["code"] == .number(-32602))
        let method = try Self.reply(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)
        #expect(method["error"]?["code"] == .number(-32601))
        let broken = try Self.reply("{not json")
        #expect(broken["error"]?["code"] == .number(-32700))
        #expect(broken["id"] == .null)
    }

    @Test("A tool answer carries text and pictures as MCP content")
    func resultShape() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let data = AgentMCP.result(id: .number(5), content: [.text("hello"), .png(png)], isError: false)
        let answer = try AgentJSON.parse(data)
        let content = answer["result"]?["content"]?.arrayValue ?? []
        #expect(content.count == 2)
        #expect(content[0]["type"]?.stringValue == "text")
        #expect(content[0]["text"]?.stringValue == "hello")
        #expect(content[1]["type"]?.stringValue == "image")
        #expect(content[1]["mimeType"]?.stringValue == "image/png")
        #expect(content[1]["data"]?.stringValue == png.base64EncodedString())
        #expect(answer["result"]?["isError"] == nil)
    }

    @Test("The handshake left for the bridge is what the app answers itself")
    func handshake() throws {
        let saved = AgentMCP.handshake(server: Self.server)
        let answer = try Self.reply(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(AgentMCP.latestProtocolVersion)"}}"#)
        #expect(saved["initialize"] == answer["result"])
        let tools = try Self.reply(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(saved["tools"] == tools["result"])
        #expect(saved["protocolVersions"]?.arrayValue?.compactMap(\.stringValue) == AgentMCP.protocolVersions)
    }

    @Test("Whole-number ids go back as whole numbers")
    func idsRoundTrip() throws {
        let data = AgentMCP.result(id: .number(42), content: [.text("x")], isError: false)
        #expect(String(decoding: data, as: UTF8.self).contains(#""id":42"#))
    }
}

/// Where each build of the app listens, so release, Dev and Probe never answer
/// for each other.
@Suite("Agent channel: the socket each app listens on")
struct AgentChannelAddressTests {

    @Test("Each bundle has its own socket in the user's Library")
    func perBundle() {
        let home = "/Users/someone"
        let probe = AgentChannelAddress.socketPath(bundleID: "com.dzearing.photonz.probe", home: home)
        #expect(probe == "/Users/someone/Library/Application Support/Photonz/Agent/probe.sock")
        #expect(AgentChannelAddress.socketPath(bundleID: "com.dzearing.photonz.dev", home: home).hasSuffix("/dev.sock"))
        #expect(AgentChannelAddress.socketPath(bundleID: "com.dzearing.photonz", home: home).hasSuffix("/release.sock"))
        #expect(AgentChannelAddress.socketPath(bundleID: "com.example.other", home: home).hasSuffix("/com.example.other.sock"))
    }

    @Test("The handshake file sits beside the socket")
    func handshakeFile() {
        #expect(AgentChannelAddress.handshakePath(bundleID: "com.dzearing.photonz.probe", home: "/Users/x")
                == "/Users/x/Library/Application Support/Photonz/Agent/probe.json")
    }

    @Test("A socket path fits the 104 bytes a Unix socket address holds, for a long home folder too")
    func fits() {
        let home = "/Users/a-rather-long-user-name"
        let path = AgentChannelAddress.socketPath(bundleID: "com.dzearing.photonz.probe", home: home)
        #expect(path.utf8.count <= AgentChannelAddress.longestSocketPath)
    }

    @Test("A go loop runner that names no app is sent to the probe, never the Dev app")
    func runnersGetTheProbe() {
        #expect(AgentChannelAddress.choice(environment: ["GO_LOOP_PID": "123"]) == "probe")
        #expect(AgentChannelAddress.choice(environment: ["GO_LOOP_PID": "123", "PHOTONZ_APP": "release"]) == "release")
        #expect(AgentChannelAddress.choice(environment: [:]) == nil)
        #expect(AgentChannelAddress.choice(environment: ["PHOTONZ_APP": " "]) == nil)
    }

    @Test("PHOTONZ_APP picks the app; unset, Dev then release then Probe")
    func choosing() {
        #expect(AgentChannelAddress.candidates(for: "probe") == ["com.dzearing.photonz.probe"])
        #expect(AgentChannelAddress.candidates(for: "dev") == ["com.dzearing.photonz.dev"])
        #expect(AgentChannelAddress.candidates(for: "release") == ["com.dzearing.photonz"])
        #expect(AgentChannelAddress.candidates(for: "com.example.x") == ["com.example.x"])
        #expect(AgentChannelAddress.candidates(for: nil)
                == ["com.dzearing.photonz.dev", "com.dzearing.photonz", "com.dzearing.photonz.probe"])
        #expect(AgentChannelAddress.candidates(for: "") == AgentChannelAddress.candidates(for: nil))
    }
}
