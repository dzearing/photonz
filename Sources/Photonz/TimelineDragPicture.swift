import Foundation

// **A file carried over the timeline turns into its ghost** (user 2026-10-28:
// "what i want is for it to morph into a ghost of what it will look like
// dropped"; 2026-10-29: "EITHER OR, not both!!!").
//
// The lanes draw the clip a file would become where it would land
// (`TimelineFileGhost`), and the picture carried under the pointer gives way
// to it while it is up, coming back once the drag leaves the timeline. That
// picture is the app's own (`HistoryDragPicture`): AppKit's could not be
// reached from the app in a real drag, whichever way it was tried.

/// Which editors are drawing a file's ghost on their timeline right now.
@MainActor enum TimelineDragPicture {

    /// Editors with a file ghost up, by identity.
    private static var ghosts: Set<ObjectIdentifier> = []

    /// An editor's ghost came up or went.
    static func ghost(_ shown: Bool, in editor: ObjectIdentifier) {
        if shown { ghosts.insert(editor) } else { ghosts.remove(editor) }
        HistoryDragPicture.give(way: !ghosts.isEmpty)
    }
}
