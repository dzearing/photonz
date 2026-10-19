import Foundation

/// What a tool answers with: words, and pictures the model can see.
public enum AgentContent: Hashable, Sendable {
    case text(String)
    case png(Data)

    var json: AgentJSON {
        switch self {
        case .text(let text): ["type": "text", "text": .string(text)]
        case .png(let data): ["type": "image", "mimeType": "image/png", "data": .string(data.base64EncodedString())]
        }
    }
}

/// The app's side of MCP: JSON-RPC 2.0, one message per line, over the socket
/// the app listens on (`docs/design/agent-mcp.md`).
///
/// Everything the protocol answers by itself (the handshake, the tool list,
/// malformed lines, bad arguments) is answered here; a checked tool call is
/// handed back for the app to carry out and answer with `result`.
public enum AgentMCP {

    /// The versions this server speaks. A client asking for one of them gets
    /// it back; any other gets the newest.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static var latestProtocolVersion: String { protocolVersions[0] }

    public struct Server: Hashable, Sendable {
        public let name: String
        public let version: String
        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    /// What to do with a line that came in.
    public enum Step: Hashable, Sendable {
        /// Send this line back.
        case reply(Data)
        /// Carry out this request and answer `id` with `result`.
        case call(id: AgentJSON, request: AgentRequest)
        /// A notification: nothing to say.
        case nothing
    }

    /// Read to the model once, when it connects: how the tools fit together.
    public static let instructions = """
        Photonz is the picture and video editor open on this Mac. These tools work in the documents \
        open in it, live, in the same undo history as a person's clicks. Start with list_documents \
        (or open_document), read_document for the structure, and render_picture, video_frame or \
        contact_sheet to see it. Look again after each meaningful step. undo takes a step back.
        """

    public static func handle(line: Data, server: Server) -> Step {
        guard let message = try? AgentJSON.parse(line), message.objectValue != nil else {
            return .reply(error(id: .null, code: -32700, message: "That line is not a JSON object."))
        }
        guard let method = message["method"]?.stringValue else {
            // A response from the client to a request we never make.
            return .nothing
        }
        guard let id = message["id"] else { return .nothing }
        let params = message["params"]
        switch method {
        case "initialize":
            let asked = params?["protocolVersion"]?.stringValue ?? ""
            let version = protocolVersions.contains(asked) ? asked : latestProtocolVersion
            return .reply(response(id: id, result: initializeResult(server: server, version: version)))
        case "ping":
            return .reply(response(id: id, result: .object([:])))
        case "tools/list":
            return .reply(response(id: id, result: toolsListResult))
        case "tools/call":
            guard let name = params?["name"]?.stringValue else {
                return .reply(error(id: id, code: -32602, message: "tools/call needs a tool name."))
            }
            switch AgentTools.request(tool: name, arguments: params?["arguments"]) {
            case .success(let request):
                return .call(id: id, request: request)
            case .failure(let failure) where failure.isUnknownTool:
                return .reply(error(id: id, code: -32602, message: failure.message))
            case .failure(let failure):
                return .reply(result(id: id, content: [.text(failure.message)], isError: true))
            }
        default:
            return .reply(error(id: id, code: -32601, message: "Photonz does not answer \(method)."))
        }
    }

    public static func initializeResult(server: Server, version: String) -> AgentJSON {
        ["protocolVersion": .string(version),
         "capabilities": ["tools": ["listChanged": false]],
         "serverInfo": ["name": .string(server.name), "version": .string(server.version)],
         "instructions": .string(instructions)]
    }

    public static var toolsListResult: AgentJSON { ["tools": .array(AgentTools.all.map(\.listing))] }

    /// What the app leaves beside its socket so the bridge can answer the
    /// handshake and the tool list while the app is not running, and start it
    /// only when a tool is called. Without it, every agent session that merely
    /// has the server installed would launch Photonz the moment it opened.
    public static func handshake(server: Server) -> AgentJSON {
        ["protocolVersions": .array(protocolVersions.map(AgentJSON.string)),
         "initialize": initializeResult(server: server, version: latestProtocolVersion),
         "tools": toolsListResult]
    }

    /// A tool's answer.
    public static func result(id: AgentJSON, content: [AgentContent], isError: Bool) -> Data {
        var result: [String: AgentJSON] = ["content": .array(content.map(\.json))]
        if isError { result["isError"] = true }
        return response(id: id, result: .object(result))
    }

    public static func error(id: AgentJSON, code: Int, message: String) -> Data {
        let reply: AgentJSON = ["jsonrpc": "2.0", "id": id,
                                "error": ["code": .number(Double(code)), "message": .string(message)]]
        return reply.encoded()
    }

    static func response(id: AgentJSON, result: AgentJSON) -> Data {
        let reply: AgentJSON = ["jsonrpc": "2.0", "id": id, "result": result]
        return reply.encoded()
    }
}
