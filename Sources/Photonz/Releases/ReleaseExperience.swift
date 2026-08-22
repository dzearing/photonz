import PhotonzCore
import SwiftUI

/// The seam between the app and the release it is running.
///
/// Every surface a release can own is asked for here, so the app has exactly
/// ONE switch over `Release` and each release folder owns everything else. A
/// window opened while Current is running is built by `CurrentExperience`; the
/// same window under Next is built by `NextExperience`.
///
/// Adding a surface the releases can differ on: add a factory here, give every
/// release folder its version, and call it from the app. See
/// `Sources/Photonz/Releases/README.md` for how a file forks.
@MainActor
enum ReleaseExperience {
    /// The root of an image editor window.
    @ViewBuilder
    static func imageEditor(windowID: EditorWindowID?) -> some View {
        switch Experiments.shared.release {
        case .current: CurrentExperience.imageEditor(windowID: windowID)
        case .next: NextExperience.imageEditor(windowID: windowID)
        }
    }

    /// The root of a recording (video) editor window.
    @ViewBuilder
    static func videoEditor(url: URL) -> some View {
        switch Experiments.shared.release {
        case .current: CurrentExperience.videoEditor(url: url)
        case .next: NextExperience.videoEditor(url: url)
        }
    }
}
