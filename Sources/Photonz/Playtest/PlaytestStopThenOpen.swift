#if PHOTONZ_PLAYTEST
import AppKit
import AVFoundation
import PhotonzCore

/// The walk step `stopThenOpenDrill`: real recordings with sound from the Mac
/// and the microphone (the pair macOS was slowest closing, about 0.45 s per
/// recorded second, until the recorder mixed them itself on 2026-10-11:
/// `RecordingSoundMixer`), each opened through the app's own door at 0.2, 0.5, 1 and
/// 2 seconds after Stop, five times each.
///
/// The user, 2026-10-10: the tile showed for a moment and went, and opening it
/// said there was no recording in it, or to wait. The recorder handed the file
/// to history 400 ms after the stream stopped whether macOS had finished it or
/// not (`RecordingFileClose`). This fails on any of what they saw:
///
/// - the recording's tile missing from history, or not first, at any look
///   between Stop and a second after its file lands;
/// - its tile losing its picture once it has one;
/// - anything said in the corner (`RecordingDoor`'s "could not be opened",
///   "still being saved", "not there");
/// - a window that never showed the recording's picture, or never took the
///   file when it landed.
///
/// Records the whole main display, as the person does (a small region with
/// the same sound closes in under 100 ms and would prove nothing), into the walk's made-up history
/// (`history` in the setup), with no stop control on screen and nothing put on
/// the clipboard; every window it opens it closes.
@MainActor
enum PlaytestStopThenOpen {
    struct Failure: Error { let description: String }

    static let recordSeconds = 2.0
    static let openDelays: [Double] = [0.2, 0.5, 1, 2]
    static let rounds = 5
    /// Asked for to the window showing the recording's picture. Measured
    /// 2026-10-10 with no other window open: medians 144 to 197 ms, worst
    /// 210 ms, about 50 ms of it the app becoming a Dock app for its first
    /// window (beside an open window the worst was 165 ms). Reading the file
    /// first, the way it opened before, took about 450 ms.
    /// 2026-10-15, load about 4: the held frame used to go in a turn after
    /// the window was made, behind its first layout, and rounds landed at 250
    /// to 271 ms. Installed while the window is seeded, three runs were worst
    /// 221, 234 and 246 ms; what is left is SwiftUI making the window (70 to
    /// 110 ms to `seed`) and its first layout with the picture (about 100 ms).
    static let openBudgetMS = 250.0

    @MainActor private final class Landed { var at: Date? }

    private struct Reading {
        var delay: Double
        var openMS: Double
        var windowMS: Double
        var landedMS: Double
        var openedBeforeLanding: Bool
    }

    static func run(coordinator app: AppCoordinator) async throws -> String {
        guard ScreenCapturer.hasPermission else {
            throw Failure(description: "the probe has no Screen Recording grant, so it cannot record")
        }
        guard PlaytestGeneratedHistory.folder != nil else {
            throw Failure(description: "this step records into history, so the walk's setup needs `history` "
                + "to point history at a made-up folder rather than the person's own")
        }
        guard let screen = NSScreen.main else { throw Failure(description: "there is no screen to record") }
        let store = app.capture.store
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let audio: AudioSources = micGranted ? [.systemAudio, .microphone] : [.systemAudio]
        let recorder = RecordingCoordinator(store: store)
        var readings: [Reading] = []
        var slow: [String] = []

        for round in 0..<rounds {
            for delay in openDelays {
                let label = "round \(round + 1), opened \(delay) s after Stop"
                var tile: CaptureEntry?
                recorder.onRecordingComplete = { tile = $0 }
                await recorder.start(config: RecordingConfig(audio: audio),
                                     screen: screen, showsControls: false)
                guard recorder.isRecording else { throw Failure(description: "\(label): the recording did not start") }
                try? await Task.sleep(for: .seconds(recordSeconds))

                let notesBefore = app.playtestNotesSaid.count
                let stop = Date()
                let landedBox = Landed()
                let landing = Task { await recorder.stop(); landedBox.at = Date() }
                // Stop puts the tile up before it awaits anything.
                while tile == nil, Date().timeIntervalSince(stop) < 1 { await Task.yield() }
                guard let entry = tile else { throw Failure(description: "\(label): Stop put no tile up in history") }
                let name = entry.fileName

                // Watched every few milliseconds until a second after it lands.
                var trouble: String?
                var hadPicture = false
                var editor: EditorState?
                var asked: Date?
                var pictureAt: Date?
                var windowAt: Date?
                var openedBeforeLanding = false
                var trace = ""
                while trouble == nil {
                    let now = Date()
                    let landedAt = landedBox.at
                    if let landedAt, now.timeIntervalSince(landedAt) > 1, pictureAt != nil { break }
                    if now.timeIntervalSince(stop) > 60 { trouble = "the file had not landed a minute after Stop"; break }
                    if store.entries.first?.fileName != name {
                        trouble = store.entries.contains(where: { $0.fileName == name })
                            ? "its tile stopped being the first in history"
                            : "its tile vanished from history"
                        break
                    }
                    let shown = store.entries.first.map { store.thumbnail(for: $0).image != nil } ?? false
                    if hadPicture, !shown { trouble = "its tile lost its picture"; break }
                    hadPicture = hadPicture || shown
                    if asked == nil, now.timeIntervalSince(stop) >= delay {
                        asked = now
                        openedBeforeLanding = landedAt == nil
                        PlaytestOpenTrace.begin()
                        app.openRecording(store.entries.first?.url ?? entry.url)
                    }
                    if asked != nil, editor == nil {
                        editor = PlaytestHarness.readyEditors.last { $0.recordingURL?.lastPathComponent == name }
                    }
                    if asked != nil, windowAt == nil, editor?.hostWindow?.isVisible == true {
                        windowAt = Date()
                        PlaytestOpenTrace.mark("visible")
                    }
                    if asked != nil, pictureAt == nil, let editor,
                       editor.movieFrameReadWidths().contains(where: { $0.read != nil }) {
                        pictureAt = Date()
                        PlaytestOpenTrace.mark("picture")
                        trace = PlaytestOpenTrace.said
                    }
                    if let asked, pictureAt == nil, now.timeIntervalSince(asked) > 10 {
                        trouble = "no window showed the recording ten seconds after it was asked for"
                    }
                    if app.playtestNotesSaid.count > notesBefore {
                        trouble = "the corner said \"\(app.playtestNotesSaid[notesBefore])\""
                    }
                    try? await Task.sleep(for: .milliseconds(5))
                }
                await landing.value
                if trouble == nil, let editor {
                    let deadline = Date().addingTimeInterval(10)
                    while editor.recordingStillLanding, Date() < deadline {
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                    if editor.recordingStillLanding { trouble = "the window never took the file when it landed" }
                }
                if trouble == nil, app.playtestNotesSaid.count > notesBefore {
                    trouble = "the corner said \"\(app.playtestNotesSaid[notesBefore])\""
                }
                editor?.hostWindow?.close()
                if let trouble {
                    throw Failure(description: "\(label) (\(name)): \(trouble)")
                }
                guard let asked, let pictureAt, let landedAt = landedBox.at else {
                    throw Failure(description: "\(label): nothing was opened")
                }
                let reading = Reading(delay: delay,
                                      openMS: pictureAt.timeIntervalSince(asked) * 1000,
                                      windowMS: (windowAt ?? pictureAt).timeIntervalSince(asked) * 1000,
                                      landedMS: landedAt.timeIntervalSince(stop) * 1000,
                                      openedBeforeLanding: openedBeforeLanding)
                readings.append(reading)
                if delay >= 0.5, reading.openMS > openBudgetMS {
                    // Where the time went, ms after the open was asked for
                    // (`PlaytestOpenTrace`).
                    slow.append(String(format: "%@ took %.0f ms (%@)", label, reading.openMS, trace))
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }

        let summary = openDelays.map { delay -> String in
            let these = readings.filter { $0.delay == delay }
            let times = these.map(\.openMS).sorted()
            let median = times.isEmpty ? 0 : times[times.count / 2]
            let early = these.filter(\.openedBeforeLanding).count
            return String(format: "at %.1f s: %.0f ms to the picture (worst %.0f), %d of %d before the file landed",
                          delay, median, times.last ?? 0, early, these.count)
        }
        let landed = readings.map(\.landedMS)
        let sound = micGranted ? "the Mac and the microphone" : "the Mac only (the probe has no microphone grant)"
        let said = "\(readings.count) full-screen recordings of \(recordSeconds) s with sound from \(sound), "
            + "no tile vanished, blanked or moved and the corner said nothing · "
            + summary.joined(separator: " · ")
            + String(format: " · files landed %.0f to %.0f ms after Stop", landed.min() ?? 0, landed.max() ?? 0)
        guard slow.isEmpty else {
            throw Failure(description: "over the \(Int(openBudgetMS)) ms open budget: "
                + slow.joined(separator: "; ") + " · " + said)
        }
        return said
    }
}
#endif
