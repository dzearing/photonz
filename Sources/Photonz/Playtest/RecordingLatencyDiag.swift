#if PHOTONZ_PLAYTEST
import AppKit
import AVFoundation
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
/// - the tile showing the recording's picture (the frame it ended on, held in
///   memory at Stop, under `next-a-recording-is-ready-at-stop`), and the
///   duration landing;
/// - an editor opened on the recording the moment its tile is up showing the
///   picture, and the same editor becoming playable once the file lands.
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
            if let data = SafeJSON.data(from: out, options: [.prettyPrinted, .sortedKeys]) {
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
        var thumbnail: CaptureThumbnail?
        let editor = EditorState()
        var editorOpened = false
        coordinator.onRecordingComplete = { entry in
            tile = Date()
            tileEntry = entry
            // The tile asks for its picture as it goes up, the way the strip
            // and the corner card do.
            thumbnail = store.thumbnail(for: entry)
        }
        await coordinator.start(config: RecordingConfig(audio: audio), screen: screen, showsControls: false)
        guard coordinator.isRecording else { out["error"] = "the recording did not start"; return }
        try? await Task.sleep(for: .seconds(seconds))

        let stop = Date()
        let inHistoryAtTile: Bool
        out["readyAtStop"] = Experiments.shared.recordingReadyAtStop
        // Watched while the file closes: the tile's picture, and an editor
        // opened on the recording the moment its tile is up.
        var held: CaptureStore.ClosingPicture?
        var thumbnailAt: Date?
        var pictureAt: Date?
        var playableAt: Date?
        let watch = Task { @MainActor in
            while !Task.isCancelled {
                if !editorOpened, let entry = tileEntry {
                    editorOpened = true
                    Task { held = await store.closingPicture(for: entry.url) }
                    if !editor.openClosingRecording(at: entry.url, from: store) {
                        // Nothing held: the editor opens when the file lands.
                        store.whenLanded(entry.url) { landed in
                            if let landed { editor.openRecordingAsDocument(at: landed.url) }
                        }
                    }
                }
                if thumbnailAt == nil, thumbnail?.image != nil { thumbnailAt = Date() }
                if pictureAt == nil, editor.document != nil,
                   editor.movieFrameReadWidths().contains(where: { $0.read != nil }) { pictureAt = Date() }
                if playableAt == nil, editor.document != nil, !editor.recordingStillLanding,
                   let movie = editor.document?.allLayers.first(where: { $0.movie != nil })?.movie,
                   MovieLibrary.shared.url(for: movie) != nil { playableAt = Date() }
                if thumbnailAt != nil, pictureAt != nil, playableAt != nil { return }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        await coordinator.stop()
        let landed = Date()
        let watchDeadline = Date().addingTimeInterval(10)
        while Date() < watchDeadline, thumbnailAt == nil || pictureAt == nil || playableAt == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        watch.cancel()
        out["stopToThumbnailMS"] = ms(stop, thumbnailAt)
        out["stopToEditorPictureMS"] = ms(stop, pictureAt)
        out["stopToPlayableMS"] = ms(stop, playableAt)
        guard let tile, let entry = tileEntry else { out["error"] = "no tile was put up"; return }
        inHistoryAtTile = store.entries.contains { $0.url == entry.url }

        let trace = coordinator.lastStopTrace
        out["outputFinishedMS"] = trace.flatMap { ms(stop, $0.outputFinished) }
        out["fallbackFiredMS"] = trace.flatMap { ms(stop, $0.fallbackFired) }
        out["stopToTileMS"] = ms(stop, tile)
        out["stopToFileLandedMS"] = ms(stop, landed)
        out["tileInHistory"] = inHistoryAtTile
        out["fileLanded"] = FileManager.default.fileExists(atPath: entry.url.path)

        // The duration the tile shows once the file has said it.
        let shown = store.thumbnail(for: entry)
        var durationMS: Double?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, durationMS == nil {
            if let duration = shown.duration, abs(duration - (await VideoExporter.duration(of: entry.url))) < 0.001 {
                durationMS = ms(stop, Date())
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        out["posterMS"] = ms(stop, thumbnailAt)
        out["durationMS"] = durationMS
        out["recordedSeconds"] = await VideoExporter.duration(of: entry.url)
        // The frame held at Stop beside the file's own frame at that moment,
        // so a person can see the two are the same picture in the same colours.
        if let held {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: entry.url))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let at = CMTime(value: CMTimeValue(held.recording.lastFrameMS), timescale: 1000)
            let fromFile = try? await generator.image(at: at).image
            for (name, image) in [("held", held.image), ("file", fromFile)] {
                guard let image else { continue }
                let url = URL(fileURLWithPath: "/tmp/photonz-last-frame-\(name).png")
                if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, image, nil)
                    CGImageDestinationFinalize(dest)
                }
            }
            out["heldFrameMS"] = held.recording.lastFrameMS
            out["heldSize"] = "\(held.image.width)x\(held.image.height)"
            out["fileSize"] = fromFile.map { "\($0.width)x\($0.height)" }
        }

        let stopToTile = tile.timeIntervalSince(stop) * 1000
        var passed = RecordingStopBudget.isWithin(stopToTileMS: stopToTile) && inHistoryAtTile
        if Experiments.shared.recordingReadyAtStop {
            passed = passed
                && RecordingStopBudget.isWithin(stopToThumbnailMS: thumbnailAt.map { $0.timeIntervalSince(stop) * 1000 } ?? .infinity)
                && RecordingStopBudget.isWithin(stopToEditorPictureMS: pictureAt.map { $0.timeIntervalSince(stop) * 1000 } ?? .infinity)
        }
        out["budgetMS"] = RecordingStopBudget.stopToTileMS
        out["thumbnailBudgetMS"] = RecordingStopBudget.stopToThumbnailMS
        out["editorBudgetMS"] = RecordingStopBudget.stopToEditorPictureMS
        out["passed"] = passed
        if !passed {
            NSLog("[recording-latency-diag] FAIL: a reading is over its budget: \(out)")
        }
    }
}
#endif
