import Darwin
import Foundation
import PhotonzAgentLink

// The MCP bridge (`docs/design/agent-mcp.md`). An agent's MCP client runs this
// and talks to it over stdin and stdout; it finds the Photonz that is running
// (launching it in the background if none is), and copies each line to the
// app's socket and each answer back. The app does all the speaking: this knows
// nothing about tools.
//
//   PHOTONZ_APP       release, dev, probe or a bundle id. Unset: the first one
//                     running of Dev, release, Probe; with none running, the
//                     release app if installed, else Dev. Unset inside a go
//                     loop runner (GO_LOOP_PID): the probe, always.
//   PHOTONZ_APP_PATH  the app bundle to launch when none is running, when
//                     LaunchServices cannot find it by bundle id.
//
// Nothing but protocol goes to stdout; what it has to say goes to stderr.

final class Bridge: @unchecked Sendable {
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var socket: Int32 = -1
    /// Requests sent to the app and not yet answered, by their id as JSON.
    private var waiting: Set<String> = []
    private let candidates: [String]
    private let home = NSHomeDirectory()
    private let launchPath = ProcessInfo.processInfo.environment["PHOTONZ_APP_PATH"]
    private let choice = AgentChannelAddress.choice(environment: ProcessInfo.processInfo.environment)

    static let launchPatience: TimeInterval = 25

    init() {
        candidates = AgentChannelAddress.candidates(for: choice)
    }

    func say(_ words: String) {
        FileHandle.standardError.write(Data("photonz-mcp: \(words)\n".utf8))
    }

    // MARK: Reaching the app

    private func connect(to path: String) -> Int32? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let bytes = Array(path.utf8.prefix(buffer.count - 1))
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { Darwin.close(fd); return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    private func connectToAny() -> Int32? {
        for bundleID in candidates {
            if let fd = connect(to: AgentChannelAddress.socketPath(bundleID: bundleID, home: home)) { return fd }
        }
        return nil
    }

    private func launch() -> Bool {
        var attempts: [[String]] = []
        if let launchPath, !launchPath.isEmpty { attempts.append(["-g", "-a", launchPath]) }
        // Unset, the shipping app is the one to start; else whatever was asked for.
        let order = (choice ?? "").isEmpty
            ? [AgentChannelAddress.releaseBundleID, AgentChannelAddress.devBundleID] : candidates
        attempts += order.map { ["-g", "-b", $0] }
        for arguments in attempts {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = arguments
            open.standardOutput = FileHandle.nullDevice
            open.standardError = FileHandle.nullDevice
            guard (try? open.run()) != nil else { continue }
            open.waitUntilExit()
            if open.terminationStatus == 0 {
                say("launched Photonz (open \(arguments.joined(separator: " ")))")
                return true
            }
        }
        return false
    }

    /// The socket to the app, connecting (and launching) as needed. Holds the lock.
    private func ensureConnected() -> Int32? {
        if socket >= 0 { return socket }
        if let fd = connectToAny() { return adopt(fd) }
        guard launch() else { return nil }
        let deadline = Date().addingTimeInterval(Self.launchPatience)
        while Date() < deadline {
            if let fd = connectToAny() { return adopt(fd) }
            usleep(200_000)
        }
        return nil
    }

    private func adopt(_ fd: Int32) -> Int32 {
        socket = fd
        let thread = Thread { [weak self] in self?.readAnswers(from: fd) }
        thread.start()
        return fd
    }

    private var notListening: String {
        "Photonz is not listening for agents. Check that Photonz is installed and running the Next release with "
            + "\"Agents can work in Photonz\" on in its Experiments window (it takes effect at the next launch)."
    }

    // MARK: Lines

    private func idKey(_ id: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func writeOut(_ line: String) {
        writeLock.lock()
        defer { writeLock.unlock() }
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private func answerWithError(_ idKey: String, _ message: String) {
        let text = (try? JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\"error\""
        writeOut(#"{"jsonrpc":"2.0","id":\#(idKey),"error":{"code":-32000,"message":\#(text)}}"#)
    }

    /// The handshake the app left beside its socket, for the first app asked
    /// for that has left one.
    private func savedHandshake() -> [String: Any]? {
        for bundleID in candidates {
            let path = AgentChannelAddress.handshakePath(bundleID: bundleID, home: home)
            if let data = FileManager.default.contents(atPath: path),
               let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                return saved
            }
        }
        return nil
    }

    /// The handshake, the tool list and a ping answered without the app, so a
    /// session that has the server installed starts Photonz only when it
    /// calls a tool. Nil when the app has never left a handshake to answer from.
    private func answeredHere(_ method: String, id: String, params: [String: Any]?) -> String? {
        var result: Any
        switch method {
        case "ping":
            result = [String: Any]()
        case "initialize":
            guard let saved = savedHandshake(), var initialize = saved["initialize"] as? [String: Any] else { return nil }
            if let asked = params?["protocolVersion"] as? String,
               (saved["protocolVersions"] as? [String])?.contains(asked) == true {
                initialize["protocolVersion"] = asked
            }
            result = initialize
        case "tools/list":
            guard let tools = savedHandshake()?["tools"] else { return nil }
            result = tools
        default:
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) else { return nil }
        return #"{"jsonrpc":"2.0","id":\#(id),"result":\#(String(decoding: data, as: UTF8.self))}"#
    }

    /// One line from the client: to the app, or answered here when the app
    /// cannot be reached.
    func forward(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        let method = message?["method"] as? String
        let id = method != nil ? message?["id"].flatMap(idKey) : nil
        // A running app answers everything. A closed one is started only for a
        // tool call, or when there is nothing saved to answer the rest from.
        lock.lock()
        if socket < 0, let fd = connectToAny() { _ = adopt(fd) }
        let connected = socket >= 0
        lock.unlock()
        if !connected, let method {
            guard let id else { return } // a notification for an app that is not there
            if let reply = answeredHere(method, id: id, params: message?["params"] as? [String: Any]) {
                writeOut(reply)
                return
            }
        }
        lock.lock()
        guard let fd = ensureConnected() else {
            lock.unlock()
            if let id { answerWithError(id, notListening) }
            say(notListening)
            return
        }
        if let id { waiting.insert(id) }
        lock.unlock()
        if !send(line, on: fd) {
            dropped(fd)
            // Once more, in case the app was restarted under us.
            lock.lock()
            let again = ensureConnected()
            lock.unlock()
            if let again, send(line, on: again) { return }
            if let id {
                lock.lock()
                waiting.remove(id)
                lock.unlock()
                answerWithError(id, notListening)
            }
        }
    }

    private func send(_ line: String, on fd: Int32) -> Bool {
        let bytes = Array((line + "\n").utf8)
        var sent = 0
        while sent < bytes.count {
            let wrote = bytes.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress! + sent, bytes.count - sent) }
            if wrote < 0, errno == EINTR { continue }
            guard wrote > 0 else { return false }
            sent += wrote
        }
        return true
    }

    /// The app went away: every question it had not answered is answered here.
    private func dropped(_ fd: Int32) {
        lock.lock()
        guard socket == fd else { lock.unlock(); return }
        Darwin.close(fd)
        socket = -1
        let orphans = waiting
        waiting = []
        lock.unlock()
        for id in orphans {
            answerWithError(id, "Photonz quit before it answered. Ask again and it will be started.")
        }
    }

    /// The client has stopped asking: wait for what it already asked.
    func finishAnswering(within seconds: TimeInterval = 120) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            lock.lock()
            let done = waiting.isEmpty
            lock.unlock()
            if done { return }
            usleep(50_000)
        }
    }

    private func readAnswers(from fd: Int32) {
        var pending = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[0..<newline], as: UTF8.self)
                pending.removeSubrange(0...newline)
                if let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                   message["method"] == nil, let id = message["id"].flatMap(idKey) {
                    lock.lock()
                    waiting.remove(id)
                    lock.unlock()
                }
                writeOut(line)
            }
        }
        dropped(fd)
    }
}

signal(SIGPIPE, SIG_IGN)
let bridge = Bridge()
while let line = readLine(strippingNewline: true) {
    bridge.forward(line)
}
bridge.finishAnswering()
exit(0)
