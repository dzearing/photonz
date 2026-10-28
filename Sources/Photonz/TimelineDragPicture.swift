import AppKit
import SwiftUI

// **A History tile turns into its ghost over the timeline** (user 2026-10-28:
// "what i want is for it to morph into a ghost of what it will look like
// dropped").
//
// A tile pulled out of History is carried by a picture of the tile. Over the
// timeline the lanes draw the clip it would become, where it would land
// (`TimelineFileGhost`), and the tile's picture went on following the pointer
// over the top of it: two pictures of one thing, the bigger one in the way.
// So while a ghost is up the picture on the pointer goes, and the ghost is
// what is being carried; carried off the timeline again, the picture comes
// back.
//
// Only the drag's own session can change that picture once a drag has begun,
// and a drop target is never handed it. The view a drag is started from is:
// AppKit hands the session back from `beginDraggingSession`, so the History
// strip is hosted in a view that keeps it (`GhostingDragHostingView`), and the
// picture is changed the moment a ghost comes up or goes.

/// The drag in the air out of History, and which editors are drawing a file's
/// ghost on their timeline right now.
@MainActor enum TimelineDragPicture {

    /// Editors with a file ghost up, by identity.
    private static var ghosts: Set<ObjectIdentifier> = []

    /// The drag a History tile started, while it is in the air.
    private static var session: NSDraggingSession?

    /// What its picture was, item by item, while it is put away.
    private static var kept: [Int: [NSDraggingImageComponent]]?

    /// A drag began off a History tile.
    static func began(_ dragging: NSDraggingSession) {
        session = dragging
        kept = nil
        refresh()
    }

    /// An editor's ghost came up or went.
    static func ghost(_ shown: Bool, in editor: ObjectIdentifier) {
        if shown { ghosts.insert(editor) } else { ghosts.remove(editor) }
        refresh()
    }

    /// The picture goes while a ghost is up and comes back when it is not.
    private static func refresh() {
        guard let session else { return }
        let hide = !ghosts.isEmpty
        guard hide != (kept != nil) else { return }
        var items: [(NSDraggingItem, Int)] = []
        session.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self],
                                       searchOptions: [:]) { item, index, _ in
            items.append((item, index))
        }
        if hide {
            var pictures: [Int: [NSDraggingImageComponent]] = [:]
            for (item, index) in items {
                pictures[index] = item.imageComponents ?? []
                item.imageComponentsProvider = { [] }
            }
            kept = pictures
        } else {
            let pictures = kept ?? [:]
            for (item, index) in items {
                let picture = pictures[index] ?? []
                item.imageComponentsProvider = { picture }
            }
            kept = nil
        }
    }
}

/// A hosting view whose drags hand their picture over to the timeline's
/// ghost (`TimelineDragPicture`). What the History strip is hosted in.
final class GhostingDragHostingView<Content: View>: NSHostingView<Content> {
    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent,
                                       source: any NSDraggingSource) -> NSDraggingSession {
        let session = super.beginDraggingSession(with: items, event: event, source: source)
        TimelineDragPicture.began(session)
        return session
    }
}
