import Darwin
import Foundation
import PhotonzAgentLink
import PhotonzCore

/// The app's door for agents: a Unix socket in the user's Library that speaks
/// MCP, one JSON-RPC message per line (`docs/design/agent-mcp.md`).
///
/// It lives in the app, in every build, because the work has to happen in the
/// documents a person has open and land in their undo history. Nothing here
/// finds a control by name or needs a window on screen, so it works the same
/// on a locked Mac. The socket is the user's own (`0600` in their Library), so
/// only programs running as them can reach it.
///
/// Reading and writing happen on a queue per connection; the protocol is
/// answered there (`AgentMCP.handle`), and a tool call hops to the main actor
/// to be carried out (`AgentWork`).
final class AgentChannel: @unchecked Sendable {

    @MainActor private static var shared: AgentChannel?

    /// Opens the socket when the Next switch for it is on. Read once, at launch.
    @MainActor
    static func startIfEnabled(coordinator: AppCoordinator) {
        guard shared == nil, Experiments.shared.agentChannelEnabled else { return }
        AgentWork.coordinator = coordinator
        let bundleID = Bundle.main.bundleIdentifier ?? AgentChannelAddress.releaseBundleID
        let path = AgentChannelAddress.socketPath(bundleID: bundleID, home: NSHomeDirectory())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let server = AgentMCP.Server(name: "photonz", version: version)
        let channel = AgentChannel(path: path, server: server)
        guard channel.start() else { return }
        shared = channel
        // Left for the bridge, so a session with the server installed does not
        // start the app just to learn what it offers.
        let handshake = AgentChannelAddress.handshakePath(bundleID: bundleID, home: NSHomeDirectory())
        try? AgentMCP.handshake(server: server).encoded().write(to: URL(fileURLWithPath: handshake), options: .atomic)
    }

    @MainActor
    static func stop() {
        shared?.close()
        shared = nil
    }

    private let path: String
    private let server: AgentMCP.Server
    private let queue = DispatchQueue(label: "photonz.agent.listen")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    /// Held so a connection lives as long as its client stays.
    private var connections: [ObjectIdentifier: Connection] = [:]

    private init(path: String, server: AgentMCP.Server) {
        self.path = path
        self.server = server
    }

    private func start() -> Bool {
        guard path.utf8.count <= AgentChannelAddress.longestSocketPath else {
            NSLog("Photonz agent channel: socket path too long: %@", path)
            return false
        }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // Another copy of this same app already listening keeps its door: two
        // apps answering one socket would each get half the questions.
        if Self.somebodyAnswers(at: path) {
            NSLog("Photonz agent channel: another copy is already listening at %@", path)
            return false
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = Self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            NSLog("Photonz agent channel: could not listen at %@ (errno %d)", path, errno)
            Darwin.close(fd)
            return false
        }
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        acceptSource = source
        return true
    }

    private func close() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listener >= 0 { Darwin.close(listener) }
            listener = -1
            for connection in connections.values { connection.close() }
            connections = [:]
            unlink(path)
        }
    }

    /// Runs on `queue`.
    private func accept() {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return }
        // A client that goes away mid-answer must not take the app with it.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let connection = Connection(fd: fd, server: server) { [weak self] gone in
            self?.queue.async { self?.connections[ObjectIdentifier(gone)] = nil }
        }
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let bytes = Array(path.utf8.prefix(buffer.count - 1))
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    static func somebodyAnswers(at path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var address = address(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    /// One client: lines in, lines out, on a queue of its own.
    final class Connection: @unchecked Sendable {
        private let fd: Int32
        private let server: AgentMCP.Server
        private let queue = DispatchQueue(label: "photonz.agent.connection")
        private var source: DispatchSourceRead?
        private var pending = Data()
        private var isClosed = false
        private let onClose: (Connection) -> Void

        init(fd: Int32, server: AgentMCP.Server, onClose: @escaping (Connection) -> Void) {
            self.fd = fd
            self.server = server
            self.onClose = onClose
        }

        func start() {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.read() }
            source.resume()
            self.source = source
        }

        func close() {
            queue.async { self.shut() }
        }

        private func shut() {
            guard !isClosed else { return }
            isClosed = true
            source?.cancel()
            source = nil
            Darwin.close(fd)
            onClose(self)
        }

        private func read() {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { shut(); return }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[pending.startIndex..<newline]
                pending = Data(pending[pending.index(after: newline)...])
                guard !line.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\r") }) else { continue }
                handle(Data(line))
            }
        }

        private func handle(_ line: Data) {
            switch AgentMCP.handle(line: line, server: server) {
            case .nothing:
                break
            case .reply(let reply):
                send(reply)
            case .call(let id, let request):
                Task { @MainActor [weak self] in
                    let answer = await AgentWork.run(request)
                    let reply = AgentMCP.result(id: id, content: answer.content, isError: answer.isError)
                    self?.queue.async { self?.send(reply) }
                }
            }
        }

        /// Runs on `queue`. The whole line goes, however many writes it takes.
        private func send(_ reply: Data) {
            guard !isClosed else { return }
            var bytes = reply
            bytes.append(UInt8(ascii: "\n"))
            let ok = bytes.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                var sent = 0
                while sent < raw.count {
                    let wrote = Darwin.write(fd, base + sent, raw.count - sent)
                    if wrote < 0, errno == EINTR || errno == EAGAIN { continue }
                    guard wrote > 0 else { return false }
                    sent += wrote
                }
                return true
            }
            if !ok { shut() }
        }
    }
}
