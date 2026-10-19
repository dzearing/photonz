// The panel's look sections watch only what they can show
// (task `keying-a-value-redraws-only-what-the-key-changes`).

import PhotonzCore
import SwiftUI

/// Builds a look section's body so that the document it reads tells it about
/// a change only when the change is one it could show.
///
/// Every view that reads `editorState.document` is rebuilt whenever ANY part of
/// the document changes, because the document is one value. Picking Position
/// from Animate a property writes one key, and Text, Appearance, Effects and
/// Time were all built again for it, with everything under them measured
/// again: about a fifth of the pick, and more of an undo. None of them shows a
/// key on where a layer is. They show the layers as they are, and the look
/// values (opacity, a shadow's distance) at the playhead, which
/// `PhotonzDocument.sameApartFromPlacementKeys` still counts.
///
/// So inside `build` every read of the document returns the document as it
/// is now, never an old copy, and what the view is told to watch is
/// `EditorState.lookRowsRevision`, which moves on for everything except a
/// placement key. Anything else the body reads (the selection, the playhead)
/// is watched exactly as before.
///
/// The rule for using it: only in a view that shows nothing a key on Position,
/// Scale, Rotation or a crop decides. Such a view would go on showing the
/// value from before the key. The Properties section and the timeline are
/// exactly those views, and do not use it.
///
/// A closure SwiftUI runs later (a `ForEach` row, a menu's items) runs outside
/// this and watches the whole document as usual, which costs a rebuild and is
/// never wrong.
@MainActor
func readingForTheLookRows<Content>(_ build: () -> Content) -> Content {
    let was = EditorState.readsForTheLookRows
    EditorState.readsForTheLookRows = true
    defer { EditorState.readsForTheLookRows = was }
    return build()
}

/// Reads the document as it is, and is told it changed by
/// `EditorState.latePassRevision`, which moves on with every change except
/// that an edit marked by `EditorState.catchUpOnTheNextPass` reaches it in
/// the next pass (`NextRunLoopPass`). So for every other edit a read in here is
/// watched exactly as one outside it, and for that one edit what it builds
/// follows a frame after the picture.
@MainActor
func readingALatePass<Content>(_ build: () -> Content) -> Content {
    let was = EditorState.readsALatePass
    EditorState.readsALatePass = true
    defer { EditorState.readsALatePass = was }
    return build()
}

/// `readingALatePass` for a view built in a closure SwiftUI runs later (a
/// `GeometryReader`'s, a `ScrollView`'s), which runs outside the body that
/// wrapped it.
@MainActor
func buildingALatePass<Content: View>(@ViewBuilder _ build: () -> Content) -> Content {
    readingALatePass(build)
}
