import AppKit
import ScreenCaptureKit

/// One-shot screen captures via ScreenCaptureKit.
/// Requires the Screen Recording permission (TCC); callers check/request first.
@MainActor
enum ScreenCapturer {

    static var hasPermission: Bool {
        #if PHOTONZ_PLAYTEST
        if let pretended = playtestPretendedPermission { return pretended }
        #endif
        return CGPreflightScreenCaptureAccess()
    }

    #if PHOTONZ_PLAYTEST
    /// What a walk has told the app to read the Screen Recording grant as, or
    /// nil to read the real one. Nothing about macOS is touched: this is the
    /// app's own answer to "may I capture", and it exists because the probe
    /// machine granted the screen long ago, so without it no walk could ever
    /// stand where the person who only wants to draw icons stands.
    /// Probe builds only (`PHOTONZ_PLAYTEST`), never in a release.
    static var playtestPretendedPermission: Bool?
    #endif

    /// The Screen Recording grant is missing, so nothing was captured. Every
    /// capture throws this rather than touching ScreenCaptureKit without the
    /// grant: on macOS 15 and later any such call queues the system's request
    /// dialog, so a capture would ask behind `PermissionGate`'s back.
    struct NotGranted: Error {}

    /// Throws `NotGranted` unless the real grant is there. Reads macOS, never asks.
    static func requireGrant() throws {
        guard PermissionGate.isGranted(.screenRecording) else { throw NotGranted() }
    }

    /// Gets Photonz listed under System Settings → Privacy & Security → Screen &
    /// System Audio Recording and surfaces the request, when `PermissionGate`
    /// says it may (never when granted; once per launch for a person; once
    /// ever for the loop's probe).
    ///
    /// One ScreenCaptureKit query does both: it is what lists a client in that
    /// pane, and without the grant it puts up the request. It used to be preceded
    /// by `CGRequestScreenCaptureAccess`, which on macOS 26 queues a SECOND
    /// identical dialog behind the first (seen 2026-11-26), so a person had two
    /// Denies to give for one question. The query throws until access is
    /// granted; that is expected, the side effect is the point.
    static func primePermissionRegistration() async {
        guard PermissionGate.mayAsk(.screenRecording) else { return }
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// `primePermissionRegistration` without waiting for it: starts the
    /// request when `PermissionGate` allows it and says whether it did.
    @discardableResult
    static func askOnce() -> Bool {
        guard PermissionGate.mayAsk(.screenRecording) else { return false }
        Task { _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        return true
    }

    /// Opens the Screen Recording pane in System Settings so the user can grant
    /// access (and see Photonz listed) without hunting through the panes.
    static func openScreenRecordingSettings() {
        guard PermissionGate.mayOpenSettings else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures one screen. `sourceRect` is in the screen's own coordinate
    /// space, points, top-left origin (i.e. exactly what a flipped overlay
    /// view covering the screen reports); nil captures the whole screen.
    ///
    /// Uses the WYSIWYG `captureImage(in:)` API, NOT the
    /// `captureImage(contentFilter:configuration:)` one: the filter-based call
    /// re-composites windows from their individual buffers and synthesizes no
    /// window shadows at all (verified 2026-07-03 against `screencapture`:
    /// filter path Δ0 luma under every window edge, WYSIWYG path matches the
    /// system exactly), so frozen modals/windows looked pasted-on. The WYSIWYG
    /// call includes shadows, omits the cursor, and returns native backing scale.
    static func capture(screen: NSScreen, sourceRect: CGRect? = nil) async throws -> CGImage {
        try requireGrant()
        let local = sourceRect ?? CGRect(origin: .zero, size: screen.frame.size)
        return try await SCScreenshotManager.captureImage(in: cgGlobalRect(for: local, on: screen))
    }

    /// Captures one screen with `excluded` (our own overlay panels) left out of
    /// the shot, and NOTHING else changed about the screen.
    ///
    /// This exists so the capture overlay never has to hide itself. The other
    /// way to keep our own dim out of the freeze is `sharingType = .none` on the
    /// overlay, but a window marked that way is invisible to EVERY capture, not
    /// just ours: a screen recording running beside us, or a shared screen, sees
    /// no dim at all for as long as the overlay stays hidden. Naming the windows
    /// in a filter keeps them out of our shot only.
    ///
    /// Falls back to nothing: a caller that cannot get this image keeps the dim
    /// over the live screen rather than freezing a picture with its own dim
    /// baked in, which is why this throws instead of degrading to `capture(screen:)`.
    static func capture(screen: NSScreen, excludingWindowNumbers excluded: Set<Int>) async throws -> CGImage {
        try requireGrant()
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { throw CocoaError(.fileNoSuchFile) }

        // The caller's windows went on screen a moment ago and the shareable
        // window list catches up a beat later, so ask again rather than shoot
        // early: every one of them has to be findable, or the shot would
        // photograph the one we missed and the frozen picture would come back
        // with our own dim in it.
        var display: SCDisplay?
        var excludedWindows: [SCWindow] = []
        let deadline = Date().addingTimeInterval(0.3)
        repeat {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            display = content.displays.first { $0.displayID == screenNumber.uint32Value }
            excludedWindows = content.windows.filter { excluded.contains(Int($0.windowID)) }
            if display != nil && excludedWindows.count == excluded.count { break }
            try? await Task.sleep(for: .milliseconds(10))
        } while Date() < deadline
        guard let display, excludedWindows.count == excluded.count else {
            throw CocoaError(.fileNoSuchFile)
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        // Window shadows are part of what a screenshot of a screen looks like.
        config.ignoreShadows = false
        config.dynamicRange = .sdr
        config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter,
                                                                     configuration: config)
        guard let image = output.sdrImage else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    /// Converts a screen-local, top-left-origin points rect to the CG global
    /// (primary-display top-left origin, y-down) space `captureImage(in:)` expects.
    private static func cgGlobalRect(for local: CGRect, on screen: NSScreen) -> CGRect {
        // NSScreen frames are global Cocoa coords (primary bottom-left origin,
        // y-up); screens[0] is always the primary. X is shared between spaces.
        let primaryMaxY = NSScreen.screens[0].frame.maxY
        return CGRect(x: screen.frame.minX + local.minX,
                      y: (primaryMaxY - screen.frame.maxY) + local.minY,
                      width: local.width,
                      height: local.height)
    }

    /// Captures one window on its own, the way the built-in window capture
    /// does: rendered by the window server from the window's own buffer, so
    /// the rounded corners are transparent and nothing in front of or behind
    /// the window is in the shot. With the shadow, the image is larger than
    /// the window and the margin around it is transparent. The window is
    /// captured whole even where it hangs off the display. Throws when the
    /// window is no longer on screen or the capture fails; the caller falls
    /// back to the frozen crop.
    static func captureWindow(id: Int, includeShadow: Bool) async throws -> CGImage {
        try requireGrant()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { Int($0.windowID) == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        config.ignoreShadows = !includeShadow
        config.ignoreClipping = true
        config.dynamicRange = .sdr
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        guard let image = output.sdrImage else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    /// Captures every attached screen (system ⇧⌘3 behavior: one image per display).
    static func captureAllScreens() async throws -> [DisplayShot] {
        var shots: [DisplayShot] = []
        for screen in NSScreen.screens {
            shots.append(DisplayShot(image: try await capture(screen: screen),
                                     scale: screen.backingScaleFactor, frame: screen.frame))
        }
        return shots
    }

    /// One display's picture from a full screen capture, and where that display
    /// is, so the one under the pointer can be picked out of them.
    struct DisplayShot: @unchecked Sendable { // CGImage is immutable
        let image: CGImage
        let scale: CGFloat
        let frame: CGRect
    }
}
