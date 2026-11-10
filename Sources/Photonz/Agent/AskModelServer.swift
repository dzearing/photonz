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
    /// Set by a walk's setup only, with `walkFolder`: the Mac's own models
    /// folder, which a download in the walk clones a file from when it is
    /// there, so a walk that presses Download is done in a second.
    static var walkSource: URL?
    /// Set by a walk's setup only: this walk shares the run's one model
    /// server (`AskWalkServer`) instead of loading its own.
    static var walkShares = false

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
    /// Running on the walk run's shared server, which this app neither
    /// started for itself nor stops (`AskWalkServer`).
    @ObservationIgnored private var shared = false
    @ObservationIgnored private var lastUsed = Date()
    @ObservationIgnored private var busy = 0
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var starting: Task<Int, Error>?

    enum Failure: Error {
        case notShipped
        case wouldNotStart
        /// It was still answering when the turn's time ran out.
        case tooSlow
    }

    /// Where the downloaded models live: one folder for every build of
    /// Photonz on the Mac (release, Next, dev, probe), so a model is
    /// downloaded once. A walk that wants a Mac with nothing downloaded
    /// (`askModelMissing`) points it at an empty folder; `ask.modelsFolder`
    /// moves it by hand.
    /// The window the server is started with and Ask plans to: the bigger
    /// one on a Mac with room for it (`AskConversation.contextWindow(memoryGigabytes:)`).
    static var window: Int { AskLocalModel.window }

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

    /// Whether every file `choice` cannot run without is on the Mac, whole.
    static func isDownloaded(_ choice: AskBuiltInModels.Choice) -> Bool {
        choice.needed.allSatisfy(isWhole)
    }

    static func isWhole(_ file: AskBuiltInModels.File) -> Bool {
        let path = folder.appending(path: file.name).path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        return size == file.bytes
    }

    /// Takes `choice`'s files off the Mac (Settings' Delete), stopping the
    /// server first if it is the one running.
    func delete(_ choice: AskBuiltInModels.Choice) {
        if running == choice.id { stop() }
        // Its saved reads are no use without it (`AskStandingRead`).
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Self.readsFolder.path)) ?? []
        where AskStandingRead.belongs(name, to: choice.id) {
            try? FileManager.default.removeItem(at: Self.readsFolder.appending(path: name))
        }
        for file in choice.files {
            try? FileManager.default.removeItem(at: Self.folder.appending(path: file.name))
        }
        // A model kept in a folder of its own takes the folder too, once empty.
        for folder in Set(choice.files.map { ($0.name as NSString).deletingLastPathComponent }) where !folder.isEmpty {
            let url = Self.folder.appending(path: folder)
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static var downloaded: [String] {
        AskBuiltInModels.ranked.filter(isDownloaded).map(\.id)
    }

    /// One turn of the chat, on `choice`, started first when it is not
    /// running. The body is Ollama's shape (`AskConversation.chatBody`) and so
    /// is the answer.
    /// `standing` is the first request's start that is the same every time
    /// (`AskConversation.standingBody`), given on a request's first turn
    /// only: it is restored from its saved read, or read and saved, before
    /// the request goes (`AskStandingRead`). `said` hears a line for the trace.
    func chat(_ body: AgentJSON, on choice: AskBuiltInModels.Choice, standing: AgentJSON? = nil,
              said: ((String) -> Void)? = nil) async throws -> AgentJSON {
        busy += 1
        defer {
            busy -= 1
            lastUsed = Date()
            if shared { AskWalkServerProcess.touch() }
        }
        let port = try await ready(choice)
        if let standing, let line = await standingRead(standing, before: body, on: choice, port: port) { said?(line) }
        guard let url = AskBuiltInServerPlan.chatURL(port: port) else { throw Failure.wouldNotStart }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = AskTools.wireEncoded(AskServerChat.body(fromOllama: body))
        request.timeoutInterval = AskLocalModel.chatSeconds
        let data: Data
        do {
            data = try await AskLocalModel.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch AskLocalModel.Trouble.tooSlow {
            // Still answering when the turn ran out: stopped, so it gives its
            // memory and the next request a clean start.
            if shared { AskWalkServerProcess.stop() }
            stop()
            throw Failure.tooSlow
        } catch {
            // The server went away part way (it was stopped, or it died). A
            // shared one that stopped answering is no use to the next walk either.
            if shared { AskWalkServerProcess.stop() }
            stop()
            throw Failure.wouldNotStart
        }
        let reply = try AgentJSON.parse(data)
        if let timings = reply["timings"], let read = timings["prompt_n"]?.doubleValue {
            said?("the model read \(Int(read)) new tokens (\(Int(timings["cache_n"]?.doubleValue ?? 0)) it had already)")
        }
        return AskServerChat.reply(fromServer: reply)
    }

    /// Where the server saves what it has read (`AskStandingRead`): one
    /// folder for every build of Photonz on the Mac, like the models, in
    /// Caches since any of it can be read again.
    static var readsFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Caches")
        return caches.appending(path: "Photonz/AskReads")
    }

    /// The server's own build, by port, for the saved reads' names.
    @ObservationIgnored private var builds: [Int: String] = [:]

    /// Puts the standing part of `body` in the server's memory: restored from
    /// its saved read when there is one, otherwise read now and saved for
    /// next time. The request then reads only what follows it. Nil when there
    /// was nothing to do; otherwise one line for the trace. Anything that
    /// fails leaves the request to read it all, as before.
    private func standingRead(_ standing: AgentJSON, before body: AgentJSON, on choice: AskBuiltInModels.Choice,
                              port: Int) async -> String? {
        guard let base = AskBuiltInServerPlan.base(port: port) else { return nil }
        let started = Date()
        func seconds() -> String { String(format: "%.1f", Date().timeIntervalSince(started)) }
        // The picture comes after the rules, so it is left out of the count.
        var words = body
        if case .object(var object) = body, let messages = object["messages"]?.arrayValue {
            object["messages"] = .array(messages.map { message in
                guard case .object(var fields) = message else { return message }
                fields["images"] = nil
                return .object(fields)
            })
            words = .object(object)
        }
        guard let request = await tokens(of: words, base), let start = await tokens(of: standing, base) else {
            return "standing read: the server could not count it"
        }
        let shared = AskStandingRead.shared(request, start)
        guard AskStandingRead.worthSaving(shared) else { return nil }
        guard let build = await build(base, port: port) else { return "standing read: the server did not say its build" }
        let draft = choice.draft.flatMap { Self.isWhole($0) ? $0 : nil }
        let files = ([choice.model] + (choice.eyes.map { [$0] } ?? []) + (draft.map { [$0] } ?? [])).map { "\($0.name) \($0.bytes)" }
        let name = AskStandingRead.fileName(.init(model: choice.id, files: files, server: build, window: Self.window), tokens: shared)
        let file = Self.readsFolder.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path) {
            let restored = await post(base.appending(path: "slots/0").appending(queryItems: [.init(name: "action", value: "restore")]),
                                      ["filename": .string(name)])
            if restored?["n_restored"]?.doubleValue.map({ Int($0) }) == shared.count {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
                return "restored the standing read (\(shared.count) tokens) in \(seconds()) s"
            }
            // Unreadable to this server: read it again below, and save it over.
            try? FileManager.default.removeItem(at: file)
        }
        guard Task.isCancelled == false,
              await post(base.appending(path: "completion"),
                         ["prompt": .array(shared.map { .number(Double($0)) }), "n_predict": 0, "cache_prompt": true],
                         seconds: AskLocalModel.chatSeconds) != nil else {
            return "standing read: the server would not read it"
        }
        let read = seconds()
        try? FileManager.default.createDirectory(at: Self.readsFolder, withIntermediateDirectories: true)
        let saved = await post(base.appending(path: "slots/0").appending(queryItems: [.init(name: "action", value: "save")]),
                               ["filename": .string(name)], seconds: 60)
        Self.keepRecentReads()
        return saved?["n_saved"] == nil
            ? "read the standing part (\(shared.count) tokens) in \(read) s; the server would not save it"
            : "read the standing part (\(shared.count) tokens) in \(read) s and saved it"
    }

    /// The tokens the server makes of `body` (Ollama's shape), as its chat
    /// would: through its chat template, then its tokenizer.
    private func tokens(of body: AgentJSON, _ base: URL) async -> [Int]? {
        guard let prompt = await post(base.appending(path: "apply-template"), AskServerChat.body(fromOllama: body))?["prompt"]?.stringValue,
              let answer = await post(base.appending(path: "tokenize"),
                                      ["content": .string(prompt), "add_special": true, "parse_special": true]) else { return nil }
        return AskStandingRead.tokens(fromTokenize: answer)
    }

    private func build(_ base: URL, port: Int) async -> String? {
        if let known = builds[port] { return known }
        var request = URLRequest(url: base.appending(path: "props"))
        request.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let props = try? AgentJSON.parse(data), let build = props["build_info"]?.stringValue, !build.isEmpty else { return nil }
        builds[port] = build
        return build
    }

    /// One POST to the server, its answer, or nil when it failed. Stop
    /// cancels it.
    private func post(_ url: URL, _ json: AgentJSON, seconds: TimeInterval = 30) async -> AgentJSON? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = AskTools.wireEncoded(json)
        request.timeoutInterval = seconds
        guard let data = try? await AskLocalModel.send(request), let answer = try? AgentJSON.parse(data),
              answer["error"] == nil else { return nil }
        return answer
    }

    /// Takes all but the most recently used saved reads off the Mac.
    private static func keepRecentReads() {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: readsFolder.path) else { return }
        let reads = names.filter { $0.hasSuffix(".\(AskStandingRead.fileExtension)") }.map { name in
            (name: name, used: ((try? files.attributesOfItem(atPath: readsFolder.appending(path: name).path))?[.modificationDate] as? Date) ?? .distantPast)
        }
        for name in AskStandingRead.toRemove(reads) { try? files.removeItem(at: readsFolder.appending(path: name)) }
    }

    /// How far the server has got with the request it is answering, from
    /// its `/slots`; nil when it is not answering one, or cannot say.
    func progress() async -> AskModelProgress? {
        guard answering, port != 0, let url = AskBuiltInServerPlan.base(port: port)?.appending(path: "slots") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? AgentJSON.parse(data) else { return nil }
        return AskModelProgress(slots: json)
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
        if answering, running == choice.id, shared ? AskWalkServerProcess.alive : server.isRunning { return port }
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
        try? FileManager.default.createDirectory(at: Self.readsFolder, withIntermediateDirectories: true)
        loading = true
        defer { loading = false }
        let draftOnDisk = choice.draft.map(Self.isWhole) ?? false
        let window = Self.window
        switch AskWalkServer.use(walkShares: Self.walkShares, model: choice.id, folder: Self.folder.path,
                                 record: AskWalkServerProcess.record, serverAlive: AskWalkServerProcess.alive,
                                 window: window) {
        case .own:
            break
        case .adopt(let port):
            return try await share(choice, port: port)
        case .start:
            let port = AskBuiltInServerPlan.pickPort()
            try AskWalkServerProcess.start(helper, arguments: AskBuiltInServerPlan.arguments(
                for: choice, in: Self.folder, port: port, draftOnDisk: draftOnDisk, window: window, reads: Self.readsFolder),
                record: .init(model: choice.id, port: port, folder: Self.folder.path, draft: draftOnDisk, window: window))
            return try await share(choice, port: port)
        }
        let port = AskBuiltInServerPlan.pickPort()
        try server.launch(helper, arguments: AskBuiltInServerPlan.arguments(for: choice, in: Self.folder, port: port,
                                                                            draftOnDisk: draftOnDisk, window: window,
                                                                            reads: Self.readsFolder),
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

    /// Uses the walk run's shared server on `port`, waiting for it to finish
    /// loading when the walk before started it.
    private func share(_ choice: AskBuiltInModels.Choice, port: Int) async throws -> Int {
        shared = true
        self.port = port
        running = choice.id
        lastUsed = Date()
        AskWalkServerProcess.touch()
        if try await AskWalkServerProcess.waitUntilAnswering(port: port, seconds: 240) {
            answering = true
            keepWatch()
            return port
        }
        AskWalkServerProcess.stop()
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
    /// A shared walk server is only let go of here, never stopped: the next
    /// walk is about to use it, and its own watch stops it.
    func stop() {
        watch?.cancel()
        watch = nil
        running = nil
        answering = false
        port = 0
        shared = false
        server.stop(pidFolder: Self.folder)
    }

    static var logFile: URL { shared.server.logFile }
}
