#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzMedia

/// The walk step `recordScriptedClicks`: a real recording through the app's
/// own recorder with three clicks scripted into it, opened the way a person
/// opens one, and checked against what was scripted.
///
/// What is real: ScreenCaptureKit records a 480 x 300 point corner of the main
/// display into a history folder of the walk's own (never the person's), the
/// pointer is followed and every press taken down by the same tracker a person
/// gets, the record is written beside the file on Stop, and the recording is
/// opened through the app's own door. What is scripted: WHERE the pointer is
/// and the presses themselves, which go in through the door the Mac's mouse
/// monitor uses, because a walk never moves the person's pointer.
///
/// Where each click should land is worked out here independently of the app's
/// own mapping: the offset into the corner times the display's backing scale.
@MainActor
enum PlaytestScriptedClicks {
    struct Failure: Error { let description: String }

    struct Outcome {
        let editor: EditorState
        let summary: String
    }

    /// The corner recorded, in points from the main display's top-left.
    static let region = CGRect(x: 40, y: 80, width: 480, height: 300)
    /// When each click is pressed after the recording starts, and where, in
    /// points from the region's top-left.
    static let script: [(seconds: Double, at: CGPoint)] = [
        (1.0, CGPoint(x: 100, y: 60)),
        (2.5, CGPoint(x: 240, y: 150)),
        (4.0, CGPoint(x: 400, y: 250)),
    ]
    static let heldMS = 80.0

    static func run(coordinator app: AppCoordinator, out: URL) async throws -> Outcome {
        guard ScreenCapturer.hasPermission else {
            throw Failure(description: "the probe has no Screen Recording grant, so it cannot record")
        }
        guard let screen = NSScreen.main else { throw Failure(description: "there is no screen to record") }
        let folder = out.appendingPathComponent("recorded-history", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let store = CaptureStore(directory: folder)
        store.start()
        let recorder = RecordingCoordinator(store: store)
        var tileAt: Date?
        recorder.onRecordingComplete = { _ in tileAt = Date() }

        let frame = screen.frame
        func screenPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + region.minX + p.x, y: frame.maxY - region.minY - p.y)
        }
        var scripted = screenPoint(CGPoint(x: 10, y: 10))
        recorder.pointer.position = { scripted }

        await recorder.start(config: RecordingConfig(source: .region(region)), screen: screen, showsControls: false)
        guard recorder.isRecording else { throw Failure(description: "the recording did not start") }
        let began = Date()

        var pressedAt: [Double] = []
        for (seconds, at) in script {
            let wait = seconds - Date().timeIntervalSince(began)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            scripted = screenPoint(at)
            // A frame for the pointer to be seen there before it presses.
            try? await Task.sleep(for: .milliseconds(40))
            let down = PointerTracker.hostNow()
            recorder.pointer.press(.left, at: scripted, hostSeconds: down)
            pressedAt.append(down)
            try? await Task.sleep(for: .milliseconds(Int(heldMS)))
            recorder.pointer.release(.left, at: scripted, hostSeconds: PointerTracker.hostNow())
        }
        let rest = 5.0 - Date().timeIntervalSince(began)
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }

        let stop = Date()
        await recorder.stop()
        guard let tileAt else { throw Failure(description: "Stop put no tile up in history") }
        let stopToTileMS = tileAt.timeIntervalSince(stop) * 1000
        guard RecordingStopBudget.isWithin(stopToTileMS: stopToTileMS) else {
            throw Failure(description: "Stop took \(Int(stopToTileMS)) ms to put the tile up, "
                + "over its \(Int(RecordingStopBudget.stopToTileMS)) ms budget")
        }
        guard let firstFrame = recorder.firstFrameHostSeconds else {
            throw Failure(description: "the stream never said when its first frame was taken")
        }
        guard let file = store.entries.first(where: { $0.kind == .video })?.url else {
            throw Failure(description: "the recording never landed in its history folder")
        }
        guard FileManager.default.fileExists(atPath: PointerTrackSidecar.url(for: file).path) else {
            throw Failure(description: "no pointer record was written beside \(file.lastPathComponent)")
        }

        app.openWindow(.video(standardizing: file))
        var opened: EditorState?
        let deadline = Date().addingTimeInterval(20)
        while opened == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            opened = PlaytestHarness.readyEditors.last {
                $0.isRecordingDocument && $0.recordingURL?.lastPathComponent == file.lastPathComponent
            }
        }
        guard let editor = opened else { throw Failure(description: "the recording did not open as a document") }
        guard let clip = editor.document?.allLayers.first(where: { $0.movie != nil }) else {
            throw Failure(description: "the opened recording has no clip")
        }
        let clicks = editor.clicks(ofClip: clip.id)
        guard clicks.count == script.count else {
            throw Failure(description: "the opened recording has \(clicks.count) clicks, not \(script.count)")
        }
        let scale = screen.backingScaleFactor
        let frameMS = 1000.0 / 60
        var lines: [String] = []
        for (i, click) in clicks.enumerated() {
            let wantMS = (pressedAt[i] - firstFrame) * 1000
            let want = CGPoint(x: script[i].at.x * scale, y: script[i].at.y * scale)
            let dt = abs(Double(click.downMS) - wantMS)
            let d = hypot(click.point.x - want.x, click.point.y - want.y)
            guard dt <= frameMS else {
                throw Failure(description: "click \(i + 1) is at \(click.downMS) ms, \(Int(dt)) ms from "
                    + "the \(Int(wantMS)) ms it was pressed at")
            }
            guard d <= 2 else {
                throw Failure(description: "click \(i + 1) is at \(Int(click.point.x)), \(Int(click.point.y)) px, "
                    + String(format: "%.1f", d) + " px from \(Int(want.x)), \(Int(want.y))")
            }
            guard let up = click.upMS, abs(Double(up - click.downMS) - heldMS) <= frameMS + 10 else {
                throw Failure(description: "click \(i + 1) was held \(heldMS) ms and reads "
                    + "\(click.upMS.map { "\($0 - click.downMS) ms" } ?? "never released")")
            }
            lines.append("\(click.downMS) ms at \(Int(click.point.x)),\(Int(click.point.y))")
        }
        let seconds = await VideoExporter.duration(of: file)
        let summary = "3 clicks kept: " + lines.joined(separator: "; ")
            + String(format: " · stop to tile %.0f ms · file %.2f s", stopToTileMS, seconds)
        return Outcome(editor: editor, summary: summary)
    }
}
#endif
