import PhotonzCore
import SwiftUI

/// What the **Next** release puts on screen: the next-generation Photonz.
///
/// This file started as a copy of `CurrentExperience`, which is the shape every
/// fork takes. Both releases still open the same shared editor, so nothing here
/// diverges yet.
///
/// To make Next different, fork the file: copy it into this folder, rename the
/// type with a `Next` prefix (one module, so names must stay unique), and point
/// the factory below at the copy. Everything Next has not forked keeps coming
/// from the shared code, which is how Current's fixes keep reaching Next for
/// free.
///
/// Nothing in this folder is ever back-ported to Current. Next reaches people
/// by being promoted, not by leaking.
@MainActor
enum NextExperience {
    @ViewBuilder
    static func imageEditor(windowID: EditorWindowID?) -> some View {
        ImageEditorRootView(windowID: windowID)
    }

    @ViewBuilder
    static func videoEditor(url: URL) -> some View {
        VideoEditorRootView(url: url)
    }
}
