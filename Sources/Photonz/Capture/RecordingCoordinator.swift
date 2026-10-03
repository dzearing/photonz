import AppKit
import Observation
import PhotonzCore

/// Orchestrates a screen-recording session (phase 12): drives the `ScreenRecorder`
/// pipeline, the floating stop HUD (excluded from the capture), the elapsed-time
/// ticker, and dropping the finished recording into the `CaptureStore` history.
/// Owned by `CaptureCenter`, alongside the screenshot pipeline.
@MainActor
@Observable
final class RecordingCoordinator {
    private let store: CaptureStore
    private let recorder = ScreenRecorder()
    private let controls = RecordingControlsController()
    /// Where the pointer goes and every click, taken down beside the picture.
    let pointer = PointerTracker()
    private var timer: Timer?
    private var startDate: Date?

    /// True from the moment capture starts until the file is finalized.
    private(set) var isRecording = false

    /// True while `start` is awaiting stream setup. `startCapture` can take
    /// seconds (and used to block indefinitely on a pending mic TCC prompt);
    /// without this guard a retry during that window spun up a second stream
    /// and leaked the first, which kept capturing to a temp file forever.
    private(set) var isStarting = false

    /// The user's last recording choices, persisted across launches (phase 12.2).
    var config: RecordingConfig {
        didSet { persist() }
    }

    /// Fired with the new video entry once a recording is saved, so the agent can
    /// pop the Quick Access Overlay (same path screenshots use).
    @ObservationIgnored var onRecordingComplete: ((CaptureEntry) -> Void)?

    init(store: CaptureStore) {
        self.store = store
        self.config = RecordingCoordinator.loadConfig()
    }

    /// Stop was pressed while the recording was still starting.
    @ObservationIgnored private var stopWhenStarted = false

    /// The last warm-up asked for, so the next one queues behind it.
    @ObservationIgnored private var warming: Task<Void, Never>?

    /// Get ready to record `config` on `screen` while the person is still on
    /// the recording card: the stop control goes up unseen, and a stream that
    /// writes nothing starts with it and the windows in `alsoExcluding` (the
    /// card) left out of its picture. Start then begins the file on that
    /// stream with nothing to wait for. Calls queue behind one another; the
    /// last one wins.
    func prepare(config: RecordingConfig, screen: NSScreen, alsoExcluding: [NSWindow] = []) {
        guard !isRecording, !isStarting else { return }
        let hud = controls.prepare(on: screen)
        let previous = warming
        warming = Task { [recorder] in
            await previous?.value
            await recorder.warmUp(config: config, screen: screen, excluding: [hud] + alsoExcluding)
        }
    }

    /// The card went away without a recording: stop the warm stream and take
    /// the unseen stop control down.
    func cancelPrepared() {
        guard !isRecording, !isStarting else { return }
        controls.hide()
        let previous = warming
        warming = Task { [recorder] in
            await previous?.value
            await recorder.coolDown()
        }
    }

    #if PHOTONZ_PLAYTEST
    /// Probe drill: something made ready by `prepare` is still standing.
    var playtestSomethingPrepared: Bool { recorder.warmConfig != nil || controls.playtestIsUp }
    #endif

    /// Begin recording per `config` on `screen`. The stop HUD is shown first (so
    /// the window server knows about it) and excluded from the captured video.
    /// When `prepare` warmed a stream for these choices the recording begins
    /// on it at once: the stop control is made visible and the file starts at
    /// the stream's next frame.
    /// `showsControls: false` is the probe's latency drill, which records
    /// without putting the stop control on the person's screen.
    func start(config: RecordingConfig, screen: NSScreen, showsControls: Bool = true) async {
        guard !isRecording, !isStarting else { return }
        lastStartTrace = StartTrace(requested: PointerTracker.hostNow())
        isStarting = true
        defer { isStarting = false }
        self.config = config

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-recording-\(UUID().uuidString).mp4")

        var excluded: [NSWindow] = []
        if showsControls {
            let wasUp = controls.isUp(on: screen)
            excluded.append(controls.show(on: screen) { [weak self] in
                Task { await self?.stop() }
            })
            lastStartTrace?.controlsShown = PointerTracker.hostNow()
            // A control put up just now needs a window-server presence before
            // SCContentFilter can exclude it; one prepared with the card has it.
            if !wasUp { try? await Task.sleep(for: .milliseconds(150)) }
        } else {
            controls.hide()
        }
        // The clock ticks from the moment the control is up, reading from the
        // first frame, so it never sits at 0:00 while macOS finishes starting
        // a stream with sound (about 1.3 s, with the file already going).
        startTimer()

        do {
            try await recorder.start(config: config, screen: screen, to: url, excluding: excluded,
                                     pointer: pointer)
            isRecording = true
            // Stop pressed while macOS was still starting the stream.
            if stopWhenStarted {
                stopWhenStarted = false
                await stop()
            }
        } catch {
            NSLog("Recording failed to start: \(error)")
            stopWhenStarted = false
            stopTimer()
            controls.hide()
            // A start that fails must say so. Before this alert the only sign
            // was the stop HUD flashing away in under a second, which reads as
            // a crash and gives the user nothing to act on.
            presentStartFailure(error)
        }
    }

    private func presentStartFailure(_ error: Error) {
        AppFront.activate()
        let alert = NSAlert()
        alert.messageText = "Could not start the recording"
        alert.informativeText = "\(error.localizedDescription)\n\nCheck Screen Recording and Microphone in System Settings under Privacy & Security, then try again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Stop, and put the recording in history at once. macOS takes a while to
    /// close the file (about 4 ms for every second recorded with sound: most of
    /// a second for three minutes), so the tile and the corner card go up the
    /// moment Stop is pressed and the file fills them in when it lands. The
    /// copy to the clipboard waits for the file, since there is nothing to
    /// paste before it exists.
    func stop() async {
        guard isRecording else {
            // The stop control is up from the moment Start is pressed; a press
            // before the stream has finished starting stops it once it has.
            if isStarting { stopWhenStarted = true }
            return
        }
        let stoppedAt = PointerTracker.hostNow()
        isRecording = false
        let started = startDate ?? .now
        stopTimer()
        controls.hide()
        // The pointer stops being followed the moment Stop is pressed, and its
        // record is written while macOS closes the file, so it never adds to
        // the wait for either.
        let take = pointer.stop()
        let firstFrame = recorder.firstFrameHostSeconds
        let pointerFile = Task.detached(priority: .userInitiated) { () -> Data? in
            guard let take, !take.isEmpty else { return nil }
            return try? JSONEncoder().encode(take.finished(firstFrameHostSeconds: firstFrame))
        }
        let pending = store.beginSaving(recordingStartedAt: started)
        // The frame the recording ends on is already in memory: it is the
        // tile's picture from now, and what an editor opened before the file
        // lands opens on.
        if Experiments.shared.recordingReadyAtStop, let last = recorder.lastFrame,
           let firstFrame = recorder.firstFrameHostSeconds {
            let size = CGSize(width: CVPixelBufferGetWidth(last.frame.buffer),
                              height: CVPixelBufferGetHeight(last.frame.buffer))
            let stoppedMS = Int(((stoppedAt - firstFrame) * 1000).rounded())
            store.holdLastFrame(last.frame, of: pending,
                                recording: ClosingRecording(pixelSize: size, lastFrameMS: last.fileMS,
                                                            stoppedMS: stoppedMS,
                                                            hasSound: config.audio.capturesAnyAudio))
        }
        onRecordingComplete?(pending)
        do {
            let url = try await recorder.stop()
            #if PHOTONZ_PLAYTEST
            if playtestFileCloseSeconds > 0 { try? await Task.sleep(for: .seconds(playtestFileCloseSeconds)) }
            #endif
            // The store files the MP4 and derives the poster/duration lazily.
            store.finishSaving(pending, tempURL: url, pointerTrack: await pointerFile.value)
        } catch {
            NSLog("Recording failed to stop: \(error)")
            store.failSaving(pending)
        }
    }

    #if PHOTONZ_PLAYTEST
    /// How long a walk makes macOS take to close the file, so it can see a
    /// window opened before the file lands (`PlaytestOpenAtStop`).
    @ObservationIgnored var playtestFileCloseSeconds: Double = 0
    #endif

    /// When each part of the last start happened, on the host clock (the
    /// probe's start drill).
    struct StartTrace {
        var requested: Double
        var controlsShown: Double?
        var timerStarted: Double?
    }
    private(set) var lastStartTrace: StartTrace?
    var lastRecorderStartTrace: ScreenRecorder.StartTrace { recorder.lastStart }

    /// When each part of the last stop happened (the probe's latency drill).
    var lastStopTrace: ScreenRecorder.StopTrace? { recorder.lastStop }

    /// When the last recording's first frame was taken, on the host clock.
    var firstFrameHostSeconds: Double? { recorder.firstFrameHostSeconds }

    func toggle(screen: NSScreen) async {
        if isRecording { await stop() } else { await start(config: config, screen: screen) }
    }

    // MARK: - Elapsed timer

    private func startTimer() {
        startDate = Date()
        lastStartTrace?.timerStarted = PointerTracker.hostNow()
        timer?.invalidate()
        controls.updateElapsed(0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // The clock counts from the recording's first frame, which is
                // where the file starts, not from the key press.
                guard let self, let first = self.recorder.firstFrameHostSeconds else { return }
                self.controls.updateElapsed(max(0, PointerTracker.hostNow() - first))
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startDate = nil
    }

    // MARK: - Config persistence

    private static let defaultsKey = "photonz.recordingConfig"

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func loadConfig() -> RecordingConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(RecordingConfig.self, from: data)
        else { return RecordingConfig() }
        return config
    }
}
