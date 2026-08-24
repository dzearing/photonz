import Foundation
import PhotonzCore

/// Which flavor of Photonz this process is. Every non-release build ships with
/// its own bundle id (`com.dzearing.photonz.dev`, `.probe` — see
/// Scripts/build-app.sh) so each holds separate TCC grants, defaults, and
/// LaunchServices identity and they run side by side with the installed
/// release app. User-facing strings must use `name` so whichever ones are
/// running at once stay distinguishable.
enum AppInfo {
    /// The plain product name, with any build-flavor suffix stripped. The
    /// fallback covers bare `swift build` runs with no bundle at all.
    static let baseName = AppNaming.baseName(fromBundleName:
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Photonz (Dev)")

    /// Release, the dev build a person works in, or the probe build the
    /// unmanned task loop launches to check itself.
    static let flavor = AppFlavor(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// Anything that is not the shipping build. Probe counts: it must no more
    /// self-update than a dev build does.
    static let isDevBuild = !flavor.isShipping

    /// The app's user-facing name, which follows the release you're running:
    /// "Photonz", "Photonz Next", and local builds keep their "(Dev)" or
    /// "(Probe)" on the end. Fixed for the life of the process, since
    /// switching release relaunches.
    @MainActor static var name: String {
        AppNaming.appName(base: baseName, release: Experiments.shared.release, flavor: flavor)
    }
}
