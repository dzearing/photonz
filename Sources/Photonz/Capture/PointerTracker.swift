import AppKit
import CoreMedia
import PhotonzCore

/// Takes down where the pointer goes and every click while a recording runs
/// (`PointerTrack.swift`), so the recording can be given click rings and a
/// zoom that follows the mouse afterwards.
///
/// Asks for nothing: watching the mouse in other apps needs no permission on
/// macOS (only the keyboard does), so there is no prompt and a recording never
/// depends on it. Cheap enough to never slow a recording: one read of the
/// pointer per frame on the main run loop, and a monitor that hears presses
/// and releases as they happen.
///
/// Every time is on the host clock, the clock `NSEvent` timestamps and a
/// screen stream's frames are both stamped with, so a click is counted from
/// the recording's first frame rather than from when Start was pressed.
@MainActor
final class PointerTracker {
    private var take: PointerTrackRecording?
    private var monitors: [Any] = []
    private var timer: Timer?

    /// Where the pointer is now, in global screen points. The probe's walk
    /// replaces it with the point it is scripting, since a walk never moves
    /// the person's own pointer.
    var position: () -> CGPoint = { NSEvent.mouseLocation }

    /// Seconds on the host clock.
    static func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    var isTracking: Bool { take != nil }

    func start(space: PointerSpace, framesPerSecond: Double = 60) {
        stop()
        take = PointerTrackRecording(space: space)
        sample()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                           .otherMouseDown, .otherMouseUp]
        // Presses in other apps...
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.hear(event) }
        }) { monitors.append(global) }
        // ...and in this one (a global monitor never hears its own app).
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.hear(event) }
            return event
        }) { monitors.append(local) }
        let timer = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Common modes, so a menu held open or a window being dragged does
        // not stop the pointer being followed.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stop listening and hand back what was taken down.
    @discardableResult
    func stop() -> PointerTrackRecording? {
        timer?.invalidate()
        timer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        defer { take = nil }
        return take
    }

    private func sample() {
        take?.move(to: position(), atHostSeconds: Self.hostNow())
    }

    private func hear(_ event: NSEvent) {
        // A press in another app has no window and comes in screen points; a
        // press in this one is in its window's points.
        let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        let button: PointerButton
        switch event.type {
        case .leftMouseDown, .leftMouseUp: button = .left
        case .rightMouseDown, .rightMouseUp: button = .right
        default: button = .other
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            press(button, at: point, hostSeconds: event.timestamp)
        default:
            release(button, at: point, hostSeconds: event.timestamp)
        }
    }

    /// The one way a press is taken down, from the OS or from the probe's walk.
    func press(_ button: PointerButton, at screenPoint: CGPoint, hostSeconds: Double) {
        take?.move(to: screenPoint, atHostSeconds: hostSeconds)
        take?.press(button, at: screenPoint, atHostSeconds: hostSeconds)
    }

    func release(_ button: PointerButton, at screenPoint: CGPoint, hostSeconds: Double) {
        take?.release(button, at: screenPoint, atHostSeconds: hostSeconds)
    }
}
