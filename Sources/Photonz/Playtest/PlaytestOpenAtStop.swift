#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzMedia

/// The walk steps `recordAndOpenAtStop` and `expectRecordingLandedInPlace`: a
/// real recording, opened through the app's own door the moment Stop puts its
/// tile up, before macOS has closed the file (`ClosingRecording`).
///
/// What is real: ScreenCaptureKit records a corner of the main display through
/// the app's own recorder into the app's own capture store, which a walk with
/// `history` in its setup points at a made-up folder; the corner card goes up
/// as it does after any recording; the recording opens through
/// `AppCoordinator.openRecording`, the door the card's Edit uses. What is
/// scripted: the card's Edit is pressed the instant the tile is up, nothing is
/// put on the clipboard (a walk never touches the person's), and macOS is made
/// to take three seconds closing the file so the steps after this one can see
/// and photograph the window before it lands.
@MainActor
enum PlaytestOpenAtStop {
    struct Failure: Error { let description: String }

    static let region = CGRect(x: 40, y: 80, width: 480, height: 300)
    static let fileCloseSeconds = 3.0

    /// What the opening step saw, for the landing step to hold it to.
    private struct Opened {
        let editor: EditorState
        let recorder: RecordingCoordinator
        let windowFrame: CGRect?
        let landing: Task<Void, Never>
    }
    private static var opened: Opened?

    static func run(coordinator app: AppCoordinator) async throws -> (editor: EditorState, summary: String) {
        guard ScreenCapturer.hasPermission else {
            throw Failure(description: "the probe has no Screen Recording grant, so it cannot record")
        }
        guard PlaytestGeneratedHistory.folder != nil else {
            throw Failure(description: "this step records into history, so the walk's setup needs `history` "
                + "to point history at a made-up folder rather than the person's own")
        }
        guard Experiments.shared.recordingReadyAtStop else {
            throw Failure(description: "next-a-recording-is-ready-at-stop is off, so nothing opens before the file lands")
        }
        guard let screen = NSScreen.main else { throw Failure(description: "there is no screen to record") }
        let recorder = RecordingCoordinator(store: app.capture.store)
        recorder.playtestFileCloseSeconds = fileCloseSeconds
        var tileAt: Date?
        recorder.onRecordingComplete = { entry in
            tileAt = Date()
            app.showCaptureToast(entry)
            app.openRecording(entry.url)
        }
        await recorder.start(config: RecordingConfig(source: .region(region)), screen: screen, showsControls: false)
        guard recorder.isRecording else { throw Failure(description: "the recording did not start") }
        try? await Task.sleep(for: .seconds(3))

        let stop = Date()
        let landing = Task { await recorder.stop() }
        var editor: EditorState?
        var pictureAt: Date?
        let deadline = Date().addingTimeInterval(fileCloseSeconds)
        while pictureAt == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
            editor = PlaytestHarness.readyEditors.last { $0.isRecordingDocument && $0.recordingStillLanding }
            if let editor, editor.movieFrameReadWidths().contains(where: { $0.read != nil }) { pictureAt = Date() }
        }
        guard let tileAt else { throw Failure(description: "Stop put no tile up in history") }
        guard let editor, let pictureAt else {
            throw Failure(description: "no window opened on the recording's last frame before its file landed")
        }
        let tileMS = tileAt.timeIntervalSince(stop) * 1000
        let pictureMS = pictureAt.timeIntervalSince(stop) * 1000
        guard RecordingStopBudget.isWithin(stopToEditorPictureMS: pictureMS) else {
            throw Failure(description: "the window showed the picture \(Int(pictureMS)) ms after Stop, over its "
                + "\(Int(RecordingStopBudget.stopToEditorPictureMS)) ms budget")
        }
        try? await Task.sleep(for: .milliseconds(400))  // the window settles
        opened = Opened(editor: editor, recorder: recorder, windowFrame: editor.hostWindow?.frame,
                        landing: landing)
        return (editor, String(format: "stop to tile %.0f ms · stop to the window showing the picture %.0f ms "
                               + "· the file lands in %.0f s", tileMS, pictureMS, fileCloseSeconds))
    }

    static func expectLandedInPlace() async throws -> String {
        guard let opened else { throw Failure(description: "no recording was opened at Stop earlier in this walk") }
        let editor = opened.editor
        await opened.landing.value
        let deadline = Date().addingTimeInterval(10)
        while editor.recordingStillLanding, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        guard !editor.recordingStillLanding else { throw Failure(description: "the file landed and the window never took it") }
        guard let clip = editor.document?.allLayers.first(where: { $0.movie != nil }), let movie = clip.movie,
              let url = MovieLibrary.shared.url(for: movie) else {
            throw Failure(description: "the window holds no recording it can play")
        }
        let seconds = await VideoExporter.duration(of: url)
        let fileMS = Int((seconds * 1000).rounded())
        guard clip.time?.outMS == fileMS else {
            throw Failure(description: "the clip runs to \(clip.time?.outMS ?? -1) ms and the file is \(fileMS) ms")
        }
        let frame = editor.hostWindow?.frame
        guard frame == opened.windowFrame else {
            throw Failure(description: "the window moved or changed size when the file landed: "
                + "\(String(describing: opened.windowFrame)) then \(String(describing: frame))")
        }
        return "landed in place: the same window, the clip \(fileMS) ms like its file, "
            + (editor.isDocumentPlaying ? "playing" : "paused on its last frame")
    }
}
#endif
