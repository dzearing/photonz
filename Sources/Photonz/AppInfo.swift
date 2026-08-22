import Foundation
import PhotonzCore

/// Which flavor of Photonz this process is. Dev builds ship as
/// "Photonz Dev.app" with their own bundle id (`com.dzearing.photonz.dev` —
/// see Scripts/build-app.sh) so they hold separate TCC grants, defaults, and
/// LaunchServices identity and can run side by side with the installed
/// release app. User-facing strings must use `name` so the two are
/// distinguishable while both are running.
enum AppInfo {
    /// The plain product name, with any build-flavor suffix stripped. The
    /// fallback covers bare `swift build` runs with no bundle at all.
    static let baseName = AppNaming.baseName(fromBundleName:
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Photonz (Dev)")

    static let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? true

    /// The app's user-facing name, which follows the release you're running:
    /// "Photonz", "Photonz Next", and dev builds keep their "(Dev)" on the end.
    /// Fixed for the life of the process, since switching release relaunches.
    @MainActor static var name: String {
        AppNaming.appName(base: baseName, release: Experiments.shared.release, isDevBuild: isDevBuild)
    }
}
