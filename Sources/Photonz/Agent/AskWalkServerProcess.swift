import Darwin
import Foundation
import PhotonzCore

/// The files and the launch behind `AskWalkServer`: the one Ask model server a
/// walk run shares. It is started detached, under its own watch, so the probe
/// quitting between walks leaves it loaded for the next one; the watch, the
/// walk scripts and the go loop let it go (`Scripts/ask-walk-server.sh`).
@MainActor
enum AskWalkServerProcess {

    static var folder: URL { AskWalkServer.folder(home: URL(fileURLWithPath: NSHomeDirectory())) }
    private static var recordFile: URL { folder.appending(path: "record.json") }
    private static var pidFile: URL { folder.appending(path: "server.pid") }
    private static var lastUsedFile: URL { folder.appending(path: "last-used") }
    /// The pid of the walk run (`Scripts/playtest-all.sh`, or one
    /// `Scripts/playtest.sh` on its own) that owns the server.
    private static var runFile: URL { folder.appending(path: "run") }

    static var record: AskWalkServer.Record? {
        (try? Data(contentsOf: recordFile)).flatMap(AskWalkServer.decode)
    }

    private static var pids: AskWalkServer.Pids? {
        (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap(AskWalkServer.pids(fromPidFile:))
    }

    /// Whether the recorded server is running and really is a model server
    /// (a pid the file names may since belong to anything).
    static var alive: Bool {
        guard let pid = pids?.server, kill(pid, 0) == 0 else { return false }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        let name = String(cString: path)
        // taskpolicy for the instant before it becomes the server.
        return name.hasSuffix("/llama-server") || name.hasSuffix("/taskpolicy")
    }

    /// Resets the idle clock the watch reads.
    static func touch() {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: lastUsedFile.path)
    }

    /// Starts the shared server for `record` from `server` with `arguments`
    /// (the app's own command line), gently, and writes down what it runs.
    static func start(_ server: URL, arguments: [String], record: AskWalkServer.Record) throws {
        stop()
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try? files.removeItem(at: pidFile)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The outer shell puts the watch in the background and is gone, so
        // nothing ties the watch or the server to this app.
        process.arguments = ["-c", #"/bin/sh -c "$PHOTONZ_WALK_WATCH" walk-server "$@" </dev/null >/dev/null 2>&1 &"#,
                             "launch"] + AskWalkServer.command(server: server.path,
                                                               arguments: AskWalkServer.arguments(arguments))
        var env = ProcessInfo.processInfo.environment
        env["PHOTONZ_WALK_WATCH"] = AskWalkServer.watchScript
        env["PHOTONZ_WALK_SERVER_DIR"] = folder.path
        env["PHOTONZ_WALK_SERVER_PORT"] = String(record.port)
        env["PHOTONZ_WALK_SERVER_IDLE"] = String(Int(AskWalkServer.idleSeconds))
        env["PHOTONZ_WALK_RUN_PID"] = runPid.map(String.init) ?? ""
        process.environment = env
        if !files.fileExists(atPath: folder.appending(path: "log").path) {
            files.createFile(atPath: folder.appending(path: "log").path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: folder.appending(path: "log")) {
            _ = try? log.seekToEnd()
            log.write(Data("\n== \(Date()) Photonz \(ProcessInfo.processInfo.processIdentifier) starts the shared walk server, \(record.model) on port \(record.port), run \(runPid.map(String.init) ?? "none")\n".utf8))
            try? log.close()
        }
        try process.run()
        process.waitUntilExit()
        try AskWalkServer.encode(record).write(to: recordFile, options: .atomic)
    }

    /// The owning run's pid, when that run is still going.
    private static var runPid: Int32? {
        guard let text = try? String(contentsOf: runFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
              kill(pid, 0) == 0 else { return nil }
        return pid
    }

    /// Waits until the shared server answers, it is gone, or `seconds` pass.
    static func waitUntilAnswering(port: Int, seconds: TimeInterval) async throws -> Bool {
        let health = AskBuiltInServerPlan.base(port: port)?.appending(path: "health")
        let deadline = Date().addingTimeInterval(seconds)
        // A moment for the watch to write the pid file after the launch.
        var grace = 20
        while Date() < deadline {
            try Task.checkCancellation()
            if !alive {
                if grace <= 0 { return false }
                grace -= 1
            }
            if await AskHelperProcess.answers(health) { return true }
            try await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// Stops the shared server: its watch takes the server with it.
    static func stop() {
        guard let pids else { return }
        kill(pids.watch, SIGTERM)
        let deadline = Date().addingTimeInterval(5)
        while kill(pids.server, 0) == 0, Date() < deadline { usleep(50_000) }
        if alive { kill(pids.server, SIGKILL) }
        try? FileManager.default.removeItem(at: pidFile)
        try? FileManager.default.removeItem(at: recordFile)
    }
}
