import Darwin
import Foundation
import Observation
import PhotonzCore

/// The model server Photonz ships inside itself (`Contents/Helpers/AskModel`,
/// llama.cpp's llama-server; `docs/design/ask.md`, "The model"). Photonz
/// starts it the first time Ask needs it, lets it go after a few idle minutes,
/// and stops it when Photonz quits, so nobody installs, opens or keeps
/// anything running for Ask.
///
/// It is started through a small watch: a shell that runs the server and
/// stops it the moment Photonz is gone, so even a Photonz that crashes leaves
/// nothing behind.
@MainActor
@Observable
final class AskModelServer {

    static let shared = AskModelServer()

    /// Set by a walk's setup only (`PlaytestSetup.askModelMissing`).
    static var walkFolder: URL?

    /// Loading a model into memory: Ask says so while it waits.
    private(set) var loading = false

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var port = 0
    /// Answering: started and done loading. A request never goes to a server
    /// still loading; it waits for the load instead.
    @ObservationIgnored private var answering = false
    @ObservationIgnored private var running: String?
    @ObservationIgnored private var lastUsed = Date()
    @ObservationIgnored private var busy = 0
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var starting: Task<Int, Error>?

    enum Failure: Error {
        case notShipped
        case wouldNotStart
    }

    /// Where the downloaded models live: one folder for every build of
    /// Photonz on the Mac (release, Next, dev, probe), so a model is
    /// downloaded once. A walk that wants a Mac with nothing downloaded
    /// (`askModelMissing`) points it at an empty folder; `ask.modelsFolder`
    /// moves it by hand.
    static var folder: URL {
        if let walkFolder { return walkFolder }
        if let moved = UserDefaults.standard.string(forKey: "ask.modelsFolder"), !moved.isEmpty {
            return URL(fileURLWithPath: moved)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: "Photonz/Models")
    }

    /// The server inside this app, or nil in a build that has none (a bare
    /// `swift run`).
    static var helper: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/AskModel/llama-server")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Whether every file of `choice` is on the Mac, whole.
    static func isDownloaded(_ choice: AskBuiltInModels.Choice) -> Bool {
        choice.files.allSatisfy { file in
            let path = folder.appending(path: file.name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
            return size == file.bytes
        }
    }

    static var downloaded: [String] {
        AskBuiltInModels.ranked.filter(isDownloaded).map(\.id)
    }

    /// One turn of the chat, on `choice`, started first when it is not
    /// running. The body is Ollama's shape (`AskConversation.chatBody`) and so
    /// is the answer.
    func chat(_ body: AgentJSON, on choice: AskBuiltInModels.Choice) async throws -> AgentJSON {
        busy += 1
        defer {
            busy -= 1
            lastUsed = Date()
        }
        let port = try await ready(choice)
        guard let url = AskBuiltInServerPlan.chatURL(port: port) else { throw Failure.wouldNotStart }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = AskServerChat.body(fromOllama: body).encoded()
        request.timeoutInterval = 300
        let data: Data
        do {
            data = try await AskLocalModel.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The server went away part way (it was stopped, or it died).
            stop()
            throw Failure.wouldNotStart
        }
        return AskServerChat.reply(fromServer: try AgentJSON.parse(data))
    }

    /// Starts loading the model Ask would use, without asking it anything:
    /// a person opening Ask or typing is about to need it, and loading takes
    /// seconds. Let go again by the idle rule if nothing is asked.
    func warm() {
        guard AskLocalModel.runtime == .builtIn,
              let choice = AskBuiltInModels.resolve(chosen: AskLocalModel.builtInChosen, downloaded: Self.downloaded,
                                                    memoryGigabytes: AskLocalModel.memoryGigabytes) else { return }
        lastUsed = Date()
        Task { _ = try? await ready(choice) }
    }

    /// The port of a server running `choice`, starting one if need be.
    private func ready(_ choice: AskBuiltInModels.Choice) async throws -> Int {
        if answering, running == choice.id, let process, process.isRunning { return port }
        if let starting { return try await starting.value }
        let task = Task {
            do {
                return try await start(choice)
            } catch Failure.wouldNotStart {
                // Once more: a server that quit while loading usually met the
                // last one still giving its memory back.
                try await Task.sleep(for: .seconds(2))
                return try await start(choice)
            }
        }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private func start(_ choice: AskBuiltInModels.Choice) async throws -> Int {
        stop()
        guard let helper = Self.helper else { throw Failure.notShipped }
        Self.stopLeftover()
        loading = true
        defer { loading = false }
        let port = AskBuiltInServerPlan.pickPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The watch: run the server, and stop it when Photonz (the pid given)
        // is gone or this shell is told to stop.
        let script = """
        "$0" "$@" & s=$!
        echo "$s $PHOTONZ_PID" > "$PHOTONZ_ASK_PIDFILE"
        trap 'kill $s 2>/dev/null; wait $s; exit 0' TERM INT
        while kill -0 "$PHOTONZ_PID" 2>/dev/null && kill -0 $s 2>/dev/null; do sleep 1; done
        kill $s 2>/dev/null; wait $s
        """
        process.arguments = ["-c", script, helper.path]
            + AskBuiltInServerPlan.arguments(for: choice, in: Self.folder, port: port)
        var environment = ProcessInfo.processInfo.environment
        environment["PHOTONZ_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        environment["PHOTONZ_ASK_PIDFILE"] = Self.pidFile.path
        process.environment = environment
        let log = Self.logFile
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: log)
        _ = try? handle?.seekToEnd()
        handle?.write(Data("\n== \(Date()) Photonz \(ProcessInfo.processInfo.processIdentifier) starts \(choice.id) on port \(port)\n".utf8))
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        self.process = process
        self.port = port
        running = choice.id
        lastUsed = Date()
        // Loading a 20 GB model from disk takes seconds, more the first time.
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            try Task.checkCancellation()
            if !process.isRunning { break }
            if await Self.healthy(port: port) {
                answering = true
                keepWatch()
                return port
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        stop()
        throw Failure.wouldNotStart
    }

    private static func healthy(port: Int) async -> Bool {
        guard let url = AskBuiltInServerPlan.base(port: port)?.appending(path: "health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Lets the server go after a few minutes with nothing asked of it.
    private func keepWatch() {
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                if AskBuiltInServerPlan.isIdle(lastUsed: lastUsed, now: Date(), busy: busy) {
                    stop()
                    return
                }
            }
        }
    }

    /// Stops the server and frees its memory. Waits a moment for it to go, so
    /// a quit leaves nothing running.
    func stop() {
        watch?.cancel()
        watch = nil
        running = nil
        answering = false
        port = 0
        guard let process else { return }
        self.process = nil
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        Self.stopLeftover()
    }

    private static var pidFile: URL { folder.appending(path: ".server-\(Bundle.main.bundleIdentifier ?? "photonz").pid") }
    static var logFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Logs/Photonz/ask-model-\(Bundle.main.bundleIdentifier ?? "photonz").log")
    }

    /// A server left running by a Photonz that is gone (the watch was killed
    /// along with it), or by this one: stopped, if it really is the helper.
    /// A server another running Photonz of the same build owns is left alone:
    /// one quitting while the next starts must not stop the new one's.
    static func stopLeftover() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return }
        let fields = text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        guard let pid = fields.first, pid > 0 else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        if let owner = fields.dropFirst().first, owner != me, kill(owner, 0) == 0 { return }
        try? FileManager.default.removeItem(at: pidFile)
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(cString: path).hasSuffix("Helpers/AskModel/llama-server") else { return }
        kill(pid, SIGTERM)
    }
}
