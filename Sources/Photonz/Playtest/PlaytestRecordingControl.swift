#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

/// The walk step `recordingControlDrill`: the floating recording control
/// (timer and Stop) starts bottom left, is dragged, comes back where it was
/// left on the next recording, keeps out of a recorded region, and goes home
/// on a double click.
///
/// What is real: every recording is a real ScreenCaptureKit recording of a
/// corner of the main display through the app's own recorder, into a history
/// folder of the walk's own, with the app's own control up for it; the drag
/// and the clicks are mouse events handed to the control's window, so the
/// SwiftUI gesture that tells the button from the rest of the control is the
/// one deciding. What is scripted: where the pointer is, since a walk never
/// moves the person's own (`RecordingControlsController.playtestPointer`).
///
/// The control sits one level under every other app's window for the drill,
/// so it never covers the person's work; its pictures are of its own window.
/// Where the person left the probe's control is put back when the drill ends.
@MainActor
enum PlaytestRecordingControl {
    struct Failure: Error { let description: String }

    /// The corner recorded, in points from the main display's top-left: top
    /// right, well away from where the control starts.
    static func region(on screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.width - 380, y: 60, width: 320, height: 200)
    }

    /// A point on the control between its clock and its button, in the
    /// window's own points (y up): nothing there but glass.
    static let emptyPart = CGPoint(x: 112, y: 26)
    /// The middle of the Stop button.
    static let stopButton = CGPoint(x: 176, y: 26)
    /// How far the drill drags the control.
    static let dragBy = CGVector(dx: 420, dy: 260)

    static func run(out: URL, photograph: (NSWindow, String) async -> Void) async throws -> String {
        guard ScreenCapturer.hasPermission else {
            throw Failure(description: "the probe has no Screen Recording grant, so it cannot record")
        }
        guard let screen = NSScreen.main else { throw Failure(description: "there is no screen to record") }
        let kept = UserDefaults.standard.data(forKey: RecordingControlSpotStore.defaultsKey)
        RecordingControlSpotStore.spot = nil
        RecordingControlsController.playtestLevel = PlaytestHarness.walkWindowLevel
        defer {
            RecordingControlsController.playtestLevel = nil
            RecordingControlsController.playtestPointer = nil
            UserDefaults.standard.set(kept, forKey: RecordingControlSpotStore.defaultsKey)
        }
        let folder = out.appendingPathComponent("recorded-history", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let store = CaptureStore(directory: folder)
        store.start()
        let recorder = RecordingCoordinator(store: store)
        let visible = screen.visibleFrame
        let corner = RecordingConfig(source: .region(region(on: screen)))
        let wasActive = NSApp.isActive
        var lines: [String] = []

        func start(_ config: RecordingConfig) async throws -> NSPanel {
            await recorder.start(config: config, screen: screen)
            guard recorder.isRecording else { throw Failure(description: "the recording did not start") }
            guard let panel = recorder.playtestControls.playtestPanel, panel.isVisible, panel.alphaValue == 1 else {
                throw Failure(description: "the recording started with no control on screen")
            }
            return panel
        }
        func stop() async throws {
            await recorder.stop()
            guard !recorder.isRecording, recorder.playtestControls.playtestPanel == nil else {
                throw Failure(description: "Stop left the recording or its control up")
            }
        }
        func say(_ frame: CGRect) -> String {
            "\(Int(frame.minX)),\(Int(frame.minY))"
        }
        func expectQuiet(_ panel: NSPanel, after what: String) throws {
            guard !panel.isKeyWindow, NSApp.isActive == wasActive else {
                throw Failure(description: "\(what) took the keyboard or brought the app forward")
            }
            guard recorder.isRecording else { throw Failure(description: "\(what) stopped the recording") }
        }

        // 1. Never moved: bottom left, the glass 16 pt in from both edges.
        var panel = try await start(corner)
        let home = RecordingControlPlacement.frame(spot: nil, visible: visible)
        let inset = RecordingControlPlacement.glassInset
        guard panel.frame == home, panel.frame.minX + inset - visible.minX == 16,
              panel.frame.minY + inset - visible.minY == 16 else {
            throw Failure(description: "the control started at \(say(panel.frame)), not bottom left at \(say(home))")
        }
        lines.append("started bottom left at \(say(home)), the glass 16 pt in")
        await photograph(panel, "recording-control-1-bottom-left")

        // 2. Dragged by the glass between the clock and the button.
        let before = panel.frame
        try await drag(panel, from: emptyPart, by: dragBy)
        let moved = before.offsetBy(dx: dragBy.dx, dy: dragBy.dy)
        guard abs(panel.frame.minX - moved.minX) <= 1, abs(panel.frame.minY - moved.minY) <= 1 else {
            throw Failure(description: "dragging the control by \(Int(dragBy.dx)),\(Int(dragBy.dy)) left it at "
                + "\(say(panel.frame)), not \(say(moved))")
        }
        try expectQuiet(panel, after: "dragging the control")
        guard let spot = RecordingControlSpotStore.spot,
              spot == RecordingControlPlacement.spot(for: panel.frame, visible: visible) else {
            throw Failure(description: "where the control was let go was not remembered")
        }
        let left = panel.frame
        lines.append("dragged to \(say(left)) while recording, remembered as \(spot.corner.rawValue) "
            + "\(Int(spot.fromSide)),\(Int(spot.fromEnd))")
        await photograph(panel, "recording-control-2-dragged")

        // 3. A press on Stop that drags off it moves nothing and stops nothing.
        try await drag(panel, from: stopButton, by: CGVector(dx: -150, dy: 120))
        guard panel.frame == left else {
            throw Failure(description: "a drag that began on Stop moved the control to \(say(panel.frame))")
        }
        try expectQuiet(panel, after: "a drag that began on Stop")
        lines.append("a drag that began on Stop moved nothing and stopped nothing")

        // 4. The next recording puts it back where it was left.
        try await stop()
        panel = try await start(corner)
        guard panel.frame == left else {
            throw Failure(description: "the next recording put the control at \(say(panel.frame)), "
                + "not where it was left at \(say(left))")
        }
        lines.append("the next recording put it back at \(say(left))")
        await photograph(panel, "recording-control-3-came-back")
        try await stop()

        // 5. Recording a region over where it was left keeps it outside.
        let over = left.insetBy(dx: -40, dy: -30)
        let topLeftRegion = CGRect(x: over.minX - screen.frame.minX, y: screen.frame.maxY - over.maxY,
                                   width: over.width, height: over.height)
        panel = try await start(RecordingConfig(source: .region(topLeftRegion)))
        guard !panel.frame.intersects(over), visible.contains(panel.frame) else {
            throw Failure(description: "recording a region over the control left it at \(say(panel.frame)), "
                + "inside the region at \(say(over))")
        }
        lines.append("recording a region over that spot moved it outside to \(say(panel.frame))")
        try await stop()

        // 6. A double click on the glass takes it home and forgets the spot.
        panel = try await start(corner)
        try await doubleClick(panel, at: emptyPart)
        try? await Task.sleep(for: .milliseconds(450))
        guard panel.frame == home, RecordingControlSpotStore.spot == nil else {
            throw Failure(description: "a double click left the control at \(say(panel.frame)), not home at \(say(home))")
        }
        try expectQuiet(panel, after: "a double click on the control")
        lines.append("a double click took it home to \(say(home))")
        await photograph(panel, "recording-control-4-home-again")
        try await stop()
        return lines.joined(separator: " · ")
    }

    private static func event(_ type: NSEvent.EventType, at point: CGPoint, in panel: NSPanel,
                              clicks: Int = 1) throws -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1) else {
            throw Failure(description: "could not make a mouse event")
        }
        return event
    }

    /// Presses at `point` in the control's window, moves the pointer `by` in
    /// a dozen steps, and lets go, the way a hand drags.
    private static func drag(_ panel: NSPanel, from point: CGPoint, by: CGVector) async throws {
        let origin = panel.frame.origin
        let screenStart = CGPoint(x: origin.x + point.x, y: origin.y + point.y)
        func send(_ type: NSEvent.EventType, _ screenPoint: CGPoint) throws {
            RecordingControlsController.playtestPointer = screenPoint
            let local = CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
            panel.sendEvent(try event(type, at: local, in: panel))
        }
        try send(.leftMouseDown, screenStart)
        try? await Task.sleep(for: .milliseconds(30))
        let steps = 12
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            try send(.leftMouseDragged, CGPoint(x: screenStart.x + by.dx * t, y: screenStart.y + by.dy * t))
            try? await Task.sleep(for: .milliseconds(16))
        }
        try send(.leftMouseUp, CGPoint(x: screenStart.x + by.dx, y: screenStart.y + by.dy))
        try? await Task.sleep(for: .milliseconds(100))
    }

    private static func doubleClick(_ panel: NSPanel, at point: CGPoint) async throws {
        RecordingControlsController.playtestPointer = CGPoint(x: panel.frame.minX + point.x,
                                                              y: panel.frame.minY + point.y)
        for clicks in 1...2 {
            panel.sendEvent(try event(.leftMouseDown, at: point, in: panel, clicks: clicks))
            try? await Task.sleep(for: .milliseconds(40))
            panel.sendEvent(try event(.leftMouseUp, at: point, in: panel, clicks: clicks))
            try? await Task.sleep(for: .milliseconds(60))
        }
    }
}
#endif
