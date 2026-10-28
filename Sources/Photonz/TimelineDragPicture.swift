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
// Only the drag's SOURCE can change that picture once a drag has begun, and
// the source of a SwiftUI drag is the hosting view it started in, whose own
// dragging methods are not open to override. Every specialisation of
// `NSHostingView` is an Objective-C class of its own, though, so the strip's
// host is a subclass that adds its own "moved to" at run time, calls the one
// SwiftUI wrote and then looks at the timeline. Nothing outside that one
// subclass is touched.

/// Which editors are drawing a file's ghost on their timeline right now, and
/// the picture each drag in the air was carrying before it was taken away.
@MainActor enum TimelineDragPicture {

    /// Editors with a file ghost up, by identity.
    private static var ghosts: Set<ObjectIdentifier> = []

    /// The drag whose picture is put away, and what it was, item by item.
    private static var session: ObjectIdentifier?
    private static var kept: [Int: [NSDraggingImageComponent]] = [:]

    /// An editor's ghost came up or went.
    static func ghost(_ shown: Bool, in editor: ObjectIdentifier) {
        if shown { ghosts.insert(editor) } else { ghosts.remove(editor) }
    }

    static var isGhostUp: Bool { !ghosts.isEmpty }

    /// The drag moved: its picture goes while a ghost is up and comes back
    /// when it is not. Free when nothing changed, since it runs on every move.
    static func follow(_ dragging: NSDraggingSession) {
        let id = ObjectIdentifier(dragging)
        if session != id {
            guard isGhostUp else { return }
            session = id
            kept = [:]
        }
        let hide = isGhostUp
        guard hide == kept.isEmpty else { return }
        var items: [(NSDraggingItem, Int)] = []
        dragging.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self],
                                        searchOptions: [:]) { item, index, _ in
            items.append((item, index))
        }
        if hide {
            for (item, index) in items {
                kept[index] = item.imageComponents ?? []
                item.imageComponentsProvider = { [] }
            }
        } else {
            for (item, index) in items {
                let picture = kept[index] ?? []
                item.imageComponentsProvider = { picture }
            }
            kept = [:]
            session = nil
        }
    }
}

/// A hosting view whose drags hand their picture over to the timeline's
/// ghost (`TimelineDragPicture`). What the History strip is hosted in.
final class GhostingDragHostingView<Content: View>: NSHostingView<Content> {

    required init(rootView: Content) {
        Self.followDrags()
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Adds "moved to" to this class, once: SwiftUI's, then a look at the
    /// timeline.
    private static func followDrags() {
        let cls: AnyClass = self
        let selector = #selector(NSDraggingSource.draggingSession(_:movedTo:))
        guard !TimelineDragFollowers.added.contains(ObjectIdentifier(cls)),
              let parent = class_getSuperclass(cls),
              let method = class_getInstanceMethod(parent, selector) else { return }
        TimelineDragFollowers.added.insert(ObjectIdentifier(cls))
        typealias MovedTo = @convention(c) (AnyObject, Selector, NSDraggingSession, NSPoint) -> Void
        let swiftUIs = unsafeBitCast(method_getImplementation(method), to: MovedTo.self)
        let moved: @convention(block) (AnyObject, NSDraggingSession, NSPoint) -> Void = { view, dragging, point in
            swiftUIs(view, selector, dragging, point)
            MainActor.assumeIsolated { TimelineDragPicture.follow(dragging) }
        }
        class_addMethod(cls, selector, imp_implementationWithBlock(moved), method_getTypeEncoding(method))
    }
}

/// The hosting classes that already follow their drags.
@MainActor private enum TimelineDragFollowers {
    static var added: Set<ObjectIdentifier> = []
}
