import AppKit
import PhotonzCore

/// Asks `CaptureShortcutOwner` whether THIS copy of Photonz answers the
/// system-wide capture shortcuts, from the copies running right now.
///
/// A running copy built knowing the rule says so in its Info.plist
/// (`stepAsideKey`, written by Scripts/build-app.sh). One without it, such as
/// the 0.21.0 that was answering beside Photonz Dev on 2026-11-03, will answer
/// whatever happens, so the rule leaves the shortcuts to it rather than make
/// two answers.
@MainActor
enum CaptureShortcutClaim {
    /// The Info.plist key a build that steps aside carries.
    static let stepAsideKey = "PhotonzCaptureShortcutsStepAside"

    /// Every bundle id Photonz ships under, the probe included.
    static func isPhotonz(_ bundleID: String) -> Bool {
        bundleID == "com.dzearing.photonz" || bundleID.hasPrefix("com.dzearing.photonz.")
    }

    /// Whether this copy answers the shortcuts now.
    static func isOurs() -> Bool {
        let me = NSRunningApplication.current
        let mine = CaptureShortcutOwner.Instance(
            pid: me.processIdentifier, flavor: AppInfo.flavor, launched: me.launchDate, stepsAside: true)
        let others = NSWorkspace.shared.runningApplications.compactMap { app -> CaptureShortcutOwner.Instance? in
            guard let id = app.bundleIdentifier, isPhotonz(id), !app.isTerminated,
                  app.processIdentifier != me.processIdentifier else { return nil }
            return CaptureShortcutOwner.Instance(
                pid: app.processIdentifier, flavor: AppFlavor(bundleIdentifier: id),
                launched: app.launchDate, stepsAside: stepsAside(app))
        }
        return CaptureShortcutOwner.holds(mine, among: others)
    }

    /// Read from the bundle on disk. An update that replaced the bundle under
    /// a copy still running reads as the new build; it is relaunched straight
    /// after, which is when it starts answering by the rule.
    private static func stepsAside(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return false }
        return (info[stepAsideKey] as? Bool) ?? false
    }
}
