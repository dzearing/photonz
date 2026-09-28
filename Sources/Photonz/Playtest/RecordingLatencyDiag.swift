#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzMedia

/// Probe-only drill of how long a recording takes to reach history once it is
/// stopped (`--recording-latency-diag <seconds>`). Records the main display
/// through the app's own `RecordingCoordinator` (with the stop control left off
/// the screen), filing into a `CaptureStore` over a scratch folder, never the
/// person's own history, and times every step after Stop:
///
/// - the tile going up in history (the budget);
/// - macOS saying the file is closed, and the file landing in the folder;
/// - the poster frame and the duration landing, which the tile does NOT wait
///   for (it draws a placeholder until they do).
///
/// `--with-microphone` and `--system-audio` record those sources too. The
/// readings go to `/tmp/photonz-recording-latency.json` and the log, the
/// recording is deleted afterwards, and the run fails (a `FAIL` line and
/// `"passed": false`) when Stop to tile is over `RecordingStopBudget`.
@MainActor
enum RecordingLatencyDiag {
    static let resultPath = "/tmp/photonz-recording-latency.json"

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--recording-latency-diag") else { return }
        let seconds = (i + 1 < args.count ? Double(args[i + 1]) : nil) ?? 5
        Task { await run(seconds: seconds, args: args) }
    }

    private static func ms(_ from: Date, _ to: Date?) -> Double? {
        to.map { ($0.timeIntervalSince(from) * 1000).rounded() }
    }

    private static func run(seconds: Double, args: [String]) async {
        var out: [String: Any] = ["seconds": seconds]
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: resultPath))
            }
            NSLog("[recording-latency-diag] \(out)")
        }
        guard let screen = NSScreen.main else { out["error"] = "no screen"; return }
        var audio: AudioSources = []
        if args.contains("--system-audio") { audio.insert(.systemAudio) }
        if args.contains("--with-microphone") { audio.insert(.microphone) }
        out["audio"] = [audio.contains(.systemAudio) ? "system" : nil,
                        audio.contains(.microphone) ? "microphone" : nil].compactMap { $0 }

        guard ScreenCapturer.hasPermission else { out["error"] = "no Screen Recording grant"; return }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-latency-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = CaptureStore(directory: scratch)
        store.start()
        // The app's own recording path, stop control left off the screen.
        let coordinator = RecordingCoordinator(store: store)
        var tile: Date?
        var tileEntry: CaptureEntry?
        coordinator.onRecordingComplete = { entry in
            tile = Date()
            tileEntry = entry
        }
        await coordinator.start(config: RecordingConfig(audio: audio), screen: screen, showsControls: false)
        guard coordinator.isRecording else { out["error"] = "the recording did not start"; return }
        try? await Task.sleep(for: .seconds(seconds))

        let stop = Date()
        let inHistoryAtTile: Bool
        await coordinator.stop()
        let landed = Date()
        guard let tile, let entry = tileEntry else { out["error"] = "no tile was put up"; return }
        inHistoryAtTile = store.entries.contains { $0.url == entry.url }

        let trace = coordinator.lastStopTrace
        out["outputFinishedMS"] = trace.flatMap { ms(stop, $0.outputFinished) }
        out["fallbackFiredMS"] = trace.flatMap { ms(stop, $0.fallbackFired) }
        out["stopToTileMS"] = ms(stop, tile)
        out["stopToFileLandedMS"] = ms(stop, landed)
        out["tileInHistory"] = inHistoryAtTile
        out["fileLanded"] = FileManager.default.fileExists(atPath: entry.url.path)

        // The tile asks for these and draws a placeholder until they land.
        _ = store.image(for: entry)
        _ = store.duration(for: entry)
        var posterMS: Double?
        var durationMS: Double?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, posterMS == nil || durationMS == nil {
            try? await Task.sleep(for: .milliseconds(5))
            if posterMS == nil, store.image(for: entry) != nil { posterMS = ms(stop, Date()) }
            if durationMS == nil, store.duration(for: entry) != nil { durationMS = ms(stop, Date()) }
        }
        out["posterMS"] = posterMS
        out["durationMS"] = durationMS
        out["recordedSeconds"] = await VideoExporter.duration(of: entry.url)

        let stopToTile = tile.timeIntervalSince(stop) * 1000
        let passed = RecordingStopBudget.isWithin(stopToTileMS: stopToTile) && inHistoryAtTile
        out["budgetMS"] = RecordingStopBudget.stopToTileMS
        out["passed"] = passed
        if !passed {
            NSLog("[recording-latency-diag] FAIL: Stop to tile took \(Int(stopToTile)) ms, over \(Int(RecordingStopBudget.stopToTileMS)) ms")
        }
    }
}
#endif
