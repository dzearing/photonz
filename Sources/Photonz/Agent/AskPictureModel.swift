import Foundation
import Observation
import PhotonzCore

/// The picture model that paints Ask's drawings when "Ask paints its
/// drawings" is on (`docs/design/ask.md`, "The picture model"): Z-Image Turbo
/// behind a loopback port, which answers with the picture already traced into
/// named, filled paths. Settings > Ask sets it up and `AskPictureServer` runs
/// it; like Ask's chat model, nothing goes further than 127.0.0.1.
@MainActor
enum AskPictureModel {

    /// A picture takes about 25 seconds; a first one also loads the model.
    static let patienceSeconds: TimeInterval = 180

    struct Painted {
        let svg: String
        let model: String
        let paths: Int
        let seconds: Double
    }

    /// Whether the switch is on and the picture model is set up on this Mac.
    static func isReady() -> Bool {
        Experiments.shared.isEnabled(FeatureCatalog.askPaintsFlag) && AskPictureServer.isInstalled
    }

    /// The drawing `call` asks for, painted and traced; nil when the switch
    /// is off or the picture model is not set up, so the drawing is made the
    /// usual way instead.
    static func paint(_ call: AgentDrawingCall) async -> Result<Painted, AgentWork.Failure>? {
        guard call.svg == nil, isReady() else { return nil }
        let server = AskPictureServer.shared
        server.busy += 1
        defer {
            server.busy -= 1
            server.lastUsed = Date()
        }
        guard let port = try? await server.ready(),
              let url = AskPictureModelPlan.base(port: port)?.appending(path: "draw") else {
            return .failure(AgentWork.Failure("add_drawing: the picture model did not start."))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = patienceSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = (try? JSONEncoder().encode(PictureModelRequest(call)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        // A drawing Ask looks at and draws again gets a new picture, not the same one.
        body["seed"] = Int.random(in: 1...999_999)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let json = try? AgentJSON.parse(data) else {
            return .failure(AgentWork.Failure("add_drawing: the picture model did not answer."))
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let svg = json["svg"]?.stringValue else {
            return .failure(AgentWork.Failure("add_drawing: the picture model said \(json["error"]?.stringValue ?? "nothing")."))
        }
        return .success(Painted(svg: svg, model: AskPictureModelPlan.name, paths: Int(json["paths"]?.doubleValue ?? 0),
                                seconds: json["seconds"]?.doubleValue ?? 0))
    }
}

/// Runs the picture model's server: started the first time Ask paints, let go
/// after a few idle minutes, stopped when Photonz quits. Nobody runs a script.
@MainActor
@Observable
final class AskPictureServer {

    static let shared = AskPictureServer()

    /// Loading the model into memory: Ask says so while it waits.
    private(set) var loading = false

    @ObservationIgnored var busy = 0
    @ObservationIgnored var lastUsed = Date()
    @ObservationIgnored private var port = 0
    @ObservationIgnored private var answering = false
    @ObservationIgnored private var starting: Task<Int, Error>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private let server = AskHelperProcess(name: "picture-model") {
        $0.hasPrefix(AskPictureModelPlan.toolsFolder(in: AskModelServer.folder).resolvingSymlinksInPath().path)
    }

    enum Failure: Error {
        case notSetUp
        case wouldNotStart
    }

    static var folder: URL { AskModelServer.folder }

    /// The `uv` inside this app that builds the tools, or nil in a build that
    /// has none (a bare `swift run`).
    static var uv: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/PictureModel/uv")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var script: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Resources/PictureModel/server.py")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The weights are whole and the tools match this build's list.
    static var isInstalled: Bool { weightsAreWhole && toolsAreInstalled }

    static var weightsAreWhole: Bool {
        AskPictureModelPlan.modelFiles.allSatisfy { AskModelDownload.isWhole($0, in: folder) }
    }

    static var toolsAreInstalled: Bool {
        let stamp = try? String(contentsOf: AskPictureModelPlan.stampFile(in: folder), encoding: .utf8)
        return AskPictureModelPlan.toolsMatch(stamp: stamp)
            && FileManager.default.isExecutableFile(atPath: AskPictureModelPlan.python(in: folder).path)
    }

    /// What Settings > Ask downloads.
    static var item: AskModelDownload.Item {
        AskModelDownload.Item(id: AskPictureModelPlan.id, name: AskPictureModelPlan.name,
                              files: AskPictureModelPlan.modelFiles, totalBytes: AskPictureModelPlan.downloadBytes)
    }

    /// The download Settings > Ask starts: the weights, then the tools.
    static func download() {
        AskModelDownload.pictures.start(item) { try await installTools() }
    }

    /// Builds the tools with the `uv` this app ships: Python and exactly the
    /// packages the server imports, in the tools folder. Stopping the task
    /// stops uv.
    static func installTools() async throws {
        if toolsAreInstalled { return }
        guard let uv else { throw Failure.notSetUp }
        let tools = AskPictureModelPlan.toolsFolder(in: folder)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: AskPictureModelPlan.stampFile(in: folder))
        var environment = AskPictureModelPlan.setupEnvironment(in: folder)
        environment["HOME"] = NSHomeDirectory()
        environment["PATH"] = "/usr/bin:/bin"
        environment["TMPDIR"] = FileManager.default.temporaryDirectory.path
        let log = shared.server.logFile
        for arguments in AskPictureModelPlan.setupCommands(in: folder) {
            try await run(uv, arguments, environment: environment, log: log)
        }
        // uv's download cache is only for the install: about 400 MB.
        try? FileManager.default.removeItem(at: tools.appending(path: "cache"))
        try AskPictureModelPlan.toolsStamp.write(to: AskPictureModelPlan.stampFile(in: folder), atomically: true,
                                                 encoding: .utf8)
    }

    private static func run(_ program: URL, _ arguments: [String], environment: [String: String], log: URL) async throws {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.environment = environment
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let handle = try? FileHandle(forWritingTo: log)
        _ = try? handle?.seekToEnd()
        handle?.write(Data("\n== \(Date()) uv \(arguments.prefix(2).joined(separator: " "))\n".utf8))
        process.standardOutput = handle
        process.standardError = handle
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()
        guard status == 0 else { throw Failure.notSetUp }
    }

    /// Deletes the weights and the tools.
    static func remove() {
        shared.stop()
        try? FileManager.default.removeItem(at: AskPictureModelPlan.toolsFolder(in: folder))
        try? FileManager.default.removeItem(at: AskPictureModelPlan.modelFolder(in: folder))
    }

    /// The port of the running server, starting it if need be.
    func ready() async throws -> Int {
        if answering, server.isRunning { return port }
        if let starting { return try await starting.value }
        let task = Task { try await start() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private func start() async throws -> Int {
        stop()
        guard Self.isInstalled, let script = Self.script else { throw Failure.notSetUp }
        loading = true
        defer { loading = false }
        let port = AskPictureModelPlan.pickPort()
        var environment = AskPictureModelPlan.serverEnvironment(in: Self.folder, port: port)
        environment["HOME"] = NSHomeDirectory()
        environment["PATH"] = "/usr/bin:/bin"
        environment["TMPDIR"] = FileManager.default.temporaryDirectory.path
        try server.launch(AskPictureModelPlan.python(in: Self.folder), arguments: AskPictureModelPlan.serverArguments(script: script),
                          environment: environment, pidFolder: Self.folder, note: "starts the picture model on port \(port)")
        self.port = port
        lastUsed = Date()
        let health = AskPictureModelPlan.base(port: port)?.appending(path: "health")
        if try await server.waitUntil(seconds: 180, { await Self.loaded(health) }) {
            answering = true
            keepWatch()
            return port
        }
        stop()
        throw Failure.wouldNotStart
    }

    private static func loaded(_ url: URL?) async -> Bool {
        guard let url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? AgentJSON.parse(data) else { return false }
        return json["ready"]?.boolValue == true
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

    /// Stops the server and frees its memory.
    func stop() {
        watch?.cancel()
        watch = nil
        answering = false
        port = 0
        server.stop(pidFolder: Self.folder)
    }
}
