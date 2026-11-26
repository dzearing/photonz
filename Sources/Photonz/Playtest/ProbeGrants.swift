#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import ScreenCaptureKit

/// What the probe build can and cannot see, written where the shell can read it.
///
/// The unmanned loop screenshots its own copy of the app so an audit carries a
/// real picture of the window instead of an offscreen render, and that needs a
/// Screen Recording grant only a person can give. Nothing in the shell can ask
/// TCC about another app's grant, so the probe answers for itself: at launch it
/// writes `probe-grants.json` beside its own bundle and `Scripts/probe-app.sh`
/// reads it back into the one status line it prints.
///
/// Probe only. The dev build compiles the same code (both are built with
/// PHOTONZ_PLAYTEST) but `fileURL` is nil for it, so a person's app never
/// writes the loop's file and never gets prompted on the loop's behalf. The
/// shipping build has none of this compiled in.
@MainActor
enum ProbeGrants {

    /// `dist/probe-grants.json`, beside "Photonz Probe.app". Nil in any other
    /// flavor, which is what keeps this probe-only.
    static var fileURL: URL? {
        guard AppInfo.flavor == .probe else { return nil }
        return Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("probe-grants.json")
    }

    /// Records the grant, and asks for it at most ONCE EVER when it is missing.
    ///
    /// The preflight never prompts, so the file lands immediately and the shell
    /// is never left waiting. When the answer is no, the request goes through
    /// `PermissionGate`, which lets this probe ask exactly once in its life
    /// (remembered in `probe-permission-asks.json` beside the bundle) and never
    /// again, whatever the answer was. It used to ask once per LAUNCH, on the
    /// belief that macOS asks only while the grant is undetermined; on macOS 26
    /// it asks every time, Deny records nothing, and each dialog waits behind
    /// the one on screen after the probe has quit. The loop launches the probe
    /// for every walk, so on 2026-11-26 the person came back to a stack of
    /// "Photonz Probe would like to record this computer's screen and audio"
    /// and denied a dozen in a row while each next one came straight up.
    static func recordOnLaunch() {
        #if PHOTONZ_PLAYTEST
        if PermissionGate.drill != nil {
            // The drill: the same launch path, read as never granted, with no
            // file written over the real one and no request reaching macOS.
            if !PermissionGate.isGranted(.screenRecording) { ScreenCapturer.askOnce() }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        guard let fileURL else { return }
        let granted = PermissionGate.isGranted(.screenRecording)
        let asked = !granted && ScreenCapturer.askOnce()
        write(granted: granted, prompted: asked, to: fileURL)
    }

    private static func write(granted: Bool, prompted: Bool, to url: URL) {
        let payload: [String: Any] = [
            "screenRecording": granted,
            // A locked screen is not a grant, but it costs the loop the same
            // thing and more: no window is drawn at all, so nothing a walk
            // reads is about the app (`PlaytestScreenState`). It belongs on the
            // same line for the same reason, so nobody claims a look at the app
            // they could not have had.
            "screenLocked": PlaytestScreenState.isLocked,
            "prompted": prompted,
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = SafeJSON.data(from: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }
}
#endif
