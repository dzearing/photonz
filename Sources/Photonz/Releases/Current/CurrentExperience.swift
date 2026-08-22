import PhotonzCore
import SwiftUI

/// What the **Current** release puts on screen: the Photonz everyone gets.
///
/// Today every surface is the shared one, unchanged. This folder is where
/// Current-only code goes if Current ever needs to differ from what Next and
/// Legacy share.
///
/// Anything that changes here has to reach Next too. While a file is shared,
/// that happens by itself; once Next has forked its own copy, the change is
/// yours to carry across by hand. A Current change is not finished until Next
/// has it (see `Sources/Photonz/Releases/README.md`).
@MainActor
enum CurrentExperience {
    @ViewBuilder
    static func imageEditor(windowID: EditorWindowID?) -> some View {
        ImageEditorRootView(windowID: windowID)
    }

    @ViewBuilder
    static func videoEditor(url: URL) -> some View {
        VideoEditorRootView(url: url)
    }
}
