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

    /// Begin recording per `config` on `screen`. The stop HUD is shown first (so
    /// the window server knows about it) and excluded from the captured video.
    func start(config: RecordingConfig, screen: NSScreen) async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        self.config = config

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-recording-\(UUID().uuidString).mp4")

        let hud = controls.show(on: screen) { [weak self] in
            Task { await self?.stop() }
        }
        // Give the HUD a window-server presence so SCContentFilter can exclude it.
        try? await Task.sleep(for: .milliseconds(150))

        do {
            try await recorder.start(config: config, screen: screen, to: url, excluding: [hud])
            isRecording = true
            startTimer()
        } catch {
            NSLog("Recording failed to start: \(error)")
            controls.hide()
            // A start that fails must say so. Before this alert the only sign
            // was the stop HUD flashing away in under a second, which reads as
            // a crash and gives the user nothing to act on.
            presentStartFailure(error)
        }
    }

    private func presentStartFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Could not start the recording"
        alert.informativeText = "\(error.localizedDescription)\n\nCheck Screen Recording and Microphone in System Settings under Privacy & Security, then try again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Stop, finalize, and file the recording into history.
    func stop() async {
        guard isRecording else { return }
        isRecording = false
        stopTimer()
        do {
            let url = try await recorder.stop()
            controls.hide()
            // The store files the MP4 and derives the poster/duration lazily.
            if let entry = store.addRecording(tempURL: url) { onRecordingComplete?(entry) }
        } catch {
            NSLog("Recording failed to stop: \(error)")
            controls.hide()
        }
    }

    func toggle(screen: NSScreen) async {
        if isRecording { await stop() } else { await start(config: config, screen: screen) }
    }

    // MARK: - Elapsed timer

    private func startTimer() {
        startDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.startDate else { return }
                self.controls.updateElapsed(Date().timeIntervalSince(start))
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
