import Foundation

/// Which flavor of Photonz this process is. Dev builds ship as
/// "Photonz Dev.app" with their own bundle id (`com.dzearing.photonz.dev` —
/// see Scripts/build-app.sh) so they hold separate TCC grants, defaults, and
/// LaunchServices identity and can run side by side with the installed
/// release app. User-facing strings must use `name` so the two are
/// distinguishable while both are running.
enum AppInfo {
    /// "Photonz" for release builds, "Photonz (Dev)" for dev bundles, and the
    /// fallback covers bare `swift build` runs with no bundle at all.
    static let name =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Photonz (Dev)"

    static let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true
}
