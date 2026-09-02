#if PHOTONZ_PLAYTEST
import AppKit
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

    /// Records the grant, and asks for it at most once per launch when it is
    /// still undetermined.
    ///
    /// The preflight never prompts, so the file lands immediately and the shell
    /// is never left waiting. Only when the answer is no does the probe issue
    /// the real request, and it does that off the launch path: a
    /// ScreenCaptureKit query is what gets the probe listed in System Settings
    /// at all, and `CGRequestScreenCaptureAccess` raises the dialog only while
    /// the grant is undetermined. Once a person has answered, granted or
    /// denied, both return the standing answer in silence, so relaunching the
    /// probe all day can never turn into a prompt loop (the rule CaptureCenter
    /// already follows, learned the hard way on 2026-07-07).
    static func recordOnLaunch() {
        guard let fileURL else { return }
        let granted = CGPreflightScreenCaptureAccess()
        write(granted: granted, prompted: !granted, to: fileURL)
        guard !granted else { return }
        Task { await ScreenCapturer.primePermissionRegistration() }
    }

    private static func write(granted: Bool, prompted: Bool, to url: URL) {
        let payload: [String: Any] = [
            "screenRecording": granted,
            "prompted": prompted,
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }
}
#endif
