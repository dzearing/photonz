import Foundation
import Observation
import PhotonzCore

/// The model server Photonz ships inside itself (`Contents/Helpers/AskModel`,
/// llama.cpp's llama-server; `docs/design/ask.md`, "The model"). Photonz
/// starts it the first time Ask needs it, lets it go after a few idle minutes,
/// and stops it when Photonz quits, so nobody installs, opens or keeps
/// anything running for Ask.
///
/// It runs under `AskHelperProcess`'s watch, so even a Photonz that crashes
/// leaves nothing behind.
@MainActor
@Observable
final class AskModelServer {

    static let shared = AskModelServer()

    /// Set by a walk's setup only (`PlaytestSetup.askModelMissing`).
    static var walkFolder: URL?

    /// Loading a model into memory: Ask says so while it waits.
    private(set) var loading = false

    @ObservationIgnored private let server = AskHelperProcess(name: "ask-model") {
        $0.hasSuffix("Helpers/AskModel/llama-server")
    }
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
        if answering, running == choice.id, server.isRunning { return port }
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
        loading = true
        defer { loading = false }
        let port = AskBuiltInServerPlan.pickPort()
        try server.launch(helper, arguments: AskBuiltInServerPlan.arguments(for: choice, in: Self.folder, port: port),
                          environment: nil, pidFolder: Self.folder, note: "starts \(choice.id) on port \(port)")
        self.port = port
        running = choice.id
        lastUsed = Date()
        // Loading a 20 GB model from disk takes seconds, more the first time.
        let health = AskBuiltInServerPlan.base(port: port)?.appending(path: "health")
        if try await server.waitUntil(seconds: 240, { await AskHelperProcess.answers(health) }) {
            answering = true
            keepWatch()
            return port
        }
        stop()
        throw Failure.wouldNotStart
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
        server.stop(pidFolder: Self.folder)
    }

    static var logFile: URL { shared.server.logFile }
}
