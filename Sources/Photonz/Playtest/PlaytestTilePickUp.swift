// Proving a tile really does come away in your hand.
//
// `PlaytestPanelDrag` covers everything that happens once something is in the
// air: it builds the tile's own payload and hands it to the view being dropped
// on. What it never covered is the first half of the gesture — pressing a tile
// and pulling, and a drag being what comes of it. Three features shipped on
// 2026-09-09 rest on that half, and all three audits said the same thing: no
// walk can prove it, please check by hand.
//
// This settles it. A press and a pull are posted at the tile, and the moment
// AppKit is asked to start a drag session is caught on its way past, with the
// payload it was asked to carry. AppKit has more than one door for that ask:
// up to macOS 26 SwiftUI used `beginDraggingSession(with:event:source:)`; from
// macOS 27 a tile is lifted by SwiftUI's own `DragLiftGestureRecognizer`, which
// asks through `beginDraggingSessionWithItems:gesture:source:` (not in any SDK
// header yet). Every door is watched, because watching one was how all four
// pick up walks read "nothing asked to start a drag" from the day the Mac was
// updated to 27.0.1 (2026-10-25), while SwiftUI was asking all along.
//
// That is the question the audits asked: does this tile have a handle, and
// does pulling on it put the right thing in the air.
//
// The session itself is then not allowed to start. A real one takes the main
// thread hostage in a loop of its own that only a mouse coming up on a real
// desk can end, and a walk has no desk. So the ask is caught, written down,
// and refused: what a walk proves is that the tile was picked up, not that the
// window server then drew a picture under the pointer, which is AppKit's
// business rather than this app's. Refusing also keeps the step from changing
// the document, because nothing is ever let go of.
//
// ONE PICK UP PER RUN OF THE APP. After a refused session SwiftUI will not
// start another, and nothing tried so far puts it back: a plain click in
// between, ending the session by hand through its source, giving every posted
// event its own number, even letting the real session run. The first tile in a
// walk comes away and every tile after it, the same tile included, stays on the
// shelf. A walk that needs to prove two tiles is two walks. That is written
// down here and said out loud by the step, because for an afternoon it looked
// exactly like a broken text style tile.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import ObjectiveC

/// One moment a view asked AppKit to start dragging something.
struct PlaytestDragAsk: Sendable {
    /// The class of the view the drag came off, for the log.
    let view: String
    /// How many things were picked up at once.
    let items: Int
    /// Every type the payload offers, which is what the drop side reads.
    let types: [String]
}

/// Catches the moment a drag session is asked for, and refuses to let it start.
@MainActor
enum PlaytestDragWatch {
    private static var installed = false
    private(set) static var asks: [PlaytestDragAsk] = []
    /// True only between `start()` and `stop()`, so the app drags normally for
    /// the person using it and only a walk ever sees a session refused.
    private(set) static var isWatching = false
    /// Whether anything has been caught at all since the app started. A pick up
    /// that catches nothing means one of two very different things, and this is
    /// how the step tells them apart: the FIRST one catching nothing is a tile
    /// with no handle, and a later one catching nothing is the one-per-run
    /// limit at the top of this file.
    private(set) static var hasCaughtAnything = false

    /// Begin watching. Everything caught from here until `stop()` is returned
    /// by it.
    static func start() {
        install()
        asks = []
        isWatching = true
    }

    /// Stop watching and hand back everything caught.
    static func stop() -> [PlaytestDragAsk] {
        isWatching = false
        let caught = asks
        asks = []
        return caught
    }

    static func record(view: NSView, items: [NSDraggingItem]) {
        var types: [String] = []
        for item in items {
            if let board = item.item as? NSPasteboardWriting {
                types += board.writableTypes(for: NSPasteboard.general).map(\.rawValue)
            } else if let provider = item.item as? NSItemProvider {
                types += provider.registeredTypeIdentifiers
            }
        }
        hasCaughtAnything = true
        asks.append(PlaytestDragAsk(
            view: String(describing: type(of: view)),
            items: items.count,
            types: NSOrderedSet(array: types).compactMap { $0 as? String }))
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        // Every door AppKit has for starting a drag. Up to macOS 26 SwiftUI
        // went through the first, with the mouse event that crossed the drag
        // threshold. From macOS 27 it lifts a tile with a gesture recogniser of
        // its own and goes through the second, which takes that recogniser in
        // place of an event and is in no SDK header yet: watching only the
        // first, every pick up read as a tile with no handle from the day the
        // Mac was updated (2026-10-25). The window's own door (macOS 15) is
        // watched too, so no way in is left unseen.
        exchange(NSView.self, "beginDraggingSessionWithItems:event:source:",
                 "photonzPlaytestBeginDraggingSessionWithItems:event:source:")
        exchange(NSView.self, "beginDraggingSessionWithItems:gesture:source:",
                 "photonzPlaytestBeginDraggingSessionWithItems:gesture:source:")
        exchange(NSWindow.self, "beginDraggingSessionWithItems:event:source:",
                 "photonzPlaytestWindowBeginDraggingSessionWithItems:event:source:")
    }

    /// Swaps one door for its stand-in. A door this Mac's AppKit does not have
    /// (the gesture one before macOS 27) is left alone.
    private static func exchange(_ cls: AnyClass, _ original: String, _ replacement: String) {
        guard let from = class_getInstanceMethod(cls, NSSelectorFromString(original)),
              let to = class_getInstanceMethod(cls, NSSelectorFromString(replacement)) else { return }
        method_exchangeImplementations(from, to)
    }
}

extension NSView {
    /// Stands in for `beginDraggingSession(with:event:source:)` while a walk is
    /// watching. After the swap, calling this name calls the real one.
    @objc(photonzPlaytestBeginDraggingSessionWithItems:event:source:)
    func photonzPlaytestBeginDraggingSession(with items: [NSDraggingItem], event: NSEvent,
                                             source: NSDraggingSource) -> NSDraggingSession {
        guard MainActor.assumeIsolated({ PlaytestDragWatch.isWatching }) else {
            return photonzPlaytestBeginDraggingSession(with: items, event: event, source: source)
        }
        MainActor.assumeIsolated { PlaytestDragWatch.record(view: self, items: items) }
        // The ask is the answer, so the real call is never made. The empty
        // session handed back in its place is dropped on the floor by
        // everything that asks for one.
        return NSDraggingSession()
    }

    /// Stands in for macOS 27's `beginDraggingSessionWithItems:gesture:source:`,
    /// the door a SwiftUI drag lifted by its own recogniser goes through.
    @objc(photonzPlaytestBeginDraggingSessionWithItems:gesture:source:)
    func photonzPlaytestBeginDraggingSession(with items: [NSDraggingItem], gesture: NSGestureRecognizer,
                                             source: NSDraggingSource) -> NSDraggingSession {
        guard MainActor.assumeIsolated({ PlaytestDragWatch.isWatching }) else {
            return photonzPlaytestBeginDraggingSession(with: items, gesture: gesture, source: source)
        }
        MainActor.assumeIsolated { PlaytestDragWatch.record(view: self, items: items) }
        return NSDraggingSession()
    }
}

extension NSWindow {
    /// Stands in for the window's own `beginDraggingSession(items:event:source:)`.
    @objc(photonzPlaytestWindowBeginDraggingSessionWithItems:event:source:)
    func photonzPlaytestBeginDraggingSession(items: [NSDraggingItem], event: NSEvent,
                                             source: NSDraggingSource) -> NSDraggingSession {
        guard MainActor.assumeIsolated({ PlaytestDragWatch.isWatching }) else {
            return photonzPlaytestBeginDraggingSession(items: items, event: event, source: source)
        }
        MainActor.assumeIsolated {
            PlaytestDragWatch.record(view: self.contentView ?? NSView(), items: items)
        }
        return NSDraggingSession()
    }
}
#endif
