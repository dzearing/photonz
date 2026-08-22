import AppKit

/// Quits and reopens the app bundle. Used by the Welcome window (a Screen
/// Recording grant only takes effect in a fresh process) and by Experiments
/// (switching release takes effect at launch).
///
/// Nothing to relaunch from a bare `swift build` binary — those runs have no
/// bundle — so it just quits there.
enum AppRelauncher {
    /// True when this build can actually reopen itself.
    static var canRelaunch: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        if canRelaunch {
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
            relauncher.arguments = ["-c", "sleep 0.4; /usr/bin/open \"\(bundlePath)\""]
            try? relauncher.run()
        }
        NSApp.terminate(nil)
    }
}
