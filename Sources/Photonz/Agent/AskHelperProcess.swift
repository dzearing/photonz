import Darwin
import Foundation

/// One program Photonz runs for Ask behind a loopback port (the chat model's
/// server, the picture model's): started through a small watch, a shell that
/// runs it and stops it the moment Photonz is gone, so even a Photonz that
/// crashes leaves nothing behind. Its output goes to
/// `~/Library/Logs/Photonz/<name>-<bundle id>.log`.
@MainActor
final class AskHelperProcess {

    /// "ask-model", "picture-model": names the log and the pid file.
    let name: String
    /// Whether a running program at this path is this helper, so a pid left
    /// in the file by a gone Photonz never stops anything else.
    private let isOurs: (String) -> Bool

    private(set) var process: Process?

    init(name: String, isOurs: @escaping (String) -> Bool) {
        self.name = name
        self.isOurs = isOurs
    }

    var isRunning: Bool { process?.isRunning == true }

    var logFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Logs/Photonz/\(name)-\(Bundle.main.bundleIdentifier ?? "photonz").log")
    }

    /// Starts `executable` under the watch, stopping whatever this helper
    /// left running first. `environment` nil passes on Photonz's own.
    func launch(_ executable: URL, arguments: [String], environment: [String: String]?, pidFolder: URL,
                note: String) throws {
        stop(pidFolder: pidFolder)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The watch: run the program, and stop it when Photonz (the pid given)
        // is gone or this shell is told to stop.
        let script = """
        "$0" "$@" & s=$!
        echo "$s $PHOTONZ_PID" > "$PHOTONZ_ASK_PIDFILE"
        trap 'kill $s 2>/dev/null; wait $s; exit 0' TERM INT
        while kill -0 "$PHOTONZ_PID" 2>/dev/null && kill -0 $s 2>/dev/null; do sleep 1; done
        kill $s 2>/dev/null; wait $s
        """
        process.arguments = ["-c", script, executable.path] + arguments
        var env = environment ?? ProcessInfo.processInfo.environment
        env["PHOTONZ_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        env["PHOTONZ_ASK_PIDFILE"] = pidFile(in: pidFolder).path
        process.environment = env
        try? FileManager.default.createDirectory(at: pidFolder, withIntermediateDirectories: true)
        let log = logFile
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: log)
        _ = try? handle?.seekToEnd()
        handle?.write(Data("\n== \(Date()) Photonz \(ProcessInfo.processInfo.processIdentifier) \(note)\n".utf8))
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        self.process = process
    }

    /// Whether `url` answers 200 within a second.
    static func answers(_ url: URL?) async -> Bool {
        guard let url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Waits until `ready` says yes, the program dies, or `seconds` pass.
    func waitUntil(seconds: TimeInterval, _ ready: () async -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try Task.checkCancellation()
            guard isRunning else { return false }
            if await ready() { return true }
            try await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// Stops the program and frees its memory. Waits a moment for it to go,
    /// so a quit leaves nothing running.
    func stop(pidFolder: URL) {
        if let process {
            self.process = nil
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(3)
                while process.isRunning, Date() < deadline { usleep(20_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        stopLeftover(pidFolder: pidFolder)
    }

    private func pidFile(in folder: URL) -> URL {
        folder.appending(path: ".\(name)-\(Bundle.main.bundleIdentifier ?? "photonz").pid")
    }

    /// A program left running by a Photonz that is gone (the watch was killed
    /// along with it), or by this one: stopped, if it really is this helper.
    /// One another running Photonz of the same build owns is left alone: one
    /// quitting while the next starts must not stop the new one's.
    func stopLeftover(pidFolder: URL) {
        let file = pidFile(in: pidFolder)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let fields = text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        guard let pid = fields.first, pid > 0 else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        if let owner = fields.dropFirst().first, owner != me, kill(owner, 0) == 0 { return }
        try? FileManager.default.removeItem(at: file)
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0, isOurs(String(cString: path)) else { return }
        kill(pid, SIGTERM)
    }
}
